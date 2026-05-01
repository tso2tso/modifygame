-- ============================================================================
-- 存档系统：本地文件读写（cjson + File API）
-- WASM 平台数据不持久（刷新即丢失），但接口统一
-- ============================================================================

local SaveLoad = {}

local SAVE_VERSION = "0.4.0"
local SAVE_DIR  = "saves"
local SAVE_FILE = "saves/autosave.json"

-- 双槽位常量
SaveLoad.SLOT_AUTO   = "auto"
SaveLoad.SLOT_MANUAL = "manual"

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
        version = SAVE_VERSION,
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

    -- 版本检查与迁移
    local ver = saveData.version or "0.0.0"
    if ver ~= SAVE_VERSION then
        print("[SaveLoad] 存档版本：" .. ver .. " → 迁移至 " .. SAVE_VERSION)
    end

    local state = SaveLoad._DeserializeState(saveData.state)
    print("[SaveLoad] 读档成功: " .. filename)
    return state
end

--- 检查是否存在有效存档（排除空文件和已删除标记）
---@param slotName string|nil
---@return boolean
function SaveLoad.HasSave(slotName)
    local filename = slotName
        and (SAVE_DIR .. "/" .. slotName .. ".json")
        or SAVE_FILE
    if not fileSystem:FileExists(filename) then return false end
    local file = File(filename, FILE_READ)
    if not file:IsOpen() then return false end
    local content = file:ReadString()
    file:Close()
    if not content or #content < 10 then return false end
    if content:find('"_deleted"') then return false end
    return true
end

--- 删除存档
---@param slotName string|nil
---@return boolean
function SaveLoad.Delete(slotName)
    local filename = slotName
        and (SAVE_DIR .. "/" .. slotName .. ".json")
        or SAVE_FILE
    if fileSystem:FileExists(filename) then
        -- 写入删除标记（沙箱不支持 os.remove）
        local file = File(filename, FILE_WRITE)
        if file:IsOpen() then
            file:WriteString('{"_deleted":true}')
            file:Close()
            print("[SaveLoad] 存档已删除: " .. filename)
            return true
        end
    end
    return false
end

--- 获取存档元信息（不完整反序列化，用于 UI 展示）
---@param slotName string|nil
---@return table|nil info { slot, timestamp, year, quarter, turn_count, cash, gold }
function SaveLoad.GetSlotInfo(slotName)
    local filename = slotName
        and (SAVE_DIR .. "/" .. slotName .. ".json")
        or SAVE_FILE
    if not fileSystem:FileExists(filename) then return nil end
    local file = File(filename, FILE_READ)
    if not file:IsOpen() then return nil end
    local content = file:ReadString()
    file:Close()
    if not content or #content < 10 then return nil end
    if content:find('"_deleted"') then return nil end

    local ok, saveData = pcall(cjson.decode, content)
    if not ok or not saveData or not saveData.state then return nil end

    local s = saveData.state
    return {
        slot = slotName or "autosave",
        timestamp = saveData.timestamp or 0,
        year = s.year or 1904,
        quarter = s.quarter or 1,
        turn_count = s.turn_count or 0,
        cash = s.cash or 0,
        gold = s.gold or 0,
    }
end

