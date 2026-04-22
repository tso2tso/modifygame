-- ============================================================================
-- 存档系统：本地文件读写（cjson + File API）
-- WASM 平台数据不持久（刷新即丢失），但接口统一
-- ============================================================================

local SaveLoad = {}

local SAVE_DIR  = "saves"
local SAVE_FILE = "saves/autosave.json"

--- 保存游戏状态到文件
---@param state table 完整游戏状态
---@param slotName string|nil 存档槽名（默认 autosave）
---@return boolean success
function SaveLoad.Save(state, slotName)
    -- 确保目录存在
    fileSystem:CreateDir(SAVE_DIR)

    local filename = slotName
        and (SAVE_DIR .. "/" .. slotName .. ".json")
        or SAVE_FILE

    -- 构造存档数据（排除不需要持久化的运行时数据）
    local saveData = {
        version = "0.1.0",
        timestamp = os.time(),
        state = SaveLoad._SerializeState(state),
    }

    local ok, jsonStr = pcall(cjson.encode, saveData)
    if not ok then
        print("[SaveLoad] 序列化失败: " .. tostring(jsonStr))
        return false
    end

    local file = File(filename, FILE_WRITE)
    if not file:IsOpen() then
        print("[SaveLoad] 无法打开文件: " .. filename)
        return false
    end

    file:WriteString(jsonStr)
    file:Close()
    print("[SaveLoad] 存档成功: " .. filename)
    return true
end

--- 读取存档
---@param slotName string|nil 存档槽名（默认 autosave）
---@return table|nil state 游戏状态，失败返回 nil
function SaveLoad.Load(slotName)
    local filename = slotName
        and (SAVE_DIR .. "/" .. slotName .. ".json")
        or SAVE_FILE

    if not fileSystem:FileExists(filename) then
        print("[SaveLoad] 存档不存在: " .. filename)
        return nil
    end

    local file = File(filename, FILE_READ)
    if not file:IsOpen() then
        print("[SaveLoad] 无法打开文件: " .. filename)
        return nil
    end

    local jsonStr = file:ReadString()
    file:Close()

    local ok, saveData = pcall(cjson.decode, jsonStr)
    if not ok then
        print("[SaveLoad] 解析失败: " .. tostring(saveData))
        return nil
    end

    -- 版本检查（未来可做迁移）
    if saveData.version ~= "0.1.0" then
        print("[SaveLoad] 存档版本不匹配: " .. tostring(saveData.version))
    end

    local state = SaveLoad._DeserializeState(saveData.state)
    print("[SaveLoad] 读档成功: " .. filename)
    return state
end

--- 检查是否存在存档
---@param slotName string|nil
---@return boolean
function SaveLoad.HasSave(slotName)
    local filename = slotName
        and (SAVE_DIR .. "/" .. slotName .. ".json")
        or SAVE_FILE
    return fileSystem:FileExists(filename)
end

--- 删除存档
---@param slotName string|nil
---@return boolean
function SaveLoad.Delete(slotName)
    local filename = slotName
        and (SAVE_DIR .. "/" .. slotName .. ".json")
        or SAVE_FILE
    if fileSystem:FileExists(filename) then
        -- 用空文件覆盖（沙箱不支持 os.remove）
        local file = File(filename, FILE_WRITE)
        if file:IsOpen() then
            file:WriteString("")
            file:Close()
            print("[SaveLoad] 存档已删除: " .. filename)
            return true
        end
    end
    return false
end

--- 列出所有存档槽
---@return string[] slotNames
function SaveLoad.ListSlots()
    if not fileSystem:DirExists(SAVE_DIR) then
        return {}
    end
    local files = fileSystem:ScanDir(SAVE_DIR .. "/", "*.json", SCAN_FILES, false)
    local slots = {}
    for _, name in ipairs(files) do
        -- 去掉 .json 后缀
        local slot = name:match("^(.+)%.json$")
        if slot then
            table.insert(slots, slot)
        end
    end
    return slots
end

-- ============================================================================
-- 内部：序列化/反序列化
-- ============================================================================

