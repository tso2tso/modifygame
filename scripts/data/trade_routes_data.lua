-- ============================================================================
-- 贸易路线数据（Phase 3：跨国贸易系统）
-- 预定义从波黑出发到欧洲各大国/小国的贸易路线
-- ============================================================================

local TradeRoutesData = {}

--- 路线定义
--- 玩家基地在波黑（奥匈帝国境内），路线基于 europe_data 邻接关系
--- base_safety: 基础安全度 0~1（越高越安全）
--- base_cost: 基础运输成本（金币）
--- transit: 途经国家列表（影响安全度计算）
--- unlocked: 是否初始开通
TradeRoutesData.ROUTES = {
    -- ── 近距离路线（1跳）──
    {
        id = "route_austria",
        name = "波黑→维也纳",
        dest_city = "维也纳",
        buyer_power_id = "austria_hungary",
        transit = {},  -- 境内运输，无途经
        base_safety = 0.95,
        base_cost = 50,
        distance = 1,
        unlocked = true,
    },
    {
        id = "route_serbia",
        name = "波黑→贝尔格莱德",
        dest_city = "贝尔格莱德",
        buyer_power_id = "serbia",
        transit = {},
        base_safety = 0.85,
        base_cost = 80,
        distance = 1,
        unlocked = true,
    },
    {
        id = "route_montenegro",
        name = "波黑→采蒂涅",
        dest_city = "采蒂涅",
        buyer_power_id = "montenegro",
        transit = {},
        base_safety = 0.80,
        base_cost = 60,
        distance = 1,
        unlocked = true,
    },

    -- ── 中距离路线（2跳）──
    {
        id = "route_germany",
        name = "波黑→柏林",
        dest_city = "柏林",
        buyer_power_id = "germany",
        transit = { "austria_hungary" },
        base_safety = 0.85,
        base_cost = 150,
        distance = 2,
        unlocked = true,
    },
    {
        id = "route_italy",
        name = "波黑→罗马",
        dest_city = "罗马",
        buyer_power_id = "italy",
        transit = { "austria_hungary" },
        base_safety = 0.80,
        base_cost = 140,
        distance = 2,
        unlocked = true,
    },
    {
        id = "route_romania",
        name = "波黑→布加勒斯特",
        dest_city = "布加勒斯特",
        buyer_power_id = "romania",
        transit = { "serbia" },
        base_safety = 0.75,
        base_cost = 120,
        distance = 2,
        unlocked = true,
    },
    {
        id = "route_bulgaria",
        name = "波黑→索非亚",
        dest_city = "索非亚",
        buyer_power_id = "bulgaria",
        transit = { "serbia" },
        base_safety = 0.70,
        base_cost = 130,
        distance = 2,
        unlocked = true,
    },
    {
        id = "route_ottoman",
        name = "波黑→伊斯坦布尔",
        dest_city = "伊斯坦布尔",
        buyer_power_id = "ottoman",
        transit = { "serbia" },
        base_safety = 0.60,
        base_cost = 200,
        distance = 2,
        unlocked = true,
    },
    {
        id = "route_switzerland",
        name = "波黑→苏黎世",
        dest_city = "苏黎世",
        buyer_power_id = "switzerland",
        transit = { "austria_hungary" },
        base_safety = 0.90,
        base_cost = 160,
        distance = 2,
        unlocked = false,  -- 需科技/事件解锁
    },

    -- ── 远距离路线（3跳）──
    {
        id = "route_france",
        name = "波黑→巴黎",
        dest_city = "巴黎",
        buyer_power_id = "france",
        transit = { "austria_hungary", "germany" },
        base_safety = 0.70,
        base_cost = 280,
        distance = 3,
        unlocked = false,
    },
    {
        id = "route_russia",
        name = "波黑→莫斯科",
        dest_city = "莫斯科",
        buyer_power_id = "russia",
        transit = { "austria_hungary", "romania" },
        base_safety = 0.55,
        base_cost = 320,
        distance = 3,
        unlocked = false,
    },
    {
        id = "route_greece",
        name = "波黑→雅典",
        dest_city = "雅典",
        buyer_power_id = "greece",
        transit = { "serbia", "bulgaria" },
        base_safety = 0.65,
        base_cost = 220,
        distance = 3,
        unlocked = false,
    },
    {
        id = "route_lowlands",
        name = "波黑→布鲁塞尔",
        dest_city = "布鲁塞尔",
        buyer_power_id = "lowlands",
        transit = { "austria_hungary", "germany" },
        base_safety = 0.75,
        base_cost = 260,
        distance = 3,
        unlocked = false,
    },

    -- ── 超远距离路线（4跳）──
    {
        id = "route_britain",
        name = "波黑→伦敦",
        dest_city = "伦敦",
        buyer_power_id = "britain",
        transit = { "austria_hungary", "germany", "lowlands" },
        base_safety = 0.60,
        base_cost = 400,
        distance = 4,
        unlocked = false,
    },
    {
        id = "route_scandinavia",
        name = "波黑→斯德哥尔摩",
        dest_city = "斯德哥尔摩",
        buyer_power_id = "scandinavia",
        transit = { "austria_hungary", "germany", "denmark" },
        base_safety = 0.65,
        base_cost = 380,
        distance = 4,
        unlocked = false,
    },
}

-- ── 订单模板（装备需求池）──

