-- ============================================================================
-- 科技研发数据表（1904-1955 扩展版 — 含分叉互斥）
-- effects 为数组格式: { { kind = "xxx", value = N }, ... }
-- 每项含 era_hint（时代提示）和 effect_desc（效果说明）供 UI 展示
-- excludes: string|nil — 与之互斥的科技id，研发此项后另一项不可再研发
-- ============================================================================

local TechData = {}

--- 获取所有可研发科技
---@return table[]
function TechData.GetAll()
    return {
        -- ================================================================
        -- A线·采矿（12个，含2处分叉 + 1中期分支 + 1终极科技）
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
            era_hint = "1900s",
            effect_desc = "矿山基础产出 +2 单位/季",
            effects = {
                { kind = "mine_output_base", value = 2 },
            },
        },
        {
            id   = "a3_electric_mine",
            name = "电气化矿井",
            icon = "💡",
            desc = "矿井电气化改造，提高安全性并降低事故风险，同时让本地煤矿开发具备可行性。",
            cost = 600, turns = 5,
            requires = "a2_steam_drill",
            era_hint = "1910s",
            effect_desc = "矿区安全 +1，事故概率 -15%，矿山槽位 +2，解锁本地煤矿",
            effects = {
                { kind = "security_bonus", value = 1 },
                { kind = "accident_reduction", value = -0.15 },
                { kind = "mine_slots", value = 2 },
                { kind = "unlock_local_coal_mine" },
            },
        },
        -- ── 分叉1: 通风 vs 爆破 ──
        {
            id   = "a4a_ventilation",
            name = "现代通风系统",
            icon = "🌬️",
            desc = "安装现代通风设备，改善矿井工作环境，提高工人效率。（与爆破开采互斥）",
            cost = 500, turns = 4,
            requires = "a3_electric_mine",
            excludes = "a4b_blasting",
            era_hint = "1910s",
            effect_desc = "工人效率 +12%，事故概率 -10%，探矿成功率 +5%",
            effects = {
                { kind = "worker_efficiency", value = 0.12 },
                { kind = "accident_reduction", value = -0.10 },
                { kind = "prospect_success", value = 0.05 },
            },
        },
        {
            id   = "a4b_blasting",
            name = "爆破开采",
            icon = "💥",
            desc = "使用炸药开采矿脉，产量暴涨但安全隐患增加。（与现代通风系统互斥）",
            cost = 450, turns = 3,
            requires = "a3_electric_mine",
            excludes = "a4a_ventilation",
            era_hint = "1910s",
            effect_desc = "矿山基础产出 +3，事故概率 +5%",
            effects = {
                { kind = "mine_output_base", value = 3 },
                { kind = "accident_reduction", value = 0.05 },
            },
        },
        {
            id   = "a5_conveyor",
            name = "传送带运输",
            icon = "🏗️",
            desc = "矿井内安装传送带系统，大幅提高矿石运输效率。",
            cost = 700, turns = 5,
            requires = "a4a_ventilation|a4b_blasting",
            era_hint = "1920s",
            effect_desc = "矿山基础产出 +2，工人效率 +5%，矿山槽位 +2",
            effects = {
                { kind = "mine_output_base", value = 2 },
                { kind = "worker_efficiency", value = 0.05 },
                { kind = "mine_slots", value = 2 },
            },
        },
        -- ── 中期分支: 地质勘探学 ──
        {
            id   = "a5b_geological_survey",
            name = "地质勘探学",
            icon = "🗺️",
            desc = "引入系统性地质勘探方法，提高矿脉发现概率并扩展矿山容量。",
            cost = 850, turns = 6,
            requires = "a5_conveyor",
            era_hint = "1920s",
            effect_desc = "探矿成功率 +12%，矿山槽位 +1",
            effects = {
                { kind = "prospect_success", value = 0.12 },
                { kind = "mine_slots", value = 1 },
            },
        },
        -- ── 分叉2: 液压 vs 深层 ──
        {
            id   = "a6a_hydraulic",
            name = "液压采掘",
            icon = "🔧",
            desc = "引入液压采掘设备，矿山产出获得百分比加成。（与深层矿脉互斥）",
            cost = 1200, turns = 7,
            requires = "a5_conveyor",
            excludes = "a6b_deep_shaft",
            era_hint = "1930s",
            effect_desc = "矿山产出 ×1.20（+20%乘法加成）",
            effects = {
                { kind = "mine_output_mult", value = 0.20 },
            },
        },
        {
            id   = "a6b_deep_shaft",
            name = "深层矿脉",
            icon = "⬇️",
            desc = "开凿深层矿井，开采更深矿脉，基础产出大幅增加。（与液压采掘互斥）",
            cost = 1300, turns = 8,
            requires = "a5_conveyor",
            excludes = "a6a_hydraulic",
            era_hint = "1930s",
            effect_desc = "矿山基础产出 +4 单位/季，探矿成功率 +5%",
            effects = {
                { kind = "mine_output_base", value = 4 },
                { kind = "prospect_success", value = 0.05 },
            },
        },
        {
            id   = "a7_wartime_extraction",
            name = "战时强采",
            icon = "🏭",
            desc = "战时体制下不惜代价提高矿产产量，工人效率和安全性同步提升。",
            cost = 1800, turns = 8,
            requires = "a6a_hydraulic|a6b_deep_shaft",
            era_hint = "1940s",
            effect_desc = "矿山产出 ×1.15，工人效率 +10%，事故 -10%",
            effects = {
                { kind = "mine_output_mult", value = 0.15 },
                { kind = "worker_efficiency", value = 0.10 },
                { kind = "accident_reduction", value = -0.10 },
            },
        },

        -- ================================================================
        -- B线·经济（13个，含2处分叉 + 1中期分支 + 1终极科技）
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
            era_hint = "1900s",
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
            era_hint = "1910s",
            effect_desc = "行动点上限 +1",
            effects = {
                { kind = "ap_bonus", value = 1 },
            },
        },
        -- ── 分叉1: 贸易路线 vs 走私网络 ──
        {
            id   = "b4a_trade_route",
            name = "巴尔干贸易路线",
            icon = "🛤️",
            desc = "开辟稳定的巴尔干贸易路线，获得被动贸易收入。（与走私网络互斥）",
            cost = 650, turns = 5,
            requires = "b3_telegraph",
            excludes = "b4b_smuggling",
            era_hint = "1910s",
            effect_desc = "解锁跨国贸易，每季被动贸易收入 +50 克朗，税率 -1%",
            effects = {
                { kind = "unlock_foreign_trade" },
                { kind = "trade_income", value = 50 },
                { kind = "tax_reduction", value = -0.01 },
            },
        },
        {
            id   = "b4b_smuggling",
            name = "走私网络",
            icon = "🕶️",
            desc = "建立隐秘走私通道，利润更高但不稳定且控制度下降。（与巴尔干贸易路线互斥）",
            cost = 500, turns = 4,
            requires = "b3_telegraph",
            excludes = "b4a_trade_route",
            era_hint = "1910s",
            effect_desc = "解锁跨国贸易，每季贸易收入 +80 克朗，每季控制度 -1",
            effects = {
                { kind = "unlock_foreign_trade" },
                { kind = "trade_income", value = 80 },
                { kind = "passive_control_gain", value = -1 },
            },
        },
        {
            id   = "b5_finance_net",
            name = "金融网络",
            icon = "💹",
            desc = "金融网络优化资金调度，获得稳定被动收入，解锁商业远征。",
            cost = 900, turns = 6,
            requires = "b4a_trade_route|b4b_smuggling",
            era_hint = "1920s",
            effect_desc = "解锁商业远征，每季被动收入 +80 克朗",
            effects = {
                { kind = "finance_network" },
                { kind = "unlock_venture" },
            },
        },
        -- ── 中期分支: 商品期货 ──
        {
            id   = "b5b_commodity_futures",
            name = "商品期货",
            icon = "📊",
            desc = "建立商品期货交易机制，对冲矿产品价格波动风险，提升投资回报。",
            cost = 800, turns = 5,
            requires = "b5_finance_net",
            era_hint = "1920s",
            effect_desc = "股票收益率 +5%，黄金售价 +3%",
            effects = {
                { kind = "stock_boost_all", value = 0.05 },
                { kind = "gold_price_bonus", value = 0.03 },
            },
        },
        {
            id   = "b6_stock_exchange",
            name = "证券交易所",
            icon = "📈",
            desc = "参与萨拉热窝证券交易，股票市场整体繁荣。",
            cost = 1100, turns = 6,
            requires = "b5_finance_net",
            era_hint = "1920s",
            effect_desc = "所有股票收益率 +10%",
            effects = {
                { kind = "stock_boost_all", value = 0.10 },
            },
        },
        -- ── 做空科技（独立分支，与 b7a/b7b 并行）──
        {
            id   = "b7_short_selling",
            name = "卖空交易",
            icon = "📉",
            desc = "引入卖空机制，允许在股票下跌时做空获利。需要证券交易所基础设施。",
            cost = 1100, turns = 6,
            requires = "b6_stock_exchange",
            era_hint = "1920s",
            effect_desc = "解锁股票做空操作",
            effects = {
                { kind = "unlock_short_selling" },
            },
        },
        -- ── 分叉2: 国际贸易 vs 战时经济 ──
        {
            id   = "b7a_intl_trade",
            name = "国际贸易协定",
            icon = "🌍",
            desc = "签署国际贸易协定，大幅增加贸易收入和黄金售价。（与战时统制经济互斥）",
            cost = 1500, turns = 8,
            requires = "b6_stock_exchange",
            excludes = "b7b_war_economy",
            era_hint = "1930s",
            effect_desc = "每季贸易收入 +100，黄金售价 +5%",
            effects = {
                { kind = "trade_income", value = 100 },
                { kind = "gold_price_bonus", value = 0.05 },
            },
        },
        {
            id   = "b7b_war_economy",
            name = "战时统制经济",
            icon = "🏛️",
            desc = "实施战时统制经济，税率大幅降低。（与国际贸易协定互斥）",
            cost = 1400, turns = 7,
            requires = "b6_stock_exchange",
            excludes = "b7a_intl_trade",
            era_hint = "1930s",
            effect_desc = "税率 -5%，每季贸易收入 +60",
            effects = {
                { kind = "tax_reduction", value = -0.05 },
                { kind = "trade_income", value = 60 },
            },
        },
        {
            id   = "b8_central_banking",
            name = "中央银行",
            icon = "🏦",
            desc = "建立中央银行体系，全面提升金融能力。",
            cost = 2000, turns = 9,
            requires = "b7a_intl_trade|b7b_war_economy",
            era_hint = "1940s",
            effect_desc = "行动点 +1，税率 -2%，股票收益率 +1%",
            effects = {
                { kind = "ap_bonus", value = 1 },
                { kind = "tax_reduction", value = -0.02 },
                { kind = "stock_boost_all", value = 0.01 },
            },
        },

        -- ================================================================
        -- C线·军事（12个，含2处分叉 + 1中期分支 + 1终极科技）
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
            name = "后勤管理",
            icon = "📦",
            desc = "优化后勤管理体系，改善军营和矿区的生活条件，提振士气。",
            cost = 500, turns = 4,
            requires = "c1_rifled_arms",
            era_hint = "1900s",
            effect_desc = "士气/战意 +3",
            effects = {
                { kind = "morale_bonus", value = 3 },
            },
        },
        {
            id   = "c3_machine_gun",
            name = "马克沁重机枪",
            icon = "🔫",
            desc = "装备马克沁重机枪，护卫火力大幅提升。",
            cost = 700, turns = 5,
            requires = "c2_logistics",
            era_hint = "1910s",
            effect_desc = "护卫战斗力 +15%，装备等级 +1",
            effects = {
                { kind = "guard_power_bonus", value = 0.15 },
                { kind = "equipment_up", value = 1 },
            },
        },
        -- ── 分叉1: 防御工事 vs 突击战术 ──
        {
            id   = "c4a_fortification",
            name = "堑壕防御",
            icon = "🏰",
            desc = "修建堑壕防御工事，大幅增强护卫防御力。（与突击战术互斥）",
            cost = 800, turns = 5,
            requires = "c3_machine_gun",
            excludes = "c4b_assault",
            era_hint = "1910s",
            effect_desc = "护卫战斗力 +20%，矿区安全 +1",
            effects = {
                { kind = "guard_power_bonus", value = 0.20 },
                { kind = "security_bonus", value = 1 },
            },
        },
        {
            id   = "c4b_assault",
            name = "突击战术",
            icon = "⚡",
            desc = "训练突击小队，善于进攻但防守薄弱。（与堑壕防御互斥）",
            cost = 750, turns = 4,
            requires = "c3_machine_gun",
            excludes = "c4a_fortification",
            era_hint = "1910s",
            effect_desc = "护卫战斗力 +25%，每季控制度 +1",
            effects = {
                { kind = "guard_power_bonus", value = 0.25 },
                { kind = "passive_control_gain", value = 1 },
            },
        },
        {
            id   = "c5_motorized",
            name = "机械化部队",
            icon = "🚛",
            desc = "部队机械化，装备全面升级，机动力大幅提升。",
            cost = 1000, turns = 6,
            requires = "c4a_fortification|c4b_assault",
            era_hint = "1920s",
            effect_desc = "装备等级 +1",
            effects = {
                { kind = "equipment_up", value = 1 },
            },
        },
        -- ── 中期分支: 战地医学 ──
        {
            id   = "c5b_field_medicine",
            name = "战地医学",
            icon = "🏥",
            desc = "建立战地医疗体系，降低伤亡损失并提升军队士气。",
            cost = 900, turns = 6,
            requires = "c5_motorized",
            era_hint = "1920s",
            effect_desc = "士气/战意 +5，事故概率 -8%",
            effects = {
                { kind = "morale_bonus", value = 5 },
                { kind = "accident_reduction", value = -0.08 },
            },
        },
        -- ── 分叉2: 情报网络 vs 重武装 ──
        {
            id   = "c6a_intelligence",
            name = "情报网络",
            icon = "🔭",
            desc = "建立情报网络，增强地区控制度并提振士气。（与重武装互斥）",
            cost = 1500, turns = 7,
            requires = "c5_motorized",
            excludes = "c6b_heavy_arms",
            era_hint = "1930s",
            effect_desc = "每季控制度 +2，士气/战意 +5，研发速度 +5%",
            effects = {
                { kind = "passive_control_gain", value = 2 },
                { kind = "morale_bonus", value = 5 },
                { kind = "research_speed", value = 0.05 },
            },
        },
        {
            id   = "c6b_heavy_arms",
            name = "重型武装",
            icon = "🎯",
            desc = "装备重炮和装甲车辆，护卫战斗力大幅提升。（与情报网络互斥）",
            cost = 1600, turns = 8,
            requires = "c5_motorized",
            excludes = "c6a_intelligence",
            era_hint = "1930s",
            effect_desc = "护卫战斗力 +30%",
            effects = {
                { kind = "guard_power_bonus", value = 0.30 },
            },
        },
        {
            id   = "c7_elite_force",
            name = "精锐部队",
            icon = "⚔️",
            desc = "训练精锐特种部队，战斗力卓越，招募成本降低。",
            cost = 2000, turns = 8,
            requires = "c6a_intelligence|c6b_heavy_arms",
            era_hint = "1940s",
            effect_desc = "护卫战斗力 +20%，招募成本 -15%，士气/战意 +3",
            effects = {
                { kind = "guard_power_bonus", value = 0.20 },
                { kind = "hire_cost_reduction", value = -0.15 },
                { kind = "morale_bonus", value = 3 },
            },
        },

        -- ================================================================
        -- D线·文化（12个，含2处分叉 + 1中期分支 + 1终极科技）
        -- ================================================================
        {
            id   = "d1_propaganda",
            name = "印刷宣传",
            icon = "🗞️",
            desc = "宣传机构提升地区控制度。",
            cost = 300, turns = 3,
            requires = nil,
            era_hint = "1900s",
            effect_desc = "每季控制度 +2",
            effects = {
                { kind = "passive_control_gain", value = 2 },
            },
        },
        {
            id   = "d2_education",
            name = "基础教育",
            icon = "📚",
            desc = "普及基础教育，提高工人素质和民众士气。",
            cost = 450, turns = 4,
            requires = "d1_propaganda",
            era_hint = "1900s",
            effect_desc = "工人效率 +8%，士气/战意 +3",
            effects = {
                { kind = "worker_efficiency", value = 0.08 },
                { kind = "morale_bonus", value = 3 },
            },
        },
        {
            id   = "d3_newspaper",
            name = "报业帝国",
            icon = "📰",
            desc = "建立报业帝国，舆论控制增强控制度并提振士气。",
            cost = 600, turns = 5,
            requires = "d2_education",
            era_hint = "1910s",
            effect_desc = "每季控制度 +2，士气/战意 +2",
            effects = {
                { kind = "passive_control_gain", value = 2 },
                { kind = "morale_bonus", value = 2 },
            },
        },
        -- ── 分叉1: 民族主义 vs 国际主义 ──
        {
            id   = "d4a_nationalism",
            name = "民族主义运动",
            icon = "🏴",
            desc = "煽动民族主义情绪，短期获得巨大士气和控制度。（与国际主义互斥）",
            cost = 550, turns = 4,
            requires = "d3_newspaper",
            excludes = "d4b_internationalism",
            era_hint = "1910s",
            effect_desc = "每季控制度 +3，士气/战意 +5，护卫战力 +10%",
            effects = {
                { kind = "passive_control_gain", value = 3 },
                { kind = "morale_bonus", value = 5 },
                { kind = "guard_power_bonus", value = 0.10 },
            },
        },
        {
            id   = "d4b_internationalism",
            name = "国际主义交流",
            icon = "🤝",
            desc = "促进国际文化交流，研发效率和贸易获得持续收益。（与民族主义运动互斥）",
            cost = 600, turns = 5,
            requires = "d3_newspaper",
            excludes = "d4a_nationalism",
            era_hint = "1910s",
            effect_desc = "研发速度 +8%，每季贸易收入 +40，工人效率 +5%",
            effects = {
                { kind = "research_speed", value = 0.08 },
                { kind = "trade_income", value = 40 },
                { kind = "worker_efficiency", value = 0.05 },
            },
        },
        {
            id   = "d5_radio",
            name = "广播电台",
            icon = "📻",
            desc = "开设广播电台，覆盖更广的民众，大幅提升控制度。",
            cost = 800, turns = 5,
            requires = "d4a_nationalism|d4b_internationalism",
            era_hint = "1920s",
            effect_desc = "每季控制度 +3，行动点 +1",
            effects = {
                { kind = "passive_control_gain", value = 3 },
                { kind = "ap_bonus", value = 1 },
            },
        },
        -- ── 中期分支: 电影工业 ──
        {
            id   = "d5b_cinema",
            name = "电影工业",
            icon = "🎬",
            desc = "发展电影产业，通过大荧幕影响民心，巩固地区控制并提振士气。",
            cost = 900, turns = 6,
            requires = "d5_radio",
            era_hint = "1920s",
            effect_desc = "每季控制度 +2，士气/战意 +4",
            effects = {
                { kind = "passive_control_gain", value = 2 },
                { kind = "morale_bonus", value = 4 },
            },
        },
        -- ── 分叉2: 大学 vs 宣传机器 ──
        {
            id   = "d6a_university",
            name = "萨拉热窝大学",
            icon = "🎓",
            desc = "创建大学培养人才，加速科研和提升工人效率。（与宣传机器互斥）",
            cost = 1400, turns = 7,
            requires = "d5_radio",
            excludes = "d6b_propaganda_machine",
            era_hint = "1930s",
            effect_desc = "研发速度 +10%，工人效率 +10%",
            effects = {
                { kind = "research_speed", value = 0.10 },
                { kind = "worker_efficiency", value = 0.10 },
            },
        },
        {
            id   = "d6b_propaganda_machine",
            name = "宣传机器",
            icon = "📢",
            desc = "大规模宣传攻势，快速获得控制度和士气。（与萨拉热窝大学互斥）",
            cost = 1200, turns = 6,
            requires = "d5_radio",
            excludes = "d6a_university",
            era_hint = "1930s",
            effect_desc = "每季控制度 +4，士气/战意 +5",
            effects = {
                { kind = "passive_control_gain", value = 4 },
                { kind = "morale_bonus", value = 5 },
            },
        },
        {
            id   = "d7_wartime_media",
            name = "战时媒体管制",
            icon = "📻",
            desc = "战时全面媒体管制，巩固控制度优势并加速研发。",
            cost = 1800, turns = 8,
            requires = "d6a_university|d6b_propaganda_machine",
            era_hint = "1940s",
            effect_desc = "每季控制度 +3，研发速度 +6%，士气/战意 +3",
            effects = {
                { kind = "passive_control_gain", value = 3 },
                { kind = "research_speed", value = 0.06 },
                { kind = "morale_bonus", value = 3 },
            },
        },

        -- ================================================================
        -- A线·采矿 扩展（3个，掠夺子分支 + 终极科技）
        -- 需要跨线前置，使用 AND(逗号) 语法
        -- ================================================================
        {
            id   = "a8_raid_tactics",
            name = "掠夺性开采",
            icon = "⚒️",
            desc = "开发激进的掠夺式开采战术，大幅提高劫掠商队和勒索时的收益。需要战时强采和军事补给管理的双重基础。",
            cost = 1800, turns = 7,
            requires = "a7_wartime_extraction,c2_logistics",
            era_hint = "1940s",
            effect_desc = "掠夺收益 +20%，矿山产出 ×1.08",
            effects = {
                { kind = "plunder_loot_mult", value = 0.20 },
                { kind = "mine_output_mult", value = 0.08 },
            },
        },
        {
            id   = "a9_vein_exploitation",
            name = "矿脉强占技术",
            icon = "💎",
            desc = "研发快速矿脉评估和强占技术，缩短掠夺冷却时间，提高矿山基础产出。",
            cost = 2200, turns = 8,
            requires = "a8_raid_tactics",
            era_hint = "1940s",
            effect_desc = "掠夺冷却 -1 季，矿山产出 +3",
            effects = {
                { kind = "plunder_cooldown_reduction", value = 1 },
                { kind = "mine_output_base", value = 3 },
            },
        },
        {
            id   = "a10_guerrilla_logistics",
            name = "游击后勤网",
            icon = "🗺️",
            desc = "建立分散式游击后勤网络，全面提升掠夺能力和矿产运输效率。",
            cost = 2600, turns = 10,
            requires = "a9_vein_exploitation,c5_motorized",
            era_hint = "1940s",
            effect_desc = "掠夺收益 +15%，掠夺冷却 -1 季，工人效率 +8%",
            effects = {
                { kind = "plunder_loot_mult", value = 0.15 },
                { kind = "plunder_cooldown_reduction", value = 1 },
                { kind = "worker_efficiency", value = 0.08 },
            },
        },
        -- ── 终极科技 ──
        {
            id   = "a11_strategic_reserves",
            name = "战略矿产储备",
            icon = "🛢️",
            desc = "建立国家级战略矿产储备体系，确保关键矿产的长期供应安全。需要游击后勤和精锐部队的双重支撑。",
            cost = 2800, turns = 10,
            requires = "a10_guerrilla_logistics,c7_elite_force",
            era_hint = "1950s",
            effect_desc = "矿山产出 ×1.20，工人效率 +8%",
            effects = {
                { kind = "mine_output_mult", value = 0.20 },
                { kind = "worker_efficiency", value = 0.08 },
            },
        },

        -- ================================================================
        -- B线·经济 扩展（3个 + 终极科技）
        -- ================================================================
        {
            id   = "b9_insurance",
            name = "商业保险体系",
            icon = "🛡️",
            desc = "建立商业保险制度，降低运输和事故风险，稳定经营收入。",
            cost = 1900, turns = 8,
            requires = "b8_central_banking",
            era_hint = "1940s",
            effect_desc = "事故概率 -12%，每季被动收入 +60 克朗",
            effects = {
                { kind = "accident_reduction", value = -0.12 },
                { kind = "trade_income", value = 60 },
            },
        },
        {
            id   = "b10_offshore_account",
            name = "海外账户",
            icon = "🌐",
            desc = "在中立国设立隐秘资产账户，降低税负并提升声誉恢复速度。",
            cost = 2200, turns = 8,
            requires = "b8_central_banking",
            era_hint = "1940s",
            effect_desc = "税率 -3%，声誉恢复 +1/季",
            effects = {
                { kind = "tax_reduction", value = -0.03 },
                { kind = "rep_recovery_bonus", value = 1 },
            },
        },
        {
            id   = "b11_trade_monopoly",
            name = "贸易垄断",
            icon = "👑",
            desc = "整合区域贸易网络形成垄断优势，大幅增加贸易收入和掠夺收益。需要金融网络和情报网络/重武装的双重支撑。",
            cost = 3000, turns = 10,
            requires = "b8_central_banking,c6a_intelligence|c6b_heavy_arms",
            era_hint = "1940s",
            effect_desc = "每季贸易收入 +120，掠夺收益 +10%",
            effects = {
                { kind = "trade_income", value = 120 },
                { kind = "plunder_loot_mult", value = 0.10 },
            },
        },
        -- ── 终极科技 ──
        {
            id   = "b12_economic_empire",
            name = "经济帝国",
            icon = "💰",
            desc = "构建横跨巴尔干的经济帝国，贸易网络和文化霸权为其提供基石。",
            cost = 3000, turns = 10,
            requires = "b11_trade_monopoly,d8_cultural_hegemony",
            era_hint = "1950s",
            effect_desc = "每季贸易收入 +150，税率 -3%",
            effects = {
                { kind = "trade_income", value = 150 },
                { kind = "tax_reduction", value = -0.03 },
            },
        },

        -- ================================================================
        -- C线·军事 扩展（6个，含掠夺科技 + 声誉管理分支 + 终极科技）
        -- ================================================================
        {
            id   = "c8_commando",
            name = "突击队训练",
            icon = "🎖️",
            desc = "培训精锐突击队用于掠夺行动，提高掠夺收益和战斗力。",
            cost = 2000, turns = 8,
            requires = "c7_elite_force",
            era_hint = "1940s",
            effect_desc = "掠夺收益 +15%，护卫战斗力 +10%",
            effects = {
                { kind = "plunder_loot_mult", value = 0.15 },
                { kind = "guard_power_bonus", value = 0.10 },
            },
        },
        {
            id   = "c9_armored_train",
            name = "装甲列车",
            icon = "🚂",
            desc = "改装装甲列车用于矿石运输和武装押运，大幅提高护卫战力。",
            cost = 2400, turns = 9,
            requires = "c8_commando",
            era_hint = "1940s",
            effect_desc = "护卫战斗力 +15%",
            effects = {
                { kind = "guard_power_bonus", value = 0.15 },
            },
        },
        {
            id   = "c10_total_war",
            name = "全面战争",
            icon = "💀",
            desc = "进入全面战争状态，家族军事力量达到巅峰。需要军事和文化双线支撑。",
            cost = 3200, turns = 11,
            requires = "c9_armored_train,d7_wartime_media",
            era_hint = "1940s",
            effect_desc = "护卫战斗力 +25%，士气/战意 +5，每季控制度 +2",
            effects = {
                { kind = "guard_power_bonus", value = 0.25 },
                { kind = "morale_bonus", value = 5 },
                { kind = "passive_control_gain", value = 2 },
            },
        },
        -- ── 掠夺声誉管理分支（从 c8_commando 分出）──
        {
            id   = "c8a_intimidation",
            name = "威慑战术",
            icon = "😈",
            desc = "通过武力威慑减少掠夺行动的阻力，缩短掠夺冷却时间。（与外交掩护互斥）",
            cost = 1600, turns = 7,
            requires = "c8_commando",
            excludes = "c8b_diplomatic_cover",
            era_hint = "1940s",
            effect_desc = "掠夺冷却 -1 季，护卫战斗力 +10%",
            effects = {
                { kind = "plunder_cooldown_reduction", value = 1 },
                { kind = "guard_power_bonus", value = 0.10 },
            },
        },
        {
            id   = "c8b_diplomatic_cover",
            name = "外交掩护",
            icon = "🕊️",
            desc = "通过外交手段掩饰掠夺行径，加速声誉恢复。（与威慑战术互斥）",
            cost = 1800, turns = 7,
            requires = "c8_commando",
            excludes = "c8a_intimidation",
            era_hint = "1940s",
            effect_desc = "声誉恢复 +2/季，每季控制度 +2",
            effects = {
                { kind = "rep_recovery_bonus", value = 2 },
                { kind = "passive_control_gain", value = 2 },
            },
        },
        {
            id   = "c9_rep_management",
            name = "声誉管理",
            icon = "📋",
            desc = "建立系统化的声誉管理机制，综合提升掠夺效率与声誉恢复。",
            cost = 2200, turns = 8,
            requires = "c8a_intimidation|c8b_diplomatic_cover",
            era_hint = "1940s",
            effect_desc = "声誉恢复 +2/季，掠夺收益 +10%，掠夺冷却 -1 季",
            effects = {
                { kind = "rep_recovery_bonus", value = 2 },
                { kind = "plunder_loot_mult", value = 0.10 },
                { kind = "plunder_cooldown_reduction", value = 1 },
            },
        },
        -- ── 终极科技 ──
        {
            id   = "c11_total_mobilization",
            name = "全面动员",
            icon = "🚩",
            desc = "实施全面国民动员体制，将国家机器全面转入战争轨道。需要全面战争和战时强采的基础。",
            cost = 3000, turns = 10,
            requires = "c10_total_war,a7_wartime_extraction",
            era_hint = "1950s",
            effect_desc = "护卫战斗力 +25%，士气/战意 +5，招募成本 -20%",
            effects = {
                { kind = "guard_power_bonus", value = 0.25 },
                { kind = "morale_bonus", value = 5 },
                { kind = "hire_cost_reduction", value = -0.20 },
            },
        },

        -- ================================================================
        -- D线·文化 扩展（3个 + 终极科技）
        -- ================================================================
        {
            id   = "d8_cultural_hegemony",
            name = "文化霸权",
            icon = "🏆",
            desc = "建立区域文化霸权，控制度和士气获得持久优势。",
            cost = 2200, turns = 9,
            requires = "d7_wartime_media",
            era_hint = "1940s",
            effect_desc = "每季控制度 +4，士气/战意 +4，工人效率 +5%",
            effects = {
                { kind = "passive_control_gain", value = 4 },
                { kind = "morale_bonus", value = 4 },
                { kind = "worker_efficiency", value = 0.05 },
            },
        },
        {
            id   = "d9_secret_society",
            name = "秘密结社",
            icon = "🔮",
            desc = "建立跨国秘密结社网络，获得政治控制度和研发加成，同时有助于掩护掠夺行为。",
            cost = 2600, turns = 10,
            requires = "d8_cultural_hegemony,b8_central_banking",
            era_hint = "1940s",
            effect_desc = "每季控制度 +3，研发速度 +6%，声誉恢复 +1/季",
            effects = {
                { kind = "passive_control_gain", value = 3 },
                { kind = "research_speed", value = 0.06 },
                { kind = "rep_recovery_bonus", value = 1 },
            },
        },
        {
            id   = "d10_national_identity",
            name = "民族认同",
            icon = "🏛️",
            desc = "锻造统一的民族认同感，全面巩固家族在地区的统治地位。",
            cost = 3000, turns = 11,
            requires = "d9_secret_society",
            era_hint = "1940s",
            effect_desc = "每季控制度 +5，士气/战意 +5，行动点 +1，护卫战力 +10%",
            effects = {
                { kind = "passive_control_gain", value = 5 },
                { kind = "morale_bonus", value = 5 },
                { kind = "ap_bonus", value = 1 },
                { kind = "guard_power_bonus", value = 0.10 },
            },
        },
        -- ── 终极科技 ──
        {
            id   = "d11_cultural_renaissance",
            name = "文化复兴",
            icon = "🌟",
            desc = "在战后废墟上推动文化复兴，重建民族精神，确立家族的精神领袖地位。",
            cost = 2800, turns = 10,
            requires = "d10_national_identity,b8_central_banking",
            era_hint = "1950s",
            effect_desc = "每季控制度 +6，士气/战意 +6，工人效率 +8%",
            effects = {
                { kind = "passive_control_gain", value = 6 },
                { kind = "morale_bonus", value = 6 },
                { kind = "worker_efficiency", value = 0.08 },
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
