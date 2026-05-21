-- ============================================================================
-- 装备与编队系统
-- 包含：编队 CRUD、装备分配、生产推进、维修、耐久衰减、老兵晋升
-- ============================================================================

local EquipmentData = require("data.equipment_data")
local GameState = require("game_state")
local Balance = require("data.balance")
local BCOPPER = Balance.COPPER

local SQUAD = EquipmentData.SQUAD
local FACTORY = EquipmentData.FACTORY
local OUTSOURCE = EquipmentData.OUTSOURCE
local REPAIR = EquipmentData.REPAIR
local CATALOG = EquipmentData.CATALOG
local SUPPORT_CATALOG = EquipmentData.SUPPORT_CATALOG

local Equipment = {}

--- 生成库存物品唯一 ID
local _nextInvUid = 0
local function genInvUid()
    _nextInvUid = _nextInvUid + 1
    return _nextInvUid
end

--- 计算编队在给定人数下所需装备件数
--- rifle 不消耗库存，返回 0；其他装备按 coverage 字段计算 ceil(size / coverage)
---@param equipId string
---@param size number
---@return number
local function calcNeededCount(equipId, size)
    if equipId == "rifle" then return 0 end
    local ed = CATALOG[equipId]
    if not ed or not ed.coverage then return 1 end  -- 兼容：无 coverage 字段按1件
    return math.ceil(size / ed.coverage)
end

