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
--
-- 6 只股票 ID：
--   sarajevo_mining    萨拉热窝矿业
--   imperial_railway   帝国铁路
--   balkan_shipping    巴尔干航运
--   military_industry  军工产业
--   austro_bank_trust  奥地利银行信托
--   oriental_trading   东方贸易公司
-- ============================================================================

local EventMarketEffects = {}

EventMarketEffects.BY_EVENT_ID = {

    -- ==================== 固定历史事件 ====================

    -- 1904 家族创业：矿业股小幅看涨
    ["family_founding_1904"] = {
        { stock_id = "sarajevo_mining", delta_mu = 0.04, duration = 3 },
    },

    -- 1906 铁路测量：铁路股利好，矿业也受提振
    ["railway_survey_1906"] = {
        { stock_id = "imperial_railway",  delta_mu = 0.06, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu = 0.03, duration = 3 },
    },

    -- 1907 矿工宿舍：矿业小幅承压（成本增加）
    ["worker_barracks_1907"] = {
        { stock_id = "sarajevo_mining", delta_mu = -0.03, duration = 2 },
    },

    -- 1908 帝国管制：税负加重，矿业承压，银行受益
    ["imperial_control_1908"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.05, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu =  0.03, duration = 4 },
    },

    -- 1910 波黑议会：政治稳定利好全市场
    ["bosnian_parliament_1910"] = {
        { stock_id = "austro_bank_trust", delta_mu = 0.03, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu = 0.02, duration = 3 },
    },

    -- 1912 巴尔干战云：军工铁路受益，航运受挫
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

    -- 1914 战争动员：军工和铁路继续上涨
    ["war_mobilization_1914"] = {
        { stock_id = "military_industry", delta_mu =  0.18, duration = 6 },
        { stock_id = "imperial_railway",  delta_mu =  0.06, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu =  0.05, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu = -0.10, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu = -0.06, duration = 4 },
    },

    -- 1915 战时通胀：矿业受通胀推动，银行承压
    ["wartime_inflation_1915"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.06, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu = -0.08, duration = 4 },
        { stock_id = "military_industry", delta_mu =  0.05, duration = 3 },
    },

    -- 1916 物资短缺：军工获利，航运和贸易暴跌
    ["wartime_shortage_1916"] = {
        { stock_id = "military_industry", delta_mu =  0.10, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu = -0.15, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu = -0.12, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu =  0.04, duration = 3 },
    },

    -- 1917 兵变与逃亡潮：全市场恐慌，军工也开始回调
    ["mutiny_wave_1917"] = {
        { stock_id = "military_industry", delta_mu = -0.06, duration = 3 },
        { stock_id = "austro_bank_trust", delta_mu = -0.08, duration = 3 },
        { stock_id = "imperial_railway",  delta_mu = -0.05, duration = 3 },
        { stock_id = "sarajevo_mining",   delta_mu = -0.04, duration = 2 },
    },

    -- 1917 俄国革命：全市场震荡，工人运动对矿业不利
    ["russian_revolution_1917"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.08, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu = -0.10, duration = 4 },
        { stock_id = "military_industry", delta_mu = -0.04, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu = -0.06, duration = 3 },
    },

    -- 1918 帝国崩解：全市场重估，金融股重挫，军工回落
    ["empire_collapse_1918"] = {
        { stock_id = "military_industry", delta_mu = -0.18, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu = -0.20, duration = 6 },
        { stock_id = "imperial_railway",  delta_mu = -0.10, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu = -0.08, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu = -0.06, duration = 4 },
    },

    -- 1919 SHS王国：政治重组，铁路和贸易逐步恢复
    ["kingdom_shs_1919"] = {
        { stock_id = "imperial_railway",  delta_mu =  0.04, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu =  0.05, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu =  0.03, duration = 3 },
        { stock_id = "austro_bank_trust", delta_mu = -0.04, duration = 3 },
    },

    -- 1920 工会化浪潮：矿业承压
    ["unionization_wave_1920"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.08, duration = 4 },
        { stock_id = "military_industry", delta_mu = -0.03, duration = 2 },
    },

    -- 1922 战后通胀高峰：实物资产涨，金融股跌
    ["postwar_inflation_1922"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.10, duration = 6 },
        { stock_id = "austro_bank_trust", delta_mu = -0.15, duration = 6 },
        { stock_id = "oriental_trading",  delta_mu = -0.08, duration = 4 },
        { stock_id = "military_industry", delta_mu =  0.04, duration = 3 },
    },

    -- 1923 铁路国有化：铁路股重挫
    ["railway_nationalization_1923"] = {
        { stock_id = "imperial_railway",  delta_mu = -0.20, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu = -0.04, duration = 3 },
        { stock_id = "balkan_shipping",   delta_mu =  0.06, duration = 3 },
    },

    -- 1925 矿业现代化：矿业大利好
    ["mining_modernization_1925"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.12, duration = 4 },
        { stock_id = "imperial_railway",  delta_mu =  0.04, duration = 3 },
    },

    -- 1926 英国大罢工：矿业和航运受益
    ["uk_general_strike_1926"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.15, duration = 3 },
        { stock_id = "balkan_shipping",   delta_mu =  0.10, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu =  0.06, duration = 3 },
    },

    -- 1928 议会枪击：全市场恐慌
    ["political_crisis_1928"] = {
        { stock_id = "austro_bank_trust", delta_mu = -0.10, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu = -0.06, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu = -0.05, duration = 3 },
        { stock_id = "imperial_railway",  delta_mu = -0.04, duration = 3 },
    },

    -- 1929 国王独裁：政治不确定性，市场波动
    ["royal_dictatorship_1929"] = {
        { stock_id = "austro_bank_trust", delta_mu = -0.06, duration = 4 },
        { stock_id = "military_industry", delta_mu =  0.05, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu = -0.04, duration = 3 },
    },

    -- 1929 大萧条：全面崩盘
    ["great_depression_1929"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.20, duration = 8 },
        { stock_id = "austro_bank_trust", delta_mu = -0.30, duration = 8 },
        { stock_id = "imperial_railway",  delta_mu = -0.15, duration = 6 },
        { stock_id = "balkan_shipping",   delta_mu = -0.18, duration = 6 },
        { stock_id = "oriental_trading",  delta_mu = -0.22, duration = 6 },
        { stock_id = "military_industry", delta_mu = -0.10, duration = 4 },
    },

    -- 1931 银行挤兑：银行信托暴跌
    ["bank_run_1931"] = {
        { stock_id = "austro_bank_trust", delta_mu = -0.25, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu = -0.08, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu = -0.06, duration = 3 },
    },

    -- 1933 法西斯思潮：军工上涨，贸易分化
    ["fascist_tide_1933"] = {
        { stock_id = "military_industry", delta_mu =  0.10, duration = 6 },
        { stock_id = "sarajevo_mining",   delta_mu =  0.06, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu = -0.04, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu = -0.03, duration = 3 },
    },

    -- 1934 国王遇刺：政治恐慌
    ["king_assassination_1934"] = {
        { stock_id = "austro_bank_trust", delta_mu = -0.10, duration = 4 },
        { stock_id = "imperial_railway",  delta_mu = -0.06, duration = 3 },
        { stock_id = "sarajevo_mining",   delta_mu = -0.04, duration = 3 },
        { stock_id = "military_industry", delta_mu =  0.06, duration = 4 },
    },

    -- 1936 德国重新武装：军工和矿业利好
    ["german_rearmament_1936"] = {
        { stock_id = "military_industry", delta_mu =  0.15, duration = 6 },
        { stock_id = "sarajevo_mining",   delta_mu =  0.10, duration = 6 },
        { stock_id = "imperial_railway",  delta_mu =  0.06, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu =  0.04, duration = 4 },
    },

    -- 1937 西班牙内战：影响不大，军工微涨
    ["spanish_civil_war_1937"] = {
        { stock_id = "military_industry", delta_mu = 0.04, duration = 3 },
    },

    -- 1938 慕尼黑协定：恐慌+军工
    ["munich_agreement_1938"] = {
        { stock_id = "military_industry", delta_mu =  0.12, duration = 6 },
        { stock_id = "sarajevo_mining",   delta_mu =  0.08, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu = -0.08, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu = -0.06, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu = -0.05, duration = 4 },
    },

    -- 1939 二战爆发：大分化
    ["wwii_outbreak_1939"] = {
        { stock_id = "military_industry", delta_mu =  0.25, duration = 8 },
        { stock_id = "sarajevo_mining",   delta_mu =  0.12, duration = 6 },
        { stock_id = "imperial_railway",  delta_mu =  0.06, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu = -0.15, duration = 6 },
        { stock_id = "austro_bank_trust", delta_mu = -0.10, duration = 6 },
        { stock_id = "oriental_trading",  delta_mu = -0.12, duration = 6 },
    },

    -- 1941 轴心国最后通牒：全市场恐慌
    ["axis_ultimatum_1941"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.12, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu = -0.15, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu = -0.18, duration = 4 },
        { stock_id = "military_industry", delta_mu =  0.15, duration = 6 },
        { stock_id = "oriental_trading",  delta_mu = -0.10, duration = 4 },
    },

    -- 1941 旧秩序瓦解：除军工外全面崩盘
    ["old_order_collapse_1941"] = {
        { stock_id = "military_industry", delta_mu =  0.20, duration = 8 },
        { stock_id = "sarajevo_mining",   delta_mu = -0.15, duration = 6 },
        { stock_id = "austro_bank_trust", delta_mu = -0.25, duration = 6 },
        { stock_id = "imperial_railway",  delta_mu = -0.18, duration = 6 },
        { stock_id = "balkan_shipping",   delta_mu = -0.20, duration = 6 },
        { stock_id = "oriental_trading",  delta_mu = -0.15, duration = 6 },
    },

    -- 1942 游击战：全面动荡
    ["partisan_warfare_1942"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.10, duration = 4 },
        { stock_id = "military_industry", delta_mu =  0.08, duration = 4 },
        { stock_id = "imperial_railway",  delta_mu = -0.12, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu = -0.10, duration = 4 },
    },

    -- 1943 意大利投降：航运短暂恢复，军工持平
    ["italy_surrender_1943"] = {
        { stock_id = "balkan_shipping",   delta_mu =  0.08, duration = 3 },
        { stock_id = "military_industry", delta_mu = -0.04, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu =  0.06, duration = 3 },
    },

    -- 1944 盟军轰炸：工业股全面受损
    ["allied_bombing_1944"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.15, duration = 4 },
        { stock_id = "imperial_railway",  delta_mu = -0.20, duration = 4 },
        { stock_id = "military_industry", delta_mu = -0.10, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu = -0.08, duration = 3 },
    },

    -- 1945 新政权：重新洗牌
    ["new_regime_1945"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.10, duration = 4 },
        { stock_id = "military_industry", delta_mu = -0.15, duration = 4 },
        { stock_id = "austro_bank_trust", delta_mu = -0.12, duration = 4 },
        { stock_id = "oriental_trading",  delta_mu =  0.06, duration = 4 },
        { stock_id = "balkan_shipping",   delta_mu =  0.08, duration = 4 },
    },

    -- ==================== 随机事件 ====================

    ["mine_accident"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.15, duration = 2 },
        { stock_id = "military_industry", delta_mu =  0.04, duration = 2 },
    },

    ["worker_strike"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.10, duration = 2 },
    },

    ["foreign_investors"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.06, duration = 3 },
        { stock_id = "austro_bank_trust", delta_mu =  0.05, duration = 3 },
    },

    ["ore_vein_discovery"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.12, duration = 3 },
    },

    ["local_pressure"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.04, duration = 2 },
    },

    ["gold_price_surge"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.08, duration = 2 },
        { stock_id = "oriental_trading",  delta_mu =  0.04, duration = 2 },
    },

    ["smuggling_route"] = {
        { stock_id = "oriental_trading",  delta_mu =  0.06, duration = 3 },
        { stock_id = "balkan_shipping",   delta_mu =  0.04, duration = 2 },
    },

    ["disease_outbreak"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.12, duration = 2 },
    },

    ["brain_drain"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.05, duration = 3 },
    },

    ["natural_disaster"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.10, duration = 2 },
        { stock_id = "imperial_railway",  delta_mu = -0.06, duration = 2 },
    },

    ["commodity_boom"] = {
        { stock_id = "sarajevo_mining",   delta_mu =  0.12, duration = 3 },
        { stock_id = "balkan_shipping",   delta_mu =  0.06, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu =  0.04, duration = 2 },
    },

    ["currency_crisis"] = {
        { stock_id = "austro_bank_trust", delta_mu = -0.15, duration = 4 },
        { stock_id = "sarajevo_mining",   delta_mu =  0.06, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu = -0.08, duration = 3 },
    },

    ["espionage_scandal"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.04, duration = 2 },
        { stock_id = "military_industry", delta_mu =  0.03, duration = 2 },
    },

    ["drought_famine"] = {
        { stock_id = "sarajevo_mining",   delta_mu = -0.06, duration = 3 },
        { stock_id = "oriental_trading",  delta_mu =  0.05, duration = 3 },
    },
}

--- 获取某事件对应的股价效果列表
---@param eventId string
---@return table[]|nil
function EventMarketEffects.Get(eventId)
    return EventMarketEffects.BY_EVENT_ID[eventId]
end

return EventMarketEffects
