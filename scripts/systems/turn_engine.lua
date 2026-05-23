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
local Equipment = require("systems.equipment")
local Trade = require("systems.trade")
local Expedition = require("systems.expedition")
local Venture = require("systems.venture")
local PlayerActionsGP = require("systems.player_actions_gp")
local Culture         = require("systems.culture")
local MapTilesData = require("data.map_tiles_data")
local RegionsData = require("data.regions_data")

local BV = Balance.VICTORY

local TurnEngine = {}

local function TotalFactionPresence(state, factionId)
    local total = 0
    for _, r in ipairs(state.regions or {}) do
        total = total + ((r.ai_presence and r.ai_presence[factionId]) or 0)
    end
    return total
end

local function MarkFactionDefeated(state, faction, mode, report)
    if faction.defeated then return end
    faction.defeated = true
    faction.defeat_mode = mode or "routed"
    faction.collapsed = true
    faction.collapsed_seasons = nil
    faction.power = 0
    faction.cash = math.max(0, math.floor((faction.cash or 0) * 0.25))
    for _, r in ipairs(state.regions or {}) do
        if r.ai_presence and r.ai_presence[faction.id] then
            r.ai_presence[faction.id] = 0
        end
    end
    for _, tile in ipairs(state.map_tiles or {}) do
        if tile.controller == faction.id then
            tile.controller = "player"
            tile.manual_control = true
        end
    end
    -- 反向同步：tile controller 变化后重算 region 的 control / ai_presence
    MapTilesData.SyncRegionsFromTiles(state)
    local msg = string.format("%s 已被击败，剩余地盘转入玩家控制", faction.name)
    GameState.AddLog(state, msg)
    if report then table.insert(report.ai_changes, msg) end
end

local function CheckFactionDefeat(state, faction, report)
    if faction.defeated then return end
    local presence = TotalFactionPresence(state, faction.id)
    local colCfg = Balance.AI.collapse or {}
    if presence <= 5 and (faction.power or 0) <= (colCfg.power_threshold or 5) then
        MarkFactionDefeated(state, faction, "routed", report)
    elseif faction.collapsed and presence <= 8 and (faction.cash or 0) <= (colCfg.cash_threshold or 100) then
        MarkFactionDefeated(state, faction, "absorbed", report)
    end
end

local function UpdateSpecialContentFlags(state, report)
    state.special_content = state.special_content or {}
    local prev = {
        quota_active = state.special_content.quota_active,
        black_market_active = state.special_content.black_market_active,
        foreign_trade_window = state.special_content.foreign_trade_window,
        technocrat_route = state.special_content.technocrat_route,
    }

    local year = state.year or 1904
    local totalCtrl = GameState.CalcTotalControl(state)
    local knowledgeAvg = 0
    local activeMembers = 0
    for _, m in ipairs((state.family and state.family.members) or {}) do
        if m.status == "active" then
            knowledgeAvg = knowledgeAvg + ((m.attrs and m.attrs.knowledge) or 0)
            activeMembers = activeMembers + 1
        end
    end
    if activeMembers > 0 then knowledgeAvg = knowledgeAvg / activeMembers end

    state.special_content.quota_active = year >= 1946 and year <= 1991
    state.special_content.black_market_active = (state.flags and state.flags.at_war)
        or (year >= 1941 and year <= 1945)
        or (year >= 1992 and year <= 1995)
        or (state.regulation_pressure or 0) >= 45
    state.special_content.foreign_trade_window = year >= 1948
        and (year <= 1955 or year >= 1984)
    state.special_content.technocrat_route = (year >= 1946 and year <= 1991)
        and (totalCtrl >= 150 or knowledgeAvg >= 6)

    local labels = {
        quota_active = "配额生产窗口开启",
        black_market_active = "灰色市场机会增加",
        foreign_trade_window = "对外贸易窗口出现",
        technocrat_route = "技术官僚路线可推进",
    }
    for key, label in pairs(labels) do
        if state.special_content[key] and not prev[key] then
            table.insert(report.ai_changes, label)
        end
    end
end

local function PickAIExpansionRegion(state, faction)
    local bestRegion = nil
    local bestScore = -math.huge
    for _, r in ipairs(state.regions or {}) do
        r.ai_presence = r.ai_presence or {}
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
    return bestRegion
end

