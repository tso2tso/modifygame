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
                    },
                },
                {
                    text = "行贿地方官员，减免税负",
                    desc = "走捷径",
                    effects = {
                        cash = -120,
                        modifiers = {
                            { target = "corruption_risk", value = 10, duration = 8 },
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
                        modifiers = {
                            { target = "supply_reserve", value = 20, duration = 0 },
                        },
                    },
                },
                {
                    text = "向军方供应矿产",
                    desc = "短期获利，建立军方关系",
                    effects = {
                        cash = 200,
                        gold = -3,
                        modifiers = {
                            { target = "military_relation", value = 15, duration = 0 },
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
                        modifiers = {
                            { target = "expansion_freeze", value = 1, duration = 4 },
                            { target = "risk", value = -10, duration = 0 },
                        },
                    },
                },
                {
                    text = "转向军需供应",
                    desc = "战争财富，但声誉有损",
                    effects = {
                        cash = 500,
                        modifiers = {
                            { target = "military_relation", value = 15, duration = 0 },
                            { target = "public_support", value = -5, duration = 0 },
                            { target = "military_industry_profit", value = 0.40, duration = 16 },
                        },
                    },
                },
                {
                    text = "向外转移部分资产",
                    desc = "分散风险",
                    effects = {
                        cash = -200,
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
                    worker_cost_multiplier = 1.15,
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
                        modifiers = {
                            { target = "public_support", value = 25, duration = 0 },
                            { target = "culture", value = 10, duration = 0 },
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
