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
-- 绝对价格保护（极端防御，正常不应触及）
StockEngine.ABS_PRICE_FLOOR = 0.10
StockEngine.ABS_PRICE_CEIL  = 99999.0
-- 软限倍率：相对公允价值的上下限
StockEngine.SOFT_CEIL_MULT  = 5.0    -- 最高 = fairValue × 5
StockEngine.SOFT_FLOOR_MULT = 0.15   -- 最低 = fairValue × 0.15
-- 历史最多保留 12 季（3 年），用于 UI 走势图
StockEngine.HISTORY_KEEP    = 12

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

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
---@param mu number     季度漂移率（已叠加所有修正 + 均值回归）
---@param sigma number  季度波动率
---@param dt number|nil 时间步长（默认 1 季度）
---@param fairValue number|nil 公允价值（用于软限价）
---@return number newPrice, number changePct
function StockEngine.StepGBM(price, mu, sigma, dt, fairValue)
    dt = dt or 1.0
    local eps   = StockEngine.RandNormal()
    local drift = (mu - 0.5 * sigma * sigma) * dt
    local shock = sigma * eps * math.sqrt(dt)
    local newPrice = price * math.exp(drift + shock)
    -- 软限价：基于公允价值
    local priceCeil = StockEngine.ABS_PRICE_CEIL
    local priceFloor = StockEngine.ABS_PRICE_FLOOR
    if fairValue and fairValue > 0 then
        priceCeil = math.min(priceCeil, fairValue * StockEngine.SOFT_CEIL_MULT)
        priceFloor = math.max(priceFloor, fairValue * StockEngine.SOFT_FLOOR_MULT)
    end
    newPrice = math.max(priceFloor, math.min(priceCeil, newPrice))
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
-- 板块加成：根据游戏实体经营状态计算板块基本面奖励/惩罚
-- 返回 [-1, +1] 区间的加成系数
-- ============================================================================
---@param state table
---@param stock table
---@return number sectorBonus
function StockEngine._GetSectorBonus(state, stock)
    local sector = stock.sector
    if not sector then return 0 end

    if sector == "mining" then
        -- 矿业：活跃矿山数量加成
        local activeMines = 0
        for _, mine in ipairs(state.mines or {}) do
            if mine.active ~= false then activeMines = activeMines + 1 end
        end
        return math.min(0.5, activeMines * 0.03)

    elseif sector == "military" then
        -- 军工：战时大幅利好，和平微弱利空
        local atWar = state.flags and state.flags.at_war
        return atWar and 0.8 or -0.2

    elseif sector == "transport" then
        local GameState = require("game_state")
        local blocked = GameState.GetModifierValue(state, "railway_blocked") > 0
        if stock.id == "imperial_railway" then
            -- 铁路：封锁利空，工业控制利好
            local industrialControl = 0
            for _, r in ipairs(state.regions or {}) do
                if r.id == "industrial_town" then industrialControl = r.control or 0; break end
            end
            return (blocked and -0.3 or 0) + (industrialControl - 40) / 200
        else
            -- 航运：战时利空，和平利好
            local atWar = state.flags and state.flags.at_war
            return atWar and -0.3 or 0.1
        end

    elseif sector == "finance" then
        -- 金融：危机期间利空，杠杆过高惩罚
        local GameState = require("game_state")
        local leverage = GameState.CalcLeverage and GameState.CalcLeverage(state) or 0
        local crisis = GameState.GetModifierValue(state, "financial_crisis") ~= 0
        return (crisis and -0.3 or 0) - math.min(0.3, leverage * 0.15)

    elseif sector == "trade" then
        -- 贸易：贸易收入加成，封锁利空
        local GameState = require("game_state")
        local blocked = GameState.GetModifierValue(state, "railway_blocked") > 0
        local tradeIncome = (state.trade_passive_income or 0) / 5000
        return math.min(0.3, tradeIncome) + (blocked and -0.2 or 0)

    elseif sector == "media" then
        -- 媒体：外交总监在任 +0.15，影响力加成，战时利空
        local GameState = require("game_state")
        local diplomatBonus = GameState.GetPositionBonus(state, "diplomat")
        local hasDP = diplomatBonus > 0
        local influence = (state.passive_influence or 0)
        local atWar = state.flags and state.flags.at_war
        return (hasDP and 0.15 or 0)
            + math.min(0.30, influence / 1000)
            + (atWar and -0.15 or 0)
    end

    return 0
end

-- ============================================================================
-- 计算公允价值：fairValue = base_value × inflation^alpha × (1 + sectorBonus)
-- ============================================================================
---@param state table
---@param stock table
---@return number fairValue
function StockEngine.ComputeFairValue(state, stock)
    local baseValue = stock.base_value or stock.price or 10
    local alpha = stock.inflation_alpha or 1.0
    local inflation = state.inflation_factor or 1.0
    local sectorBonus = StockEngine._GetSectorBonus(state, stock)
    -- 通胀锚定 + 板块基本面
    local fv = baseValue * (inflation ^ alpha) * (1 + sectorBonus)
    return math.max(0.10, fv)
end

-- ============================================================================
-- 批量推进所有股票（Fair Value Anchored GBM）
-- 每个季度结束时调用一次（TurnEngine.EndTurn 里）
--
-- 核心公式：
--   effectiveMu = base_mu + eventDelta + θ × ln(fairValue / price)
--   P_{t+1} = P_t × exp((effectiveMu - σ²/2) + σ × ε)
-- ============================================================================
---@param state table 游戏状态（含 state.stocks）
function StockEngine.UpdateAll(state)
    if not state.stocks then return end

    local isWar = StockEngine._IsWarEra(state)
    local sigmaMult = isWar and StockEngine.WAR_SIGMA_MULT or 1.0

    for _, stock in ipairs(state.stocks) do
        -- 保留前一价用于 UI 对比
        stock.prev_price = stock.price

        -- 1. 计算公允价值
        local fairValue = StockEngine.ComputeFairValue(state, stock)
        stock.fair_value = fairValue

        -- 2. 均值回归项：θ × ln(V / P)
        local theta = stock.theta or 0.12
        local reversionTerm = 0
        if stock.price > 0 and fairValue > 0 then
            reversionTerm = theta * math.log(fairValue / stock.price)
        end

        -- 3. 组合 mu：基础 + 事件修正 + 均值回归
        local eventDelta = StockEngine._ConsumeEventMods(stock)
        local effectiveMu = (stock.mu or 0) + eventDelta + reversionTerm

        -- 4. 组合 sigma：基础 × 战时倍率
        local effectiveSigma = (stock.sigma or 0.1) * sigmaMult

        -- 5. 执行 GBM 步进（软限价基于公允价值）
        stock.price, stock.change_pct = StockEngine.StepGBM(
            stock.price, effectiveMu, effectiveSigma, 1.0, fairValue)

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

