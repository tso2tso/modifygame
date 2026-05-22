-- ============================================================================
-- 大国博弈核心引擎（Phase 2）
-- 每季度调用一次：历史漂移 → 继承处理 → 征服执行 → 抵抗增长 → 本地AI联动
-- ============================================================================

local PowersData = require("data.powers_data")
local EuropeData = require("data.europe_data")
local Config     = require("config")
local GameState  = require("game_state")
local Balance    = require("data.balance")

local GrandPowers = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 安全 clamp 到 [0, 100]
local function clamp100(v) return math.max(0, math.min(100, math.floor(v + 0.5))) end

--- 判断大国是否在当前年份活跃
---@param powerDef table  PowersData 定义
---@param year number
---@return boolean
local function IsPowerActive(powerDef, year)
    return year >= powerDef.active_years[1] and year <= powerDef.active_years[2]
end

--- 获取当前章节 id (1-5)
---@param year number
---@return number eraId
local function GetEraId(year)
    local era = Config.GetEraByYear(year)
    return era and era.id or 1
end

-- ============================================================================
-- 1. 初始化：在 state 中创建活跃大国运行时数据
-- ============================================================================

--- 初始化大国系统（由 game_state 在创建时调用，或首次 Tick 时懒加载）
---@param state table 游戏状态
function GrandPowers.Init(state)
    if state._gp_initialized then return end

    state.powers = {}
    state.fronts = {}
    state.collaboration_score = state.collaboration_score or 0

    -- 为初始年份活跃的大国创建运行时条目
    local allPowers = PowersData.GetAllPowers()
    for _, def in ipairs(allPowers) do
        if IsPowerActive(def, state.year) then
            GrandPowers._ActivatePower(state, def)
        end
    end

    state._gp_initialized = true
end

--- 内部：激活一个大国（创建运行时条目）
---@param state table
---@param def table PowersData 定义
function GrandPowers._ActivatePower(state, def)
    if state.powers[def.id] then return end  -- 已激活

    -- 尝试从基准线获取当前值，否则用定义的 initial
    local bl = PowersData.GetBaseline(def.id, state.year)
    local mil = bl and bl.military    or def.initial.military
    local eco = bl and bl.economy     or def.initial.economy
    local fat = bl and bl.war_fatigue or def.initial.war_fatigue

    local eraId = GetEraId(state.year)
    state.powers[def.id] = {
        id          = def.id,
        label       = def.label,
        military    = mil,
        economy     = eco,
        war_fatigue = fat,
        faction     = PowersData.GetFaction(def.id, eraId),
        war_goals   = PowersData.GetWarGoals(def.id, eraId),
        attitude_to_player = 0,
        active      = true,
    }
end

--- 内部：停用一个大国
---@param state table
---@param powerId string
function GrandPowers._DeactivatePower(state, powerId)
    if state.powers[powerId] then
        state.powers[powerId].active = false
    end
end

-- ============================================================================
-- 2. 主 Tick 函数（每季度调用一次）
-- ============================================================================

--- 大国系统每季度更新
---@param state table
---@return table report { conquest_msgs, succession_msgs }
function GrandPowers.Tick(state)
    -- 懒加载初始化
    if not state._gp_initialized then
        GrandPowers.Init(state)
    end

    local report = {
        conquest_msgs = {},
        succession_msgs = {},
    }

    local year    = state.year
    local quarter = state.quarter
    local eraId   = GetEraId(year)

    -- ── Step 1: 检查新大国是否需要激活 ──
    GrandPowers._CheckActivations(state, year)

    -- ── Step 2: 历史漂移 ──
    GrandPowers._ApplyDrift(state, year)

    -- ── Step 3: 更新阵营标签 ──
    GrandPowers._UpdateFactions(state, eraId)

    -- ── Step 4: 继承/消亡事件 ──
    GrandPowers._ProcessSuccessions(state, year, quarter, report)

    -- ── Step 4.5: 分支标记触发器（基于玩家积累行为自动激活分支）──
    GrandPowers._CheckBranchTriggers(state, year, quarter)

    -- ── Step 5: 征服事件 ──
    GrandPowers._ProcessConquests(state, year, quarter, report)

    -- ── Step 6: 抵抗增长 ──
    GrandPowers._GrowResistance(state)

    -- ── Step 7: 本地 AI 联动 ──
    GrandPowers._LinkLocalAI(state, eraId)

    -- ── Step 8: 好感度自然衰减 ──
    GrandPowers._DecayAttitudes(state)

    -- ── Step 9: 生成世界快讯 ──
    report.headline = GrandPowers._GenerateHeadline(state, report)

    return report
