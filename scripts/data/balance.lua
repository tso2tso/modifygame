-- ============================================================================
-- 经济平衡数值表（详细版，覆盖收入/支出/市场/武装/胜利）
-- 所有数值均可通过此文件调节，不散落在各系统中
-- ============================================================================

local Balance = {}

-- ============================================================================
-- 时间
-- ============================================================================
Balance.TIME = {
    start_year    = 1904,
    start_quarter = 1,
    end_year      = 1955,   -- 延伸到战后重建（1946-1955）
    end_quarter   = 4,
    quarters_per_year = 4,
}

-- ============================================================================
-- 行动点 (AP)
-- ============================================================================
Balance.AP = {
    base          = 6,      -- 每季基础 AP
    max_bonus     = 4,      -- 最大加成上限
    -- AP 惩罚
    war_penalty   = -1,     -- 战争状态
    low_security_penalty = -1,  -- 治安极差 (安全等级 1)
    vacant_penalty = -1,    -- 空缺岗位 >= 2
}

-- ============================================================================
-- 起始资源
-- ============================================================================
Balance.START = {
    cash          = 1000,
    gold          = 5,
    workers       = 10,
    guards        = 5,
}

-- ============================================================================
-- 矿业
-- ============================================================================
Balance.MINE = {
    base_gold_output    = 2,     -- 基础每季产金量
    base_copper_output  = 5,     -- 基础每季产铜量
    base_coal_output    = 8,     -- 基础每季采煤量（工业区）
    copper_price        = 8,     -- 铜售价/单位（工业原料定位）
    gold_price          = 50,    -- 黄金售价/单位
    coal_price          = 5,     -- 煤炭售价/单位（低单价高产量）
    upgrade_cost        = 300,   -- 矿山升级基础费用
    max_level           = 5,     -- 矿山最大等级
    max_quarterly_depletion_ratio = 0.08, -- 单季最多开采初始储量的 8%，防止产能溢出式耗尽
    -- 每级产能加成
    level_output_bonus  = 0.20,  -- 每级 +20% 产能
    -- 事故概率（受治安和投入影响）
    accident_base_chance = 0.05, -- 5% 基础事故概率/季
    -- 矿山耗尽处置
    depletion = {
        migrate_ap = 1,                -- 产能迁移消耗 AP
        migrate_cash_ratio = 0.5,      -- 迁移费 = 新矿费用 × 此比例
        cleanup_cost_per_level = 200,  -- 善后处理：每级费用
    },
    prospect = {
        ap = 1,                 -- 启动探矿消耗 AP
        cash = 400,             -- 探矿基础费用
        turns = 2,              -- 探矿周期（季度）
        base_success = 0.25,    -- 首次成功率 25%
        success_decay = 0.05,   -- 每次成功后递减 5%
        min_success = 0.05,     -- 最低成功率 5%
        reserve_min = 1000,     -- 备用矿储量下限
        reserve_max = 2000,     -- 备用矿储量上限
        max_reserves = 2,       -- 备用槽位上限
    },
    -- 铜矿探矿（补充 copper_reserve）
    copper_prospect = {
        ap = 1,                 -- 消耗 AP
        cash = 250,             -- 费用较低（铜价值低于金）
        turns = 1,              -- 1 季度出结果（铜矿勘探较简单）
        base_success = 0.65,    -- 首次成功率 65%
        success_decay = 0.03,   -- 每次成功后递减 3%
        min_success = 0.30,     -- 最低成功率 30%
        reserve_min = 400,      -- 铜储量下限
        reserve_max = 800,      -- 铜储量上限
    },
    -- 煤矿探矿（补充 coal_reserve）
    coal_prospect = {
        ap = 1,                 -- 消耗 AP
        cash = 200,             -- 费用最低（煤分布广）
        turns = 1,              -- 1 季度出结果
        base_success = 0.65,    -- 首次成功率 65%
        success_decay = 0.03,   -- 每次成功后递减 3%
        min_success = 0.30,     -- 最低成功率 30%
        reserve_min = 600,      -- 煤储量下限
        reserve_max = 1200,     -- 煤储量上限
    },
}