--- 从编队的 equip_items 数组更新 squad.condition 为平均耐久（向下兼容 UI 读取）
---@param squad table
local function syncSquadCondition(squad)
    if not squad.equip_items or #squad.equip_items == 0 then
        squad.condition = 100
        return
    end
    local total = 0
    for _, ei in ipairs(squad.equip_items) do
        total = total + ei.condition
    end
    squad.condition = math.floor(total / #squad.equip_items)
end

--- 确保库存物品有 uid（兼容旧存档）
---@param item table
local function ensureUid(item)
    if not item.uid then item.uid = genInvUid() end
end

--- 查找装备数据（主武器或支援装备统一查找）
---@param equipId string
---@return table|nil data
---@return boolean isSupport
local function lookupEquipData(equipId)
    local d = CATALOG[equipId]
    if d then return d, false end
    d = SUPPORT_CATALOG[equipId]
    if d then return d, true end
    return nil, false
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
    -- 扫描编队装备项的 uid
    for _, sq in ipairs(m.squads or {}) do
        if sq.equip_items then
            for _, ei in ipairs(sq.equip_items) do
                if ei.uid and ei.uid > maxUid then maxUid = ei.uid end
            end
        end
        -- 扫描支援装备 uid
        if sq.support_equip_uid and sq.support_equip_uid > maxUid then
            maxUid = sq.support_equip_uid
        end
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
            -- 非默认装备回库存（按 equip_items 逐件退回）
            if sq.equip_id ~= "rifle" then
                m.inventory = m.inventory or {}
                if sq.equip_items and #sq.equip_items > 0 then
                    for _, ei in ipairs(sq.equip_items) do
                        table.insert(m.inventory, { equip_id = sq.equip_id, condition = ei.condition, uid = genInvUid() })
                    end
                else
                    -- 兼容旧存档：无 equip_items 时退回 1 件
                    table.insert(m.inventory, { equip_id = sq.equip_id, condition = sq.condition, uid = genInvUid() })
                end
            end
            -- 支援装备回库存
            if sq.support_equip_id then
                m.inventory = m.inventory or {}
                table.insert(m.inventory, {
                    equip_id = sq.support_equip_id,
                    condition = sq.support_equip_condition or 100,
                    uid = genInvUid(),
                })
            end
            local name = sq.name
            table.remove(m.squads, i)
            return true, name .. " 已解散"
        end
    end
    return false, "编队不存在"
end

--- 调整编队人数（扩编时自动从库存补充武器，缩编时退回多余武器）
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

            -- 检查扩编后是否需要更多武器
            if sq.equip_id ~= "rifle" then
                local oldNeeded = calcNeededCount(sq.equip_id, sq.size)
                local newNeeded = calcNeededCount(sq.equip_id, newSize)
                m.inventory = m.inventory or {}

                if newNeeded > oldNeeded then
                    -- 扩编：需要从库存补充武器
                    local extraNeeded = newNeeded - oldNeeded
                    -- 检查库存是否充足
                    local availCount = 0
                    for _, item in ipairs(m.inventory) do
                        if item.equip_id == sq.equip_id and not item.repairing then
                            availCount = availCount + 1
                        end
                    end
                    if availCount < extraNeeded then
                        local ed = CATALOG[sq.equip_id]
                        return false, (ed and ed.name or sq.equip_id) .. " 库存不足（需补充 " .. extraNeeded .. "，库存 " .. availCount .. "）"
                    end
                    -- 从库存取出（优先高耐久）
                    sq.equip_items = sq.equip_items or {}
                    local taken = 0
                    -- 按耐久排序后取
                    local candidates = {}
                    for i, item in ipairs(m.inventory) do
                        ensureUid(item)
                        if item.equip_id == sq.equip_id and not item.repairing then
                            table.insert(candidates, { idx = i, item = item })
                        end
                    end
                    table.sort(candidates, function(a, b) return a.item.condition > b.item.condition end)
                    local removeIndices = {}
                    for _, c in ipairs(candidates) do
                        if taken >= extraNeeded then break end
                        table.insert(sq.equip_items, { condition = c.item.condition, uid = genInvUid() })
                        table.insert(removeIndices, c.idx)
                        taken = taken + 1
                    end
                    -- 从库存移除（倒序避免索引偏移）
                    table.sort(removeIndices, function(a, b) return a > b end)
                    for _, idx in ipairs(removeIndices) do
                        table.remove(m.inventory, idx)
                    end
                    syncSquadCondition(sq)
                elseif newNeeded < oldNeeded then
                    -- 缩编：退回多余武器到库存
                    if sq.equip_items and #sq.equip_items > 0 then
                        local excessCount = oldNeeded - newNeeded
                        -- 退回耐久最低的
                        table.sort(sq.equip_items, function(a, b) return a.condition < b.condition end)
                        for _ = 1, excessCount do
                            if #sq.equip_items == 0 then break end
                            local ei = table.remove(sq.equip_items, 1)
                            table.insert(m.inventory, { equip_id = sq.equip_id, condition = ei.condition, uid = genInvUid() })
                        end
                        syncSquadCondition(sq)
                    end
                end
            end

            local oldSize = sq.size
            sq.size = newSize
            return true, sq.name .. ": " .. oldSize .. " → " .. newSize .. " 人"
        end
    end
    return false, "编队不存在"
end

--- 为编队分配装备（从库存中按 coverage 取出所需数量）
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

    m.inventory = m.inventory or {}

    -- 计算新装备需要的件数
    local neededCount = calcNeededCount(equipId, squad.size)

    if equipId ~= "rifle" then
        -- 检查库存数量是否充足
        local candidates = {}
        for i, item in ipairs(m.inventory) do
            ensureUid(item)
            if item.equip_id == equipId and not item.repairing then
                table.insert(candidates, { idx = i, item = item })
            end
        end
        if #candidates < neededCount then
            return false, equipData.name .. " 库存不足（需要 " .. neededCount .. "，库存 " .. #candidates .. "）"
        end

        -- 按耐久从高到低排序，取前 neededCount 件
        table.sort(candidates, function(a, b) return a.item.condition > b.item.condition end)
        local removeIndices = {}
        local newEquipItems = {}
        for k = 1, neededCount do
            local c = candidates[k]
            table.insert(newEquipItems, { condition = c.item.condition, uid = genInvUid() })
            table.insert(removeIndices, c.idx)
        end

        -- 当前装备退回库存（非步枪）
        if squad.equip_id ~= "rifle" then
            if squad.equip_items and #squad.equip_items > 0 then
                for _, ei in ipairs(squad.equip_items) do
                    table.insert(m.inventory, { equip_id = squad.equip_id, condition = ei.condition, uid = genInvUid() })
                end
            else
                -- 兼容旧存档
                table.insert(m.inventory, { equip_id = squad.equip_id, condition = squad.condition, uid = genInvUid() })
            end
        end

        -- 从库存移除（倒序）
        table.sort(removeIndices, function(a, b) return a > b end)
        for _, idx in ipairs(removeIndices) do
            table.remove(m.inventory, idx)
        end

        -- 装备新武器
        squad.equip_id = equipId
        squad.equip_items = newEquipItems
        syncSquadCondition(squad)
    else
        -- 换回步枪：当前装备退回库存
        if squad.equip_id ~= "rifle" then
            if squad.equip_items and #squad.equip_items > 0 then
                for _, ei in ipairs(squad.equip_items) do
                    table.insert(m.inventory, { equip_id = squad.equip_id, condition = ei.condition, uid = genInvUid() })
                end
            else
                table.insert(m.inventory, { equip_id = squad.equip_id, condition = squad.condition, uid = genInvUid() })
            end
        end
        squad.equip_id = "rifle"
        squad.equip_items = nil
        squad.condition = 100
    end

    return true, squad.name .. " 装备了 " .. equipData.name .. (neededCount > 1 and ("×" .. neededCount) or "")
end

-- ============================================================================
-- 支援装备分配
-- ============================================================================

--- 为编队分配支援装备（从库存取出1件）
---@param state table
---@param squadId number
---@param supportEquipId string
---@return boolean ok
---@return string msg
function Equipment.AssignSupport(state, squadId, supportEquipId)
    local m = state.military
    local squad = nil
    for _, sq in ipairs(m.squads or {}) do
        if sq.id == squadId then squad = sq; break end
    end
    if not squad then return false, "编队不存在" end

    local sd = SUPPORT_CATALOG[supportEquipId]
    if not sd then return false, "支援装备不存在" end

    if not EquipmentData.IsSupportUnlocked(state, supportEquipId) then
        return false, sd.name .. " 尚未解锁"
    end

    -- 已有同类支援装备
    if squad.support_equip_id == supportEquipId then
        return false, "已装备 " .. sd.name
    end

    m.inventory = m.inventory or {}

    -- 查找库存中的支援装备（优先高耐久）
    local bestIdx, bestCond = nil, -1
    for i, item in ipairs(m.inventory) do
        if item.equip_id == supportEquipId and not item.repairing then
            if item.condition > bestCond then
                bestIdx = i
                bestCond = item.condition
            end
        end
    end
    if not bestIdx then
        return false, sd.name .. " 库存不足"
    end

    -- 如果已有其他支援装备，先退回库存
    if squad.support_equip_id then
        local oldSd = SUPPORT_CATALOG[squad.support_equip_id]
        table.insert(m.inventory, {
            equip_id = squad.support_equip_id,
            condition = squad.support_equip_condition or 100,
            uid = genInvUid(),
        })
    end

    -- 从库存取出新支援装备
    local item = m.inventory[bestIdx]
    squad.support_equip_id = supportEquipId
    squad.support_equip_condition = item.condition
    squad.support_equip_uid = genInvUid()
    table.remove(m.inventory, bestIdx)

    return true, squad.name .. " 装备了 " .. sd.name
end

--- 卸下编队支援装备（退回库存）
---@param state table
---@param squadId number
---@return boolean ok
---@return string msg
function Equipment.RemoveSupport(state, squadId)
    local m = state.military
    local squad = nil
    for _, sq in ipairs(m.squads or {}) do
        if sq.id == squadId then squad = sq; break end
    end
    if not squad then return false, "编队不存在" end
    if not squad.support_equip_id then return false, "该编队没有支援装备" end

    local sd = SUPPORT_CATALOG[squad.support_equip_id]
    m.inventory = m.inventory or {}
    table.insert(m.inventory, {
        equip_id = squad.support_equip_id,
        condition = squad.support_equip_condition or 100,
        uid = genInvUid(),
    })

    local name = sd and sd.name or squad.support_equip_id
    squad.support_equip_id = nil
    squad.support_equip_condition = nil
    squad.support_equip_uid = nil

    return true, squad.name .. " 卸下了 " .. name
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

--- 开始生产装备（工厂）— 支持主武器和支援装备
---@param state table
---@param equipId string
---@return boolean ok
---@return string msg
function Equipment.StartProduction(state, equipId)
    local m = state.military
    local equipData, isSupport = lookupEquipData(equipId)
    if not equipData then return false, "装备不存在" end
    if isSupport then
        if not EquipmentData.IsSupportUnlocked(state, equipId) then
            return false, equipData.name .. " 尚未解锁"
        end
    else
        if not EquipmentData.IsUnlocked(state, equipId) then
            return false, equipData.name .. " 尚未解锁"
        end
    end
    if Equipment.GetFactoryFreeSlots(state) < 1 then
        return false, "工厂无空闲槽位"
    end
    local cost = math.floor(equipData.prod_cost * GameState.GetInflationFactor(state))
    if state.cash < cost then
        return false, "现金不足（需要 " .. cost .. "）"
    end
    -- 铜耗检查
    local copperNeed = BCOPPER.prod_copper_cost[equipId] or 0
    if copperNeed > 0 and (state.copper or 0) < copperNeed then
        return false, "铜不足（需要 " .. copperNeed .. "，持有 " .. (state.copper or 0) .. "）"
    end
    state.cash = state.cash - cost
    if copperNeed > 0 then
        state.copper = (state.copper or 0) - copperNeed
    end
    m.production_queue = m.production_queue or {}
    table.insert(m.production_queue, {
        equip_id = equipId,
        progress = 0,
        total = equipData.prod_turns,
        source = "factory",
    })
    local msg = "开始生产 " .. equipData.name .. "（" .. equipData.prod_turns .. " 季）"
    if copperNeed > 0 then
        msg = msg .. " 消耗铜 " .. copperNeed
    end
    return true, msg
end

--- 开始代工装备 — 支持主武器和支援装备
---@param state table
---@param equipId string
---@return boolean ok
---@return string msg
function Equipment.StartOutsource(state, equipId)
    local m = state.military
    local equipData, isSupport = lookupEquipData(equipId)
    if not equipData then return false, "装备不存在" end
    if isSupport then
        if not EquipmentData.IsSupportUnlocked(state, equipId) then
            return false, equipData.name .. " 尚未解锁"
        end
    else
        if not EquipmentData.IsUnlocked(state, equipId) then
            return false, equipData.name .. " 尚未解锁"
        end
    end
    if Equipment.GetOutsourceFreeSlots(state) < 1 then
        return false, "代工槽位已满"
    end
    local cost = math.floor(equipData.prod_cost * OUTSOURCE.cost_multiplier * GameState.GetInflationFactor(state))
    if state.cash < cost then
        return false, "现金不足（需要 " .. cost .. "）"
    end
    -- 铜耗检查（代工同样消耗铜）
    local copperNeed = BCOPPER.prod_copper_cost[equipId] or 0
    if copperNeed > 0 and (state.copper or 0) < copperNeed then
        return false, "铜不足（需要 " .. copperNeed .. "，持有 " .. (state.copper or 0) .. "）"
    end
    state.cash = state.cash - cost
    if copperNeed > 0 then
        state.copper = (state.copper or 0) - copperNeed
    end
    m.outsource_slots = m.outsource_slots or {}
    local totalTurns = equipData.prod_turns + OUTSOURCE.time_bonus
    table.insert(m.outsource_slots, {
        equip_id = equipId,
        progress = 0,
        total = totalTurns,
        source = "outsource",
    })
    local msg = "代工 " .. equipData.name .. "（" .. totalTurns .. " 季，+60% 成本）"
    if copperNeed > 0 then
        msg = msg .. " 消耗铜 " .. copperNeed
    end
    return true, msg
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
    local equipData = lookupEquipData(item.equip_id)
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

    -- 推进工厂生产队列（煤炭短缺时暂停工厂生产/维修，代工不受影响）
    m.production_queue = m.production_queue or {}
    local coalShortage = state.factory_coal_shortage
    if coalShortage then
        table.insert(messages, "燃煤不足，兵工厂生产暂停")
        state.factory_coal_shortage = nil  -- 清除标记（已被消费）
    end
    local keptQueue = {}
    for _, item in ipairs(m.production_queue) do
        local isFactoryItem = (item.source ~= "outsource")
        if coalShortage and isFactoryItem then
            -- 煤炭短缺：工厂项目不推进，直接保留
            table.insert(keptQueue, item)
        else
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
                        local ed = lookupEquipData(item.equip_id)
                        table.insert(messages, (ed and ed.name or item.equip_id) .. " 维修完成（耐久 " .. invItem.condition .. "）")
                    end
                else
                    -- 生产完成 → 进入库存
                    m.inventory = m.inventory or {}
                    table.insert(m.inventory, { equip_id = item.equip_id, condition = 100, uid = genInvUid() })
                    local ed = lookupEquipData(item.equip_id)
                    table.insert(messages, (ed and ed.name or item.equip_id) .. " 生产完成，已入库")
                end
            else
                table.insert(keptQueue, item)
            end
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
            local ed = lookupEquipData(item.equip_id)
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
            -- 耐久衰减（T1 步枪不衰减）
            if sq.equip_id ~= "rifle" then
                if sq.equip_items and #sq.equip_items > 0 then
                    -- 多件装备：逐件衰减
                    local kept = {}
                    for _, ei in ipairs(sq.equip_items) do
                        local wear = 5 + math.random(0, 7)
                        ei.condition = math.max(0, ei.condition - wear)
                        if ei.condition > 0 then
                            table.insert(kept, ei)
                        end
                        -- condition <= 0 的装备视为战损报废，直接丢弃
                    end
                    sq.equip_items = kept
                    if #sq.equip_items == 0 then
                        -- 全部损毁 → 退回 T1
                        sq.equip_id = "rifle"
                        sq.equip_items = nil
                        sq.condition = 100
                    else
                        syncSquadCondition(sq)
                    end
                else
                    -- 兼容旧存档：单件逻辑
                    local wear = 5 + math.random(0, 7)
                    sq.condition = math.max(0, sq.condition - wear)
                    if sq.condition <= 0 then
                        sq.equip_id = "rifle"
                        sq.condition = 100
                    end
                end
            end

            -- 支援装备耐久衰减（独立于主武器）
            if sq.support_equip_id then
                local sWear = 3 + math.random(0, 5)
                sq.support_equip_condition = math.max(0, (sq.support_equip_condition or 100) - sWear)
                if sq.support_equip_condition <= 0 then
                    -- 支援装备战损报废
                    sq.support_equip_id = nil
                    sq.support_equip_condition = nil
                    sq.support_equip_uid = nil
                end
            end

            -- 老兵经验（称号modifier：经验加成降低升级门槛）
            local expBonus = GameState.GetModifierValue(state, "squad_exp_bonus")
            sq.battles = (sq.battles or 0) + 1
            local vet = EquipmentData.VETERANCY
            if sq.veterancy < 3 then
                local nextLevel = sq.veterancy + 1
                local nextData = vet[nextLevel]
                -- 经验加成：等效减少所需战斗次数
                local reqBattles = nextData and nextData.battles_required or 999
                if expBonus > 0 then
                    reqBattles = math.max(1, math.ceil(reqBattles / (1 + expBonus)))
                end
                if nextData and sq.battles >= reqBattles then
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
            -- 缩编后可能需要退回多余装备
            if sq.equip_id ~= "rifle" and sq.equip_items and #sq.equip_items > 0 then
                local needed = calcNeededCount(sq.equip_id, sq.size)
                while #sq.equip_items > needed do
                    -- 退回耐久最低的
                    local minIdx, minCond = 1, sq.equip_items[1].condition
                    for ei_i = 2, #sq.equip_items do
                        if sq.equip_items[ei_i].condition < minCond then
                            minIdx = ei_i
                            minCond = sq.equip_items[ei_i].condition
                        end
                    end
                    local ei = table.remove(sq.equip_items, minIdx)
                    table.insert(m.inventory, { equip_id = sq.equip_id, condition = ei.condition, uid = genInvUid() })
                end
                syncSquadCondition(sq)
            end
            table.insert(kept, sq)
        else
            -- 装备回库存（全部退回）
            m.inventory = m.inventory or {}
            if sq.equip_id ~= "rifle" then
                if sq.equip_items and #sq.equip_items > 0 then
                    for _, ei in ipairs(sq.equip_items) do
                        table.insert(m.inventory, { equip_id = sq.equip_id, condition = ei.condition, uid = genInvUid() })
                    end
                else
                    table.insert(m.inventory, { equip_id = sq.equip_id, condition = sq.condition, uid = genInvUid() })
                end
            end
            -- 支援装备回库存
            if sq.support_equip_id then
                table.insert(m.inventory, {
                    equip_id = sq.support_equip_id,
                    condition = sq.support_equip_condition or 100,
                    uid = genInvUid(),
                })
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

    -- 编队装备维护（按实际装备件数 × 单件维护费）
    for _, sq in ipairs(m.squads or {}) do
        local ed = CATALOG[sq.equip_id]
        if ed then
            local count = 1
            if sq.equip_items and #sq.equip_items > 0 then
                count = #sq.equip_items
            elseif sq.equip_id ~= "rifle" then
                count = calcNeededCount(sq.equip_id, sq.size)
            end
            equipMaint = equipMaint + ed.maintenance * count
        end
        -- 编队支援装备维护（全价，1件）
        if sq.support_equip_id then
            local sd = SUPPORT_CATALOG[sq.support_equip_id]
            if sd then
                equipMaint = equipMaint + sd.maintenance
            end
        end
    end
    -- 库存装备维护（半价，主武器和支援装备统一）
    for _, item in ipairs(m.inventory or {}) do
        local ed = lookupEquipData(item.equip_id)
        if ed then
            equipMaint = equipMaint + math.floor(ed.maintenance * 0.5)
        end
    end
    equipMaint = math.floor(equipMaint * inflation)

    -- 铜库存维护费减免（每持有10铜 → -5%，上限25%）
    local copperHeld = state.copper or 0
    if copperHeld >= 10 then
        local reduction = math.min(BCOPPER.maintenance_reduction_cap,
            math.floor(copperHeld / 10) * BCOPPER.maintenance_reduction_per_10)
        equipMaint = math.floor(equipMaint * (1 - reduction))
    end

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

--- 公开辅助：计算编队在给定人数下所需装备件数
Equipment.CalcNeededCount = calcNeededCount

return Equipment