end

-- ============================================================================
-- 3. 各子步骤实现
-- ============================================================================

--- 检查并激活到达 active_years[1] 的大国
function GrandPowers._CheckActivations(state, year)
    local allPowers = PowersData.GetAllPowers()
    for _, def in ipairs(allPowers) do
        if IsPowerActive(def, year) and not state.powers[def.id] then
            GrandPowers._ActivatePower(state, def)
        end
    end
end

--- 历史漂移：每个活跃大国的三围向基准线漂移
--- 自适应漂移：偏离基准线超过阈值时加速回拉，防止历史线完全脱轨
function GrandPowers._ApplyDrift(state, year)
    local baseDrift = PowersData.DRIFT_RATE
    local highDrift = PowersData.DRIFT_RATE_HIGH
    local threshold = PowersData.DRIFT_DEVIATION_THRESHOLD
    for id, power in pairs(state.powers) do
        if power.active then
            local bl = PowersData.GetBaseline(id, year)
            if bl then
                -- 对每个维度独立计算漂移率：偏离大则加速回拉
                local function adaptiveDrift(current, baseline)
                    local deviation = math.abs(current - baseline)
                    if deviation > threshold then
                        return highDrift
                    end
                    return baseDrift
                end
                local milDrift = adaptiveDrift(power.military, bl.military)
                local ecoDrift = adaptiveDrift(power.economy, bl.economy)
                local fatDrift = adaptiveDrift(power.war_fatigue, bl.war_fatigue)
                power.military    = clamp100(power.military    + (bl.military    - power.military)    * milDrift)
                power.economy     = clamp100(power.economy     + (bl.economy     - power.economy)     * ecoDrift)
                power.war_fatigue = clamp100(power.war_fatigue + (bl.war_fatigue - power.war_fatigue) * fatDrift)
            end
        end
    end
end

--- 更新阵营标签（章节切换时可能变化）
function GrandPowers._UpdateFactions(state, eraId)
    for id, power in pairs(state.powers) do
        if power.active then
            local newFaction = PowersData.GetFaction(id, eraId)
            if newFaction then
                power.faction = newFaction
            end
        end
    end
end

--- 处理继承/消亡事件
function GrandPowers._ProcessSuccessions(state, year, quarter, report)
    local events = PowersData.GetSuccessionEvents(year, quarter)
    for _, ev in ipairs(events) do
        if ev.dissolve and ev.old_id then
            -- 大国消亡，不产生继承
            GrandPowers._DeactivatePower(state, ev.old_id)
            table.insert(report.succession_msgs,
                string.format("%s 已灭亡", state.powers[ev.old_id] and state.powers[ev.old_id].label or ev.old_id))

        elseif ev.create_fresh and ev.new_id then
            -- 凭空创建新大国（如铁托南斯拉夫）
            local def = PowersData.GetPowerById(ev.new_id)
            if def then
                GrandPowers._ActivatePower(state, def)
                table.insert(report.succession_msgs,
                    string.format("%s 崛起", def.label))
            end

        elseif ev.old_id and ev.new_id then
            -- 标准继承：旧 → 新
            local oldPower = state.powers[ev.old_id]

            if ev.rename_sovereign then
                -- 主权重命名：将所有旧主权替换为新主权
                if state.europe then
                    for _, country in pairs(state.europe) do
                        if country.sovereign == ev.old_id then
                            country.sovereign = ev.new_id
                        end
                    end
                end
            end

            if ev.restore_original then
                -- 恢复原主权：被旧大国占领的领土恢复独立
                if state.europe then
                    for _, country in pairs(state.europe) do
                        if country.sovereign == ev.old_id then
                            country.sovereign = country.original
                            country.resistance = 0
                        end
                    end
                end
            end

            if ev.absorb then
                -- 吸收：旧大国领土并入新大国
                if state.europe then
                    for _, country in pairs(state.europe) do
                        if country.sovereign == ev.old_id or country.original == ev.old_id then
                            country.sovereign = ev.new_id
                        end
                    end
                end
            end

            -- 停用旧大国
            GrandPowers._DeactivatePower(state, ev.old_id)

            -- 激活新大国（如果尚未存在）
            local newDef = PowersData.GetPowerById(ev.new_id)
            if newDef and not state.powers[ev.new_id] then
                GrandPowers._ActivatePower(state, newDef)
                -- 部分继承旧大国的 attitude
                if oldPower then
                    state.powers[ev.new_id].attitude_to_player =
                        math.floor(oldPower.attitude_to_player * 0.5)
                end
            end

            local oldLabel = oldPower and oldPower.label or ev.old_id
            local newLabel = newDef and newDef.label or ev.new_id
            table.insert(report.succession_msgs,
                string.format("%s → %s", oldLabel, newLabel))
        end
    end
