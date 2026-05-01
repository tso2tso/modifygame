-- ============================================================================
-- 经济系统：矿业收入、工资支出、税收、通胀
-- ============================================================================

local Balance = require("data.balance")
local GameState = require("game_state")
local Equipment = require("systems.equipment")

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

    -- 通胀影响名义价格；资产价格修正影响矿山/地产等资本品估值
    local inflation = GameState.GetInflationFactor(state)
    local laborCostFactor = GameState.GetLaborCostFactor(state)
    local civilianDemand = GameState.GetModifierValue(state, "civilian_consumption")
    local transportRisk = math.max(0, GameState.GetModifierValue(state, "transport_risk"))

    -- ============================
    -- 1. 矿山产出（金 + 银）
    -- ============================
    -- 处理产能迁移（上季度标记的 migrating 矿山）
    Economy._ProcessMigrations(state)

    for _, mine in ipairs(state.mines) do
        if mine.active and not mine.migrating then
            local mineReserve = mine.reserve or 0
            local output = Economy._CalcMineOutput(state, mine)
            -- 检查独立储量
            if mineReserve > 0 then
                output = math.min(output, mineReserve)
                mine.reserve = mineReserve - output
                state.gold = state.gold + output
                report.gold_mined = report.gold_mined + output
            end
            -- 白银副产物：按矿山等级产出（消耗 region 共享 silver_reserve）
            local region = GameState.GetRegion(state, mine.region_id)
            local silverOut = math.floor(BM.base_silver_output
                * (1 + (mine.level - 1) * BM.level_output_bonus))
            if silverOut > 0 and region and (region.resources.silver_reserve or 0) > 0 then
                silverOut = math.min(silverOut, region.resources.silver_reserve)
                region.resources.silver_reserve = region.resources.silver_reserve - silverOut
                state.silver = (state.silver or 0) + silverOut
                report.silver_mined = report.silver_mined + silverOut
            end
        end
    end

    -- 同步 region.gold_reserve 为所有矿 reserve 之和（兼容其他引用）
    Economy._SyncRegionGoldReserve(state)

    -- ============================
    -- 1.5 煤炭采集（工业区）
    -- ============================
    report.coal_mined = 0
    for _, r in ipairs(state.regions) do
        if r.type == "industrial" and (r.resources.coal_reserve or 0) > 0 then
            local coalOut = math.floor(BM.base_coal_output * (1 + (r.development - 1) * 0.15))
            coalOut = math.min(coalOut, r.resources.coal_reserve)
            r.resources.coal_reserve = r.resources.coal_reserve - coalOut
            state.coal = (state.coal or 0) + coalOut
            report.coal_mined = report.coal_mined + coalOut
        end
    end

    -- ============================
    -- 2. 黄金出售（仅在玩家开启自动出售时执行；默认关闭，由玩家在产业页手动操作）
    -- ============================
    local railwayBlocked = GameState.GetModifierValue(state, "railway_blocked") > 0
    if state.gold_auto_sell and not railwayBlocked then
        local reserveGold = math.floor(state.gold * 0.1 + 0.5)  -- 保留10%（四舍五入）
        local sellable = math.max(0, state.gold - reserveGold)
        if sellable > 0 then
            local price = BM.gold_price * inflation
            -- 战时军需利润修正
            local priceModifier = GameState.GetModifierValue(state, "military_industry_profit")
            if priceModifier > 0 then
                price = price * (1 + priceModifier * 0.5)
            end
            -- 科技金价加成
            local goldPriceBonus = state.gold_price_bonus or 0
            if goldPriceBonus > 0 then
                price = price * (1 + goldPriceBonus)
            end
            -- 事件独立金价修正
            local goldPriceMod = GameState.GetModifierValue(state, "gold_price_mod")
            if goldPriceMod ~= 0 then
                price = price * (1 + goldPriceMod)
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
        local silverPriceMod = GameState.GetModifierValue(state, "silver_price_mod")
        local silverPrice = math.floor(BM.silver_price * inflation * (1 + silverPriceMod))
        silverPrice = math.max(1, silverPrice)
        report.silver_sold = silverStock
        report.silver_income = silverStock * silverPrice
        state.silver = 0
        state.cash = state.cash + report.silver_income
    end

    -- ============================
    -- 2.6 煤炭出售（全量出售）
    -- ============================
    report.coal_sold = 0
    report.coal_income = 0
    local coalStock = state.coal or 0
    if coalStock > 0 then
        local coalPriceMod = GameState.GetModifierValue(state, "coal_price_mod")
        local coalPrice = math.floor(BM.coal_price * inflation * (1 + coalPriceMod))
        coalPrice = math.max(1, coalPrice)
        report.coal_sold = coalStock
        report.coal_income = coalStock * coalPrice
        state.coal = 0
        state.cash = state.cash + report.coal_income
    end

    -- ============================
    -- 3. 工资支出（通胀作用于所有人力成本）
    -- ============================
    -- 工人雇佣成本（科技折扣）
    local hireCostMul = 1.0 + (state.hire_cost_discount or 0)  -- discount 为负值
    hireCostMul = math.max(0.5, hireCostMul)  -- 最低 50% 成本
    report.worker_expense = math.floor(state.workers.hired * state.workers.wage * laborCostFactor * hireCostMul)
    report.military_expense = math.floor(state.military.guards * state.military.wage * inflation)
    local supplyDiscount = 1.0 - (state.finance_supply_discount or 0)
    local supplyPerGuard = math.max(1, BMI.supply_per_guard - (state.supply_reduction_bonus or 0))
    report.supply_expense = math.floor(state.military.guards * supplyPerGuard
        * BMI.supply_cost * inflation * supplyDiscount * (1 + math.min(0.5, transportRisk)))

    -- 装备维护费 + 兵工厂维护费
    local equipMaint, factoryMaint = Equipment.CalcMaintenanceCost(state)
    report.equip_maintenance = equipMaint
    report.factory_maintenance = factoryMaint
    report.military_expense = report.military_expense + equipMaint + factoryMaint

    -- 金融网络被动收入
    report.finance_income = state.finance_passive_income or 0
    if report.finance_income > 0 then
        state.cash = state.cash + report.finance_income
    end

    -- 贸易被动收入（科技"贸易路线"等）
    report.trade_income = state.trade_passive_income or 0
    if report.trade_income > 0 then
        state.cash = state.cash + report.trade_income
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
                bonus = math.floor(bonus * inflation)
                report.region_income = report.region_income + bonus
            end
        end
        -- ── 工业城 (industrial): 控制度 >= 40% 时获得贸易收入
        if r.type == "industrial" then
            if r.control >= 40 then
                local tradeIncome = math.floor(r.control * 1.5 * inflation * math.max(0.4, 1 + civilianDemand))
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
                    penalty = math.floor(penalty * inflation)
                    report.ai_penalty = report.ai_penalty + penalty
                end
            end
        end
    end

    report.shadow_income = 0
    local shadowIncome = GameState.GetModifierValue(state, "shadow_income")
    if shadowIncome > 0 then
        report.shadow_income = math.floor(shadowIncome * inflation)
        state.cash = state.cash + report.shadow_income
    end

    report.transport_penalty = 0
    if transportRisk > 0 then
        local exposedIncome = report.gold_income + report.silver_income + report.region_income + report.shadow_income
        report.transport_penalty = math.floor(exposedIncome * math.min(0.30, transportRisk * 0.25))
    end

    report.income_mod_adjustment = 0
    local grossIncome = report.gold_income + report.silver_income + (report.coal_income or 0)
        + report.region_income + report.finance_income + (report.trade_income or 0) + report.shadow_income
    local incomeMod = GameState.GetModifierValue(state, "income_mod")
    if incomeMod ~= 0 then
        incomeMod = math.max(-0.75, math.min(1.00, incomeMod))
        report.income_mod_adjustment = math.floor(grossIncome * incomeMod)
        state.cash = state.cash + report.income_mod_adjustment
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
    if state.flags and state.flags.at_war then
        taxRate = BE.war_tax_rate
    end
    -- 事件修正
    local taxMod = GameState.GetModifierValue(state, "tax_rate")
    taxRate = taxRate + taxMod
    taxRate = taxRate
        - GameState.GetModifierValue(state, "legitimacy") * 0.0004
        - GameState.GetModifierValue(state, "political_standing") * 0.0004
        - GameState.GetModifierValue(state, "public_support") * 0.0002
        + GameState.GetModifierValue(state, "corruption_risk") * 0.0005
        + math.max(0, GameState.GetModifierValue(state, "risk")) * 0.0004
        + (state.regulation_pressure or 0) * 0.0008
    -- 首都控制度 >= 30% 减税：每 10% 超出部分减 1% 税率
    for _, r in ipairs(state.regions) do
        if r.type == "capital" and r.control >= 30 then
            local taxReduction = math.floor((r.control - 30) / 10) * 0.01
            taxRate = taxRate - taxReduction
        end
    end
    taxRate = math.max(0, math.min(0.35, taxRate))
    report.tax = math.max(0, math.floor(state.cash * taxRate))

    -- ============================
    -- 5. 汇总并扣款
    -- ============================
    -- 注意：gold_income / silver_income / region_income 已在步骤 2-3.5 加到 state.cash，此处只减支出
    report.total_income = grossIncome + report.income_mod_adjustment
    report.total_expense = report.worker_expense + report.military_expense
        + report.supply_expense + report.tax + report.ai_penalty + report.transport_penalty
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
        local emergencyGoldPrice = math.max(1, math.floor(BM.gold_price * inflation))
        local sellGold = math.min(state.gold, math.ceil(needed / emergencyGoldPrice))
        if sellGold > 0 then
            state.cash = state.cash + sellGold * emergencyGoldPrice
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
    -- 工人加成（含工人效率科技加成）
    local efficiencyMul = 1.0 + (state.worker_efficiency_bonus or 0)
    local workerBonus = math.floor(state.workers.hired / BW.workers_per_unit * efficiencyMul)
    -- 事件修正
    local outputMod = GameState.GetModifierValue(state, "mine_output")
        + (state.mine_output_base_bonus or 0)
        + (mine.output_bonus or 0)

    local total = (base + outputMod) * levelMul * (1 + posBonus) + workerBonus
    -- 科技乘法加成（mine_output_mult）
    local multBonus = (state.mine_output_mult_bonus or 0)
        + GameState.GetModifierValue(state, "mine_output_mult")
    if multBonus ~= 0 then
        total = total * (1 + multBonus)
    end
    return math.max(0, math.floor(total))
