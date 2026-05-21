-- ============================================================================
-- 称号数据定义  titles_data.lua
-- 20 个称号 × 5 大类
-- v3: 全称号增加 rewards 字段 + 难度适配208回合节奏 + 新增"幕后执政"
-- ============================================================================

local EquipmentData = require("data.equipment_data")

local TitlesData = {}

--- 本地辅助：计算总控制度（避免循环依赖 GameState）
local function _CalcTotalControl(state)
    local total = 0
    for _, r in ipairs(state.regions or {}) do
        total = total + (r.control or 0)
    end
    return total
end

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
--- rewards: { modifiers = { {key, value, label} }, unlock_features = { ... } }
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
        rewards = {
            modifiers = {
                { key = "combat_power_bonus", value = 0.05, label = "战斗力+5%" },
            },
        },
        check    = function(state, stats)
            return (state.battle_wins_total or 0) >= 1
        end,
    },
    {
        id       = "warmonger",
        name     = "战争狂人",
        desc     = "主动发起 30 次攻击，且拥有 25+ 武装",
        category = "military",
        icon     = "🔥",
        portraitImage = "image/titles/zhanzhengkuangren.png",
        rewards = {
            modifiers = {
                { key = "expedition_power_bonus", value = 0.10, label = "远征战力+10%" },
                { key = "expedition_limit_bonus", value = 1, label = "远征上限+1次/回合" },
            },
        },
        check    = function(state, stats)
            local mil = state.military or {}
            return (stats.attacks_initiated or 0) >= 30
                and (mil.guards or 0) >= 25
        end,
    },
    {
        id       = "ever_victorious",
        name     = "常胜将军",
        desc     = "累计赢得 25 场战斗，且战意达到 60+",
        category = "military",
        icon     = "🏆",
        portraitImage = "image/titles/changshengjiangjun.png",
        rewards = {
            modifiers = {
                { key = "combat_power_bonus", value = 0.10, label = "战斗力+10%" },
                { key = "squad_exp_bonus", value = 0.50, label = "小队经验+50%" },
            },
        },
        check    = function(state, stats)
            local mil = state.military or {}
            return (state.battle_wins_total or 0) >= 25
                and (mil.morale or 0) >= 60
        end,
    },
    {
        id       = "iron_wall",
        name     = "铁壁防线",
        desc     = "拥有 45+ 武装且拥有T5级装备",
        category = "military",
        icon     = "🛡️",
        portraitImage = "image/titles/tiebifangxian.png",
        rewards = {
            modifiers = {
                { key = "defense_bonus", value = 0.15, label = "防御+15%" },
                { key = "occupation_maintenance_discount", value = 0.30, label = "占领据点维护费-30%" },
            },
        },
        check    = function(state, stats)
            local mil = state.military or {}
            if (mil.guards or 0) < 45 then return false end
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
            return maxTier >= 5
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
        rewards = {
            modifiers = {
                { key = "plunder_income_bonus", value = 0.15, label = "掠夺收入+15%" },
            },
        },
        check    = function(state, stats)
            return (stats.plunder_successes or 0) >= 3
        end,
    },
    {
        id       = "balkan_wolf",
        name     = "巴尔干之狼",
        desc     = "成功掠夺 18 次，且声誉降至 -40 以下",
        category = "plunder",
        icon     = "🐺",
        portraitImage = "image/titles/baerganzhilang.png",
        rewards = {
            modifiers = {
                { key = "plunder_income_bonus", value = 0.25, label = "突袭掠夺收入+25%" },
                { key = "raid_ap_discount", value = 1, label = "突袭AP消耗-1" },
            },
        },
        check    = function(state, stats)
            return (stats.plunder_successes or 0) >= 18
                and (state.reputation or 0) <= -40
        end,
    },
    {
        id       = "infamous",
        name     = "臭名昭著",
        desc     = "声誉降至 -80 以下，且成功掠夺 15 次",
        category = "plunder",
        icon     = "💀",
        portraitImage = "image/titles/choumingzhaozhu.png",
        rewards = {
            modifiers = {
                { key = "intimidation_defense_debuff", value = 0.10, label = "突袭时敌方防御-10%" },
                { key = "aggression_decay_bonus", value = 0.50, label = "侵略衰减速度+50%" },
            },
        },
        check    = function(state, stats)
            return (state.reputation or 0) <= -80
                and (stats.plunder_successes or 0) >= 15
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
        rewards = {
            modifiers = {
                { key = "mine_output_bonus", value = 0.10, label = "矿产产出+10%" },
                { key = "copper_price_bonus", value = 0.05, label = "铜矿售价+5%" },
            },
        },
        check    = function(state, stats)
            return #(state.mines or {}) >= 3
        end,
    },
    {
        id       = "financial_titan",
        name     = "金融巨鳄",
        desc     = "现金余额达到 300,000，且累计收入达到 600,000",
        category = "economy",
        icon     = "🏦",
        portraitImage = "image/titles/jinrongjue.png",
        rewards = {
            modifiers = {
                { key = "income_bonus", value = 0.05, label = "所有收入+5%" },
                { key = "loan_interest_discount", value = 0.01, label = "贷款利率-1%" },
            },
        },
        check    = function(state, stats)
            return (state.cash or 0) >= 300000
                and (state.total_income or 0) >= 600000
        end,
    },
    {
        id       = "debt_emperor",
        name     = "债务帝王",
        desc     = "同时背负 3 笔贷款，总负债达到 60,000，且没有连续违约",
        category = "economy",
        icon     = "📜",
        portraitImage = "image/titles/zhaiwudiwang.png",
        rewards = {
            modifiers = {
                { key = "loan_limit_bonus", value = 0.30, label = "贷款额度上限+30%" },
            },
        },
        check    = function(state, stats)
            local debt = 0
            for _, loan in ipairs(state.loans or {}) do
                debt = debt + (loan.principal or 0)
            end
            return #(state.loans or {}) >= 3
                and debt >= 60000
                and (state.loan_consecutive_defaults or 0) == 0
                and not state.bankrupt
        end,
    },
    {
        id       = "inflation_survivor",
        name     = "通胀幸存者",
        desc     = "通胀因子达到 2.5 以上，且现金 >= 30,000、黄金 >= 80",
        category = "economy",
        icon     = "📉",
        portraitImage = "image/titles/tongzhangxincunzhe.png",
        rewards = {
            modifiers = {
                { key = "inflation_resistance", value = 0.20, label = "通胀对收入负面影响-20%" },
                { key = "gold_trade_tax_free", value = 1, label = "黄金交易免税" },
            },
        },
        check    = function(state, stats)
            return (state.inflation_factor or 1) >= 2.5
                and (state.cash or 0) >= 30000
                and (state.gold or 0) >= 80
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
        rewards = {
            modifiers = {
                { key = "trade_fee_discount", value = 0.10, label = "交易手续费-10%" },
            },
        },
        check    = function(state, stats)
            return (stats.trades_completed or 0) >= 5
        end,
    },
    {
        id       = "invisible_hand",
        name     = "有形大手",
        desc     = "成功操纵股市 18 次",
        category = "stock",
        icon     = "🤚",
        portraitImage = "image/titles/youxingdashou.png",
        rewards = {
            modifiers = {
                { key = "manipulation_success_bonus", value = 0.08, label = "操纵成功率+8%" },
                { key = "manipulation_cost_discount", value = 0.15, label = "操纵成本-15%" },
            },
        },
        check    = function(state, stats)
            return (stats.manipulation_successes or 0) >= 18
        end,
    },
    {
        id       = "master_trader",
        name     = "操盘圣手",
        desc     = "完成 70 笔股票交易",
        category = "stock",
        icon     = "🎯",
        portraitImage = "image/titles/caopanshengshou.png",
        rewards = {
            modifiers = {
                { key = "trade_fee_discount", value = 0.25, label = "交易手续费-25%" },
            },
        },
        check    = function(state, stats)
            return (stats.trades_completed or 0) >= 70
        end,
    },
    {
        id       = "short_hunter",
        name     = "空头猎人",
        desc     = "做空累计盈利达到 30,000",
        category = "stock",
        icon     = "🦅",
        portraitImage = "image/titles/kongtoulieren.png",
        rewards = {
            modifiers = {
                { key = "short_leverage_bonus", value = 0.50, label = "做空杠杆上限+50%" },
                { key = "short_margin_discount", value = 0.20, label = "做空保证金-20%" },
            },
        },
        check    = function(state, stats)
            return (stats.short_profit_total or 0) >= 30000
        end,
    },

    -- ================================================================
    -- 综合（5） — 新增"情报网络"+"幕后执政"
    -- ================================================================
    {
        id       = "intel_network",
        name     = "情报网络",
        desc     = "建立区域情报网络，开启大国外交互动能力",
        category = "comprehensive",
        icon     = "🕵️",
        portraitImage = "image/victory_intelligence_network.png",
        rewards = {
            unlock_features = { "gp_actions" },
            modifiers = {
                { key = "intel_efficiency", value = 0.05, label = "情报效率+5%" },
            },
        },
        check    = function(state, stats)
            -- 条件：总控制度 >= 60（温和门槛，可在早期达成）
            return _CalcTotalControl(state) >= 60
        end,
    },

    {
        id       = "tech_pioneer",
        name     = "科技先驱",
        desc     = "研究完成 18 项科技",
        category = "comprehensive",
        icon     = "🔬",
        portraitImage = "image/titles/kejixianqu.png",
        rewards = {
            modifiers = {
                { key = "research_speed_bonus", value = 0.15, label = "研究速度+15%" },
            },
        },
        check    = function(state, stats)
            local count = 0
            if state.tech and state.tech.researched then
                for _ in pairs(state.tech.researched) do
                    count = count + 1
                end
            end
            return count >= 18
        end,
    },
    {
        id       = "family_prosperity",
        name     = "家族兴旺",
        desc     = "家族成员达到 5 人在岗、无人适应中，且总控制度达到 200",
        category = "comprehensive",
        icon     = "👨‍👩‍👧‍👦",
        portraitImage = "image/titles/jiazuxingwang.png",
        rewards = {
            modifiers = {
                { key = "family_skill_bonus", value = 0.20, label = "家族成员技能效果+20%" },
                { key = "onboarding_reduction", value = 1, label = "新成员适应期-1季" },
            },
        },
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
            if positioned < 5 then return false end
            return _CalcTotalControl(state) >= 200
        end,
    },
    {
        id       = "witness_of_ages",
        name     = "时代见证者",
        desc     = "存活超过 120 个回合（30年）且未破产",
        category = "comprehensive",
        icon     = "⏳",
        portraitImage = "image/victory_era_witness.png",
        rewards = {
            modifiers = {
                { key = "income_bonus", value = 0.08, label = "所有收入+8%" },
                { key = "event_reward_bonus", value = 0.15, label = "事件选项额外奖励+15%" },
            },
        },
        check    = function(state, stats)
            return (state.turn_count or 0) >= 120 and not state.bankrupt
        end,
    },
    {
        id       = "shadow_ruler",
        name     = "幕后执政",
        desc     = "掌控全国三大区域，成为波黑真正的幕后掌权者。解锁跨国贸易与军事远征。",
        category = "comprehensive",
        icon     = "🏛️",
        portraitImage = "image/victory_shadow_ruler.png",
        rewards = {
            unlock_features = { "expedition" },
            modifiers = {
                { key = "diplomacy_control_bonus", value = 0.10, label = "外交控制度+10%" },
            },
        },
        check    = function(state, stats)
            -- 条件1：三个区域控制度都 >= 70
            for _, r in ipairs(state.regions or {}) do
                if (r.control or 0) < 70 then return false end
            end
            -- 条件2：总控制度 >= 200（已由条件1隐含，但保留作为额外门槛）
            if _CalcTotalControl(state) < 200 then return false end
            -- 条件3：拥有至少 15 武装
            local mil = state.military or {}
            if (mil.guards or 0) < 15 then return false end
            return true
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
