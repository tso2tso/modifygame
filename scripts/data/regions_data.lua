-- ============================================================================
-- 地区节点数据：3 个初始节点（矿山区 / 工业城 / 首都）
-- ============================================================================

local RegionsData = {}

--- 创建初始地区节点
---@return table[] regions
function RegionsData.CreateInitialRegions()
    return {
        {
            id = "mine_district",
            name = "巴科维奇矿区",
            icon = "⛏️",
            type = "mine",
            desc = "波黑中部山区的金银矿脉，家族起家之地。矿脉品质优良但交通不便，需要稳定的劳工和护矿力量。",
            -- 资源与产能
            resources = {
                gold_reserve  = 200,   -- 黄金储量（单位）
                silver_reserve = 500,  -- 白银储量
                base_output   = 2,     -- 基础每季产金量
            },
            -- 地区属性
            security    = 3,     -- 治安等级 1-5（3=普通）
            development = 1,     -- 基建水平 1-5
            population  = 800,   -- 劳动力规模
            policy      = "neutral", -- 政策环境
            culture     = 0,     -- 文化价值
            -- 控制状态
            control     = 80,    -- 玩家控制度 0-100
            influence   = 0,     -- 地区影响力（科技/事件累积）
            ai_presence = {      -- AI 势力存在
                local_clan = 15,
                foreign_capital = 5,
            },
        },

        {
            id = "industrial_town",
            name = "泽尼察工业区",
            icon = "🏭",
            type = "industrial",
            desc = "波黑重要的工业重镇，有冶炼设施和铁路连接。适合发展加工业和军需生产，但竞争激烈。",
            resources = {
                coal_reserve   = 1000,
                steel_capacity = 0,    -- 初始无钢铁产能，需投资建设
                base_output    = 0,
            },
            security    = 4,
            development = 2,
            population  = 3000,
            policy      = "neutral",
            culture     = 5,
            control     = 20,
            influence   = 0,     -- 地区影响力
            ai_presence = {
                local_clan = 30,
                foreign_capital = 25,
            },
        },

        {
            id = "capital_city",
            name = "萨拉热窝",
            icon = "🏛️",
            type = "capital",
            desc = "波黑首府，多民族多宗教聚居的文化名城。政治与外交行动的核心节点，也是文化路线的关键战场。",
            resources = {
                gold_reserve   = 0,
                silver_reserve = 0,
                base_output    = 0,
            },
            security    = 4,
            development = 3,
            population  = 50000,
            policy      = "regulated",
            culture     = 20,
            control     = 5,
            influence   = 0,     -- 地区影响力
            ai_presence = {
                local_clan = 20,
                foreign_capital = 35,
            },
        },
    }
end

--- 获取治安等级描述
---@param level number 1-5
---@return string
function RegionsData.GetSecurityText(level)
    local texts = {
        [1] = "极度危险",
        [2] = "动荡不安",
        [3] = "勉强维持",
        [4] = "基本稳定",
        [5] = "秩序良好",
    }
    return texts[level] or "未知"
end

--- 获取基建等级描述
---@param level number 1-5
---@return string
function RegionsData.GetDevelopmentText(level)
    local texts = {
        [1] = "荒芜",
        [2] = "初步建设",
        [3] = "基础完善",
        [4] = "设施齐全",
        [5] = "高度发达",
    }
    return texts[level] or "未知"
end

return RegionsData