--- 和平时期订单模板（低级民用物资）
--- 售价设计：总成本(现金+铜×铜价8) × ~1.5 倍利润，通胀另算(inflation^0.5)
TradeRoutesData.PEACE_ORDER_TEMPLATES = {
    {
        label = "民用步枪采购",
        items = { { equip_id = "rifle", qty_min = 3, qty_max = 8 } },
        payment_per_unit = 40,     -- 成本0，基础利润
        deadline_turns = 4,
        risk_level = "low",
    },
    {
        label = "改良步枪订单",
        items = { { equip_id = "improved_rifle", qty_min = 2, qty_max = 5 } },
        payment_per_unit = 220,    -- 成本144(120+3×8)，利润53%
        deadline_turns = 4,
        risk_level = "low",
    },
}

--- 战争时期订单模板（高级军火）
--- 售价设计：总成本 × ~2 倍战时溢价，通胀另算(inflation^0.5)
TradeRoutesData.WAR_ORDER_TEMPLATES = {
    {
        label = "步枪紧急采购",
        items = { { equip_id = "rifle", qty_min = 5, qty_max = 15 } },
        payment_per_unit = 80,     -- 成本0，战时溢价
        deadline_turns = 2,
        risk_level = "medium",
    },
    {
        label = "改良步枪军购",
        items = { { equip_id = "improved_rifle", qty_min = 3, qty_max = 8 } },
        payment_per_unit = 350,    -- 成本144，利润143%
        deadline_turns = 3,
        risk_level = "medium",
    },
    {
        label = "机枪采购合同",
        items = { { equip_id = "mg", qty_min = 1, qty_max = 4 } },
        payment_per_unit = 550,    -- 成本298(250+6×8)，利润85%
        deadline_turns = 3,
        risk_level = "high",
    },
    {
        label = "迫击炮军购",
        items = { { equip_id = "mortar", qty_min = 1, qty_max = 3 } },
        payment_per_unit = 900,    -- 成本480(400+10×8)，利润88%
        deadline_turns = 4,
        risk_level = "high",
    },
    {
        label = "机动装备采购",
        items = { { equip_id = "motorized", qty_min = 1, qty_max = 2 } },
        payment_per_unit = 1500,   -- 成本770(650+15×8)，利润95%
        deadline_turns = 5,
        risk_level = "high",
    },
    {
        label = "精锐套件特供",
        items = { { equip_id = "elite_kit", qty_min = 1, qty_max = 2 } },
        payment_per_unit = 2200,   -- 成本1200(1000+25×8)，利润83%
        deadline_turns = 6,
        risk_level = "high",
    },
}

-- ── 民用商品订单模板（消耗矿产资源而非装备）──

--- 和平时期民用订单模板
--- 售价参考：矿产市价(copper_price=8, gold_price=50, coal_price=5) × ~1.5 倍利润
TradeRoutesData.CIVIL_PEACE_TEMPLATES = {
    {
        label = "铜锭出口",
        resources = { { resource = "copper", qty_min = 5, qty_max = 15 } },
        payment_per_unit = 12,     -- 铜价8，利润50%
        deadline_turns = 3,
        risk_level = "low",
    },
    {
        label = "煤炭供应",
        resources = { { resource = "coal", qty_min = 10, qty_max = 30 } },
        payment_per_unit = 7,      -- 煤价5，利润40%
        deadline_turns = 3,
        risk_level = "low",
    },
    {
        label = "黄金交割",
        resources = { { resource = "gold", qty_min = 2, qty_max = 6 } },
        payment_per_unit = 55,     -- 金价50，利润10%（贵金属薄利）
        deadline_turns = 2,
        risk_level = "low",
    },
}

--- 战争时期民用订单模板（战时溢价，风险更高）
TradeRoutesData.CIVIL_WAR_TEMPLATES = {
    {
        label = "战略矿产",
        resources = {
            { resource = "copper", qty_min = 5, qty_max = 10 },
            { resource = "coal", qty_min = 5, qty_max = 10 },
        },
        payment_per_unit = 20,     -- 批次价，战时溢价
        deadline_turns = 4,
        risk_level = "medium",
    },
    {
        label = "贵金属急单",
        resources = { { resource = "gold", qty_min = 3, qty_max = 10 } },
        payment_per_unit = 80,     -- 金价50，战时溢价60%
        deadline_turns = 2,
        risk_level = "medium",
    },
    {
        label = "工业原料包",
        resources = {
            { resource = "gold", qty_min = 1, qty_max = 1 },
            { resource = "copper", qty_min = 8, qty_max = 8 },
            { resource = "coal", qty_min = 15, qty_max = 15 },
        },
        payment_per_unit = 350,    -- 固定批次，整包价
        deadline_turns = 4,
        risk_level = "high",
    },
}

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 获取指定路线定义
---@param routeId string
---@return table|nil
function TradeRoutesData.GetRoute(routeId)
    for _, r in ipairs(TradeRoutesData.ROUTES) do
        if r.id == routeId then return r end
    end
    return nil
end

--- 获取指定买家的路线
---@param buyerPowerId string
---@return table|nil
function TradeRoutesData.GetRouteForBuyer(buyerPowerId)
    for _, r in ipairs(TradeRoutesData.ROUTES) do
        if r.buyer_power_id == buyerPowerId then return r end
    end
    return nil
end

--- 获取所有已开通的路线
---@param state table|nil 可选，用于检查运行时解锁
---@return table[]
function TradeRoutesData.GetUnlockedRoutes(state)
    local result = {}
    for _, r in ipairs(TradeRoutesData.ROUTES) do
        local unlocked = r.unlocked
        -- 运行时解锁检查（通过 modifier 或 unlocked_features）
        if not unlocked and state then
            local tradeState = state.trade or {}
            local routeUnlocks = tradeState.route_unlocks or {}
            if routeUnlocks[r.id] then
                unlocked = true
            end
        end
        if unlocked then
            table.insert(result, r)
        end
    end
    return result
end

return TradeRoutesData