-- ============================================================================
-- 工人与人力
-- ============================================================================
Balance.WORKERS = {
    base_wage        = 8,     -- 工人每季工资
    engineer_wage    = 20,    -- 工程师每季工资
    scholar_wage     = 25,    -- 学者每季工资
    -- 效率：每 10 名工人产能 +1
    workers_per_unit = 10,
    -- 招聘费
    hire_cost        = 15,    -- 每招一名工人的费用
    fire_penalty     = 5,     -- 解雇补偿
    -- 士气影响
    morale_wage_threshold = 0.8,  -- 工资低于区域均值 80% 时士气下降
}

-- ============================================================================
-- 武装
-- ============================================================================
Balance.MILITARY = {
    guard_wage       = 12,    -- 护卫每季工资
    recruit_cost     = 30,    -- 招募一名护卫
    -- 战斗力计算
    guard_base_power = 1.0,   -- 每名护卫基础战力
    morale_multiplier = 0.01, -- 士气对战力的乘数 (70 士气 = ×0.7)
    -- 补给
    supply_per_guard = 3,     -- 每名护卫每季消耗补给
    supply_cost      = 2,     -- 每单位补给价格
    -- 士气
    base_morale      = 70,
    morale_decay     = -2,    -- 每季自然衰减
    -- 注意：战斗胜负士气变化使用 Balance.COMBAT.win_morale / lose_morale
}

-- ============================================================================
-- 经济与市场
-- ============================================================================
Balance.ECONOMY = {
    -- 税率（基础，受事件修正）
    base_tax_rate    = 0.03,  -- 3% 财富税（降低开局压力，防止新手 6 季破产）
    war_tax_rate     = 0.12,  -- 战时税率
    -- 利率
    loan_interest    = 0.06,  -- 贷款季利率
    -- 维护费
    building_maintenance = 10,  -- 每栋建筑每季维护
}

-- ============================================================================
-- 胜利条件（v3 — 时间线延长至1955 + 可达性调优）
-- 设计目标：经济线在1945-1950可达，军事线在1940-1950可达
-- ============================================================================
Balance.VICTORY = {
    -- 相对领先胜利：不再因固定阈值直接结束，而是领先 AI 后可宣布胜利并继续游玩
    relative = {
        min_claim_year = 1945,
        lead_margin = {
            economic = 800,
            military = 150,
        },
        dominance_margin = 900,
        ai_military_power_multiplier = 0.12,
        dominance_requires_positive_track = true,
    },
    -- 经济胜利：每季增量 = (floor(cash/2000) + min(floor(gold*0.3), gold_vp_cap) + floor(total_control/15) + floor(total_influence/50)) * war_mod
    economic = {
        threshold       = 1600,  -- 经济胜利点阈值（2000→1600：延长时间线后适度降低）
        cash_divisor    = 2000,  -- 每 2000 现金 +1 点（3000→2000：让现金积累更有效）
        gold_multiplier = 0.3,   -- 每黄金 +0.3 点（0.5→0.3：防止囤金碾压一切策略）
        gold_vp_cap     = 10,    -- 黄金 VP 贡献上限 10/季（约需 34 金才封顶）
        control_divisor = 15,    -- 每 15 总控制度 +1 点（20→15：区域控制更有价值）
        influence_divisor = 50,  -- 每 50 总影响力 +1 点（60→50：文化投入更有回报）
        war_mod         = 0.6,   -- 战时乘数（战争拖慢经济胜利）
        gate_year       = 1930,  -- 章节门控：经济线要到 1930 年后才结算
        -- 快照验证：达到阈值瞬间必须满足以下条件，否则视为无效
        snapshot = {
            min_cash          = 10000,  -- 15000→10000：降低快照门槛
            min_gold          = 20,     -- 25→20
            min_total_control = 80,     -- 100→80
        },
    },
    -- 军事胜利：每季增量 = (floor(guards*0.25) + floor(morale/25) + floor(total_control/12) + 胜场 + 装备分 + 老兵分) * war_mod
    military = {
        threshold        = 2000,  -- 军事胜利点阈值
        guard_multiplier = 0.25,  -- 每护卫 +0.25 点（0.3→0.25：装备/老兵分补充）
        morale_divisor   = 25,    -- 每 25 士气 +1 点
        control_divisor  = 12,    -- 每 12 总控制度 +1 点
        battle_wins_cap  = 3,     -- 每季最多计入 3 场近期胜利
        war_mod          = 1.25,  -- 战时乘数（战争加速军事胜利）
        gate_year        = 1925,  -- 章节门控：军事线要到 1925 年后才结算
        -- 装备/老兵胜利分（方案B）
        equip_score_cap         = 4,    -- 装备分上限
        equip_tier_multiplier   = 0.8,  -- 每 (tier-1) × 0.8
        veterancy_score_cap     = 2,    -- 老兵分上限（王牌编队数 × 1）
        -- 快照验证
        snapshot = {
            min_guards        = 25,     -- 降低快照门槛
            min_morale        = 50,
            min_total_control = 100,
        },
    },
}

