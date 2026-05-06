-- ============================================================================
-- 称号数据定义  titles_data.lua
-- 18 个称号 × 5 大类，条件偏后期（每类有一个入门称号）
-- ============================================================================

local EquipmentData = require("data.equipment_data")

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
--- portraitImage 为可选 1:1 立绘资源接口，例如 "image/titles/first_blood.png"
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
        portraitImage = "image/titles/chuzhangaojie.png",
        check    = function(state, stats)
            return (state.battle_wins_total or 0) >= 1
        end,
    },
    {
        id       = "warmonger",
        name     = "战争狂人",
        desc     = "主动发起 40 次攻击，且拥有 30+ 武装",
        category = "military",
        icon     = "🔥",
        portraitImage = "image/titles/zhanzhengkuangren.png",
        check    = function(state, stats)
            local mil = state.military or {}
            return (stats.attacks_initiated or 0) >= 40
                and (mil.guards or 0) >= 30
        end,
    },
    {
        id       = "ever_victorious",
        name     = "常胜将军",
        desc     = "累计赢得 35 场战斗，且护卫士气达到 70+",
        category = "military",
        icon     = "🏆",
        portraitImage = "image/titles/changshengjiangjun.png",
        check    = function(state, stats)
            local mil = state.military or {}
            return (state.battle_wins_total or 0) >= 35
                and (mil.morale or 0) >= 70
        end,
    },
    {
        id       = "iron_wall",
        name     = "铁壁防线",
        desc     = "拥有 60+ 武装且拥有最高等级（T6）装备",
        category = "military",
        icon     = "🛡️",
        portraitImage = "image/titles/tiebifangxian.png",
        check    = function(state, stats)
            local mil = state.military or {}
            if (mil.guards or 0) < 60 then return false end
            -- 检查编队和库存中最高装备 tier
            local maxTier = 0
            for _, sq in ipairs(mil.squads or {}) do
                local cat = EquipmentData.CATALOG[sq.equip_id]
                if cat and cat.tier > maxTier then maxTier = cat.tier end
            end
            for _, inv in ipairs(mil.inventory or {}) do
                local cat = EquipmentData.CATALOG[inv.equip_id]
                if cat and cat.tier > maxTier then maxTier = cat.tier end
            end
            return maxTier >= 6
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
        portraitImage = "image/titles/jiefeinanjue.png",
        check    = function(state, stats)
            return (stats.plunder_successes or 0) >= 3
        end,
    },
    {
        id       = "balkan_wolf",
        name     = "巴尔干之狼",
        desc     = "成功掠夺 25 次，且声誉降至 -50 以下",
        category = "plunder",
        icon     = "🐺",
        portraitImage = "image/titles/baerganzhilang.png",
        check    = function(state, stats)
            return (stats.plunder_successes or 0) >= 25
                and (state.reputation or 0) <= -50
        end,
    },
    {
        id       = "infamous",
        name     = "臭名昭著",
        desc     = "声誉降至 -95 以下，且成功掠夺 20 次",
        category = "plunder",
        icon     = "💀",
        portraitImage = "image/titles/choumingzhaozhu.png",
        check    = function(state, stats)
            return (state.reputation or 0) <= -95
                and (stats.plunder_successes or 0) >= 20
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
        portraitImage = "image/titles/kuangyexinxing.png",
        check    = function(state, stats)
            return #(state.mines or {}) >= 3
        end,
    },
    {
        id       = "financial_titan",
        name     = "金融巨鳄",
        desc     = "现金余额达到 500,000，且累计收入达到 1,000,000",
        category = "economy",
        icon     = "🏦",
        portraitImage = "image/titles/jinrongjue.png",
        check    = function(state, stats)
            return (state.cash or 0) >= 500000
                and (state.total_income or 0) >= 1000000
        end,
    },
    {
        id       = "debt_emperor",
        name     = "债务帝王",
        desc     = "同时背负 3 笔贷款，总负债达到 100,000，且没有连续违约",
        category = "economy",
        icon     = "📜",
        portraitImage = "image/titles/zhaiwudiwang.png",
        check    = function(state, stats)
            local debt = 0
            for _, loan in ipairs(state.loans or {}) do
                debt = debt + (loan.principal or 0)
            end
            return #(state.loans or {}) >= 3
                and debt >= 100000
                and (state.loan_consecutive_defaults or 0) == 0
                and not state.bankrupt
        end,
    },
    {
        id       = "inflation_survivor",
        name     = "通胀幸存者",
        desc     = "通胀因子达到 3.0 以上，且现金 ≥ 50,000、黄金 ≥ 100",
        category = "economy",
        icon     = "📉",
        portraitImage = "image/titles/tongzhangxincunzhe.png",
        check    = function(state, stats)
            return (state.inflation_factor or 1) >= 3.0
                and (state.cash or 0) >= 50000
                and (state.gold or 0) >= 100
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
        portraitImage = "image/titles/churuguhai.png",
        check    = function(state, stats)
            return (stats.trades_completed or 0) >= 5
        end,
    },
    {
        id       = "invisible_hand",
        name     = "有形大手",
        desc     = "成功操纵股市 25 次",
        category = "stock",
        icon     = "🤚",
        portraitImage = "image/titles/youxingdashou.png",
        check    = function(state, stats)
            return (stats.manipulation_successes or 0) >= 25
        end,
    },
    {
        id       = "master_trader",
        name     = "操盘圣手",
        desc     = "完成 100 笔股票交易",
        category = "stock",
        icon     = "🎯",
        portraitImage = "image/titles/caopanshengshou.png",
        check    = function(state, stats)
            return (stats.trades_completed or 0) >= 100
        end,
    },
    {
        id       = "short_hunter",
        name     = "空头猎人",
        desc     = "做空累计盈利达到 50,000",
        category = "stock",
        icon     = "🦅",
        portraitImage = "image/titles/kongtoulieren.png",
        check    = function(state, stats)
            return (stats.short_profit_total or 0) >= 50000
        end,
    },

    -- ================================================================
    -- 综合（3）
    -- ================================================================
    {
        id       = "tech_pioneer",
        name     = "科技先驱",
        desc     = "研究完成 24 项科技",
        category = "comprehensive",
        icon     = "🔬",
        portraitImage = "image/titles/kejixianqu.png",
        check    = function(state, stats)
            local count = 0
            if state.tech and state.tech.researched then
                for _ in pairs(state.tech.researched) do
                    count = count + 1
                end
            end
            return count >= 24
        end,
    },
    {
        id       = "family_prosperity",
        name     = "家族兴旺",
        desc     = "家族成员达到 6 人、全部在岗、无人适应中，且总影响力达到 150",
        category = "comprehensive",
        icon     = "👨‍👩‍👧‍👦",
        portraitImage = "image/titles/jiazuxingwang.png",
        check    = function(state, stats)
            local members = state.family and state.family.members or {}
            local positioned = 0
            for _, m in ipairs(members) do
                if m.status == "active" and m.position then
                    if (m.onboarding_remaining or 0) > 0 then
                        return false
                    end
                    positioned = positioned + 1
                end
            end
            if positioned < 6 then return false end
            local totalInfluence = 0
            for _, r in ipairs(state.regions or {}) do
                totalInfluence = totalInfluence + (r.influence or 0)
            end
            return totalInfluence >= 150
        end,
    },
    {
        id       = "witness_of_ages",
        name     = "时代见证者",
        desc     = "存活超过 160 个回合（40年）且未破产",
        category = "comprehensive",
        icon     = "⏳",
        portraitImage = "image/titles/shidaijianzhengzhe.png",
        check    = function(state, stats)
            return (state.turn_count or 0) >= 160 and not state.bankrupt
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
