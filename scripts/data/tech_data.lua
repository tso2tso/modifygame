-- ============================================================================
-- 科技研发数据表
-- 每项科技：id / name / icon / desc / cost / turns / effects
-- effects 是一个应用函数：Tech.Apply(state, tech) 会调用
-- ============================================================================

local TechData = {}

--- 获取所有可研发科技
---@return table[]
function TechData.GetAll()
    return {
        {
            id   = "steam_drill",
            name = "蒸汽钻机",
            icon = "⚙️",
            desc = "引入蒸汽钻机，提高矿山基础产出 +2 单位/季。",
            cost = 300,   turns = 3,
            requires = nil,
            effects = { kind = "mine_output_base", value = 2 },
        },
        {
            id   = "electric_mine",
            name = "电气化矿井",
            icon = "💡",
            desc = "矿井电气化改造，安全 +1，并降低事故概率。",
            cost = 500,   turns = 4,
            requires = "steam_drill",
            effects = { kind = "security_bonus", value = 1 },
        },
        {
            id   = "accounting",
            name = "现代会计学",
            icon = "📒",
            desc = "现代会计制度降低税负 -2%。",
            cost = 350,   turns = 3,
            requires = nil,
            effects = { kind = "tax_reduction", value = -0.02 },
        },
        {
            id   = "telegraph",
            name = "电报网络",
            icon = "📡",
            desc = "架设电报网络，基础 AP 上限 +1。",
            cost = 600,   turns = 4,
            requires = "accounting",
            effects = { kind = "ap_bonus", value = 1 },
        },
        {
            id   = "rifled_arms",
            name = "线膛步枪",
            icon = "🔫",
            desc = "装备线膛步枪，护卫装备等级 +1。",
            cost = 450,   turns = 3,
            requires = nil,
            effects = { kind = "equipment_up", value = 1 },
        },
        {
            id   = "logistics",
            name = "补给链管理",
            icon = "📦",
            desc = "优化后勤，每名护卫补给消耗降低。",
            cost = 400,   turns = 3,
            requires = "rifled_arms",
            effects = { kind = "supply_reduction", value = -1 },
        },
        {
            id   = "finance_net",
            name = "金融网络",
            icon = "💹",
            desc = "金融网络优化资金调度，军事补给成本 -20%，每季被动收入 +80。",
            cost = 700,   turns = 5,
            requires = "accounting",
            effects = { kind = "finance_network" },
        },
        {
            id   = "propaganda",
            name = "印刷宣传",
            icon = "🗞️",
            desc = "宣传机构提升影响力，每季 +2 地区影响力。",
            cost = 500,   turns = 4,
            requires = nil,
            effects = { kind = "influence_gain", value = 2 },
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