-- ============================================================================
-- 影响力 (Influence) 系统
-- ============================================================================
Balance.INFLUENCE = {
    decay_per_season = -1,   -- 每季自然衰减 -1（除非本季执行了文化行动）
    -- 行动消耗
    cost_treaty      = 30,   -- 签订协议消耗影响力
    -- cost_bribe 已移除（v2 简化）
    cost_infiltrate  = 20,   -- 政治渗透消耗影响力
    -- 阈值被动效果
    thresholds = {
        { min = 30,  label = "地方认可",     desc = "地区安全 +1" },
        { min = 70,  label = "舆论优势",     desc = "招募费 -10%" },
        { min = 120, label = "政治联盟",     desc = "AP 上限 +1" },
        { min = 200, label = "文化霸权",     desc = "科技研发 -1 季" },
        { min = 300, label = "不朽影响力",   desc = "经济/军事双线各 +5/季" },
    },
}

-- ============================================================================
-- AI 势力
-- ============================================================================
Balance.AI = {
    -- 地方传统家族
    local_clan = {
        start_cash       = 800,
        growth_rate      = 0.05,  -- 每季资产增长率
        aggression       = 0.3,   -- 攻击倾向
        expand_threshold = 600,   -- 资产超过此值开始扩张
        cash_cap         = 8000,  -- 现金上限（防止复利爆炸）
    },
    -- 外国资本
    foreign_capital = {
        start_cash       = 2000,
        growth_rate      = 0.08,
        aggression       = 0.1,
        expand_threshold = 1000,
        war_flee_threshold = 0.6, -- 战争风险 > 0.6 时撤资
        cash_cap         = 12000, -- 现金上限（外资更富裕但也有上限）
    },
    -- 时代递增：AI 上限随年代提升，避免 1912 年后完全静态
    era_scaling = {
        { year = 1925, cash_cap_mul = 1.3, power_cap = 110 },  -- 一战后扩张
        { year = 1935, cash_cap_mul = 1.6, power_cap = 120 },  -- 二战前军备竞赛
    },
    -- 战时 power 临时上限提升
    war_power_cap = 120,   -- 战时 AI power 上限可达 120（和平时仍为 100）
    -- AI 主动花费行为（每季检查一次）
    spending = {
        -- 雇佣兵：AI 花钱提升 power
        mercenary_cost    = 500,   -- 每次花费
        mercenary_power   = 5,     -- 每次增加 power
        mercenary_chance  = 0.25,  -- 触发概率（cash > expand_threshold 时）
        -- 地区压制：AI 花钱降低玩家控制度
        suppress_cost     = 400,
        suppress_control  = -3,    -- 降低玩家控制度
        suppress_chance   = 0.20,  -- 触发概率（attitude < -30 时）
        -- 经济制裁：AI 花钱对玩家施加负面修正器
        sanction_cost     = 600,
        sanction_chance   = 0.15,  -- 触发概率（foreign_capital 且 attitude < -40 时）
        -- 通胀操纵：外资推高通胀系数（仅 foreign_capital）
        inflate_cost      = 800,
        inflate_drift     = 0.012, -- 额外通胀漂移
        inflate_duration  = 4,     -- 持续季度
        inflate_chance    = 0.12,  -- 触发概率（attitude < -50 时）
        -- 矿价波动：外资压低金铜价格（仅 foreign_capital）
        mine_price_cost   = 700,
        mine_price_mod    = -0.15, -- 矿产品价格 -15%
        mine_price_duration = 3,
        mine_price_chance = 0.15,  -- 触发概率（attitude < -35 时）
    },
    -- 正向态度触发器（每季检查，使态度不至于单调下降）
    positive_triggers = {
        player_weak_cash    = 500,   -- 玩家现金低于此值 → 态度 +2（不再是威胁）
        player_few_mines    = 2,     -- 玩家矿山少于此数 → 态度 +1（领地竞争消退）
        low_power_sympathy  = 30,    -- AI power 低于此值 → 态度 +1（弱势求和倾向）
        natural_recovery    = 1,     -- 每季自然回暖 +1（人心向善基线）
        attitude_cap        = 60,    -- 正向态度上限（不会无限好感）
    },
    -- AI 势力瘫痪机制（power + cash 过低时触发）
    collapse = {
        power_threshold   = 5,    -- power <= 此值 且 cash <= cash_threshold 时触发瘫痪
        cash_threshold    = 100,  -- cash <= 此值 且 power <= power_threshold 时触发瘫痪
        collapsed_power_gain = 1, -- 瘫痪期间每季度 power 恢复量（正常 2~3）
        presence_decay    = 5,    -- 瘫痪期间每季度地区存在度衰减
        recovery_seasons  = 6,    -- 瘫痪持续 N 季后获得一次性注入
        recovery_cash     = 400,  -- 恢复时注入的现金
        recovery_power    = 20,   -- 恢复时注入的势力值
    },
}