--- 每季根据玩家实体经营对相关股票注入小幅基本面修正。
--- 该修正走现有 event_mu_mods 管线，保持与历史事件同一套消费机制。
---@param state table
---@param report table|nil EconomyReport
function StockEngine.ApplyOperationalDrift(state, report)
    if not state or not state.stocks then return end

    local function add(stockId, delta, source)
        delta = clamp(delta or 0, -0.035, 0.035)
        if math.abs(delta) < 0.002 then return end
        StockEngine.ApplyEventModifier(state, stockId, delta, 1, source)
    end

    -- 矿业：矿山规模、等级和矿区控制度。
    local activeMines, levelSum = 0, 0
    for _, mine in ipairs(state.mines or {}) do
        if mine.active ~= false then
            activeMines = activeMines + 1
            levelSum = levelSum + (mine.level or 1)
        end
    end
    local mineControl = 0
    for _, r in ipairs(state.regions or {}) do
        if r.id == "mine_district" then
            mineControl = r.control or 0
            break
        end
    end
    add("sarajevo_mining",
        activeMines * 0.003 + levelSum * 0.0015 + (mineControl - 50) / 5000,
        "operational_mining")

    -- 军工：兵工厂、生产队列、战时压力。
    local factoryLevel = state.military and state.military.factory and state.military.factory.level or 0
    local queueSize = #(state.military and state.military.production_queue or {})
    local warBonus = (state.flags and state.flags.at_war) and 0.006 or 0
    add("military_industry", factoryLevel * 0.006 + queueSize * 0.004 + warBonus,
        "operational_military")

    -- 铁路/运输：铁路封锁直接利空，工业控制与贸易收入利好。
    local GameState = require("game_state")
    local blocked = GameState.GetModifierValue(state, "railway_blocked") > 0
    local industrialControl = 0
    for _, r in ipairs(state.regions or {}) do
        if r.id == "industrial_town" then
            industrialControl = r.control or 0
            break
        end
    end
    add("imperial_railway",
        (industrialControl - 40) / 6000 + (blocked and -0.025 or 0.006),
        "operational_railway")

    -- 金融：贷款压力和监管压力偏负，金融网络收入偏正。
    local totalDebt = GameState.CalcTotalDebt and GameState.CalcTotalDebt(state) or 0
    local totalAssets = GameState.CalcTotalAssets and GameState.CalcTotalAssets(state) or 1
    local leverage = totalDebt / math.max(1, totalAssets)
    local regulation = (state.regulation_pressure or 0) / 100
    local financeIncome = (state.finance_passive_income or 0) / 10000
    add("austro_bank_trust", financeIncome - leverage * 0.018 - regulation * 0.012,
        "operational_finance")

    -- 贸易：贸易被动收入、外贸/铁路畅通、黑市压力。
    local tradeIncome = (state.trade_passive_income or 0) / 10000
    add("oriental_trading", tradeIncome + (blocked and -0.012 or 0.004) - regulation * 0.006,
        "operational_trade")

    -- 媒体/新闻：影响力、外交总监、新闻社持股。
    local passiveInfluence = (state.passive_influence or 0) / 800
    local diplomatBonus = GameState.GetPositionBonus(state, "diplomat")
    local pressLevel = StockEngine.GetHoldingLevel(state, "balkan_press")
    local pressHoldingBonus = (pressLevel == "control" and 0.012)
        or (pressLevel == "influence" and 0.006) or 0
    local mediaWarPenalty = (state.flags and state.flags.at_war) and -0.012 or 0
    add("balkan_press",
        math.min(0.025, passiveInfluence) + (diplomatBonus > 0 and 0.005 or 0)
        + pressHoldingBonus + mediaWarPenalty,
        "operational_media")
end

--- 持股档位，用于公司协同和 UI 展示。
---@param state table
---@param stockId string
---@return string level none|stake|influence|control
---@return number shares
function StockEngine.GetHoldingLevel(state, stockId)
    local h = state.portfolio and state.portfolio.holdings and state.portfolio.holdings[stockId]
    local shares = h and h.shares or 0
    local stock = StockEngine.Find(state, stockId)
    local maxShares = StockEngine.GetMaxShares(stock)
    local pct = shares / maxShares  -- 持股比例
    local Bal = require("data.balance")
    local LP = Bal.STOCK_LEVEL_PCT or { control = 0.60, influence = 0.30, stake = 0.10 }
    if pct >= LP.control   then return "control",   shares end
    if pct >= LP.influence then return "influence", shares end
    if pct >= LP.stake     then return "stake",     shares end
    return "none", shares
end

function StockEngine.GetHoldingLevelLabel(level)
    if level == "control" then return "控股" end
    if level == "influence" then return "重要持股" end
    if level == "stake" then return "战略持股" end
    return "金融持仓"
end

local function levelValue(level, stakeVal, influenceVal, controlVal)
    if level == "control" then return controlVal end
    if level == "influence" then return influenceVal end
    if level == "stake" then return stakeVal end
    return 0
end

local function clearCompanyModifiers(state)
    local kept = {}
    for _, mod in ipairs(state.modifiers or {}) do
        if not (mod.id and mod.id:find("^company_")) then
            table.insert(kept, mod)
        end
    end
    state.modifiers = kept
end

