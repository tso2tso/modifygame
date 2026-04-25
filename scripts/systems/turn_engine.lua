-- ============================================================================
-- 回合引擎：管理结算→事件→行动→回合结束的完整流程
-- ============================================================================

local Balance = require("data.balance")
local Config = require("config")
local GameState = require("game_state")
local Economy = require("systems.economy")
local Events = require("systems.events")
local StockEngine = require("systems.stock_engine")
local Combat = require("systems.combat")
local Tech = require("systems.tech")

local BV = Balance.VICTORY

local TurnEngine = {}

local function PickAIExpansionRegion(state, faction)
    local bestRegion = nil
    local bestScore = -math.huge
    for _, r in ipairs(state.regions or {}) do
        if r.ai_presence and r.ai_presence[faction.id] ~= nil then
            local presence = r.ai_presence[faction.id] or 0
            local control = r.control or 0
            local resourceScore = 0
            if r.type == "mine" then resourceScore = resourceScore + 20 end
            if r.type == "industrial" then resourceScore = resourceScore + 16 end
            if r.type == "capital" then resourceScore = resourceScore + 12 end
            local score = presence * 1.2 + math.max(0, 70 - control) + resourceScore
                + (5 - (r.security or 3)) * 4 + math.random(0, 8)
            if score > bestScore then
                bestScore = score
                bestRegion = r
            end
        end
    end
    return bestRegion
end

--- 回合结算结果
---@class TurnReport
---@field economy EconomyReport
---@field victory_delta table { economic, military }
---@field events_triggered string[]
---@field ai_changes string[]
---@field warnings string[]

