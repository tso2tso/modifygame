-- ============================================================================
-- 经济系统：矿业收入、工资支出、税收、通胀
-- ============================================================================

local Balance = require("data.balance")
local GameState = require("game_state")

local BM = Balance.MINE
local BW = Balance.WORKERS
local BMI = Balance.MILITARY
local BE = Balance.ECONOMY

local Economy = {}

--- 单季度经济结算结果
---@class EconomyReport
---@field gold_mined number 本季采金量
---@field gold_sold number 本季售出黄金
---@field gold_income number 黄金销售收入
---@field worker_expense number 工人工资
---@field military_expense number 军事开支
---@field supply_expense number 补给开支
---@field tax number 税收
---@field total_income number 总收入
---@field total_expense number 总支出
---@field net number 净收入
---@field bankrupt boolean 是否破产

--- 执行单季经济结算
---@param state table
---@return EconomyReport report
function Economy.Settle(state)
    local report = {
        gold_mined = 0,
        gold_sold = 0,
        gold_income = 0,
        worker_expense = 0,
        military_expense = 0,
        supply_expense = 0,
        tax = 0,
        total_income = 0,
        total_expense = 0,
        net = 0,
        bankrupt = false,
    }

    -- ============================
    -- 1. 矿山产出
    -- ============================
    for _, mine in ipairs(state.mines) do
        if mine.active then
            local output = Economy._CalcMineOutput(state, mine)
            -- 检查储量
            local region = GameState.GetRegion(state, mine.region_id)
            if region and region.resources.gold_reserve > 0 then
                output = math.min(output, region.resources.gold_reserve)
                region.resources.gold_reserve = region.resources.gold_reserve - output
                state.gold = state.gold + output
                report.gold_mined = report.gold_mined + output
            end
        end
    end

    -- ============================
    -- 2. 黄金出售（保留策略：保留 10 单位）
    -- ============================
    local reserveGold = 10
    local sellable = math.max(0, state.gold - reserveGold)
    if sellable > 0 then
        local price = BM.gold_price
        -- 战时修正
        local priceModifier = GameState.GetModifierValue(state, "military_industry_profit")
        if priceModifier > 0 then
            price = math.floor(price * (1 + priceModifier * 0.5))
        end
        report.gold_sold = sellable
        report.gold_income = sellable * price
        state.gold = state.gold - sellable
        state.cash = state.cash + report.gold_income
    end

    -- ============================
    -- 3. 工资支出
    -- ============================
    report.worker_expense = state.workers.hired * state.workers.wage
    report.military_expense = state.military.guards * state.military.wage
    report.supply_expense = state.military.guards * BMI.supply_per_guard * BMI.supply_cost

    -- ============================
    -- 4. 税收
    -- ============================
    local taxRate = BE.base_tax_rate
    if state.flags.at_war then
        taxRate = BE.war_tax_rate
    end
    -- 事件修正
    local taxMod = GameState.GetModifierValue(state, "tax_rate")
    taxRate = taxRate + taxMod
    report.tax = math.max(0, math.floor(state.cash * taxRate))

    -- ============================
    -- 5. 汇总并扣款
    -- ============================
    -- 注意：gold_income 已在步骤 2 中加到 state.cash，此处只减支出
    report.total_income = report.gold_income
    report.total_expense = report.worker_expense + report.military_expense
        + report.supply_expense + report.tax
    report.net = report.total_income - report.total_expense

    state.cash = state.cash - report.total_expense

    -- 累计统计
    state.total_income = state.total_income + report.total_income
    state.total_expense = state.total_expense + report.total_expense

    -- ============================
    -- 6. 破产检查
    -- ============================
    if state.cash < 0 then
        report.bankrupt = true
        -- 紧急变卖黄金
        local needed = math.abs(state.cash)
        local sellGold = math.min(state.gold, math.ceil(needed / BM.gold_price))
        if sellGold > 0 then
            state.cash = state.cash + sellGold * BM.gold_price
            state.gold = state.gold - sellGold
            GameState.AddLog(state, string.format(
                "财政危机！紧急变卖 %d 单位黄金。", sellGold))
        end
        -- 仍然为负则归零（债务机制未来添加）
        if state.cash < 0 then
            state.cash = 0
            GameState.AddLog(state, "家族资金耗尽，陷入困境。")
        end
    end

    return report
end

--- 计算单个矿山的产出
---@param state table
---@param mine table
---@return number output 黄金产出量
function Economy._CalcMineOutput(state, mine)
    local base = BM.base_gold_output
    -- 等级加成
    local levelMul = 1.0 + (mine.level - 1) * BM.level_output_bonus
    -- 矿业总监岗位加成
    local posBonus = GameState.GetPositionBonus(state, "mine_director")
    -- 工人加成
    local workerBonus = math.floor(state.workers.hired / BW.workers_per_unit)
    -- 事件修正
    local outputMod = GameState.GetModifierValue(state, "mine_output")

    local total = (base + outputMod) * levelMul * (1 + posBonus) + workerBonus
    return math.max(0, math.floor(total))
end

--- 获取当前季度预估收支
---@param state table
---@return number income, number expense
function Economy.GetEstimate(state)
    local income = 0
    for _, mine in ipairs(state.mines) do
        if mine.active then
            income = income + Economy._CalcMineOutput(state, mine) * BM.gold_price
        end
    end

    local expense = state.workers.hired * state.workers.wage
        + state.military.guards * state.military.wage
        + state.military.guards * BMI.supply_per_guard * BMI.supply_cost

    return income, expense
end

return Economy