--- 应用持股/控股带来的实体协同。每季重算，避免旧存档和长期堆叠。
---@param state table
function StockEngine.ApplyCompanySynergies(state)
    if not state then return end
    local GameState = require("game_state")
    clearCompanyModifiers(state)
    state.company_synergies = {}

    local configs = {
        {
            stock = "sarajevo_mining",
            label = "矿业供货协议",
            target = "mine_output_mult",
            values = { 0.015, 0.035, 0.060 },
        },
        {
            stock = "military_industry",
            label = "军工订单协同",
            target = "military_industry_profit",
            values = { 0.025, 0.060, 0.100 },
        },
        {
            stock = "imperial_railway",
            label = "铁路运输协同",
            target = "income_mod",
            values = { 0.008, 0.018, 0.030 },
        },
        {
            stock = "austro_bank_trust",
            label = "金融授信协同",
            target = "tax_rate",
            values = { -0.002, -0.005, -0.008 },
        },
        {
            stock = "oriental_trading",
            label = "贸易渠道协同",
            target = "income_mod",
            values = { 0.006, 0.014, 0.024 },
        },
        {
            stock = "balkan_press",
            label = "媒体舆论协同",
            target = "influence_per_season",
            values = { 1, 2, 4 },
            -- 额外效果由 TickShorts / 操盘逻辑单独读取
            extra = {
                { level = "influence", target = "morale_per_season", value = 3 },
                { level = "control",   target = "morale_per_season", value = 5 },
            },
        },
    }

    for _, cfg in ipairs(configs) do
        local level, shares = StockEngine.GetHoldingLevel(state, cfg.stock)
        local value = levelValue(level, cfg.values[1], cfg.values[2], cfg.values[3])
        if value ~= 0 then
            GameState.AddModifier(state, "company_" .. cfg.stock, cfg.target, value, 1)
            table.insert(state.company_synergies, {
                stock_id = cfg.stock,
                label = cfg.label,
                level = level,
                shares = shares,
                target = cfg.target,
                value = value,
            })
        end
        -- 处理 extra 效果（如媒体协同的士气加成）
        if cfg.extra and level ~= "none" then
            for _, ex in ipairs(cfg.extra) do
                local meets = (ex.level == "stake") or
                    (ex.level == "influence" and (level == "influence" or level == "control")) or
                    (ex.level == "control" and level == "control")
                if meets then
                    GameState.AddModifier(state, "company_" .. cfg.stock .. "_" .. ex.target,
                        ex.target, ex.value, 1)
                end
            end
        end
    end
end

-- ============================================================================
-- 买卖接口
-- ============================================================================

--- 获取某支股票的最大持仓上限
---@param stock table|nil
---@return number
function StockEngine.GetMaxShares(stock)
    local Balance = require("data.balance")
    return (stock and stock.max_shares) or Balance.STOCK_MAX_SHARES or 800
end

--- 获取某支股票还能买入的数量
---@param state table
---@param stockId string
---@return number remainingShares
function StockEngine.GetBuyableShares(state, stockId)
    local stock = StockEngine.Find(state, stockId)
    if not stock then return 0 end
    local maxShares = StockEngine.GetMaxShares(stock)
    local h = state.portfolio and state.portfolio.holdings and state.portfolio.holdings[stockId]
    local currentShares = (h and h.shares) or 0
    return math.max(0, maxShares - currentShares)
end

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
    -- 持仓上限检查
    local buyable = StockEngine.GetBuyableShares(state, stockId)
    if buyable <= 0 then
        return false, string.format("已达持仓上限（%d 股）", StockEngine.GetMaxShares(stock))
    end
    if shares > buyable then
        shares = buyable  -- 自动裁剪到可买数量
    end
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
    -- 称号计数
    state.stats = state.stats or {}
    state.stats.trades_completed = (state.stats.trades_completed or 0) + 1

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
    local revenue = stock.price * shares
    local costBasis = (h.avg_cost or stock.price) * shares
    local profit = revenue - costBasis
    -- 科技加成：盈利时增加收益，亏损时减少亏损
    local bonus = state.stock_return_bonus or 0
    local bonusAmount = 0
    if bonus > 0 and profit ~= 0 then
        if profit > 0 then
            -- 盈利：额外获得 profit * bonus
            bonusAmount = math.floor(profit * bonus)
        else
            -- 亏损：减少 |profit| * bonus 的亏损（bonusAmount 为正数，补偿玩家）
            bonusAmount = math.floor(math.abs(profit) * bonus)
        end
    end
    local gain = math.floor(revenue) + bonusAmount
    state.cash = state.cash + gain
    h.shares = h.shares - shares
    if h.shares <= 0 then
        state.portfolio.holdings[stockId] = nil
    end
    -- 称号计数
    state.stats = state.stats or {}
    state.stats.trades_completed = (state.stats.trades_completed or 0) + 1

    if bonusAmount > 0 then
        if profit > 0 then
            return true, string.format("卖出 %d 股 @ %.2f 获现 %d（含收益加成 +%d）",
                shares, stock.price, gain, bonusAmount)
        else
            return true, string.format("卖出 %d 股 @ %.2f 获现 %d（已减少亏损 %d）",
                shares, stock.price, gain, bonusAmount)
        end
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

-- ============================================================================
-- 做空机制
-- ============================================================================

--- 计算当前做空参数（含科技/顾问加成）
---@param state table
---@return table params { max_pct, interest, force_close_pct }
function StockEngine.GetShortParams(state)
    local Bal = require("data.balance")
    local SS = Bal.SHORT_SELLING
    local maxPct = SS.max_short_pct
    local interest = SS.interest_rate
    local forceClose = SS.force_close_pct

    -- d5_radio → 最大做空提至 40%
    if state.tech and state.tech.researched and state.tech.researched["d5_radio"] then
        maxPct = SS.radio_max_pct
    end
    -- d7_wartime_media → 强平线放宽至 90%
    if state.tech and state.tech.researched and state.tech.researched["d7_wartime_media"] then
        forceClose = SS.wartime_media_force_close
    end
    -- M3: 银行信托持股 → 融券利率优惠（原为新闻社，已解耦）
    local bankLevel = StockEngine.GetHoldingLevel(state, "austro_bank_trust")
    if bankLevel == "control" then
        interest = SS.bank_control_interest       -- 控股 → 3%
    elseif bankLevel == "influence" then
        interest = SS.bank_influence_interest      -- 重要持股 → 4%
    else
        -- diplomat bonus >= 0.5 → 利息降至 4%（优先级低于银行持股）
        local GameState = require("game_state")
        local dpBonus = GameState.GetPositionBonus(state, "diplomat")
        if dpBonus >= 0.5 then
            interest = SS.diplomat_interest
        end
    end

    return { max_pct = maxPct, interest = interest, force_close_pct = forceClose, margin_ratio = SS.margin_ratio }