end

-- ============================================================================
-- Step 4.5: 分支标记触发器（P2-1）
-- 基于玩家积累的行动历史，在特定年份窗口内自动激活分支标记
-- 设计原则：每个分支都需要"前期积累（合作度/行动次数）+ 窗口期"
-- ============================================================================

--- 统计行动历史中满足条件的行动次数
---@param history table[] 行动历史
---@param actionId string|nil 行动ID（nil=任意行动）
---@param powerId string|nil 目标大国（nil=任意大国）
---@param fromYear number|nil 起始年份
---@param toYear number|nil 结束年份
---@return number count
local function _CountActions(history, actionId, powerId, fromYear, toYear)
    local count = 0
    for _, entry in ipairs(history) do
        if (not actionId or entry.action == actionId)
            and (not powerId or entry.power == powerId)
            and (not fromYear or entry.year >= fromYear)
            and (not toYear or entry.year <= toYear) then
            count = count + 1
        end
    end
    return count
end

--- 检查并自动激活分支标记（基于玩家积累行为）
--- 在 Step 4（继承/消亡）之后、Step 5（征服）之前执行
function GrandPowers._CheckBranchTriggers(state, year, quarter)
    local score = state.collaboration_score or 0
    local history = state.gp_action_history or {}
    if #history == 0 then return end -- 无行动历史则跳过

    -- ──────────────────────────────────────────────
    -- 1. 战争加速 (1913-1914)
    -- 条件：合作度 ≥ 30 + 向奥匈执行过 share_intel
    -- ──────────────────────────────────────────────
    if year >= 1913 and year <= 1914
        and not state._branch_war_accelerated
        and not state._branch_war_delayed
        and not state._branch_war_prevented then
        if score >= 30
            and _CountActions(history, "share_intel", "austria_hungary") >= 1 then
            state._branch_war_accelerated = true
            GameState.AddLog(state,
                "[分支触发] 你对奥匈帝国的深度合作与情报共享加速了战争进程")
        end
    end

    -- ──────────────────────────────────────────────
    -- 2. 战争推迟 (1913-1914)
    -- 条件：合作度 ≤ -20 + 累计对大国执行 3 次经济制裁
    -- ──────────────────────────────────────────────
    if year >= 1913 and year <= 1914
        and not state._branch_war_delayed
        and not state._branch_war_accelerated
        and not state._branch_war_prevented then
        if score <= -20
            and _CountActions(history, "economic_sanction") >= 3 then
            state._branch_war_delayed = math.random(2, 4)
            GameState.AddLog(state,
                "[分支触发] 你长期的经济制裁行动削弱了列强的战争能力，一战被推迟")
        end
    end

    -- ──────────────────────────────────────────────
    -- 3. 战争阻止 (1912-1913) — 蝴蝶效应级别
    -- 条件：5 次货币战争 + 总控制度 ≥ 200（极端路线）
    -- ──────────────────────────────────────────────
    if year >= 1912 and year <= 1913
        and not state._branch_war_prevented
        and not state._branch_war_accelerated then
        local totalCtrl = GameState.CalcTotalControl(state)
        if _CountActions(history, "currency_war") >= 5 and totalCtrl >= 200 then
            state._branch_war_prevented = true
            state._branch_war_delayed = 99
            GameState.AddLog(state,
                "[分支触发·蝴蝶效应] 你的货币战争与庞大控制力重塑了欧洲格局，一战被阻止！")
        end
    end

    -- ──────────────────────────────────────────────
    -- 4. 奥匈联邦化 (1916-1917)
    -- 条件：合作路线 — 对奥匈好感 ≥ 50 + 合作度 ≥ 40
    -- ──────────────────────────────────────────────
    if year >= 1916 and year <= 1917
        and not state._branch_ah_federalized then
        local ah = state.powers and state.powers["austria_hungary"]
        if ah and ah.active
            and ah.attitude_to_player >= 50
            and score >= 40 then
            state._branch_ah_federalized = true
            -- 联邦化效果：奥匈军事削弱但不解体
            ah.military = math.max(10, ah.military - 15)
            ah.war_fatigue = math.max(0, ah.war_fatigue - 10)
            ah.attitude_to_player = math.min(100, ah.attitude_to_player + 15)
            GameState.AddLog(state,
                "[分支触发] 你与奥匈帝国的深度合作推动了联邦化改革，帝国改组为多民族联邦")
        end
    end

    -- ──────────────────────────────────────────────
    -- 5. 南斯拉夫中立 (1940-1941)
    -- 条件：对南斯拉夫好感 ≥ 30 + 执行 shelter_refugees ≥ 2 次
    -- ──────────────────────────────────────────────
    if year >= 1940 and year <= 1941
        and not state._branch_yugo_neutral then
        -- 南斯拉夫在不同时期有不同 ID
        local yugo = state.powers
            and (state.powers["yugoslavia"] or state.powers["tito_yugoslavia"])
        if yugo and yugo.active
            and (yugo.attitude_to_player or 0) >= 30
            and _CountActions(history, "shelter_refugees") >= 2 then
            state._branch_yugo_neutral = true
            GameState.AddLog(state,
                "[分支触发] 你的难民庇护行动和外交努力使南斯拉夫暂时维持中立")
        end
    end

    -- ──────────────────────────────────────────────
    -- 6. 自我解放 (1943-1944)
    -- 条件：抵抗路线 — 合作度 ≤ -50 + 武装 ≥ 25 + 支持游击队 ≥ 3 次
    -- ──────────────────────────────────────────────
    if year >= 1943 and year <= 1944
        and not state._branch_self_liberation then
        local guards = state.military and state.military.guards or 0
        if score <= -50 and guards >= 25
            and _CountActions(history, "support_guerrilla") >= 3 then
            state._branch_self_liberation = true
            -- 自我解放效果：控制度大幅提升
            for _, r in ipairs(state.regions) do
                r.control = math.min(100, (r.control or 0) + 10)
            end
            GameState.AddLog(state,
                "[分支触发] 你的长期抵抗与军事准备使自主解放成为可能！萨拉热窝率先起义")
        end
    end
