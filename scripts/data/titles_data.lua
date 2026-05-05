-- ============================================================================
-- 称号数据定义  titles_data.lua
-- 18 个称号 × 5 大类，条件偏后期（每类有一个入门称号）
-- ============================================================================

local TitlesData = {}

--- 称号类别
TitlesData.CATEGORIES = {
    { id = "military",      label = "军事",   icon = "⚔️" },
    { id = "plunder",       label = "掠夺",   icon = "🏴" },
    { id = "economy",       label = "经济",   icon = "💰" },
    { id = "stock",         label = "证券",   icon = "📈" },
    { id = "comprehensive", label = "综合",   icon = "🏛️" },
}

--- 所有称号定义
--- check(state, stats) → boolean
TitlesData.TITLES = {

    -- ================================================================
    -- 军事（4）
    -- ================================================================
    {
        id       = "first_blood",
        name     = "初战告捷",
        desc     = "赢得第一场战斗",
        category = "military",
        icon     = "🗡️",
        check    = function(state, stats)
            return (state.battle_wins_total or 0) >= 1
        end,
    },
    {
        id       = "warmonger",
        name     = "战争狂人",
        desc     = "主动发起 30 次攻击",
        category = "military",
        icon     = "🔥",
        check    = function(state, stats)
            return (stats.attacks_initiated or 0) >= 30
        end,
    },
    {
        id       = "ever_victorious",
        name     = "常胜将军",
        desc     = "累计赢得 25 场战斗",
        category = "military",
        icon     = "🏆",
        check    = function(state, stats)
            return (state.battle_wins_total or 0) >= 25
        end,
    },
    {
        id       = "iron_wall",
        name     = "铁壁防线",
        desc     = "拥有 40+ 武装且装备等级达到 5",
        category = "military",
        icon     = "🛡️",
        check    = function(state, stats)
            local mil = state.military or {}
            return (mil.guards or 0) >= 40 and (mil.equipment or 0) >= 5
        end,
    },

    -- ================================================================
    -- 掠夺（3）
    -- ================================================================
    {
        id       = "bandit_baron",
        name     = "劫匪男爵",
        desc     = "成功掠夺 3 次",
        category = "plunder",
        icon     = "🗡️",
        check    = function(state, stats)
            return (stats.plunder_successes or 0) >= 3
        end,
    },
    {
        id       = "balkan_wolf",
        name     = "巴尔干之狼",
        desc     = "成功掠夺 15 次",
        category = "plunder",
        icon     = "🐺",
        check    = function(state, stats)
            return (stats.plunder_successes or 0) >= 15
        end,
    },
    {
        id       = "infamous",
        name     = "臭名昭著",
        desc     = "声誉降至 -80 以下",
        category = "plunder",
        icon     = "💀",
        check    = function(state, stats)
            return (state.reputation or 0) <= -80
        end,
    },

    -- ================================================================
    -- 经济（4）
    -- ================================================================
    {
        id       = "mining_star",
        name     = "矿业新星",
        desc     = "同时拥有 3 座矿山",
        category = "economy",
        icon     = "⛏️",
        check    = function(state, stats)
            return #(state.mines or {}) >= 3
        end,
    },
    {
        id       = "financial_titan",
        name     = "金融巨鳄",
        desc     = "现金余额达到 30,000",
        category = "economy",
        icon     = "🏦",
        check    = function(state, stats)
            return (state.cash or 0) >= 30000
        end,
    },
    {
        id       = "debt_emperor",
        name     = "债务帝王",
        desc     = "同时背负 5 笔贷款且未破产",
        category = "economy",
        icon     = "📜",
        check    = function(state, stats)
            return #(state.loans or {}) >= 5 and not state.bankrupt
        end,
    },
    {
        id       = "inflation_survivor",
        name     = "通胀幸存者",
        desc     = "通胀因子达到 2.0 以上且现金 ≥ 5,000",
        category = "economy",
        icon     = "📉",
        check    = function(state, stats)
            return (state.inflation_factor or 1) >= 2.0
                and (state.cash or 0) >= 5000
        end,
    },

    -- ================================================================
    -- 证券（4）
    -- ================================================================
    {
        id       = "stock_debut",
        name     = "初入股海",
        desc     = "完成 5 笔股票交易",
        category = "stock",
        icon     = "📊",
        check    = function(state, stats)
            return (stats.trades_completed or 0) >= 5
        end,
    },
    {
        id       = "invisible_hand",
        name     = "有形大手",
        desc     = "成功操纵股市 15 次",
        category = "stock",
        icon     = "🤚",
        check    = function(state, stats)
            return (stats.manipulation_successes or 0) >= 15
        end,
    },
    {
        id       = "master_trader",
        name     = "操盘圣手",
        desc     = "完成 60 笔股票交易",
        category = "stock",
        icon     = "🎯",
        check    = function(state, stats)
            return (stats.trades_completed or 0) >= 60
        end,
    },
    {
        id       = "short_hunter",
        name     = "空头猎人",
        desc     = "做空累计盈利达到 10,000",
        category = "stock",
        icon     = "🦅",
        check    = function(state, stats)
            return (stats.short_profit_total or 0) >= 10000
        end,
    },

    -- ================================================================
    -- 综合（3）
    -- ================================================================
    {
        id       = "tech_pioneer",
        name     = "科技先驱",
        desc     = "研究完成 10 项科技",
        category = "comprehensive",
        icon     = "🔬",
        check    = function(state, stats)
            local count = 0
            if state.tech and state.tech.researched then
                for _ in pairs(state.tech.researched) do
                    count = count + 1
                end
            end
            return count >= 10
        end,
    },
    {
        id       = "family_prosperity",
        name     = "家族兴旺",
        desc     = "家族成员达到 6 人且全部在岗",
        category = "comprehensive",
        icon     = "👨‍👩‍👧‍👦",
        check    = function(state, stats)
            local members = state.family and state.family.members or {}
            if #members < 6 then return false end
            for _, m in ipairs(members) do
                if m.status ~= "active" or not m.position then
                    return false
                end
            end
            return true
        end,
    },
    {
        id       = "witness_of_ages",
        name     = "时代见证者",
        desc     = "存活超过 60 个回合（15年）",
        category = "comprehensive",
        icon     = "⏳",
        check    = function(state, stats)
            return (state.turn_count or 0) >= 60
        end,
    },
}

--- 按 ID 快查表（启动时构建）
TitlesData._byId = nil
function TitlesData.GetById(id)
    if not TitlesData._byId then
        TitlesData._byId = {}
        for _, t in ipairs(TitlesData.TITLES) do
            TitlesData._byId[t.id] = t
        end
    end
    return TitlesData._byId[id]
end

--- 按类别分组
function TitlesData.GetByCategory(catId)
    local result = {}
    for _, t in ipairs(TitlesData.TITLES) do
        if t.category == catId then
            table.insert(result, t)
        end
    end
    return result
end

return TitlesData
