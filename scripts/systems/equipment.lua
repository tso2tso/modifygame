-- ============================================================================
-- 装备与编队系统
-- 包含：编队 CRUD、装备分配、生产推进、维修、耐久衰减、老兵晋升
-- ============================================================================

local EquipmentData = require("data.equipment_data")
local GameState = require("game_state")

local SQUAD = EquipmentData.SQUAD
local FACTORY = EquipmentData.FACTORY
local OUTSOURCE = EquipmentData.OUTSOURCE
local REPAIR = EquipmentData.REPAIR
local CATALOG = EquipmentData.CATALOG

local Equipment = {}

--- 生成库存物品唯一 ID
local _nextInvUid = 0
local function genInvUid()
    _nextInvUid = _nextInvUid + 1
    return _nextInvUid
end

--- 确保库存物品有 uid（兼容旧存档）
---@param item table
local function ensureUid(item)
    if not item.uid then item.uid = genInvUid() end
end

--- 存档加载后重建 uid 计数器，避免与已有 uid 冲突
---@param state table
function Equipment.RebuildUidCounter(state)
    local maxUid = 0
    local m = state.military or {}
    for _, item in ipairs(m.inventory or {}) do
        if item.uid and item.uid > maxUid then maxUid = item.uid end
    end
    for _, item in ipairs(m.production_queue or {}) do
        if item.inv_uid and item.inv_uid > maxUid then maxUid = item.inv_uid end
    end
    _nextInvUid = maxUid
end

-- ============================================================================
-- 编队管理
-- ============================================================================

--- 获取已编队的护卫总人数
---@param state table
---@return number
function Equipment.GetAssignedGuards(state)
    local total = 0
    for _, sq in ipairs(state.military.squads or {}) do
        total = total + sq.size
    end
    return total
end

--- 获取未编队的护卫人数
---@param state table
---@return number
function Equipment.GetUnassignedGuards(state)
    return math.max(0, state.military.guards - Equipment.GetAssignedGuards(state))
end

--- 生成下一个编队 ID
---@param state table
---@return number
local function nextSquadId(state)
    local maxId = 0
    for _, sq in ipairs(state.military.squads or {}) do
        if sq.id > maxId then maxId = sq.id end
    end
    return maxId + 1
end

local SQUAD_NAMES = { "第一大队", "第二大队", "第三大队", "第四大队", "第五大队", "第六大队" }