end

--- 公开接口：执行单次征服（修改主权 + war_fatigue + covert_bonus），供 turn_engine C3 调用
---@param state table
---@param attackerId string  攻击方大国 ID
---@param targetId   string  被征服国家 ID
---@param report     table   { conquest_msgs, ... }，若 nil 则不写报告
function GrandPowers.ApplyConquest(state, attackerId, targetId, report)
    local target = state.europe and state.europe[targetId]
    if not target then return end

    EuropeData.ChangeSovereignty(state.europe, targetId, attackerId)

    local attackerPower = state.powers[attackerId]
    if attackerPower then
        local fatInc = (target.tier == "major") and 8 or 3
        local covertBonus = (state.modifiers or {})["covert_military_bonus_" .. attackerId] or 0
        if covertBonus > 0 then
            fatInc = math.floor(fatInc * (1 - covertBonus))
        end
        attackerPower.war_fatigue = clamp100(attackerPower.war_fatigue + fatInc)
    end

    if report then
        local attackerLabel = (attackerPower and attackerPower.label) or attackerId
        table.insert(report.conquest_msgs,
            string.format("%s 征服了 %s", attackerLabel, target.label))
    end
    GameState.AddLog(state, string.format("大国动态：%s 征服了 %s",
        (attackerPower and attackerPower.label) or attackerId, target.label))