-- ============================================================================
-- 股市（GBM 模型基本面）
-- mu    季度漂移率（长期趋势）
-- sigma 季度波动率
-- 参数参考：见 systems/stock_engine.lua 注释的"现实对照表"
-- ============================================================================
Balance.STOCKS = {
    {
        id     = "sarajevo_mining",
        name   = "萨拉热窝矿业",
        price  = 12.50,
        mu     = 0.005,     -- 调低：均值回归后只需微正漂移
        sigma  = 0.10,      -- 中等波动
        sector = "mining",
        rating = "buy",
        -- 公允价值锚定参数（Fair Value Anchored Model）
        base_value      = 12.50,  -- 1904年初始公允价值（= 初始价格）
        inflation_alpha = 1.15,   -- 通胀敏感度（矿业受大宗商品影响大）
        theta           = 0.12,   -- 均值回归速度（半衰期 ≈ 6 季）
    },
    {
        id     = "imperial_railway",
        name   = "帝国铁路公司",
        price  = 8.30,
        mu     = -0.003,    -- 微弱下行（战前铁路受政治打压）
        sigma  = 0.07,      -- 公用事业低波动
        sector = "transport",
        rating = "hold",
        base_value      = 8.30,
        inflation_alpha = 0.90,   -- 铁路定价受管制，跟通胀弱
        theta           = 0.15,   -- 回归偏快（公用事业均值回归强）
    },
    {
        id     = "balkan_shipping",
        name   = "巴尔干行船",
        price  = 15.60,
        mu     = 0.000,
        sigma  = 0.12,      -- 航运中等偏高
        sector = "transport",
        rating = "hold",
        base_value      = 15.60,
        inflation_alpha = 0.95,
        theta           = 0.12,
    },
    {
        id     = "military_industry",
        name   = "军需工业集团",
        price  = 22.10,
        mu     = 0.000,     -- 平时不涨；战时事件会暴涨
        sigma  = 0.15,      -- 高波动（军工敏感）
        sector = "military",
        rating = "hold",
        base_value      = 22.10,
        inflation_alpha = 0.85,   -- 军工定价独立于通胀，靠订单驱动
        theta           = 0.10,   -- 回归偏慢（大事件可拉开更长偏离）
    },
    {
        id     = "austro_bank_trust",
        name   = "奥匈银行信托",
        price  = 31.40,
        mu     = 0.003,     -- 金融温和正漂移
        sigma  = 0.08,
        sector = "finance",
        rating = "buy",
        base_value      = 31.40,
        inflation_alpha = 0.75,   -- 金融资产本身是通胀对冲，alpha 低
        theta           = 0.15,   -- 金融股均值回归强
    },
    {
        id     = "oriental_trading",
        name   = "东方贸易商行",
        price  = 9.75,
        mu     = 0.002,
        sigma  = 0.10,      -- 中小贸易波动
        sector = "trade",
        rating = "hold",
        base_value      = 9.75,
        inflation_alpha = 0.95,
        theta           = 0.12,
    },
}