--- 创建新编队
---@param state table
---@param size number 人数
---@param name string|nil 自定义名称
---@return boolean ok
---@return string msg
function Equipment.CreateSquad(state, size, name)
    local m = state.military
    m.squads = m.squads or {}

    if #m.squads >= SQUAD.max_squads then
        return false, "编队数已达上限（" .. SQUAD.max_squads .. "）"
    end
    if size < SQUAD.min_size then
        return false, "编队最少需要 " .. SQUAD.min_size .. " 人"
    end
    if size > SQUAD.max_size then
        return false, "编队最多 " .. SQUAD.max_size .. " 人"
    end
    local unassigned = Equipment.GetUnassignedGuards(state)
    if unassigned < size then
        return false, "未编队护卫不足（可用 " .. unassigned .. " 人）"
    end

    local id = nextSquadId(state)
    local squadName = name or SQUAD_NAMES[#m.squads + 1] or ("编队" .. id)
    table.insert(m.squads, {
        id = id,
        name = squadName,
        size = size,
        equip_id = "rifle",  -- 默认 T1
        veterancy = 0,
        condition = 100,
        battles = 0,
    })

    return true, "已创建 " .. squadName .. "（" .. size .. " 人）"
end

--- 解散编队（人员回归未编队，装备回归库存）
---@param state table
---@param squadId number
---@return boolean ok
---@return string msg
function Equipment.DisbandSquad(state, squadId)
    local m = state.military
    for i, sq in ipairs(m.squads or {}) do
        if sq.id == squadId then
            -- 非默认装备回库存
            if sq.equip_id ~= "rifle" then
                m.inventory = m.inventory or {}
                local invItem = { equip_id = sq.equip_id, condition = sq.condition, uid = genInvUid() }
                table.insert(m.inventory, invItem)
            end
            local name = sq.name
            table.remove(m.squads, i)
            return true, name .. " 已解散"
        end
    end
    return false, "编队不存在"
end

--- 调整编队人数
---@param state table
---@param squadId number
---@param newSize number
---@return boolean ok
---@return string msg
function Equipment.ResizeSquad(state, squadId, newSize)
    local m = state.military
    for _, sq in ipairs(m.squads or {}) do
        if sq.id == squadId then
            if newSize < SQUAD.min_size then
                return false, "编队最少 " .. SQUAD.min_size .. " 人"
            end
            if newSize > SQUAD.max_size then
                return false, "编队最多 " .. SQUAD.max_size .. " 人"
            end
            if newSize > sq.size then
                local need = newSize - sq.size
                local avail = Equipment.GetUnassignedGuards(state)
                if avail < need then
                    return false, "未编队护卫不足（需要 " .. need .. "，可用 " .. avail .. "）"
                end
            end
            local oldSize = sq.size
            sq.size = newSize
            return true, sq.name .. ": " .. oldSize .. " → " .. newSize .. " 人"
        end
    end
    return false, "编队不存在"
end

--- 为编队分配装备（从库存中取出）
---@param state table
---@param squadId number
---@param equipId string
---@return boolean ok
---@return string msg
function Equipment.AssignEquipment(state, squadId, equipId)
    local m = state.military
    local squad = nil
    for _, sq in ipairs(m.squads or {}) do
        if sq.id == squadId then squad = sq; break end
    end
    if not squad then return false, "编队不存在" end

    local equipData = CATALOG[equipId]
    if not equipData then return false, "装备不存在" end

    if not EquipmentData.IsUnlocked(state, equipId) then
        return false, equipData.name .. " 尚未解锁"
    end

    -- 如果要换的装备与当前相同，跳过
    if squad.equip_id == equipId then
        return false, "已装备 " .. equipData.name
    end

    -- 从库存中找到该装备（优先选最高耐久 + 非维修中）
    m.inventory = m.inventory or {}
    local invIdx = nil
    local invItem = nil
    for i, item in ipairs(m.inventory) do
        ensureUid(item)
        if item.equip_id == equipId and not item.repairing then
            if not invItem or item.condition > invItem.condition then
                invIdx = i
                invItem = item
            end
        end
    end

    if equipId ~= "rifle" and not invIdx then
        return false, equipData.name .. " 库存不足"
    end

    -- 当前装备退回库存（非步枪）
    if squad.equip_id ~= "rifle" then
        local retItem = { equip_id = squad.equip_id, condition = squad.condition, uid = genInvUid() }
        table.insert(m.inventory, retItem)
    end

    -- 装备新武器
    if invIdx then
        squad.equip_id = invItem.equip_id
        squad.condition = invItem.condition
        table.remove(m.inventory, invIdx)
    else
        -- rifle 不需要库存
        squad.equip_id = "rifle"
        squad.condition = 100
    end

    return true, squad.name .. " 装备了 " .. equipData.name
end

-- ============================================================================
-- 生产系统
-- ============================================================================

--- 获取工厂当前可用生产槽位数
---@param state table
---@return number
function Equipment.GetFactoryFreeSlots(state)
    local m = state.military
    if not m.factory or not m.factory.level then return 0 end
    if m.factory.building then return 0 end -- 正在建造/升级中
    local levelData = FACTORY.levels[m.factory.level]
    if not levelData then return 0 end
    local used = 0
    for _, item in ipairs(m.production_queue or {}) do
        used = used + 1
    end
    return math.max(0, levelData.slots - used)
end

--- 获取代工可用槽位数
---@param state table
---@return number
function Equipment.GetOutsourceFreeSlots(state)
    local m = state.military
    local used = #(m.outsource_slots or {})
    return math.max(0, OUTSOURCE.max_slots - used)
end

--- 建造兵工厂
---@param state table
---@return boolean ok
---@return string msg
function Equipment.BuildFactory(state)
    local m = state.military
    if m.factory and m.factory.level and not m.factory.building then
        return false, "兵工厂已存在（Lv" .. m.factory.level .. "）"
    end
    if m.factory and m.factory.building then
        return false, "兵工厂正在建造中"
    end
    local levelData = FACTORY.levels[1]
    local cost = math.floor(levelData.build_cost * GameState.GetInflationFactor(state))
    if state.cash < cost then
        return false, "现金不足（需要 " .. cost .. "）"
    end
    state.cash = state.cash - cost
    m.factory = {
        level = 0,  -- 建造中为 0
        building = { progress = 0, total = levelData.build_turns, target_level = 1 },
    }
    return true, "开始建造兵工厂 Lv1（" .. levelData.build_turns .. " 季）"
end

--- 升级兵工厂
---@param state table
---@return boolean ok
---@return string msg
function Equipment.UpgradeFactory(state)
    local m = state.military
    if not m.factory or not m.factory.level or m.factory.level < 1 then
        return false, "请先建造兵工厂"
    end
    if m.factory.building then
        return false, "兵工厂正在建造/升级中"
    end
    local nextLevel = m.factory.level + 1
    if nextLevel > FACTORY.max_level then
        return false, "兵工厂已满级"
    end
    -- 检查科技解锁
    -- Lv2 需要工业化科技(暂用 b3), Lv3 需要重工业科技(暂用 b5)
    -- 注意：具体科技 ID 在 P4 阶段对接
    local levelData = FACTORY.levels[nextLevel]
    local cost = math.floor(levelData.build_cost * GameState.GetInflationFactor(state))
    if state.cash < cost then
        return false, "现金不足（需要 " .. cost .. "）"
    end
    state.cash = state.cash - cost
    m.factory.building = { progress = 0, total = levelData.build_turns, target_level = nextLevel }
    return true, "开始升级兵工厂至 Lv" .. nextLevel .. "（" .. levelData.build_turns .. " 季）"
end

--- 开始生产装备（工厂）
---@param state table
---@param equipId string
---@return boolean ok
---@return string msg
function Equipment.StartProduction(state, equipId)
    local m = state.military
    local equipData = CATALOG[equipId]
    if not equipData then return false, "装备不存在" end
    if equipId == "rifle" then return false, "步枪无需生产" end
    if not EquipmentData.IsUnlocked(state, equipId) then
        return false, equipData.name .. " 尚未解锁"
    end
    if Equipment.GetFactoryFreeSlots(state) < 1 then
        return false, "工厂无空闲槽位"
    end
    local cost = math.floor(equipData.prod_cost * GameState.GetInflationFactor(state))
    if state.cash < cost then
        return false, "现金不足（需要 " .. cost .. "）"
    end
    state.cash = state.cash - cost
    m.production_queue = m.production_queue or {}
    table.insert(m.production_queue, {
        equip_id = equipId,
        progress = 0,
        total = equipData.prod_turns,
        source = "factory",
    })
    return true, "开始生产 " .. equipData.name .. "（" .. equipData.prod_turns .. " 季）"
end

--- 开始代工装备
---@param state table
---@param equipId string
---@return boolean ok
---@return string msg
function Equipment.StartOutsource(state, equipId)
    local m = state.military
    local equipData = CATALOG[equipId]
    if not equipData then return false, "装备不存在" end
    if equipId == "rifle" then return false, "步枪无需生产" end
    if not EquipmentData.IsUnlocked(state, equipId) then
        return false, equipData.name .. " 尚未解锁"
    end
    if Equipment.GetOutsourceFreeSlots(state) < 1 then
        return false, "代工槽位已满"
    end
    local cost = math.floor(equipData.prod_cost * OUTSOURCE.cost_multiplier * GameState.GetInflationFactor(state))
    if state.cash < cost then
        return false, "现金不足（需要 " .. cost .. "）"
    end
    state.cash = state.cash - cost
    m.outsource_slots = m.outsource_slots or {}
    local totalTurns = equipData.prod_turns + OUTSOURCE.time_bonus
    table.insert(m.outsource_slots, {
        equip_id = equipId,
        progress = 0,
        total = totalTurns,
        source = "outsource",
    })
    return true, "代工 " .. equipData.name .. "（" .. totalTurns .. " 季，+60% 成本）"
end

--- 开始维修装备（从库存中选择，占用工厂槽位）
---@param state table
---@param invIndex number 库存中的索引
---@return boolean ok
---@return string msg
function Equipment.StartRepair(state, invIndex)
    local m = state.military
    m.inventory = m.inventory or {}
    local item = m.inventory[invIndex]
    if not item then return false, "库存装备不存在" end
    if item.repairing then return false, "装备正在维修中" end
    if item.condition >= 100 then return false, "装备无需维修" end
    if Equipment.GetFactoryFreeSlots(state) < 1 then
        return false, "工厂无空闲槽位"
    end
    local equipData = CATALOG[item.equip_id]
    if not equipData then return false, "装备数据异常" end
    local cost = math.floor(equipData.prod_cost * REPAIR.cost_ratio * GameState.GetInflationFactor(state))
    if state.cash < cost then
        return false, "现金不足（需要 " .. cost .. "）"
    end
    state.cash = state.cash - cost
    -- 确保有 uid，标记维修中
    ensureUid(item)
    item.repairing = true
    m.production_queue = m.production_queue or {}
    table.insert(m.production_queue, {
        equip_id = item.equip_id,
        progress = 0,
        total = 1,  -- 维修固定 1 季
        source = "repair",
        inv_uid = item.uid,  -- 通过 uid 追踪，不受数组索引变动影响
        repair_condition = item.condition,  -- 当前耐久
    })
    return true, "开始维修 " .. equipData.name .. "（1 季）"
end

-- ============================================================================
-- 每季推进（由 turn_engine 调用）
-- ============================================================================

--- 推进生产队列和兵工厂建造
---@param state table
---@return string[] messages
function Equipment.TickProduction(state)
    local m = state.military
    local messages = {}

    -- 推进兵工厂建造/升级
    if m.factory and m.factory.building then
        local b = m.factory.building
        b.progress = b.progress + 1
        if b.progress >= b.total then
            m.factory.level = b.target_level
            m.factory.building = nil
            table.insert(messages, "兵工厂升级至 Lv" .. m.factory.level .. " 完成")
        end
    end

    -- 推进工厂生产队列
    m.production_queue = m.production_queue or {}
    local keptQueue = {}
    for _, item in ipairs(m.production_queue) do
        item.progress = item.progress + 1
        if item.progress >= item.total then
            if item.source == "repair" then
                -- 维修完成：通过 uid 查找库存物品
                local invItem = nil
                for _, inv in ipairs(m.inventory or {}) do
                    if inv.uid and inv.uid == item.inv_uid then
                        invItem = inv
                        break
                    end
                end
                if invItem then
                    invItem.condition = math.min(100, (item.repair_condition or 0) + REPAIR.condition_per_turn)
                    invItem.repairing = nil
                    local ed = CATALOG[item.equip_id]
                    table.insert(messages, (ed and ed.name or item.equip_id) .. " 维修完成（耐久 " .. invItem.condition .. "）")
                end
            else
                -- 生产完成 → 进入库存
                m.inventory = m.inventory or {}
                table.insert(m.inventory, { equip_id = item.equip_id, condition = 100, uid = genInvUid() })
                local ed = CATALOG[item.equip_id]
                table.insert(messages, (ed and ed.name or item.equip_id) .. " 生产完成，已入库")
            end
        else
            table.insert(keptQueue, item)
        end
    end
    m.production_queue = keptQueue

    -- 推进代工槽位
    m.outsource_slots = m.outsource_slots or {}
    local keptOutsource = {}
    for _, item in ipairs(m.outsource_slots) do
        item.progress = item.progress + 1
        if item.progress >= item.total then
            m.inventory = m.inventory or {}
            table.insert(m.inventory, { equip_id = item.equip_id, condition = 100, uid = genInvUid() })
            local ed = CATALOG[item.equip_id]
            table.insert(messages, (ed and ed.name or item.equip_id) .. " 代工完成，已入库")
        else
            table.insert(keptOutsource, item)
        end
    end
    m.outsource_slots = keptOutsource

    return messages
end

--- 战斗后处理：耐久衰减 + 老兵经验
---@param state table
---@param participatingSquadIds number[]|nil 参与战斗的编队（nil=全部）
function Equipment.OnBattleEnd(state, participatingSquadIds)
    local m = state.military
    for _, sq in ipairs(m.squads or {}) do
        local participated = true
        if participatingSquadIds then
            participated = false
            for _, sid in ipairs(participatingSquadIds) do
                if sid == sq.id then participated = true; break end
            end
        end

        if participated then
            -- 耐久衰减 10-20（T1 步枪不衰减）
            if sq.equip_id ~= "rifle" then
                local wear = 10 + math.random(0, 10)
                sq.condition = math.max(0, sq.condition - wear)
                -- 损毁 → 退回 T1
                if sq.condition <= 0 then
                    sq.equip_id = "rifle"
                    sq.condition = 100
                end
            end

            -- 老兵经验
            sq.battles = (sq.battles or 0) + 1
            local vet = EquipmentData.VETERANCY
            if sq.veterancy < 3 then
                local nextLevel = sq.veterancy + 1
                local nextData = vet[nextLevel]
                if nextData and sq.battles >= nextData.battles_required then
                    sq.veterancy = nextLevel
                end
            end
        end
    end
end

--- 战斗减员处理：从编队中扣除阵亡人数
--- 优先从最大编队中扣除，低于最小人数的编队自动解散
---@param state table
---@param lostGuards number 阵亡护卫数
function Equipment.OnGuardsLost(state, lostGuards)
    local m = state.military
    if not m.squads or #m.squads == 0 then return end

    local remaining = lostGuards
    -- 先从未编队护卫中扣
    local unassigned = Equipment.GetUnassignedGuards(state)
    if unassigned > 0 then
        local fromUnassigned = math.min(unassigned, remaining)
        remaining = remaining - fromUnassigned
    end

    -- 再从编队中按人数从大到小扣
    if remaining > 0 then
        table.sort(m.squads, function(a, b) return a.size > b.size end)
        for _, sq in ipairs(m.squads) do
            if remaining <= 0 then break end
            local loss = math.min(sq.size, remaining)
            sq.size = sq.size - loss
            remaining = remaining - loss
        end
    end

    -- 清理人数不足的编队
    local kept = {}
    for _, sq in ipairs(m.squads) do
        if sq.size >= SQUAD.min_size then
            table.insert(kept, sq)
        else
            -- 装备回库存
            if sq.equip_id ~= "rifle" then
                m.inventory = m.inventory or {}
                table.insert(m.inventory, { equip_id = sq.equip_id, condition = sq.condition, uid = genInvUid() })
            end
        end
    end
    m.squads = kept
end

-- ============================================================================
-- 战力计算辅助
-- ============================================================================

--- 计算单个编队的战力
---@param squad table
---@return number power
function Equipment.CalcSquadPower(squad)
    local equipData = CATALOG[squad.equip_id] or CATALOG.rifle
    local vetData = EquipmentData.VETERANCY[squad.veterancy] or EquipmentData.VETERANCY[0]
    local condMul = EquipmentData.GetConditionMul(squad.condition or 100)
    return squad.size * equipData.power_mul * vetData.power_mul * condMul
end

--- 计算装备胜利分（方案B）
---@param state table
---@return number equipScore
---@return number veterancyScore
function Equipment.CalcVictoryScores(state)
    local m = state.military
    local BVM = require("data.balance").VICTORY.military

    -- 装备分: min(cap, Σ(tier-1) × multiplier)
    local rawEquipScore = 0
    for _, sq in ipairs(m.squads or {}) do
        local ed = CATALOG[sq.equip_id]
        if ed then
            rawEquipScore = rawEquipScore + (ed.tier - 1) * (BVM.equip_tier_multiplier or 0.8)
        end
    end
    local equipScore = math.min(BVM.equip_score_cap or 4, math.floor(rawEquipScore))

    -- 老兵分: min(cap, 王牌编队数 × 1)
    local aceCount = 0
    for _, sq in ipairs(m.squads or {}) do
        if sq.veterancy >= 3 then aceCount = aceCount + 1 end
    end
    local veterancyScore = math.min(BVM.veterancy_score_cap or 2, aceCount)

    return equipScore, veterancyScore
end

--- 计算装备维护总费用（每季）
---@param state table
---@return number equipMaint 装备维护费
---@return number factoryMaint 工厂维护费
function Equipment.CalcMaintenanceCost(state)
    local m = state.military
    local inflation = GameState.GetInflationFactor(state)
    local equipMaint = 0

    -- 编队装备维护
    for _, sq in ipairs(m.squads or {}) do
        local ed = CATALOG[sq.equip_id]
        if ed then
            equipMaint = equipMaint + ed.maintenance
        end
    end
    -- 库存装备维护（半价）
    for _, item in ipairs(m.inventory or {}) do
        local ed = CATALOG[item.equip_id]
        if ed then
            equipMaint = equipMaint + math.floor(ed.maintenance * 0.5)
        end
    end
    equipMaint = math.floor(equipMaint * inflation)

    -- 工厂维护
    local factoryMaint = 0
    if m.factory and m.factory.level and m.factory.level > 0 then
        local levelData = FACTORY.levels[m.factory.level]
        if levelData then
            factoryMaint = math.floor(levelData.maintenance * inflation)
        end
    end

    return equipMaint, factoryMaint
end

return Equipment
