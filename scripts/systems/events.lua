-- ============================================================================
-- 事件系统：检查触发条件、入队、应用效果
-- ============================================================================

local GameState = require("game_state")
local EventsData = require("data.events_data")
local Balance = require("data.balance")
local StockEngine = require("systems.stock_engine")
local EventMarketEffects = require("data.event_market_effects")

local Events = {}

--- 检查当季应触发的事件，返回事件列表
---@param state table
---@return table[] triggeredEvents
function Events.CheckEvents(state)
    local triggered = {}

    -- 1. 检查固定历史事件
    local fixedEvents = EventsData.GetFixedEvents()
    for _, event in ipairs(fixedEvents) do
        if not state.events_fired[event.id] then
            if event.fixed_date then
                if state.year == event.fixed_date.year and
                   state.quarter == event.fixed_date.quarter then
                    table.insert(triggered, event)
                end
            end
        end
    end

    -- 2. 检查随机事件（如果没有固定事件）
    if #triggered == 0 then
        local templates = EventsData.GetRandomEventTemplates()
        for _, event in ipairs(templates) do
            if not state.events_fired[event.id] and
               Events._CheckTrigger(state, event) then
                -- 冷却检查
                local cd = state.random_cooldowns[event.id] or 0
                if cd <= 0 then
                    -- 概率检查
                    if math.random() < (event.chance or 0.1) then
                        table.insert(triggered, event)
                        break  -- 每季最多一个随机事件
                    end
                end
            end
        end
    end

    return triggered
end

--- 检查随机事件触发条件
---@param state table
---@param event table
---@return boolean
function Events._CheckTrigger(state, event)
    local trigger = event.trigger
    if not trigger then return true end

    -- 需要矿山
    if trigger.requires_mine then
        local hasMine = false
        for _, mine in ipairs(state.mines) do
            if mine.active then hasMine = true; break end
        end
        if not hasMine then return false end
    end

    -- 最高治安限制
    if trigger.max_security then
        local mineRegion = GameState.GetRegion(state, "mine_district")
        if mineRegion and mineRegion.security > trigger.max_security then
            return false
        end
    end

    -- 最低工人数
    if trigger.min_workers then
        if state.workers.hired < trigger.min_workers then
            return false
        end
    end

    -- 最低年份
    if trigger.min_year then
        if state.year < trigger.min_year then
            return false
        end
    end

    -- 最低基建
    if trigger.min_development then
        local mineRegion = GameState.GetRegion(state, "mine_district")
        if mineRegion and mineRegion.development < trigger.min_development then
            return false
        end
    end

    return true
end

--- 将事件加入处理队列
---@param state table
---@param events table[]
function Events.Enqueue(state, events)
    for _, event in ipairs(events) do
        table.insert(state.event_queue, event)
    end
end

--- 应用事件选项效果
---@param state table
---@param event table 事件数据
---@param optionIndex number 选择的选项索引 (1-based)
function Events.ApplyOption(state, event, optionIndex)
    local option = event.options[optionIndex]
    if not option then return end

    local effects = option.effects or {}

    -- 1. 直接资源效果
    if effects.cash then
        state.cash = state.cash + effects.cash
    end
    if effects.gold then
        state.gold = math.max(0, state.gold + effects.gold)
    end

    -- 2. 工人加成
    if effects.workers_bonus then
        state.workers.hired = state.workers.hired + effects.workers_bonus
    end

    -- 3. 治安加成
    if effects.security_bonus then
        local mineRegion = GameState.GetRegion(state, "mine_district")
        if mineRegion then
            mineRegion.security = math.max(1, math.min(5,
                mineRegion.security + effects.security_bonus))
        end
    end

    -- 4. 修正器
    if effects.modifiers then
        for _, mod in ipairs(effects.modifiers) do
            GameState.AddModifier(state,
                event.id .. "_" .. mod.target,
                mod.target,
                mod.value,
                mod.duration or 0)
        end
    end

    -- 5. 工资修正（永久）
    local wageMod = GameState.GetModifierValue(state, "worker_wage")
    if wageMod ~= 0 then
        state.workers.wage = state.workers.wage + wageMod
        -- 立即移除工资修正（已应用到基础值）
        local kept = {}
        for _, m in ipairs(state.modifiers) do
            if m.target ~= "worker_wage" then
                table.insert(kept, m)
            end
        end
        state.modifiers = kept
    end

    -- 6. 工人士气修正（立即应用）
    local moraleMod = GameState.GetModifierValue(state, "worker_morale")
    if moraleMod ~= 0 then
        state.workers.morale = math.max(0, math.min(100,
            state.workers.morale + moraleMod))
        local kept = {}
        for _, m in ipairs(state.modifiers) do
            if m.target ~= "worker_morale" then
                table.insert(kept, m)
            end
        end
        state.modifiers = kept
    end

    -- 7. 事件专属 ongoing_modifiers（如战争经济）
    if event.ongoing_modifiers then
        local om = event.ongoing_modifiers
        for target, value in pairs(om.effects or {}) do
            GameState.AddModifier(state,
                event.id .. "_ongoing_" .. target,
                target, value, om.duration or 0)
        end
    end

    -- 8. 事件附加 AP 奖励
    if event.bonus_ap then
        state.ap.temp = state.ap.temp + event.bonus_ap
    end

    -- 8.5 事件 → 股价：注入 delta_mu（GBM 第三层联动）
    local mktEffects = EventMarketEffects.Get(event.id)
    if mktEffects then
        for _, mod in ipairs(mktEffects) do
            StockEngine.ApplyEventModifier(state,
                mod.stock_id, mod.delta_mu, mod.duration, event.id)
        end
    end
    -- 选项本身携带 stock_effects 时也注入
    if option.stock_effects then
        for _, mod in ipairs(option.stock_effects) do
            StockEngine.ApplyEventModifier(state,
                mod.stock_id, mod.delta_mu, mod.duration,
                event.id .. "_opt" .. optionIndex)
        end
    end

    -- 9. 标记事件已触发
    state.events_fired[event.id] = true

    -- 10. 设置冷却（随机事件）
    if event.trigger and event.trigger.cooldown then
        state.random_cooldowns[event.id] = event.trigger.cooldown
    end

    -- 11. 战争状态触发
    if event.id == "sarajevo_shots_1914" then
        state.flags.at_war = true
        state.flags.war_start_turn = state.turn_count
    end

    -- 12. 日志
    GameState.AddLog(state, string.format("[事件] %s → %s", event.title, option.text))
end

--- 从队列取出下一个事件
---@param state table
---@return table|nil event
function Events.Dequeue(state)
    if #state.event_queue > 0 then
        return table.remove(state.event_queue, 1)
    end
    return nil
end

--- 检查队列是否还有事件
---@param state table
---@return boolean
function Events.HasPendingEvents(state)
    return #state.event_queue > 0
end

return Events
