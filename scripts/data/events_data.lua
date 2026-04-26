-- ============================================================================
-- 事件数据：固定历史事件 + 随机事件模板
-- MVP 范围：1904-1918，共 8 个事件（5 固定 + 3 随机模板）
-- ============================================================================

local EventsData = {}

--- 事件优先级
EventsData.PRIORITY = {
    MAIN   = "main",    -- 主线大事件，全屏弹窗
    REGION = "region",  -- 地区事件，中型弹窗
    MINOR  = "minor",   -- 小事件，Toast 或小卡片
}

--- 获取全部固定历史事件
---@return table[]
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
            desc = "经过多年在 Bakovići 矿区的辛苦劳作，你终于攒够了积蓄，从一位年迈的塞尔维亚矿主手中买下了第一块矿权。三百克朗的投入，承载着整个家族的命运。",
            options = {
                {
                    text = "稳扎稳打，小规模开采",
                    desc = "控制风险，积累经验",
                    effects = {
                        cash = -100,
                        gold = 2,
                        modifiers = {
                            { target = "mine_output", value = 0, duration = 0 },
                        },
                    },
                },
                {
                    text = "大胆投入，扩大开采规模",
                    desc = "高风险高回报",
                    effects = {
                        cash = -300,
                        gold = 0,
                        workers_bonus = 5,
                        modifiers = {
                            { target = "mine_output", value = 1, duration = 4 },
                        },
                    },
                },
                {
                    text = "拉拢当地势力，合资开发",
                    desc = "分享利润换取保护",
                    effects = {
                        cash = -50,
                        gold = 1,
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
                    desc = "提高运输效率，短期资金承压",
                    effects = {
                        cash = -180,
                        asset_price_mod = 0.04,
                        asset_price_duration = 6,
                        modifiers = {
                            { target = "mine_output", value = 1, duration = 6 },
                            { target = "transport_risk", value = -0.08, duration = 8 },
                        },
                    },
                },
                {
                    text = "与铁路公司签订长期运价",
                    desc = "稳定现金流，但受外资牵制",
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
                    desc = "保守独立，错过扩张窗口",
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
                    desc = "花费较高，减少劳资冲突",
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
                    desc = "控制成本，士气小幅提升",
                    effects = {
                        cash = -80,
                        modifiers = {
                            { target = "worker_morale", value = 6, duration = 0 },
                        },
                    },
                },
                {
                    text = "把宿舍包给地方承包人",
                    desc = "省钱但埋下治安隐患",
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
        -- 1908 Q4 - 帝国管制加强
        -- ================================================================
        {
            id = "imperial_control_1908",
            title = "帝国管制令",
            fixed_date = { year = 1908, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📜",
            desc = "奥匈帝国正式吞并波黑，维也纳加强了对地方经济的管控。税收大幅上升，所有矿业许可证需要重新审核。",
            options = {
                {
                    text = "依法缴税，申请合法许可",
                    desc = "安全但代价不小",
                    effects = {
                        cash = -200,
                        modifiers = {
                            { target = "tax_rate", value = 0.05, duration = 0 },
                            { target = "legitimacy", value = 20, duration = 0 },
                        },
                        inflation_delta = 0.01,
                    },
                },
                {
                    text = "行贿地方官员，减免税负",
                    desc = "走捷径",
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
                    desc = "风险极高但利润丰厚",
                    effects = {
                        cash = 50,
                        modifiers = {
                            { target = "security", value = -1, duration = 4 },
                            { target = "shadow_income", value = 30, duration = 4 },
                        },
                        inflation_drift_mod = 0.002,
                        inflation_drift_duration = 4,
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
                    desc = "保守但安全",
                    effects = {
                        cash = -80,
                        inflation_delta = 0.015,
                        modifiers = {
                            { target = "supply_reserve", value = 20, duration = 0 },
                            { target = "transport_risk", value = -0.05, duration = 4 },
                            { target = "gold_price_mod", value = 0.15, duration = 4 },   -- 战争避险推高金价
                            { target = "coal_price_mod", value = 0.25, duration = 4 },   -- 军工耗煤大涨
                        },
                    },
                },
                {
                    text = "向军方供应矿产",
                    desc = "短期获利，建立军方关系",
                    effects = {
                        cash = 200,
                        gold = -3,
                        asset_price_mod = 0.06,
                        asset_price_duration = 4,
                        modifiers = {
                            { target = "military_relation", value = 15, duration = 0 },
                            { target = "military_industry_profit", value = 0.15, duration = 4 },
                            { target = "gold_price_mod", value = 0.10, duration = 4 },
                            { target = "silver_price_mod", value = 0.08, duration = 4 },
                            { target = "coal_price_mod", value = 0.30, duration = 4 },
                        },
                    },
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
            desc = "战争正式吞没帝国边陲。铁路优先运输军队，矿山被要求保障军需，粮食、煤炭和工资同时上涨。",
            options = {
                {
                    text = "接受军方订单",
                    desc = "军需利润提高，民用市场受挤压",
                    effects = {
                        cash = 260,
                        inflation_delta = 0.04,
                        inflation_drift_mod = 0.006,
                        inflation_drift_duration = 8,
                        asset_price_mod = 0.10,
                        asset_price_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "military_industry_profit", value = 0.25, duration = 8 },
                            { target = "civilian_consumption", value = -0.12, duration = 8 },
                            { target = "worker_cost_multiplier", value = 0.08, duration = 8 },
                            { target = "gold_price_mod", value = 0.20, duration = 8 },
                            { target = "coal_price_mod", value = 0.45, duration = 8 },   -- 战时煤炭紧缺
                        },
                    },
                },
                {
                    text = "优先保障矿工家庭",
                    desc = "利润较低，但稳住士气和民心",
                    effects = {
                        cash = -120,
                        inflation_delta = 0.025,
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
                    desc = "保留硬通货，承担走私风险",
                    effects = {
                        gold = 6,
                        inflation_delta = 0.03,
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
                    desc = "成本上升，降低罢工风险",
                    effects = {
                        cash = -240,
                        inflation_delta = 0.05,
                        modifiers = {
                            { target = "worker_wage", value = 1, duration = 0 },
                            { target = "worker_morale", value = 18, duration = 0 },
                            { target = "public_support", value = 8, duration = 0 },
                            { target = "gold_price_mod", value = 0.25, duration = 6 },   -- 避险金价
                            { target = "coal_price_mod", value = 0.60, duration = 6 },   -- 煤炭极度短缺
                            { target = "silver_price_mod", value = 0.12, duration = 4 },
                        },
                    },
                },
                {
                    text = "削减民用供给保军需",
                    desc = "短期现金流好，民心和治安恶化",
                    effects = {
                        cash = 360,
                        inflation_delta = 0.06,
                        asset_price_mod = 0.08,
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
                    desc = "高收益高风险",
                    effects = {
                        cash = 120,
                        gold = -2,
                        inflation_drift_mod = 0.005,
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
        -- 1914 Q2 - 萨拉热窝枪声（核心主线事件）
        -- ================================================================
        {
            id = "sarajevo_shots_1914",
            title = "萨拉热窝枪声",
            fixed_date = { year = 1914, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "💥",
            desc = "1914年6月28日，一声枪响震动了整个地区。大公遇刺，战争阴云迅速笼罩巴尔干。市场恐慌，军需价格飙升，一切都将改变。",
            options = {
                {
                    text = "囤积黄金并暂停扩张",
                    desc = "保守策略，保全资产",
                    effects = {
                        gold = 10,
                        inflation_delta = 0.03,
                        asset_price_mod = 0.08,
                        asset_price_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "expansion_freeze", value = 1, duration = 4 },
                            { target = "risk", value = -10, duration = 0 },
                            { target = "gold_price_mod", value = 0.30, duration = 8 },   -- 战争恐慌金价飙升
                            { target = "silver_price_mod", value = 0.10, duration = 6 },
                            { target = "coal_price_mod", value = 0.40, duration = 8 },   -- 军工煤需猛增
                        },
                    },
                },
                {
                    text = "转向军需供应",
                    desc = "战争财富，但声誉有损",
                    effects = {
                        cash = 500,
                        inflation_delta = 0.05,
                        inflation_drift_mod = 0.008,
                        inflation_drift_duration = 12,
                        asset_price_mod = 0.12,
                        asset_price_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "military_relation", value = 15, duration = 0 },
                            { target = "public_support", value = -5, duration = 0 },
                            { target = "military_industry_profit", value = 0.40, duration = 16 },
                            { target = "gold_price_mod", value = 0.25, duration = 12 },
                            { target = "silver_price_mod", value = 0.15, duration = 8 },
                            { target = "coal_price_mod", value = 0.50, duration = 12 },  -- 军需大量耗煤
                        },
                    },
                },
                {
                    text = "向外转移部分资产",
                    desc = "分散风险",
                    effects = {
                        cash = -200,
                        inflation_delta = 0.02,
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
                    desc = "趁乱扩张",
                    effects = {
                        cash = -300,
                        inflation_delta = 0.03,
                        inflation_drift_mod = -0.010,
                        inflation_drift_duration = 6,
                        asset_price_mod = -0.15,
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
                    desc = "政治安全优先",
                    effects = {
                        cash = -100,
                        inflation_delta = -0.01,
                        inflation_drift_mod = -0.012,
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
                    desc = "赢得民心",
                    effects = {
                        cash = -200,
                        inflation_delta = -0.005,
                        inflation_drift_mod = -0.008,
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
        -- 1929 Q4 - 大萧条波及
        -- ================================================================
        {
            id = "great_depression_1929",
            title = "大萧条波及",
            fixed_date = { year = 1929, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📉",
            desc = "纽约股灾的冲击沿着银行和贸易网络传到巴尔干。信贷收缩、订单减少，现金比账面资产更重要。",
            options = {
                {
                    text = "收缩债务，保留现金",
                    desc = "放慢扩张，降低金融风险",
                    effects = {
                        cash = -250,
                        inflation_delta = -0.03,
                        asset_price_mod = -0.20,
                        asset_price_duration = 8,
                        modifiers = {
                            { target = "risk", value = -12, duration = 8 },
                            { target = "civilian_consumption", value = -0.15, duration = 8 },
                            { target = "gold_price_mod", value = 0.35, duration = 8 },    -- 避险金价飙升
                            { target = "silver_price_mod", value = -0.20, duration = 6 }, -- 工业需求萎缩
                            { target = "coal_price_mod", value = -0.25, duration = 8 },   -- 经济冷却煤价暴跌
                        },
                    },
                },
                {
                    text = "抄底廉价资产",
                    desc = "承担短期压力换长期资产",
                    effects = {
                        cash = -500,
                        asset_price_mod = -0.30,
                        asset_price_duration = 4,
                        modifiers = {
                            { target = "total_assets", value = 900, duration = 0 },
                            { target = "foreign_control", value = -6, duration = 0 },
                        },
                    },
                },
                {
                    text = "裁员并停掉亏损业务",
                    desc = "现金回血，但劳工关系恶化",
                    effects = {
                        cash = 260,
                        modifiers = {
                            { target = "worker_morale", value = -18, duration = 0 },
                            { target = "public_support", value = -10, duration = 0 },
                            { target = "mine_output", value = -1, duration = 4 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1941 Q2 - 旧秩序瓦解
        -- ================================================================
        {
            id = "old_order_collapse_1941",
            title = "旧秩序瓦解",
            fixed_date = { year = 1941, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🪖",
            desc = "全面战争再次改变波黑。行政体系碎裂，工厂、铁路和矿山都面临征用，家族必须决定资产优先还是人员优先。",
            options = {
                {
                    text = "迁走核心设备",
                    desc = "保护长期资产，短期产能下降",
                    effects = {
                        cash = -420,
                        inflation_delta = 0.06,
                        inflation_drift_mod = 0.010,
                        inflation_drift_duration = 10,
                        asset_price_mod = 0.12,
                        asset_price_duration = 8,
                        war_state = true,
                        modifiers = {
                            { target = "mine_output", value = -1, duration = 6 },
                            { target = "total_assets", value = 700, duration = 0 },
                            { target = "gold_price_mod", value = 0.35, duration = 10 },  -- 战争避险
                            { target = "coal_price_mod", value = 0.55, duration = 10 },  -- 军工耗煤
                            { target = "silver_price_mod", value = 0.10, duration = 6 },
                        },
                    },
                },
                {
                    text = "与占领当局合作保产",
                    desc = "现金流稳定，声誉风险很高",
                    effects = {
                        cash = 600,
                        inflation_delta = 0.08,
                        war_state = true,
                        modifiers = {
                            { target = "military_industry_profit", value = 0.30, duration = 10 },
                            { target = "legitimacy", value = -25, duration = 0 },
                            { target = "public_support", value = -20, duration = 0 },
                        },
                    },
                },
                {
                    text = "建立地下供应网",
                    desc = "转入灰色经营，风险和收益都提高",
                    effects = {
                        gold = -4,
                        inflation_delta = 0.05,
                        war_state = true,
                        modifiers = {
                            { target = "shadow_income", value = 90, duration = 10 },
                            { target = "transport_risk", value = 0.30, duration = 10 },
                            { target = "public_support", value = 10, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1945 Q2 - 新政权建立
        -- ================================================================
        {
            id = "new_regime_1945",
            title = "新政权建立",
            fixed_date = { year = 1945, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🏛️",
            desc = "战争结束，新政权接管工业与金融秩序。公开资产面临审查，但技术、人员和地方信用仍有价值。",
            options = {
                {
                    text = "献出部分资产换取保护",
                    desc = "损失账面财富，保住家族成员",
                    effects = {
                        cash = -350,
                        inflation_delta = -0.04,
                        inflation_drift_mod = -0.012,
                        inflation_drift_duration = 8,
                        asset_price_mod = -0.10,
                        asset_price_duration = 8,
                        war_state = false,
                        modifiers = {
                            { target = "political_standing", value = 25, duration = 0 },
                            { target = "total_assets", value = -400, duration = 0 },
                        },
                    },
                },
                {
                    text = "转为技术官僚路线",
                    desc = "以专业能力保留影响力",
                    effects = {
                        cash = -120,
                        war_state = false,
                        modifiers = {
                            { target = "tech_bonus", value = 10, duration = 12 },
                            { target = "legitimacy", value = 12, duration = 0 },
                        },
                    },
                },
                {
                    text = "隐藏资本，等待窗口",
                    desc = "保留硬资产，长期审查风险上升",
                    effects = {
                        gold = 8,
                        war_state = false,
                        modifiers = {
                            { target = "shadow_income", value = 50, duration = 12 },
                            { target = "corruption_risk", value = 20, duration = 12 },
                            { target = "political_standing", value = -10, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1968 Q2 - 学潮与改革风向
        -- ================================================================
        {
            id = "reform_winds_1968",
            title = "学潮与改革风向",
            fixed_date = { year = 1968, quarter = 2 },
            priority = EventsData.PRIORITY.REGION,
            icon = "📰",
            desc = "大学、工厂和报刊同时出现改革讨论。年轻人要求更多机会，旧体制也在寻找能带来效率的企业家。",
            options = {
                {
                    text = "赞助教育与技术培训",
                    desc = "强化长期研发和公众形象",
                    effects = {
                        cash = -300,
                        modifiers = {
                            { target = "tech_bonus", value = 12, duration = 10 },
                            { target = "culture", value = 18, duration = 0 },
                            { target = "public_support", value = 12, duration = 0 },
                        },
                    },
                },
                {
                    text = "投资报刊和城市文化",
                    desc = "推动文化路线",
                    effects = {
                        cash = -260,
                        modifiers = {
                            { target = "culture", value = 28, duration = 0 },
                            { target = "political_standing", value = 8, duration = 0 },
                        },
                    },
                },
                {
                    text = "保持低调，专注生产",
                    desc = "少惹麻烦，稳住现金流",
                    effects = {
                        cash = 180,
                        modifiers = {
                            { target = "mine_output", value = 1, duration = 6 },
                            { target = "public_support", value = -4, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1984 Q1 - 冬季盛会窗口
        -- ================================================================
        {
            id = "winter_games_1984",
            title = "冬季盛会窗口",
            fixed_date = { year = 1984, quarter = 1 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🏔️",
            desc = "萨拉热窝站上世界舞台。旅游、基建、媒体与城市名望迎来一次罕见的窗口。",
            options = {
                {
                    text = "投资酒店与交通",
                    desc = "旅游收益与资产估值上升",
                    effects = {
                        cash = -500,
                        asset_price_mod = 0.18,
                        asset_price_duration = 8,
                        modifiers = {
                            { target = "total_assets", value = 800, duration = 0 },
                            { target = "civilian_consumption", value = 0.14, duration = 8 },
                        },
                    },
                },
                {
                    text = "打造家族文化品牌",
                    desc = "大幅提升文化影响",
                    effects = {
                        cash = -360,
                        modifiers = {
                            { target = "culture", value = 45, duration = 0 },
                            { target = "public_support", value = 20, duration = 0 },
                        },
                    },
                },
                {
                    text = "承接后勤合同",
                    desc = "短期现金收益",
                    effects = {
                        cash = 520,
                        modifiers = {
                            { target = "political_standing", value = 10, duration = 0 },
                            { target = "transport_risk", value = -0.08, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1992 Q2 - 国家崩裂与战争
        -- ================================================================
        {
            id = "state_fracture_1992",
            title = "国家崩裂与战争",
            fixed_date = { year = 1992, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📻",
            desc = "政治秩序崩裂，城市和山谷被检查站切开。物流中断、物价飞涨，武装和民生都成为生存问题。",
            options = {
                {
                    text = "武装护产",
                    desc = "保护资产，军事压力上升",
                    effects = {
                        cash = -650,
                        inflation_delta = 0.12,
                        inflation_drift_mod = 0.018,
                        inflation_drift_duration = 12,
                        asset_price_mod = 0.22,
                        asset_price_duration = 10,
                        war_state = true,
                        modifiers = {
                            { target = "military_industry_profit", value = 0.35, duration = 12 },
                            { target = "public_support", value = -8, duration = 0 },
                            { target = "gold_price_mod", value = 0.40, duration = 12 },  -- 90年代战争金价飙升
                            { target = "coal_price_mod", value = 0.70, duration = 10 },  -- 围城煤炭极度紧缺
                            { target = "silver_price_mod", value = 0.15, duration = 8 },
                        },
                    },
                },
                {
                    text = "撤出流动资产",
                    desc = "现金与黄金安全，地方影响受损",
                    effects = {
                        cash = -220,
                        gold = 12,
                        inflation_delta = 0.08,
                        war_state = true,
                        modifiers = {
                            { target = "foreign_assets", value = 2, duration = 0 },
                            { target = "local_reputation", value = -18, duration = 0 },
                        },
                    },
                },
                {
                    text = "组织民生救济",
                    desc = "牺牲资金换取民心",
                    effects = {
                        cash = -520,
                        inflation_delta = 0.06,
                        war_state = true,
                        modifiers = {
                            { target = "public_support", value = 35, duration = 0 },
                            { target = "culture", value = 18, duration = 0 },
                            { target = "civilian_consumption", value = 0.10, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1994 Q1 - 市场惨案冲击
        -- ================================================================
        {
            id = "market_tragedy_1994",
            title = "市场惨案冲击",
            fixed_date = { year = 1994, quarter = 1 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🕯️",
            desc = "城市惨案让国际目光重新聚焦萨拉热窝。舆论、援助、制裁和地下交易都在同一季度急剧变化。",
            options = {
                {
                    text = "投入救助和医疗",
                    desc = "提升民心和国际声誉",
                    effects = {
                        cash = -420,
                        inflation_delta = 0.03,
                        modifiers = {
                            { target = "public_support", value = 30, duration = 0 },
                            { target = "culture", value = 20, duration = 0 },
                            { target = "political_standing", value = 12, duration = 0 },
                        },
                    },
                },
                {
                    text = "推动国际宣传",
                    desc = "强化政治影响",
                    effects = {
                        cash = -260,
                        modifiers = {
                            { target = "political_standing", value = 25, duration = 0 },
                            { target = "culture", value = 12, duration = 0 },
                        },
                    },
                },
                {
                    text = "借混乱扩大黑市",
                    desc = "现金收益高，声望代价巨大",
                    effects = {
                        cash = 600,
                        inflation_delta = 0.05,
                        modifiers = {
                            { target = "shadow_income", value = 120, duration = 6 },
                            { target = "public_support", value = -30, duration = 0 },
                            { target = "corruption_risk", value = 22, duration = 8 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 1995 Q4 - 和平协议生效
        -- ================================================================
        {
            id = "peace_accord_1995",
            title = "和平协议生效",
            fixed_date = { year = 1995, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🕊️",
            desc = "和平协议结束大规模战事。战争红利退潮，重建、银行、地产和援助合作成为新的增长点。",
            options = {
                {
                    text = "转向重建地产",
                    desc = "承接重建需求，资产估值回升",
                    effects = {
                        cash = -700,
                        inflation_delta = -0.08,
                        inflation_drift_mod = -0.020,
                        inflation_drift_duration = 10,
                        asset_price_mod = 0.20,
                        asset_price_duration = 10,
                        war_state = false,
                        modifiers = {
                            { target = "total_assets", value = 1200, duration = 0 },
                            { target = "civilian_consumption", value = 0.18, duration = 10 },
                            { target = "gold_price_mod", value = -0.15, duration = 8 },   -- 和平回归金价回落
                            { target = "coal_price_mod", value = 0.20, duration = 10 },   -- 重建基建需煤
                            { target = "silver_price_mod", value = 0.10, duration = 6 },  -- 工业复苏
                        },
                    },
                },
                {
                    text = "建立银行与援助渠道",
                    desc = "金融路线打开",
                    effects = {
                        cash = -450,
                        inflation_delta = -0.06,
                        war_state = false,
                        modifiers = {
                            { target = "political_standing", value = 22, duration = 0 },
                            { target = "foreign_control", value = 10, duration = 0 },
                            { target = "civilian_consumption", value = 0.10, duration = 8 },
                        },
                    },
                },
                {
                    text = "修复城市记忆工程",
                    desc = "文化评价大幅提升",
                    effects = {
                        cash = -380,
                        inflation_delta = -0.04,
                        war_state = false,
                        modifiers = {
                            { target = "culture", value = 50, duration = 0 },
                            { target = "public_support", value = 25, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 2008 Q4 - 全球金融危机波及
        -- ================================================================
        {
            id = "global_financial_crisis_2008",
            title = "全球金融危机波及",
            fixed_date = { year = 2008, quarter = 4 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "🏦",
            desc = "全球金融危机让外资谨慎、地产降温、融资成本上升。现金流健康的家族反而能趁机整合资产。",
            options = {
                {
                    text = "去杠杆，守住现金",
                    desc = "减少风险，错过部分机会",
                    effects = {
                        cash = -300,
                        inflation_delta = -0.02,
                        asset_price_mod = -0.18,
                        asset_price_duration = 8,
                        modifiers = {
                            { target = "risk", value = -16, duration = 8 },
                            { target = "foreign_control", value = -6, duration = 0 },
                        },
                    },
                },
                {
                    text = "抄底优质地产和银行股",
                    desc = "高风险长期扩张",
                    effects = {
                        cash = -900,
                        asset_price_mod = -0.25,
                        asset_price_duration = 4,
                        modifiers = {
                            { target = "total_assets", value = 1500, duration = 0 },
                            { target = "foreign_control", value = 8, duration = 0 },
                            { target = "gold_price_mod", value = 0.30, duration = 6 },    -- 金融恐慌推高金价
                            { target = "silver_price_mod", value = -0.15, duration = 6 }, -- 工业金属需求萎缩
                            { target = "coal_price_mod", value = -0.20, duration = 6 },   -- 经济衰退煤价跌
                        },
                    },
                },
                {
                    text = "转向本地实业现金流",
                    desc = "降低金融波动",
                    effects = {
                        cash = 240,
                        modifiers = {
                            { target = "mine_output", value = 1, duration = 6 },
                            { target = "civilian_consumption", value = 0.08, duration = 6 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 2014 Q2 - 百年纪念节点
        -- ================================================================
        {
            id = "centennial_2014",
            title = "百年纪念节点",
            fixed_date = { year = 2014, quarter = 2 },
            priority = EventsData.PRIORITY.MAIN,
            icon = "📜",
            desc = "枪声过去整整一百年。城市、家族、矿山与金融账本都成为历史的一部分，最后的选择将写入家族档案。",
            options = {
                {
                    text = "建立家族博物馆",
                    desc = "用文化和记忆收束百年经营",
                    effects = {
                        cash = -600,
                        modifiers = {
                            { target = "culture", value = 80, duration = 0 },
                            { target = "public_support", value = 35, duration = 0 },
                        },
                    },
                },
                {
                    text = "成立跨国基金会",
                    desc = "巩固金融与政治网络",
                    effects = {
                        cash = -900,
                        modifiers = {
                            { target = "political_standing", value = 45, duration = 0 },
                            { target = "foreign_assets", value = 3, duration = 0 },
                            { target = "total_assets", value = 1800, duration = 0 },
                        },
                    },
                },
                {
                    text = "公布百年家族档案",
                    desc = "声望提升，也暴露灰色历史",
                    effects = {
                        cash = 200,
                        modifiers = {
                            { target = "culture", value = 45, duration = 0 },
                            { target = "legitimacy", value = 25, duration = 0 },
                            { target = "corruption_risk", value = -15, duration = 0 },
                        },
                    },
                },
            },
        },
    }
end

--- 获取随机事件模板（按条件触发）
---@return table[]
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
            -- 触发条件：拥有矿山且治安 <= 3
            trigger = {
                requires_mine = true,
                max_security = 3,
                cooldown = 4,  -- 触发后冷却 4 季度
            },
            -- 触发概率 (每季度检查)
            chance = 0.20,
            desc = "矿井深处发生塌方事故，多名矿工被困。救援行动刻不容缓，但也需要大量资金。",
            options = {
                {
                    text = "全力救援，不惜代价",
                    desc = "花费高昂但保住人心",
                    effects = {
                        cash = -150,
                        modifiers = {
                            { target = "worker_morale", value = 15, duration = 0 },
                            { target = "public_support", value = 5, duration = 0 },
                            { target = "mine_output", value = -1, duration = 2 },
                        },
                    },
                },
                {
                    text = "最低限度救援",
                    desc = "省钱但伤士气",
                    effects = {
                        cash = -30,
                        modifiers = {
                            { target = "worker_morale", value = -20, duration = 0 },
                            { target = "public_support", value = -10, duration = 0 },
                            { target = "mine_output", value = -1, duration = 1 },
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
                cooldown = 6,
            },
            chance = 0.18,
            desc = "矿工们要求提高工资和改善工作条件。如果不妥善处理，生产将陷入停滞。",
            options = {
                {
                    text = "答应加薪要求",
                    desc = "工资永久上涨",
                    effects = {
                        modifiers = {
                            { target = "worker_wage", value = 2, duration = 0 },
                            { target = "worker_morale", value = 20, duration = 0 },
                        },
                    },
                },
                {
                    text = "谈判妥协，部分满足",
                    desc = "折中方案",
                    effects = {
                        cash = -50,
                        modifiers = {
                            { target = "worker_wage", value = 1, duration = 0 },
                            { target = "worker_morale", value = 5, duration = 0 },
                        },
                    },
                },
                {
                    text = "强硬镇压，雇佣替工",
                    desc = "短期有效但隐患巨大",
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
                min_development = 2,
                cooldown = 8,
            },
            chance = 0.15,
            desc = "一支来自维也纳的投资考察团对你的矿业经营产生了兴趣。他们愿意提供资金，但要求分享利润和决策权。",
            options = {
                {
                    text = "接受投资，让出部分股权",
                    desc = "获得大笔资金但失去部分控制",
                    effects = {
                        cash = 600,
                        modifiers = {
                            { target = "foreign_control", value = 20, duration = 0 },
                            { target = "mine_output", value = 1, duration = 0 },
                        },
                    },
                },
                {
                    text = "仅接受技术合作",
                    desc = "小额资助换取技术支持",
                    effects = {
                        cash = 100,
                        modifiers = {
                            { target = "tech_bonus", value = 5, duration = 8 },
                        },
                    },
                },
                {
                    text = "婉拒，保持独立经营",
                    desc = "不受外部干涉",
                    effects = {
                        modifiers = {
                            { target = "independence", value = 10, duration = 0 },
                        },
                    },
                },
            },
            -- 特殊：本季度 +1 临时 AP
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
                cooldown = 6,
            },
            chance = 0.12,
            desc = "矿工们在深处发现了一条富含金银的新矿脉。这可能让产量大幅提升，但开发需要额外投入。",
            options = {
                {
                    text = "立即开发新矿脉",
                    desc = "投入资金，提升产能 4 季",
                    effects = {
                        cash = -250,
                        modifiers = {
                            { target = "mine_output", value = 2, duration = 4 },
                        },
                    },
                },
                {
                    text = "谨慎勘探，稳步推进",
                    desc = "小投入，长期收益",
                    effects = {
                        cash = -80,
                        gold = 3,
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
            chance = 0.16,
            desc = "当地传统势力对你的崛起感到不安，他们通过各种渠道向你施加压力，要求分享利益或限制扩张。",
            options = {
                {
                    text = "缴纳保护费，息事宁人",
                    desc = "破财消灾",
                    effects = {
                        cash = -200,
                        modifiers = {
                            { target = "local_relations", value = 10, duration = 0 },
                        },
                    },
                },
                {
                    text = "针锋相对，强硬回击",
                    desc = "树敌但显示实力",
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
                    desc = "花费影响力换取保护",
                    effects = {
                        cash = -100,
                        modifiers = {
                            { target = "legitimacy", value = 5, duration = 0 },
                        },
                    },
                },
            },
        },

        -- ================================================================
        -- 黄金价格波动
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
            chance = 0.14,
            desc = "国际市场传来消息，黄金价格出现剧烈波动。此刻出手可能大赚，但也可能买在高点。",
            options = {
                {
                    text = "趁高价抛售库存黄金",
                    desc = "卖出 5 单位黄金，高价兑现",
                    effects = {
                        gold = -5,
                        cash = 400,
                    },
                },
                {
                    text = "逢低吸纳，增加储备",
                    desc = "花钱买入更多黄金",
                    effects = {
                        cash = -200,
                        gold = 6,
                    },
                },
                {
                    text = "按兵不动",
                    desc = "不冒险",
                    effects = {},
                },
            },
        },
    }
end

return EventsData
