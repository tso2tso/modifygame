-- ============================================================================
-- 股市引擎：几何布朗运动（GBM）价格模拟
--
-- 核心公式（单季推进）：
--   P_{t+1} = P_t * exp((mu - sigma^2/2) * dt + sigma * eps * sqrt(dt))
--   其中 eps ~ N(0,1)，dt = 1 季度
--
-- 分层：
--   L1  每支股票自带 mu/sigma 基本面（见 data/balance.lua STOCKS）
--   L2  事件临时修正 delta_mu（见 data/event_market_effects.lua 注入的 event_mu_mods）
--   L3  全局修正：战争章节 sigma * war_sigma_multiplier
-- ============================================================================

local StockEngine = {}

-- ============================================================================
-- 常量
-- ============================================================================
-- 战争章节（第二章 1914-1918 / 第四章 1941-1945 / 第六章 1992-1995）
-- 波动率乘数，对应真实战时股市放量震荡规律
StockEngine.WAR_SIGMA_MULT  = 1.8
-- 价格下限保护（避免极端随机数打到 0）
StockEngine.PRICE_FLOOR     = 1.0
-- 价格上限保护（避免指数爆炸造成整数溢出）
StockEngine.PRICE_CEIL      = 9999.0
-- 历史最多保留 12 季（3 年），用于 UI 走势图
StockEngine.HISTORY_KEEP    = 12

-- ============================================================================
-- Box-Muller 变换：生成标准正态随机数 N(0, 1)
-- Lua 标准库只给均匀分布，这里用经典方法转正态
-- ============================================================================
---@return number eps
function StockEngine.RandNormal()
    local u1 = math.random()
    local u2 = math.random()
    if u1 < 1e-10 then u1 = 1e-10 end   -- 避免 log(0)
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

-- ============================================================================
-- 单步 GBM：返回新价格和涨跌幅
-- ============================================================================
---@param price number  当前价格
---@param mu number     季度漂移率（已叠加所有修正）
---@param sigma number  季度波动率
---@param dt number|nil 时间步长（默认 1 季度）
---@return number newPrice, number changePct
function StockEngine.StepGBM(price, mu, sigma, dt)
    dt = dt or 1.0
    local eps   = StockEngine.RandNormal()
    local drift = (mu - 0.5 * sigma * sigma) * dt
    local shock = sigma * eps * math.sqrt(dt)
    local newPrice = price * math.exp(drift + shock)
    newPrice = math.max(StockEngine.PRICE_FLOOR,
        math.min(StockEngine.PRICE_CEIL, newPrice))
    local changePct = (newPrice - price) / price * 100.0
    return newPrice, changePct
end

-- ============================================================================
-- 战争修正判断
-- ============================================================================
---@param state table
---@return boolean
function StockEngine._IsWarEra(state)
    if state.flags and state.flags.at_war then return true end
    local Config = require("config")
    local era = Config.GetEraByYear(state.year or 1904)
    return era and era.war_stripe == true
end

-- ============================================================================
-- 累计 event_mu_mods 对 mu 的总修正
-- event_mu_mods 格式：{ { delta = 0.15, remaining = 2, source = "balkan_wars_1912" }, ... }
-- 同时消耗一次（remaining - 1），到期剔除
-- ============================================================================
---@param stock table
---@return number totalDelta
function StockEngine._ConsumeEventMods(stock)
    if not stock.event_mu_mods or #stock.event_mu_mods == 0 then
        return 0
    end
    local kept = {}
    local total = 0
    for _, mod in ipairs(stock.event_mu_mods) do
        total = total + (mod.delta or 0)
        if mod.remaining == nil then
            -- 无期限修正（不应该出现，防御性保留）
            table.insert(kept, mod)
        elseif mod.remaining > 1 then
            mod.remaining = mod.remaining - 1
            table.insert(kept, mod)
        end
        -- remaining <= 1 本季消费后淘汰
    end
    stock.event_mu_mods = kept
    return total
end

-- ============================================================================
-- 批量推进所有股票
-- 每个季度结束时调用一次（TurnEngine.EndTurn 里）
-- ============================================================================
---@param state table 游戏状态（含 state.stocks）
function StockEngine.UpdateAll(state)
    if not state.stocks then return end

    local isWar = StockEngine._IsWarEra(state)
    local sigmaMult = isWar and StockEngine.WAR_SIGMA_MULT or 1.0

    for _, stock in ipairs(state.stocks) do
        -- 保留前一价用于 UI 对比
        stock.prev_price = stock.price

        -- 组合 mu：基础 + 事件修正（并消耗一季）
        local eventDelta = StockEngine._ConsumeEventMods(stock)
        local effectiveMu = (stock.mu or 0) + eventDelta
        -- 组合 sigma：基础 * 战时倍率
        local effectiveSigma = (stock.sigma or 0.1) * sigmaMult

        stock.price, stock.change_pct = StockEngine.StepGBM(
            stock.price, effectiveMu, effectiveSigma)

        -- 历史归档
        stock.history = stock.history or {}
        table.insert(stock.history, stock.price)
        while #stock.history > StockEngine.HISTORY_KEEP do
            table.remove(stock.history, 1)
        end
    end
