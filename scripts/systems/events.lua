-- ============================================================================
-- 事件系统：检查触发条件、入队、应用效果
-- ============================================================================

local GameState = require("game_state")
local EventsData = require("data.events_data")
local Balance = require("data.balance")
local StockEngine = require("systems.stock_engine")
local EventMarketEffects = require("data.event_market_effects")
local Config = require("config")

local BranchEvents = nil  -- 延迟加载，避免循环依赖

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
    -- 难度系数
    local diff = Config.GetDifficulty(state.difficulty)

    -- 保底机制：连续无事件时概率提升（阈值受难度影响）
    local drought = state.event_drought_counter or 0
    local chanceMultiplier = 1.0
    if drought >= diff.drought_threshold_3 then
        chanceMultiplier = 2.0
    elseif drought >= diff.drought_threshold_2 then
        chanceMultiplier = 1.5
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
                -- 概率检查（带保底乘数 + 难度系数）
                local effectiveChance = (event.chance or 0.1) * chanceMultiplier * diff.event_chance_mult
                -- 事件自带的概率修正（基于游戏状态中的 modifier）
                if event.chance_modifier then
                    local modVal = GameState.GetModifierValue(state, event.chance_modifier)
                    if modVal ~= 0 then
                        effectiveChance = effectiveChance * (1 + modVal)
                    end
                end
                -- 前期缓冲：early_shield_years 之前降低随机事件概率
                local shieldYear = diff.early_shield_years or 1905
                if state.year and state.year <= shieldYear then
                    effectiveChance = effectiveChance * 0.4
                end
                if math.random() < effectiveChance then
                    table.insert(triggered, event)
                    randomCount = randomCount + 1
                end
            end
        end
    end

    -- 3. 检查灾害事件（独立触发池，不受保底机制影响）
    -- 开局前 16 季度（1904-1907）完全免疫，由 min_year >= 1908 保证
    local disasterTemplates = EventsData.GetDisasterEventTemplates()
    local shuffledDisasters = {}
    for _, e in ipairs(disasterTemplates) do table.insert(shuffledDisasters, e) end
    for i = #shuffledDisasters, 2, -1 do
        local j = math.random(1, i)
        shuffledDisasters[i], shuffledDisasters[j] = shuffledDisasters[j], shuffledDisasters[i]
    end

    local disasterCount = 0
    local maxDisaster = 1  -- 每季最多触发 1 个灾害
    for _, event in ipairs(shuffledDisasters) do
        if disasterCount >= maxDisaster then break end
        if Events._CheckTrigger(state, event) then
            local cd = state.random_cooldowns[event.id] or 0
            if cd <= 0 then
                local effectiveChance = (event.chance or 0.05) * (diff.disaster_chance_mult or diff.event_chance_mult)
                -- 灾害自带的概率修正
                if event.chance_modifier then
                    local modVal = GameState.GetModifierValue(state, event.chance_modifier)
                    if modVal ~= 0 then
                        effectiveChance = effectiveChance * (1 + modVal)
                    end
                end
                -- 灾害事件不享受保底加成（不用 chanceMultiplier）
                -- 灾害事件不使用早期概率衰减（由 min_year 硬性屏蔽）
                if math.random() < effectiveChance then
                    table.insert(triggered, event)
                    disasterCount = disasterCount + 1
                end
            end
        end
    end

    -- 4. 更新事件干旱计数器（灾害事件不计入，仅标准随机事件参与保底）
    if randomCount > 0 then
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
        if mineRegion and GameState.HasControlMilestone(state, 80) then
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
        if mineRegion and (mineRegion.development or 0) < trigger.min_development then
            return false
        end
    end

    -- 最低声誉（注意：声誉为负数，min_reputation = -20 表示声誉 <= -20 才触发）
    if trigger.min_reputation then
        if (state.reputation or 0) > trigger.min_reputation then
            return false
        end
    end

    -- 需要已强占矿脉
    if trigger.has_seized_veins then
        if not state.has_seized_veins then
            return false
        end
    end

    -- 最低护卫数
    if trigger.min_guards then
        local guards = 0
        local mineRegion = GameState.GetRegion(state, "mine_district")
        if mineRegion then
            guards = mineRegion.guards or 0
        end
        if guards < trigger.min_guards then
            return false
        end
    end

    -- 最低控制度（使用所有地区总和）
    if trigger.min_control then
        if GameState.CalcTotalControl(state) < trigger.min_control then
            return false
        end
    end

    -- 需要特定科技已研究（单个 string）
    if trigger.requires_tech then
        local researched = state.tech and state.tech.researched or {}
        if not researched[trigger.requires_tech] then
            return false
        end
    end

    -- 需要任意一个科技已研究（数组，OR 逻辑）
    if trigger.requires_tech_any then
        local researched = state.tech and state.tech.researched or {}
        local anyMet = false
        for _, tid in ipairs(trigger.requires_tech_any) do
            if researched[tid] then anyMet = true; break end
        end
        if not anyMet then return false end
    end

    -- 自定义触发条件（用于远征制裁等复杂逻辑）
    if trigger.custom then
        if not trigger.custom(state) then
            return false
        end
    end

    return true
