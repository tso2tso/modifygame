-- ============================================================================
-- 事件数据：固定历史事件 + 随机事件模板
-- 范围：1904-1955（战后重建），共 43 个固定事件 + 14 个随机模板
-- 所有效果使用系数修正（multiplier / drift），不使用直接数值
-- ============================================================================

local EventsData = {}

--- 事件优先级
EventsData.PRIORITY = {
    MAIN   = "main",    -- 主线大事件，全屏弹窗
    REGION = "region",  -- 地区事件，中型弹窗
    MINOR  = "minor",   -- 小事件，Toast 或小卡片
}

--- 获取全部固定历史事件
---@return table
function EventsData.GetFixedEvents()
    return {
        -- ================================================================
        -- 1904 Q1 - 家族创业开局
        -- ================================================================
        {
            id = "family_founding_1904",
            title = "金矿矿权",
            fixed_date = { year = 1904, quarter = 1 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "⛏️",
            image = "image/events/family_founding_1904.png",
            desc = "经过多年在 Bakovići 矿区的辛苦劳作，你终于攒够了积蓄，从一位年迈的塞尔维亚矿主手中买下了第一块矿权。三百克朗的投入，承载着整个家族的命运。",
            options = {
                {
                    text = "稳扎稳打，小规模开采",
                    desc = "小本经营，稳中求进",
                    effects = {
                        cash = -100,
                        gold_reserve = 30,
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.05, duration = 0 },
                        },
                    },
                },
                {
                    text = "大胆投入，扩大开采规模",
                    desc = "大投入大回报，但资金压力不小",
                    effects = {
                        cash = -300,
                        gold_reserve = 50,
                        workers_bonus = 5,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.15, duration = 4 },
                        },
                    },
                },
                {
                    text = "拉拢当地势力，合资开发",
                    desc = "花小钱交朋友，换来本地人脉",
                    effects = {
                        cash = -50,
                        gold_reserve = 20,
                        security_bonus = 1,
                        modifiers = {
                            { target = "local_relations", value = 15, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1906 Q2 - 铁路测量队
        -- ================================================================
        {
            id = "railway_survey_1906",
            title = "铁路测量队",
            fixed_date = { year = 1906, quarter = 2 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🚂",
            desc = "帝国铁路工程师来到波黑中部测量山谷线路。矿石外运的机会正在出现，但修路也会把更多官员、税吏和外来资本带进矿区。",
            options = {
                {
                    text = "投资车站和装卸设施",
                    desc = "重金投资运输基建，长期降低物流风险",
                    effects = {
                        cash = -180,
                        inflation_delta = 0.005,
                        asset_price_mod = 0.04,
                        asset_price_duration = 6,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.10, duration = 6 },
                            { target = "transport_risk", value = -0.08, duration = 8 },
                        },
                    },
                },
                {
                    text = "与铁路公司签订长期运价",
                    desc = "赚到现钱，但让外资插手经营",
                    effects = {
                        cash = 120,
                        modifiers = {
                            { target = "foreign_control", value = 8, duration = 0 },
                            { target = "civilian_consumption", value = 0.06, duration = 8 },
                        },
                    },
                },
                {
                    text = "维持骡队运输",
                    desc = "保住独立自主，但运输效率落后",
                    effects = {
                        modifiers = {
                            { target = "independence", value = 8, duration = 0 },
                            { target = "transport_risk", value = 0.08, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1907 Q3 - 矿工宿舍扩建
        -- ================================================================
        {
            id = "worker_barracks_1907",
            title = "矿工宿舍扩建",
            fixed_date = { year = 1907, quarter = 3 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🏚️",
            desc = "矿区人口迅速增加，旧木屋已经挤不下新来的矿工。宿舍、医务间和食堂的投入会直接影响士气，也会改变长期人工成本。",
            options = {
                {
                    text = "建设体面宿舍和医务间",
                    desc = "工人满意、口碑提升，但长期人力成本增加",
                    effects = {
                        cash = -220,
                        modifiers = {
                            { target = "worker_morale", value = 18, duration = 0 },
                            { target = "worker_cost_multiplier", value = 0.05, duration = 8 },
                            { target = "public_support", value = 8, duration = 0 },
                        },
                    },
                },
                {
                    text = "只修必要铺位",
                    desc = "凑合过关，小幅改善",
                    effects = {
                        cash = -80,
                        modifiers = {
                            { target = "worker_morale", value = 6, duration = 0 },
                        },
                    },
                },
                {
                    text = "把宿舍包给地方承包人",
                    desc = "省钱又拉关系，但工人怨声载道",
                    effects = {
                        cash = 40,
                        security_bonus = -1,
                        modifiers = {
                            { target = "local_relations", value = 8, duration = 0 },
                            { target = "worker_morale", value = -8, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1908 Q4 - 帝国吞并波黑
        -- ================================================================
        {
            id = "imperial_control_1908",
            title = "帝国管制令",
            fixed_date = { year = 1908, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📜",
            image = "image/events/annexation_crisis_1908.png",
            desc = "奥匈帝国正式吞并波黑，维也纳加强了对地方经济的管控。税收大幅上升，所有矿业许可证需要重新审核。",
            options = {
                {
                    text = "依法缴税，申请合法许可",
                    desc = "守法经营赢得信誉，但税负永久加重",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "tax_rate", value = 0.05, duration = 0 },
                            { target = "legitimacy", value = 20, duration = 0 },
                        },
                    },
                },
                {
                    text = "行贿地方官员，减免税负",
                    desc = "走歪路省税钱，但腐败缠身",
                    effects = {
                        cash = -120,
                        modifiers = {
                            { target = "corruption_risk", value = 10, duration = 8 },
                            { target = "shadow_income", value = 25, duration = 6 },
                        },
                    },
                },
                {
                    text = "部分生产转入地下",
                    desc = "铤而走险赚快钱，治安隐患加剧",
                    effects = {
                        cash = 50,
                        inflation_drift_mod = 0.002,
                        inflation_drift_duration = 4,
                        modifiers = {
                            { target = "security", value = -1, duration = 4 },
                            { target = "shadow_income", value = 30, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1910 Q1 - 波黑议会设立
        -- ================================================================
        {
            id = "bosnian_parliament_1910",
            title = "波黑议会设立",
            fixed_date = { year = 1910, quarter = 1 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🏛️",
            desc = "帝国在波黑设立了地方议会，虽然权力有限，但地方精英开始有了政治参与的渠道。矿业家族可以借此建立政治影响力。",
            options = {
                {
                    text = "资助亲商议员参选",
                    desc = "花钱培养政治盟友，换来税负减免",
                    effects = {
                        cash = -160,
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "political_standing", value = 12, duration = 0 },
                            { target = "tax_rate", value = -0.02, duration = 8 },
                        },
                    },
                },
                {
                    text = "保持距离，专注矿业",
                    desc = "不趟浑水，专注本业",
                    effects = {
                        modifiers = {
                            { target = "mine_output_mult", value = 0.05, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1912 Q2 - 巴尔干战争波及
        -- ================================================================
        {
            id = "balkan_wars_1912",
            title = "巴尔干战云",
            fixed_date = { year = 1912, quarter = 2 },
            priority = EventsData.PRIORITY.REGION,
            icon = "⚔️",
            desc = "巴尔干战争的余波传到波黑，边境局势紧张，物资价格波动剧烈。军需品需求猛增，运输线路受到威胁。",
            options = {
                {
                    text = "囤积物资，静观其变",
                    desc = "稳扎稳打囤物资，降低运输风险",
                    effects = {
                        cash = -80,
                        inflation_delta = 0.015,
                        modifiers = {
                            { target = "supply_reserve", value = 20, duration = 0 },
                            { target = "transport_risk", value = -0.05, duration = 4 },
                            { target = "gold_price_mod", value = 0.15, duration = 4 },
                            { target = "coal_price_mod", value = 0.25, duration = 4 },
                        },
                    },
                },
                {
                    text = "向军方供应矿产",
                    desc = "用矿产换军方关系，短期获利可观",
                    effects = {
                        cash = 200,
                        gold = -3,
                        inflation_delta = 0.02,
                        asset_price_mod = 0.06,
                        asset_price_duration = 4,
                        modifiers = {
                            { target = "military_relation", value = 15, duration = 0 },
                            { target = "military_industry_profit", value = 0.15, duration = 4 },
                            { target = "gold_price_mod", value = 0.10, duration = 4 },
                            { target = "coal_price_mod", value = 0.30, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1914 Q2 - 萨拉热窝枪声（核心主线事件）
        -- ================================================================
        {
            id = "sarajevo_shots_1914",
            title = "萨拉热窝枪声",
            fixed_date = { year = 1914, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "💥",
            image = "image/events/sarajevo_shots_1914.png",
            desc = "1914年6月28日，一声枪响震动了整个地区。大公遇刺，战争阴云迅速笼罩巴尔干。市场恐慌，军需价格飙升，一切都将改变。",
            options = {
                {
                    text = "囤积黄金并暂停扩张",
                    desc = "保守避险，囤金等待风暴过去",
                    effects = {
                        gold = 10,
                        inflation_delta = 0.08,
                        inflation_drift_mod = 0.015,
                        inflation_drift_duration = 8,
                        asset_price_mod = 0.15,
                        asset_price_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "expansion_freeze", value = 1, duration = 4 },
                            { target = "risk", value = -10, duration = 0 },
                            { target = "gold_price_mod", value = 0.50, duration = 8 },
                            { target = "coal_price_mod", value = 0.60, duration = 8 },
                        },
                    },
                },
                {
                    text = "转向军需供应",
                    desc = "发战争财利润丰厚，但民心尽失",
                    effects = {
                        cash = 500,
                        inflation_delta = 0.12,
                        inflation_drift_mod = 0.025,
                        inflation_drift_duration = 12,
                        asset_price_mod = 0.20,
                        asset_price_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "military_relation", value = 15, duration = 0 },
                            { target = "public_support", value = -5, duration = 0 },
                            { target = "military_industry_profit", value = 0.40, duration = 16 },
                            { target = "gold_price_mod", value = 0.45, duration = 12 },
                            { target = "coal_price_mod", value = 0.70, duration = 12 },
                        },
                    },
                },
                {
                    text = "向外转移部分资产",
                    desc = "资产转移海外避险，但本地口碑受损",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.06,
                        war_state = true,
                        modifiers = {
                            { target = "foreign_assets", value = 1, duration = 0 },
                            { target = "local_reputation", value = -10, duration = 0 },
                        },
                    },
                },
            },
            -- 持续修正：战争经济持续 16 个季度
            ongoing_modifiers = {
                duration = 16,
                effects = {
                    military_industry_profit = 0.40,
                    civilian_consumption = -0.20,
                    transport_risk = 0.30,
                    worker_cost_multiplier = 0.15,
                    tax_rate = 0.06,  -- 战争税：战争利润税+所得税加征
                },
            },
        },

        -- ================================================================
        -- 1914 Q3 - 战争动员令
        -- ================================================================
        {
            id = "war_mobilization_1914",
            title = "战争动员令",
            fixed_date = { year = 1914, quarter = 3 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📯",
            image = "image/events/war_breaks_out_1914.png",
            desc = "战争正式吞没帝国边陲。铁路优先运输军队，矿山被要求保障军需，粮食、煤炭和工资同时上涨。",
            options = {
                {
                    text = "接受军方订单",
                    desc = "军需利润可观，但民生和人力成本双双承压",
                    effects = {
                        cash = 260,
                        inflation_delta = 0.10,
                        inflation_drift_mod = 0.020,
                        inflation_drift_duration = 8,
                        asset_price_mod = 0.18,
                        asset_price_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "military_industry_profit", value = 0.25, duration = 8 },
                            { target = "civilian_consumption", value = -0.12, duration = 8 },
                            { target = "worker_cost_multiplier", value = 0.08, duration = 8 },
                        },
                    },
                },
                {
                    text = "优先保障矿工家庭",
                    desc = "赢得民心和士气，但要掏腰包",
                    effects = {
                        cash = -120,
                        inflation_delta = 0.07,
                        war_state = true,
                        modifiers = {
                            { target = "worker_morale", value = 12, duration = 0 },
                            { target = "public_support", value = 15, duration = 0 },
                            { target = "civilian_consumption", value = 0.08, duration = 6 },
                        },
                    },
                },
                {
                    text = "暗中转移库存",
                    desc = "黑市暴利诱人，但法律风险极高",
                    effects = {
                        gold = 6,
                        inflation_delta = 0.08,
                        war_state = true,
                        modifiers = {
                            { target = "shadow_income", value = 45, duration = 6 },
                            { target = "transport_risk", value = 0.18, duration = 8 },
                            { target = "legitimacy", value = -8, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1915 Q2 - 战时通胀加剧
        -- ================================================================
        {
            id = "wartime_inflation_1915",
            title = "战时通胀加剧",
            fixed_date = { year = 1915, quarter = 2 },
            priority = EventsData.PRIORITY.REGION,
            icon = "💰",
            desc = "帝国大量印钞支撑战争开销，克朗购买力急速下降。面粉价格翻倍，工人要求加薪的声音越来越大。",
            options = {
                {
                    text = "提前囤积实物资产",
                    desc = "现金换黄金保值，但加剧通胀",
                    effects = {
                        cash = -200,
                        gold = 4,
                        inflation_delta = 0.10,
                        inflation_drift_mod = 0.018,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "gold_price_mod", value = 0.20, duration = 6 },
                        },
                    },
                },
                {
                    text = "跟随通胀调薪",
                    desc = "工人满意，但工资成本永久增加",
                    effects = {
                        cash = -150,
                        inflation_delta = 0.08,
                        inflation_drift_mod = 0.012,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "worker_morale", value = 10, duration = 0 },
                            { target = "worker_cost_multiplier", value = 0.10, duration = 0 },
                        },
                    },
                },
                {
                    text = "冻结工资，以实物补贴",
                    desc = "省下现金，但工人怨气积累",
                    effects = {
                        inflation_delta = 0.09,
                        inflation_drift_mod = 0.015,
                        inflation_drift_duration = 4,
                        modifiers = {
                            { target = "worker_morale", value = -8, duration = 0 },
                            { target = "civilian_consumption", value = -0.06, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1916 Q1 - 物资短缺
        -- ================================================================
        {
            id = "wartime_shortage_1916",
            title = "物资短缺",
            fixed_date = { year = 1916, quarter = 1 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🥖",
            desc = "长期战争让市场上的粮食、煤炭和药品越来越贵。矿工要求提高配给，军方仍在催促产量。",
            options = {
                {
                    text = "提高工资和配给",
                    desc = "善待工人赢得人心，但开支大增",
                    effects = {
                        cash = -240,
                        inflation_delta = 0.12,
                        inflation_drift_mod = 0.018,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "worker_wage", value = 1, duration = 0 },
                            { target = "worker_morale", value = 18, duration = 0 },
                            { target = "public_support", value = 8, duration = 0 },
                            { target = "coal_price_mod", value = 0.60, duration = 6 },
                        },
                    },
                },
                {
                    text = "削减民用供给保军需",
                    desc = "军工暴利，但民间怨恨沸腾",
                    effects = {
                        cash = 360,
                        inflation_delta = 0.15,
                        inflation_drift_mod = 0.022,
                        inflation_drift_duration = 6,
                        asset_price_mod = 0.15,
                        asset_price_duration = 6,
                        security_bonus = -1,
                        modifiers = {
                            { target = "military_industry_profit", value = 0.20, duration = 6 },
                            { target = "public_support", value = -18, duration = 0 },
                            { target = "civilian_consumption", value = -0.18, duration = 6 },
                        },
                    },
                },
                {
                    text = "开辟黑市补给线",
                    desc = "黑市补给利润高，但腐败和风险并行",
                    effects = {
                        cash = 120,
                        gold = -2,
                        inflation_drift_mod = 0.016,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "shadow_income", value = 70, duration = 6 },
                            { target = "transport_risk", value = 0.25, duration = 6 },
                            { target = "corruption_risk", value = 12, duration = 8 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1917 Q1 - 兵变与逃亡潮
        -- ================================================================
        {
            id = "mutiny_wave_1917",
            title = "兵变与逃亡潮",
            fixed_date = { year = 1917, quarter = 1 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🏳️",
            desc = "前线溃败的消息传来，大批士兵逃离战场涌入波黑山区。逃兵中有矿工出身的熟手，也有心怀叵测的亡命之徒。",
            options = {
                {
                    text = "收留逃兵充当矿工",
                    desc = "廉价劳力补充产能，但治安和纪律下降",
                    effects = {
                        workers_bonus = 8,
                        inflation_delta = 0.02,
                        security_bonus = -1,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.10, duration = 4 },
                            { target = "worker_morale", value = -5, duration = 0 },
                        },
                    },
                },
                {
                    text = "组建矿区自卫队",
                    desc = "守护矿区赢得民心，但得罪军方",
                    effects = {
                        cash = -180,
                        inflation_delta = 0.015,
                        security_bonus = 1,
                        modifiers = {
                            { target = "public_support", value = 10, duration = 0 },
                            { target = "military_relation", value = -5, duration = 0 },
                        },
                    },
                },
                {
                    text = "向当局举报换取奖赏",
                    desc = "讨好当局换奖赏，但失去民间信任",
                    effects = {
                        cash = 100,
                        modifiers = {
                            { target = "legitimacy", value = 8, duration = 0 },
                            { target = "public_support", value = -12, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1917 Q3 - 俄国革命冲击
        -- ================================================================
        {
            id = "russian_revolution_1917",
            title = "俄国革命冲击",
            fixed_date = { year = 1917, quarter = 3 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🔴",
            image = "image/events/russian_revolution_1917.png",
            desc = "俄国爆发十月革命，工人运动浪潮席卷欧洲。波黑矿区的工人也开始讨论工人自治和公平分配。",
            options = {
                {
                    text = "主动改善劳工待遇",
                    desc = "顺应潮流安抚人心，但永久推高成本",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.02,
                        modifiers = {
                            { target = "worker_morale", value = 15, duration = 0 },
                            { target = "worker_cost_multiplier", value = 0.08, duration = 0 },
                            { target = "public_support", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "强化管控，压制激进工人",
                    desc = "铁腕维稳，但激化矛盾",
                    effects = {
                        cash = -60,
                        inflation_delta = 0.01,
                        security_bonus = 1,
                        modifiers = {
                            { target = "worker_morale", value = -15, duration = 0 },
                            { target = "public_support", value = -8, duration = 0 },
                        },
                    },
                },
                {
                    text = "暗中资助温和改良派",
                    desc = "暗中扶植温和派，争取时间但留下把柄",
                    effects = {
                        cash = -120,
                        modifiers = {
                            { target = "political_standing", value = 8, duration = 0 },
                            { target = "corruption_risk", value = 5, duration = 6 },
                            { target = "worker_morale", value = 5, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1918 Q4 - 帝国崩解
        -- ================================================================
        {
            id = "empire_collapse_1918",
            title = "帝国崩解",
            fixed_date = { year = 1918, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🏚️",
            desc = "奥匈帝国宣告瓦解，旧有的经济秩序和法律体系一夜之间土崩瓦解。旧合同失效，债务面临重估，权力出现真空。这既是危机，也是千载难逢的机遇。",
            options = {
                {
                    text = "迅速接管废弃资产",
                    desc = "趁乱抄底扩张资产，但法律地位存疑",
                    effects = {
                        cash = -300,
                        inflation_delta = 0.08,
                        inflation_drift_mod = -0.025,
                        inflation_drift_duration = 6,
                        asset_price_mod = -0.25,
                        asset_price_duration = 6,
                        war_state = false,
                        modifiers = {
                            { target = "total_assets", value = 500, duration = 0 },
                            { target = "legitimacy", value = -15, duration = 0 },
                        },
                    },
                },
                {
                    text = "与新政权合作，确保地位",
                    desc = "顺势投靠新政权，赢得政治地位",
                    effects = {
                        cash = -100,
                        inflation_delta = -0.03,
                        inflation_drift_mod = -0.030,
                        inflation_drift_duration = 8,
                        war_state = false,
                        modifiers = {
                            { target = "political_standing", value = 20, duration = 0 },
                            { target = "legitimacy", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "援助难民和失业工人",
                    desc = "慷慨援助赢得口碑，为重建打基础",
                    effects = {
                        cash = -200,
                        inflation_delta = -0.015,
                        inflation_drift_mod = -0.020,
                        inflation_drift_duration = 6,
                        war_state = false,
                        modifiers = {
                            { target = "public_support", value = 25, duration = 0 },
                            { target = "culture", value = 10, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1919 Q2 - SHS王国成立
        -- ================================================================
        {
            id = "kingdom_shs_1919",
            title = "塞尔维亚-克罗地亚-斯洛文尼亚王国",
            fixed_date = { year = 1919, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "👑",
            image = "image/events/treaty_of_versailles_1919.png",
            desc = "新王国成立，波黑被纳入大塞尔维亚框架。新政府推行土地改革和矿业国有化政策，旧帝国时代的产权面临重新认定。",
            options = {
                {
                    text = "主动配合产权登记",
                    desc = "合法合规站稳脚跟，但税负永久加重",
                    effects = {
                        cash = -150,
                        inflation_delta = 0.015,
                        modifiers = {
                            { target = "legitimacy", value = 18, duration = 0 },
                            { target = "tax_rate", value = 0.03, duration = 0 },
                            { target = "political_standing", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "利用旧关系打通新官员",
                    desc = "打通关系减税，但埋下腐败隐患",
                    effects = {
                        cash = -80,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "corruption_risk", value = 12, duration = 8 },
                            { target = "tax_rate", value = -0.02, duration = 6 },
                        },
                    },
                },
                {
                    text = "将部分资产转移到瑞士",
                    desc = "海外藏富未雨绸缪，但本地产能受损",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "foreign_assets", value = 1, duration = 0 },
                            { target = "mine_output_mult", value = -0.05, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1920 Q3 - 矿业工会化浪潮
        -- ================================================================
        {
            id = "unionization_wave_1920",
            title = "矿业工会化浪潮",
            fixed_date = { year = 1920, quarter = 3 },
            priority = EventsData.PRIORITY.REGION,
            icon = "✊",
            desc = "新国家劳工法出台，矿工工会迅速壮大。工会要求集体协商工资、工时和安全标准，传统的矿主说了算时代正在终结。",
            options = {
                {
                    text = "接受工会协商，建立合作机制",
                    desc = "赢得工人拥护，但人力成本永久攀升",
                    effects = {
                        inflation_delta = 0.015,
                        modifiers = {
                            { target = "worker_morale", value = 20, duration = 0 },
                            { target = "worker_cost_multiplier", value = 0.12, duration = 0 },
                            { target = "public_support", value = 12, duration = 0 },
                        },
                    },
                },
                {
                    text = "引入计件工资制度",
                    desc = "效率提升但工人不满",
                    effects = {
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.10, duration = 0 },
                            { target = "worker_morale", value = -5, duration = 0 },
                        },
                    },
                },
                {
                    text = "暗中分化工会领导层",
                    desc = "分裂工会维持控制，但名声和士气双降",
                    effects = {
                        cash = -100,
                        modifiers = {
                            { target = "worker_morale", value = -10, duration = 0 },
                            { target = "corruption_risk", value = 8, duration = 6 },
                            { target = "public_support", value = -8, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1922 Q1 - 战后通胀高峰
        -- ================================================================
        {
            id = "postwar_inflation_1922",
            title = "战后通胀高峰",
            fixed_date = { year = 1922, quarter = 1 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📈",
            desc = "战争债务和新货币转换导致通胀持续飙升。第纳尔购买力快速下跌，物价月月上涨，持有现金等于持续亏损。",
            options = {
                {
                    text = "全面转持黄金和实物",
                    desc = "全部换成硬通货保值，代价是通胀加速",
                    effects = {
                        cash = -400,
                        gold = 12,
                        inflation_delta = 0.15,
                        inflation_drift_mod = 0.025,
                        inflation_drift_duration = 8,
                        modifiers = {
                            { target = "gold_price_mod", value = 0.25, duration = 8 },
                        },
                    },
                },
                {
                    text = "加速投资固定资产",
                    desc = "趁贬值抄底固定资产，长期产能提升",
                    effects = {
                        cash = -350,
                        inflation_delta = 0.12,
                        inflation_drift_mod = 0.020,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.12, duration = 0 },
                            { target = "total_assets", value = 300, duration = 0 },
                        },
                    },
                },
                {
                    text = "借入长期贷款（通胀还债）",
                    desc = "借钱让通胀还债，聪明但有风险",
                    effects = {
                        cash = 500,
                        inflation_delta = 0.10,
                        inflation_drift_mod = 0.018,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "legitimacy", value = -8, duration = 0 },
                            { target = "corruption_risk", value = 5, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1923 Q3 - 铁路国有化风波
        -- ================================================================
        {
            id = "railway_nationalization_1923",
            title = "铁路国有化风波",
            fixed_date = { year = 1923, quarter = 3 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🚂",
            desc = "新政府宣布铁路收归国有，私人投资者的铁路股份被强制收购。依赖铁路运矿的家族面临运输成本变化。",
            options = {
                {
                    text = "接受补偿，转投公路运输",
                    desc = "拿补偿走独立路线，但运输不便",
                    effects = {
                        cash = 200,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "transport_risk", value = 0.10, duration = 6 },
                            { target = "independence", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "利用政治关系保留优惠运价",
                    desc = "走后门保运价优惠，但滋生腐败",
                    effects = {
                        cash = -100,
                        modifiers = {
                            { target = "political_standing", value = 5, duration = 0 },
                            { target = "transport_risk", value = -0.05, duration = 8 },
                            { target = "corruption_risk", value = 6, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1925 Q1 - 矿业现代化机遇
        -- ================================================================
        {
            id = "mining_modernization_1925",
            title = "矿业现代化机遇",
            fixed_date = { year = 1925, quarter = 1 },
            priority = EventsData.PRIORITY.REGION,
            icon = "⚙️",
            desc = "战后欧洲工业复苏，德国和英国的矿业设备商向巴尔干推销电气化采矿设备。效率可大幅提升，但投资巨大。",
            options = {
                {
                    text = "引进电气化设备",
                    desc = "效率飞跃式提升，但让出部分控制权",
                    effects = {
                        cash = -450,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.20, duration = 0 },
                            { target = "worker_cost_multiplier", value = -0.05, duration = 0 },
                            { target = "foreign_control", value = 6, duration = 0 },
                        },
                    },
                },
                {
                    text = "仅购买核心部件",
                    desc = "适度升级，量力而行",
                    effects = {
                        cash = -180,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.08, duration = 0 },
                        },
                    },
                },
                {
                    text = "自主研发改良工艺",
                    desc = "自力更生搞研发，保住独立性",
                    effects = {
                        cash = -100,
                        modifiers = {
                            { target = "tech_bonus", value = 8, duration = 8 },
                            { target = "independence", value = 8, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1926 Q3 - 英国大罢工波及国际矿市
        -- ================================================================
        {
            id = "uk_general_strike_1926",
            title = "英国大罢工冲击",
            fixed_date = { year = 1926, quarter = 3 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🏭",
            desc = "英国爆发总罢工，煤矿停产导致国际煤炭和矿石价格暴涨。巴尔干矿产出口窗口难得一开。",
            options = {
                {
                    text = "全力增产抢占市场",
                    desc = "全速开工抢市场，赚得多但工人吃不消",
                    effects = {
                        cash = 350,
                        inflation_delta = 0.015,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.15, duration = 3 },
                            { target = "worker_morale", value = -8, duration = 0 },
                            { target = "coal_price_mod", value = 0.35, duration = 4 },
                        },
                    },
                },
                {
                    text = "维持正常产量，以溢价出售",
                    desc = "稳吃溢价，不冒进",
                    effects = {
                        cash = 200,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "coal_price_mod", value = 0.20, duration = 3 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1928 Q2 - 南斯拉夫政治危机
        -- ================================================================
        {
            id = "political_crisis_1928",
            title = "议会枪击事件",
            fixed_date = { year = 1928, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🔫",
            desc = "议会中发生枪击事件，克罗地亚领袖中弹身亡。族群矛盾激化，国家面临分裂危机。经济不确定性陡增，资本外流加速。",
            options = {
                {
                    text = "加强与贝尔格莱德中央关系",
                    desc = "靠拢中央赢得政治资本，但本地口碑下降",
                    effects = {
                        cash = -120,
                        inflation_delta = 0.02,
                        modifiers = {
                            { target = "political_standing", value = 15, duration = 0 },
                            { target = "local_reputation", value = -5, duration = 0 },
                        },
                    },
                },
                {
                    text = "强化本地自治网络",
                    desc = "经营本地人脉，增强自主权",
                    effects = {
                        cash = -100,
                        inflation_delta = 0.015,
                        modifiers = {
                            { target = "local_relations", value = 15, duration = 0 },
                            { target = "independence", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "趁乱低价收购动荡地区资产",
                    desc = "趁乱抄底扩张，但手段不太光彩",
                    effects = {
                        cash = -300,
                        inflation_delta = 0.025,
                        asset_price_mod = -0.08,
                        asset_price_duration = 4,
                        modifiers = {
                            { target = "total_assets", value = 400, duration = 0 },
                            { target = "legitimacy", value = -8, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1929 Q1 - 国王独裁
        -- ================================================================
        {
            id = "royal_dictatorship_1929",
            title = "国王独裁",
            fixed_date = { year = 1929, quarter = 1 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "👑",
            desc = "国王废除宪法，建立独裁统治，改国名为南斯拉夫王国。所有政党被取缔，经济管控收紧，私人企业面临更严格的审查。",
            options = {
                {
                    text = "积极配合新体制",
                    desc = "顺从新体制换取政治地位，但失去经营自主",
                    effects = {
                        cash = -80,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "legitimacy", value = 15, duration = 0 },
                            { target = "political_standing", value = 12, duration = 0 },
                            { target = "independence", value = -10, duration = 0 },
                        },
                    },
                },
                {
                    text = "低调经营，避开政治",
                    desc = "闷声做事，不出风头",
                    effects = {
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "public_support", value = 5, duration = 0 },
                        },
                    },
                },
                {
                    text = "暗中支持反对派",
                    desc = "暗中押注反对派，有远见但风险极大",
                    effects = {
                        cash = -150,
                        inflation_delta = 0.015,
                        modifiers = {
                            { target = "corruption_risk", value = 15, duration = 8 },
                            { target = "political_standing", value = -10, duration = 0 },
                            { target = "local_relations", value = 10, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1929 Q4 - 大萧条波及
        -- ================================================================
        {
            id = "great_depression_1929",
            title = "大萧条波及",
            fixed_date = { year = 1929, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📉",
            image = "image/events/economic_crisis_1929.png",
            desc = "纽约股灾的冲击沿着银行和贸易网络传到巴尔干。信贷收缩、订单减少，现金比账面资产更重要。",
            options = {
                {
                    text = "收缩债务，保留现金",
                    desc = "勒紧裤腰带过寒冬，稳健但要忍受萎缩",
                    effects = {
                        cash = -250,
                        inflation_delta = -0.08,
                        inflation_drift_mod = -0.025,
                        inflation_drift_duration = 8,
                        asset_price_mod = -0.35,
                        asset_price_duration = 8,
                        modifiers = {
                            { target = "risk", value = -12, duration = 8 },
                            { target = "civilian_consumption", value = -0.15, duration = 8 },
                            { target = "gold_price_mod", value = 0.35, duration = 8 },
                            { target = "coal_price_mod", value = -0.25, duration = 8 },
                            { target = "tax_rate", value = -0.03, duration = 12 },  -- 经济萎缩，税基收窄
                        },
                    },
                },
                {
                    text = "抄底廉价资产",
                    desc = "趁大萧条抄底资产，豪赌但回报丰厚",
                    effects = {
                        cash = -500,
                        inflation_delta = -0.06,
                        inflation_drift_mod = -0.020,
                        inflation_drift_duration = 6,
                        asset_price_mod = -0.45,
                        asset_price_duration = 4,
                        modifiers = {
                            { target = "total_assets", value = 900, duration = 0 },
                            { target = "foreign_control", value = -6, duration = 0 },
                            { target = "tax_rate", value = -0.03, duration = 12 },  -- 经济萎缩，税基收窄
                        },
                    },
                },
                {
                    text = "裁员并停掉亏损业务",
                    desc = "裁员止血保现金，但人心散了",
                    effects = {
                        cash = 260,
                        inflation_delta = -0.015,
                        modifiers = {
                            { target = "worker_morale", value = -18, duration = 0 },
                            { target = "public_support", value = -10, duration = 0 },
                            { target = "mine_output_mult", value = -0.15, duration = 4 },
                            { target = "tax_rate", value = -0.03, duration = 12 },  -- 经济萎缩，税基收窄
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1931 Q1 - 银行挤兑风潮
        -- ================================================================
        {
            id = "bank_run_1931",
            title = "银行挤兑风潮",
            fixed_date = { year = 1931, quarter = 1 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🏦",
            desc = "奥地利信贷银行倒闭引发连锁效应，巴尔干各地银行挤兑。储户恐慌取款，信贷市场冻结。",
            options = {
                {
                    text = "提前提取银行存款",
                    desc = "先下手为强抢现金，但名声受损",
                    effects = {
                        cash = 300,
                        inflation_delta = 0.06,
                        inflation_drift_mod = 0.012,
                        inflation_drift_duration = 4,
                        modifiers = {
                            { target = "legitimacy", value = -5, duration = 0 },
                            { target = "gold_price_mod", value = 0.20, duration = 4 },
                        },
                    },
                },
                {
                    text = "公开宣布不撤资以稳定人心",
                    desc = "公开站台稳定人心，赢得信誉",
                    effects = {
                        cash = -100,
                        inflation_delta = 0.04,
                        modifiers = {
                            { target = "legitimacy", value = 12, duration = 0 },
                            { target = "public_support", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "趁机以低价收购银行不良资产",
                    desc = "低价捡漏不良资产，但手段有些灰色",
                    effects = {
                        cash = -350,
                        inflation_delta = 0.05,
                        asset_price_mod = -0.12,
                        asset_price_duration = 4,
                        modifiers = {
                            { target = "total_assets", value = 500, duration = 0 },
                            { target = "corruption_risk", value = 8, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1933 Q1 - 法西斯思潮蔓延
        -- ================================================================
        {
            id = "fascist_tide_1933",
            title = "法西斯思潮蔓延",
            fixed_date = { year = 1933, quarter = 1 },
            priority = EventsData.PRIORITY.REGION,
            icon = "⚡",
            desc = "希特勒上台后，法西斯思潮在欧洲蔓延。南斯拉夫国内极端民族主义组织活动增加，地方安全形势恶化，但德国经济复苏也带来新的贸易机会。",
            options = {
                {
                    text = "拓展对德贸易",
                    desc = "搭上德国经济快车，但绑定越来越深",
                    effects = {
                        cash = 250,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.08, duration = 6 },
                            { target = "foreign_control", value = 8, duration = 0 },
                            { target = "coal_price_mod", value = 0.15, duration = 6 },
                        },
                    },
                },
                {
                    text = "加强与英法的经济联系",
                    desc = "押注西方阵营，稳健但收益有限",
                    effects = {
                        cash = -80,
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "legitimacy", value = 8, duration = 0 },
                            { target = "political_standing", value = 5, duration = 0 },
                        },
                    },
                },
                {
                    text = "两面下注，维持中立",
                    desc = "左右逢源保独立，但谁都不讨好",
                    effects = {
                        inflation_delta = 0.008,
                        modifiers = {
                            { target = "independence", value = 5, duration = 0 },
                            { target = "political_standing", value = -3, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1934 Q4 - 国王遇刺
        -- ================================================================
        {
            id = "king_assassination_1934",
            title = "国王遇刺",
            fixed_date = { year = 1934, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🗡️",
            desc = "亚历山大一世在法国马赛遇刺身亡。年幼的王子即位，摄政委员会执政。政局动荡，各派势力争夺权力真空。",
            options = {
                {
                    text = "支持摄政委员会",
                    desc = "站队摄政派赢得政治靠山",
                    effects = {
                        cash = -100,
                        inflation_delta = 0.02,
                        modifiers = {
                            { target = "political_standing", value = 12, duration = 0 },
                            { target = "legitimacy", value = 8, duration = 0 },
                        },
                    },
                },
                {
                    text = "保持中立，加强资产保护",
                    desc = "不表态，闷声保全资产",
                    effects = {
                        cash = -60,
                        inflation_delta = 0.015,
                        asset_price_mod = -0.06,
                        asset_price_duration = 4,
                        modifiers = {
                            { target = "gold_price_mod", value = 0.10, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1936 Q2 - 德国重新武装
        -- ================================================================
        {
            id = "german_rearmament_1936",
            title = "德国重新武装",
            fixed_date = { year = 1936, quarter = 2 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🔧",
            desc = "德国大规模重新武装，对原材料的需求急剧增加。巴尔干矿产成为重要供应来源，但与轴心国的经济绑定也意味着政治风险。",
            options = {
                {
                    text = "签订对德矿产出口合同",
                    desc = "军工大单利润丰厚，但从此受制于人",
                    effects = {
                        cash = 400,
                        inflation_delta = 0.015,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.15, duration = 8 },
                            { target = "military_industry_profit", value = 0.20, duration = 8 },
                            { target = "foreign_control", value = 12, duration = 0 },
                            { target = "coal_price_mod", value = 0.25, duration = 8 },
                        },
                    },
                },
                {
                    text = "多元化出口渠道",
                    desc = "多线布局保独立，赚得少但安全",
                    effects = {
                        cash = 150,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.06, duration = 6 },
                            { target = "independence", value = 8, duration = 0 },
                        },
                    },
                },
                {
                    text = "缩减出口，优先内需",
                    desc = "优先保民生，少赚但口碑好",
                    effects = {
                        inflation_delta = 0.008,
                        modifiers = {
                            { target = "public_support", value = 8, duration = 0 },
                            { target = "civilian_consumption", value = 0.06, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1937 Q3 - 西班牙内战与国际志愿者
        -- ================================================================
        {
            id = "spanish_civil_war_1937",
            title = "西班牙内战阴影",
            fixed_date = { year = 1937, quarter = 3 },
            priority = EventsData.PRIORITY.MINOR,
            icon = "🌍",
            desc = "西班牙内战中，来自南斯拉夫的志愿者也加入了国际纵队。矿区中有工人请假前往西班牙，也有人带回激进思想。",
            options = {
                {
                    text = "允许工人志愿参战",
                    desc = "放人走赢得人心，但劳动力减少",
                    effects = {
                        workers_bonus = -3,
                        inflation_delta = 0.008,
                        modifiers = {
                            { target = "public_support", value = 10, duration = 0 },
                            { target = "worker_morale", value = 8, duration = 0 },
                        },
                    },
                },
                {
                    text = "禁止矿工离岗",
                    desc = "保住产能，但工人心生不满",
                    effects = {
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "worker_morale", value = -10, duration = 0 },
                            { target = "mine_output_mult", value = 0.05, duration = 3 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1938 Q4 - 慕尼黑协定与战争逼近
        -- ================================================================
        {
            id = "munich_agreement_1938",
            title = "慕尼黑协定",
            fixed_date = { year = 1938, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📋",
            image = "image/events/anschluss_1938.png",
            desc = "英法对德绥靖让整个欧洲感到不安。战争似乎不可避免，各国开始秘密囤积战略物资。巴尔干矿产的战略价值急剧上升。",
            options = {
                {
                    text = "大量囤积黄金和战略物资",
                    desc = "重金囤积硬通货和物资，为战争做准备",
                    effects = {
                        cash = -350,
                        gold = 8,
                        inflation_delta = 0.06,
                        inflation_drift_mod = 0.012,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "gold_price_mod", value = 0.25, duration = 8 },
                            { target = "supply_reserve", value = 30, duration = 0 },
                        },
                    },
                },
                {
                    text = "趁战略需求高涨提价出口",
                    desc = "趁战略需求大赚一笔，短期暴利",
                    effects = {
                        cash = 500,
                        inflation_delta = 0.05,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.12, duration = 4 },
                            { target = "military_industry_profit", value = 0.15, duration = 6 },
                            { target = "coal_price_mod", value = 0.30, duration = 6 },
                        },
                    },
                },
                {
                    text = "加固矿区防御设施",
                    desc = "加固防御未雨绸缪，长远保障运输安全",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.04,
                        security_bonus = 1,
                        modifiers = {
                            { target = "transport_risk", value = -0.10, duration = 8 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1939 Q3 - 二战爆发
        -- ================================================================
        {
            id = "wwii_outbreak_1939",
            title = "二战爆发",
            fixed_date = { year = 1939, quarter = 3 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🌐",
            image = "image/events/wwii_starts_1939.png",
            desc = "德国入侵波兰，英法对德宣战，第二次世界大战正式爆发。虽然南斯拉夫暂时保持中立，但战争经济已经开始重塑一切。",
            options = {
                {
                    text = "向交战各方出口矿产",
                    desc = "两边卖军火大发战争财，但通胀飙升",
                    effects = {
                        cash = 600,
                        inflation_delta = 0.10,
                        inflation_drift_mod = 0.020,
                        inflation_drift_duration = 8,
                        modifiers = {
                            { target = "military_industry_profit", value = 0.25, duration = 8 },
                            { target = "mine_output_mult", value = 0.12, duration = 6 },
                            { target = "coal_price_mod", value = 0.40, duration = 8 },
                            { target = "gold_price_mod", value = 0.20, duration = 8 },
                        },
                    },
                },
                {
                    text = "收缩经营，保存实力",
                    desc = "收缩保命，牺牲产能换安全",
                    effects = {
                        cash = -100,
                        inflation_delta = 0.07,
                        inflation_drift_mod = 0.012,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "risk", value = -10, duration = 0 },
                            { target = "mine_output_mult", value = -0.08, duration = 4 },
                        },
                    },
                },
                {
                    text = "秘密转移核心资产到中立国",
                    desc = "海外转移资产避险，但本地口碑尽毁",
                    effects = {
                        cash = -300,
                        inflation_delta = 0.08,
                        modifiers = {
                            { target = "foreign_assets", value = 2, duration = 0 },
                            { target = "local_reputation", value = -12, duration = 0 },
                            { target = "gold_price_mod", value = 0.15, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1941 Q1 - 轴心国最后通牒
        -- ================================================================
        {
            id = "axis_ultimatum_1941",
            title = "轴心国最后通牒",
            fixed_date = { year = 1941, quarter = 1 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "⚠️",
            desc = "德国向南斯拉夫发出最后通牒，要求加入轴心国。政府内部激烈争论，军事政变推翻了亲德政府，但这也加速了德国入侵。",
            options = {
                {
                    text = "紧急加固矿区并储备物资",
                    desc = "紧急备战加固矿区，花费不菲但有备无患",
                    effects = {
                        cash = -300,
                        inflation_delta = 0.12,
                        inflation_drift_mod = 0.025,
                        inflation_drift_duration = 8,
                        security_bonus = 1,
                        modifiers = {
                            { target = "supply_reserve", value = 40, duration = 0 },
                            { target = "gold_price_mod", value = 0.30, duration = 8 },
                            { target = "coal_price_mod", value = 0.45, duration = 8 },
                        },
                    },
                },
                {
                    text = "立即将家族成员撤离",
                    desc = "家人安全第一，但会被骂'跑路'",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.10,
                        modifiers = {
                            { target = "public_support", value = -8, duration = 0 },
                            { target = "foreign_assets", value = 1, duration = 0 },
                        },
                    },
                },
                {
                    text = "联络抵抗组织",
                    desc = "投身抵抗运动，赢得多方信任",
                    effects = {
                        cash = -100,
                        inflation_delta = 0.09,
                        modifiers = {
                            { target = "military_relation", value = 10, duration = 0 },
                            { target = "public_support", value = 15, duration = 0 },
                            { target = "legitimacy", value = 8, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1941 Q2 - 旧秩序瓦解（德军入侵）
        -- ================================================================
        {
            id = "old_order_collapse_1941",
            title = "旧秩序瓦解",
            fixed_date = { year = 1941, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🪖",
            desc = "德军闪击南斯拉夫，十日之内全境沦陷。行政体系碎裂，工厂、铁路和矿山都面临征用，家族必须决定资产优先还是人员优先。",
            options = {
                {
                    text = "迁走核心设备",
                    desc = "保住核心设备，但产能大幅下滑且要缴占领税",
                    effects = {
                        cash = -420,
                        inflation_delta = 0.15,
                        inflation_drift_mod = 0.030,
                        inflation_drift_duration = 10,
                        asset_price_mod = 0.20,
                        asset_price_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "mine_output_mult", value = -0.20, duration = 6 },
                            { target = "total_assets", value = 700, duration = 0 },
                            { target = "gold_price_mod", value = 0.35, duration = 10 },
                            { target = "coal_price_mod", value = 0.55, duration = 10 },
                            { target = "tax_rate", value = 0.10, duration = 12 },  -- 占领军征收贡金
                        },
                    },
                },
                {
                    text = "与占领当局合作保产",
                    desc = "与占领军合作赚大钱，但沦为'汉奸'",
                    effects = {
                        cash = 600,
                        inflation_delta = 0.20,
                        inflation_drift_mod = 0.035,
                        inflation_drift_duration = 10,
                        war_state = true,
                        modifiers = {
                            { target = "military_industry_profit", value = 0.30, duration = 10 },
                            { target = "legitimacy", value = -25, duration = 0 },
                            { target = "public_support", value = -20, duration = 0 },
                            { target = "tax_rate", value = 0.15, duration = 12 },  -- 合作者承担更高占领税
                        },
                    },
                },
                {
                    text = "建立地下供应网",
                    desc = "建地下网络求生，暗利高但风险如影随形",
                    effects = {
                        gold = -4,
                        inflation_delta = 0.12,
                        inflation_drift_mod = 0.022,
                        inflation_drift_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "shadow_income", value = 90, duration = 10 },
                            { target = "transport_risk", value = 0.30, duration = 10 },
                            { target = "public_support", value = 10, duration = 0 },
                            { target = "tax_rate", value = 0.06, duration = 12 },  -- 地下经营仍受部分征税
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1942 Q2 - 游击战与民族仇杀
        -- ================================================================
        {
            id = "partisan_warfare_1942",
            title = "游击战与民族仇杀",
            fixed_date = { year = 1942, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🔥",
            desc = "铁托领导的游击队与切特尼克在波黑山区激烈交战。矿区夹在各方势力之间，物资和人员被反复征用。族群间的暴力让整个社区陷入恐惧。",
            options = {
                {
                    text = "暗中资助游击队",
                    desc = "资助游击队赢得民心，但矿区安全堪忧",
                    effects = {
                        cash = -200,
                        gold = -3,
                        inflation_delta = 0.10,
                        inflation_drift_mod = 0.018,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "public_support", value = 20, duration = 0 },
                            { target = "legitimacy", value = 10, duration = 0 },
                            { target = "transport_risk", value = 0.20, duration = 6 },
                        },
                    },
                },
                {
                    text = "保持中立，全力保护矿区",
                    desc = "谁都不帮只管赚钱，但安全形势恶化",
                    effects = {
                        cash = -300,
                        inflation_delta = 0.12,
                        inflation_drift_mod = 0.015,
                        inflation_drift_duration = 6,
                        modifiers = {
                            { target = "security", value = -1, duration = 6 },
                            { target = "shadow_income", value = 40, duration = 6 },
                        },
                    },
                },
                {
                    text = "组织矿区居民互保",
                    desc = "组织民间互保，凝聚人心守护家园",
                    effects = {
                        cash = -250,
                        inflation_delta = 0.08,
                        security_bonus = 1,
                        modifiers = {
                            { target = "worker_morale", value = 10, duration = 0 },
                            { target = "public_support", value = 15, duration = 0 },
                            { target = "culture", value = 8, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1943 Q3 - 意大利投降
        -- ================================================================
        {
            id = "italy_surrender_1943",
            title = "意大利投降",
            fixed_date = { year = 1943, quarter = 3 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🏳️",
            desc = "意大利向盟军投降，驻扎在巴尔干的意军撤出。大量武器装备和物资散落，各方势力疯狂争夺。权力真空带来机遇也带来危险。",
            options = {
                {
                    text = "抢收意军遗弃物资",
                    desc = "抢收物资充实储备，但治安和运输风险加大",
                    effects = {
                        cash = 300,
                        inflation_delta = 0.08,
                        security_bonus = -1,
                        modifiers = {
                            { target = "supply_reserve", value = 25, duration = 0 },
                            { target = "military_relation", value = 8, duration = 0 },
                            { target = "transport_risk", value = 0.15, duration = 4 },
                        },
                    },
                },
                {
                    text = "协助盟军情报工作",
                    desc = "协助盟军换取政治资本和海外布局",
                    effects = {
                        cash = -80,
                        inflation_delta = 0.06,
                        modifiers = {
                            { target = "political_standing", value = 12, duration = 0 },
                            { target = "foreign_assets", value = 1, duration = 0 },
                            { target = "legitimacy", value = 8, duration = 0 },
                        },
                    },
                },
                {
                    text = "避开冲突，加固矿区防御",
                    desc = "不冒险，加固自家防线求稳",
                    effects = {
                        cash = -120,
                        inflation_delta = 0.06,
                        security_bonus = 1,
                        modifiers = {
                            { target = "worker_morale", value = 5, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1944 Q2 - 盟军轰炸与解放前夜
        -- ================================================================
        {
            id = "allied_bombing_1944",
            title = "盟军轰炸与解放前夜",
            fixed_date = { year = 1944, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "✈️",
            desc = "盟军开始大规模轰炸巴尔干的交通枢纽和工业设施。游击队控制了越来越多的领土。战争的结局已经明朗，但最后的阵痛最为剧烈。",
            options = {
                {
                    text = "将矿区伪装成民用设施",
                    desc = "隐蔽保全矿区，但产能和运输严重受限",
                    effects = {
                        cash = -150,
                        inflation_delta = 0.10,
                        inflation_drift_mod = 0.015,
                        inflation_drift_duration = 4,
                        modifiers = {
                            { target = "mine_output_mult", value = -0.15, duration = 4 },
                            { target = "transport_risk", value = 0.20, duration = 4 },
                        },
                    },
                },
                {
                    text = "主动联络游击队并提供支援",
                    desc = "重金投靠游击队，为战后新秩序押注",
                    effects = {
                        cash = -300,
                        gold = -3,
                        inflation_delta = 0.08,
                        modifiers = {
                            { target = "political_standing", value = 20, duration = 0 },
                            { target = "legitimacy", value = 15, duration = 0 },
                            { target = "public_support", value = 18, duration = 0 },
                        },
                    },
                },
                {
                    text = "转移地下储备，准备战后重建",
                    desc = "囤金转移资产，为战后重建留本钱",
                    effects = {
                        cash = -200,
                        gold = 5,
                        inflation_delta = 0.07,
                        modifiers = {
                            { target = "foreign_assets", value = 1, duration = 0 },
                            { target = "total_assets", value = 400, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1945 Q2 - 新政权建立（终章）
        -- ================================================================
        {
            id = "new_regime_1945",
            title = "新政权建立",
            fixed_date = { year = 1945, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🏛️",
            image = "image/events/war_ends_1945.png",
            desc = "战争结束，铁托领导的新政权接管工业与金融秩序。公开资产面临审查和国有化，但技术、人员和地方信用仍有价值。家族百年经营的最终考验到来。",
            options = {
                {
                    text = "献出部分资产换取保护",
                    desc = "割肉求存换政治庇护，但重税漫长",
                    effects = {
                        cash = -350,
                        inflation_delta = -0.10,
                        inflation_drift_mod = -0.030,
                        inflation_drift_duration = 8,
                        asset_price_mod = -0.20,
                        asset_price_duration = 8,
                        war_state = false,
                        modifiers = {
                            { target = "political_standing", value = 25, duration = 0 },
                            { target = "total_assets", value = -400, duration = 0 },
                            { target = "tax_rate", value = 0.08, duration = 16 },  -- 新政权累进重税（顺从者较轻）
                        },
                    },
                },
                {
                    text = "转为技术官僚路线",
                    desc = "凭技术立身，税负较轻但失去财富",
                    effects = {
                        cash = -120,
                        inflation_delta = -0.06,
                        war_state = false,
                        modifiers = {
                            { target = "tech_bonus", value = 10, duration = 12 },
                            { target = "legitimacy", value = 12, duration = 0 },
                            { target = "tax_rate", value = 0.06, duration = 16 },  -- 技术官僚路线，税负较低
                        },
                    },
                },
                {
                    text = "隐藏资本，等待窗口",
                    desc = "藏起家底暗中积累，但一旦败露万劫不复",
                    effects = {
                        gold = 8,
                        inflation_delta = -0.03,
                        war_state = false,
                        modifiers = {
                            { target = "shadow_income", value = 50, duration = 12 },
                            { target = "corruption_risk", value = 20, duration = 12 },
                            { target = "political_standing", value = -10, duration = 0 },
                            { target = "tax_rate", value = 0.12, duration = 16 },  -- 资本家极高税率
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- ===   第五章  战后余烬 (1946-1955)                           ===
        -- ================================================================

        -- ================================================================
        -- 1946 Q2 - 土地改革与国有化
        -- ================================================================
        {
            id = "land_reform_1946",
            title = "土地改革",
            fixed_date = { year = 1946, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🏗️",
            desc = "新政权推行激进土地改革，大地主庄园被没收分配。矿业暂时例外，但'生产工具归公'的口号已经贴满矿区围墙。你需要在政策夹缝中保住家族产业。",
            options = {
                {
                    text = "主动上缴部分土地，以退为进",
                    desc = "主动让步保住政治生命，但家产缩水",
                    effects = {
                        cash = -200,
                        modifiers = {
                            { target = "political_standing", value = 15, duration = 0 },
                            { target = "total_assets", value = -300, duration = 0 },
                            { target = "public_support", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "聘请法律顾问拖延审查",
                    desc = "法律手段拖延审查，但腐败风险上升",
                    effects = {
                        cash = -100,
                        modifiers = {
                            { target = "corruption_risk", value = 15, duration = 8 },
                            { target = "tech_bonus", value = 5, duration = 0 },
                        },
                    },
                },
                {
                    text = "将资产转入合作社名义",
                    desc = "暗度陈仓保住资产，但合法性存疑",
                    effects = {
                        cash = -50,
                        modifiers = {
                            { target = "shadow_income", value = 40, duration = 8 },
                            { target = "political_standing", value = -5, duration = 0 },
                            { target = "legitimacy", value = -8, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1947 Q1 - 第一个五年计划
        -- ================================================================
        {
            id = "five_year_plan_1947",
            title = "五年计划",
            fixed_date = { year = 1947, quarter = 1 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📋",
            desc = "南斯拉夫仿照苏联模式推出第一个五年计划。重工业、矿产被列为优先发展目标。国家对产量施加硬性指标，但也提供设备和劳动力支持。",
            options = {
                {
                    text = "全力配合，超额完成指标",
                    desc = "全力冲指标赢得政治认可，但工人疲于奔命",
                    effects = {
                        cash = 300,
                        inflation_delta = 0.02,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.20, duration = 8 },
                            { target = "political_standing", value = 20, duration = 0 },
                            { target = "worker_morale", value = -5, duration = 0 },
                        },
                    },
                },
                {
                    text = "谨慎参与，保留技术核心",
                    desc = "稳健参与，技术和产能均有提升",
                    effects = {
                        cash = 100,
                        modifiers = {
                            { target = "tech_bonus", value = 8, duration = 8 },
                            { target = "mine_output_mult", value = 0.08, duration = 8 },
                        },
                    },
                },
                {
                    text = "虚报产量，暗留利润",
                    desc = "虚报数据中饱私囊，利润大但东窗事发必遭清算",
                    effects = {
                        cash = 250,
                        gold = 3,
                        modifiers = {
                            { target = "corruption_risk", value = 30, duration = 12 },
                            { target = "political_standing", value = -10, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1948 Q3 - 铁托-斯大林决裂
        -- ================================================================
        {
            id = "tito_stalin_split_1948",
            title = "铁托决裂",
            fixed_date = { year = 1948, quarter = 3 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "⚡",
            desc = "铁托拒绝服从莫斯科，南斯拉夫被共产国际开除。苏联及东欧盟国实施全面封锁。波黑各地人心惶惶——选错阵营意味着灭顶之灾。",
            options = {
                {
                    text = "公开效忠铁托路线",
                    desc = "坚定站队铁托赢得政治高位，但贸易受封锁冲击",
                    effects = {
                        cash = -150,
                        inflation_delta = 0.08,
                        modifiers = {
                            { target = "political_standing", value = 30, duration = 0 },
                            { target = "trade_income_mult", value = -0.15, duration = 8 },
                            { target = "legitimacy", value = 15, duration = 0 },
                        },
                    },
                },
                {
                    text = "保持沉默，两不得罪",
                    desc = "两不得罪但两边都不待见",
                    effects = {
                        modifiers = {
                            { target = "political_standing", value = -10, duration = 0 },
                            { target = "public_support", value = -5, duration = 0 },
                        },
                    },
                },
                {
                    text = "秘密联络西方买家",
                    desc = "暗通西方开辟新财路，但走的是灰色地带",
                    effects = {
                        cash = 200,
                        modifiers = {
                            { target = "trade_income_mult", value = 0.10, duration = 12 },
                            { target = "corruption_risk", value = 15, duration = 8 },
                            { target = "foreign_assets", value = 1, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1949 Q4 - 西方援助到来
        -- ================================================================
        {
            id = "western_aid_1949",
            title = "西方援助",
            fixed_date = { year = 1949, quarter = 4 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🤝",
            desc = "与苏联决裂后，美英开始向南斯拉夫提供经济和军事援助。波黑地区获得一批工业设备和贷款额度。但附带条件：允许外国顾问进入矿区考察。",
            options = {
                {
                    text = "全面接受援助和顾问",
                    desc = "全面拥抱西方援助，技术飞跃但外国影响力深入",
                    effects = {
                        cash = 400,
                        inflation_delta = -0.02,
                        modifiers = {
                            { target = "tech_bonus", value = 12, duration = 12 },
                            { target = "foreign_influence", value = 15, duration = 0 },
                            { target = "mine_output_mult", value = 0.10, duration = 8 },
                        },
                    },
                },
                {
                    text = "只接受设备，拒绝顾问",
                    desc = "只拿设备不让人进来，务实但收益有限",
                    effects = {
                        cash = 150,
                        modifiers = {
                            { target = "tech_bonus", value = 5, duration = 8 },
                            { target = "political_standing", value = 5, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1951 Q1 - 朝鲜战争原材料热潮
        -- ================================================================
        {
            id = "korean_war_boom_1951",
            title = "矿产热潮",
            fixed_date = { year = 1951, quarter = 1 },
            priority = EventsData.PRIORITY.REGION,
            icon = "📈",
            desc = "朝鲜战争爆发，全球原材料价格暴涨。波黑的铅、锌、煤炭需求猛增，矿区日夜不停运转。这是战后最好的赚钱窗口，但工人体力和设备都在透支。",
            options = {
                {
                    text = "全力扩产，抓住风口",
                    desc = "拼命扩产赚暴利，但工人和设备都在透支",
                    effects = {
                        cash = 500,
                        gold = 5,
                        inflation_delta = 0.03,
                        asset_price_mod = 0.15,
                        asset_price_duration = 6,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.25, duration = 6 },
                            { target = "worker_morale", value = -10, duration = 0 },
                            { target = "equipment_wear", value = 20, duration = 8 },
                        },
                    },
                },
                {
                    text = "稳健经营，适度增产",
                    desc = "稳健增产，赚钱的同时照顾工人",
                    effects = {
                        cash = 250,
                        gold = 2,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.10, duration = 6 },
                            { target = "worker_morale", value = 5, duration = 0 },
                        },
                    },
                },
                {
                    text = "囤积原矿待价而沽",
                    desc = "囤矿待涨赚黄金，但手段不够透明",
                    effects = {
                        gold = 8,
                        modifiers = {
                            { target = "total_assets", value = 300, duration = 0 },
                            { target = "corruption_risk", value = 10, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1952 Q3 - 工人自治制度
        -- ================================================================
        {
            id = "self_management_1952",
            title = "工人自治",
            fixed_date = { year = 1952, quarter = 3 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🏭",
            desc = "铁托推行独特的'工人自治'制度——企业由工人委员会管理，而非国家官僚。矿区也必须成立工人委员会。这既是机遇也是挑战：处理得当可以赢得人心，否则将失去实际控制权。",
            options = {
                {
                    text = "真心推行自治，让工人参与决策",
                    desc = "真心放权赢得全面支持，长远受益",
                    effects = {
                        cash = -80,
                        modifiers = {
                            { target = "worker_morale", value = 25, duration = 0 },
                            { target = "mine_output_mult", value = 0.08, duration = 12 },
                            { target = "public_support", value = 15, duration = 0 },
                            { target = "legitimacy", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "形式上成立委员会，实际保留决策权",
                    desc = "走过场应付了事，但工人看在眼里",
                    effects = {
                        modifiers = {
                            { target = "worker_morale", value = -5, duration = 0 },
                            { target = "political_standing", value = 5, duration = 0 },
                            { target = "corruption_risk", value = 10, duration = 8 },
                        },
                    },
                },
                {
                    text = "利用委员会安插亲信",
                    desc = "借制度之名行揽权之实，腐败风险极高",
                    effects = {
                        modifiers = {
                            { target = "total_influence", value = 15, duration = 0 },
                            { target = "corruption_risk", value = 25, duration = 12 },
                            { target = "political_standing", value = -5, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1954 Q1 - 的里雅斯特危机解决
        -- ================================================================
        {
            id = "trieste_resolution_1954",
            title = "的里雅斯特和约",
            fixed_date = { year = 1954, quarter = 1 },
            priority = EventsData.PRIORITY.REGION,
            icon = "🕊️",
            desc = "经过多年谈判，南意之间的的里雅斯特领土争端终于解决。亚得里亚海贸易通道重新开放，波黑矿产品获得了通往地中海的出口渠道。",
            options = {
                {
                    text = "投资亚得里亚贸易线",
                    desc = "投资海上贸易线，打开地中海市场",
                    effects = {
                        cash = -200,
                        modifiers = {
                            { target = "trade_income_mult", value = 0.20, duration = 0 },
                            { target = "foreign_assets", value = 1, duration = 0 },
                            { target = "total_assets", value = 200, duration = 0 },
                        },
                    },
                },
                {
                    text = "建立走私渠道",
                    desc = "走私暴利诱人，但腐败代价极其沉重",
                    effects = {
                        cash = 350,
                        gold = 5,
                        modifiers = {
                            { target = "shadow_income", value = 60, duration = 8 },
                            { target = "corruption_risk", value = 35, duration = 12 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1955 Q3 - 百年终章：家族命运
        -- ================================================================
        {
            id = "family_legacy_1955",
            title = "百年传承",
            fixed_date = { year = 1955, quarter = 3 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "👑",
            desc = "从1904年的第一块矿权，到1955年的社会主义南斯拉夫——半个世纪的风雨已经过去。老矿区的烟囱依然在冒烟，但世界早已不是当年的模样。是时候为家族的下一个篇章定下基调了。",
            options = {
                {
                    text = "扎根波黑，成为地方柱石",
                    desc = "扎根本地成为社区柱石，政治和民心全面丰收",
                    effects = {
                        modifiers = {
                            { target = "political_standing", value = 30, duration = 0 },
                            { target = "public_support", value = 20, duration = 0 },
                            { target = "legitimacy", value = 25, duration = 0 },
                            { target = "total_influence", value = 20, duration = 0 },
                        },
                    },
                },
                {
                    text = "布局海外，分散家族资产",
                    desc = "海外分散布局，为家族留退路",
                    effects = {
                        cash = -300,
                        gold = 10,
                        modifiers = {
                            { target = "foreign_assets", value = 3, duration = 0 },
                            { target = "total_assets", value = 500, duration = 0 },
                        },
                    },
                },
                {
                    text = "功成身退，家族隐于幕后",
                    desc = "功成身退隐于幕后，暗中积累但退出政坛",
                    effects = {
                        gold = 15,
                        modifiers = {
                            { target = "shadow_income", value = 80, duration = 0 },
                            { target = "political_standing", value = -20, duration = 0 },
                            { target = "total_assets", value = 300, duration = 0 },
                        },
                    },
                },
            },
        },
    }
end

--- 获取随机事件模板（按条件触发）
---@return table
function EventsData.GetRandomEventTemplates()
    return {
        -- ================================================================
        -- 矿难事故
        -- ================================================================
        {
            id = "mine_accident",
            title = "矿难事故",
            priority = EventsData.PRIORITY.REGION,
            icon = "⚠️",
            trigger = {
                requires_mine = true,
                max_security = 3,
                cooldown = 4,
            },
            chance = 0.20,
            desc = "矿井深处发生塌方事故，多名矿工被困。救援行动刻不容缓，但也需要大量资金。",
            options = {
                {
                    text = "全力救援，不惜代价",
                    desc = "不惜代价救人，赢得人心但停产损失大",
                    effects = {
                        cash = -150,
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "worker_morale", value = 15, duration = 0 },
                            { target = "public_support", value = 5, duration = 0 },
                            { target = "mine_output_mult", value = -0.10, duration = 2 },
                        },
                    },
                },
                {
                    text = "最低限度救援",
                    desc = "省了钱但寒了人心",
                    effects = {
                        cash = -30,
                        modifiers = {
                            { target = "worker_morale", value = -20, duration = 0 },
                            { target = "public_support", value = -10, duration = 0 },
                            { target = "mine_output_mult", value = -0.08, duration = 1 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 工人罢工
        -- ================================================================
        {
            id = "worker_strike",
            title = "工人罢工",
            priority = EventsData.PRIORITY.REGION,
            icon = "✊",
            trigger = {
                min_workers = 15,
                cooldown = 5,
            },
            chance = 0.20,
            desc = "矿工们要求提高工资和改善工作条件。如果不妥善处理，生产将陷入停滞。",
            options = {
                {
                    text = "答应加薪要求",
                    desc = "满足加薪要求，工人满意但成本永久上升",
                    effects = {
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "worker_wage", value = 2, duration = 0 },
                            { target = "worker_morale", value = 20, duration = 0 },
                        },
                    },
                },
                {
                    text = "谈判妥协，部分满足",
                    desc = "折中妥协，小幅加薪平息事态",
                    effects = {
                        cash = -50,
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "worker_wage", value = 1, duration = 0 },
                            { target = "worker_morale", value = 5, duration = 0 },
                        },
                    },
                },
                {
                    text = "强硬镇压，雇佣替工",
                    desc = "铁腕镇压，省钱但后患无穷",
                    effects = {
                        modifiers = {
                            { target = "worker_morale", value = -30, duration = 0 },
                            { target = "public_support", value = -15, duration = 0 },
                            { target = "security", value = -1, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 外资考察团
        -- ================================================================
        {
            id = "foreign_investors",
            title = "外资考察团",
            priority = EventsData.PRIORITY.REGION,
            icon = "🤝",
            trigger = {
                min_year = 1906,
                max_year = 1940,
                min_development = 2,
                cooldown = 6,
            },
            chance = 0.18,
            desc = "一支外国投资考察团对你的矿业经营产生了兴趣。他们愿意提供资金，但要求分享利润和决策权。",
            options = {
                {
                    text = "接受投资，让出部分股权",
                    desc = "大笔资金涌入，产能飙升，但从此受制于人",
                    effects = {
                        cash = 600,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "foreign_control", value = 20, duration = 0 },
                            { target = "mine_output_mult", value = 0.10, duration = 0 },
                        },
                    },
                },
                {
                    text = "仅接受技术合作",
                    desc = "只引进技术不让渡股权，收益有限但保住自主",
                    effects = {
                        cash = 100,
                        modifiers = {
                            { target = "tech_bonus", value = 5, duration = 8 },
                        },
                    },
                },
                {
                    text = "婉拒，保持独立经营",
                    desc = "拒绝外资，独立性更强但错失发展机遇",
                    effects = {
                        modifiers = {
                            { target = "independence", value = 10, duration = 0 },
                        },
                    },
                },
            },
            bonus_ap = 1,
        },

        -- ================================================================
        -- 矿脉发现
        -- ================================================================
        {
            id = "ore_vein_discovery",
            title = "新矿脉发现",
            priority = EventsData.PRIORITY.REGION,
            icon = "💎",
            trigger = {
                requires_mine = true,
                min_year = 1905,
                cooldown = 5,
            },
            chance = 0.14,
            desc = "矿工们在深处发现了一条富含金银的新矿脉。这可能让产量大幅提升，但开发需要额外投入。",
            options = {
                {
                    text = "立即开发新矿脉",
                    desc = "大手笔投入开发，短期产能暴增",
                    effects = {
                        cash = -250,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.20, duration = 4 },
                        },
                    },
                },
                {
                    text = "谨慎勘探，稳步推进",
                    desc = "小成本稳健勘探，收获黄金和长期产能提升",
                    effects = {
                        cash = -80,
                        gold = 3,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.08, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 地方势力施压
        -- ================================================================
        {
            id = "local_pressure",
            title = "地方势力施压",
            priority = EventsData.PRIORITY.REGION,
            icon = "🏛️",
            trigger = {
                min_year = 1906,
                cooldown = 5,
            },
            chance = 0.18,
            desc = "当地传统势力对你的崛起感到不安，他们通过各种渠道向你施加压力，要求分享利益或限制扩张。",
            options = {
                {
                    text = "缴纳保护费，息事宁人",
                    desc = "花钱消灾，地方关系改善但开了口子",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.005,
                        modifiers = {
                            { target = "local_relations", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "针锋相对，强硬回击",
                    desc = "正面硬刚，治安恶化且彻底得罪地方",
                    effects = {
                        cash = -50,
                        security_bonus = -1,
                        modifiers = {
                            { target = "local_relations", value = -20, duration = 0 },
                        },
                    },
                },
                {
                    text = "寻找高层靠山对抗",
                    desc = "另辟蹊径找靠山，花钱提升政治地位",
                    effects = {
                        cash = -100,
                        modifiers = {
                            { target = "legitimacy", value = 5, duration = 0 },
                            { target = "political_standing", value = 5, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 金价异动
        -- ================================================================
        {
            id = "gold_price_surge",
            title = "金价异动",
            priority = EventsData.PRIORITY.MINOR,
            icon = "📊",
            trigger = {
                min_year = 1905,
                cooldown = 4,
            },
            chance = 0.16,
            desc = "国际市场传来消息，黄金价格出现剧烈波动。此刻出手可能大赚，但也可能买在高点。",
            options = {
                {
                    text = "趁高价抛售库存黄金",
                    desc = "高位抛售黄金套现，但会压低后续金价",
                    effects = {
                        gold = -5,
                        cash = 400,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "gold_price_mod", value = -0.10, duration = 2 },
                        },
                    },
                },
                {
                    text = "逢低吸纳，增加储备",
                    desc = "趁低价囤积黄金，押注金价继续上涨",
                    effects = {
                        cash = -200,
                        gold = 6,
                        modifiers = {
                            { target = "gold_price_mod", value = 0.08, duration = 3 },
                        },
                    },
                },
                {
                    text = "按兵不动",
                    desc = "观望不动，不赚不亏",
                    effects = {},
                },
            },
        },

        -- ================================================================
        -- 走私通道（战时专属）
        -- ================================================================
        {
            id = "smuggling_route",
            title = "走私通道",
            priority = EventsData.PRIORITY.REGION,
            icon = "🌙",
            trigger = {
                min_year = 1914,
                requires_war = true,
                cooldown = 4,
            },
            chance = 0.22,
            desc = "战时管控催生了利润丰厚的走私网络。有人提出利用矿区的偏远位置作为转运站。",
            options = {
                {
                    text = "参与走私，赚取暴利",
                    desc = "暴利诱人但风险极高，腐败和运输隐患随之而来",
                    effects = {
                        cash = 400,
                        inflation_delta = 0.02,
                        modifiers = {
                            { target = "shadow_income", value = 60, duration = 4 },
                            { target = "corruption_risk", value = 15, duration = 6 },
                            { target = "transport_risk", value = 0.12, duration = 4 },
                        },
                    },
                },
                {
                    text = "向当局举报换取奖赏",
                    desc = "举报换来官方认可，但得罪了地方势力",
                    effects = {
                        cash = 120,
                        modifiers = {
                            { target = "legitimacy", value = 10, duration = 0 },
                            { target = "local_relations", value = -10, duration = 0 },
                        },
                    },
                },
                {
                    text = "装作不知道",
                    desc = "明哲保身，不沾是非",
                    effects = {},
                },
            },
        },

        -- ================================================================
        -- 瘟疫/疾病爆发
        -- ================================================================
        {
            id = "disease_outbreak",
            title = "矿区疫病",
            priority = EventsData.PRIORITY.REGION,
            icon = "🦠",
            trigger = {
                requires_mine = true,
                max_security = 4,
                cooldown = 6,
            },
            chance = 0.15,
            desc = "矿区爆发传染病，工人大面积感染。产量骤降，如果不控制还会蔓延到周边社区。",
            options = {
                {
                    text = "紧急请医生并隔离治疗",
                    desc = "花大价钱救人，赢得人心但短期停产严重",
                    effects = {
                        cash = -250,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "worker_morale", value = 10, duration = 0 },
                            { target = "public_support", value = 8, duration = 0 },
                            { target = "mine_output_mult", value = -0.12, duration = 2 },
                        },
                    },
                },
                {
                    text = "继续生产，忽视疫情",
                    desc = "漠视生命，工人死伤惨重，人心尽失",
                    effects = {
                        workers_bonus = -5,
                        modifiers = {
                            { target = "worker_morale", value = -25, duration = 0 },
                            { target = "public_support", value = -15, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 技术人才流失
        -- ================================================================
        {
            id = "brain_drain",
            title = "技术人才流失",
            priority = EventsData.PRIORITY.MINOR,
            icon = "🧠",
            trigger = {
                min_year = 1918,
                cooldown = 5,
            },
            chance = 0.16,
            desc = "战后移民潮中，几位经验丰富的矿业工程师计划前往美国或阿根廷。留住他们需要开出高薪。",
            options = {
                {
                    text = "高薪挽留核心技术人员",
                    desc = "高薪留人，技术和产能双升但工资成本永久增加",
                    effects = {
                        cash = -180,
                        modifiers = {
                            { target = "tech_bonus", value = 6, duration = 6 },
                            { target = "mine_output_mult", value = 0.06, duration = 0 },
                            { target = "worker_cost_multiplier", value = 0.05, duration = 0 },
                        },
                    },
                },
                {
                    text = "让他们走，培养本地新人",
                    desc = "短痛换长远，本地人才慢慢成长",
                    effects = {
                        modifiers = {
                            { target = "mine_output_mult", value = -0.08, duration = 3 },
                            { target = "tech_bonus", value = 3, duration = 8 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 自然灾害
        -- ================================================================
        {
            id = "natural_disaster",
            title = "山洪暴发",
            priority = EventsData.PRIORITY.REGION,
            icon = "🌊",
            trigger = {
                requires_mine = true,
                cooldown = 6,
            },
            chance = 0.12,
            desc = "暴雨引发山洪，冲毁了部分矿区道路和设施。运输中断，需要紧急修复。",
            options = {
                {
                    text = "全面修复并加固设施",
                    desc = "大修加固一劳永逸，但花费不菲且短期停产",
                    effects = {
                        cash = -300,
                        modifiers = {
                            { target = "transport_risk", value = -0.10, duration = 0 },
                            { target = "mine_output_mult", value = -0.10, duration = 2 },
                            { target = "public_support", value = 5, duration = 0 },
                        },
                    },
                },
                {
                    text = "临时修补道路",
                    desc = "省钱应急，但运输隐患留了下来",
                    effects = {
                        cash = -80,
                        modifiers = {
                            { target = "transport_risk", value = 0.05, duration = 4 },
                            { target = "mine_output_mult", value = -0.05, duration = 1 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 国际矿石需求波动
        -- ================================================================
        {
            id = "commodity_boom",
            title = "矿石需求暴增",
            priority = EventsData.PRIORITY.MINOR,
            icon = "📈",
            trigger = {
                min_year = 1910,
                cooldown = 5,
            },
            chance = 0.15,
            desc = "国际市场上某种矿石需求暴增，价格飙涨。这是扩大生产的好机会，但过度扩张也可能后劲不足。",
            options = {
                {
                    text = "全力增产满足需求",
                    desc = "全速开工抢市场，赚得多但工人吃不消",
                    effects = {
                        cash = 350,
                        inflation_delta = 0.01,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.15, duration = 3 },
                            { target = "worker_morale", value = -6, duration = 0 },
                            { target = "coal_price_mod", value = 0.15, duration = 3 },
                        },
                    },
                },
                {
                    text = "适度增产，保留余力",
                    desc = "稳扎稳打适度增产，收益适中无负面影响",
                    effects = {
                        cash = 180,
                        modifiers = {
                            { target = "mine_output_mult", value = 0.08, duration = 3 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 汇率危机
        -- ================================================================
        {
            id = "currency_crisis",
            title = "汇率危机",
            priority = EventsData.PRIORITY.REGION,
            icon = "💱",
            trigger = {
                min_year = 1920,
                cooldown = 5,
            },
            chance = 0.16,
            desc = "本国货币对外大幅贬值，进口物价飙升。持有外汇的人一夜暴富，而依赖进口设备的企业叫苦连天。",
            options = {
                {
                    text = "趁机用外汇收购本地资产",
                    desc = "危中求机抄底资产，回报丰厚但通胀飙升",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.03,
                        inflation_drift_mod = 0.004,
                        inflation_drift_duration = 4,
                        modifiers = {
                            { target = "total_assets", value = 350, duration = 0 },
                            { target = "gold_price_mod", value = 0.15, duration = 4 },
                        },
                    },
                },
                {
                    text = "将收入转为黄金储备",
                    desc = "换成黄金保值，但通胀照样吃掉一部分",
                    effects = {
                        cash = -150,
                        gold = 5,
                        inflation_delta = 0.025,
                        inflation_drift_mod = 0.003,
                        inflation_drift_duration = 3,
                    },
                },
                {
                    text = "维持现状，等待汇率回稳",
                    desc = "什么也不做，坐等通胀侵蚀财富",
                    effects = {
                        inflation_delta = 0.02,
                    },
                },
            },
        },

        -- ================================================================
        -- 间谍风波
        -- ================================================================
        {
            id = "espionage_scandal",
            title = "间谍风波",
            priority = EventsData.PRIORITY.MINOR,
            icon = "🕵️",
            trigger = {
                min_year = 1935,
                cooldown = 6,
            },
            chance = 0.14,
            desc = "有消息称外国间谍对矿区的产量和储备数据感兴趣。当局加强了对矿业企业的审查。",
            options = {
                {
                    text = "全面配合调查",
                    desc = "配合调查赢得信任，但生产受到干扰",
                    effects = {
                        cash = -60,
                        modifiers = {
                            { target = "legitimacy", value = 8, duration = 0 },
                            { target = "mine_output_mult", value = -0.05, duration = 2 },
                        },
                    },
                },
                {
                    text = "利用调查打击竞争对手",
                    desc = "借刀杀人提升政治地位，但沾上腐败污点",
                    effects = {
                        cash = -100,
                        modifiers = {
                            { target = "corruption_risk", value = 10, duration = 6 },
                            { target = "political_standing", value = 5, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 旱灾粮荒
        -- ================================================================
        {
            id = "drought_famine",
            title = "旱灾粮荒",
            priority = EventsData.PRIORITY.REGION,
            icon = "☀️",
            trigger = {
                min_year = 1908,
                cooldown = 6,
            },
            chance = 0.13,
            desc = "持续干旱导致粮食歉收，矿区工人的口粮供应出现短缺。物价飞涨，工人要求补贴。",
            options = {
                {
                    text = "购买粮食发放给工人",
                    desc = "自掏腰包济民，人心大振但物价更高了",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.02,
                        inflation_drift_mod = 0.003,
                        inflation_drift_duration = 3,
                        modifiers = {
                            { target = "worker_morale", value = 12, duration = 0 },
                            { target = "public_support", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "削减口粮标准",
                    desc = "省了粮食钱，但工人饿着肚子干活效率骤降",
                    effects = {
                        inflation_delta = 0.025,
                        inflation_drift_mod = 0.004,
                        inflation_drift_duration = 3,
                        modifiers = {
                            { target = "worker_morale", value = -15, duration = 0 },
                            { target = "mine_output_mult", value = -0.08, duration = 3 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 劫匪劫道
        -- ================================================================
        {
            id = "bandit_raid",
            title = "劫匪劫道",
            priority = EventsData.PRIORITY.REGION,
            icon = "🏴‍☠️",
            trigger = {
                requires_mine = true,
                min_year = 1905,
                cooldown = 4,
            },
            chance = 0.08,
            chance_modifier = "transport_risk", -- 运输风险越高越容易触发
            desc = "一伙武装劫匪袭击了从矿区出发的运输队，押运人员被打散，部分货物被劫走。治安堪忧。",
            options = {
                {
                    text = "出钱赎回货物并加强护送",
                    desc = "花钱止损并降低后续运输风险，但开销不小",
                    effects = {
                        cash = -150,
                        modifiers = {
                            { target = "transport_risk", value = -0.08, duration = 4 },
                        },
                    },
                },
                {
                    text = "组织武装追击",
                    desc = "动用武装追剿匪帮，消耗兵力但有望夺回货物",
                    effects = {
                        gold = -2,
                        security_bonus = 1,
                        modifiers = {
                            { target = "transport_risk", value = -0.05, duration = 6 },
                        },
                    },
                },
                {
                    text = "认栽吃亏，吸取教训",
                    desc = "损失已成定局，运输隐患依然存在",
                    effects = {
                        gold = -3,
                        modifiers = {
                            { target = "worker_morale", value = -5, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 铁路瘫痪
        -- ================================================================
        {
            id = "railway_shutdown",
            title = "铁路瘫痪",
            priority = EventsData.PRIORITY.REGION,
            icon = "🚂",
            trigger = {
                requires_mine = true,
                min_year = 1910,
                cooldown = 6,
            },
            chance = 0.06,
            chance_modifier = "transport_risk", -- 运输风险越高越容易触发
            desc = "铁路干线发生严重事故——桥梁垮塌、路基损毁，短期内无法修复。矿区出产的黄金堆在仓库里运不出去，本季度无法出售。",
            options = {
                {
                    text = "紧急抢修，尽快恢复通车",
                    desc = "花大价钱加急修复，下季度恢复销售，运输风险略降",
                    effects = {
                        cash = -300,
                        modifiers = {
                            { target = "railway_blocked", value = 1, duration = 1 },
                            { target = "transport_risk", value = -0.05, duration = 0 },
                        },
                    },
                },
                {
                    text = "等待官方修复，节省开支",
                    desc = "省了修路钱，但黄金积压更久且运输风险上升",
                    effects = {
                        modifiers = {
                            { target = "railway_blocked", value = 1, duration = 2 },
                            { target = "transport_risk", value = 0.08, duration = 3 },
                        },
                    },
                },
            },
        },
    }
end

return EventsData