end

--- 处理征服事件（含分支标记影响）
function GrandPowers._ProcessConquests(state, year, quarter, report)
    local events = PowersData.GetConquestEvents(year, quarter)

    -- ── 分支标记：战争加速 ──
    -- 协助刺杀后，下一季度的一战征服事件提前触发
    if state._branch_war_accelerated and year >= 1914 and year <= 1918 then
        local nextQ = quarter + 1
        local nextY = year
        if nextQ > 4 then nextQ = 1; nextY = nextY + 1 end
        local nextEvents = PowersData.GetConquestEvents(nextY, nextQ)
        for _, ev in ipairs(nextEvents) do
            if ev.year >= 1914 and ev.year <= 1918 then
                table.insert(events, ev)
            end
        end
        -- 记录被提前执行的季度，下季度跳过这些事件防止双重执行
        state._war_accel_done = { year = nextY, quarter = nextQ }
        state._branch_war_accelerated = false  -- 加速只生效一次
    end

    -- 跳过已被加速提前执行过的事件
    if state._war_accel_done
        and state._war_accel_done.year == year
        and state._war_accel_done.quarter == quarter then
        -- 本季度事件已在上季度被提前执行，过滤掉一战区间事件
        local filtered = {}
        for _, ev in ipairs(events) do
            if not (ev.year >= 1914 and ev.year <= 1918) then
                table.insert(filtered, ev)
            end
        end
        events = filtered
        state._war_accel_done = nil  -- 清除标记
    end

    -- ── 分支标记：战争推迟 ──
    -- _branch_war_delayed > 0 时，一战事件（1914-1918）被推迟
    local warDelay = state._branch_war_delayed or 0
    if warDelay > 0 and year >= 1914 and year <= 1918 then
        -- 每季度消耗1点推迟
        state._branch_war_delayed = warDelay - 1
        -- 跳过本季度所有一战征服事件
        local filtered = {}
        for _, ev in ipairs(events) do
            if ev.year >= 1914 and ev.year <= 1918 then
                -- 被推迟的事件：重新入队到时间线的延后位置（下季度再检查）
                -- 简化处理：直接跳过，漂移系统会自然推进
            else
                table.insert(filtered, ev)
            end
        end
        events = filtered
        if #events == 0 then return end
    end

    -- ── 分支标记：战争阻止 ──
    if state._branch_war_prevented and year >= 1914 and year <= 1918 then
        -- 跳过所有一战征服事件
        local filtered = {}
        for _, ev in ipairs(events) do
            if not (ev.year >= 1914 and ev.year <= 1918) then
                table.insert(filtered, ev)
            end
        end
        events = filtered
    end

    -- ── 分支标记：奥匈联邦化 ──
    if state._branch_ah_federalized then
        -- 跳过 1918 年解放事件（奥匈不完全解体）
        local filtered = {}
        for _, ev in ipairs(events) do
            if not (ev.year == 1918 and ev.action == "liberate") then
                table.insert(filtered, ev)
            end
        end
        events = filtered
    end

    -- ── 分支标记：南斯拉夫中立 ──
    if state._branch_yugo_neutral then
        -- 1941年对南斯拉夫/塞尔维亚/黑山的征服推迟（跳过本次）
        local filtered = {}
        for _, ev in ipairs(events) do
            local isYugoTarget = (ev.target == "yugoslavia" or ev.target == "serbia" or ev.target == "montenegro")
            if ev.year == 1941 and isYugoTarget and ev.action == "conquer" then
                -- 跳过（中立持续到 1941 Q4 自动失效）
                if quarter >= 4 then
                    state._branch_yugo_neutral = false  -- 中立失效
                    table.insert(filtered, ev)
                end
            else
                table.insert(filtered, ev)
            end
        end
        events = filtered
    end

    -- ── 分支标记：自我解放 ──
    if state._branch_self_liberation then
        -- 跳过 1944 Q4 铁托解放事件（已自行解放）
        local filtered = {}
        for _, ev in ipairs(events) do
            if ev.year == 1944 and ev.quarter == 4 and ev.attacker == "tito_yugoslavia" then
                -- 已自行解放，跳过
            else
                table.insert(filtered, ev)
            end
        end
        events = filtered
    end

    for _, ev in ipairs(events) do
        if not state.europe then break end

        local target = state.europe[ev.target]
        if not target then goto continue end

        if ev.action == "conquer" then
            -- 征服：复用公开接口（主权变更 + war_fatigue + covert_bonus）
            GrandPowers.ApplyConquest(state, ev.attacker, ev.target, report)

        elseif ev.action == "liberate" then
            -- 解放：恢复原主权
            local oldSovereign = target.sovereign
            target.sovereign = target.original
            target.resistance = 0

            local liberatorLabel = ev.attacker
            -- 尝试获取解放方的 label
            if state.powers[ev.attacker] then
                liberatorLabel = state.powers[ev.attacker].label
            elseif ev.attacker == "entente" then
                liberatorLabel = "协约国"
            elseif ev.attacker == "allies" then
                liberatorLabel = "同盟国"
            end

            table.insert(report.conquest_msgs,
                string.format("%s 解放了 %s", liberatorLabel, target.label))

            GameState.AddLog(state, string.format("大国动态：%s 解放了 %s", liberatorLabel, target.label))

        elseif ev.action == "annex" then
            -- 和平吞并（如德奥合并）
            EuropeData.ChangeSovereignty(state.europe, ev.target, ev.attacker)

            local attackerPower = state.powers[ev.attacker]
            local attackerLabel = attackerPower and attackerPower.label or ev.attacker
            table.insert(report.conquest_msgs,
                string.format("%s 吞并了 %s", attackerLabel, target.label))

            GameState.AddLog(state, string.format("大国动态：%s 吞并了 %s", attackerLabel, target.label))
        end

        ::continue::
    end
