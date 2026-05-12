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
    cash          = 800,
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
    base_coal_output    = 15,    -- 基础每季采煤量（工业区）
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
        reserve_min = 1000,     -- 煤储量下限
        reserve_max = 2000,     -- 煤储量上限
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
    -- 士气
    base_morale      = 70,
    morale_decay     = -2,    -- 每季自然衰减
    morale_boost_cost_per_guard = 40, -- 犒赏军心：每名护卫基础现金消耗
    morale_boost_ap   = 1,    -- 犒赏军心：AP 消耗
    morale_boost_amount = 6,  -- 犒赏军心：士气恢复量
    -- 注意：战斗胜负士气变化使用 Balance.COMBAT.win_morale / lose_morale
}

-- ============================================================================
-- 经济与市场
-- ============================================================================
Balance.ECONOMY = {
    -- 税率（基础，受事件修正）
    base_tax_rate    = 0.08,  -- 8% 收入税（改为按季度总收入征税，原 3% 财产税）
    war_tax_rate     = 0.25,  -- 战时收入税率（原 12% 财产税）
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
    -- 经济胜利：每季增量 = (floor(cash/2000) + min(floor(gold*0.3), gold_vp_cap) + floor(total_control/15)) * war_mod
    economic = {
        threshold       = 1600,  -- 经济胜利点阈值（2000→1600：延长时间线后适度降低）
        cash_divisor    = 2000,  -- 每 2000 现金 +1 点（3000→2000：让现金积累更有效）
        gold_multiplier = 0.3,   -- 每黄金 +0.3 点（0.5→0.3：防止囤金碾压一切策略）
        gold_vp_cap     = 40,    -- 黄金 VP 贡献上限 40/季（让黄金策略成为可行路线）
        control_divisor = 15,    -- 每 15 总控制度 +1 点（20→15：区域控制更有价值）
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
        -- 威慑分：维持军力但不打仗也有回报（保守军事路线补偿）
        deterrence_guard_min    = 15,   -- 威慑分所需最低卫队数
        deterrence_bonus        = 1,    -- 每季威慑 VP
        -- 快照验证
        snapshot = {
            min_guards        = 25,     -- 降低快照门槛
            min_morale        = 50,
            min_total_control = 100,
        },
    },
    -- 统治胜利：征服路线的终极目标
    domination = {
        type = "domination",
        label = "巴尔干霸主",
        desc = "占领巴尔干半岛全部小国（黑山、塞尔维亚、保加利亚、罗马尼亚、希腊）",
        required_countries = { "montenegro", "serbia", "bulgaria", "romania", "greece" },
        min_total_control = 100,
    },
    -- 全面统治：征服所有可达国家
    world_domination = {
        type = "world_domination",
        label = "全面统治",
        desc = "占领所有可达国家",
        required_countries = "all_reachable",  -- 动态计算
        min_total_control = 100,
    },
}

