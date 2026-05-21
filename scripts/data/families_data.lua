-- ============================================================================
-- 家族初始数据：3 名核心成员
-- 属性范围 1-10：管理(management) / 谋略(strategy) / 魅力(charisma) / 学识(knowledge) / 野心(ambition)
-- ============================================================================

local FamiliesData = {}

-- 立绘图片路径（assets/ 是资源根目录，路径从下一级开始）
FamiliesData.PORTRAITS = {
    -- 固定角色立绘
    patriarch   = "image/portraits/nikola.png",
    eldest_son  = "image/portraits/marko.png",
    niece       = "image/portraits/lina.png",
}

-- 学员/新成员立绘池
FamiliesData.PORTRAIT_POOL = {
    "image/portraits/pool_01.png",
    "image/portraits/pool_02.png",
    "image/portraits/pool_03.png",
    "image/portraits/pool_04.png",
    "image/portraits/pool_05.png",
    "image/portraits/pool_06.png",
    "image/portraits/pool_07.png",
    "image/portraits/pool_08.png",
}

-- ============================================================================
-- 天赋（每个成员出生时随机获得 1 个）
-- effect_kind: 供系统查询的效果标识
-- ============================================================================
FamiliesData.TRAITS = {
    {
        id          = "mine_intuition",
        name        = "矿脉直觉",
        icon        = "💎",
        desc        = "对矿脉走向有天生的判断力",
        effect_desc = "矿山产出 +10%",
        effect_kind = "mine_output_pct",
        effect_value = 0.10,
    },
    {
        id          = "iron_discipline",
        name        = "铁腕治军",
        icon        = "🛡️",
        desc        = "天生的军事领袖气质",
        effect_desc = "士气衰减减半",
        effect_kind = "morale_decay_mult",
        effect_value = 0.50,
    },
    {
        id          = "silver_tongue",
        name        = "巧舌如簧",
        icon        = "🗣️",
        desc        = "极具说服力的交涉天赋",
        effect_desc = "外交行动 AP -1",
        effect_kind = "diplomacy_ap_reduction",
        effect_value = 1,
    },
    {
        id          = "tax_expert",
        name        = "税务专家",
        icon        = "📊",
        desc        = "精通税务规划与避税手段",
        effect_desc = "税率 -3%",
        effect_kind = "tax_rate_reduction",
        effect_value = 0.03,
    },
    {
        id          = "tech_prodigy",
        name        = "技术奇才",
        icon        = "🔬",
        desc        = "对新技术有超乎常人的领悟力",
        effect_desc = "科研速度 +15%",
        effect_kind = "research_speed_pct",
        effect_value = 0.15,
    },
    {
        id          = "market_sense",
        name        = "市场嗅觉",
        icon        = "📈",
        desc        = "对市场波动有敏锐的直觉",
        effect_desc = "股票手续费 -20%",
        effect_kind = "stock_fee_reduction",
        effect_value = 0.20,
    },
}

-- ============================================================================
-- 缺陷（每个成员出生时随机获得 1 个）
-- ============================================================================
FamiliesData.FLAWS = {
    {
        id          = "extravagant",
        name        = "挥霍无度",
        icon        = "💸",
        desc        = "花钱大手大脚，增加家族开支",
        effect_desc = "维护费 +10%",
        effect_kind = "maintenance_pct",
        effect_value = 0.10,
    },
    {
        id          = "stubborn",
        name        = "刚愎自用",
        icon        = "😤",
        desc        = "固执己见，难以融入新岗位",
        effect_desc = "上岗磨合期 ×2",
        effect_kind = "onboarding_mult",
        effect_value = 2,
    },
    {
        id          = "frail",
        name        = "体弱多病",
        icon        = "🤒",
        desc        = "身体虚弱，年老后容易卧病不起",
        effect_desc = "55岁后每季 10% 概率暂离",
        effect_kind = "sick_chance_after_55",
        effect_value = 0.10,
    },
    {
        id          = "overconfident",
        name        = "眼高手低",
        icon        = "🎭",
        desc        = "高估自己的能力，实际表现打折",
        effect_desc = "岗位适配「优秀」降为「良好」",
        effect_kind = "downgrade_excellent",
        effect_value = 1,
    },
    {
        id          = "greedy",
        name        = "贪得无厌",
        icon        = "🪙",
        desc        = "贪婪成性，总想从中捞取好处",
        effect_desc = "腐败值 +3",
        effect_kind = "corruption_add",
        effect_value = 3,
    },
    {
        id          = "troublemaker",
        name        = "惹是生非",
        icon        = "⚡",
        desc        = "容易引发外交纠纷",
        effect_desc = "每季 5% 概率触发外交事件",
        effect_kind = "diplomacy_incident_chance",
        effect_value = 0.05,
    },
}