-- 压制专用：选玩家控制度最高且 AI 有存在度的地区（优先打击玩家核心区）
local function PickAISuppressRegion(state, faction)
    local best, bestScore = nil, -1
    for _, r in ipairs(state.regions or {}) do
        r.ai_presence = r.ai_presence or {}
        local playerControl = r.control or 0
        local aiPresence = r.ai_presence[faction.id] or 0
        if aiPresence > 0 and playerControl > bestScore then
            best = r
            bestScore = playerControl
        end
    end
    return best
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

    MapTilesData.EnsureState(state)
    MapTilesData.SyncTilesFromRegions(state)

    -- ========================================
    -- 阶段 0.5: 岗位专精加成刷新（upsert modifier，防止累积）
    -- ========================================
    do
        local BF = Balance.FAMILY
        local onboardRatio = BF.onboarding_bonus_ratio or 0.3

        -- 辅助：根据成员属性和适应期计算实际加成系数
        local function calcSpecBonus(member, attrName, fullBonus)
            if not member then return 0 end
            local attrVal = member[attrName] or 0
            local bonus = attrVal * fullBonus
            if (member.onboarding_remaining or 0) > 0 then
                bonus = bonus * onboardRatio
            end
            return bonus
        end

        -- 矿业主管：management → mine_output_mult 加成（每点 +3%，上限 30%）
        local mineDirector = GameState.GetMemberAtPosition(state, "mine_director")
        if mineDirector then
            local bonus = math.min(calcSpecBonus(mineDirector, "management", 0.03), 0.30)
            GameState.SetModifier(state, "spec_mine_director", "mine_output_mult", bonus)
        else
            GameState.RemoveModifier(state, "spec_mine_director")
        end

        -- 军务主管：strategy → spec_expedition_dmg 加成（每点 +2%，上限 20%）
        local milChief = GameState.GetMemberAtPosition(state, "military_chief")
        if milChief then
            local bonus = math.min(calcSpecBonus(milChief, "strategy", 0.02), 0.20)
            GameState.SetModifier(state, "spec_military_chief", "spec_expedition_dmg", bonus)
        else
            GameState.RemoveModifier(state, "spec_military_chief")
        end

        -- 民政主管：management → spec_passive_control 加成（每点 +0.5，上限 5）
        local civilDirector = GameState.GetMemberAtPosition(state, "civil_director")
        if civilDirector then
            local bonus = math.min(calcSpecBonus(civilDirector, "management", 0.5), 5.0)
            GameState.SetModifier(state, "spec_civil_director", "spec_passive_control", bonus)
        else
            GameState.RemoveModifier(state, "spec_civil_director")
        end

        -- 科技顾问：knowledge → spec_research_speed 加成（每点 +2%，上限 20%）
        local techAdvisor = GameState.GetMemberAtPosition(state, "tech_advisor")
        if techAdvisor then
            local bonus = math.min(calcSpecBonus(techAdvisor, "knowledge", 0.02), 0.20)
            GameState.SetModifier(state, "spec_tech_advisor", "spec_research_speed", bonus)
        else
            GameState.RemoveModifier(state, "spec_tech_advisor")
        end

        -- 外交官：charisma → spec_aggression_decay 加成（每点 +0.1/季，上限 1.0）
        local diplomat = GameState.GetMemberAtPosition(state, "diplomat")
        if diplomat then
            local bonus = math.min(calcSpecBonus(diplomat, "charisma", 0.1), 1.0)
            GameState.SetModifier(state, "spec_diplomat", "spec_aggression_decay", bonus)
        else
            GameState.RemoveModifier(state, "spec_diplomat")
        end
    end

    -- ========================================
    -- 阶段 0: 通胀推进（影响本季价格）
    -- ========================================
    local infl = Balance.INFLATION
    local era = Config.GetEraByYear and Config.GetEraByYear(state.year) or nil
    local isWarPressure = (state.flags and state.flags.at_war) or (era and era.war_stripe)
    local drift = isWarPressure and infl.quarter_drift_war or infl.quarter_drift_peace
    -- 战后通缩恢复：和平期间若通胀高于阈值，额外施加负漂移使经济逐步恢复
    if not isWarPressure then
        local deflThreshold = infl.postwar_deflation_threshold or 2.0
        local deflDrift = infl.postwar_deflation_drift or -0.015
        if (state.inflation_factor or 1.0) > deflThreshold then
            drift = drift + deflDrift
        end
    end
    drift = drift + GameState.GetModifierValue(state, "inflation_drift")
    -- 难度乘数：高难度通胀漂移更快
    local diff = Config.GetDifficulty(state.difficulty)
    drift = drift * (diff.inflation_drift_mult or 1.0)
    drift = math.max(infl.quarter_drift_crisis_floor or -0.015, drift)
    -- 乘法模型：factor *= (1 + drift)，符合通胀的复利特征
    state.inflation_factor = math.max(infl.floor_factor or infl.base_factor or 1.0,
        math.min(infl.cap_factor, (state.inflation_factor or 1.0) * (1 + drift)))

    -- ========================================
    -- 阶段 1: 经济结算
    -- ========================================
    state.phase = "settlement"
    StockEngine.ApplyCompanySynergies(state)
    report.economy = Economy.Settle(state)

    -- ========================================
    -- 阶段 1.5: 股市 GBM 更新（每季一次）
    -- ========================================
    StockEngine.ApplyOperationalDrift(state, report.economy)
    StockEngine.UpdateAll(state)
    -- 做空仓位结算（利息、强平、到期）
    StockEngine.TickShorts(state)
    -- 操盘冷却推进
    StockEngine.TickManipulationCooldowns(state)
    -- M2: 方向互斥锁推进
    StockEngine.TickDirectionLocks(state)
    -- (公信力已合并到统一声誉，恢复逻辑在阶段 4.6)
    -- S2: 庇护难民冷却递减
    if (state._shelter_cooldown or 0) > 0 then
        state._shelter_cooldown = state._shelter_cooldown - 1
    end

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
            -- 动态利率：base_interest × (1 + leverage × multiplier) × 难度乘数
            local effectiveRate = loan.interest * (1 + currentLeverage * leverageMul) * (diff.loan_interest_mult or 1.0)
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

    -- 贷款利息计入累计支出统计
    if report.loan_interest and report.loan_interest > 0 then
        state.total_expense = (state.total_expense or 0) + report.loan_interest
        report.economy.total_expense = report.economy.total_expense + report.loan_interest
        report.economy.net = report.economy.net - report.loan_interest
    end

    -- ========================================
    -- 阶段 1.7: 科技研发推进
    -- ========================================
    Tech.Tick(state, report)

    -- ========================================
    -- 阶段 1.8: 装备生产/维修推进
    -- ========================================
    local equipMessages = Equipment.TickProduction(state)
    for _, msg in ipairs(equipMessages) do
        GameState.AddLog(state, "[装备] " .. msg)
        table.insert(report.warnings, msg)
    end

    -- ========================================
    -- 阶段 1.9: 外贸结算（解锁后激活）
    -- ========================================
    if Trade.CanDoForeignAction(state) then
        -- 结算运输中的订单（到达/失败判定）
        local tradeReport = Trade.SettleDeliveries(state)
        if #tradeReport.deliveries > 0 then
            local msg = string.format("[外贸] 本季度交付 %d 笔订单，收入 %d 金币",
                #tradeReport.deliveries, tradeReport.total_revenue)
            GameState.AddLog(state, msg)
            table.insert(report.warnings, msg)
        end
        if #tradeReport.failures > 0 then
            local msg = string.format("[外贸] %d 笔订单运输失败，损失货物",
                #tradeReport.failures)
            GameState.AddLog(state, msg)
            table.insert(report.warnings, msg)
        end
        -- 记录上季度收入（供经济结算使用）
        state.trade.last_quarter_revenue = tradeReport.total_revenue
        -- 生成新订单补充订单池
        Trade.GenerateOrders(state)
        report.trade_settlement = tradeReport
    end

    if report.economy.bankrupt then
        table.insert(report.warnings, "家族财政陷入困境！")
    end

    -- ========================================
    -- 阶段 2: 事件检查
    -- ========================================
    state.phase = "event"
    -- 随机事件冷却推进
    for eventId, cd in pairs(state.random_cooldowns or {}) do
        if cd > 0 then
            state.random_cooldowns[eventId] = cd - 1
        end
    end
    -- 检查本季事件并入队
    local triggeredEvents = Events.CheckEvents(state)
    if #triggeredEvents > 0 then
        local normalEvents = {}
        for _, ev in ipairs(triggeredEvents) do
            if ev.type == "market_intel" then
                -- market_intel 事件：自动应用效果，不入队（无选项）
                local msg = Events.ApplyMarketIntel(state, ev)
                if msg then
                    state.turn_messages = state.turn_messages or {}
                    table.insert(state.turn_messages, msg)
                end
                table.insert(report.events_triggered, ev.title)
            else
                table.insert(normalEvents, ev)
            end
        end
        if #normalEvents > 0 then
            Events.Enqueue(state, normalEvents)
            for _, ev in ipairs(normalEvents) do
                table.insert(report.events_triggered, ev.title)
            end
        end
    end

    -- ========================================
    -- 阶段 3: 胜利点结算（v2 — 新公式 + 章节门控 + war_mod）
    -- ========================================
    local oldEco = state.victory.economic
    local oldMil = state.victory.military

    local totalControl = GameState.CalcTotalControl(state)
    local isWar = state.flags and state.flags.at_war

    -- ── 经济胜利点 ──
    local BVE = BV.economic
    local ecoDelta = 0
    if state.year >= BVE.gate_year then
        local cashPart    = state.cash > 0 and math.floor(state.cash / BVE.cash_divisor) or 0
        local goldPart    = math.min(math.floor(state.gold * BVE.gold_multiplier), BVE.gold_vp_cap or 999)
        local controlPart = math.floor(totalControl / BVE.control_divisor)
        ecoDelta = cashPart + goldPart + controlPart
        -- war_mod
        if isWar then
            ecoDelta = math.floor(ecoDelta * BVE.war_mod)
        end
        -- 控制度里程碑"绝对统治"（总控制度>=280）→ +5
        if totalControl >= 280 then
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
        -- 装备分 + 老兵分（方案B）
        local equipScore, vetScore = Equipment.CalcVictoryScores(state)
        -- 威慑分：卫队 >= 阈值且本季无败绩 → +deterrence_bonus VP
        local deterrencePart = 0
        if state.military.guards >= (BVM.deterrence_guard_min or 15)
            and (state.battle_losses_this_quarter or 0) == 0 then
            deterrencePart = BVM.deterrence_bonus or 1
        end
        milDelta = guardPart + moralePart + controlPart + winsPart + equipScore + vetScore + deterrencePart
        -- war_mod
        if isWar then
            milDelta = math.floor(milDelta * BVM.war_mod)
        end
        -- 控制度里程碑"绝对统治"（总控制度>=280）→ +5
        if totalControl >= 280 then
            milDelta = milDelta + 5
        end
    end

    state.victory.economic = state.victory.economic + ecoDelta
    state.victory.military = state.victory.military + milDelta

    -- AI 同步累积相对胜利分，用于“领先 AI 多少点”的胜利判断
    for _, faction in ipairs(state.ai_factions or {}) do
        faction.victory = faction.victory or { economic = 0, military = 0 }
        -- 瘫痪期间不累积胜利分
        if not faction.collapsed then
            local aiDelta = GameState.CalcAIVictoryDelta(state, faction)
            faction.victory.economic = (faction.victory.economic or 0) + (aiDelta.economic or 0)
            faction.victory.military = (faction.victory.military or 0) + (aiDelta.military or 0)
        end
        faction.battle_wins_unclaimed = 0
    end

    report.victory_delta.economic = state.victory.economic - oldEco
    report.victory_delta.military = state.victory.military - oldMil
    state.battle_wins_unclaimed = 0
    state.battle_losses_this_quarter = 0  -- V2: 重置本季败绩（威慑VP用）
    GameState.UpdateVictoryPrompt(state)

    -- ========================================
    -- 阶段 3.5: 合作度实际效果（每季根据合作度区间刷新修正器）
    -- ========================================
    do
        -- 移除上季的合作度修正器
        if state.modifiers then
            local kept = {}
            for _, mod in ipairs(state.modifiers) do
                if mod.source ~= "collaboration_effect" then
                    table.insert(kept, mod)
                end
            end
            state.modifiers = kept
        end
        local collabScore = state.collaboration_score or 0
        if collabScore >= 30 then
            -- 合作者：占领维护费-30%（利用远征结算中已有的 occupation_maintenance_discount 读取）
            GameState.AddModifier(state, "collaboration_effect",
                "occupation_maintenance_discount", 0.30, 2)
        elseif collabScore <= -30 then
            -- 人民英雄：抵抗组织增长加成+15%（在 grand_powers 的抵抗增长中读取）
            GameState.AddModifier(state, "collaboration_effect",
                "resistance_growth_bonus", 0.15, 2)
        end
        -- 注：偏向合作(10~29)的贸易价格+10%直接在 trade.lua 订单生成时计算
        -- 注：消极抵抗(-10~-29)的制裁阈值+3直接在 expedition.lua CheckSanction 中计算
    end

    -- ========================================
    -- 阶段 4: 修正器推进
    -- ========================================
    GameState.TickModifiers(state)

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

    -- 在岗成员的腐败倾向会轻微影响监管压力；清廉团队则略微缓和。
    local corruptionAvg = GameState.GetActiveFamilyHiddenAverage(state, "corruption")
    -- 家族缺陷：贪得无厌（corruption_add）—— 叠加腐败均值
    local flawCorrupt = GameState.GetActiveFlawEffect and GameState.GetActiveFlawEffect(state, "corruption_add") or 0
    corruptionAvg = corruptionAvg + flawCorrupt
    if corruptionAvg >= 7 then
        state.regulation_pressure = math.min(100, (state.regulation_pressure or 0) + 1)
    elseif corruptionAvg > 0 and corruptionAvg <= 2 then
        state.regulation_pressure = math.max(0, (state.regulation_pressure or 0) - 1)
    end
    UpdateSpecialContentFlags(state, report)

    -- ========================================
    -- 阶段 4.6: 掠夺系统每季结算
    -- ========================================
    do
        local BRep = Balance.REPUTATION

        -- 1. 冷却计时器 tick（所有 cooldown > 0 的 -1）
        state.plunder_cooldowns = state.plunder_cooldowns or {}
        for key, cd in pairs(state.plunder_cooldowns) do
            if cd > 0 then
                state.plunder_cooldowns[key] = cd - 1
            end
        end

        -- 2. 声誉自然恢复（向 0 靠拢，+2 或 -2）
        local rep = state.reputation or 0
        if rep ~= 0 then
            local repRecovery = BRep.recovery_per_turn + (state.rep_recovery_bonus or 0)
            -- 新闻社持股加成恢复
            local pressLevel = nil
            if StockEngine and StockEngine.GetHoldingLevel then
                pressLevel = StockEngine.GetHoldingLevel(state, "balkan_press")
            end
            if pressLevel == "control" then
                repRecovery = repRecovery + BRep.press_control_recovery_bonus
            elseif pressLevel == "influence" then
                repRecovery = repRecovery + BRep.press_influence_recovery_bonus
            end
            if rep < 0 then
                state.reputation = math.min(0, rep + repRecovery)
            else
                state.reputation = math.max(0, rep - repRecovery)
            end
        end
        -- local_reputation 修正器：事件赋予的本地声誉惩罚（累加到 reputation）
        local localRepMod = GameState.GetModifierValue(state, "local_reputation")
        if localRepMod ~= 0 then
            state.reputation = (state.reputation or 0) + localRepMod
        end

        -- 3. 夺取矿脉到期检查 + 产出
        state.seized_veins = state.seized_veins or {}
        local keptVeins = {}
        local veinIncome = 0
        for _, vein in ipairs(state.seized_veins) do
            -- 产出
            local income = math.floor(vein.gold_per_turn * GameState.GetInflationFactor(state))
            veinIncome = veinIncome + income
            vein.remaining = vein.remaining - 1
            if vein.remaining > 0 then
                table.insert(keptVeins, vein)
            end
        end
        state.seized_veins = keptVeins
        if veinIncome > 0 then
            state.cash = state.cash + veinIncome
            local msg = string.format("⛏ 夺取矿脉产出 %d 克朗（剩余 %d 处）",
                veinIncome, #keptVeins)
            table.insert(report.ai_changes, msg)
            GameState.AddLog(state, msg)
        end

        -- 4. 公敌级别：地区控制力衰减
        local repTier = GameState.GetReputationTier(state)
        local controlDecay = BRep.control_decay[repTier] or 0
        if controlDecay > 0 then
            for _, r in ipairs(state.regions) do
                r.control = math.max(0, (r.control or 0) - controlDecay)
            end
            local msg = string.format("⚠ 公敌声誉导致所有地区控制力 -%d", controlDecay)
            table.insert(report.warnings, msg)
            GameState.AddLog(state, msg)
        end
    end

    -- 家族学位：公共管理（control_per_season）—— 每季首都控制度被动增长
    local degreeControlGain = GameState.GetActiveDegreeEffect and GameState.GetActiveDegreeEffect(state, "control_per_season") or 0
    if degreeControlGain > 0 then
        for _, r in ipairs(state.regions) do
            if r.type == "capital" then
                r.control = math.min(100, (r.control or 0) + degreeControlGain)
            end
        end
    end

    -- A4 民政主管专精：spec_passive_control —— 每季所有地区控制度被动增长（上限 5 点）
    local specPassiveControl = GameState.GetModifierValue(state, "spec_passive_control")
    if specPassiveControl > 0 then
        local gain = math.floor(specPassiveControl)
        if gain > 0 then
            for _, r in ipairs(state.regions) do
                r.control = math.min(100, (r.control or 0) + gain)
            end
        end
    end

    -- ========================================
    -- 阶段 5: 武装士气衰减
    -- ========================================
    -- 军务主管加成：减少衰减量（而非全量衰减后再加性恢复）
    local milChiefBonus = GameState.GetPositionBonus(state, "military_chief")
    local decayAmount = Balance.MILITARY.morale_decay  -- 负值，如 -2
    -- 家族天赋：铁腕治军（morale_decay_mult）—— 衰减量乘以系数（0.50 = 衰减减半）
    local traitMoraleMult = GameState.GetActiveTraitEffect and GameState.GetActiveTraitEffect(state, "morale_decay_mult") or 0
    if traitMoraleMult > 0 then
        decayAmount = math.floor(decayAmount * traitMoraleMult)  -- 负数 × 正小数，向零取整
    end
    if milChiefBonus > 0 then
        -- 主管减缓衰减：每点 bonus 减少衰减 1 点（向下取整）
        local reduction = math.floor(milChiefBonus * 1.0)
        decayAmount = math.min(0, decayAmount + reduction)  -- 确保不会变成正值
    end
    state.military.morale = math.max(0, math.min(100,
        state.military.morale + decayAmount))
    -- 军务主管满配独有：精锐操练，每季度自动恢复 +3 士气
    if GameState.HasExcellentPosition(state, "military_chief") then
        state.military.morale = math.min(100, state.military.morale + 3)
    end

    -- ========================================
    -- 阶段 6: AI 势力更新
    -- ========================================
    for _, faction in ipairs(state.ai_factions) do
        local aiConfig = Balance.AI[faction.type]
        if aiConfig then
            if faction.defeated then goto continue_faction end
            -- 攻击冷却递减（每季 -1）
            if faction.attack_cooldown and faction.attack_cooldown > 0 then
                faction.attack_cooldown = faction.attack_cooldown - 1
            end
            -- ── 瘫痪状态检测 ──
            local colCfg = Balance.AI.collapse
            if not faction.collapsed then
                -- 检查是否应该进入瘫痪
                if faction.power <= colCfg.power_threshold
                    and faction.cash <= colCfg.cash_threshold then
                    -- 记录崩溃前战力，用于正比恢复计算
                    faction.pre_collapse_power = math.max(faction.power or 0, 1)
                    faction.collapsed = true
                    faction.collapsed_seasons = 0
                    GameState.AddLog(state, string.format(
                        "💀 %s 势力崩溃，陷入瘫痪！", faction.name))
                    table.insert(report.ai_changes,
                        string.format("%s 势力崩溃，已瘫痪", faction.name))
                end
            end

            if faction.collapsed then
                -- 瘫痪期间：慢速恢复 power，存在度衰减
                faction.collapsed_seasons = (faction.collapsed_seasons or 0) + 1
                -- 慢速 power 恢复
                if faction.power < 100 then
                    faction.power = math.min(100,
                        faction.power + (colCfg.collapsed_power_gain or 1))
                end
                -- 地区存在度衰减
                for _, r in ipairs(state.regions or {}) do
                    if r.ai_presence and r.ai_presence[faction.id] then
                        local p = r.ai_presence[faction.id]
                        if p > 0 then
                            r.ai_presence[faction.id] = math.max(0,
                                p - (colCfg.presence_decay or 5))
                        end
                    end
                end
                -- 瘫痪期间态度缓慢回暖（被打服了）
                if faction.attitude < 0 then
                    faction.attitude = math.min(0, faction.attitude + 3)
                end
                -- 到达恢复期限：注入资源，解除瘫痪
                -- 玩家在其区域保持高控制度（≥60）时恢复时间延长至9季
                local recoverySeasonsNeeded = colCfg.recovery_seasons or 6
                local playerHighControl = false
                for _, r in ipairs(state.regions or {}) do
                    if (r.ai_presence and (r.ai_presence[faction.id] or 0) > 0)
                        and (r.control or 0) >= 60 then
                        playerHighControl = true
                        break
                    end
                end
                if playerHighControl then recoverySeasonsNeeded = 9 end
                if faction.collapsed_seasons >= recoverySeasonsNeeded then
                    faction.collapsed = false
                    faction.collapsed_seasons = nil
                    -- 正比恢复：被打越惨，复活越弱；最低 0.3 系数（保证 120 现金 / 6 战力）
                    local recoveryMult = math.max(0.3, (faction.pre_collapse_power or 20) / 100)
                    faction.pre_collapse_power = nil
                    local recoveryCap = 100 + math.floor(math.max(0, (state.year or 1878) - 1878) / 10) * 5
                    faction.cash  = (faction.cash or 0) + math.floor((colCfg.recovery_cash or 400) * recoveryMult)
                    faction.power = math.min(recoveryCap,
                        (faction.power or 0) + math.floor((colCfg.recovery_power or 20) * recoveryMult))
                    GameState.AddLog(state, string.format(
                        "⚡ %s 势力重组，恢复活动！", faction.name))
                    table.insert(report.ai_changes,
                        string.format("%s 从瘫痪中恢复，重新活跃", faction.name))
                end
                -- 瘫痪期间跳过正常 growth / spending / 攻击
                -- 只做态度 clamp
                faction.attitude = math.max(-100, math.min(100, faction.attitude))
                goto continue_faction
            end

            -- ── 正常状态：基础资产增长（难度越高 AI 增长越快）──
            local rate = aiConfig.growth_rate * (diff.ai_growth_mult or 1.0)
            local growth = math.floor(faction.cash * math.max(0, rate))
            faction.cash = faction.cash + growth
            -- 现金上限：防止复利爆炸增长（按时代递增 × 难度系数）
            local cashCap = math.floor((aiConfig.cash_cap or 10000) * (diff.ai_cash_cap_mult or 1.0))
            local eraScaling = Balance.AI.era_scaling
            if eraScaling then
                for i = #eraScaling, 1, -1 do
                    if state.year >= eraScaling[i].year then
                        cashCap = math.floor(cashCap * (eraScaling[i].cash_cap_mul or 1.0))
                        break
                    end
                end
            end
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

            -- 招募封锁倒计时
            if faction.recruit_blocked and faction.recruit_blocked > 0 then
                faction.recruit_blocked = faction.recruit_blocked - 1
                if faction.recruit_blocked <= 0 then
                    faction.recruit_blocked = nil
                    table.insert(report.ai_changes,
                        string.format("%s 的招募渠道已恢复", faction.name))
                end
            end

            -- 势力增长（每季 +2，上限随时代/战况浮动）
            -- 战力上限公式：100 + floor((year-1878)/10)*5，每10年+5点，1946年=134
            local powerCap = 100 + math.floor(math.max(0, (state.year or 1878) - 1878) / 10) * 5
            -- 战时额外加成
            if state.flags and state.flags.at_war then
                powerCap = powerCap + (Balance.AI.war_power_bonus or 20)
            end
            if faction.power < powerCap then
                local powerGain = 2
                -- 战时 AI 势力增长更快
                if state.flags and state.flags.at_war then powerGain = 3 end
                -- 招募被封锁时跳过扩张
                if not faction.recruit_blocked or faction.recruit_blocked <= 0 then
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
                end
                faction.power = math.min(powerCap, faction.power + math.floor(powerGain * (diff.ai_growth_mult or 1.0)))
            end

            -- C2: AI 势力自然衰减（防滚雪球）
            aiConfig = Balance.AI[faction.type] or {}
            local decayRate = aiConfig.power_decay_rate or 0
            if decayRate > 0 and faction.power > 0 then
                local decay = math.floor(faction.power * decayRate)
                if decay >= 1 then
                    faction.power = math.max(0, faction.power - decay)
                end
            end

            -- 协议保护期内 AI 不主动敌对
            if faction.pact_remaining and faction.pact_remaining > 0 then
                faction.pact_remaining = faction.pact_remaining - 1
                if faction.attitude < 10 then faction.attitude = 10 end
            end

            -- C4-2 外交谈判冷却递减
            local cdKey = "negotiate_cd_" .. (faction.id or faction.name or "?")
            state._negotiate_cooldowns = state._negotiate_cooldowns or {}
            if (state._negotiate_cooldowns[cdKey] or 0) > 0 then
                state._negotiate_cooldowns[cdKey] = state._negotiate_cooldowns[cdKey] - 1
            end

            -- 战时外资撤退
            if faction.type == "foreign_capital" and state.flags and state.flags.at_war then
                if math.random() > aiConfig.war_flee_threshold then
                    local fled = math.floor(faction.cash * 0.15)
                    faction.cash = faction.cash - fled
                    faction.power = math.max(0, faction.power - 3)
                    table.insert(report.ai_changes,
                        string.format("%s 因战争局势撤资 %d", faction.name, fled))
                end
            end

            -- ── AI 主动花费现金（预算上限：保留40%现金，按优先级顺序判定）──
            local spend = Balance.AI.spending
            local spendMult = diff.ai_spending_mult or 1.0  -- 高难度时 AI 花费门槛降低
            local budgetCap = math.floor(faction.cash * 0.6)  -- 本季最多花60%
            local budgetSpent = 0
            -- 1) 雇佣兵：power 不足时优先补强（最高优先级）
            if budgetSpent < budgetCap
                and faction.cash >= math.floor((spend.mercenary_cost or 500) / spendMult)
                and faction.cash > (aiConfig.expand_threshold or 600)
                and faction.power < (powerCap - 10)
                and math.random() < (spend.mercenary_chance or 0.25) then
                local cost = spend.mercenary_cost or 500
                faction.cash = faction.cash - cost
                budgetSpent = budgetSpent + cost
                faction.power = math.min(powerCap, faction.power + (spend.mercenary_power or 5))
                table.insert(report.ai_changes,
                    string.format("%s 雇佣了私兵（power +%d）", faction.name, spend.mercenary_power or 5))
            end
            -- 2) 地区压制：态度差时打压玩家控制度（使用专用压制区域选择）
            if budgetSpent < budgetCap
                and faction.attitude < -30
                and faction.cash >= math.floor((spend.suppress_cost or 400) / spendMult)
                and math.random() < (spend.suppress_chance or 0.20) then
                local cost = spend.suppress_cost or 400
                faction.cash = faction.cash - cost
                budgetSpent = budgetSpent + cost
                local targetRegion = PickAISuppressRegion(state, faction)
                if targetRegion then
                    targetRegion.control = math.max(0,
                        (targetRegion.control or 0) + (spend.suppress_control or -3))
                    table.insert(report.ai_changes,
                        string.format("%s 在%s进行了地区压制（控制度 %d）",
                            faction.name, targetRegion.name, spend.suppress_control or -3))
                end
            end
            -- 3) 经济制裁：外资对玩家施加负面修正器
            if budgetSpent < budgetCap
                and faction.type == "foreign_capital"
                and faction.attitude < -40
                and faction.cash >= math.floor((spend.sanction_cost or 600) / spendMult)
                and math.random() < (spend.sanction_chance or 0.15) then
                local cost = spend.sanction_cost or 600
                faction.cash = faction.cash - cost
                budgetSpent = budgetSpent + cost
                GameState.AddModifier(state, "foreign_sanction", "income_mod", -0.10, 3)
                table.insert(report.ai_changes,
                    string.format("%s 对家族实施了经济制裁（收入 -10%%，持续3季）", faction.name))
            end
            -- 4) 矿价打压：外资压低金铜矿产品价格（先于通胀）
            if budgetSpent < budgetCap
                and faction.type == "foreign_capital"
                and faction.attitude < -35
                and faction.cash >= math.floor((spend.mine_price_cost or 700) / spendMult)
                and math.random() < (spend.mine_price_chance or 0.15) then
                local cost = spend.mine_price_cost or 700
                faction.cash = faction.cash - cost
                budgetSpent = budgetSpent + cost
                local priceMod = spend.mine_price_mod or -0.15
                local priceDur = spend.mine_price_duration or 3
                GameState.AddModifier(state, "foreign_gold_dump",
                    "gold_price_mod", priceMod, priceDur)
                GameState.AddModifier(state, "foreign_copper_dump",
                    "copper_price_mod", priceMod, priceDur)
                table.insert(report.ai_changes,
                    string.format("%s 压低了金铜市场价格（%.0f%%，持续%d季）",
                        faction.name, priceMod * 100, priceDur))
            end
            -- 5) 通胀操控：最激进，最后判定
            if budgetSpent < budgetCap
                and faction.type == "foreign_capital"
                and faction.attitude < -50
                and faction.cash >= math.floor((spend.inflate_cost or 800) / spendMult)
                and math.random() < (spend.inflate_chance or 0.12) then
                local cost = spend.inflate_cost or 800
                faction.cash = faction.cash - cost
                budgetSpent = budgetSpent + cost  -- luacheck: ignore
                GameState.AddModifier(state, "foreign_inflate",
                    "inflation_drift", spend.inflate_drift or 0.012, spend.inflate_duration or 4)
                table.insert(report.ai_changes,
                    string.format("%s 操纵了货币供应，推高通胀（+%.1f%%/季，持续%d季）",
                        faction.name, (spend.inflate_drift or 0.012) * 100, spend.inflate_duration or 4))
            end

            -- ── C4-2 三层态度系统：负向触发器（难度越高 AI 敌意增长越快）──
            local aggrMult = diff.ai_aggression_mult or 1.0
            local BSt = Balance.AI.structural or {}
            local BAr = Balance.AI.arrogance or {}

            -- ── 层 1：结构性（随玩家成功自动触发，数值降低）──
            -- 1a) 经济嫉妒（玩家现金 > AI × 1.5） → -2/季（原 -3）
            local envyMult = BSt.economic_envy_mult or 1.5
            local envyDecay = BSt.economic_envy_decay or 2
            if state.cash > (faction.cash or 0) * envyMult then
                faction.attitude = math.max(-100, faction.attitude - math.ceil(envyDecay * aggrMult))
            end
            -- 1b) 军事威胁（卫队 > 20 且 AI power < 50） → -2/季
            local threatGuards = BSt.military_threat_guards or 20
            local threatPower  = BSt.military_threat_power or 50
            local threatDecay  = BSt.military_threat_decay or 2
            if state.military.guards > threatGuards and faction.power < threatPower then
                faction.attitude = math.max(-100, faction.attitude - math.ceil(threatDecay * aggrMult))
            end
            -- 1c) 势力扩张（矿山 ≥ 5） → -1/季（不变）
            local minesThreshold = BSt.mines_threshold or 5
            local minesDecay     = BSt.mines_decay or 1
            if #state.mines >= minesThreshold then
                faction.attitude = math.max(-100, faction.attitude - math.ceil(minesDecay * aggrMult))
            end

            -- ── 层 2：行为性（一次性惩罚，在占领/制裁发生时由外部调用触发，这里不重复） ──
            -- （见 Expedition.Occupy → faction 态度 -8；ui_action_modals 制裁 → 态度 -5）

            -- ── 层 3：自傲（AI 自身强大时的傲慢，阈值提升至 80） ──
            local arrogThreshold = BAr.power_threshold or 80
            local arrogDecay     = BAr.decay_per_season or 1
            local arrogFloor     = BAr.attitude_floor or -50
            if faction.power >= arrogThreshold and faction.attitude > arrogFloor then
                faction.attitude = faction.attitude - math.ceil(arrogDecay * aggrMult)
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
            -- 9) local_relations 修正器：事件赋予的地方关系加成/惩罚
            local localRelMod = GameState.GetModifierValue(state, "local_relations")
            if localRelMod ~= 0 then
                -- 每季按修正器值的 1/4 影响态度（修正器为累积总值，分散到每季）
                local relEffect = math.floor(localRelMod * 0.25 + 0.5)
                if relEffect ~= 0 then
                    faction.attitude = faction.attitude + relEffect
                end
            end

            -- 最终 clamp
            faction.attitude = math.max(-100, math.min(100, faction.attitude))
        end
        ::continue_faction::
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
    for _, faction in ipairs(state.ai_factions or {}) do
        CheckFactionDefeat(state, faction, report)
    end
    MapTilesData.SyncTilesFromRegions(state)

    -- ========================================
    -- 阶段 6.6: 远征系统结算
    -- 活跃远征推进 → 占领收入/维护 → HP恢复 → 侵略值衰减 → 制裁倒计时
    -- ========================================
    -- C2 外交路线每季结算（与军事远征独立，不需要幕后执政解锁）
    Expedition.TickDiplomacy(state)

    if Expedition.CanDoExpedition(state) then
        -- 推进活跃远征（造成伤害，HP归零→完成判定）
        local tickReports = Expedition.TickActiveExpeditions(state)
        if tickReports and #tickReports > 0 then
            report.expedition_tick = tickReports
        end

        local expReport = Expedition.SettleTurn(state)
        Expedition.TickCountryHP(state)

        -- 制裁倒计时
        if state.expeditions.under_sanction then
            state.expeditions.sanction_remaining = (state.expeditions.sanction_remaining or 0) - 1
            if state.expeditions.sanction_remaining <= 0 then
                state.expeditions.under_sanction = false
                state.expeditions.sanction_remaining = 0
                GameState.AddLog(state, "⚖ 列强制裁解除，远征行动恢复")
            end
        end

        -- 制裁检查
        if Expedition.CheckSanction(state) then
            table.insert(report.ai_changes, "⚠ 侵略值过高，列强正在酝酿制裁")
        end

        if expReport then
            report.expedition_settlement = expReport
        end
    end

    -- ========================================
    -- 阶段 6.65: 商业远征结算
    -- 活跃远征推进 → 商站收入/维护 → 市场壁垒恢复 → 贸易制裁
    -- ========================================
    if Venture.CanDoVenture(state) then
        -- 推进活跃商业远征（扣投资费、渗透壁垒、完成判定）
        local ventureTickReports = Venture.TickActiveVentures(state)
        if ventureTickReports and #ventureTickReports > 0 then
            report.venture_tick = ventureTickReports
        end

        -- A3: 将商业危机事件推入事件队列（触发弹窗）
        local pendingCrises = state.ventures._pending_crisis
        if pendingCrises and #pendingCrises > 0 then
            -- 注入 ctx 到事件 options 的 custom 闭包所需路径
            -- events.lua ApplyOption 会将 event._ctx 作为第二参数传入 effects.custom
            for _, crisis in ipairs(pendingCrises) do
                -- 将 _ctx 改写为 options 内部 custom 可读取的格式
                for _, opt in ipairs(crisis.options or {}) do
                    if opt.effects and opt.effects.custom then
                        local originalFn = opt.effects.custom
                        local capturedCtx = crisis._ctx
                        opt.effects.custom = function(st, _)
                            originalFn(st, capturedCtx)
                        end
                    end
                end
                crisis._ctx = nil
            end
            Events.Enqueue(state, pendingCrises)
            state.ventures._pending_crisis = {}
        end

        -- 商站收入/维护结算 + 紧张度衰减 + 制裁倒计时/触发
        local ventureReport = Venture.SettleTurn(state)

        -- 市场壁垒自然恢复（未被投资的国家）
        Venture.TickMarketBarriers(state)

        if ventureReport then
            report.venture_settlement = ventureReport
            -- 制裁事件推送到 AI 变化列表
            if ventureReport.sanction_triggered then
                table.insert(report.ai_changes, "⚠ 市场紧张度过高，列强发起贸易制裁！")
            end
            if ventureReport.sanction_lifted then
                table.insert(report.ai_changes, "⚖ 贸易制裁已解除，商业活动恢复正常")
            end
        end
    end

    -- ========================================
    -- 阶段 6.7: 大国博弈系统更新
    -- 历史漂移 → 继承处理 → 征服执行 → 抵抗增长 → 本地AI联动
    -- ========================================
    local gpReport = GrandPowers.Tick(state)
    if gpReport then
        -- 历史快讯推送（A.2）：将最重要的世界事件作为专属消息类型推送
        if gpReport.headline then
            local yearQ = string.format("%dQ%d", state.year, state.quarter)
            state.turn_messages = state.turn_messages or {}
            table.insert(state.turn_messages, {
                text = string.format("📰 %s: %s", yearQ, gpReport.headline),
                type = "world_news",
            })
        end
        for _, msg in ipairs(gpReport.conquest_msgs or {}) do
            table.insert(report.ai_changes, msg)
        end
        for _, msg in ipairs(gpReport.succession_msgs or {}) do
            table.insert(report.ai_changes, msg)
        end
    end

    -- ========================================
    -- 阶段 6.75: C3 大国博弈 — 消费 _incited_wars / 结算 covert_support
    -- ========================================
    do
        -- 消费到期的煽动战争记录
        if state._incited_wars then
            local remaining = {}
            for _, inc in ipairs(state._incited_wars) do
                if (state.turn or 0) >= inc.trigger_turn then
                    -- 找目标地区确认仍在对手主权下
                    local targetCountry = state.europe and state.europe[inc.target]
                    local stillValid = targetCountry and targetCountry.sovereign == inc.defender
                    if stillValid then
                        -- 通过公开接口执行征服（主权变更 + war_fatigue + covert_bonus）
                        local conqReport = { conquest_msgs = {} }
                        GrandPowers.ApplyConquest(state, inc.attacker, inc.target, conqReport)
                        local aLabel = (state.powers[inc.attacker] and state.powers[inc.attacker].label) or inc.attacker
                        local tLabel = (targetCountry and targetCountry.label) or inc.target
                        GameState.AddLog(state, string.format(
                            "C3煽动战争触发：%s 征服了 %s", aLabel, tLabel))
                        table.insert(report.ai_changes, string.format("%s（煽动）征服了 %s", aLabel, tLabel))
                    else
                        GameState.AddLog(state, string.format(
                            "C3煽动战争失效：目标 %s 已无效", inc.target))
                    end

                    -- 30% 概率被双方发现
                    if math.random() < (Balance.GP and Balance.GP.incite_detected_chance or 0.30) then
                        local attLoss = Balance.GP and Balance.GP.incite_detected_att_loss or 40
                        local pA = state.powers[inc.attacker]
                        local pB = state.powers[inc.defender]
                        if pA then pA.attitude_to_player = math.max(-100, (pA.attitude_to_player or 0) - attLoss) end
                        if pB then pB.attitude_to_player = math.max(-100, (pB.attitude_to_player or 0) - attLoss) end
                        GameState.AddLog(state, string.format(
                            "煽动战争阴谋败露！%s、%s 好感各 -%d",
                            (pA and pA.label or inc.attacker),
                            (pB and pB.label or inc.defender), attLoss))
                    end
                else
                    table.insert(remaining, inc)
                end
            end
            state._incited_wars = remaining
        end

        -- 结算到期的暗中支援（每季检查：若大国本季完成征服则算"赢"）
        if state._covert_supports then
            local gpConquestThisTurn = {}
            for _, msg in ipairs(report.ai_changes or {}) do
                -- 简单检测：conquest_msgs 含"征服"字样时匹配攻击方
                for powId, _ in pairs(state._covert_supports or {}) do
                    local power = state.powers[powId]
                    if power and msg:find(power.label or powId) and msg:find("征服") then
                        gpConquestThisTurn[powId] = true
                    end
                end
            end
            -- 收集需要结算的 key（避免遍历中修改）
            local toSettle = {}
            for powId, rec in pairs(state._covert_supports) do
                if (state.turn or 0) > (rec.turn or 0) then
                    table.insert(toSettle, powId)
                end
            end
            for _, powId in ipairs(toSettle) do
                PlayerActionsGP.SettleCovertSupport(state, powId, gpConquestThisTurn[powId] or false)
            end
        end
    end

    -- ========================================
    -- 阶段 6.76: C5 文化系统结算
    -- ========================================
    do
        local cultureLogs = Culture.Tick(state)
        for _, msg in ipairs(cultureLogs) do
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
    -- 阶段 6.9: 动态治安等级调整
    -- 根据玩家军事力量 vs AI 区域威胁 + 控制度直接计算目标治安
    -- ========================================
    do
        -- 记录旧值用于报告
        local oldSecurity = {}
        for _, r in ipairs(state.regions or {}) do
            oldSecurity[r.id] = r.security or 3
        end
        -- 直接计算目标治安
        GameState.RecalcSecurity(state)
        -- 生成变化报告
        for _, r in ipairs(state.regions or {}) do
            local old = oldSecurity[r.id] or 3
            if r.security ~= old then
                local dirText = r.security > old and "改善" or "恶化"
                local msg = string.format("%s 治安%s：%s → %s",
                    r.name, dirText,
                    RegionsData.GetSecurityText(old),
                    RegionsData.GetSecurityText(r.security))
                table.insert(report.ai_changes, msg)
            end
        end
    end

    -- ========================================
    -- 阶段 7: 劳工满意度
    -- ========================================
    -- 工资满足度影响士气
    if state.workers.wage < Balance.WORKERS.base_wage then
        state.workers.morale = math.max(0, state.workers.morale - 5)
        if state.workers.morale < 30 then
            table.insert(report.warnings, "劳工满意度极低，可能引发罢工！")
        end
    else
        -- 工资正常，士气缓慢恢复
        state.workers.morale = math.min(100, state.workers.morale + 1)
    end

    -- ========================================
    -- 阶段 8: 家族培养进度
    -- ========================================
    for _, member in ipairs((state.family and state.family.members) or {}) do
        if member.status == "disabled" and (member.disabled_turns or 0) > 0 then
            member.disabled_turns = member.disabled_turns - 1
            if member.disabled_turns <= 0 then
                member.status = "active"
                member.disabled_turns = 0
                table.insert(report.warnings, member.name .. " 已恢复行动")
            end
        end
        -- 上岗适应期递减
        if (member.onboarding_remaining or 0) > 0 then
            member.onboarding_remaining = member.onboarding_remaining - 1
            if member.onboarding_remaining <= 0 then
                member.onboarding_remaining = 0
                if member.position then
                    local posName = member.position
                    for _, p in ipairs(Config.POSITIONS or {}) do
                        if p.id == member.position then posName = p.name; break end
                    end
                    table.insert(report.warnings,
                        string.format("%s 已适应%s岗位，全额加成生效", member.name, posName))
                end
            end
        end
        -- 下岗冷却CD递减
        if (member.cooldown_turns or 0) > 0 then
            member.cooldown_turns = member.cooldown_turns - 1
            if member.cooldown_turns <= 0 then
                member.cooldown_turns = 0
            end
        end
    end

    -- ── 年龄增长与退休检查 ──
    -- 每年第 1 季度：全体成员 age+1；达到退休年龄则强制退休
    if state.quarter == 1 then
        local retireAge = Balance.FAMILY.retirement_age or 60
        local warnAge   = Balance.FAMILY.retirement_warning_age or 55
        local membersToRetire = {}
        for _, member in ipairs((state.family and state.family.members) or {}) do
            member.age = (member.age or 30) + 1
            if member.age >= retireAge then
                table.insert(membersToRetire, member.id)
            elseif member.age >= warnAge then
                table.insert(report.warnings,
                    string.format("%s 已 %d 岁，将在 %d 年后退休",
                        member.name, member.age, retireAge - member.age))
            end
        end
        -- 反向遍历移除退休成员（避免索引混乱）
        for i = #membersToRetire, 1, -1 do
            local ok, name = GameState.RetireFamilyMember(state, membersToRetire[i])
            if ok then
                table.insert(report.warnings,
                    string.format("🎖 %s 年满退休，光荣离开家族核心圈", name))
            end
        end
    end

    -- ── P1: 低忠诚事件系统 ──
    -- 触发条件：在岗成员 loyalty ≤ 4
    -- 概率：(5 - loyalty) × 5%
    -- 事件池：消极怠工(40%), 泄露情报(30%), 携款潜逃(20%), 投靠对手(10%, loyalty ≤ 2)
    do
        local FamiliesData = require("data.families_data")
        local membersToRemove = {}  -- 收集需要移除的成员id（避免遍历中删除）
        for _, member in ipairs((state.family and state.family.members) or {}) do
            if member.status == "active" and member.position then
                local loyalty = FamiliesData.GetHiddenValue(member, "loyalty")
                if loyalty <= 4 then
                    local chance = (5 - loyalty) * 0.05
                    if math.random() < chance then
                        -- 按权重选事件
                        local roll = math.random(100)
                        if loyalty <= 2 and roll <= 10 then
                            -- 投靠对手（10%，仅 loyalty ≤ 2）
                            table.insert(membersToRemove, member.id)
                            table.insert(report.warnings,
                                string.format("⚠ %s 忠诚极低，投靠了对手势力，永久离队！", member.name))
                            GameState.AddLog(state,
                                string.format("[家族危机] %s 投靠对手，携资出走", member.name))
                            -- 扣除部分现金模拟携款
                            local stolen = math.floor(state.cash * 0.05)
                            state.cash = math.max(0, state.cash - stolen)
                            if stolen > 0 then
                                table.insert(report.warnings,
                                    string.format("  携走 %d 现金", stolen))
                            end
                        elseif roll <= 30 then
                            -- 携款潜逃（20%）
                            local stolen = math.floor(state.cash * 0.03)
                            state.cash = math.max(0, state.cash - stolen)
                            table.insert(report.warnings,
                                string.format("⚠ %s 携款潜逃，损失 %d 现金（已追回岗位）",
                                    member.name, stolen))
                            GameState.AddLog(state,
                                string.format("[家族危机] %s 携款潜逃 %d 克朗", member.name, stolen))
                        elseif roll <= 60 then
                            -- 泄露情报（30%）
                            -- 随机增加一个AI势力的态度
                            local factions = state.ai_factions or {}
                            if #factions > 0 then
                                local f = factions[math.random(#factions)]
                                f.attitude = math.min(100, (f.attitude or 0) + 5)
                                table.insert(report.warnings,
                                    string.format("⚠ %s 向 %s 泄露了情报",
                                        member.name, f.name))
                                GameState.AddLog(state,
                                    string.format("[家族危机] %s 泄露情报给 %s",
                                        member.name, f.name))
                            end
                        else
                            -- 消极怠工（40%）
                            member.status = "disabled"
                            member.disabled_turns = 1
                            member.position = nil
                            table.insert(report.warnings,
                                string.format("⚠ %s 消极怠工，暂时失能1季",
                                    member.name))
                            GameState.AddLog(state,
                                string.format("[家族危机] %s 消极怠工，失能1季",
                                    member.name))
                        end
                    end
                end
            end
        end
        -- 处理需要永久移除的成员
        for _, mid in ipairs(membersToRemove) do
            GameState.RemoveFamilyMember(state, mid)
        end
    end

    -- ── 缺陷：体弱多病 —— 55岁后每季概率暂离 ──
    do
        local FamiliesData = require("data.families_data")
        for _, member in ipairs((state.family and state.family.members) or {}) do
            if member.status == "active" and member.flaw then
                local sickChance = GameState.GetMemberFlawEffect(member, "sick_chance_after_55")
                if sickChance > 0 and (member.age or 0) >= 55 then
                    if math.random() < sickChance then
                        member.status = "disabled"
                        member.disabled_turns = 1
                        if member.position then
                            member.position = nil
                            member.onboarding_remaining = 0
                        end
                        table.insert(report.warnings,
                            string.format("🤒 %s 因体弱多病暂时卧床，失能 1 季", member.name))
                        GameState.AddLog(state,
                            string.format("[家族] %s 因病暂离岗位 1 季", member.name))
                    end
                end
            end
        end
    end

    -- ── 缺陷：惹是生非 —— 每季概率触发外交事件 ──
    do
        for _, member in ipairs((state.family and state.family.members) or {}) do
            if member.status == "active" and member.position and member.flaw then
                local incidentChance = GameState.GetMemberFlawEffect(member, "diplomacy_incident_chance")
                if incidentChance > 0 and math.random() < incidentChance then
                    -- 随机降低一个 AI 势力的好感
                    local factions = state.ai_factions or {}
                    if #factions > 0 then
                        local f = factions[math.random(#factions)]
                        f.attitude = math.max(-100, (f.attitude or 0) - 3)
                        table.insert(report.warnings,
                            string.format("⚡ %s 惹是生非，导致与 %s 关系恶化",
                                member.name, f.name))
                        GameState.AddLog(state,
                            string.format("[家族] %s 引发外交事件，%s 态度 -3",
                                member.name, f.name))
                    end
                end
            end
        end
    end

    if state.family.training then
        state.family.training.progress = state.family.training.progress + 1
        if state.family.training.progress >= state.family.training.total then
            -- 培养完成：标记可重随10次（看广告或免广告卡）
            state.family.training.member_template.reroll_available = 10
            table.insert(state.family.members, state.family.training.member_template)
            GameState.AddLog(state, string.format("新成员 %s 加入家族！",
                state.family.training.member_template.name))
            table.insert(report.warnings,
                "新家族成员 " .. state.family.training.member_template.name .. " 培养完成！")
            state.family.training = nil
        end
    end

    -- ── 大学进修进度 ──
    if state.family.university and #state.family.university > 0 then
        local FamiliesData = require("data.families_data")
        local completed = {}
        for i, u in ipairs(state.family.university) do
            u.progress = u.progress + 1
            if u.progress >= u.total then
                table.insert(completed, i)
                -- 查找成员，授予学位和属性加成
                for _, m in ipairs(state.family.members) do
                    if m.id == u.member_id then
                        m.degrees = m.degrees or {}
                        table.insert(m.degrees, u.degree_id)
                        -- 应用属性加成
                        local degreeDef = FamiliesData.GetDegreeDef(u.degree_id)
                        if degreeDef and degreeDef.attr_bonus then
                            for attr, bonus in pairs(degreeDef.attr_bonus) do
                                m.attrs[attr] = (m.attrs[attr] or 0) + bonus
                            end
                        end
                        table.insert(report.warnings,
                            string.format("🎓 %s 完成「%s」学位！",
                                m.name, degreeDef and degreeDef.name or u.degree_id))
                        GameState.AddLog(state, string.format(
                            "%s 获得「%s」学位，属性提升",
                            m.name, degreeDef and degreeDef.name or u.degree_id))
                        break
                    end
                end
            end
        end
        -- 反向移除已完成的进修记录
        for i = #completed, 1, -1 do
            table.remove(state.family.university, completed[i])
        end
    end

    -- ========================================
    -- 阶段 8.5: 探矿进度
    -- ========================================
    if state.prospecting then
        state.prospecting.progress = state.prospecting.progress + 1
        if state.prospecting.progress >= state.prospecting.total then
            local chance = state.prospecting.success_chance
            local roll = math.random()
            if roll <= chance then
                -- 成功：生成备用矿
                local cfg = Balance.MINE.prospect
                local reserve = math.random(cfg.reserve_min, cfg.reserve_max)
                local cnt = (state.prospect_success_count or 0) + 1
                local id = "prospect_" .. cnt .. "_q" .. (state.quarter or 0)
                state.prospect_reserves = state.prospect_reserves or {}
                table.insert(state.prospect_reserves, {
                    id = id,
                    name = "探明矿脉 #" .. cnt,
                    reserve = reserve,
                    initial_reserve = reserve,
                })
                state.prospect_success_count = cnt
                GameState.AddLog(state, string.format(
                    "[矿业] 探矿成功！发现新矿脉（储量 %d），已加入备用", reserve))
                table.insert(report.warnings, "探矿成功！发现新矿脉（储量 " .. reserve .. "）")
            else
                GameState.AddLog(state, "[矿业] 探矿未果，未发现有价值矿脉")
                table.insert(report.warnings, "探矿未果，未发现有价值矿脉")
            end
            state.prospecting = nil
        end
    end

    -- ========================================
    -- 阶段 8.55: 铜矿探矿进度
    -- ========================================
    if state.copper_prospecting then
        state.copper_prospecting.progress = state.copper_prospecting.progress + 1
        if state.copper_prospecting.progress >= state.copper_prospecting.total then
            local chance = state.copper_prospecting.success_chance
            local roll = math.random()
            if roll <= chance then
                local cfg = Balance.MINE.copper_prospect
                local added = math.random(cfg.reserve_min, cfg.reserve_max)
                -- 补充到矿区的 copper_reserve
                for _, r in ipairs(state.regions or {}) do
                    if r.type == "mine" and r.resources then
                        r.resources.copper_reserve = (r.resources.copper_reserve or 0) + added
                        break
                    end
                end
                state.copper_prospect_count = (state.copper_prospect_count or 0) + 1
                GameState.AddLog(state, string.format(
                    "[矿业] 铜矿勘探成功！发现新铜脉（储量 +%d），已注入矿区", added))
                table.insert(report.warnings, "铜矿勘探成功！新增铜储量 " .. added)
            else
                GameState.AddLog(state, "[矿业] 铜矿勘探未果，未发现有价值铜脉")
                table.insert(report.warnings, "铜矿勘探未果")
            end
            state.copper_prospecting = nil
        end
    end

    -- ========================================
    -- 阶段 8.56: 煤矿探矿进度
    -- ========================================
    if state.coal_prospecting then
        state.coal_prospecting.progress = state.coal_prospecting.progress + 1
        if state.coal_prospecting.progress >= state.coal_prospecting.total then
            local chance = state.coal_prospecting.success_chance
            local roll = math.random()
            if roll <= chance then
                local cfg = Balance.MINE.coal_prospect
                local added = math.random(cfg.reserve_min, cfg.reserve_max)
                -- 补充到工业区的 coal_reserve
                for _, r in ipairs(state.regions or {}) do
                    if r.type == "industrial" and r.resources then
                        r.resources.coal_reserve = (r.resources.coal_reserve or 0) + added
                        break
                    end
                end
                state.coal_prospect_count = (state.coal_prospect_count or 0) + 1
                GameState.AddLog(state, string.format(
                    "[矿业] 煤矿勘探成功！发现新煤层（储量 +%d），已注入工业区", added))
                table.insert(report.warnings, "煤矿勘探成功！新增煤储量 " .. added)
            else
                GameState.AddLog(state, "[矿业] 煤矿勘探未果，未发现有价值煤层")
                table.insert(report.warnings, "煤矿勘探未果")
            end
            state.coal_prospecting = nil
        end
    end

    -- ========================================
    -- 阶段 8.6: 外国矿侦察进度 & 有效性检查
    -- ========================================
    do
        local ForeignOps = require("systems.foreign_ops")
        ForeignOps.TickScout(state)
        ForeignOps.ValidateActive(state)
    end

    -- ========================================
    -- 阶段 8.9: 称号检查
    -- ========================================
    do
        local Titles = require("systems.titles")
        local newTitles = Titles.Check(state)
        if #newTitles > 0 then
            for _, t in ipairs(newTitles) do
                GameState.AddLog(state, string.format("🏅 获得称号「%s」", t.name))
            end
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
        "采金:%d 产铜:%d 收入:%d 支出:%d 净利:%d 现金:%d",
        report.economy.gold_mined,
        report.economy.copper_mined,
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
    table.insert(lines, string.format("采金 %d | 产铜 %d | 产煤 %d | 收入 %d",
        eco.gold_mined, eco.copper_mined, eco.coal_mined or 0, eco.total_income))
    if (eco.coal_mined or 0) > 0 or (eco.coal_factory_consumed or 0) > 0
        or (eco.coal_industrial_consumed or 0) > 0 or (eco.coal_mine_allocated or 0) > 0
        or (eco.coal_sold or 0) > 0 then
        table.insert(lines, string.format("煤炭 明细：工厂-%d 工业-%d 矿山-%d 售出%d",
            eco.coal_factory_consumed or 0,
            eco.coal_industrial_consumed or 0,
            eco.coal_mine_allocated or 0,
            eco.coal_sold or 0))
    end
    table.insert(lines, string.format("支出 %d (工资%d+军费%d+税%d)",
        eco.total_expense, eco.worker_expense, eco.military_expense,
        eco.tax))
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