end

--- 好感度自然衰减：每季所有活跃大国的 attitude_to_player 向0靠拢
--- 设计意图：好感不再一劳永逸，需要持续维护外交关系
function GrandPowers._DecayAttitudes(state)
    local cfg = Balance.ATTITUDE_DECAY
    if not cfg then return end
    -- military_relation 修正器：正值减缓好感衰减，负值加速衰减
    local milRelMod = GameState.GetModifierValue(state, "military_relation")
    for _, power in pairs(state.powers) do
        if power.active then
            local att = power.attitude_to_player or 0
            if math.abs(att) > cfg.threshold then
                local decay = math.min(
                    math.abs(att) * cfg.rate,
                    cfg.cap_per_turn
                )
                decay = math.max(1, math.floor(decay + 0.5))
                -- military_relation 调整衰减速度：正值减缓，负值加速
                if milRelMod ~= 0 then
                    local factor = 1 - milRelMod * 0.03  -- +15 → ×0.55 衰减, -5 → ×1.15 衰减
                    decay = math.max(0, math.floor(decay * factor + 0.5))
                end
                if att > 0 then
                    power.attitude_to_player = att - decay
                else
                    power.attitude_to_player = att + decay
                end
            end
        end
    end
end

--- 生成本季最重要的世界快讯标题
--- 优先级：征服 > 继承 > 大国军事剧变
---@param state table
---@param report table Tick产出的report
---@return string|nil headline
function GrandPowers._GenerateHeadline(state, report)
    -- 1. 征服事件（最高优先）
    if report.conquest_msgs and #report.conquest_msgs > 0 then
        return report.conquest_msgs[1]
    end
    -- 2. 继承/消亡事件
    if report.succession_msgs and #report.succession_msgs > 0 then
        return report.succession_msgs[1]
    end
    -- 3. 大国军事或经济剧变（与上季对比变化最大的）
    local bestDelta = 0
    local bestMsg = nil
    for id, power in pairs(state.powers) do
        if power.active then
            local bl = PowersData.GetBaseline(id, state.year)
            if bl then
                local milDelta = math.abs(power.military - bl.military)
                local ecoDelta = math.abs(power.economy - bl.economy)
                if milDelta > bestDelta then
                    bestDelta = milDelta
                    local dir = power.military > bl.military and "增强" or "衰退"
                    bestMsg = string.format("%s 军事力量%s（当前 %d）",
                        power.label, dir, power.military)
                end
                if ecoDelta > bestDelta then
                    bestDelta = ecoDelta
                    local dir = power.economy > bl.economy and "繁荣" or "萧条"
                    bestMsg = string.format("%s 经济%s（当前 %d）",
                        power.label, dir, power.economy)
                end
            end
        end
    end
    -- 偏离超过15才算"剧变"
    if bestDelta >= 15 and bestMsg then
        return bestMsg
    end
    return nil