end

-- ============================================================================
-- 查找股票（ID 或名称）
-- ============================================================================
---@param state table
---@param key string   stock.id 或 stock.name
---@return table|nil stock
function StockEngine.Find(state, key)
    if not state.stocks then return nil end
    for _, s in ipairs(state.stocks) do
        if s.id == key or s.name == key then
            return s
        end
    end
    return nil
end

-- ============================================================================
-- 注入事件修正
-- ============================================================================
---@param stock table
---@param delta number   mu 偏移（例如 +0.30 战时军工暴涨）
---@param duration number 持续季度数（最少 1）
---@param source string|nil 来源标识（事件 id，便于调试）
function StockEngine.InjectMod(stock, delta, duration, source)
    if not stock then return end
    stock.event_mu_mods = stock.event_mu_mods or {}
    table.insert(stock.event_mu_mods, {
        delta = delta,
        remaining = math.max(1, duration or 1),
        source = source,
    })
end

-- ============================================================================
-- 按名称或 ID 向股票注入修正（用于事件联动）
-- ============================================================================
---@param state table
---@param key string  stock.id 或 stock.name
---@param delta number
---@param duration number
---@param source string|nil
function StockEngine.ApplyEventModifier(state, key, delta, duration, source)
    local stock = StockEngine.Find(state, key)
    if stock then
        StockEngine.InjectMod(stock, delta, duration, source)
    end
end

-- ============================================================================
-- 买卖接口
-- ============================================================================

--- 买入股票
---@param state table
---@param stockId string
---@param shares number
---@return boolean ok, string|nil errMsg
function StockEngine.Buy(state, stockId, shares)
    shares = math.floor(shares or 0)
    if shares <= 0 then return false, "数量无效" end
    local stock = StockEngine.Find(state, stockId)
    if not stock then return false, "股票不存在" end
    local cost = math.ceil(stock.price * shares)
    if state.cash < cost then
        return false, "资金不足"
    end
    state.cash = state.cash - cost
    state.portfolio = state.portfolio or { holdings = {} }
    state.portfolio.holdings = state.portfolio.holdings or {}
    local h = state.portfolio.holdings[stockId]
    if h then
        local totalCost = (h.avg_cost or stock.price) * h.shares + cost
        h.shares = h.shares + shares
        h.avg_cost = totalCost / h.shares
    else
        state.portfolio.holdings[stockId] = {
            shares = shares,
            avg_cost = stock.price,
        }
    end
    return true, string.format("买入 %d 股 @ %.2f", shares, stock.price)
end

--- 卖出股票
---@param state table
---@param stockId string
---@param shares number
---@return boolean ok, string|nil msg
function StockEngine.Sell(state, stockId, shares)
    shares = math.floor(shares or 0)
    if shares <= 0 then return false, "数量无效" end
    local stock = StockEngine.Find(state, stockId)
    if not stock then return false, "股票不存在" end
    state.portfolio = state.portfolio or { holdings = {} }
    local h = state.portfolio.holdings and state.portfolio.holdings[stockId]
    if not h or h.shares < shares then
        return false, "持仓不足"
    end
    local gain = math.floor(stock.price * shares)
    state.cash = state.cash + gain
    h.shares = h.shares - shares
    if h.shares <= 0 then
        state.portfolio.holdings[stockId] = nil
    end
    return true, string.format("卖出 %d 股 @ %.2f 获现 %d", shares, stock.price, gain)
end

--- 持仓估值
---@param state table
---@return number totalValue, number totalCost, number totalShares
function StockEngine.PortfolioValue(state)
    local val, cost, shares = 0, 0, 0
    if not state.portfolio or not state.portfolio.holdings then
        return 0, 0, 0
    end
    for stockId, h in pairs(state.portfolio.holdings) do
        local s = StockEngine.Find(state, stockId)
        if s then
            val = val + s.price * h.shares
            cost = cost + (h.avg_cost or 0) * h.shares
            shares = shares + h.shares
        end
    end
    return val, cost, shares
end

return StockEngine
