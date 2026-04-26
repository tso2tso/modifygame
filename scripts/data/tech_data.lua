-- ============================================================================
-- 科技研发数据表（扩展版 — 30 科技）
-- effects 为数组格式: { { kind = "xxx", value = N }, ... }
-- 每项含 era_hint（时代提示）和 effect_desc（效果说明）供 UI 展示
-- ============================================================================

local TechData = {}

--- 获取所有可研发科技
---@return table[]
function TechData.GetAll()
    return {
        -- ================================================================
        -- A线·采矿（8个）
        -- ================================================================
        {
            id   = "a1_hand_drill",
            name = "手工钻孔",
            icon = "⛏️",
            desc = "改进手工钻孔技术，小幅提升矿山基础产出。",
            cost = 200, turns = 3,
            requires = nil,
            era_hint = "1900s",
            effect_desc = "矿山基础产出 +1 单位/季",
            effects = {
                { kind = "mine_output_base", value = 1 },
            },
        },
        {
            id   = "a2_steam_drill",
            name = "蒸汽钻机",
            icon = "⚙️",
            desc = "引入蒸汽钻机，大幅提高矿山基础产出。",
            cost = 400, turns = 4,
            requires = "a1_hand_drill",
            era_hint = "1910s",
            effect_desc = "矿山基础产出 +2 单位/季",
            effects = {
                { kind = "mine_output_base", value = 2 },
            },
        },
        {
            id   = "a3_electric_mine",
            name = "电气化矿井",
            icon = "💡",
            desc = "矿井电气化改造，提高安全性并降低事故风险。",
            cost = 600, turns = 5,
            requires = "a2_steam_drill",
            era_hint = "1920s",
            effect_desc = "矿区安全 +1，事故概率 -15%",
            effects = {
                { kind = "security_bonus", value = 1 },
                { kind = "accident_reduction", value = -0.15 },
            },
        },
        {
            id   = "a4_ventilation",
            name = "通风系统",
            icon = "🌬️",
            desc = "安装现代通风设备，改善矿井工作环境，提高工人效率。",
            cost = 500, turns = 4,
            requires = "a3_electric_mine",
            era_hint = "1930s",
            effect_desc = "工人效率 +10%",
            effects = {
                { kind = "worker_efficiency", value = 0.10 },
            },
        },
        {
            id   = "a5_conveyor",
            name = "传送带运输",
            icon = "🏗️",
            desc = "矿井内安装传送带系统，大幅提高矿石运输效率。",
            cost = 800, turns = 6,
            requires = "a4_ventilation",
            era_hint = "1940s",
            effect_desc = "矿山基础产出 +3 单位/季",
            effects = {
                { kind = "mine_output_base", value = 3 },
            },
        },
        {
            id   = "a6_hydraulic",
            name = "液压采掘",
            icon = "🔧",
            desc = "引入液压采掘设备，矿山产出获得百分比加成。",
            cost = 1200, turns = 7,
            requires = "a5_conveyor",
            era_hint = "1960s",
            effect_desc = "矿山产出 ×1.20（+20%乘法加成）",
            effects = {
                { kind = "mine_output_mult", value = 0.20 },
            },
        },
        {
            id   = "a7_auto_drill",
            name = "自动化钻探",
            icon = "🤖",
            desc = "自动化钻探系统减少人力依赖，同时提升产出和工人效率。",
            cost = 1800, turns = 8,
            requires = "a6_hydraulic",
            era_hint = "1980s",
            effect_desc = "矿山产出 ×1.25，工人效率 +15%",
            effects = {
                { kind = "mine_output_mult", value = 0.25 },
                { kind = "worker_efficiency", value = 0.15 },
            },
        },
        {
            id   = "a8_deep_mining",
            name = "深层采矿",
            icon = "⬇️",
            desc = "深层采矿技术突破，开采更深矿脉，产出质的飞跃。",
            cost = 2500, turns = 10,
            requires = "a7_auto_drill",
            era_hint = "2000s",
            effect_desc = "矿山基础产出 +5，产出 ×1.15",
            effects = {
                { kind = "mine_output_base", value = 5 },
                { kind = "mine_output_mult", value = 0.15 },
            },
        },

        -- ================================================================
        -- B线·经济（8个）
        -- ================================================================
        {
            id   = "b1_bookkeeping",
            name = "复式记账",
            icon = "📖",
            desc = "引入复式记账法，初步降低税务负担。",
            cost = 250, turns = 3,
            requires = nil,
            era_hint = "1900s",
            effect_desc = "税率 -1%",
            effects = {
                { kind = "tax_reduction", value = -0.01 },
            },
        },
        {
            id   = "b2_accounting",
            name = "现代会计学",
            icon = "📒",
            desc = "现代会计制度进一步优化税务结构。",
            cost = 400, turns = 4,
            requires = "b1_bookkeeping",
            era_hint = "1910s",
            effect_desc = "税率 -2%",
            effects = {
                { kind = "tax_reduction", value = -0.02 },
            },
        },
        {
            id   = "b3_telegraph",
            name = "电报网络",
            icon = "📡",
            desc = "架设电报网络，信息传递加速，决策效率提升。",
            cost = 600, turns = 5,
            requires = "b2_accounting",
            era_hint = "1920s",
            effect_desc = "行动点上限 +1",
            effects = {
                { kind = "ap_bonus", value = 1 },
            },
        },
        {
            id   = "b4_trade_route",
            name = "贸易路线",
            icon = "🛤️",
            desc = "开辟稳定的贸易路线，获得被动贸易收入。",
            cost = 700, turns = 5,
            requires = "b3_telegraph",
            era_hint = "1930s",
            effect_desc = "每季被动贸易收入 +60 克朗",
            effects = {
                { kind = "trade_income", value = 60 },
            },
        },
        {
            id   = "b5_finance_net",
            name = "金融网络",
            icon = "💹",
            desc = "金融网络优化资金调度，降低军事补给成本并获得被动收入。",
            cost = 1000, turns = 6,
            requires = "b4_trade_route",
            era_hint = "1950s",
            effect_desc = "军事补给成本 -20%，每季被动收入 +80 克朗",
            effects = {
                { kind = "finance_network" },
            },
        },
        {
            id   = "b6_stock_exchange",
            name = "证券交易所",
            icon = "📈",
            desc = "建立证券交易所，股票市场整体繁荣。",
            cost = 1200, turns = 7,
            requires = "b5_finance_net",
            era_hint = "1960s",
            effect_desc = "所有股票期望收益率 +2%",
            effects = {
                { kind = "stock_boost_all", value = 0.02 },
            },
        },
        {
            id   = "b7_global_trade",
            name = "全球贸易",
            icon = "🌍",
            desc = "接入全球贸易网络，大幅增加贸易收入和黄金售价。",
            cost = 1600, turns = 8,
            requires = "b6_stock_exchange",
            era_hint = "1980s",
            effect_desc = "每季贸易收入 +120，黄金售价 +5%",
            effects = {
                { kind = "trade_income", value = 120 },
                { kind = "gold_price_bonus", value = 0.05 },
            },
        },
        {
            id   = "b8_digital_finance",
            name = "数字金融",
            icon = "💻",
            desc = "数字化金融革命，行动决策极速化，税负进一步优化。",
            cost = 2200, turns = 9,
            requires = "b7_global_trade",
            era_hint = "2000s",
            effect_desc = "行动点上限 +1，税率 -3%",
            effects = {
                { kind = "ap_bonus", value = 1 },
                { kind = "tax_reduction", value = -0.03 },
            },
        },

        -- ================================================================
        -- C线·军事（7个）
        -- ================================================================
        {
            id   = "c1_rifled_arms",
            name = "线膛步枪",
            icon = "🔫",
            desc = "装备线膛步枪，护卫装备等级提升。",
            cost = 300, turns = 3,
            requires = nil,
            era_hint = "1900s",
            effect_desc = "装备等级 +1",
            effects = {
                { kind = "equipment_up", value = 1 },
            },
        },
        {
            id   = "c2_logistics",
            name = "补给管理",
            icon = "📦",
            desc = "优化后勤补给链，降低护卫补给消耗。",
            cost = 500, turns = 4,
            requires = "c1_rifled_arms",
            era_hint = "1910s",
            effect_desc = "护卫补给消耗 -1",
            effects = {
                { kind = "supply_reduction", value = -1 },
            },
        },
        {
            id   = "c3_fortification",
            name = "防御工事",
            icon = "🏰",
            desc = "修建防御工事，护卫战斗力获得加成。",
            cost = 700, turns = 5,
            requires = "c2_logistics",
            era_hint = "1930s",
            effect_desc = "护卫战斗力 +15%",
            effects = {
                { kind = "guard_power_bonus", value = 0.15 },
            },
        },
        {
            id   = "c4_motorized",
            name = "机械化部队",
            icon = "🚛",
            desc = "部队机械化，装备升级同时进一步降低补给消耗。",
            cost = 900, turns = 6,
            requires = "c3_fortification",
            era_hint = "1940s",
            effect_desc = "装备等级 +1，补给消耗 -1",
            effects = {
                { kind = "equipment_up", value = 1 },
                { kind = "supply_reduction", value = -1 },
            },
        },
        {
            id   = "c5_recon",
            name = "侦察网络",
            icon = "🔭",
            desc = "建立侦察情报网络，增强地区影响力并提振士气。",
            cost = 1100, turns = 7,
            requires = "c4_motorized",
            era_hint = "1960s",
            effect_desc = "每季影响力 +1，士气 +3",
            effects = {
                { kind = "influence_gain", value = 1 },
                { kind = "morale_bonus", value = 3 },
            },
        },
        {
            id   = "c6_modern_arms",
            name = "现代武装",
            icon = "🎯",
            desc = "换装现代化武器，护卫战斗力与装备大幅提升。",
            cost = 1500, turns = 8,
            requires = "c5_recon",
            era_hint = "1980s",
            effect_desc = "护卫战斗力 +25%，装备等级 +1",
            effects = {
                { kind = "guard_power_bonus", value = 0.25 },
                { kind = "equipment_up", value = 1 },
            },
        },
        {
            id   = "c7_elite_force",
            name = "精锐部队",
            icon = "⚔️",
            desc = "训练精锐特种部队，战斗力卓越，招募成本降低。",
            cost = 2000, turns = 9,
            requires = "c6_modern_arms",
            era_hint = "2000s",
            effect_desc = "护卫战斗力 +20%，招募成本 -15%",
            effects = {
                { kind = "guard_power_bonus", value = 0.20 },
                { kind = "hire_cost_reduction", value = -0.15 },
            },
        },

        -- ================================================================
        -- D线·文化（7个）
        -- ================================================================
        {
            id   = "d1_propaganda",
            name = "印刷宣传",
            icon = "🗞️",
            desc = "宣传机构提升地区影响力。",
            cost = 300, turns = 3,
            requires = nil,
            era_hint = "1900s",
            effect_desc = "每季影响力 +2",
            effects = {
                { kind = "influence_gain", value = 2 },
            },
        },
        {
            id   = "d2_education",
            name = "基础教育",
            icon = "📚",
            desc = "普及基础教育，提高工人素质和民众士气。",
            cost = 450, turns = 4,
            requires = "d1_propaganda",
            era_hint = "1910s",
            effect_desc = "工人效率 +8%，士气 +3",
            effects = {
                { kind = "worker_efficiency", value = 0.08 },
                { kind = "morale_bonus", value = 3 },
            },
        },
        {
            id   = "d3_newspaper",
            name = "报业帝国",
            icon = "📰",
            desc = "建立报业帝国，舆论控制增强影响力并提振士气。",
            cost = 600, turns = 5,
            requires = "d2_education",
            era_hint = "1930s",
            effect_desc = "每季影响力 +2，士气 +2",
            effects = {
                { kind = "influence_gain", value = 2 },
                { kind = "morale_bonus", value = 2 },
            },
        },
        {
            id   = "d4_radio",
            name = "广播电台",
            icon = "📻",
            desc = "开设广播电台，覆盖更广的民众，大幅提升影响力。",
            cost = 800, turns = 6,
            requires = "d3_newspaper",
            era_hint = "1940s",
            effect_desc = "每季影响力 +3",
            effects = {
                { kind = "influence_gain", value = 3 },
            },
        },
        {
            id   = "d5_university",
            name = "大学",
            icon = "🎓",
            desc = "创建大学培养人才，加速科研并增加决策能力。",
            cost = 1000, turns = 6,
            requires = "d4_radio",
            era_hint = "1960s",
            effect_desc = "研发速度 +15%，行动点上限 +1",
            effects = {
                { kind = "research_speed", value = 0.15 },
                { kind = "ap_bonus", value = 1 },
            },
        },
        {
            id   = "d6_television",
            name = "电视网络",
            icon = "📺",
            desc = "电视网络全面覆盖，文化软实力剧增。",
            cost = 1400, turns = 7,
            requires = "d5_university",
            era_hint = "1980s",
            effect_desc = "每季影响力 +4，士气 +5",
            effects = {
                { kind = "influence_gain", value = 4 },
                { kind = "morale_bonus", value = 5 },
            },
        },
        {
            id   = "d7_internet",
            name = "互联网",
            icon = "🌐",
            desc = "互联网时代来临，信息爆炸带来全面提升。",
            cost = 2000, turns = 9,
            requires = "d6_television",
            era_hint = "2000s",
            effect_desc = "行动点 +1，研发速度 +20%，每季影响力 +3",
            effects = {
                { kind = "ap_bonus", value = 1 },
                { kind = "research_speed", value = 0.20 },
                { kind = "influence_gain", value = 3 },
            },
        },
    }
end

--- 根据 id 查找科技
---@param id string
---@return table|nil
function TechData.GetById(id)
    for _, t in ipairs(TechData.GetAll()) do
        if t.id == id then return t end
    end
    return nil
end

return TechData