end

--- 抵抗增长：被占领国家每季度抵抗度 +2（本地加固时+4，纳粹合作者时轴心占领区-1）
function GrandPowers._GrowResistance(state)
    if not state.europe then return end

    -- 轴心国 ID 列表（用于判断纳粹合作者分支的作用范围）
    local AXIS_POWERS = { nazi_germany = true, italy = true, hungary = true, bulgaria = true }
    -- 玩家本地区域（加固分支仅影响这些区域）
    local LOCAL_REGIONS = { austria_hungary = true, serbia = true, bosnia = true, montenegro = true }
    local AUTO_LIBERATE_THRESHOLD = 95

    for id, country in pairs(state.europe) do
        if country.sovereign ~= country.original then
            -- 被占领，计算本国的抵抗增长值
            local growth = 2
            -- 加固分支：仅影响玩家本地区域，抵抗翻倍
            if state._branch_fortified and LOCAL_REGIONS[id] then
                growth = 4
            end
            -- 纳粹合作者分支：仅影响轴心国占领的国家，占领方压制较温和
            if state._branch_nazi_collaborator and state.year >= 1941 and state.year <= 1945
                and AXIS_POWERS[country.sovereign] then
                growth = math.max(1, growth - 1)
            end
            -- 稳定度影响：低稳定度（<80）加速抵抗增长（share_intel 等行动的效果）
            local stab = country.stability or 100
            if stab < 80 then
                -- 稳定度每低于80减10点，抵抗增长+25%（如60稳定度→+50%）
                local stabMult = 1 + (80 - stab) * 0.025
                growth = math.floor(growth * stabMult + 0.5)
            end
            -- 合作度"人民英雄"加成：抵抗增长 +15%
            local resistBonus = GameState.GetModifierValue(state, "resistance_growth_bonus")
            if resistBonus > 0 then
                growth = math.floor(growth * (1 + resistBonus) + 0.5)
            end
            country.resistance = math.min(100, (country.resistance or 0) + growth)

            -- 抵抗达到阈值 → 自动解放
            if country.resistance >= AUTO_LIBERATE_THRESHOLD then
                local oldSovereign = country.sovereign
                country.sovereign = country.original
                country.resistance = 0

                -- 占领方 war_fatigue 增加（镇压失败的代价）
                if state.powers[oldSovereign] and state.powers[oldSovereign].active then
                    state.powers[oldSovereign].war_fatigue =
                        clamp100(state.powers[oldSovereign].war_fatigue + 5)
                end

                GameState.AddLog(state,
                    string.format("大国动态：%s 人民起义，成功自我解放！", country.label))
            end
        else
            -- 未被占领，抵抗归零
            country.resistance = 0
        end
    end
end