-- ============================================================================
-- 行动点购买（顶栏 [+] 按钮）
-- ============================================================================
Balance.AP_PURCHASE = {
    cost_per_ap       = 200,  -- 每次 +1 AP 消耗的现金
    max_per_season    = 2,    -- 每季最多购买次数
}

-- ============================================================================
-- 贷款（v2 — 基于资产估值 + 杠杆利率）
-- ============================================================================
Balance.LOAN = {
    max_active    = 3,         -- 同时最多持有 3 笔贷款
    -- 抵押折扣：实体资产可贷比例高，股票波动大所以可贷比例低
    collateral = {
        real_asset_ratio  = 0.80,  -- 现金/黄金/矿山等实体资产抵押率
        stock_asset_ratio = 0.25,  -- 股票市值抵押率
    },
    -- 贷款档位：amount_ratio = 占抵押价值的比例（实际额度 = 抵押价值 × ratio，最低保底 min_amount）
    options = {
        { amount_ratio = 0.15, min_amount = 300,  base_interest = 0.04, duration = 4, label = "小额短贷" },
        { amount_ratio = 0.35, min_amount = 800,  base_interest = 0.05, duration = 6, label = "中额贷款" },
        { amount_ratio = 0.60, min_amount = 2000, base_interest = 0.06, duration = 8, label = "大额长贷" },
    },
    -- 杠杆利率加成：实际利率 = base_interest × (1 + leverage × leverage_interest_multiplier)
    -- leverage = 总负债 / 抵押价值
    leverage_interest_multiplier = 1.5,  -- 杠杆率 0.5 → 利率 ×1.75；杠杆率 1.0 → 利率 ×2.5
    max_leverage   = 0.80,     -- 杠杆率超过 80% 时禁止再贷款
    default_penalty = 0.15,    -- 违约（资金不足付息）时本金膨胀 15%
    max_rollovers  = 1,        -- 最多展期次数，超过则强制清算
    default_morale_penalty = -10,  -- 坏账核销士气惩罚
    -- 强制抵押清算（违约时优先执行）
    forced_liquidation = {
        sell_gold       = true,   -- 第一步：强制变卖黄金偿付利息
        downgrade_mines = true,   -- 第二步：黄金不够则降级矿山换现金
        mine_downgrade_refund_ratio = 0.5,  -- 降级矿山退还升级费的 50%
        morale_penalty  = -5,     -- 每次强制清算士气惩罚
    },
    -- 破产条件（强制清算后仍无法偿付才计入连续违约）
    bankruptcy = {
        consecutive_defaults = 4,     -- 连续违约 4 季触发破产（清算后仍违约才计数）
        negative_net_worth_turns = 4, -- 净资产连续为负 4 季触发破产
        warning_at_defaults = 2,      -- 连续违约 2 季开始警告
    },
}

-- ============================================================================
-- 通胀（按季累积的乘数，越战越严重）
-- ============================================================================
Balance.INFLATION = {
    base_factor       = 1.0,
    -- 历史参考：奥匈帝国一战物价涨10-15×，南斯拉夫二战涨20-50×
    -- 大萧条期间通缩-20~-30%，战后新货币逐步稳定
    floor_factor      = 0.45,    -- 大萧条可压至基准0.45×（历史通缩-20~-30%）
    quarter_drift_peace = 0.006,   -- +0.6%/季（和平温和，年化~2.4%，接近历史）
    quarter_drift_war   = 0.07,    -- +7%/季（战时通胀：16季≈1.07^16≈3×，合理且不致死螺旋）
    quarter_drift_crisis_floor = -0.04, -- 大萧条/战后通缩可达-4%/季（年化-15%，接近历史-20~-30%）
    cap_factor        = 10.0,      -- 上限10×（防止数值彻底失控）
    asset_mod_floor   = -0.60,     -- 大萧条期间资产暴跌-60%（接近历史股市跌幅）
    asset_mod_cap     = 1.00,      -- 战时资产泡沫可达+100%（军需品价格翻倍常见）
    -- 战后通缩恢复：和平期间若通胀高于此阈值，每季额外施加负漂移
    postwar_deflation_threshold = 2.0,   -- 通胀超过 2× 时触发战后通缩
    postwar_deflation_drift     = -0.015, -- 每季 -1.5%（与和平 +0.6% 叠加 → 净 -0.9%/季）
}