-- ============================================================================
-- 大学学位（科技 d6a_university 解锁后可进修，每人最多 2 个不同学位）
-- ============================================================================
FamiliesData.DEGREES = {
    {
        id          = "mining_engineering",
        name        = "采矿工程",
        icon        = "⛏️",
        desc        = "系统学习采矿理论与矿山管理",
        attr_bonus  = { management = 1 },
        effect_desc = "管理 +1，探矿速度 +10%",
        effect_kind = "prospect_speed_pct",
        effect_value = 0.10,
    },
    {
        id          = "military_academy",
        name        = "军事学院",
        icon        = "⚔️",
        desc        = "接受正规军事教育与战术训练",
        attr_bonus  = { strategy = 1 },
        effect_desc = "谋略 +1，战斗经验 +20%",
        effect_kind = "combat_exp_pct",
        effect_value = 0.20,
    },
    {
        id          = "diplomacy_school",
        name        = "外交学院",
        icon        = "🤝",
        desc        = "学习国际关系与外交礼仪",
        attr_bonus  = { charisma = 1 },
        effect_desc = "魅力 +1，合作度 +15%",
        effect_kind = "collaboration_pct",
        effect_value = 0.15,
    },
    {
        id          = "public_admin",
        name        = "公共管理",
        icon        = "🏛️",
        desc        = "研修行政管理与公共政策",
        attr_bonus  = { management = 1 },
        effect_desc = "管理 +1，控制度 +1/季",
        effect_kind = "control_per_season",
        effect_value = 1,
    },
    {
        id          = "engineering",
        name        = "理工学院",
        icon        = "🔧",
        desc        = "钻研工程技术与机械原理",
        attr_bonus  = { knowledge = 1 },
        effect_desc = "学识 +1，维修费 -15%",
        effect_kind = "repair_cost_reduction",
        effect_value = 0.15,
    },
    {
        id          = "business_school",
        name        = "商学院",
        icon        = "💼",
        desc        = "学习商业运营与贸易策略",
        attr_bonus  = { ambition = 1 },
        effect_desc = "野心 +1，贸易利润 +8%",
        effect_kind = "trade_profit_pct",
        effect_value = 0.08,
    },
}

-- ============================================================================
-- 天赋/缺陷快速查找
-- ============================================================================

--- 按 id 查找天赋定义
---@param traitId string
---@return table|nil
function FamiliesData.GetTraitDef(traitId)
    for _, t in ipairs(FamiliesData.TRAITS) do
        if t.id == traitId then return t end
    end
    return nil
end

--- 按 id 查找缺陷定义
---@param flawId string
---@return table|nil
function FamiliesData.GetFlawDef(flawId)
    for _, f in ipairs(FamiliesData.FLAWS) do
        if f.id == flawId then return f end
    end
    return nil
end

--- 按 id 查找学位定义
---@param degreeId string
---@return table|nil
function FamiliesData.GetDegreeDef(degreeId)
    for _, d in ipairs(FamiliesData.DEGREES) do
        if d.id == degreeId then return d end
    end
    return nil
end