end

--- 获取某支股票可做空的最大股数
---@param state table
---@param stockId string
---@return number maxShortable
function StockEngine.GetMaxShortShares(state, stockId)
    local stock = StockEngine.Find(state, stockId)
    if not stock then return 0 end
    local params = StockEngine.GetShortParams(state)
    local maxShares = StockEngine.GetMaxShares(stock)
    local maxShort = math.floor(maxShares * params.max_pct)
    -- 减去已有做空仓位
    local existing = 0
    local pos = state.portfolio and state.portfolio.short_positions
        and state.portfolio.short_positions[stockId]
    if pos then existing = pos.shares or 0 end
    return math.max(0, maxShort - existing)
end

--- 开立做空仓位
---@param state table
---@param stockId string
---@param shares number
---@return boolean ok, string|nil msg
function StockEngine.OpenShort(state, stockId, shares)
    shares = math.floor(shares or 0)
    if shares <= 0 then return false, "数量无效" end

    -- 科技前置检查
    if not (state.tech and state.tech.researched and state.tech.researched["b7_short_selling"]) then
        return false, "需先研究「卖空交易」科技"
    end

    local stock = StockEngine.Find(state, stockId)
    if not stock then return false, "股票不存在" end

    local maxShortable = StockEngine.GetMaxShortShares(state, stockId)
    if maxShortable <= 0 then return false, "已达做空上限" end
    if shares > maxShortable then shares = maxShortable end

    -- 保证金计算
    local Bal = require("data.balance")
    local margin = math.ceil(stock.price * shares * Bal.SHORT_SELLING.margin_ratio)
    if state.cash < margin then
        return false, string.format("保证金不足（需要 %d）", margin)
    end

    -- 冻结保证金
    state.cash = state.cash - margin

    -- 记录仓位
    state.portfolio = state.portfolio or {}
    state.portfolio.short_positions = state.portfolio.short_positions or {}
    local existing = state.portfolio.short_positions[stockId]
    if existing then
        -- 追加做空：合并仓位
        local totalMargin = existing.margin + margin
        local totalShares = existing.shares + shares
        local avgEntry = (existing.entry_price * existing.shares + stock.price * shares) / totalShares
        existing.shares = totalShares
        existing.entry_price = avgEntry
        existing.margin = totalMargin
        -- seasons_held 保持不变（从首次开仓算）
    else
        state.portfolio.short_positions[stockId] = {
            shares = shares,
            entry_price = stock.price,
            margin = margin,
            seasons_held = 0,
        }
    end

    local GameState = require("game_state")
    GameState.AddLog(state, string.format("做空 %s %d 股 @ %.2f，冻结保证金 %d",
        stock.name or stockId, shares, stock.price, margin))
    return true, string.format("做空 %d 股 @ %.2f，保证金 %d", shares, stock.price, margin)
end

--- 平仓做空仓位（部分或全部）
---@param state table
---@param stockId string
---@param shares number|nil nil = 全部平仓
---@return boolean ok, string|nil msg
function StockEngine.CloseShort(state, stockId, shares)
    local pos = state.portfolio and state.portfolio.short_positions
        and state.portfolio.short_positions[stockId]
    if not pos or pos.shares <= 0 then return false, "无做空仓位" end

    local stock = StockEngine.Find(state, stockId)
    if not stock then return false, "股票不存在" end

    shares = math.floor(shares or pos.shares)
    if shares <= 0 then return false, "数量无效" end
    if shares > pos.shares then shares = pos.shares end

    -- 按比例计算归还保证金
    local ratio = shares / pos.shares
    local returnMargin = math.floor(pos.margin * ratio)

    -- 浮动盈亏 = (entry_price - current_price) × shares
    local pnl = (pos.entry_price - stock.price) * shares

    -- 利息成本 = shares × current_price × interest_rate × seasons_held
    local params = StockEngine.GetShortParams(state)
    local interestCost = math.floor(shares * stock.price * params.interest * (pos.seasons_held or 0))

    -- 实际盈亏 = 浮动盈亏 - 利息成本
    local netPnl = math.floor(pnl - interestCost)

    -- 称号计数：做空盈利
    if netPnl > 0 then
        state.stats = state.stats or {}
        state.stats.short_profit_total = (state.stats.short_profit_total or 0) + netPnl
    end

    -- 结算 = 归还保证金 + 实际盈亏
    local settlement = returnMargin + netPnl
    state.cash = state.cash + math.max(0, settlement)  -- 最少归 0（极端亏损不再倒扣）

    -- 更新仓位
    pos.shares = pos.shares - shares
    pos.margin = pos.margin - returnMargin
    if pos.shares <= 0 then
        state.portfolio.short_positions[stockId] = nil
    end

    local GameState = require("game_state")
    local profitText = netPnl >= 0
        and string.format("盈利 %d", netPnl)
        or string.format("亏损 %d", -netPnl)
    GameState.AddLog(state, string.format("平仓做空 %s %d 股 @ %.2f，%s（利息 %d）",
        stock.name or stockId, shares, stock.price, profitText, interestCost))
    return true, string.format("平仓 %d 股，%s", shares, profitText)
end