--- 执行完整回合结算
---@param state table
---@return TurnReport
function TurnEngine.EndTurn(state)
    local report = {
        economy = nil,
        victory_delta = { economic = 0, military = 0 },
        events_triggered = {},
        ai_changes = {},
        warnings = {},
    }

    -- ========================================
    -- 阶段 0: 通胀推进（影响本季价格）
    -- ========================================
    local infl = Balance.INFLATION
    local era = Config.GetEraByYear and Config.GetEraByYear(state.year) or nil
    local isWarPressure = (state.flags and state.flags.at_war) or (era and era.war_stripe)
    local drift = isWarPressure and infl.quarter_drift_war or infl.quarter_drift_peace
    drift = drift + GameState.GetModifierValue(state, "inflation_drift")
    drift = math.max(infl.quarter_drift_crisis_floor or -0.015, drift)
    state.inflation_factor = math.max(infl.floor_factor or infl.base_factor or 1.0,
        math.min(infl.cap_factor, (state.inflation_factor or 1.0) + drift))

    -- ========================================
    -- 阶段 1: 经济结算
    -- ========================================
    state.phase = "settlement"
    report.economy = Economy.Settle(state)

    -- ========================================
    -- 阶段 1.5: 股市 GBM 更新（每季一次）
    -- ========================================
    StockEngine.UpdateAll(state)

    -- ========================================
    -- 阶段 1.6: 贷款利息结算 & 到期还本 & 破产检测
    -- ========================================
    report.loan_interest = 0
    report.loan_defaulted = false
    local anyDefaultThisTurn = false
    if state.loans and #state.loans > 0 then
        -- 计算当前杠杆率（用于动态利率）
        local currentLeverage = GameState.CalcLeverage(state)
        local leverageMul = Balance.LOAN.leverage_interest_multiplier or 1.5

        local kept = {}
        for _, loan in ipairs(state.loans) do
            -- 动态利率：base_interest × (1 + leverage × multiplier)
            local effectiveRate = loan.interest * (1 + currentLeverage * leverageMul)
            local interest = math.ceil(loan.principal * effectiveRate)
            report.loan_interest = report.loan_interest + interest
            if state.cash >= interest then
                state.cash = state.cash - interest
                loan.total_paid = (loan.total_paid or 0) + interest
            else
                -- 违约：本金按违约率膨胀
                loan.principal = math.floor(loan.principal * (1 + Balance.LOAN.default_penalty))
                report.loan_defaulted = true
                anyDefaultThisTurn = true
                GameState.AddLog(state, string.format("贷款违约！利息 %d 付不出，本金膨胀至 %d",
                    interest, loan.principal))
            end
            loan.remaining_turns = loan.remaining_turns - 1
            if loan.remaining_turns <= 0 then
                -- 到期还本
                if state.cash >= loan.principal then
                    state.cash = state.cash - loan.principal
                    GameState.AddLog(state, string.format("贷款 %d 到期清偿", loan.principal))
                else
                    -- 还不上：检查是否还能展期
                    local rollovers = loan.rollovers or 0
                    if rollovers < (Balance.LOAN.max_rollovers or 1) then
                        -- 允许展期：部分清偿 + 延长 4 季 + 本金膨胀
                        local pay = state.cash
                        state.cash = 0
                        loan.principal = math.floor((loan.principal - pay) * (1 + Balance.LOAN.default_penalty))
                        loan.remaining_turns = 4
                        loan.rollovers = rollovers + 1
                        table.insert(kept, loan)
                        GameState.AddLog(state, string.format(
                            "贷款展期（第%d次）：剩余欠款 %d，延长4季",
                            loan.rollovers, loan.principal))
                    else
                        -- 已达展期上限 → 强制清算
                        local remaining = loan.principal
                        -- 1) 先用现金抵扣
                        local cashPay = math.min(state.cash, remaining)
                        state.cash = state.cash - cashPay
                        remaining = remaining - cashPay
                        -- 2) 再用黄金按市价抵扣
                        if remaining > 0 and state.gold > 0 then
                            local goldPrice = math.max(1,
                                math.floor(Balance.MINE.gold_price * GameState.GetInflationFactor(state)))
                            local goldNeeded = math.ceil(remaining / goldPrice)
                            local goldUsed = math.min(state.gold, goldNeeded)
                            state.gold = state.gold - goldUsed
                            remaining = remaining - goldUsed * goldPrice
                            state.emergency_gold_sold = true
                            GameState.AddLog(state, string.format(
                                "强制清算：变卖 %d 单位黄金偿债", goldUsed))
                        end
                        -- 3) 仍不够则坏账核销
                        if remaining > 0 then
                            anyDefaultThisTurn = true
                            state.military.morale = math.max(0,
                                state.military.morale + (Balance.LOAN.default_morale_penalty or -10))
                            GameState.AddLog(state, string.format(
                                "坏账核销：%d 克朗无力偿还，家族声誉受损，士气 %d",
                                remaining, Balance.LOAN.default_morale_penalty or -10))
                        else
                            GameState.AddLog(state, "贷款到期强制清算完毕")
                        end
                        -- 贷款不保留（不 insert 到 kept）
                    end
                end
            else
                table.insert(kept, loan)
            end
        end
        state.loans = kept
    end

    -- ── 破产检测 ──
    local bkConfig = Balance.LOAN.bankruptcy or {}
    -- 连续违约追踪
    if anyDefaultThisTurn then
        state.loan_consecutive_defaults = (state.loan_consecutive_defaults or 0) + 1
    else
        state.loan_consecutive_defaults = 0
    end
    -- 净资产追踪
    local totalAssets = GameState.CalcTotalAssets(state)
    local totalDebt = GameState.CalcTotalDebt(state)
    if totalAssets < totalDebt then
        state.negative_net_worth_turns = (state.negative_net_worth_turns or 0) + 1
    else
        state.negative_net_worth_turns = 0
    end
    -- 触发破产
    local bkDefaults = bkConfig.consecutive_defaults or 3
    local bkNegTurns = bkConfig.negative_net_worth_turns or 4
    if (state.loan_consecutive_defaults >= bkDefaults)
        or (state.negative_net_worth_turns >= bkNegTurns) then
        state.bankrupt = true
        local reason = ""
        if state.loan_consecutive_defaults >= bkDefaults then
            reason = string.format("连续 %d 季贷款违约", state.loan_consecutive_defaults)
        else
            reason = string.format("净资产连续 %d 季为负", state.negative_net_worth_turns)
        end
        GameState.AddLog(state, "💀 家族宣告破产！原因：" .. reason)
        table.insert(report.warnings, "家族破产！" .. reason)
    end

    -- ========================================
    -- 阶段 1.7: 科技研发推进
    -- ========================================
    Tech.Tick(state, report)

    if report.economy.bankrupt then
        table.insert(report.warnings, "家族财政陷入困境！")
    end

    -- ========================================
    -- 阶段 2: 事件检查
    -- ========================================
    state.phase = "event"
    -- 随机事件冷却推进
    for eventId, cd in pairs(state.random_cooldowns) do
        if cd > 0 then
            state.random_cooldowns[eventId] = cd - 1
        end
    end
    -- 检查本季事件并入队
    local triggeredEvents = Events.CheckEvents(state)
    if #triggeredEvents > 0 then
        Events.Enqueue(state, triggeredEvents)
        for _, ev in ipairs(triggeredEvents) do
            table.insert(report.events_triggered, ev.title)
        end
    end

    -- ========================================
    -- 阶段 3: 胜利点结算（v2 — 新公式 + 章节门控 + war_mod）
    -- ========================================
    local oldEco = state.victory.economic
    local oldMil = state.victory.military

    local totalControl = GameState.CalcTotalControl(state)
    local totalInfluence = GameState.CalcTotalInfluence(state)
    local isWar = state.flags.at_war

    -- ── 经济胜利点 ──
    local BVE = BV.economic
    local ecoDelta = 0
    if state.year >= BVE.gate_year then
        local cashPart    = state.cash > 0 and math.floor(state.cash / BVE.cash_divisor) or 0
        local goldPart    = math.floor(state.gold * BVE.gold_multiplier)
        local controlPart = math.floor(totalControl / BVE.control_divisor)
        local influPart   = math.floor(totalInfluence / BVE.influence_divisor)
        ecoDelta = cashPart + goldPart + controlPart + influPart
        -- war_mod
        if isWar then
            ecoDelta = math.floor(ecoDelta * BVE.war_mod)
        end
        -- Influence 阈值 5 级加成
        if totalInfluence >= 300 then
            ecoDelta = ecoDelta + 5
        end
    end

    -- ── 军事胜利点 ──
    local BVM = BV.military
    local milDelta = 0
    if state.year >= BVM.gate_year then
        local guardPart   = math.floor(state.military.guards * BVM.guard_multiplier)
        local moralePart  = math.floor(state.military.morale / BVM.morale_divisor)
        local controlPart = math.floor(totalControl / BVM.control_divisor)
        local winsPart    = math.min(state.battle_wins_unclaimed or 0, BVM.battle_wins_cap)
        milDelta = guardPart + moralePart + controlPart + winsPart
        -- war_mod
        if isWar then
            milDelta = math.floor(milDelta * BVM.war_mod)
        end
        -- Influence 阈值 5 级加成
        if totalInfluence >= 300 then
            milDelta = milDelta + 5
        end
    end

    state.victory.economic = state.victory.economic + ecoDelta
    state.victory.military = state.victory.military + milDelta

    -- 上限保护
    state.victory.economic = math.min(state.victory.economic, BVE.threshold + 50)
    state.victory.military = math.min(state.victory.military, BVM.threshold + 50)

    report.victory_delta.economic = state.victory.economic - oldEco
    report.victory_delta.military = state.victory.military - oldMil
    state.battle_wins_unclaimed = 0

    -- ========================================
    -- 阶段 4: 修正器推进
    -- ========================================
    GameState.TickModifiers(state)

    -- ========================================
    -- 阶段 4.5: Influence 自然衰减
    -- 每季所有地区 influence 衰减，除非本季执行了文化行动
    -- ========================================
    if not state.culture_action_this_turn then
        local decay = Balance.INFLUENCE.decay_per_season
        for _, r in ipairs(state.regions) do
            r.influence = math.max(0, (r.influence or 0) + decay)
        end
    end
    -- 重置本季文化行动标记
    state.culture_action_this_turn = false
    -- 重置紧急变卖标记
    state.emergency_gold_sold = false

    if (state.regulation_pressure or 0) >= 50 then
        local checkChance = math.min(0.35, (state.regulation_pressure or 0) / 300)
        if math.random() < checkChance then
            local penalty = math.floor(state.cash * 0.03)
            state.cash = math.max(0, state.cash - penalty)
            state.regulation_pressure = math.max(0, (state.regulation_pressure or 0) - 8)
            table.insert(report.warnings, string.format("监管检查罚没 %d 现金", penalty))
            GameState.AddLog(state, string.format("监管检查：罚没 %d 现金，压力略有下降", penalty))
        end
    end

    -- ========================================
    -- 阶段 5: 武装士气衰减
    -- ========================================
    local moraleBefore = state.military.morale
    state.military.morale = math.max(0, math.min(100,
        state.military.morale + Balance.MILITARY.morale_decay))

    -- 军务主管加成：减缓衰减
    local milChiefBonus = GameState.GetPositionBonus(state, "military_chief")
    if milChiefBonus > 0 then
        state.military.morale = math.min(100,
            state.military.morale + math.floor(milChiefBonus * 3))
    end

    -- ========================================
    -- 阶段 6: AI 势力更新
    -- ========================================
    for _, faction in ipairs(state.ai_factions) do
        local aiConfig = Balance.AI[faction.type]
        if aiConfig then
            -- 基础资产增长率 + 情报渗透 debuff
            local rate = aiConfig.growth_rate + (faction.growth_mod or 0)
            if faction.growth_mod_remaining and faction.growth_mod_remaining > 0 then
                faction.growth_mod_remaining = faction.growth_mod_remaining - 1
                if faction.growth_mod_remaining <= 0 then
                    faction.growth_mod = 0
                end
            end
            local growth = math.floor(faction.cash * math.max(0, rate))
            faction.cash = faction.cash + growth
            local foreignControl = GameState.GetModifierValue(state, "foreign_control")
            if faction.type == "foreign_capital" and foreignControl ~= 0 then
                faction.attitude = math.max(-100, math.min(100,
                    faction.attitude + math.floor(foreignControl / 10)))
                faction.power = math.max(0, math.min(100,
                    faction.power + math.floor(foreignControl / 12)))
            end

            -- 势力增长（加速：每季 +2，上限 100）
            if faction.power < 100 then
                local powerGain = 2
                -- 战时 AI 势力增长更快
                if state.flags.at_war then powerGain = 3 end
                if faction.cash >= (aiConfig.expand_threshold or math.huge) then
                    powerGain = powerGain + 1
                    local targetRegion = PickAIExpansionRegion(state, faction)
                    if targetRegion then
                        local before = targetRegion.ai_presence[faction.id] or 0
                        targetRegion.ai_presence[faction.id] = math.min(100, before + 2)
                        table.insert(report.ai_changes,
                            string.format("%s 扩大了在%s的地区存在度", faction.name, targetRegion.name))
                    end
                end
                faction.power = math.min(100, faction.power + powerGain)
            end

            -- 协议保护期内 AI 不主动敌对
            if faction.pact_remaining and faction.pact_remaining > 0 then
                faction.pact_remaining = faction.pact_remaining - 1
                if faction.attitude < 10 then faction.attitude = 10 end
            end

            -- 战时外资撤退
            if faction.type == "foreign_capital" and state.flags.at_war then
                if math.random() > aiConfig.war_flee_threshold then
                    local fled = math.floor(faction.cash * 0.15)
                    faction.cash = faction.cash - fled
                    faction.power = math.max(0, faction.power - 3)
                    table.insert(report.ai_changes,
                        string.format("%s 因战争局势撤资 %d", faction.name, fled))
                end
            end

            -- 与玩家的态度随竞争变化（多维触发）
            -- 1) 经济碾压 → 嫉妒
            if state.cash > faction.cash * 1.5 then
                faction.attitude = math.max(-100, faction.attitude - 3)
            end
            -- 2) 军事威胁 → 恐惧
            if state.military.guards > 20 and faction.power < 50 then
                faction.attitude = math.max(-100, faction.attitude - 2)
            end
            -- 3) 玩家矿山过多 → 领地竞争
            if #state.mines >= 5 then
                faction.attitude = math.max(-100, faction.attitude - 1)
            end
            -- 4) AI 势力扩大后自然傲慢
            if faction.power >= 60 and faction.attitude > -50 then
                faction.attitude = faction.attitude - 1
            end
        end
    end

    -- ========================================
    -- 阶段 6.5: AI 可能主动进攻（战斗系统）
    -- ========================================
    local combatResults = Combat.ResolveAIActions(state)
    for _, msg in ipairs(combatResults) do
        table.insert(report.ai_changes, msg)
    end

    -- ========================================
    -- 阶段 7: 工人士气
    -- ========================================
    -- 工资满足度影响士气
    if state.workers.wage < Balance.WORKERS.base_wage then
        state.workers.morale = math.max(0, state.workers.morale - 5)
        if state.workers.morale < 30 then
            table.insert(report.warnings, "工人士气极低，可能引发罢工！")
        end
    else
        -- 工资正常，士气缓慢恢复
        state.workers.morale = math.min(100, state.workers.morale + 1)
    end

    -- ========================================
    -- 阶段 8: 家族培养进度
    -- ========================================
    if state.family.training then
        state.family.training.progress = state.family.training.progress + 1
        if state.family.training.progress >= state.family.training.total then
            -- 培养完成
            table.insert(state.family.members, state.family.training.member_template)
            GameState.AddLog(state, string.format("新成员 %s 加入家族！",
                state.family.training.member_template.name))
            table.insert(report.warnings,
                "新家族成员 " .. state.family.training.member_template.name .. " 培养完成！")
            state.family.training = nil
        end
    end

    -- ========================================
    -- 阶段 9: 推进季度
    -- ========================================
    state.phase = "action"
    GameState.AdvanceQuarter(state)
    state.ap.max = GameState.CalcMaxAP(state)
    state.ap.current = state.ap.max

    -- 日志
    local logText = string.format(
        "采金:%d 产银:%d 收入:%d 支出:%d 净利:%d 现金:%d",
        report.economy.gold_mined,
        report.economy.silver_mined,
        report.economy.total_income,
        report.economy.total_expense,
        report.economy.net,
        state.cash)
    GameState.AddLog(state, logText)

    return report
