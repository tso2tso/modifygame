-- ============================================================================
-- 跨国贸易系统（Phase 3）
-- 订单生成 → 接单 → 分配装备 → 发货 → 结算
-- 幕后执政（shadow_ruler）解锁后激活
-- ============================================================================

local Balance = require("data.balance")
local GameState = require("game_state")
local TradeRoutesData = require("data.trade_routes_data")
local EquipmentData = require("data.equipment_data")
local EuropeData = require("data.europe_data")

local BFT = Balance.FOREIGN_TRADE
local CATALOG = EquipmentData.CATALOG

local Trade = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 检查是否已解锁跨国行动
---@param state table
---@return boolean
function Trade.CanDoForeignAction(state)
    return state.unlocked_features
        and state.unlocked_features["foreign_trade"] == true
end

--- 确保 trade 子表存在
---@param state table
local function ensureTradeState(state)
    if not state.trade then
        state.trade = {
            order_pool = {},
            active_orders = {},
            routes = {},
            route_unlocks = {},
            completed_count = 0,
            failed_count = 0,
            total_revenue = 0,
            -- (贸易信誉已合并到统一声誉 state.reputation)
            last_quarter_revenue = 0,
        }
    end
    local t = state.trade
    t.order_pool = t.order_pool or {}
    t.active_orders = t.active_orders or {}
    t.routes = t.routes or {}
    t.route_unlocks = t.route_unlocks or {}
    t.completed_count = t.completed_count or 0
    t.failed_count = t.failed_count or 0
    t.total_revenue = t.total_revenue or 0
    -- (t.reputation 已合并到 state.reputation)
    t.last_quarter_revenue = t.last_quarter_revenue or 0
end

--- 生成订单 ID
---@param state table
---@return string
local function genOrderId(state)
    local count = (state.trade.completed_count or 0)
        + (state.trade.failed_count or 0)
        + #(state.trade.active_orders or {})
        + #(state.trade.order_pool or {})
    return string.format("order_q%d_%03d", state.quarter or 0, count + 1)
end

--- 判断某国家是否处于战争状态
---@param state table
---@param countryId string
---@return boolean
local function isCountryAtWar(state, countryId)
    -- 基于 fronts 检查（大国博弈系统）
    for _, front in ipairs(state.fronts or {}) do
        if front.attacker == countryId or front.defender == countryId then
            return true
        end
    end
    return false
end

--- 统计当前交战大国数量
---@param state table
---@return number
local function countBelligerents(state)
    local seen = {}
    for _, front in ipairs(state.fronts or {}) do
        seen[front.attacker] = true
        seen[front.defender] = true
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    return count
end

--- 从订单模板创建订单实例
---@param state table
---@param template table
---@param buyerPowerId string
---@param buyerLabel string
---@return table order
local function createOrderFromTemplate(state, template, buyerPowerId, buyerLabel)
    local inflation = GameState.GetInflationFactor(state)
    local items = {}
    for _, itemDef in ipairs(template.items) do
        local qty = math.random(itemDef.qty_min, itemDef.qty_max)
        table.insert(items, { equip_id = itemDef.equip_id, qty = qty })
    end

    -- 计算总报酬
    local totalPayment = 0
    for _, item in ipairs(items) do
        totalPayment = totalPayment + item.qty * template.payment_per_unit
    end
    -- 通胀溢价
    totalPayment = math.floor(totalPayment
        * (inflation ^ (BFT.inflation_price_exponent or 0.5)))
    -- 统一声誉→贸易订单价格加成
    local repOrderBonus = GameState.GetTradeOrderBonus(state)
    if repOrderBonus > 0 then
        totalPayment = math.floor(totalPayment * (1 + repOrderBonus))
    end
    -- 合作度价格加成：偏向合作(10~29) → 订单价格+10%
    local collabScore = state.collaboration_score or 0
    if collabScore >= 10 and collabScore < 30 then
        totalPayment = math.floor(totalPayment * 1.10)
    end
    -- 称号系统的贸易价格加成（trade_price_bonus modifier）
    local tradePriceBonus = GameState.GetModifierValue(state, "trade_price_bonus")
    if tradePriceBonus > 0 then
        totalPayment = math.floor(totalPayment * (1 + tradePriceBonus))
    end

    local order = {
        id = genOrderId(state),
        buyer_power_id = buyerPowerId,
        buyer_label = buyerLabel,
        items_required = items,
        items_allocated = {},
        payment_base = totalPayment,
        deadline_turns = template.deadline_turns,
        remaining_turns = template.deadline_turns,
        risk_level = template.risk_level,
        template_label = template.label,
        status = "available",  -- available → accepted → shipping → delivered/failed/expired
        route_id = nil,
        escort_squad_id = nil,
        shipping_remaining = 0,
    }

    return order
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 格式化买家标签为「城市（国家）」
---@param state table
---@param route table 路线定义（来自 TradeRoutesData）
---@return string
function Trade.FormatBuyerLabel(state, route)
    local europe = state.europe or {}
    local countryLabel = route.buyer_power_id
    if europe[route.buyer_power_id] then
        countryLabel = europe[route.buyer_power_id].label or countryLabel
    end
    local city = route.dest_city
    if city then
        return city .. "（" .. countryLabel .. "）"
    end
    return countryLabel