end

--- 获取当前季度预估收支
---@param state table
---@return number income, number expense, table details
function Economy.GetEstimate(state)
    local inflation = GameState.GetInflationFactor(state)
    local laborCostFactor = GameState.GetLaborCostFactor(state)
    local income = 0
    local details = {
        gold_potential_income = 0,
        gold_auto_income = 0,
        silver_income = 0,
        coal_income = 0,
        region_income = 0,
        finance_income = state.finance_passive_income or 0,
        trade_income = state.trade_passive_income or 0,
        shadow_income = 0,
        transport_penalty = 0,
        ai_penalty = 0,
        tax = 0,
    }

    -- 金价修正（与 Settle / calcGoldPrice 保持一致）
    local estGoldPrice = BM.gold_price * inflation
    local estPriceModifier = GameState.GetModifierValue(state, "military_industry_profit")
    if estPriceModifier > 0 then
        estGoldPrice = estGoldPrice * (1 + estPriceModifier * 0.5)
    end
    local estGoldPriceBonus = state.gold_price_bonus or 0
    if estGoldPriceBonus > 0 then
        estGoldPrice = estGoldPrice * (1 + estGoldPriceBonus)
    end
    local estGoldPriceMod = GameState.GetModifierValue(state, "gold_price_mod")
    if estGoldPriceMod ~= 0 then
        estGoldPrice = estGoldPrice * (1 + estGoldPriceMod)
    end
    estGoldPrice = math.floor(estGoldPrice)

    local estTotalGoldOut = 0
    for _, mine in ipairs(state.mines) do
        if mine.active and not mine.migrating then
            local mineReserve = mine.reserve or 0
            if mineReserve > 0 then
                local goldOut = Economy._CalcMineOutput(state, mine)
                goldOut = math.min(goldOut, mineReserve)
                details.gold_potential_income = details.gold_potential_income + goldOut * estGoldPrice
                estTotalGoldOut = estTotalGoldOut + goldOut
            end
            -- 白银
            local region = GameState.GetRegion(state, mine.region_id)
            local silverOut = math.floor(BM.base_silver_output
                * (1 + (mine.level - 1) * BM.level_output_bonus))
            if region and (region.resources.silver_reserve or 0) > 0 then
                silverOut = math.min(silverOut, region.resources.silver_reserve)
            else
                silverOut = 0
            end
            local silverPriceMod = GameState.GetModifierValue(state, "silver_price_mod")
            details.silver_income = details.silver_income
                + math.floor(silverOut * BM.silver_price * inflation * (1 + silverPriceMod))
        end
    end
    if state.gold_auto_sell then
        local totalGold = (state.gold or 0) + estTotalGoldOut
        local reserveGold = math.floor(totalGold * 0.1 + 0.5)
        local sellable = math.max(0, totalGold - reserveGold)
        details.gold_auto_income = sellable * estGoldPrice
    end

    -- 煤炭预估
    local coalPriceMod = GameState.GetModifierValue(state, "coal_price_mod")
    local estCoalPrice = math.max(1, math.floor(BM.coal_price * inflation * (1 + coalPriceMod)))
    for _, r in ipairs(state.regions) do
        if r.type == "industrial" and (r.resources.coal_reserve or 0) > 0 then
            local coalOut = math.floor(BM.base_coal_output * (1 + (r.development - 1) * 0.15))
            coalOut = math.min(coalOut, r.resources.coal_reserve)
            details.coal_income = details.coal_income + coalOut * estCoalPrice
        end
    end

    local civilianDemand = GameState.GetModifierValue(state, "civilian_consumption")
    local transportRisk = math.max(0, GameState.GetModifierValue(state, "transport_risk"))
    for _, r in ipairs(state.regions) do
        if r.type == "mine" and r.control >= 50 then
            details.region_income = details.region_income + math.floor(math.floor((r.control - 50) / 10) * 20 * inflation)
        elseif r.type == "industrial" and r.control >= 40 then
            details.region_income = details.region_income
                + math.floor(r.control * 1.5 * inflation * math.max(0.4, 1 + civilianDemand))
        end
    end
    -- AI 存在度负面效果（与 Settle 保持一致）
    for _, r in ipairs(state.regions) do
        if r.ai_presence then
            for _, presence in pairs(r.ai_presence) do
                if presence >= 50 then
                    local penalty = math.floor((presence - 50) / 10) * 15
                    penalty = math.floor(penalty * inflation)
                    details.ai_penalty = details.ai_penalty + penalty
                end
            end
        end
    end

    local shadowIncome = GameState.GetModifierValue(state, "shadow_income")
    if shadowIncome > 0 then
        details.shadow_income = math.floor(shadowIncome * inflation)
    end

    income = details.gold_auto_income + details.silver_income + details.coal_income
        + details.region_income + details.finance_income + details.trade_income + details.shadow_income
    local estimateIncomeMod = GameState.GetModifierValue(state, "income_mod")
    if estimateIncomeMod ~= 0 then
        estimateIncomeMod = math.max(-0.75, math.min(1.00, estimateIncomeMod))
        details.income_mod_adjustment = math.floor(income * estimateIncomeMod)
        income = income + details.income_mod_adjustment
    end

    if transportRisk > 0 then
        details.transport_penalty = math.floor(income * math.min(0.30, transportRisk * 0.25))
    end

    -- 工人工资（含科技折扣，与 Settle 保持一致）
    local estHireCostMul = math.max(0.5, 1.0 + (state.hire_cost_discount or 0))
    local estSupplyDiscount = 1.0 - (state.finance_supply_discount or 0)
    local estSupplyPerGuard = math.max(1, BMI.supply_per_guard - (state.supply_reduction_bonus or 0))
    -- 装备维护费 + 工厂维护费
    local estEquipMaint, estFactoryMaint = Equipment.CalcMaintenanceCost(state)
    details.equip_maintenance = estEquipMaint
    details.factory_maintenance = estFactoryMaint
    local expenseBeforeTax = math.floor(state.workers.hired * state.workers.wage * laborCostFactor * estHireCostMul)
        + math.floor(state.military.guards * state.military.wage * inflation)
        + math.floor(state.military.guards * estSupplyPerGuard * BMI.supply_cost * inflation
            * estSupplyDiscount * (1 + math.min(0.5, transportRisk)))
        + details.transport_penalty
        + estEquipMaint + estFactoryMaint

    local taxRate = BE.base_tax_rate
    if state.flags and state.flags.at_war then taxRate = BE.war_tax_rate end
    taxRate = taxRate + GameState.GetModifierValue(state, "tax_rate")
        - GameState.GetModifierValue(state, "legitimacy") * 0.0004
        - GameState.GetModifierValue(state, "political_standing") * 0.0004
        - GameState.GetModifierValue(state, "public_support") * 0.0002
        + GameState.GetModifierValue(state, "corruption_risk") * 0.0005
        + math.max(0, GameState.GetModifierValue(state, "risk")) * 0.0004
        + (state.regulation_pressure or 0) * 0.0008
    -- 首都控制度 >= 30% 减税（与 Settle 保持一致）
    for _, r in ipairs(state.regions) do
        if r.type == "capital" and r.control >= 30 then
            local taxReduction = math.floor((r.control - 30) / 10) * 0.01
            taxRate = taxRate - taxReduction
        end
    end
    taxRate = math.max(0, math.min(0.35, taxRate))
    details.tax = math.floor(math.max(0, state.cash + income) * taxRate)
    local expense = expenseBeforeTax + details.tax + details.ai_penalty

    return income, expense, details
