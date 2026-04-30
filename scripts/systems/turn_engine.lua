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
local GrandPowers = require("systems.grand_powers")
local BranchEvents = require("systems.branch_events")

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
    -- 乘法模型：factor *= (1 + drift)，符合通胀的复利特征
    state.inflation_factor = math.max(infl.floor_factor or infl.base_factor or 1.0,
        math.min(infl.cap_factor, (state.inflation_factor or 1.0) * (1 + drift)))

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
    --   违约流程（渐进式）：
    --     1) 现金付息
    --     2) 现金不足 → 强制变卖黄金补足
    --     3) 黄金不足 → 强制降级矿山换现金
    --     4) 清算后仍不足 → 真正违约，本金膨胀
    -- ========================================
    report.loan_interest = 0
    report.loan_defaulted = false
    report.forced_liquidation = {}  -- 记录本季强制清算明细
    local anyDefaultThisTurn = false
    local forcedLiquidation = Balance.LOAN.forced_liquidation or {}

    --- 强制抵押清算：尝试从资产中凑足 shortfall 金额
    --- @param st table 游戏状态
    --- @param shortfall number 需要补足的金额
    --- @param reportLiq string[] 清算日志输出
    --- @return number remaining 清算后仍欠的金额（0 表示已补足）
    local function ForcedLiquidate(st, shortfall, reportLiq)
        local remaining = shortfall
        local didLiquidate = false

        -- 步骤 1：强制变卖黄金
        if remaining > 0 and (forcedLiquidation.sell_gold ~= false) and (st.gold or 0) > 0 then
            local goldPrice = math.max(1,
                math.floor(Balance.MINE.gold_price * GameState.GetInflationFactor(st)))
            local goldNeeded = math.ceil(remaining / goldPrice)
            local goldUsed = math.min(st.gold, goldNeeded)
            st.gold = st.gold - goldUsed
            local recovered = goldUsed * goldPrice
            st.cash = st.cash + recovered
            remaining = remaining - recovered
            st.emergency_gold_sold = true
            didLiquidate = true
            local msg = string.format("强制清算：变卖 %d 单位黄金（回收 %d 克朗）", goldUsed, recovered)
            GameState.AddLog(st, msg)
            table.insert(reportLiq, msg)
        end

        -- 步骤 2：强制降级矿山
        if remaining > 0 and (forcedLiquidation.downgrade_mines ~= false) then
            local refundRatio = forcedLiquidation.mine_downgrade_refund_ratio or 0.5
            local assetFactor = GameState.GetAssetPriceFactor(st)
            -- 按等级从高到低排序，优先降级高等级矿山（回收更多）
            local sortedMines = {}
            for _, m in ipairs(st.mines) do
                table.insert(sortedMines, { mine = m })
            end
            table.sort(sortedMines, function(a, b) return a.mine.level > b.mine.level end)

            for _, entry in ipairs(sortedMines) do
                if remaining <= 0 then break end
                local mine = entry.mine
                if mine.level > 1 then
                    local levelsToSell = 0
                    local totalRefund = 0
                    while mine.level > 1 and remaining > 0 do
                        local refund = math.floor(Balance.MINE.upgrade_cost * assetFactor * refundRatio)
                        mine.level = mine.level - 1
                        levelsToSell = levelsToSell + 1
                        totalRefund = totalRefund + refund
                        st.cash = st.cash + refund
                        remaining = remaining - refund
                    end
                    if levelsToSell > 0 then
                        didLiquidate = true
                        local mineName = mine.name or "矿山"
                        local msg = string.format(
                            "强制清算：矿山[%s]降级 %d 级（回收 %d 克朗），当前等级 %d",
                            mineName, levelsToSell, totalRefund, mine.level)
                        GameState.AddLog(st, msg)
                        table.insert(reportLiq, msg)
                    end
                end
            end
        end

        -- 士气惩罚（只要发生了清算就扣）
        if didLiquidate then
            local penalty = forcedLiquidation.morale_penalty or -5
            st.military.morale = math.max(0, st.military.morale + penalty)
        end

        return math.max(0, remaining)
    end

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
                -- 正常付息
                state.cash = state.cash - interest
                loan.total_paid = (loan.total_paid or 0) + interest
            else
                -- 现金不足 → 启动强制抵押清算流程
                local shortfall = interest - state.cash
                local afterLiq = ForcedLiquidate(state, shortfall, report.forced_liquidation)

                if afterLiq <= 0 then
                    -- 清算后凑够了，正常扣款
                    state.cash = state.cash - interest
                    loan.total_paid = (loan.total_paid or 0) + interest
                    GameState.AddLog(state, string.format(
                        "贷款利息 %d：现金不足，通过强制清算补足", interest))
                else
                    -- 清算后仍不够 → 真正违约
                    -- 先把所有现金用于偿付
                    local partialPay = state.cash
                    state.cash = 0
                    loan.total_paid = (loan.total_paid or 0) + partialPay
                    -- 未偿付部分 → 本金膨胀
                    local unpaid = interest - partialPay
                    loan.principal = math.floor(loan.principal * (1 + Balance.LOAN.default_penalty))
                    report.loan_defaulted = true
                    anyDefaultThisTurn = true
                    GameState.AddLog(state, string.format(
                        "贷款违约！利息 %d 中 %d 无法偿付（已强制清算），本金膨胀至 %d",
                        interest, unpaid, loan.principal))
                end
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
                        -- 已达展期上限 → 强制清算偿还本金
                        local shortfall = loan.principal - state.cash
                        local afterLiq = ForcedLiquidate(state, shortfall, report.forced_liquidation)

                        if afterLiq <= 0 then
                            -- 清算后够还
                            state.cash = state.cash - loan.principal
                            GameState.AddLog(state, "贷款到期：通过强制清算完成还本")
                        else
                            -- 清算后仍不够 → 坏账核销
                            local partialPay = state.cash
                            state.cash = 0
                            local remaining = loan.principal - partialPay
                            anyDefaultThisTurn = true
                            state.military.morale = math.max(0,
                                state.military.morale + (Balance.LOAN.default_morale_penalty or -10))
                            GameState.AddLog(state, string.format(
                                "坏账核销：%d 克朗无力偿还（已强制清算），家族声誉受损",
                                remaining))
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

    -- ── 破产检测（渐进式：清算 → 警告 → 破产）──
    local bkConfig = Balance.LOAN.bankruptcy or {}
    -- 连续违约追踪（只有强制清算后仍违约才计入）
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
    -- 警告阶段
    local warnAt = bkConfig.warning_at_defaults or 2
    if (state.loan_consecutive_defaults >= warnAt)
        and not state.bankrupt then
        local bkDefaults = bkConfig.consecutive_defaults or 4
        local remaining = bkDefaults - state.loan_consecutive_defaults
        local warnMsg = string.format(
            "连续违约 %d 季（强制清算后仍无法偿付），再违约 %d 季将破产！",
            state.loan_consecutive_defaults, remaining)
        table.insert(report.warnings, warnMsg)
        GameState.AddLog(state, "⚠ " .. warnMsg)
    end
    if (state.negative_net_worth_turns >= warnAt)
        and not state.bankrupt then
        local bkNegTurns = bkConfig.negative_net_worth_turns or 4
        local remaining = bkNegTurns - state.negative_net_worth_turns
        if remaining > 0 then
            local warnMsg = string.format(
                "净资产连续 %d 季为负，再持续 %d 季将破产！",
                state.negative_net_worth_turns, remaining)
            table.insert(report.warnings, warnMsg)
            GameState.AddLog(state, "⚠ " .. warnMsg)
        end
    end
    -- 触发破产
    local bkDefaults = bkConfig.consecutive_defaults or 4
    local bkNegTurns = bkConfig.negative_net_worth_turns or 4
    if (state.loan_consecutive_defaults >= bkDefaults)
        or (state.negative_net_worth_turns >= bkNegTurns) then
        state.bankrupt = true
        local reason = ""
        if state.loan_consecutive_defaults >= bkDefaults then
            reason = string.format("连续 %d 季贷款违约（强制清算后仍无法偿付）",
                state.loan_consecutive_defaults)
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

    -- AI 同步累积相对胜利分，用于“领先 AI 多少点”的胜利判断
    for _, faction in ipairs(state.ai_factions or {}) do
        faction.victory = faction.victory or { economic = 0, military = 0 }
        local aiDelta = GameState.CalcAIVictoryDelta(state, faction)
        faction.victory.economic = (faction.victory.economic or 0) + (aiDelta.economic or 0)
        faction.victory.military = (faction.victory.military or 0) + (aiDelta.military or 0)
        faction.battle_wins_unclaimed = 0
    end

    report.victory_delta.economic = state.victory.economic - oldEco
    report.victory_delta.military = state.victory.military - oldMil
    state.battle_wins_unclaimed = 0
    GameState.UpdateVictoryPrompt(state)

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
            -- 现金上限：防止复利爆炸增长
            local cashCap = aiConfig.cash_cap or 10000
            if faction.cash > cashCap then
                faction.cash = cashCap
            end

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

            -- ── AI 主动花费现金（防止现金无意义堆积）──
            local spend = Balance.AI.spending
            -- 1) 雇佣兵：有钱时花钱提升 power
            if faction.cash >= (spend.mercenary_cost or 500)
                and faction.cash > (aiConfig.expand_threshold or 600)
                and faction.power < 90
                and math.random() < (spend.mercenary_chance or 0.25) then
                faction.cash = faction.cash - spend.mercenary_cost
                faction.power = math.min(100, faction.power + (spend.mercenary_power or 5))
                table.insert(report.ai_changes,
                    string.format("%s 雇佣了私兵（power +%d）", faction.name, spend.mercenary_power or 5))
            end
            -- 2) 地区压制：态度差时打压玩家控制度
            if faction.attitude < -30
                and faction.cash >= (spend.suppress_cost or 400)
                and math.random() < (spend.suppress_chance or 0.20) then
                faction.cash = faction.cash - spend.suppress_cost
                local targetRegion = PickAIExpansionRegion(state, faction)
                if targetRegion then
                    targetRegion.control = math.max(0,
                        (targetRegion.control or 0) + (spend.suppress_control or -3))
                    table.insert(report.ai_changes,
                        string.format("%s 在%s进行了地区压制（控制度 %d）",
                            faction.name, targetRegion.name, spend.suppress_control or -3))
                end
            end
            -- 3) 经济制裁：外资对玩家施加负面修正器
            if faction.type == "foreign_capital"
                and faction.attitude < -40
                and faction.cash >= (spend.sanction_cost or 600)
                and math.random() < (spend.sanction_chance or 0.15) then
                faction.cash = faction.cash - spend.sanction_cost
                GameState.AddModifier(state, "foreign_sanction", "income_mod", -0.10, 3)
                table.insert(report.ai_changes,
                    string.format("%s 对家族实施了经济制裁（收入 -10%%，持续3季）", faction.name))
            end
            -- 4) 通胀操纵：外资推高通胀（极端敌对时）
            if faction.type == "foreign_capital"
                and faction.attitude < -50
                and faction.cash >= (spend.inflate_cost or 800)
                and math.random() < (spend.inflate_chance or 0.12) then
                faction.cash = faction.cash - spend.inflate_cost
                GameState.AddModifier(state, "foreign_inflate",
                    "inflation_drift", spend.inflate_drift or 0.012, spend.inflate_duration or 4)
                table.insert(report.ai_changes,
                    string.format("%s 操纵了货币供应，推高通胀（+%.1f%%/季，持续%d季）",
                        faction.name, (spend.inflate_drift or 0.012) * 100, spend.inflate_duration or 4))
            end
            -- 5) 矿价波动：外资压低金银矿产品价格
            if faction.type == "foreign_capital"
                and faction.attitude < -35
                and faction.cash >= (spend.mine_price_cost or 700)
                and math.random() < (spend.mine_price_chance or 0.15) then
                faction.cash = faction.cash - spend.mine_price_cost
                local priceMod = spend.mine_price_mod or -0.15
                local priceDur = spend.mine_price_duration or 3
                GameState.AddModifier(state, "foreign_gold_dump",
                    "gold_price_mod", priceMod, priceDur)
                GameState.AddModifier(state, "foreign_silver_dump",
                    "silver_price_mod", priceMod, priceDur)
                table.insert(report.ai_changes,
                    string.format("%s 压低了金银市场价格（%.0f%%，持续%d季）",
                        faction.name, priceMod * 100, priceDur))
            end

            -- ── 态度系统：负向触发器 ──
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

            -- ── 态度系统：正向触发器（平衡单调下降）──
            local posTrig = Balance.AI.positive_triggers
            local attCap = posTrig.attitude_cap or 60
            -- 5) 自然回暖：每季基线 +1（关系不会永远恶化）
            if faction.attitude < attCap then
                faction.attitude = math.min(attCap,
                    faction.attitude + (posTrig.natural_recovery or 1))
            end
            -- 6) 玩家经济弱势 → 不再是威胁
            if state.cash < (posTrig.player_weak_cash or 500)
                and faction.attitude < attCap then
                faction.attitude = math.min(attCap, faction.attitude + 2)
            end
            -- 7) 玩家矿山少 → 领地竞争消退
            if #state.mines < (posTrig.player_few_mines or 2)
                and faction.attitude < attCap then
                faction.attitude = math.min(attCap, faction.attitude + 1)
            end
            -- 8) AI 弱势时求和倾向
            if faction.power < (posTrig.low_power_sympathy or 30)
                and faction.attitude < attCap then
                faction.attitude = math.min(attCap, faction.attitude + 1)
            end
            -- 最终 clamp
            faction.attitude = math.max(-100, math.min(100, faction.attitude))
        end
    end

    -- ── 阶段 6.2: foreign_control 持续性修正器 ──
    -- 根据 foreign_capital 在各地区的 ai_presence 总和计算外资控制度
    -- 该修正器影响 foreign_capital 的态度和 power（已在上方消费）
    do
        local totalForeignPresence = 0
        for _, r in ipairs(state.regions or {}) do
            if r.ai_presence and r.ai_presence.foreign_capital then
                totalForeignPresence = totalForeignPresence + r.ai_presence.foreign_capital
            end
        end
        -- 外资存在度 > 30 时开始产生 foreign_control 修正
        -- 每 20 点存在度 → +1 foreign_control 值
        local fcValue = 0
        if totalForeignPresence > 30 then
            fcValue = math.floor((totalForeignPresence - 30) / 20)
        end
        -- 移除旧的 foreign_control 修正器，替换为当前值
        if state.modifiers then
            local kept = {}
            for _, mod in ipairs(state.modifiers) do
                if mod.target ~= "foreign_control" then
                    table.insert(kept, mod)
                end
            end
            state.modifiers = kept
        end
        if fcValue > 0 then
            GameState.AddModifier(state, "foreign_presence_control",
                "foreign_control", fcValue, 1)
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
    -- 阶段 6.7: 大国博弈系统更新
    -- 历史漂移 → 继承处理 → 征服执行 → 抵抗增长 → 本地AI联动
    -- ========================================
    local gpReport = GrandPowers.Tick(state)
    if gpReport then
        for _, msg in ipairs(gpReport.conquest_msgs or {}) do
            table.insert(report.ai_changes, msg)
        end
        for _, msg in ipairs(gpReport.succession_msgs or {}) do
            table.insert(report.ai_changes, msg)
        end
    end

    -- ========================================
    -- 阶段 6.8: 历史分支事件检查
    -- 在大国博弈更新之后，检查是否有分支节点需要触发
    -- ========================================
    local branchEvents = BranchEvents.CheckBranchEvents(state)
    if #branchEvents > 0 then
        Events.Enqueue(state, branchEvents)
        for _, ev in ipairs(branchEvents) do
            table.insert(report.events_triggered, ev.title)
        end
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
    if report.forced_liquidation and #report.forced_liquidation > 0 then
        for _, msg in ipairs(report.forced_liquidation) do
            table.insert(lines, "⚠ " .. msg)
        end
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