--- 列出所有有效存档槽（排除已删除的）
---@return string[] slotNames
function SaveLoad.ListSlots()
    if not fileSystem:DirExists(SAVE_DIR) then
        return {}
    end
    local files = fileSystem:ScanDir(SAVE_DIR .. "/", "*.json", SCAN_FILES, false)
    local slots = {}
    for _, name in ipairs(files) do
        local slot = name:match("^(.+)%.json$")
        if slot and SaveLoad.HasSave(slot) then
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
    data.silver = state.silver or 0
    data.coal = state.coal or 0
    data.inflation_factor = state.inflation_factor or 1.0
    data.ap = {
        current = state.ap.current,
        max = state.ap.max,
        temp = state.ap.temp or 0,
        bonus_used = state.ap.bonus_used or 0,
    }
    data.victory = {
        economic = state.victory.economic,
        military = state.victory.military,
        claimed = state.victory.claimed,
        claimed_year = state.victory.claimed_year,
        claimed_quarter = state.victory.claimed_quarter,
        prompt_pending = state.victory.prompt_pending,
    }
    data.battle_wins_total = state.battle_wins_total or 0
    data.battle_wins_unclaimed = state.battle_wins_unclaimed or 0
    data.phase = state.phase
    data.turn_count = state.turn_count

    -- 贷款/破产追踪
    data.loan_consecutive_defaults = state.loan_consecutive_defaults or 0
    data.negative_net_worth_turns = state.negative_net_worth_turns or 0
    data.bankrupt = state.bankrupt or false

    -- 黄金自动出售
    data.gold_auto_sell = state.gold_auto_sell or false

    -- 监管压力
    data.regulation_pressure = state.regulation_pressure or 0

    -- 大国博弈系统
    data.europe = state.europe
    data.collaboration_score = state.collaboration_score or 0
    data.powers = state.powers or {}
    data.fronts = state.fronts or {}

    -- 家族成员
    data.family = { members = {}, training = state.family.training }
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
            influence = r.influence or 0,
            ai_presence = r.ai_presence,
        })
    end

    -- 矿山
    data.mines = {}
    for _, mine in ipairs(state.mines) do
        table.insert(data.mines, {
            id = mine.id,
            name = mine.name,
            region_id = mine.region_id,
            level = mine.level,
            output_bonus = mine.output_bonus,
            active = mine.active,
            reserve = mine.reserve,
            migrating = mine.migrating or nil,
        })
    end
    data.mine_slots_bonus = state.mine_slots_bonus or 0

    -- 探矿
    data.prospect_reserves = state.prospect_reserves or {}
    data.prospecting = state.prospecting
    data.prospect_success_count = state.prospect_success_count or 0
    data.prospect_success_bonus = state.prospect_success_bonus or 0

    -- 股市（含历史与 event_mu_mods）
    data.stocks = {}
    for _, s in ipairs(state.stocks or {}) do
        table.insert(data.stocks, {
            id = s.id,
            name = s.name,
            price = s.price,
            prev_price = s.prev_price,
            change_pct = s.change_pct,
            mu = s.mu,
            sigma = s.sigma,
            sector = s.sector,
            rating = s.rating,
            history = s.history,
            event_mu_mods = s.event_mu_mods,
        })
    end
    data.portfolio = state.portfolio or { holdings = {} }

    -- 贷款
    data.loans = state.loans or {}

    -- 科技
    data.tech = state.tech or { researched = {}, in_progress = nil, bonus_points = 0 }

    -- 被动加成（印刷宣传等）
    data.passive_influence = state.passive_influence or 0
    data.derived_effects = {
        mine_output_base_bonus = state.mine_output_base_bonus or 0,
        mine_output_mult_bonus = state.mine_output_mult_bonus or 0,
        worker_efficiency_bonus = state.worker_efficiency_bonus or 0,
        guard_power_tech_bonus = state.guard_power_tech_bonus or 0,
        research_speed_bonus = state.research_speed_bonus or 0,
        trade_passive_income = state.trade_passive_income or 0,
        finance_passive_income = state.finance_passive_income or 0,
        finance_supply_discount = state.finance_supply_discount or 0,
        gold_price_bonus = state.gold_price_bonus or 0,
        hire_cost_discount = state.hire_cost_discount or 0,
        supply_reduction_bonus = state.supply_reduction_bonus or 0,
        accident_rate_mod = state.accident_rate_mod or 0,
    }

    -- 新手引导
    data.tutorial_done = state.tutorial_done or false

    -- 广告幸运事件
    data.lucky_ad_watched = state.lucky_ad_watched or 0
    data.lucky_ad_decay = state.lucky_ad_decay or 1.0

    -- 破产免死广告
    data.bankrupt_ad_used = state.bankrupt_ad_used or 0

    -- 音量设置
    data.audio_settings = state.audio_settings

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
        supply = state.military.supply,
        -- 装备/编队系统
        squads = state.military.squads or {},
        inventory = state.military.inventory or {},
        factory = state.military.factory,
        production_queue = state.military.production_queue or {},
        outsource_slots = state.military.outsource_slots or {},
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
    data.event_queue = state.event_queue or {}
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
    -- 基础字段
    data.year = data.year or 1904
    data.quarter = data.quarter or 1
    data.cash = data.cash or 1000
    data.gold = data.gold or 5
    data.ap = data.ap or { current = 6, max = 6 }
    data.ap.temp = data.ap.temp or 0
    data.ap.bonus_used = data.ap.bonus_used or 0
    data.victory = data.victory or { economic = 0, military = 0 }
    data.family = data.family or { members = {} }
    -- family.training 可以为 nil（表示没有正在培养的成员）
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

    -- 新字段兼容旧存档：若不存在则从 Balance 重建
    data.silver = data.silver or 0
    data.coal = data.coal or 0
    data.inflation_factor = data.inflation_factor or 1.0
    data.loans = data.loans or {}
    data.tech = data.tech or { researched = {}, in_progress = nil, bonus_points = 0 }
    data.tech.researched = data.tech.researched or {}
    data.portfolio = data.portfolio or { holdings = {} }
    data.portfolio.holdings = data.portfolio.holdings or {}
    data.passive_influence = data.passive_influence or 0
    data.battle_wins_total = data.battle_wins_total or 0
    data.battle_wins_unclaimed = data.battle_wins_unclaimed or 0
    data.victory.claimed = data.victory.claimed
    data.victory.claimed_year = data.victory.claimed_year
    data.victory.claimed_quarter = data.victory.claimed_quarter
    data.victory.prompt_pending = data.victory.prompt_pending

    -- 贷款/破产追踪（v0.4.0 新增保存）
    data.loan_consecutive_defaults = data.loan_consecutive_defaults or 0
    data.negative_net_worth_turns = data.negative_net_worth_turns or 0
    if data.bankrupt == nil then data.bankrupt = false end

    -- 破产免死广告
    data.bankrupt_ad_used = data.bankrupt_ad_used or 0

    -- 黄金自动出售（v0.4.0 新增保存）
    if data.gold_auto_sell == nil then data.gold_auto_sell = false end

    -- 监管压力（v0.4.0 新增保存）
    data.regulation_pressure = data.regulation_pressure or 0

    -- 大国博弈系统（v0.4.0 新增保存）
    if not data.europe then
        local EuropeData = require("data.europe_data")
        data.europe = EuropeData.CreateInitial()
        print("[SaveLoad] 旧存档迁移：初始化大国博弈地图")
    end
    data.collaboration_score = data.collaboration_score or 0
    data.powers = data.powers or {}
    data.fronts = data.fronts or {}

    -- 每回合重置的运行时标记（不需要持久化，但需要有默认值）
    if data.emergency_gold_sold == nil then data.emergency_gold_sold = false end
    if data.culture_action_this_turn == nil then data.culture_action_this_turn = false end
    data.turn_messages = data.turn_messages or {}

    for _, r in ipairs(data.regions) do
        r.influence = r.influence or 0
    end
    for _, faction in ipairs(data.ai_factions) do
        faction.victory = faction.victory or { economic = 0, military = 0 }
        faction.victory.economic = faction.victory.economic or 0
        faction.victory.military = faction.victory.military or 0
        faction.battle_wins_unclaimed = faction.battle_wins_unclaimed or 0
    end

    local derived = data.derived_effects or {}
    data.mine_output_base_bonus = derived.mine_output_base_bonus or data.mine_output_base_bonus or 0
    data.mine_output_mult_bonus = derived.mine_output_mult_bonus or data.mine_output_mult_bonus or 0
    data.worker_efficiency_bonus = derived.worker_efficiency_bonus or data.worker_efficiency_bonus or 0
    data.guard_power_tech_bonus = derived.guard_power_tech_bonus or data.guard_power_tech_bonus or 0
    data.research_speed_bonus = derived.research_speed_bonus or data.research_speed_bonus or 0
    data.trade_passive_income = derived.trade_passive_income or data.trade_passive_income or 0
    data.finance_passive_income = derived.finance_passive_income or data.finance_passive_income or 0
    data.finance_supply_discount = derived.finance_supply_discount or data.finance_supply_discount or 0
    data.gold_price_bonus = derived.gold_price_bonus or data.gold_price_bonus or 0
    data.hire_cost_discount = derived.hire_cost_discount or data.hire_cost_discount or 0
    data.supply_reduction_bonus = derived.supply_reduction_bonus or data.supply_reduction_bonus or 0
    data.accident_rate_mod = derived.accident_rate_mod or data.accident_rate_mod or 0
    data.derived_effects = nil  -- 清除残留，避免序列化时产生嵌套冗余
    data.military.supply = data.military.supply or 20

    -- 装备/编队系统（v0.5.0 新增）
    data.military.squads = data.military.squads or {}
    data.military.inventory = data.military.inventory or {}
    -- data.military.factory 可以为 nil（表示未建造）
    data.military.production_queue = data.military.production_queue or {}
    data.military.outsource_slots = data.military.outsource_slots or {}

    -- 矿山槽位 + 探矿（v0.4.0 新增）
    data.mine_slots_bonus = data.mine_slots_bonus or 0
    data.prospect_reserves = data.prospect_reserves or {}
    -- data.prospecting 可以为 nil（表示未在探矿）
    data.prospect_success_count = data.prospect_success_count or 0
    data.prospect_success_bonus = data.prospect_success_bonus or 0
    -- 矿山独立储量兼容（旧存档无 reserve 字段）
    for _, mine in ipairs(data.mines) do
        if mine.reserve == nil then
            mine.reserve = 500  -- 旧存档默认储量
        end
    end

    -- 兼容旧存档：老版本只保存 researched，没有保存科技派生字段。
    if not data.derived_effects and data.tech and data.tech.researched then
        local TechData = require("data.tech_data")
        for _, tech in ipairs(TechData.GetAll()) do
            if data.tech.researched[tech.id] then
                for _, eff in ipairs(tech.effects or {}) do
                    if eff.kind == "mine_output_base" then
                        data.mine_output_base_bonus = (data.mine_output_base_bonus or 0) + eff.value
                    elseif eff.kind == "mine_output_mult" then
                        data.mine_output_mult_bonus = (data.mine_output_mult_bonus or 0) + eff.value
                    elseif eff.kind == "worker_efficiency" then
                        data.worker_efficiency_bonus = (data.worker_efficiency_bonus or 0) + eff.value
                    elseif eff.kind == "guard_power_bonus" then
                        data.guard_power_tech_bonus = (data.guard_power_tech_bonus or 0) + eff.value
                    elseif eff.kind == "research_speed" then
                        data.research_speed_bonus = (data.research_speed_bonus or 0) + eff.value
                    elseif eff.kind == "trade_income" then
                        data.trade_passive_income = (data.trade_passive_income or 0) + eff.value
                    elseif eff.kind == "finance_network" then
                        data.finance_supply_discount = 0.20
                        data.finance_passive_income = 80
                    elseif eff.kind == "gold_price_bonus" then
                        data.gold_price_bonus = (data.gold_price_bonus or 0) + eff.value
                    elseif eff.kind == "hire_cost_reduction" then
                        data.hire_cost_discount = (data.hire_cost_discount or 0) + eff.value
                    elseif eff.kind == "supply_reduction" then
                        data.supply_reduction_bonus = (data.supply_reduction_bonus or 0) + math.abs(eff.value)
                    elseif eff.kind == "accident_reduction" then
                        data.accident_rate_mod = (data.accident_rate_mod or 0) + eff.value
                    elseif eff.kind == "mine_slots" then
                        data.mine_slots_bonus = (data.mine_slots_bonus or 0) + eff.value
                    elseif eff.kind == "prospect_success" then
                        data.prospect_success_bonus = (data.prospect_success_bonus or 0) + eff.value
                    end
                end
            end
        end
        for _, mine in ipairs(data.mines or {}) do
            mine.output_bonus = 0
        end
    end

    -- 新手引导兼容（旧存档默认跳过引导）
    if data.tutorial_done == nil then data.tutorial_done = true end

    -- 广告幸运事件兼容
    data.lucky_ad_watched = data.lucky_ad_watched or 0
    data.lucky_ad_decay = data.lucky_ad_decay or 1.0

    -- 音量设置兼容（旧存档无此字段）
    -- data.audio_settings 可以为 nil，由 AudioManager.LoadSettings 处理

    if not data.stocks or #data.stocks == 0 then
        local Balance = require("data.balance")
        data.stocks = {}
        for _, s in ipairs(Balance.STOCKS) do
            local inst = {}
            for k, v in pairs(s) do inst[k] = v end
            inst.prev_price = inst.price
            inst.change_pct = 0
            inst.history = { inst.price }
            inst.event_mu_mods = {}
            table.insert(data.stocks, inst)
        end
    else
        for _, s in ipairs(data.stocks) do
            s.history = s.history or { s.price }
            s.event_mu_mods = s.event_mu_mods or {}
            s.change_pct = s.change_pct or 0
        end
    end

    -- 重建装备库存 uid 计数器，避免新物品 uid 与旧存档冲突
    local Equipment = require("systems.equipment")
    Equipment.RebuildUidCounter(data)

    return data
end

return SaveLoad