--- 每季结算做空仓位：扣利息 + 检查强平 + 检查到期
---@param state table
function StockEngine.TickShorts(state)
    if not state.portfolio or not state.portfolio.short_positions then return end

    local Bal = require("data.balance")
    local SS = Bal.SHORT_SELLING
    local params = StockEngine.GetShortParams(state)
    local GameState = require("game_state")

    -- 收集需要强平的仓位（迭代中不能修改表）
    local forceCloseList = {}

    for stockId, pos in pairs(state.portfolio.short_positions) do
        if pos.shares > 0 then
            pos.seasons_held = (pos.seasons_held or 0) + 1
            local stock = StockEngine.Find(state, stockId)
            if not stock then
                table.insert(forceCloseList, stockId)
            else
                -- 检查强制平仓：亏损 >= 保证金 × force_close_pct
                local unrealizedLoss = (stock.price - pos.entry_price) * pos.shares
                if unrealizedLoss > 0 and unrealizedLoss >= pos.margin * params.force_close_pct then
                    table.insert(forceCloseList, stockId)
                    GameState.AddLog(state, string.format(
                        "⚠ %s 做空仓位触发强制平仓（亏损 %.0f，保证金 %d）",
                        stock.name or stockId, unrealizedLoss, pos.margin))
                -- 检查到期
                elseif pos.seasons_held >= SS.max_duration then
                    table.insert(forceCloseList, stockId)
                    GameState.AddLog(state, string.format(
                        "%s 做空仓位已达 %d 季上限，自动平仓",
                        stock.name or stockId, SS.max_duration))
                end
            end
        end
    end

    -- 执行强平
    for _, stockId in ipairs(forceCloseList) do
        StockEngine.CloseShort(state, stockId)
    end
end

--- 做空持仓估值（浮动盈亏总计）
---@param state table
---@return number totalPnl, number totalMargin
function StockEngine.ShortPositionValue(state)
    local totalPnl, totalMargin = 0, 0
    if not state.portfolio or not state.portfolio.short_positions then
        return 0, 0
    end
    local params = StockEngine.GetShortParams(state)
    for stockId, pos in pairs(state.portfolio.short_positions) do
        local stock = StockEngine.Find(state, stockId)
        if stock and pos.shares > 0 then
            local pnl = (pos.entry_price - stock.price) * pos.shares
            local interest = pos.shares * stock.price * params.interest * (pos.seasons_held or 0)
            totalPnl = totalPnl + math.floor(pnl - interest)
            totalMargin = totalMargin + (pos.margin or 0)
        end
    end
    return totalPnl, totalMargin
end

-- ============================================================================
-- 庄家操盘
-- ============================================================================

--- 计算操盘成功率（含文化顾问加成）
---@param state table
---@param baseSuccess number
---@return number successRate
local function calcManipulationSuccess(state, baseSuccess)
    local GameState = require("game_state")
    local cultureBonus = GameState.GetPositionBonus(state, "culture_advisor")
    -- 每 0.1 bonus 加 5% 成功率（pump）或 6%（通用取 5%）
    local bonusRate = math.floor(cultureBonus * 10) * 0.05
    -- M1: 公信力乘数（cred=100 → ×1.0, cred=0 → ×0.5）
    local credMult = StockEngine.GetCredibilityMultiplier(state)
    return math.min(1.0, (baseSuccess + bonusRate) * credMult)
end

--- 计算操盘实际资金成本（含外交总监折扣）
---@param state table
---@param baseCost number
---@param discountKey string "pump"|"dump"
---@return number actualCost
local function calcManipulationCost(state, baseCost, discountKey)
    local GameState = require("game_state")
    local Bal = require("data.balance")
    local dpBonus = GameState.GetPositionBonus(state, "diplomat")
    local discount = 0
    if dpBonus > 0 and Bal.MARKET_MANIPULATION.diplomat_discount then
        discount = Bal.MARKET_MANIPULATION.diplomat_discount[discountKey] or 0
    end
    return math.ceil(baseCost * (1 - discount))
end

--- 做多操盘
---@param state table
---@param stockId string
---@return boolean ok, string|nil msg
function StockEngine.MarketPump(state, stockId)
    local Bal = require("data.balance")
    local cfg = Bal.MARKET_MANIPULATION.pump
    local GameState = require("game_state")

    -- M2: 方向锁检查（Dump 后不能 Pump）
    local noPump = StockEngine.CheckDirectionLock(state, stockId, "no_pump")
    if noPump > 0 then
        return false, string.format("方向锁定中：该股 %d 季内不能做多操盘", noPump)
    end
    -- 冷却检查
    state.manipulation_cooldowns = state.manipulation_cooldowns or {}
    if (state.manipulation_cooldowns.pump or 0) > 0 then
        return false, string.format("做多操盘冷却中（剩余 %d 季）", state.manipulation_cooldowns.pump)
    end
    -- 前置科技检查
    if not (state.tech and state.tech.researched and state.tech.researched["d3_newspaper"]) then
        return false, "需先研究「地方报纸」科技"
    end
    -- 新闻社持股 >= stake
    local pressLevel = StockEngine.GetHoldingLevel(state, "balkan_press")
    if pressLevel == "none" then
        return false, "需持有巴尔干新闻社 ≥ 战略持股（10%）"
    end
    -- AP 检查
    if (state.ap.current + (state.ap.temp or 0)) < cfg.ap then
        return false, "行动点不足"
    end

    local stock = StockEngine.Find(state, stockId)
    if not stock then return false, "股票不存在" end

    -- 资金计算
    local maxShares = StockEngine.GetMaxShares(stock)
    local marketCap = stock.price * maxShares
    local baseCost = math.ceil(marketCap * cfg.cost_ratio)
    local actualCost = calcManipulationCost(state, baseCost, "pump")

    if state.cash < math.max(cfg.min_cash, actualCost) then
        return false, string.format("资金不足（需要 %d）", math.max(cfg.min_cash, actualCost))
    end

    -- 消耗 AP + 资金
    GameState.SpendAP(state, cfg.ap)
    state.cash = state.cash - actualCost

    -- 成功率判定
    local successRate = calcManipulationSuccess(state, cfg.base_success)
    local roll = math.random()

    if roll <= successRate then
        -- 成功：注入 delta_mu
        StockEngine.InjectMod(stock, cfg.delta_mu, cfg.duration, "market_pump")
        state.manipulation_cooldowns.pump = cfg.cooldown
        -- 称号计数
        state.stats = state.stats or {}
        state.stats.manipulation_successes = (state.stats.manipulation_successes or 0) + 1
        -- M2: Pump 成功后不能对该股 Dump
        local DL = Bal.DIRECTION_LOCK
        StockEngine.SetDirectionLock(state, stockId, "no_dump", DL.after_pump)
        -- M1: 消耗公信力
        StockEngine.ConsumeCredibility(state, "pump", true)
        GameState.AddLog(state, string.format(
            "📈 做多操盘成功：%s delta_mu +%.2f 持续 %d 季（投入 %d，公信力 %d）",
            stock.name or stockId, cfg.delta_mu, cfg.duration, actualCost,
            state.press_credibility or 0))
        -- M4: AI 对手盘反制
        StockEngine.TryAICounterparty(state, stockId, "pump")
        return true, string.format("操盘成功！%s 将受到做多推动（投入 %d）",
            stock.name or stockId, actualCost)
    else
        -- 失败：损失部分资金
        local lostExtra = math.floor(actualCost * cfg.fail_loss)
        state.cash = state.cash - math.min(lostExtra, state.cash)
        state.manipulation_cooldowns.pump = cfg.cooldown
        -- M1: 失败也消耗公信力（且消耗更多）
        StockEngine.ConsumeCredibility(state, "pump", false)
        GameState.AddLog(state, string.format(
            "📉 做多操盘失败：%s 操盘被识破，额外损失 %d（公信力 %d）",
            stock.name or stockId, lostExtra, state.press_credibility or 0))
        return false, string.format("操盘失败！被市场识破，额外损失 %d", lostExtra)
    end