--- 随机选取一个天赋 id（可排除指定 id）
---@param excludeIds table|nil 已有的天赋 id 列表
---@return string
function FamiliesData.RandomTraitId(excludeIds)
    local pool = {}
    local exSet = {}
    if excludeIds then
        for _, id in ipairs(excludeIds) do exSet[id] = true end
    end
    for _, t in ipairs(FamiliesData.TRAITS) do
        if not exSet[t.id] then table.insert(pool, t.id) end
    end
    if #pool == 0 then
        -- fallback: 全部可选
        return FamiliesData.TRAITS[math.random(#FamiliesData.TRAITS)].id
    end
    return pool[math.random(#pool)]
end

--- 随机选取一个缺陷 id（可排除指定 id）
---@param excludeIds table|nil 已有的缺陷 id 列表
---@return string
function FamiliesData.RandomFlawId(excludeIds)
    local pool = {}
    local exSet = {}
    if excludeIds then
        for _, id in ipairs(excludeIds) do exSet[id] = true end
    end
    for _, f in ipairs(FamiliesData.FLAWS) do
        if not exSet[f.id] then table.insert(pool, f.id) end
    end
    if #pool == 0 then
        return FamiliesData.FLAWS[math.random(#FamiliesData.FLAWS)].id
    end
    return pool[math.random(#pool)]
end

-- 已分配的池立绘索引（避免重复分配）
local usedPoolIndices_ = {}

--- 创建初始家族成员列表
---@return table[] members
function FamiliesData.CreateInitialMembers()
    return {
        -- 家主：均衡型，擅长管理和魅力
        {
            id = "patriarch",
            name = "尼古拉·科瓦奇",
            title = "家主",
            portrait = "👤",
            portraitImage = FamiliesData.PORTRAITS.patriarch,
            attrs = {
                management = 7,
                strategy   = 5,
                charisma   = 7,
                knowledge  = 5,
                ambition   = 6,
            },
            -- 隐藏倾向（不直接显示，通过事件结果暗示）
            hidden = {
                corruption = 2,  -- 1-10，越高越贪
                loyalty    = 9,  -- 1-10，越高越忠
                radical    = 3,  -- 1-10，越高越激进
            },
            trait = "mine_intuition",  -- 天赋：矿脉直觉
            flaw  = "stubborn",        -- 缺陷：刚愎自用
            degrees = {},              -- 已获学位列表
            position = nil,      -- 当前岗位 id
            status = "active",   -- active / disabled
            disabled_turns = 0,  -- 失能剩余回合
            age = 42,            -- 1904年时42岁（生于1862年）
            bio = "波黑中部金矿的前矿工领班，凭借过人的组织能力和人脉，在 1904 年获得了第一块矿权。为人稳重，深受矿工信任。",
        },

        -- 长子：偏军事和谋略
        {
            id = "eldest_son",
            name = "马尔科·科瓦奇",
            title = "长子",
            portrait = "🧑",
            portraitImage = FamiliesData.PORTRAITS.eldest_son,
            attrs = {
                management = 4,
                strategy   = 7,
                charisma   = 4,
                knowledge  = 3,
                ambition   = 7,
            },
            hidden = {
                corruption = 4,
                loyalty    = 7,
                radical    = 7,
            },
            trait = "iron_discipline",  -- 天赋：铁腕治军
            flaw  = "troublemaker",     -- 缺陷：惹是生非
            degrees = {},
            position = nil,
            status = "active",
            disabled_turns = 0,
            age = 24,            -- 1904年时24岁（生于1880年）
            bio = "性格果敢，善于筹划，年轻时在奥匈帝国边防军中服过短役。对家族的矿业前景充满野心，主张用武力保护矿区安全。",
        },

        -- 侄女：偏学识和文化
        {
            id = "niece",
            name = "莉娜·科瓦奇",
            title = "侄女",
            portrait = "👩",
            portraitImage = FamiliesData.PORTRAITS.niece,
            attrs = {
                management = 5,
                strategy   = 3,
                charisma   = 6,
                knowledge  = 8,
                ambition   = 4,
            },
            hidden = {
                corruption = 1,
                loyalty    = 8,
                radical    = 2,
            },
            trait = "tech_prodigy",  -- 天赋：技术奇才
            flaw  = "frail",         -- 缺陷：体弱多病
            degrees = {},
            position = nil,
            status = "active",
            disabled_turns = 0,
            age = 20,            -- 1904年时20岁（生于1884年）
            bio = "在萨拉热窝接受过正规教育，通晓德语和法语。对采矿技术和地质勘探有浓厚兴趣，也关注社会文化事业。",
        },
    }
end

--- 获取属性匹配评级
--- 双属性 >= 8 满配；双属性 >= 5 半配；任一属性 <= 4 差配。
---@param member table
---@param attr1 string 关键属性 1
---@param attr2 string 关键属性 2
---@return string rating "excellent" / "good" / "poor"
---@return number bonus 加成系数 (1.0 / 0.5 / -0.1)
function FamiliesData.GetPositionFit(member, attr1, attr2)
    local v1 = member.attrs[attr1] or 1
    local v2 = member.attrs[attr2] or 1

    if v1 >= 8 and v2 >= 8 then
        return "excellent", 1.0
    elseif v1 >= 5 and v2 >= 5 then
        return "good", 0.5
    elseif v1 <= 4 or v2 <= 4 then
        return "poor", -0.1
    end

    -- 一高一中或一高一低的成员仍能胜任，但无法拿到完整加成。
    return "good", 0.5
end

--- 获取隐藏倾向的可读线索，不直接暴露具体数值。
---@param member table
---@return string[]
function FamiliesData.GetHiddenTraitHints(member)
    local h = member.hidden or {}
    local hints = {}
    if (h.loyalty or 0) >= 8 then
        table.insert(hints, "可靠")
    elseif (h.loyalty or 10) <= 4 then
        table.insert(hints, "易动摇")
    end

    if (h.corruption or 0) >= 7 then
        table.insert(hints, "灰色倾向")
    elseif (h.corruption or 10) <= 2 then
        table.insert(hints, "清廉")
    end

    if (h.radical or 0) >= 7 then
        table.insert(hints, "激进")
    elseif (h.radical or 10) <= 3 then
        table.insert(hints, "稳健")
    end

    return hints
end

--- 计算成员在灰色经营、战时强硬、制度路线中的倾向值。
---@param member table
---@param kind string corruption|loyalty|radical
---@return number
function FamiliesData.GetHiddenValue(member, kind)
    return ((member.hidden or {})[kind]) or 0
end

--- 从立绘池中获取下一张可用立绘
---@return string|nil imagePath
function FamiliesData.AllocatePoolPortrait()
    for i = 1, #FamiliesData.PORTRAIT_POOL do
        if not usedPoolIndices_[i] then
            usedPoolIndices_[i] = true
            return FamiliesData.PORTRAIT_POOL[i]
        end
    end
    return nil  -- 池已耗尽
end

--- 标记某张池立绘为已使用（存档恢复时调用）
---@param imagePath string
function FamiliesData.MarkPoolPortraitUsed(imagePath)
    for i, path in ipairs(FamiliesData.PORTRAIT_POOL) do
        if path == imagePath then
            usedPoolIndices_[i] = true
            return
        end
    end
end

--- 查询某个池索引是否已被使用（peek，不修改状态）
---@param index number 池索引（1-based）
---@return boolean
function FamiliesData.IsPoolPortraitUsed(index)
    return usedPoolIndices_[index] == true
end

--- 释放某张池立绘，使其可被重新分配（成员永久离队时调用）
---@param imagePath string
function FamiliesData.ReleasePoolPortrait(imagePath)
    for i, path in ipairs(FamiliesData.PORTRAIT_POOL) do
        if path == imagePath then
            usedPoolIndices_[i] = nil
            return
        end
    end
end

-- 巴尔干风格随机名（男女混用）
local RANDOM_FIRST_NAMES = {
    "伊万", "斯特凡", "达沃尔", "米洛什", "佐兰",
    "德拉甘", "弗拉多", "安德烈", "鲍里斯", "彼得",
    "亚历山大", "托米斯拉夫", "布兰科", "杜尚", "米兰",
    "安娜", "伊万娜", "米莱娜", "达妮卡", "卡塔琳娜",
    "玛丽娅", "耶莱娜", "德拉加娜", "索菲娅", "柳比察",
}

--- 创建一个可培养的新成员模板。
---@param index number|nil
---@param existingNames table|nil 已有成员名列表，用于去重
---@return table
function FamiliesData.CreateTraineeTemplate(index, existingNames)
    index = index or math.random(1000, 9999)
    local function attr()
        return math.random(3, 8)
    end
    -- 名字去重：从池中排除已使用的名字
    local firstName
    if existingNames and #existingNames > 0 then
        local usedSet = {}
        for _, n in ipairs(existingNames) do
            -- 提取"·"前的名字部分
            local fn = n:match("^(.-)·") or n
            usedSet[fn] = true
        end
        local available = {}
        for _, fn in ipairs(RANDOM_FIRST_NAMES) do
            if not usedSet[fn] then
                table.insert(available, fn)
            end
        end
        if #available > 0 then
            firstName = available[math.random(#available)]
        else
            -- 池耗尽，加数字后缀避免重名
            firstName = RANDOM_FIRST_NAMES[math.random(#RANDOM_FIRST_NAMES)]
                .. tostring(math.random(10, 99))
        end
    else
        firstName = RANDOM_FIRST_NAMES[math.random(#RANDOM_FIRST_NAMES)]
    end
    local poolImage = FamiliesData.AllocatePoolPortrait()
    return {
        id = "trainee_" .. tostring(index),
        name = firstName .. "·科瓦奇",
        title = "家族新秀",
        portrait = "👥",
        portraitImage = poolImage,
        attrs = {
            management = attr(),
            strategy = attr(),
            charisma = attr(),
            knowledge = attr(),
            ambition = attr(),
        },
        hidden = {
            corruption = math.random(1, 7),
            loyalty = math.random(4, 9),
            radical = math.random(1, 8),
        },
        trait = FamiliesData.RandomTraitId(),
        flaw  = FamiliesData.RandomFlawId(),
        degrees = {},
        position = nil,
        status = "active",
        disabled_turns = 0,
        onboarding_remaining = 0,
        cooldown_turns = 0,
        reroll_available = 0,
        age = math.random(
            require("data.balance").FAMILY.trainee_age_min or 20,
            require("data.balance").FAMILY.trainee_age_max or 35
        ),
        bio = "通过家族培养进入核心圈层的新成员，能力与倾向会在长期经营中逐步显现。",
    }
end

--- 重随成员全部属性（看广告后调用）
---@param member table
function FamiliesData.RerollMemberAttrs(member)
    local function attr()
        return math.random(3, 8)
    end
    member.attrs = {
        management = attr(),
        strategy   = attr(),
        charisma   = attr(),
        knowledge  = attr(),
        ambition   = attr(),
    }
    member.hidden = {
        corruption = math.random(1, 7),
        loyalty    = math.random(4, 9),
        radical    = math.random(1, 8),
    }
end

return FamiliesData