--- 序列化状态（将复杂对象转为纯数据表）
---@param state table
---@return table
function SaveLoad._SerializeState(state)
    -- 当前阶段状态是纯 Lua 表，可以直接序列化
    -- 未来如果有 userdata（如 Vector3），需要手动转换
    local data = {}

    -- 基础字段直接复制
    data.year = state.year
    data.quarter = state.quarter
    data.cash = state.cash
    data.gold = state.gold
    data.ap = { current = state.ap.current, max = state.ap.max }
    data.victory = {
        economic = state.victory.economic,
        military = state.victory.military,
    }
    data.phase = state.phase
    data.turn_count = state.turn_count

    -- 家族成员
    data.family = { members = {} }
    for _, m in ipairs(state.family.members) do
        table.insert(data.family.members, {
            id = m.id,
            name = m.name,
            title = m.title,
            portrait = m.portrait,
            attrs = {
                management = m.attrs.management,
                strategy   = m.attrs.strategy,
                charisma   = m.attrs.charisma,
                knowledge  = m.attrs.knowledge,
                ambition   = m.attrs.ambition,
            },
            hidden = m.hidden,
            position = m.position,
            status = m.status,
            disabled_turns = m.disabled_turns,
            bio = m.bio,
        })
    end

    -- 地区
    data.regions = {}
    for _, r in ipairs(state.regions) do
        table.insert(data.regions, {
            id = r.id,
            name = r.name,
            icon = r.icon,
            type = r.type,
            resources = r.resources,
            security = r.security,
            development = r.development,
            population = r.population,
            policy = r.policy,
            culture = r.culture,
            control = r.control,
            ai_presence = r.ai_presence,
        })
    end

    -- 矿山
    data.mines = {}
    for _, mine in ipairs(state.mines) do
        table.insert(data.mines, {
            id = mine.id,
            region_id = mine.region_id,
            level = mine.level,
            output_bonus = mine.output_bonus,
        })
    end

    -- 工人/军事
    data.workers = {
        hired = state.workers.hired,
        wage = state.workers.wage,
        morale = state.workers.morale,
    }
    data.military = {
        guards = state.military.guards,
        morale = state.military.morale,
        wage = state.military.wage,
        equipment = state.military.equipment,
    }

    -- AI 势力
    data.ai_factions = state.ai_factions

    -- 修正器
    data.modifiers = state.modifiers

    -- 历史日志（只保留最近 50 条）
    data.history_log = {}
    local logStart = math.max(1, #state.history_log - 49)
    for i = logStart, #state.history_log do
        table.insert(data.history_log, state.history_log[i])
    end

    -- 事件状态
    data.events_fired = state.events_fired
    data.random_cooldowns = state.random_cooldowns

    -- 全局标记
    data.flags = state.flags

    -- 累计统计
    data.total_income = state.total_income
    data.total_expense = state.total_expense

    return data
end

--- 反序列化状态
---@param data table
---@return table state
function SaveLoad._DeserializeState(data)
    -- 纯数据表，直接返回（加上默认值保护）
    data.ap = data.ap or { current = 6, max = 6 }
    data.victory = data.victory or { economic = 0, military = 0 }
    data.family = data.family or { members = {} }
    data.regions = data.regions or {}
    data.mines = data.mines or {}
    data.workers = data.workers or { hired = 10, wage = 8, morale = 70 }
    data.military = data.military or { guards = 5, morale = 70, wage = 12, equipment = 1 }
    data.ai_factions = data.ai_factions or {}
    data.modifiers = data.modifiers or {}
    data.history_log = data.history_log or {}
    data.events_fired = data.events_fired or {}
    data.flags = data.flags or { at_war = false, war_start_turn = 0 }
    data.random_cooldowns = data.random_cooldowns or {}
    data.total_income = data.total_income or 0
    data.total_expense = data.total_expense or 0
    data.event_queue = data.event_queue or {}
    data.phase = data.phase or "action"
    data.turn_count = data.turn_count or 0
    return data
end

return SaveLoad
