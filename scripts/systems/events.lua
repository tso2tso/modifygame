-- ============================================================================
-- 事件系统：检查触发条件、入队、应用效果
-- ============================================================================

local GameState = require("game_state")
local EventsData = require("data.events_data")
local Balance = require("data.balance")
local StockEngine = require("systems.stock_engine")
local EventMarketEffects = require("data.event_market_effects")
local Config = require("config")

local Events = {}

local function ClampInflation(value)
    local infl = Balance.INFLATION
    return math.max(infl.floor_factor or infl.base_factor or 1.0,
        math.min(infl.cap_factor, value))
end

local function AddRegulationPressure(state, delta)
    if not delta or delta == 0 then return end
    state.regulation_pressure = math.max(0, math.min(100,
        (state.regulation_pressure or 0) + delta))
end

--- 检查当季应触发的事件，返回事件列表
--- 固定事件和随机事件可以同季触发（不再互斥）
--- 连续 N 季无事件时触发保底随机事件（概率翻倍）
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

    -- 2. 检查随机事件（不再要求"没有固定事件"才检查）
    local templates = EventsData.GetRandomEventTemplates()
    -- 保底机制：连续无事件时概率提升
    local drought = state.event_drought_counter or 0
    local chanceMultiplier = 1.0
    if drought >= 3 then
        chanceMultiplier = 2.0   -- 连续3季无事件，概率翻倍
    elseif drought >= 2 then
        chanceMultiplier = 1.5   -- 连续2季无事件，概率×1.5
    end

    -- 打乱模板顺序以增加随机性
    local shuffled = {}
    for _, e in ipairs(templates) do table.insert(shuffled, e) end
    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local randomCount = 0
    local maxRandom = (#triggered > 0) and 1 or 2  -- 有固定事件时最多1个随机，否则最多2个
    for _, event in ipairs(shuffled) do
        if randomCount >= maxRandom then break end
        if Events._CheckTrigger(state, event) then
            -- 冷却检查
            local cd = state.random_cooldowns[event.id] or 0
            if cd <= 0 then
                -- 概率检查（带保底乘数）
                local effectiveChance = (event.chance or 0.1) * chanceMultiplier
                if math.random() < effectiveChance then
                    table.insert(triggered, event)
                    randomCount = randomCount + 1
                end
            end
        end
    end

    -- 3. 更新事件干旱计数器
    if #triggered > 0 then
        state.event_drought_counter = 0
    else
        state.event_drought_counter = (state.event_drought_counter or 0) + 1
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
        local effectiveSecurity = mineRegion and mineRegion.security or 0
        if mineRegion and GameState.HasInfluenceThreshold(state, 30) then
            effectiveSecurity = effectiveSecurity + 1
        end
        if mineRegion and effectiveSecurity > trigger.max_security then
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

    -- 最高年份
    if trigger.max_year then
        if state.year > trigger.max_year then
            return false
        end
    end

    -- 需要处于战争状态
    if trigger.requires_war then
        local atWar = state.flags and state.flags.at_war
        if not atWar then
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

--- 将事件加入处理队列（自动去重 + 标记 events_fired 防止重复触发）
---@param state table
---@param events table[]
function Events.Enqueue(state, events)
    for _, event in ipairs(events) do
        -- 去重：检查队列中是否已有同 id 事件
        local already = false
        for _, queued in ipairs(state.event_queue) do
            if queued.id == event.id then
                already = true
                break
            end
        end
        if not already then
            table.insert(state.event_queue, event)
        end
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
    if effects.gold_reserve then
        local region = GameState.GetRegion(state, "mine_district")
        if region then
            region.resources.gold_reserve = (region.resources.gold_reserve or 0) + effects.gold_reserve
        end
    end

    -- 1.5 历史事件对宏观环境的直接冲击
    if effects.inflation_delta then
        state.inflation_factor = ClampInflation((state.inflation_factor or 1.0) + effects.inflation_delta)
    end
    if effects.war_state ~= nil then
        state.flags = state.flags or {}
        state.flags.at_war = effects.war_state and true or false
        if state.flags.at_war then
            state.flags.war_start_turn = state.turn_count
        else
            state.flags.war_end_turn = state.turn_count
        end
    end
    if effects.inflation_drift_mod then
        GameState.AddModifier(state,
            event.id .. "_inflation_drift",
            "inflation_drift",
            effects.inflation_drift_mod,
            effects.inflation_drift_duration or 4)
    end
    if effects.asset_price_mod then
        GameState.AddModifier(state,
            event.id .. "_asset_price_mod",
            "asset_price_mod",
            effects.asset_price_mod,
            effects.asset_price_duration or 4)
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
            if mod.target == "security" then
                local mineRegion = GameState.GetRegion(state, "mine_district")
                if mineRegion then
                    mineRegion.security = math.max(1, math.min(5,
                        mineRegion.security + mod.value))
                end
            elseif mod.target == "tech_bonus" then
                state.tech = state.tech or { researched = {}, in_progress = nil, bonus_points = 0 }
                state.tech.bonus_points = (state.tech.bonus_points or 0) + mod.value
            else
                GameState.AddModifier(state,
                    event.id .. "_" .. mod.target,
                    mod.target,
                    mod.value,
                    mod.duration or 0)
            end

            if mod.target == "corruption_risk" then
                AddRegulationPressure(state, math.ceil(mod.value * 0.5))
            elseif mod.target == "shadow_income" then
                AddRegulationPressure(state, math.ceil(math.max(0, mod.value) / 25))
            elseif mod.target == "legitimacy" or mod.target == "political_standing" then
                AddRegulationPressure(state, -math.floor(mod.value / 10))
            elseif mod.target == "risk" then
                AddRegulationPressure(state, math.ceil(math.max(0, mod.value) * 0.3))
            end
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

    -- 11. 兼容旧事件：没有显式 war_state 的萨拉热窝枪声仍会进入战时
    if event.id == "sarajevo_shots_1914" and effects.war_state == nil then
        state.flags = state.flags or {}
        state.flags.at_war = true
        state.flags.war_start_turn = state.turn_count
    end

    -- 12. 日志
    GameState.AddLog(state, string.format("[事件] %s → %s", event.title, option.text))

    -- 13. Toast 反馈——让玩家直观看到效果
    local parts = {}
    if effects.cash and effects.cash ~= 0 then
        local sign = effects.cash > 0 and "+" or ""
        table.insert(parts, "现金 " .. sign .. Config.FormatNumber(effects.cash))
    end
    if effects.gold and effects.gold ~= 0 then
        local sign = effects.gold > 0 and "+" or ""
        table.insert(parts, "黄金 " .. sign .. effects.gold)
    end
    if effects.gold_reserve and effects.gold_reserve ~= 0 then
        local sign = effects.gold_reserve > 0 and "+" or ""
        table.insert(parts, "金矿储量 " .. sign .. effects.gold_reserve)
    end
    if effects.workers_bonus and effects.workers_bonus ~= 0 then
        local sign = effects.workers_bonus > 0 and "+" or ""
        table.insert(parts, "工人 " .. sign .. effects.workers_bonus)
    end
    if effects.security_bonus and effects.security_bonus ~= 0 then
        local sign = effects.security_bonus > 0 and "+" or ""
        table.insert(parts, "治安 " .. sign .. effects.security_bonus)
    end
    if #parts > 0 then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(table.concat(parts, "  "), { variant = "info", duration = 2.5 })
    end
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