-- ============================================================================
-- 控制度里程碑（总控制度 = 各地区 control 之和，最大 500）
-- ============================================================================
Balance.CONTROL_MILESTONES = {
    thresholds = {
        { min = 80,  label = "地方认可",     desc = "地区安全 +1" },
        { min = 150, label = "舆论优势",     desc = "招募费 -10%" },
        { min = 200, label = "政治联盟",     desc = "AP 上限 +1" },
        { min = 300, label = "区域霸权",     desc = "科技研发 -1 季" },
        { min = 400, label = "绝对统治",     desc = "经济/军事双线各 +5/季" },
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
        power_decay_rate = 0.01,  -- 每季 power 内耗衰减 1%（防雪球）
    },
    -- 外国资本
    foreign_capital = {
        start_cash       = 2000,
        growth_rate      = 0.08,
        aggression       = 0.1,
        expand_threshold = 1000,
        war_flee_threshold = 0.6, -- 战争风险 > 0.6 时撤资
        cash_cap         = 12000, -- 现金上限（外资更富裕但也有上限）
        power_decay_rate = 0.015, -- 每季 power 内耗衰减 1.5%（防雪球）
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
        max_shares = 20000,      -- 矿业：总股本 2 万
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
        max_shares = 20000,      -- 军工：总股本 2 万
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
    {
        id     = "balkan_press",
        name   = "巴尔干新闻社",
        price  = 6.80,
        mu     = 0.004,     -- 小幅正漂移（文化资产温和增长）
        sigma  = 0.13,      -- 较高波动（受舆论/事件影响大）
        sector = "media",
        max_shares = 50000,
        rating = "hold",
        base_value      = 6.80,
        inflation_alpha = 0.80,   -- 中低通胀敏感度
        theta           = 0.10,   -- 慢均值回归（给操控空间）
    },
}
-- 每支股票的最大持仓（防止雪球效应）
-- 矿业/军工 = 20000，其余 = 50000（各股票可在 STOCKS 表中用 max_shares 覆盖）
Balance.STOCK_MAX_SHARES = 50000
-- 持股级别按百分比计算（相对于该股票 max_shares）
Balance.STOCK_LEVEL_PCT = {
    control   = 0.60,   -- ≥60% → 控股
    influence = 0.30,   -- ≥30% → 重要持股
    stake     = 0.10,   -- ≥10% → 战略持股
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
    local_coal_mine = { ap = 1, cash = 700, base_reserve = 1500, base_output = 8 },
    sell_mine = { ap = 2, cash_per_level = 500 },
    raid_ai = { ap = 2, cash = 300, recruit_block_duration = 4 },  -- 破坏招募：封锁AI扩张4季
}

-- ============================================================================
-- 跨国贸易（Phase 3：幕后执政解锁后激活）
-- ============================================================================
Balance.FOREIGN_TRADE = {
    -- 订单生成
    peace_order_count = 3,           -- 和平时期每季固定生成订单数（从1提升到3，增加贸易可玩性）
    war_order_base = 2,              -- 战时基础订单数
    war_order_per_belligerent = 1,   -- 每个交战大国额外 +1 订单
    war_order_cap = 5,               -- 战时订单上限
    order_pool_max = 6,              -- 订单池最大容量（超出的丢弃最旧的）
    accept_ap_cost = 1,              -- 接受订单消耗 AP
    ship_ap_cost = 1,                -- 发货消耗 AP
    quick_fulfill_surcharge = 0.20,  -- 一键履约运费溢价 20%（省 AP 但多花运费）

    -- 路线安全度修正
    safety_war_penalty = -0.20,      -- 途经国家处于战争时安全度 -20%
    safety_occupied_penalty = -0.15, -- 途经国家被占领时 -15%
    safety_diplo_bonus_max = 0.20,   -- 外交分数最大加成 +20%
    safety_escort_bonus = 0.20,      -- 护送小队基础加成
    safety_escort_vet_bonus = 0.05,  -- 护送小队每级老兵额外 +5%

    -- 交付结算
    delivery_turns = 1,              -- 发货后需运输的季度数（近距离1，中距离2，远距离3）
    delivery_distance_turns = { 1, 1, 2, 3 },  -- 按 distance 索引（1跳=1季, 2跳=1季, 3跳=2季, 4跳=3季）
    failure_loss_ratio = 0.5,        -- 运输失败时损失已分配装备的比例
    -- (贸易信誉已合并到统一声誉系统 Balance.REPUTATION)

    -- 外交效果
    diplo_success_collab = 5,        -- 成功交付 → 买家合作度 +5
    diplo_success_enemy = -3,        -- 成功交付 → 买家敌人合作度 -3
    diplo_fail_collab = -3,          -- 交付失败 → 买家合作度 -3

    -- 通胀乘数
    inflation_price_exponent = 0.5,  -- 订单报酬随通胀增长的指数
}

-- ============================================================================
-- 好感度自然衰减（大国 attitude_to_player 每季向0靠拢）
-- ============================================================================
Balance.ATTITUDE_DECAY = {
    rate          = 0.05,   -- 每季衰减5%（向0靠拢）
    threshold     = 5,      -- 绝对值≤5时停止衰减（微弱关系持久）
    cap_per_turn  = 3,      -- 单季最大衰减量（防止极高好感快速崩塌）
}

-- ============================================================================
-- 远征（跨国军事行动）
-- ============================================================================
Balance.EXPEDITION = {
    -- HP系统
    hp_per_stability       = 7,      -- 国家HP = stability × 此值（多回合远征需更厚HP池）
    hp_regen_ratio         = 0.15,   -- 每季恢复 = stability × 此值（远征期间恢复减弱）
    regen_when_raided_mult = 0,      -- 有活跃远征时完全不恢复
    sovereign_regen_mult   = 1.5,    -- 被大国保护的小国恢复 ×1.5
    major_damage_reduction = 0.7,    -- 大国伤害减免（受到 70% 伤害）
    political_hp_ratio     = 5,      -- 大国政治HP = stability × 此值

    -- 远征发起消耗
    expedition_ap_cost           = 2,    -- 发起远征消耗AP
    expedition_cost_per_soldier  = 40,   -- 每名士兵40₿（受通胀影响）
    expedition_reinforce_ap      = 1,    -- 增援消耗AP
    expedition_withdraw_ap       = 1,    -- 撤退消耗AP（无金钱消耗）

    -- 每回合伤害公式参数
    expedition_base_damage_per_turn = 8,    -- 基础每回合伤害
    expedition_defender_mult        = 2,    -- 防御基数 = stability × 此值
    expedition_power_scaling        = 0.6,  -- 兵力差距的缩放指数

    -- 完成时结算
    expedition_success_base         = 0.70,  -- 基础成功率70%
    expedition_success_power_weight = 0.20,  -- 兵力优势每100%加20%成功率
    expedition_success_cap          = 0.95,  -- 成功率上限95%
    expedition_success_floor        = 0.30,  -- 成功率下限30%
    expedition_loss_base_ratio      = 0.08,  -- 基础损失率8%（部署兵力的比例）
    expedition_loss_power_reduction = 0.03,  -- 兵力优势每100%减少3%损失
    expedition_loss_min_ratio       = 0.02,  -- 最低损失率2%
    expedition_fail_loss_mult       = 1.5,   -- 失败时损失倍率
    expedition_fail_hp_restore      = 0.3,   -- 失败后目标HP恢复到最大值的此比例

    -- 掠夺（远征成功时）
    expedition_loot_per_stability   = 80,    -- 每点stability的掠夺基数

    -- 支援作战（保持不变）
    support_ap_cost        = 2,      -- 支援作战AP
    support_cash_cost      = 300,    -- 支援作战现金
    support_reward_min     = 500,    -- 佣兵报酬最小值
    support_reward_max     = 2000,   -- 佣兵报酬最大值
    support_base_success   = 0.65,   -- 支援基础成功率
    support_power_factor   = 0.002,  -- 战力影响系数

    -- 占领行动
    occupy_ap_cost         = 2,      -- 自行占领AP
    occupy_cash_cost       = 300,    -- 自行占领现金
    give_to_faction_ap     = 1,      -- 交给势力AP
    give_to_faction_relation = 15,   -- 交给势力关系加成

    -- 占领收入/维护
    occupy_income_minor    = 200,    -- 小国/中等国家每季收入
    occupy_income_major    = 350,    -- 大国每季收入
    occupy_maintenance_minor = 120,  -- 小国维护费
    occupy_maintenance_major = 200,  -- 大国维护费

    -- 侵略制裁
    aggression_per_expedition = 1,   -- 每次发起远征增加侵略度
    aggression_per_occupy  = 2,      -- 自行占领增加侵略度
    aggression_per_give    = 1,      -- 交给势力增加侵略度（比自占低）
    aggression_decay       = 0.5,    -- 每季自然衰减
    sanction_threshold     = 5,      -- 制裁触发阈值
    intervention_threshold = 8,      -- 军事干预触发阈值
    sanction_duration      = 4,      -- 制裁持续回合

    -- 征服难度系数
    difficulty_tiers = {
        { max_count = 2,  mod = 1.00 },  -- 前2个国家正常难度
        { max_count = 5,  mod = 1.15 },  -- 3-5个 +15%
        { max_count = 10, mod = 1.35 },  -- 6-10个 +35%
        { max_count = 99, mod = 1.60 },  -- 11+ +60%
    },

    -- 前进基地加成
    forward_base_attack_bonus = 0.20,  -- 邻接已占领国家时攻击力+20%
}

-- ============================================================================
-- 商业远征（经济路线的深度渗透玩法）
-- 前置：称号系统解锁"商业大亨"后激活
-- ============================================================================
Balance.VENTURE = {
    -- 市场壁垒（类似远征HP，基于目标国stability）
    barrier_per_stability      = 2,      -- 市场壁垒 = stability × 此值
    barrier_regen_ratio        = 0.10,   -- 撤出后壁垒恢复 = stability × 此值/回合
    regen_when_active_mult     = 0,      -- 活跃渗透期间壁垒不恢复（与远征一致）
    major_barrier_bonus        = 1.3,    -- 大国壁垒额外 ×1.3
    neutral_barrier_bonus      = 1.2,    -- 中立国壁垒额外 ×1.2

    -- 并发限制
    max_concurrent_ventures    = 2,      -- 最多同时进行2个商业远征

    -- 发起商业远征
    venture_ap_cost            = 2,      -- 发起渗透消耗AP
    base_investment_cost       = 300,    -- 每回合基础投资额（受通胀影响）
    reinforce_ap_cost          = 1,      -- 调整投资等级消耗AP
    withdraw_ap_cost           = 1,      -- 撤出渗透消耗AP

    -- 投资等级（类似远征兵力，越高渗透越快但花费越多）
    investment_levels = {
        { mult = 1.0, cost_mult = 1.0, label = "小额投资" },
        { mult = 1.8, cost_mult = 2.0, label = "中额投资" },
        { mult = 2.5, cost_mult = 3.0, label = "大额投资" },
    },

    -- 渗透公式参数
    base_penetration_per_turn  = 10,     -- 基础每回合渗透值
    distance_penalty           = { 0, 0.05, 0.10, 0.20 },  -- 距离1-4的渗透惩罚

    -- 渗透策略（发起时选择，进行中可切换）
    -- 每种策略有独特效果，形成差异化选择而非纯数值比较
    strategies = {
        normal = {
            label = "常规贸易",
            icon  = "📦",
            desc  = "稳扎稳打的传统商路渗透，额外降低紧张度",
            cost_mult        = 1.0,
            penetration_mult = 1.0,
            tension_add      = 0,
            rep_cost         = 0,
            requires         = nil,
            -- 独特效果：每季额外衰减紧张度
            extra_tension_decay = 0.1,
        },
        dumping = {
            label = "倾销战",
            icon  = "💰",
            desc  = "以低价倾销打开市场，渗透极快但紧张度极高；据点收入+30%，削弱目标国稳定度",
            cost_mult        = 1.5,
            penetration_mult = 2.0,
            tension_add      = 0.8,
            rep_cost         = -3,
            requires         = nil,
            -- 独特效果：渗透期间每季削弱目标国稳定度；据点收入加成
            stability_damage_per_turn = 1,    -- 每季削减目标国稳定度
            post_income_bonus        = 0.30,  -- 据点收入+30%
        },
        bribery = {
            label = "商业贿赂",
            icon  = "🤝",
            desc  = "通过贿赂当地官员绕过壁垒，完成成功率+15%，据点维护费-20%",
            cost_mult        = 1.3,
            penetration_mult = 1.2,
            tension_add      = 0.2,
            rep_cost         = -2,
            requires         = { type = "reputation", min = 10 },
            -- 独特效果：提高完成成功率；降低据点维护费
            success_rate_bonus    = 0.15,  -- 成功率+15%
            maintenance_discount  = 0.20,  -- 据点维护费-20%
        },
        tech_export = {
            label = "技术输出",
            icon  = "⚙️",
            desc  = "以先进技术换取市场准入，据点每季产科技点，改善外交",
            cost_mult        = 1.5,
            penetration_mult = 1.5,
            tension_add      = 0.1,
            rep_cost         = 0,
            requires         = { type = "tech", tech_id = "b4a_trade_route" },
            -- 独特效果：据点每季产科技点；改善与目标国外交
            post_tech_per_turn  = 1,    -- 据点每季产 1 科技点
            diplo_bonus         = 2,    -- 建立据点时改善外交
        },
    },

    -- 完成后建立类型（类似远征的占领三选一）
    establishments = {
        trading_post = {
            label = "贸易站",
            icon  = "🏪",
            desc  = "轻量级商业据点，低收入低维护",
            income_minor       = 120,    -- 小国/中等国家每季收入
            income_major       = 200,    -- 大国每季收入
            maintenance_minor  = 60,
            maintenance_major  = 100,
            tension_add        = 1,
            diplo_penalty      = -3,     -- 对目标国好感度
        },
        joint_venture = {
            label = "合资商行",
            icon  = "🏢",
            desc  = "与当地商人合作经营，中等收入中等维护",
            income_minor       = 250,
            income_major       = 400,
            maintenance_minor  = 140,
            maintenance_major  = 220,
            tension_add        = 2,
            diplo_penalty      = -5,
        },
        monopoly = {
            label = "商业垄断",
            icon  = "🏰",
            desc  = "完全控制当地市场，高收入高维护高风险",
            income_minor       = 400,
            income_major       = 650,
            maintenance_minor  = 250,
            maintenance_major  = 400,
            tension_add        = 3,
            diplo_penalty      = -10,
            requires           = { type = "tech", tech_id = "b11_trade_monopoly" },
        },
    },

    -- 市场紧张度（类似远征侵略计数器）
    tension_per_venture        = 1,      -- 每次发起渗透增加紧张度
    tension_decay              = 0.3,    -- 每季自然衰减
    sanction_threshold         = 5,      -- 贸易制裁触发阈值
    intervention_threshold     = 8,      -- 列强联合抵制触发阈值
    sanction_duration          = 4,      -- 制裁持续回合
    sanction_income_mult       = 0.5,    -- 制裁期间商业据点收入减半

    -- 壁垒恢复（撤出或失败后）
    fail_barrier_restore       = 0.3,    -- 渗透失败后壁垒恢复至最大值的此比例

    -- 渗透完成判定
    completion_success_base    = 0.80,   -- 壁垒归零后基础成功率80%
    completion_success_cap     = 0.95,   -- 成功率上限95%
    completion_success_floor   = 0.40,   -- 成功率下限40%
    completion_rep_weight      = 0.003,  -- 每点正声誉 +0.3% 成功率

    -- 耦合加成
    occupied_barrier_mult      = 0.5,    -- 已被远征占领的国家壁垒减半
    trade_route_bonus          = 0.15,   -- 已有贸易路线时渗透 +15%
    reputation_bonus_per_10    = 0.05,   -- 每10点正声誉渗透 +5%
    reputation_bonus_cap       = 0.25,   -- 声誉渗透加成上限25%

    -- 难度递增（已建立的商业据点越多越难）
    difficulty_tiers = {
        { max_count = 2,  mod = 1.00 },  -- 前2个据点正常
        { max_count = 4,  mod = 1.15 },  -- 3-4个 +15%
        { max_count = 7,  mod = 1.30 },  -- 5-7个 +30%
        { max_count = 99, mod = 1.50 },  -- 8+ +50%
    },

    -- 股市联动（东方贸易商行 mu 加成）
    stock_id                   = "oriental_trading",
    stock_bonus_per_post       = 0.003,  -- 每个贸易站 → mu +0.3%
    stock_bonus_per_joint      = 0.005,  -- 每个合资商行 → mu +0.5%
    stock_bonus_per_monopoly   = 0.008,  -- 每个垄断 → mu +0.8%
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
    lose_morale         = -14,
    lose_guards_ratio   = 0.18,  -- 战败损失 18% 护卫（原 30%，降低级联崩溃风险）
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
    -- 年龄与退休
    retirement_age         = 60,   -- 强制退休年龄
    trainee_age_min        = 20,   -- 新培养成员最小年龄
    trainee_age_max        = 35,   -- 新培养成员最大年龄
    retirement_warning_age = 55,   -- 退休预警年龄（UI 提示）
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
-- 免广告卡（看广告充能，每回合免广告重随）
-- ============================================================================
Balance.AD_FREE_CARD = {
    charge_ads_needed      = 10,  -- 充满需要看的广告次数
    free_lucky_per_turn    = 3,   -- 每回合免广告领广告金次数（匹配 LUCKY_EVENT.max_per_season）
    free_rerolls_per_turn  = 10,  -- 每回合免广告重随次数（匹配成员重随上限）
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
    industrial_consumption = { 0, 2, 4, 7, 10 },  -- 工业运营煤耗：矿山最高等级 Lv1~5 对应每季消耗
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

-- ============================================================================
-- 掠夺行动（武力掠夺发展路线）
-- ============================================================================
Balance.PLUNDER = {
    raid_caravan = {
        ap = 1, cash = 80, cooldown = 1, difficulty = 8,
        loot_min = 250, loot_max = 550, rep_cost = -5,
        fail_guard_loss = 1,
    },
    seize_vein = {
        ap = 2, cash = 120, cooldown = 3, difficulty = 14,
        vein_duration = 4, vein_gold_per_turn = 150, rep_cost = -15,
        fail_rep_extra = -10,
    },
    extort_foreign = {
        ap = 2, cash = 150, cooldown = 2, difficulty = 18,
        loot_min = 400, loot_max = 800, rep_cost = -10,
        fail_aggression_boost = 15,
    },
    success_floor = 0.15,
    success_ceil  = 0.90,
}

-- ============================================================================
-- 统一声誉系统（合并原掠夺声誉 + 贸易信誉 + 媒体公信力）
-- 范围 -100 ~ +100，初始 0
-- 正面区：贸易价格加成、路线安全加成、操盘成功率高
-- 负面区：贸易惩罚、AI攻击概率上升、操盘成功率低
-- ============================================================================
Balance.REPUTATION = {
    initial           = 0,
    min               = -100,
    max               = 100,
    recovery_per_turn = 2,    -- 每季自然恢复（向0靠拢，+2或-2）
    -- 负面等级阈值
    thresholds = {
        suspicious   = -10,   -- 可疑
        notorious    = -30,   -- 恶名
        infamous     = -50,   -- 臭名昭著
        public_enemy = -80,   -- 公敌
    },
    -- 各负面等级贸易溢价（索引 1~5 对应清白→公敌）
    trade_penalty    = { 0, 0.05, 0.15, 0.25, 0.40 },
    -- AI 攻击概率加成
    ai_attack_bonus  = { 0, 0, 0, 0.20, 0.50 },
    -- 公敌级别每季地区控制力衰减
    control_decay    = { 0, 0, 0, 0, 2 },
    -- 正面声誉效果（替代原贸易信誉）
    trade_order_bonus  = 0.005, -- 每点正声誉 → 订单报酬 +0.5%（满声誉+50%）
    trade_safety_bonus = 0.002, -- 每点正声誉 → 路线安全 +0.2%（满声誉+20%）
    -- 贸易事件对声誉的影响
    trade_success_bonus  = 1,   -- 贸易交付成功 声誉 +1
    trade_failure_penalty = -2, -- 贸易失败 声誉 -2
    -- 操盘公信力映射（替代原 CREDIBILITY）
    -- 操盘乘数 = floor + (1-floor) × clamp01((rep - min) / (max - min))
    -- rep=100 → ×1.0, rep=0 → ×0.75, rep=-100 → ×0.5
    market_multiplier_floor = 0.5,
    market_cost_pump        = 15,  -- Pump 成功扣减声誉
    market_cost_dump        = 20,  -- Dump 成功扣减声誉
    market_cost_coordinated = 30,  -- 联合操盘成功扣减声誉
    market_cost_fail_mult   = 1.5, -- 失败时扣减 ×1.5
    -- 新闻社持股加成恢复
    press_control_recovery_bonus   = 3,  -- 控股额外 +3/季
    press_influence_recovery_bonus = 1,  -- 重要持股额外 +1/季
    -- 主动恢复行动
    actions = {
        charity = {           -- 公益捐赠
            ap_cost  = 1,
            cash_cost = 500,
            rep_gain = 8,
            cooldown = 0,     -- 不限冷却，可连续使用
            label    = "公益捐赠",
            icon     = "🎗️",
            desc     = "向萨拉热窝社区捐赠资金，改善民众生活",
        },
        public_apology = {    -- 公开道歉
            ap_cost  = 2,
            cash_cost = 200,
            rep_gain = 15,
            cooldown = 4,     -- 4季冷却（年度）
            label    = "公开道歉",
            icon     = "📜",
            desc     = "在报纸上发表公开声明，承认过往过失并承诺改善",
        },
        community_project = { -- 社区建设
            ap_cost  = 2,
            cash_cost = 1500,
            rep_gain = 25,
            cooldown = 8,     -- 8季冷却（两年）
            label    = "社区建设",
            icon     = "🏗️",
            desc     = "投资建设医院、学校等公共设施，大幅提升声誉",
        },
    },
}

-- ============================================================================
-- 做空机制
-- ============================================================================
Balance.SHORT_SELLING = {
    max_short_pct   = 0.30,    -- 最大做空股数 = max_shares × 30%
    margin_ratio    = 0.50,    -- 保证金比例（冻结市值 × 50%）
    interest_rate   = 0.05,    -- 每季利息 5%（按当前市值）
    force_close_pct = 0.80,    -- 亏损 >= 保证金 × 80% 时强制平仓
    max_duration    = 8,       -- 最大持仓期（季度）
    -- 科技/顾问加成后的数值
    diplomat_interest       = 0.04,  -- diplomat bonus >= 0.5 → 利息降至 4%
    radio_max_pct           = 0.40,  -- d5_radio 已研究 → 最大做空提至 40%
    wartime_media_force_close = 0.90,-- d7_wartime_media 已研究 → 强平线放宽至 90%
    -- M3: 做空利息折扣从新闻社转移到银行信托（解耦新闻社操盘+做空自耦合）
    bank_influence_interest = 0.04,  -- 银行信托 >= influence → 利息降至 4%
    bank_control_interest   = 0.03,  -- 银行信托 >= control → 利息降至 3%
}

-- ============================================================================
-- 方向互斥（M2: 操盘方向锁，Pump/Dump 互斥，不影响普通买卖）
-- ============================================================================
Balance.DIRECTION_LOCK = {
    after_pump = 3,  -- Pump 成功后，3 季内不能对该股 Dump
    after_dump = 3,  -- Dump 成功后，3 季内不能对该股 Pump
}

-- (Balance.CREDIBILITY 已合并到 Balance.REPUTATION)

-- ============================================================================
-- 庄家操盘（市场操纵）
-- ============================================================================
Balance.MARKET_MANIPULATION = {
    pump = {
        ap           = 1,
        cost_ratio   = 0.15,    -- 目标股票当前市值 × 15% 的现金
        min_cash_base = 5000,   -- 基准资金门槛（×通胀因子动态调整，原固定 40000）
        base_success = 0.70,    -- 基础成功率 70%
        cooldown     = 2,       -- 冷却 2 季
        delta_mu     = 0.15,    -- 成功时 delta_mu
        duration     = 2,       -- 持续 2 季
        fail_loss    = 0.50,    -- 失败时资金损失 50%
        -- 前置：d3_newspaper + 新闻社 >= stake
    },
    dump = {
        ap           = 1,
        cost_ratio   = 0.20,    -- 目标股票当前市值 × 20% 的现金
        min_cash_base = 8000,   -- 基准资金门槛（×通胀因子动态调整，原固定 60000）
        base_success = 0.60,    -- 基础成功率 60%
        cooldown     = 3,       -- 冷却 3 季
        delta_mu     = -0.18,   -- 成功时 delta_mu
        duration     = 2,       -- 持续 2 季
        rebound_mu   = 0.06,    -- 成功后反弹 +0.06
        rebound_dur  = 1,       -- 反弹持续 1 季
        fail_loss    = 0.60,    -- 失败时资金损失 60%
        fail_rebound_mu  = 0.08,-- 失败时目标股反向上涨
        fail_rebound_dur = 1,   -- 失败反弹持续 1 季
        -- 前置：d5_radio + 新闻社 >= influence
    },
    coordinated = {
        ap           = 2,
        fixed_cost_base = 15000, -- 基准成本（×通胀因子动态调整，原固定 100000）
        base_success = 0.50,    -- 基础成功率 50%
        cooldown     = 5,       -- 冷却 5 季
        pump_mu      = 0.20,    -- 做多目标 delta_mu
        dump_mu      = -0.15,   -- 做空目标 delta_mu
        duration     = 2,       -- 持续 2 季
        fail_loss    = 0.70,    -- 失败时资金损失 70%
        fail_rep     = -5,      -- 失败时声誉 -5
        -- 前置：d7_wartime_media + 新闻社 >= control + 文化顾问 bonus >= 0.8
    },
    -- 外交总监在任时资金投入折扣
    diplomat_discount = {
        pump = 0.10,            -- 做多操盘资金降低 10%
        dump = 0.15,            -- 做空操盘资金降低 15%
    },
}

-- ============================================================================
-- M4: AI 对手盘（外资反向交易）
-- ============================================================================
Balance.AI_COUNTERPARTY = {
    min_foreign_cash   = 3000,      -- 外资现金低于此值不触发
    react_chance = {
        pump        = 0.30,         -- Pump 后 30% 基础反制概率
        dump        = 0.25,         -- Dump 后 25%
        coordinated = 0.45,         -- 联合操盘后 45%
    },
    counter_mu = {
        pump = -0.06,               -- 抵消做多约 30-40%
        dump =  0.05,               -- 抵消做空约 30%
    },
    counter_duration    = 2,        -- 反向 delta_mu 持续 2 季
    cash_scale_base     = 5000,     -- 外资现金 >= 此值达到基础概率
    cash_scale_max      = 15000,    -- 外资现金 >= 此值概率 x1.5
    counter_cost_ratio  = 0.05,     -- 反制消耗外资现金比例
    -- 与公信力联动: 实际概率 = base × cashScale × (2.0 - credMult)
    -- cred=100 → ×1.0（不加成），cred=0 → ×1.5（AI更容易识破）
}

return Balance