end

-- ============================================================================
-- Market Intel 事件处理（type = "market_intel"）
-- ============================================================================

--- 股票名称映射
local STOCK_NAMES = {
    sarajevo_mining  = "萨拉热窝矿业",
    imperial_railway = "帝国铁路",
    balkan_shipping  = "巴尔干航运",
    military_industry = "军工联合体",
    austro_bank_trust = "奥匈银行信托",
    oriental_trading  = "东方贸易公司",
    balkan_press      = "巴尔干新闻社",
}

--- 板块名称映射
local SECTOR_NAMES = {
    mining    = "矿业",
    transport = "运输",
    military  = "军工",
    finance   = "金融",
    trade     = "贸易",
    media     = "媒体",
}

--- 解析 target_mode，返回 { target_stock_id, target_sector, stock_name, sector_name }
---@param state table
---@param event table
---@return table|nil info  目标信息，nil 表示无有效目标
local function ResolveMarketIntelTarget(state, event)
    local mode = event.target_mode
    if not mode then return nil end

    if mode == "random_stock_exclude_press" then
        -- 随机选择一只非新闻社股票
        local candidates = {}
        for _, stock in ipairs(state.stocks or {}) do
            if stock.id ~= "balkan_press" then
                table.insert(candidates, stock)
            end
        end
        if #candidates == 0 then return nil end
        local pick = candidates[math.random(1, #candidates)]
        return {
            target_stock_id = pick.id,
            stock_name = STOCK_NAMES[pick.id] or pick.id,
            sector_name = SECTOR_NAMES[pick.sector] or pick.sector,
        }

    elseif mode == "random_sector" then
        -- 随机选择一个有股票的 sector（排除 media）
        local sectorSet = {}
        for _, stock in ipairs(state.stocks or {}) do
            if stock.sector and stock.sector ~= "media" then
                sectorSet[stock.sector] = true
            end
        end
        local sectors = {}
        for s in pairs(sectorSet) do table.insert(sectors, s) end
        if #sectors == 0 then return nil end
        local pick = sectors[math.random(1, #sectors)]
        return {
            target_sector = pick,
            sector_name = SECTOR_NAMES[pick] or pick,
        }

    elseif mode == "war_rumor" then
        -- 固定影响军工 + 航运，无需动态目标
        return {
            target_stock_id = "military_industry",
            stock_name = STOCK_NAMES["military_industry"],
            sector_name = SECTOR_NAMES["military"],
        }
    end

    return nil
end

--- 将 {target} / {sector} 占位符替换为实际 stock_id / sector 的 stock_id 列表
---@param mods table[]  event_market_effects 的效果数组
---@param info table    ResolveMarketIntelTarget 返回的 info
---@param state table   游戏状态（用于 sector → stock_id 列表）
---@return table[] resolved  替换后的效果数组
local function ResolveEffectPlaceholders(mods, info, state)
    local resolved = {}
    for _, mod in ipairs(mods) do
        if mod.stock_id == "{target}" then
            if info.target_stock_id then
                table.insert(resolved, {
                    stock_id = info.target_stock_id,
                    delta_mu = mod.delta_mu,
                    duration = mod.duration,
                })
            end
        elseif mod.stock_id == "{sector}" then
            -- 板块所有股票都受影响
            local sectorId = info.target_sector
            if sectorId then
                for _, stock in ipairs(state.stocks or {}) do
                    if stock.sector == sectorId then
                        table.insert(resolved, {
                            stock_id = stock.id,
                            delta_mu = mod.delta_mu,
                            duration = mod.duration,
                        })
                    end
                end
            end
        else
            -- 直接使用（如 war_rumor 中的固定 stock_id）
            table.insert(resolved, {
                stock_id = mod.stock_id,
                delta_mu = mod.delta_mu,
                duration = mod.duration,
            })
        end
    end
    return resolved
end

--- 替换消息文本中的 {stock_name} / {sector_name} 占位符
local function ReplaceMessagePlaceholders(msg, info)
    if not msg then return "" end
    if info.stock_name then
        msg = msg:gsub("{stock_name}", info.stock_name)
    end
    if info.sector_name then
        msg = msg:gsub("{sector_name}", info.sector_name)
    end
    return msg
end

--- 处理 market_intel 事件：解析目标、应用股价效果、生成消息
--- 返回 turn_message 表（供 ui_manager 展示新闻快报弹窗）
---@param state table
---@param event table
---@return table|nil message  { title, public, hint, intel, event_id }
function Events.ApplyMarketIntel(state, event)
    -- 1. 解析目标
    local info = ResolveMarketIntelTarget(state, event)
    if not info then return nil end

    -- 2. 获取效果映射并替换占位符
    local rawMods = EventMarketEffects.Get(event.id)
    if rawMods then
        local resolved = ResolveEffectPlaceholders(rawMods, info, state)
        for _, mod in ipairs(resolved) do
            StockEngine.ApplyEventModifier(state,
                mod.stock_id, mod.delta_mu, mod.duration,
                event.id)
        end
    end

    -- 3. 标记已触发 + 设置冷却
    state.events_fired[event.id] = true
    if event.trigger and event.trigger.cooldown then
        state.random_cooldowns[event.id] = event.trigger.cooldown
    end

    -- 4. 判断文化顾问等级
    local advisorBonus = GameState.GetPositionBonus(state, "culture_advisor")
    local advisorLevel = "none"  -- 无顾问
    if advisorBonus >= 1.0 then
        advisorLevel = "excellent"  -- 满配
    elseif advisorBonus > 0 then
        advisorLevel = "normal"  -- 在任但非满配
    end

    -- 5. 构造消息
    local publicText = ReplaceMessagePlaceholders(event.public_message, info)
    local hintText = ReplaceMessagePlaceholders(event.hint_message, info)
    local intelText = ReplaceMessagePlaceholders(event.intel_message, info)

    local message = {
        type = "market_intel",
        event_id = event.id,
        title = event.title,
        icon = event.icon or "📰",
        public = publicText,
        hint = (advisorLevel ~= "none") and hintText or nil,
        intel = (advisorLevel == "excellent") and intelText or nil,
        advisor_level = advisorLevel,
    }

    -- 6. 日志
    GameState.AddLog(state, string.format("[市场情报] %s", event.title))

    return message
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

    -- 分支事件委托给 BranchEvents 模块处理
    if event._is_branch then
        if not BranchEvents then
            BranchEvents = require("systems.branch_events")
        end
        local handled = BranchEvents.ApplyBranchOption(state, event, optionIndex)
        if handled then
            -- 标记已触发 + 日志 + Toast
            state.events_fired[event.id] = true
            GameState.AddLog(state, string.format("[分支事件] %s → %s", event.title, option.text))

            -- collaboration_score 变化 Toast
            local cs = option.effects and option.effects.collaboration_score
            if cs and cs ~= 0 then
                local sign = cs > 0 and "+" or ""
                local UI = require("urhox-libs/UI")
                UI.Toast.Show(string.format("合作度 %s%d", sign, cs),
                    { variant = cs > 0 and "warning" or "success", duration = 2.5 })
            end
            return
        end
    end

    local effects = option.effects or {}

    -- 1. 直接资源效果（cash 乘以通胀系数，让费用/收益随通胀动态缩放）
    if effects.cash then
        local inflationFactor = state.inflation_factor or 1.0
        local adjustedCash = math.floor(effects.cash * inflationFactor)
        state.cash = state.cash + adjustedCash
    end
    if effects.gold then
        state.gold = math.max(0, state.gold + effects.gold)
    end
    if effects.gold_reserve then
        -- 将储量增量分配到矿区的各矿山独立储量上（均分），
        -- 避免被 _SyncRegionGoldReserve 覆盖
        local regionMines = {}
        for _, mine in ipairs(state.mines) do
            if (mine.region_id or "mine_district") == "mine_district" and mine.active then
                table.insert(regionMines, mine)
            end
        end
        if #regionMines > 0 then
            local perMine = math.floor(effects.gold_reserve / #regionMines)
            local remainder = effects.gold_reserve - perMine * #regionMines
            for i, mine in ipairs(regionMines) do
                local bonus = perMine + (i <= remainder and 1 or 0)
                mine.reserve = math.max(0, (mine.reserve or 0) + bonus)
                mine.initial_reserve = math.max(mine.initial_reserve or 0, mine.reserve or 0)
            end
        end
        -- 同步 region 显示值
        local region = GameState.GetRegion(state, "mine_district")
        if region then
            local total = 0
            for _, mine in ipairs(state.mines) do
                if (mine.region_id or "mine_district") == "mine_district" then
                    total = total + math.max(0, mine.reserve or 0)
                end
            end
            region.resources.gold_reserve = total
        end
    end

    -- 1.5 历史事件对宏观环境的直接冲击
    if effects.inflation_delta then
        -- 乘法模型：delta 作为百分比冲击，factor *= (1 + delta)
        state.inflation_factor = ClampInflation((state.inflation_factor or 1.0) * (1 + effects.inflation_delta))
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

    -- 6. 劳工满意度修正（立即应用）
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

    -- 6.1 战意修正（立即应用）
    local guardMoraleMod = GameState.GetModifierValue(state, "guard_morale")
    if guardMoraleMod ~= 0 then
        state.military.morale = math.max(0, math.min(100,
            state.military.morale + guardMoraleMod))
        local kept = {}
        for _, m in ipairs(state.modifiers) do
            if m.target ~= "guard_morale" then
                table.insert(kept, m)
            end
        end
        state.modifiers = kept
    end

    -- 6.5 声誉修正（立即应用到 state.reputation）
    local repMod = GameState.GetModifierValue(state, "reputation_penalty")
    if repMod ~= 0 then
        local BRep = Balance.REPUTATION
        state.reputation = math.max(BRep.min,
            math.min(BRep.max, (state.reputation or 0) + repMod))
        local kept = {}
        for _, m in ipairs(state.modifiers) do
            if m.target ~= "reputation_penalty" then
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
        local inflationFactor = state.inflation_factor or 1.0
        local displayCash = math.floor(effects.cash * inflationFactor)
        local sign = displayCash > 0 and "+" or ""
        table.insert(parts, "现金 " .. sign .. Config.FormatNumber(displayCash))
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
