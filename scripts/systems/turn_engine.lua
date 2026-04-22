-- ============================================================================
-- 回合引擎：管理结算→事件→行动→回合结束的完整流程
-- ============================================================================

local Balance = require("data.balance")
local GameState = require("game_state")
local Economy = require("systems.economy")
local Events = require("systems.events")

local BV = Balance.VICTORY

local TurnEngine = {}

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
    -- 阶段 1: 经济结算
    -- ========================================
    state.phase = "settlement"
    report.economy = Economy.Settle(state)

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
    -- 阶段 3: 胜利点结算
    -- ========================================
    local oldEco = state.victory.economic
    local oldMil = state.victory.military

    -- 经济胜利点
    local ecoDelta = 0
    if state.cash > 0 then
        ecoDelta = ecoDelta + math.floor(state.cash / BV.economic.cash_divisor)
    end
    ecoDelta = ecoDelta + state.gold * BV.economic.gold_multiplier

    -- 军事胜利点
    local milDelta = 0
    milDelta = milDelta + math.floor(state.military.guards * BV.military.guard_multiplier)
    milDelta = milDelta + math.floor(state.military.morale / BV.military.morale_divisor)
    -- 地区控制加成
    for _, r in ipairs(state.regions) do
        milDelta = milDelta + math.floor(r.control / BV.military.control_divisor)
    end

    state.victory.economic = state.victory.economic + ecoDelta
    state.victory.military = state.victory.military + milDelta

    -- 限制上限避免过快
    state.victory.economic = math.min(state.victory.economic, BV.threshold + 20)
    state.victory.military = math.min(state.victory.military, BV.threshold + 20)

    report.victory_delta.economic = state.victory.economic - oldEco
    report.victory_delta.military = state.victory.military - oldMil

    -- ========================================
    -- 阶段 4: 修正器推进
    -- ========================================
    GameState.TickModifiers(state)

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
            -- 资产增长
            local growth = math.floor(faction.cash * aiConfig.growth_rate)
            faction.cash = faction.cash + growth

            -- 势力缓慢增长
            if faction.power < 80 then
                faction.power = math.min(100, faction.power + 1)
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

            -- 与玩家的态度随竞争变化
            if state.cash > faction.cash * 1.5 then
                faction.attitude = math.max(-100, faction.attitude - 2)
            end
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
        "采金:%d 售金:%d 收入:%d 支出:%d 净利:%d 现金:%d",
        report.economy.gold_mined,
        report.economy.gold_sold,
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
    table.insert(lines, string.format("采金 %d | 售出 %d | 收入 %d",
        eco.gold_mined, eco.gold_sold, eco.gold_income))
    table.insert(lines, string.format("支出 %d (工资%d+军费%d+补给%d+税%d)",
        eco.total_expense, eco.worker_expense, eco.military_expense,
        eco.supply_expense, eco.tax))

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
