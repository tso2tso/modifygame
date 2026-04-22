-- ============================================================================
-- 家族初始数据：3 名核心成员
-- 属性范围 1-10：管理(management) / 谋略(strategy) / 魅力(charisma) / 学识(knowledge) / 野心(ambition)
-- ============================================================================

local FamiliesData = {}

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
            position = nil,      -- 当前岗位 id
            status = "active",   -- active / disabled
            disabled_turns = 0,  -- 失能剩余回合
            bio = "波黑中部金矿的前矿工领班，凭借过人的组织能力和人脉，在 1904 年获得了第一块矿权。为人稳重，深受矿工信任。",
        },

        -- 长子：偏军事和谋略
        {
            id = "eldest_son",
            name = "马尔科·科瓦奇",
            title = "长子",
            portrait = "🧑",
            attrs = {
                management = 4,
                strategy   = 8,
                charisma   = 4,
                knowledge  = 3,
                ambition   = 8,
            },
            hidden = {
                corruption = 4,
                loyalty    = 7,
                radical    = 7,
            },
            position = nil,
            status = "active",
            disabled_turns = 0,
            bio = "性格果敢，善于筹划，年轻时在奥匈帝国边防军中服过短役。对家族的矿业前景充满野心，主张用武力保护矿区安全。",
        },

        -- 侄女：偏学识和文化
        {
            id = "niece",
            name = "莉娜·科瓦奇",
            title = "侄女",
            portrait = "👩",
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
            position = nil,
            status = "active",
            disabled_turns = 0,
            bio = "在萨拉热窝接受过正规教育，通晓德语和法语。对采矿技术和地质勘探有浓厚兴趣，也关注社会文化事业。",
        },
    }
end

--- 获取属性匹配评级
--- 主属性 >= 7 满配, 5-6 半配, <= 4 负面
---@param member table
---@param attr1 string 主属性
---@param attr2 string 副属性
---@return string rating "excellent" / "good" / "poor"
---@return number bonus 加成系数 (1.0 / 0.5 / -0.1)
function FamiliesData.GetPositionFit(member, attr1, attr2)
    local v1 = member.attrs[attr1] or 1
    local v2 = member.attrs[attr2] or 1
    local primary = math.max(v1, v2)

    if primary >= 7 then
        return "excellent", 1.0
    elseif primary >= 5 then
        return "good", 0.5
    else
        return "poor", -0.1
    end
end

return FamiliesData