-- ============================================================================
-- 科技研发
-- ============================================================================
Balance.TECH = {
    base_research_cost = 300,  -- 单项科技基础现金成本
    base_research_ap   = 2,    -- 单项科技启动 AP 消耗
    base_research_turns = 3,   -- 基础研发季度数
}

-- ============================================================================
-- 情报行动
-- ============================================================================
Balance.INTEL = {
    scout = { ap = 1, cash = 80 },
    -- infiltrate / bribe 已移除（v2 简化：仅保留 scout + 破坏招募）
}

-- ============================================================================
-- 外交
-- ============================================================================
Balance.DIPLOMACY = {
    gift    = { ap = 1, cash = 200, attitude = 6 },
    treaty  = { ap = 2, cash = 500, attitude_req = 20, attitude = 15, pact_turns = 8 },
    hostile = { ap = 1, attitude = -35 },
}

-- ============================================================================
-- 资产交易
-- ============================================================================
Balance.TRADE = {
    new_mine = { ap = 2, cash = 1200, base_reserve = 1500, max_mines = 4 },  -- 基础4槽，科技可扩至8
    sell_mine = { ap = 2, cash_per_level = 500 },
    raid_ai = { ap = 2, cash = 300, recruit_block_duration = 4 },  -- 破坏招募：封锁AI扩张4季
}

-- ============================================================================
-- 战斗
-- ============================================================================
Balance.COMBAT = {
    ai_attack_threshold = -20,   -- AI attitude 低于此值才可能进攻（降低门槛）
    ai_attack_power_req = 40,    -- 且 AI power 达到阈值（降低门槛）
    ai_attack_chance    = 0.35,  -- 每季 35% 概率主动进攻（提高概率）
    player_attack_ap    = 2,     -- 主动突袭 AI 消耗 AP
    player_attack_cash  = 180,   -- 主动突袭的情报/补给准备费
    win_morale          = 10,
    lose_morale         = -18,
    lose_guards_ratio   = 0.30,  -- 战败损失 30% 护卫
    loot_ratio          = 0.25,  -- 战胜抢夺 AI 25% 现金
}

-- ============================================================================
-- 家族
-- ============================================================================
Balance.FAMILY = {
    max_members      = 11,    -- 最多核心成员（3初始+8培养）
    train_cost       = 200,   -- 培养新成员基础费用
    train_duration   = 10,    -- 培养周期（季度）
    -- 递增培养费用：第4-6人 200，第7-8人 300，第9-11人 500
    train_cost_tiers = {
        { max_count = 6,  cost = 200 },  -- 成员数 ≤ 6 时
        { max_count = 8,  cost = 300 },  -- 成员数 7-8 时
        { max_count = 11, cost = 500 },  -- 成员数 9-11 时
    },
    attr_threshold_excellent = 8,  -- 满配属性阈值
    attr_threshold_good      = 5,  -- 半配属性阈值
    -- 岗位加成
    position_bonus_full = 1.0,    -- 满配加成系数
    position_bonus_half = 0.5,    -- 半配加成系数
    position_penalty    = -0.1,   -- 差配惩罚
    -- 空缺惩罚
    vacant_efficiency_penalty = -0.30,  -- 空缺方向效率 -30%
    -- 上岗适应期
    onboarding_turns       = 2,    -- 上岗后需适应 2 季度
    onboarding_bonus_ratio = 0.3,  -- 适应期间仅获得 30% 岗位加成
    -- 下岗冷却
    unassign_cooldown      = 2,    -- 撤下成员进入 2 季度冷却期
}