--- 本地 AI 联动：根据当前控制萨拉热窝的大国，调整本地 AI 参数
function GrandPowers._LinkLocalAI(state, eraId)
    if not state.ai_factions then return end

    -- 萨拉热窝的主权随 austria_hungary（或其继承国）的命运变化
    -- 判断玩家所在地区当前的宗主国
    local localSovereign = nil
    if state.europe then
        -- 找到 austria_hungary 或其继承国当前控制的实体
        local ah = state.europe["austria_hungary"]
        if ah then
            localSovereign = ah.sovereign
        end
    end

    -- 根据大国系统调整本地 AI 的态度倾向和增长率
    for _, faction in ipairs(state.ai_factions) do
        -- 找到该 AI 的幕后大国
        local proxyPower = nil
        for _, power in pairs(state.powers) do
            if power.active then
                local def = PowersData.GetPowerById(power.id)
                if def and def.local_proxy == faction.type then
                    proxyPower = power
                    break
                end
            end
        end

        if proxyPower then
            -- 幕后大国的经济实力影响本地 AI 的增长率修正
            local ecoFactor = (proxyPower.economy - 50) / 500  -- -0.10 ~ +0.10
            -- 经济联动：大国经济强→代理人获得现金注入；大国经济弱→代理人现金流出
            if ecoFactor > 0 then
                local cashBoost = math.floor(faction.cash * ecoFactor)
                faction.cash = faction.cash + cashBoost
                -- 强制 cashCap（与 turn_engine.lua AI 现金上限保持一致）
                local aiConfig = Balance.AI or {}
                local cashCap = aiConfig.cash_cap or 10000
                local eraScaling = aiConfig.era_scaling
                if eraScaling then
                    for i = #eraScaling, 1, -1 do
                        if state.year >= eraScaling[i].year then
                            cashCap = math.floor(cashCap * (eraScaling[i].cash_cap_mul or 1.0))
                            break
                        end
                    end
                end
                if faction.cash > cashCap then
                    faction.cash = cashCap
                end
            elseif ecoFactor < 0 then
                local cashDrain = math.floor(faction.cash * math.abs(ecoFactor))
                faction.cash = math.max(0, faction.cash - cashDrain)
            end
            -- 幕后大国厌战时，代理人力量削弱
            if proxyPower.war_fatigue > 60 then
                -- 高厌战 → 代理人支持减弱
                local penalty = math.floor((proxyPower.war_fatigue - 60) / 10)
                faction.power = math.max(0, faction.power - penalty)
            end
        end
    end
end

-- ============================================================================
-- 公开查询 API（供 UI 和其他系统调用）
-- ============================================================================

--- 获取所有活跃大国的运行时数据
---@param state table
---@return table[] activePowers
function GrandPowers.GetActivePowers(state)
    local result = {}
    if not state.powers then return result end
    for _, power in pairs(state.powers) do
        if power.active then
            table.insert(result, power)
        end
    end
    -- 按 military 降序排列
    table.sort(result, function(a, b) return a.military > b.military end)
    return result
end

--- 获取某大国当前控制的领土列表
---@param state table
---@param powerId string
---@return table[] countries
function GrandPowers.GetControlledTerritories(state, powerId)
    if not state.europe then return {} end
    local result = {}
    for id, country in pairs(state.europe) do
        if country.sovereign == powerId then
            table.insert(result, country)
        end
    end
    return result
end

--- 获取某大国的前线状态（正在进攻哪些目标）
---@param state table
---@param powerId string
---@return table[] frontLines
function GrandPowers.GetFrontLines(state, powerId)
    -- Phase 2 简化：直接从征服时间线推算当前前线
    -- 完整前线系统将在 Phase 5 实现
    local result = {}
    local power = state.powers and state.powers[powerId]
    if not power or not power.war_goals then return result end

    for _, goalId in ipairs(power.war_goals) do
        local target = state.europe and state.europe[goalId]
        if target and target.sovereign == target.original then
            -- 目标尚未被征服，是活跃前线
            table.insert(result, {
                target_id = goalId,
                target_label = target.label,
                status = "active",
            })
        elseif target and target.sovereign == powerId then
            -- 已征服
            table.insert(result, {
                target_id = goalId,
                target_label = target.label,
                status = "conquered",
            })
        end
    end
    return result
end

--- 判断萨拉热窝当前是否处于被占领状态
---@param state table
---@return boolean isOccupied, string|nil occupierId
function GrandPowers.IsSarajevoOccupied(state)
    if not state.europe then return false, nil end
    local ah = state.europe["austria_hungary"]
    if not ah then return false, nil end

    -- 萨拉热窝的命运跟随 austria_hungary 区域
    if ah.sovereign ~= ah.original then
        return true, ah.sovereign
    end

    -- 还需要检查南斯拉夫继承的情况
    -- 如果 yugoslavia 或 tito_yugoslavia 存在且被占领
    local yugo = state.europe["serbia"]  -- 塞尔维亚区域代表南斯拉夫核心
    if yugo and yugo.sovereign ~= yugo.original and yugo.sovereign ~= "yugoslavia"
        and yugo.sovereign ~= "tito_yugoslavia" then
        return true, yugo.sovereign
    end

    return false, nil
end

return GrandPowers