end

-- ============================================================================
-- 矿山耗尽处置辅助函数
-- ============================================================================

--- 同步 region.gold_reserve 为该地区所有矿 reserve 之和（兼容引用）
function Economy._SyncRegionGoldReserve(state)
    local sums = {}
    for _, mine in ipairs(state.mines) do
        local rid = mine.region_id or "mine_district"
        sums[rid] = (sums[rid] or 0) + math.max(0, mine.reserve or 0)
    end
    for _, r in ipairs(state.regions) do
        if r.resources.gold_reserve ~= nil then
            -- 有矿的区域取矿 reserve 之和，无矿的区域归零
            r.resources.gold_reserve = sums[r.id] or 0
        end
    end
end

--- 处理上季度标记为 migrating 的矿山：完成迁移
function Economy._ProcessMigrations(state)
    local kept = {}
    for _, mine in ipairs(state.mines) do
        if mine.migrating then
            local target = nil
            for _, m in ipairs(state.mines) do
                if m ~= mine and m.active and not m.migrating and (m.reserve or 0) > 0 then
                    target = m
                    break
                end
            end
            if target then
                target.level = math.min(BM.max_level, target.level + 1)
                GameState.AddLog(state, string.format(
                    "[矿业] 产能迁移完成：%s 的设备转移至 %s（等级→%d）",
                    mine.name, target.name, target.level))
            else
                GameState.AddLog(state, string.format(
                    "[矿业] 产能迁移失败：%s 无可用目标矿山，设备报废",
                    mine.name))
            end
        else
            table.insert(kept, mine)
        end
    end
    state.mines = kept
end

return Economy