end

--- 每季生成新订单（TurnEngine Phase 1.9 调用）
---@param state table
function Trade.GenerateOrders(state)
    ensureTradeState(state)
    local t = state.trade

    -- 清空过期的可用订单（每季刷新）
    t.order_pool = {}

    -- 获取已开通路线
    local routes = TradeRoutesData.GetUnlockedRoutes(state)
    if #routes == 0 then return end

    -- 确定生成数量
    local isWartime = state.flags and state.flags.at_war
    local orderCount
    if isWartime then
        orderCount = BFT.war_order_base
            + countBelligerents(state) * BFT.war_order_per_belligerent
        orderCount = math.min(orderCount, BFT.war_order_cap)
    else
        orderCount = BFT.peace_order_count
    end

    -- modifier 加成
    local freqBonus = GameState.GetModifierValue(state, "order_frequency_bonus")
    orderCount = orderCount + math.floor(freqBonus)

    -- 制裁状态：可接订单减半
    if state.expeditions and state.expeditions.under_sanction then
        orderCount = math.max(1, math.floor(orderCount * 0.5))
    end

    -- 选择订单模板池
    local templates = isWartime
        and TradeRoutesData.WAR_ORDER_TEMPLATES
        or TradeRoutesData.PEACE_ORDER_TEMPLATES

    -- 生成订单
    for i = 1, orderCount do
        -- 随机选择一条路线作为买家
        local route = routes[math.random(1, #routes)]
        -- 获取买家标签：城市（国家）格式
        local buyerLabel = Trade.FormatBuyerLabel(state, route)

        -- 随机选模板
        local template = templates[math.random(1, #templates)]

        -- 检查玩家是否有能力生产该装备（已解锁该装备）
        local canProduce = true
        for _, itemDef in ipairs(template.items) do
            if itemDef.equip_id ~= "rifle"
                and not EquipmentData.IsUnlocked(state, itemDef.equip_id) then
                canProduce = false
                break
            end
        end

        if canProduce then
            local order = createOrderFromTemplate(
                state, template, route.buyer_power_id, buyerLabel)
            order.route_id = route.id
            table.insert(t.order_pool, order)
        end
    end

    -- 限制订单池大小
    while #t.order_pool > BFT.order_pool_max do
        table.remove(t.order_pool, 1)
    end

    if #t.order_pool > 0 then
        print(string.format("[Trade] 生成 %d 个贸易订单", #t.order_pool))
    end
end

--- 接受订单（玩家操作，消耗 AP）
---@param state table
---@param orderId string
---@return boolean ok
---@return string msg
function Trade.AcceptOrder(state, orderId)
    ensureTradeState(state)
    local t = state.trade

    -- 在订单池中查找
    local order = nil
    local orderIdx = nil
    for i, o in ipairs(t.order_pool) do
        if o.id == orderId then
            order = o
            orderIdx = i
            break
        end
    end
    if not order then
        return false, "订单不存在或已被接取"
    end

    -- 消耗 AP
    if not GameState.SpendAP(state, BFT.accept_ap_cost) then
        return false, "行动点不足（需要 " .. BFT.accept_ap_cost .. " AP）"
    end

    -- 移入进行中列表
    order.status = "accepted"
    table.insert(t.active_orders, order)
    table.remove(t.order_pool, orderIdx)

    GameState.AddLog(state, string.format(
        "[贸易] 接受订单「%s」→ %s，报酬 %d",
        order.template_label or order.id,
        order.buyer_label,
        order.payment_base))

    return true, "已接受订单：" .. (order.template_label or order.id)
end

--- 为订单分配装备（从库存取出）
---@param state table
---@param orderId string
---@param allocations table[] { equip_id, qty }
---@return boolean ok
---@return string msg
function Trade.AllocateEquipment(state, orderId, allocations)
    ensureTradeState(state)
    local t = state.trade

    -- 查找活跃订单
    local order = nil
    for _, o in ipairs(t.active_orders) do
        if o.id == orderId then order = o; break end
    end
    if not order then return false, "订单不存在" end
    if order.status ~= "accepted" then
        return false, "订单状态异常（当前：" .. order.status .. "）"
    end

    local m = state.military
    m.inventory = m.inventory or {}

    -- 验证并分配
    for _, alloc in ipairs(allocations) do
        -- 从库存中查找足够数量的指定装备
        local needed = alloc.qty
        local taken = 0
        local keptInventory = {}

        for _, inv in ipairs(m.inventory) do
            if inv.equip_id == alloc.equip_id and not inv.repairing and needed > 0 then
                -- 取出
                needed = needed - 1
                taken = taken + 1
                -- 记录已分配
                order.items_allocated = order.items_allocated or {}
                table.insert(order.items_allocated, {
                    equip_id = inv.equip_id,
                    condition = inv.condition,
                    uid = inv.uid,
                })
            else
                table.insert(keptInventory, inv)
            end
        end
        m.inventory = keptInventory

        if taken < alloc.qty then
            -- 回滚：将已取出的还回去
            for _, item in ipairs(order.items_allocated or {}) do
                table.insert(m.inventory, item)
            end
            order.items_allocated = {}
            return false, string.format(
                "%s 库存不足（需 %d，可用 %d）",
                (CATALOG[alloc.equip_id] and CATALOG[alloc.equip_id].name) or alloc.equip_id,
                alloc.qty, taken)
        end
    end

    return true, "装备分配完成"
end

--- 检查订单是否已满足所有装备需求
---@param order table
---@return boolean
function Trade.IsOrderFulfilled(order)
    if not order.items_required then return false end
    local allocated = {}
    for _, item in ipairs(order.items_allocated or {}) do
        allocated[item.equip_id] = (allocated[item.equip_id] or 0) + 1
    end
    for _, req in ipairs(order.items_required) do
        if (allocated[req.equip_id] or 0) < req.qty then
            return false
        end
    end
    return true
end

--- 发货（玩家操作，消耗 AP）
---@param state table
---@param orderId string
---@param escortSquadId number|nil 护送编队 ID（可选）
---@return boolean ok
---@return string msg
function Trade.ShipOrder(state, orderId, escortSquadId)
    ensureTradeState(state)
    local t = state.trade

    -- 查找活跃订单
    local order = nil
    for _, o in ipairs(t.active_orders) do
        if o.id == orderId then order = o; break end
    end
    if not order then return false, "订单不存在" end
    if order.status ~= "accepted" then
        return false, "订单尚未处于已接受状态"
    end

    -- 检查装备是否已满足
    if not Trade.IsOrderFulfilled(order) then
        return false, "装备尚未全部分配，无法发货"
    end

    -- 消耗 AP
    if not GameState.SpendAP(state, BFT.ship_ap_cost) then
        return false, "行动点不足（需要 " .. BFT.ship_ap_cost .. " AP）"
    end

    -- 获取路线
    local routeDef = TradeRoutesData.GetRoute(order.route_id)
    if not routeDef then
        return false, "贸易路线不存在"
    end

    -- 运输成本
    local transportCost = math.floor(routeDef.base_cost
        * GameState.GetInflationFactor(state))
    if state.cash < transportCost then
        -- 退还 AP
        state.ap.current = state.ap.current + BFT.ship_ap_cost
        return false, "现金不足支付运输费（需 " .. transportCost .. "）"
    end
    state.cash = state.cash - transportCost

    -- 设置护送编队
    if escortSquadId then
        order.escort_squad_id = escortSquadId
    end

    -- 计算运输时间
    local distance = routeDef.distance or 1
    local distTurns = BFT.delivery_distance_turns or { 1, 1, 2, 3 }
    order.shipping_remaining = distTurns[distance] or 1

    order.status = "shipping"

    GameState.AddLog(state, string.format(
        "[贸易] 订单「%s」已发货 → %s，运输 %d 季，运费 %d",
        order.template_label or order.id,
        order.buyer_label,
        order.shipping_remaining,
        transportCost))

    return true, string.format("已发货！运输 %d 季", order.shipping_remaining)
end

--- 计算路线安全度
---@param state table
---@param routeId string
---@param escortSquadId number|nil
---@return number safety 0~1
function Trade.CalcRouteSafety(state, routeId, escortSquadId)
    local routeDef = TradeRoutesData.GetRoute(routeId)
    if not routeDef then return 0 end

    local safety = routeDef.base_safety

    -- 途经国家修正
    for _, transitId in ipairs(routeDef.transit) do
        local country = state.europe and state.europe[transitId]
        if country then
            -- 战争惩罚
            if isCountryAtWar(state, transitId) then
                safety = safety + BFT.safety_war_penalty
            end
            -- 被占领惩罚
            if EuropeData.IsOccupied(state.europe, transitId) then
                safety = safety + BFT.safety_occupied_penalty
            end
        end
    end

    -- 外交加成（合作度/100 × 最大加成）
    local collab = state.collaboration_score or 0
    local diplBonus = math.max(0, collab / 100) * BFT.safety_diplo_bonus_max
    safety = safety + diplBonus

    -- ── P2-3c 外交→贸易耦合：大国态度影响路线安全度 ──
    if state.powers and routeDef.buyer_power_id then
        -- 买家大国态度修正
        local buyerPower = state.powers[routeDef.buyer_power_id]
        if buyerPower and buyerPower.active then
            local att = buyerPower.attitude_to_player or 0
            if att >= 30 then
                safety = safety + 0.10
            elseif att <= -30 then
                safety = safety - 0.10
            end
        end
        -- 途经国家的宗主大国态度修正（较小影响）
        for _, transitId in ipairs(routeDef.transit) do
            local transitCountry = state.europe and state.europe[transitId]
            if transitCountry then
                local sovId = transitCountry.sovereign or transitId
                local sovPower = state.powers[sovId]
                if sovPower and sovPower.active then
                    local att = sovPower.attitude_to_player or 0
                    if att >= 30 then
                        safety = safety + 0.03
                    elseif att <= -30 then
                        safety = safety - 0.03
                    end
                end
            end
        end
    end

    -- 统一声誉→贸易路线安全加成
    local repSafetyBonus = GameState.GetTradeSafetyBonus(state)
    if repSafetyBonus > 0 then
        safety = safety + repSafetyBonus
    end

    -- 护送小队加成
    if escortSquadId then
        local m = state.military
        for _, sq in ipairs(m.squads or {}) do
            if sq.id == escortSquadId then
                safety = safety + BFT.safety_escort_bonus
                    + (sq.veterancy or 0) * BFT.safety_escort_vet_bonus
                break
            end
        end
    end

    -- modifier 加成
    local safetyMod = GameState.GetModifierValue(state, "trade_safety_bonus")
    safety = safety + safetyMod

    -- 制裁惩罚：sanction_trade_penalty modifier 影响路线安全
    local sanctionPenalty = GameState.GetModifierValue(state, "sanction_trade_penalty")
    if sanctionPenalty ~= 0 then
        safety = safety + sanctionPenalty  -- sanctionPenalty 本身为负值
    end

    -- 制裁状态额外惩罚（接受制裁期间路线安全降低）
    if state.expeditions and state.expeditions.under_sanction then
        safety = safety - 0.15
    end

    return math.max(0, math.min(1, safety))
end

--- 每季结算交付（TurnEngine Phase 1.9 调用）
---@param state table
---@return table report { total_revenue, deliveries, failures }
function Trade.SettleDeliveries(state)
    ensureTradeState(state)
    local t = state.trade

    local report = {
        total_revenue = 0,
        deliveries = {},
        failures = {},
        expired = {},
    }

    local keptOrders = {}
    for _, order in ipairs(t.active_orders) do
        if order.status == "shipping" then
            order.shipping_remaining = (order.shipping_remaining or 1) - 1
            if order.shipping_remaining <= 0 then
                -- 到达目的地 → 判定成功/失败
                local safety = Trade.CalcRouteSafety(
                    state, order.route_id, order.escort_squad_id)
                local roll = math.random()

                if roll <= safety then
                    -- 成功交付
                    order.status = "delivered"
                    local revenue = order.payment_base
                    state.cash = state.cash + revenue
                    report.total_revenue = report.total_revenue + revenue
                    t.completed_count = t.completed_count + 1
                    t.total_revenue = t.total_revenue + revenue

                    -- 统一声誉 +
                    GameState.ModifyReputation(state, Balance.REPUTATION.trade_success_bonus)

                    -- 统计
                    state.stats = state.stats or {}
                    state.stats.trades_completed =
                        (state.stats.trades_completed or 0) + 1

                    table.insert(report.deliveries, {
                        order_id = order.id,
                        label = order.template_label or order.id,
                        buyer = order.buyer_label,
                        revenue = revenue,
                    })

                    GameState.AddLog(state, string.format(
                        "[贸易] 订单「%s」成功交付 %s，收入 %d",
                        order.template_label or order.id,
                        order.buyer_label,
                        revenue))

                    -- ── P2-3a 贸易→远征耦合：战时交付获得军事物资储备buff ──
                    local isWartime = state.flags and state.flags.at_war
                    if isWartime then
                        GameState.AddModifier(state,
                            "trade_supply",           -- source
                            "expedition_supply_boost", -- target
                            0.15,                      -- +15% 远征伤害
                            2)                         -- 持续2回合
                        GameState.AddLog(state, "[贸易→远征] 战时物资交付成功，获得「军事物资储备」：远征伤害+15%（2回合）")
                    end

                    -- 不保留已完成订单
                else
                    -- 运输失败（劫掠/丢失）
                    order.status = "failed"
                    t.failed_count = t.failed_count + 1

                    -- 统一声誉 -
                    GameState.ModifyReputation(state, Balance.REPUTATION.trade_failure_penalty)

                    -- 损失部分装备
                    local lossCount = math.floor(
                        #(order.items_allocated or {}) * BFT.failure_loss_ratio)
                    -- 其余装备返还库存
                    local m = state.military
                    m.inventory = m.inventory or {}
                    for idx, item in ipairs(order.items_allocated or {}) do
                        if idx > lossCount then
                            table.insert(m.inventory, {
                                equip_id = item.equip_id,
                                condition = math.max(10, (item.condition or 100) - 20),
                            })
                        end
                    end

                    table.insert(report.failures, {
                        order_id = order.id,
                        label = order.template_label or order.id,
                        buyer = order.buyer_label,
                        lost_items = lossCount,
                    })

                    GameState.AddLog(state, string.format(
                        "[贸易] 订单「%s」运输失败！损失 %d 件装备",
                        order.template_label or order.id,
                        lossCount))
                    -- 不保留已失败订单
                end
            else
                -- 仍在运输中
                table.insert(keptOrders, order)
            end

        elseif order.status == "accepted" then
            -- 未发货的订单：倒计时
            order.remaining_turns = (order.remaining_turns or 3) - 1
            if order.remaining_turns <= 0 then
                -- 过期
                order.status = "expired"
                t.failed_count = t.failed_count + 1
                GameState.ModifyReputation(state, Balance.REPUTATION.trade_failure_penalty)

                -- 返还已分配装备
                local m = state.military
                m.inventory = m.inventory or {}
                for _, item in ipairs(order.items_allocated or {}) do
                    table.insert(m.inventory, {
                        equip_id = item.equip_id,
                        condition = item.condition or 100,
                    })
                end

                table.insert(report.expired, {
                    order_id = order.id,
                    label = order.template_label or order.id,
                })

                GameState.AddLog(state, string.format(
                    "[贸易] 订单「%s」已过期，装备已退回库存",
                    order.template_label or order.id))
                -- 不保留过期订单
            else
                table.insert(keptOrders, order)
            end
        else
            -- 其他状态直接保留（不应该出现）
            table.insert(keptOrders, order)
        end
    end

    t.active_orders = keptOrders
    return report
end

--- 一键完成订单（接单+自动分配+发货，合并为 1AP）
--- 自动从库存中分配所需装备，如果库存不足则拒绝
---@param state table
---@param orderId string
---@param escortSquadId number|nil 护送编队 ID（可选）
---@return boolean ok
---@return string msg
function Trade.QuickFulfill(state, orderId, escortSquadId)
    ensureTradeState(state)
    local t = state.trade

    -- 在订单池中查找
    local order = nil
    local orderIdx = nil
    for i, o in ipairs(t.order_pool) do
        if o.id == orderId then
            order = o
            orderIdx = i
            break
        end
    end
    if not order then
        return false, "订单不存在或已被接取"
    end

    -- AP 检查（只消耗 1AP，合并了原来的 accept+ship）
    local quickAP = 1
    local totalAP = state.ap.current + (state.ap.temp or 0)
    if totalAP < quickAP then
        return false, "行动点不足（需要 " .. quickAP .. " AP）"
    end

    -- 检查库存是否满足所有需求
    local m = state.military
    m.inventory = m.inventory or {}
    local inventoryCounts = {}
    for _, inv in ipairs(m.inventory) do
        if not inv.repairing then
            inventoryCounts[inv.equip_id] = (inventoryCounts[inv.equip_id] or 0) + 1
        end
    end
    for _, req in ipairs(order.items_required) do
        local available = inventoryCounts[req.equip_id] or 0
        if available < req.qty then
            local name = (CATALOG[req.equip_id] and CATALOG[req.equip_id].name) or req.equip_id
            return false, string.format("%s 库存不足（需 %d，可用 %d）", name, req.qty, available)
        end
        -- 预扣以检查多项需求不冲突
        inventoryCounts[req.equip_id] = available - req.qty
    end

    -- 检查路线运输费
    local routeDef = TradeRoutesData.GetRoute(order.route_id)
    if not routeDef then
        return false, "贸易路线不存在"
    end
    local transportCost = math.floor(routeDef.base_cost * GameState.GetInflationFactor(state))
    if state.cash < transportCost then
        return false, "现金不足支付运输费（需 " .. transportCost .. "）"
    end

    -- ── 一切检查通过，开始执行 ──

    -- 扣 AP
    GameState.SpendAP(state, quickAP)

    -- 从订单池移入活跃列表
    order.status = "accepted"
    table.insert(t.active_orders, order)
    table.remove(t.order_pool, orderIdx)

    -- 自动分配装备
    order.items_allocated = {}
    for _, req in ipairs(order.items_required) do
        local needed = req.qty
        local keptInventory = {}
        for _, inv in ipairs(m.inventory) do
            if inv.equip_id == req.equip_id and not inv.repairing and needed > 0 then
                needed = needed - 1
                table.insert(order.items_allocated, {
                    equip_id = inv.equip_id,
                    condition = inv.condition,
                    uid = inv.uid,
                })
            else
                table.insert(keptInventory, inv)
            end
        end
        m.inventory = keptInventory
    end

    -- S1: QuickFulfill 便利溢价
    transportCost = math.floor(transportCost * (1 + (BFT.quick_fulfill_surcharge or 0.20)))

    -- 扣运输费
    state.cash = state.cash - transportCost

    -- 设置护送编队
    if escortSquadId then
        order.escort_squad_id = escortSquadId
    end

    -- 计算运输时间
    local distance = routeDef.distance or 1
    local distTurns = BFT.delivery_distance_turns or { 1, 1, 2, 3 }
    order.shipping_remaining = distTurns[distance] or 1
    order.status = "shipping"

    GameState.AddLog(state, string.format(
        "[贸易] 一键完成订单「%s」→ %s，报酬 %d，运费 %d（含便利费），运输 %d 季",
        order.template_label or order.id,
        order.buyer_label,
        order.payment_base,
        transportCost,
        order.shipping_remaining))

    return true, string.format("一键发货！「%s」运输 %d 季，运费 %d（含便利费）",
        order.template_label or order.id,
        order.shipping_remaining,
        transportCost)
end

--- 检查订单是否可以一键完成（UI 预检查用）
---@param state table
---@param order table
---@return boolean canQuick
---@return string|nil reason
function Trade.CanQuickFulfill(state, order)
    -- AP 检查
    local totalAP = state.ap.current + (state.ap.temp or 0)
    if totalAP < 1 then
        return false, "行动点不足"
    end

    -- 库存检查
    local m = state.military
    m.inventory = m.inventory or {}
    local inventoryCounts = {}
    for _, inv in ipairs(m.inventory) do
        if not inv.repairing then
            inventoryCounts[inv.equip_id] = (inventoryCounts[inv.equip_id] or 0) + 1
        end
    end
    for _, req in ipairs(order.items_required or {}) do
        local available = inventoryCounts[req.equip_id] or 0
        if available < req.qty then
            local name = (CATALOG[req.equip_id] and CATALOG[req.equip_id].name) or req.equip_id
            return false, string.format("%s不足(%d/%d)", name, available, req.qty)
        end
        inventoryCounts[req.equip_id] = available - req.qty
    end

    -- 运输费检查
    local routeDef = TradeRoutesData.GetRoute(order.route_id)
    if routeDef then
        local transportCost = math.floor(routeDef.base_cost * GameState.GetInflationFactor(state))
        if state.cash < transportCost then
            return false, "运费不足(" .. transportCost .. ")"
        end
    end

    return true
end

--- 获取订单摘要信息（UI 用）
---@param state table
---@return table summary
function Trade.GetSummary(state)
    ensureTradeState(state)
    local t = state.trade
    return {
        pool_count = #t.order_pool,
        active_count = #t.active_orders,
        completed = t.completed_count,
        failed = t.failed_count,
        total_revenue = t.total_revenue,
        reputation = state.reputation or 0,
        last_quarter_revenue = t.last_quarter_revenue,
    }
end

--- 获取可用订单列表（UI 用）
---@param state table
---@return table[]
function Trade.GetAvailableOrders(state)
    ensureTradeState(state)
    return state.trade.order_pool
end

--- 获取进行中订单列表（UI 用）
---@param state table
---@return table[]
function Trade.GetActiveOrders(state)
    ensureTradeState(state)
    return state.trade.active_orders
end

--- ── P2-3c 外交→贸易耦合：为指定买家生成1个奖励订单 ──
--- war_supplier 行动调用：立即获得来自该大国的贸易订单
---@param state table
---@param buyerPowerId string
---@return boolean ok
---@return string msg
function Trade.GenerateBonusOrder(state, buyerPowerId)
    ensureTradeState(state)
    local t = state.trade

    -- 查找该买家的路线
    local routeDef = TradeRoutesData.GetRouteForBuyer(buyerPowerId)
    if not routeDef then
        return false, "该大国无对应贸易路线"
    end

    -- 检查路线是否已开通
    local routeUnlocked = routeDef.unlocked
    if not routeUnlocked then
        local unlocks = t.route_unlocks or {}
        routeUnlocked = unlocks[routeDef.id] == true
    end
    if not routeUnlocked then
        return false, "该大国贸易路线尚未开通"
    end

    -- 获取买家标签：城市（国家）格式
    local buyerLabel = Trade.FormatBuyerLabel(state, routeDef)

    -- 选择模板：战时用战争模板，和平用和平模板
    local isWartime = state.flags and state.flags.at_war
    local templates = isWartime
        and TradeRoutesData.WAR_ORDER_TEMPLATES
        or TradeRoutesData.PEACE_ORDER_TEMPLATES
    local template = templates[math.random(1, #templates)]

    local order = createOrderFromTemplate(state, template, buyerPowerId, buyerLabel)
    order.route_id = routeDef.id
    table.insert(t.order_pool, order)

    return true, string.format("获得来自%s的奖励订单「%s」",
        buyerLabel, template.label)
end

return Trade