end

--- 做空操盘
---@param state table
---@param stockId string
---@return boolean ok, string|nil msg
function StockEngine.MarketDump(state, stockId)
    local Bal = require("data.balance")
    local cfg = Bal.MARKET_MANIPULATION.dump
    local GameState = require("game_state")

    -- M2: 方向锁检查（Pump 后不能 Dump）
    local noDump = StockEngine.CheckDirectionLock(state, stockId, "no_dump")
    if noDump > 0 then
        return false, string.format("方向锁定中：该股 %d 季内不能做空操盘", noDump)
    end
    -- 冷却检查
    state.manipulation_cooldowns = state.manipulation_cooldowns or {}
    if (state.manipulation_cooldowns.dump or 0) > 0 then
        return false, string.format("做空操盘冷却中（剩余 %d 季）", state.manipulation_cooldowns.dump)
    end
    -- 前置科技检查
    if not (state.tech and state.tech.researched and state.tech.researched["d5_radio"]) then
        return false, "需先研究「广播电台」科技"
    end
    -- 新闻社持股 >= influence
    local pressLevel = StockEngine.GetHoldingLevel(state, "balkan_press")
    if pressLevel ~= "influence" and pressLevel ~= "control" then
        return false, "需持有巴尔干新闻社 ≥ 重要持股（30%）"
    end
    -- AP 检查
    if (state.ap.current + (state.ap.temp or 0)) < cfg.ap then
        return false, "行动点不足"
    end

    local stock = StockEngine.Find(state, stockId)
    if not stock then return false, "股票不存在" end

    -- 资金计算
    local maxShares = StockEngine.GetMaxShares(stock)
    local marketCap = stock.price * maxShares
    local baseCost = math.ceil(marketCap * cfg.cost_ratio)
    local actualCost = calcManipulationCost(state, baseCost, "dump")

    if state.cash < math.max(cfg.min_cash, actualCost) then
        return false, string.format("资金不足（需要 %d）", math.max(cfg.min_cash, actualCost))
    end

    -- 消耗 AP + 资金
    GameState.SpendAP(state, cfg.ap)
    state.cash = state.cash - actualCost

    -- 成功率判定
    local successRate = calcManipulationSuccess(state, cfg.base_success)
    local roll = math.random()

    if roll <= successRate then
        -- 成功：注入 delta_mu（下跌 + 延迟反弹）
        StockEngine.InjectMod(stock, cfg.delta_mu, cfg.duration, "market_dump")
        StockEngine.InjectMod(stock, cfg.rebound_mu, cfg.duration + cfg.rebound_dur, "market_dump_rebound")
        state.manipulation_cooldowns.dump = cfg.cooldown
        -- 称号计数
        state.stats = state.stats or {}
        state.stats.manipulation_successes = (state.stats.manipulation_successes or 0) + 1
        -- M2: Dump 成功后不能对该股 Pump
        local DL = Bal.DIRECTION_LOCK
        StockEngine.SetDirectionLock(state, stockId, "no_pump", DL.after_dump)
        -- M1: 消耗公信力
        StockEngine.ConsumeCredibility(state, "dump", true)
        GameState.AddLog(state, string.format(
            "📉 做空操盘成功：%s delta_mu %.2f 持续 %d 季（投入 %d，公信力 %d）",
            stock.name or stockId, cfg.delta_mu, cfg.duration, actualCost,
            state.press_credibility or 0))
        -- M4: AI 对手盘反制
        StockEngine.TryAICounterparty(state, stockId, "dump")
        return true, string.format("操盘成功！%s 将受到做空打压（投入 %d）",
            stock.name or stockId, actualCost)
    else
        -- 失败：资金损失 + 目标股反向上涨
        local lostExtra = math.floor(actualCost * cfg.fail_loss)
        state.cash = state.cash - math.min(lostExtra, state.cash)
        StockEngine.InjectMod(stock, cfg.fail_rebound_mu, cfg.fail_rebound_dur, "dump_fail_rebound")
        state.manipulation_cooldowns.dump = cfg.cooldown
        -- M1: 失败也消耗公信力（且消耗更多）
        StockEngine.ConsumeCredibility(state, "dump", false)
        GameState.AddLog(state, string.format(
            "📈 做空操盘失败：%s 反向上涨，额外损失 %d（公信力 %d）",
            stock.name or stockId, lostExtra, state.press_credibility or 0))
        return false, string.format("操盘失败！%s 反向上涨，额外损失 %d",
            stock.name or stockId, lostExtra)
    end
end