-- ============================================================================
-- 破产免死（看广告触发，每局仅限一次）
-- ============================================================================
Balance.BANKRUPTCY_RESCUE = {
    max_uses_per_game  = 1,       -- 每局最多使用次数
    rescue_cash_base   = 800,     -- 注入现金基础值（叠加通胀）
    clear_defaults     = true,    -- 重置连续违约计数
    clear_neg_nw       = true,    -- 重置负净资产计数
}

-- ============================================================================
-- 幸运事件（看广告触发）
-- 基础金额 666~2000，随通胀浮动，概率递减
-- ============================================================================
Balance.LUCKY_EVENT = {
    -- 奖励档位：base = 基础金额，weight = 初始权重（越大越容易抽到）
    tiers = {
        { base = 666,  label = "小额意外之财",   weight = 50 },   -- 最常见
        { base = 888,  label = "商队赠礼",       weight = 30 },
        { base = 1200, label = "矿脉意外发现",   weight = 12 },
        { base = 1600, label = "贵族赞助",       weight = 5 },
        { base = 2000, label = "中了头彩！",     weight = 3 },    -- 最稀有
    },
    -- 概率递减：每次看广告后，下次各档权重 × decay_factor
    decay_factor   = 0.7,     -- 每次衰减 30%
    decay_min      = 0.15,    -- 最低衰减到原始权重的 15%
    -- 冷却：同一季度内最多看 N 次广告
    max_per_season = 3,
}

-- ============================================================================
-- 外国矿产操作（侦察 → 开采 → 重建）
-- ============================================================================
Balance.FOREIGN_OPS = {
    -- 侦察
    scout_ap         = 1,
    scout_cash       = 150,
    scout_turns      = 1,       -- 1 季完成侦察

    -- 开采
    exploit_ap       = 2,
    exploit_cash     = 800,
    exploit_min_collab = 10,    -- 需要合作分 >= 10
    initial_damage   = 0.80,    -- 占领初始 80% 损毁
    max_concurrent   = 3,       -- 同时最多开采 3 个外国矿

    -- 重建
    rebuild_ap       = 1,
    rebuild_cash     = 500,
    rebuild_repair   = 0.10,    -- 每次修复 10%
    rebuild_min_damage = 0.10,  -- 最低损毁 10%（永远无法完全恢复）

    -- 产出系数（相对国内矿同等级基础产出的比例）
    output_base_ratio = 0.5,    -- 外国矿基础产出 = 国内 50%
}

-- ============================================================================
-- 煤炭动力化机制
-- ============================================================================
Balance.COAL = {
    factory_consumption  = { 3, 5, 8 },  -- 兵工厂 Lv1/2/3 每季煤耗
    mine_power_per_5     = 0.15,          -- 每5煤投入矿山 → 金矿产出 +15%
    mine_power_cap       = 0.30,          -- 矿山电力加成上限 30%
    war_price_premium    = 0.50,          -- 战时煤价 +50%
    min_control_factor   = 0.30,          -- 煤炭产出控制度下限（控制度<30%时按30%算，保证基础产量）
}

-- ============================================================================
-- 黄金抗通胀机制
-- ============================================================================
Balance.GOLD = {
    inflation_hedge_per_10   = 0.02,  -- 每持有10黄金 → 支出通胀乘数 -2%
    inflation_hedge_cap      = 0.20,  -- 最多减少20%
    price_inflation_exponent = 1.2,   -- 金价 = base × inflation^1.2（超线性增长）
    reserve_interest_threshold = 20,  -- 超过20的部分才生息
    reserve_interest_rate    = 0.005, -- 0.5%/季（折算现金）
    war_premium              = 0.30,  -- 战时金价溢价30%
}

Balance.COPPER = {
    -- 装备生产铜耗（按 tier，与 equipment_data CATALOG key 对应）
    prod_copper_cost = {
        rifle          = 0,    -- T1 免费
        improved_rifle = 3,    -- T2
        mg             = 6,    -- T3
        mortar         = 10,   -- T4
        motorized      = 15,   -- T5
        elite_kit      = 25,   -- T6
    },
    maintenance_reduction_per_10 = 0.05,  -- 每持有10铜 → 装备维护费 -5%
    maintenance_reduction_cap    = 0.25,  -- 维护费减免上限 25%
}

return Balance