end

--- 获取回合报告的简要文本
---@param report TurnReport
---@return string
function TurnEngine.FormatReportSummary(report)
    local lines = {}

    -- 经济
    local eco = report.economy
    table.insert(lines, string.format("采金 %d | 产银 %d | 收入 %d",
        eco.gold_mined, eco.silver_mined, eco.total_income))
    table.insert(lines, string.format("支出 %d (工资%d+军费%d+补给%d+税%d)",
        eco.total_expense, eco.worker_expense, eco.military_expense,
        eco.supply_expense, eco.tax))
    if report.loan_interest and report.loan_interest > 0 then
        table.insert(lines, string.format("贷款利息 %d", report.loan_interest))
    end
    if report.tech_completed then
        local TechData = require("data.tech_data")
        local t = TechData.GetById(report.tech_completed)
        if t then table.insert(lines, "✓ 科技完成：" .. t.name) end
    end

    -- 胜利
    if report.victory_delta.economic > 0 or report.victory_delta.military > 0 then
        table.insert(lines, string.format("胜利点 经济+%d 军事+%d",
            report.victory_delta.economic, report.victory_delta.military))
    end

    -- 警告
    for _, w in ipairs(report.warnings) do
        table.insert(lines, "⚠ " .. w)
    end

    return table.concat(lines, "\n")
end

return TurnEngine