--- 联合操盘（同时做多一只 + 做空一只）
---@param state table
---@param pumpStockId string 做多目标
---@param dumpStockId string 做空目标
---@return boolean ok, string|nil msg
function StockEngine.CoordinatedOp(state, pumpStockId, dumpStockId)
    local Bal = require("data.balance")
    local cfg = Bal.MARKET_MANIPULATION.coordinated
    local GameState = require("game_state")

    -- 两个目标不能相同
    if pumpStockId == dumpStockId then
        return false, "做多和做空目标不能是同一只股票"
    end
    -- M2: 方向锁检查（联合操盘的两个方向分别检查）
    local noPumpLock = StockEngine.CheckDirectionLock(state, pumpStockId, "no_pump")
    if noPumpLock > 0 then
        return false, string.format("方向锁定中：做多目标 %d 季内不能做多操盘", noPumpLock)
    end
    local noDumpLock = StockEngine.CheckDirectionLock(state, dumpStockId, "no_dump")
    if noDumpLock > 0 then
        return false, string.format("方向锁定中：做空目标 %d 季内不能做空操盘", noDumpLock)
    end
    -- 冷却检查
    state.manipulation_cooldowns = state.manipulation_cooldowns or {}
    if (state.manipulation_cooldowns.coordinated or 0) > 0 then
        return false, string.format("联合操盘冷却中（剩余 %d 季）", state.manipulation_cooldowns.coordinated)
    end
    -- 前置科技检查
    if not (state.tech and state.tech.researched and state.tech.researched["d7_wartime_media"]) then
        return false, "需先研究「战时媒体管控」科技"
    end
    -- 新闻社 >= control
    local pressLevel = StockEngine.GetHoldingLevel(state, "balkan_press")
    if pressLevel ~= "control" then
        return false, "需持有巴尔干新闻社 ≥ 控股（60%）"
    end
    -- 文化顾问 bonus >= 0.8
    local cultureBonus = GameState.GetPositionBonus(state, "culture_advisor")
    if cultureBonus < 0.8 then
        return false, "需要文化顾问加成 ≥ 0.8"
    end
    -- AP 检查
    if (state.ap.current + (state.ap.temp or 0)) < cfg.ap then
        return false, "行动点不足"
    end

    local pumpStock = StockEngine.Find(state, pumpStockId)
    local dumpStock = StockEngine.Find(state, dumpStockId)
    if not pumpStock then return false, "做多目标不存在" end
    if not dumpStock then return false, "做空目标不存在" end

    -- 固定资金
    if state.cash < cfg.fixed_cost then
        return false, string.format("资金不足（需要 %d）", cfg.fixed_cost)
    end

    -- 消耗 AP + 资金
    GameState.SpendAP(state, cfg.ap)
    state.cash = state.cash - cfg.fixed_cost

    -- 成功率
    local successRate = calcManipulationSuccess(state, cfg.base_success)
    local roll = math.random()

    if roll <= successRate then
        -- 成功：两只股票同时注入
        StockEngine.InjectMod(pumpStock, cfg.pump_mu, cfg.duration, "coordinated_pump")
        StockEngine.InjectMod(dumpStock, cfg.dump_mu, cfg.duration, "coordinated_dump")
        state.manipulation_cooldowns.coordinated = cfg.cooldown
        -- 称号计数
        state.stats = state.stats or {}
        state.stats.manipulation_successes = (state.stats.manipulation_successes or 0) + 1
        -- M2: 联合操盘成功后设方向锁
        local DL = Bal.DIRECTION_LOCK
        StockEngine.SetDirectionLock(state, pumpStockId, "no_dump", DL.after_pump)
        StockEngine.SetDirectionLock(state, dumpStockId, "no_pump", DL.after_dump)
        -- M1: 联合操盘消耗更多公信力
        StockEngine.ConsumeCredibility(state, "coordinated", true)
        GameState.AddLog(state, string.format(
            "⚡ 联合操盘成功：%s ↑ / %s ↓ 持续 %d 季（投入 %d，公信力 %d）",
            pumpStock.name or pumpStockId, dumpStock.name or dumpStockId,
            cfg.duration, cfg.fixed_cost, state.press_credibility or 0))
        -- M4: AI 对手盘反制（对做多和做空目标分别尝试）
        StockEngine.TryAICounterparty(state, pumpStockId, "pump")
        StockEngine.TryAICounterparty(state, dumpStockId, "dump")
        return true, string.format("联合操盘成功！%s ↑ / %s ↓",
            pumpStock.name or pumpStockId, dumpStock.name or dumpStockId)
    else
        -- 失败：资金损失 + 声誉惩罚
        local lostExtra = math.floor(cfg.fixed_cost * cfg.fail_loss)
        state.cash = state.cash - math.min(lostExtra, state.cash)
        state.reputation = (state.reputation or 0) + cfg.fail_rep
        state.manipulation_cooldowns.coordinated = cfg.cooldown
        -- M1: 失败也消耗公信力（且消耗更多）
        StockEngine.ConsumeCredibility(state, "coordinated", false)
        GameState.AddLog(state, string.format(
            "💥 联合操盘失败：操盘败露，额外损失 %d，声誉 %d（公信力 %d）",
            lostExtra, cfg.fail_rep, state.press_credibility or 0))
        return false, string.format("联合操盘失败！损失 %d，声誉 %d", lostExtra, cfg.fail_rep)
    end
end

--- 每季递减操盘冷却
---@param state table
function StockEngine.TickManipulationCooldowns(state)
    local cd = state.manipulation_cooldowns
    if not cd then return end
    if (cd.pump or 0) > 0 then cd.pump = cd.pump - 1 end
    if (cd.dump or 0) > 0 then cd.dump = cd.dump - 1 end
    if (cd.coordinated or 0) > 0 then cd.coordinated = cd.coordinated - 1 end
end

-- ============================================================================
-- M1: 媒体公信力（操盘消耗性资源）
-- ============================================================================

--- 获取公信力对成功率的乘数
---@param state table
---@return number multiplier [multiplier_floor, 1.0]
function StockEngine.GetCredibilityMultiplier(state)
    local Bal = require("data.balance")
    local C = Bal.CREDIBILITY
    local cred = state.press_credibility or C.initial
    local floor = C.multiplier_floor
    return floor + (1.0 - floor) * (cred / C.max)
