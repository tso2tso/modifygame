-- ============================================================================
-- 装备与编队数据定义
-- ============================================================================

local EquipmentData = {}

-- ============================================================================
-- 装备目录
-- ============================================================================
EquipmentData.CATALOG = {
    rifle = {
        id = "rifle",
        name = "步枪",
        tier = 1,
        power_mul = 1.0,
        prod_turns = 0,    -- 默认装备，无需生产
        prod_cost = 0,
        maintenance = 5,
        icon = "🔫",
        desc = "标准制式步枪，护卫基础装备。",
    },
    improved_rifle = {
        id = "improved_rifle",
        name = "改良步枪",
        tier = 2,
        power_mul = 1.4,
        prod_turns = 2,
        prod_cost = 120,
        maintenance = 8,
        icon = "🎯",
        desc = "改进瞄准与弹药的步枪，射程和精度更高。",
    },
    mg = {
        id = "mg",
        name = "机枪",
        tier = 3,
        power_mul = 1.8,
        prod_turns = 3,
        prod_cost = 250,
        maintenance = 15,
        icon = "⚙️",
        desc = "重型制压火力，适合阵地防御和火力覆盖。",
    },
    mortar = {
        id = "mortar",
        name = "迫击炮",
        tier = 4,
        power_mul = 2.3,
        prod_turns = 4,
        prod_cost = 400,
        maintenance = 22,
        icon = "💣",
        desc = "间接火力支援武器，攻防兼备。",
    },
    motorized = {
        id = "motorized",
        name = "机动装备",
        tier = 5,
        power_mul = 3.0,
        prod_turns = 5,
        prod_cost = 650,
        maintenance = 35,
        icon = "🚗",
        desc = "摩托化载具与重武器，极大提升机动作战能力。",
    },
    elite_kit = {
        id = "elite_kit",
        name = "精锐套件",
        tier = 6,
        power_mul = 4.0,
        prod_turns = 6,
        prod_cost = 1000,
        maintenance = 50,
        icon = "⭐",
        desc = "最先进的单兵装备与通讯系统，全面碾压优势。",
    },
}

-- 按 tier 排序的装备 ID 列表（方便 UI 遍历）
EquipmentData.TIER_ORDER = { "rifle", "improved_rifle", "mg", "mortar", "motorized", "elite_kit" }

-- ============================================================================
-- 老兵等级
-- ============================================================================
EquipmentData.VETERANCY = {
    [0] = { name = "新兵", power_mul = 1.00, battles_required = 0 },
    [1] = { name = "老兵", power_mul = 1.15, battles_required = 2 },
    [2] = { name = "精锐", power_mul = 1.30, battles_required = 5 },
    [3] = { name = "王牌", power_mul = 1.50, battles_required = 10 },
}

-- ============================================================================
-- 装备耐久度对战力的影响
-- ============================================================================
---@param condition number 0-100
---@return number multiplier
function EquipmentData.GetConditionMul(condition)
    if condition >= 60 then return 1.0 end
    if condition >= 30 then return 0.7 end
    if condition > 0 then return 0.4 end
    return 0  -- 损毁
end

-- ============================================================================
-- 编队规则
-- ============================================================================
EquipmentData.SQUAD = {
    min_size = 3,         -- 编队最少人数
    max_size = 8,         -- 编队最多人数
    max_squads = 6,       -- 最大编队数
    unassigned_power = 0.6,  -- 未编队护卫战力系数
}

-- ============================================================================
-- 兵工厂配置
-- ============================================================================
EquipmentData.FACTORY = {
    levels = {
        [1] = { build_cost = 500, build_turns = 4, slots = 1, maintenance = 30 },
        [2] = { build_cost = 800, build_turns = 3, slots = 2, maintenance = 50 },
        [3] = { build_cost = 1200, build_turns = 3, slots = 3, maintenance = 80 },
    },
    max_level = 3,
}

-- ============================================================================
-- 代工配置
-- ============================================================================
EquipmentData.OUTSOURCE = {
    max_slots = 2,        -- 同时代工上限
    cost_multiplier = 1.6,  -- 成本 ×1.6
    time_bonus = 1,       -- 额外 +1 季
}

-- ============================================================================
-- 维修配置
-- ============================================================================
EquipmentData.REPAIR = {
    condition_per_turn = 40,  -- 每季恢复 40 耐久
    cost_ratio = 0.20,       -- 维修费 = 生产成本 × 20%
}

-- ============================================================================
-- 科技解锁映射：tech_id → 解锁的装备 ID
-- ============================================================================
EquipmentData.TECH_UNLOCK = {
    c1_rifled_arms   = "improved_rifle",
    c3_machine_gun   = "mg",
    c4a_fortification = "mortar",
    c4b_assault      = "mortar",
    c5_motorized     = "motorized",
    c7_elite_force   = "elite_kit",
}

-- ============================================================================
-- 辅助查询
-- ============================================================================

--- 获取装备数据
---@param equipId string
---@return table|nil
function EquipmentData.Get(equipId)
    return EquipmentData.CATALOG[equipId]
end

--- 检查装备是否已解锁（通过科技）
---@param state table
---@param equipId string
---@return boolean
function EquipmentData.IsUnlocked(state, equipId)
    if equipId == "rifle" then return true end  -- T1 始终可用
    local researched = state.tech and state.tech.researched or {}
    for techId, unlockEquipId in pairs(EquipmentData.TECH_UNLOCK) do
        if unlockEquipId == equipId and researched[techId] then
            return true
        end
    end
    return false
end

--- 获取所有已解锁装备列表
---@param state table
---@return table[] list
function EquipmentData.GetUnlockedList(state)
    local list = {}
    for _, eid in ipairs(EquipmentData.TIER_ORDER) do
        if EquipmentData.IsUnlocked(state, eid) then
            table.insert(list, EquipmentData.CATALOG[eid])
        end
    end
    return list
end

return EquipmentData
