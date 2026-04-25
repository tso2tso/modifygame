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
---@field silver_mined number 本季产银量
---@field silver_sold number 本季售出白银
---@field silver_income number 白银销售收入
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
        silver_mined = 0,
        silver_sold = 0,
        silver_income = 0,
        worker_expense = 0,
        military_expense = 0,
        supply_expense = 0,
        tax = 0,
        total_income = 0,
        total_expense = 0,
        net = 0,
        bankrupt = false,
    }

    -- 通胀乘数（影响出售价）
    local inflation = state.inflation_factor or 1.0

    -- ============================
    -- 1. 矿山产出（金 + 银）
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
            -- 白银副产物：按矿山等级产出（不占 gold_reserve）
            local silverOut = math.floor(BM.base_silver_output
                * (1 + (mine.level - 1) * BM.level_output_bonus))
            if silverOut > 0 then
                state.silver = (state.silver or 0) + silverOut
                report.silver_mined = report.silver_mined + silverOut
            end
        end
    end

    -- ============================
    -- 2. 黄金出售（仅在玩家开启自动出售时执行；默认关闭，由玩家在产业页手动操作）
    -- ============================
    if state.gold_auto_sell then
        local reserveGold = 10
        local sellable = math.max(0, state.gold - reserveGold)
        if sellable > 0 then
            local price = BM.gold_price * inflation
            -- 战时军需利润修正
            local priceModifier = GameState.GetModifierValue(state, "military_industry_profit")
            if priceModifier > 0 then
                price = price * (1 + priceModifier * 0.5)
            end
            price = math.floor(price)
            report.gold_sold = sellable
            report.gold_income = sellable * price
            state.gold = state.gold - sellable
            state.cash = state.cash + report.gold_income
        end
    end

    -- ============================
    -- 2.5 白银出售（保留 0，全量出售）
    -- ============================
    local silverStock = state.silver or 0
    if silverStock > 0 then
        local silverPrice = math.floor(BM.silver_price * inflation)
        report.silver_sold = silverStock
        report.silver_income = silverStock * silverPrice
        state.silver = 0
        state.cash = state.cash + report.silver_income
    end

    -- ============================
    -- 3. 工资支出（通胀作用于所有人力成本）
    -- ============================
    report.worker_expense = math.floor(state.workers.hired * state.workers.wage * inflation)
    report.military_expense = math.floor(state.military.guards * state.military.wage * inflation)
    local supplyDiscount = 1.0 - (state.finance_supply_discount or 0)
    report.supply_expense = math.floor(state.military.guards * BMI.supply_per_guard
        * BMI.supply_cost * inflation * supplyDiscount)

    -- 金融网络被动收入
    report.finance_income = state.finance_passive_income or 0
    if report.finance_income > 0 then
        state.cash = state.cash + report.finance_income
    end

    -- 被动地区影响力增益（科技"印刷宣传"等）
    if state.passive_influence and state.passive_influence ~= 0 then
        for _, r in ipairs(state.regions) do
            r.influence = (r.influence or 0) + state.passive_influence
        end
    end

    -- ============================
    -- 3.5 地区控制度被动收入 & AI 存在度负面效果
    -- ============================
    report.region_income = 0
    report.ai_penalty = 0
    for _, r in ipairs(state.regions) do
        -- ── 矿区 (mine): 控制度高 → 安全奖励减少事故概率（通过 security +1 间接体现）
        -- 这里通过直接经济加成体现
        if r.type == "mine" then
            -- 控制度 >= 50%: 每 10% 超出部分给 +20 被动收入
            if r.control >= 50 then
                local bonus = math.floor((r.control - 50) / 10) * 20
                report.region_income = report.region_income + bonus
            end
        end
        -- ── 工业城 (industrial): 控制度 >= 40% 时获得贸易收入
        if r.type == "industrial" then
            if r.control >= 40 then
                local tradeIncome = math.floor(r.control * 1.5)
                report.region_income = report.region_income + tradeIncome
            end
        end
        -- ── 首都 (capital): 控制度 >= 30% 时减税
        -- 减税效果在下方税率计算中体现

        -- ── AI 存在度负面效果 ──
        if r.ai_presence then
            for _, presence in pairs(r.ai_presence) do
                if presence >= 50 then
                    -- AI 高存在度：每 10% 超出 50 的部分，额外支出 +15
                    local penalty = math.floor((presence - 50) / 10) * 15
                    report.ai_penalty = report.ai_penalty + penalty
                end
            end
        end
    end

    -- 地区被动收入加到现金
    if report.region_income > 0 then
        state.cash = state.cash + report.region_income
        report.total_income = (report.total_income or 0) + report.region_income
    end

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
    -- 首都控制度 >= 30% 减税：每 10% 超出部分减 1% 税率
    for _, r in ipairs(state.regions) do
        if r.type == "capital" and r.control >= 30 then
            local taxReduction = math.floor((r.control - 30) / 10) * 0.01
            taxRate = taxRate - taxReduction
        end
    end
    taxRate = math.max(0, taxRate)
    report.tax = math.max(0, math.floor(state.cash * taxRate))

    -- ============================
    -- 5. 汇总并扣款
    -- ============================
    -- 注意：gold_income / silver_income / region_income 已在步骤 2-3.5 加到 state.cash，此处只减支出
    report.total_income = report.gold_income + report.silver_income + report.region_income
        + report.finance_income
    report.total_expense = report.worker_expense + report.military_expense
        + report.supply_expense + report.tax + report.ai_penalty
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
            state.emergency_gold_sold = true
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
    local inflation = state.inflation_factor or 1.0
    local income = 0
    for _, mine in ipairs(state.mines) do
        if mine.active then
            local goldOut = Economy._CalcMineOutput(state, mine)
            income = income + math.floor(goldOut * BM.gold_price * inflation)
            local silverOut = math.floor(BM.base_silver_output
                * (1 + (mine.level - 1) * BM.level_output_bonus))
            income = income + math.floor(silverOut * BM.silver_price * inflation)
        end
    end

    local expense = math.floor(state.workers.hired * state.workers.wage * inflation)
        + math.floor(state.military.guards * state.military.wage * inflation)
        + math.floor(state.military.guards * BMI.supply_per_guard * BMI.supply_cost * inflation)

    return income, expense
end

return Economy
