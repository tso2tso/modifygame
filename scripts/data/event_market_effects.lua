-- ============================================================================
-- 事件 → 股价（mu 偏移）映射表
-- 当事件被玩家处理（选择任一选项）后，此映射会向相关股票注入短期 delta_mu
-- 这是 GBM 分层模型的第三层：让价格走势有叙事因果，而不只是随机噪声
--
-- 数据格式：
--   [<event_id>] = {
--       { stock_id, delta_mu, duration },
--       ...
--   }
--
-- 参数意义：
--   delta_mu  季度 mu 偏移量（+0.15 表示未来 N 季 +15% 漂移）
--   duration  持续季度数（被 StockEngine.UpdateAll 消费一次减一次）
-- ============================================================================

local EventMarketEffects = {}

EventMarketEffects.BY_EVENT_ID = {
    -- 1904 家族创业：矿业股小幅看涨（玩家存在本身提振同行）
    ["family_founding_1904"] = {
        { stock_id = "sarajevo_mining", delta_mu = 0.04, duration = 3 },
    },

    -- 1908 帝国管制：税负加重，矿业承压，银行信托受益（更多借贷需求）
    ["imperial_control_1908"] = {
        { stock_id = "sarajevo_mining",  delta_mu = -0.05, duration = 4 },
        { stock_id = "austro_bank_trust",delta_mu =  0.03, duration = 4 },
    },

    -- 1912 巴尔干战云：军工与铁路受益，航运受挫
    ["balkan_wars_1912"] = {
        { stock_id = "military_industry", delta_mu =  0.12, duration = 4 },
        { stock_id = "imperial_railway",  delta_mu =  0.04, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu = -0.08, duration = 4 },
    },

    -- 1914 萨拉热窝枪声：战时军工暴涨、航运崩溃、银行挤兑
    ["sarajevo_shots_1914"] = {
        { stock_id = "military_industry", delta_mu =  0.30, duration = 6 },
        { stock_id = "imperial_railway",  delta_mu =  0.08, duration = 6 },
        { stock_id = "balkan_shipping",   delta_mu = -0.22, duration = 6 },
        { stock_id = "austro_bank_trust", delta_mu = -0.12, duration = 6 },
        { stock_id = "oriental_trading",  delta_mu = -0.10, duration = 4 },
    },

    -- 1918 帝国崩解：全市场重估，金融股重挫，军工回落
    ["empire_collapse_1918"] = {
        { stock_id = "military_industry", delta_mu = -0.18, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu = -0.20, duration = 6 },
        { stock_id = "imperial_railway",  delta_mu = -0.10, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu = -0.08, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu = -0.06, duration = 4 },
    },

    -- 随机事件：矿难
    ["mine_accident"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.15, duration = 2 },
        { stock_id = "military_industry", delta_mu =  0.04, duration = 2 },
    },

    -- 工人罢工：矿业承压
    ["worker_strike"] = {
        { stock_id = "sarajevo_mining", delta_mu = -0.10, duration = 2 },
    },

    -- 外资考察团：银行信托与矿业双受益
    ["foreign_investors"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.06, duration = 3 },
        { stock_id = "austro_bank_trust", delta_mu =  0.05, duration = 3 },
    },
}

--- 获取某事件对应的股价效果列表
---@param eventId string
---@return table[]|nil
function EventMarketEffects.Get(eventId)
    return EventMarketEffects.BY_EVENT_ID[eventId]
end

return EventMarketEffects