end

--- 消耗公信力
---@param state table
---@param costKey string "pump"|"dump"|"coordinated"
---@param success boolean 是否操盘成功
function StockEngine.ConsumeCredibility(state, costKey, success)
    local Bal = require("data.balance")
    local C = Bal.CREDIBILITY
    local baseCost = C["cost_" .. costKey] or 15
    local cost = success and baseCost or math.ceil(baseCost * C.cost_fail_mult)
    state.press_credibility = math.max(0, (state.press_credibility or C.initial) - cost)
end

--- 每季恢复公信力（含新闻社持股加成）
---@param state table
function StockEngine.TickCredibility(state)
    local Bal = require("data.balance")
    local C = Bal.CREDIBILITY
    if not state.press_credibility then
        state.press_credibility = C.initial
    end
    local recovery = C.recovery_per_season
    -- 新闻社持股加速恢复
    local pressLevel = StockEngine.GetHoldingLevel(state, "balkan_press")
    if pressLevel == "control" then
        recovery = recovery + C.press_control_recovery_bonus
    elseif pressLevel == "influence" then
        recovery = recovery + C.press_influence_recovery_bonus
    end
    state.press_credibility = math.min(C.max, state.press_credibility + recovery)
end

-- ============================================================================
-- M2: 方向互斥锁（同一股票买/空方向冷却）
-- ============================================================================

--- 设置方向锁
---@param state table
---@param stockId string
---@param lockType string "no_buy"|"no_short"
---@param duration number 冷却季数
function StockEngine.SetDirectionLock(state, stockId, lockType, duration)
    if not duration or duration <= 0 then return end
    state.direction_locks = state.direction_locks or {}
    state.direction_locks[stockId] = state.direction_locks[stockId] or {}
    local cur = state.direction_locks[stockId][lockType] or 0
    state.direction_locks[stockId][lockType] = math.max(cur, duration)
end

--- 检查方向锁剩余冷却
---@param state table
---@param stockId string
---@param lockType string "no_buy"|"no_short"
---@return number remaining 剩余季数（0 = 无锁）
function StockEngine.CheckDirectionLock(state, stockId, lockType)
    if not state.direction_locks then return 0 end
    local locks = state.direction_locks[stockId]
    if not locks then return 0 end
    return math.max(0, locks[lockType] or 0)
end

--- 每季递减所有方向锁
---@param state table
function StockEngine.TickDirectionLocks(state)
    if not state.direction_locks then return end
    for stockId, locks in pairs(state.direction_locks) do
        local empty = true
        for lockType, remaining in pairs(locks) do
            if remaining > 0 then
                locks[lockType] = remaining - 1
                if locks[lockType] > 0 then empty = false end
            end
        end
        if empty then
            state.direction_locks[stockId] = nil
        end
    end
end

-- ============================================================================
-- M4: AI 对手盘（外资反向交易）
-- ============================================================================

--- 尝试 AI 对手盘反向交易（在操盘成功后调用）
---@param state table
---@param stockId string 被操盘的股票ID
---@param manipType string "pump"|"dump"
---@return boolean triggered 是否触发了反制
function StockEngine.TryAICounterparty(state, stockId, manipType)
    local Bal = require("data.balance")
    local AC = Bal.AI_COUNTERPARTY
    local GameState = require("game_state")

    -- 查找外资 AI
    local foreign = nil
    for _, f in ipairs(state.ai_factions or {}) do
        if f.type == "foreign_capital" and not f.defeated then
            foreign = f
            break
        end
    end
    if not foreign then return false end

    -- 现金门槛
    if (foreign.cash or 0) < AC.min_foreign_cash then return false end

    -- 基础概率
    local baseChance = AC.react_chance[manipType] or 0
    if baseChance <= 0 then return false end

    -- 现金规模修正: [0.5, 1.5]
    local cashScale
    if foreign.cash >= AC.cash_scale_max then
        cashScale = 1.5
    elseif foreign.cash >= AC.cash_scale_base then
        cashScale = 1.0 + 0.5 * (foreign.cash - AC.cash_scale_base) / (AC.cash_scale_max - AC.cash_scale_base)
    else
        cashScale = 0.5 + 0.5 * (foreign.cash / AC.cash_scale_base)
    end

    -- 公信力联动: 公信力越低，AI 越容易识破
    -- credMult ∈ [0.5, 1.0], 所以 (2.0 - credMult) ∈ [1.0, 1.5]
    local credMult = StockEngine.GetCredibilityMultiplier(state)
    local credFactor = 2.0 - credMult

    local finalChance = baseChance * cashScale * credFactor
    finalChance = math.min(finalChance, 0.85) -- 概率上限 85%

    local roll = math.random()
    if roll > finalChance then return false end

    -- 触发反制
    local stock = StockEngine.Find(state, stockId)
    if not stock then return false end

    local counterMu = AC.counter_mu[manipType]
    if not counterMu then return false end

    -- 注入反向 delta_mu
    StockEngine.InjectMod(stock, counterMu, AC.counter_duration, "ai_counter_" .. manipType)

    -- 外资消耗现金
    local maxShares = StockEngine.GetMaxShares(stock)
    local marketCap = stock.price * maxShares
    local counterCost = math.floor(marketCap * AC.counter_cost_ratio)
    counterCost = math.min(counterCost, foreign.cash)
    foreign.cash = foreign.cash - counterCost

    -- 记录日志
    GameState.AddLog(state, string.format(
        "🏦 外资反制：%s 检测到操盘，注入反向 delta_mu %.2f 持续 %d 季（外资投入 %d，概率 %.0f%%）",
        stock.name or stockId, counterMu, AC.counter_duration,
        counterCost, finalChance * 100))

    -- 记录到 state 以供 UI 显示
    state.last_ai_counter = {
        stockId = stockId,
        manipType = manipType,
        counterMu = counterMu,
        counterCost = counterCost,
        chance = finalChance,
    }

    return true
end

return StockEngine
