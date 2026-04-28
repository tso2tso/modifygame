-- ============================================================================
-- 大国博弈核心引擎（Phase 2）
-- 每季度调用一次：历史漂移 → 继承处理 → 征服执行 → 抵抗增长 → 本地AI联动
-- ============================================================================

local PowersData = require("data.powers_data")
local EuropeData = require("data.europe_data")
local Config     = require("config")
local GameState  = require("game_state")

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

    -- ── Step 5: 征服事件 ──
    GrandPowers._ProcessConquests(state, year, quarter, report)

    -- ── Step 6: 抵抗增长 ──
    GrandPowers._GrowResistance(state)

    -- ── Step 7: 本地 AI 联动 ──
    GrandPowers._LinkLocalAI(state, eraId)

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
function GrandPowers._ApplyDrift(state, year)
    local driftRate = PowersData.DRIFT_RATE
    for id, power in pairs(state.powers) do
        if power.active then
            local bl = PowersData.GetBaseline(id, year)
            if bl then
                power.military    = clamp100(power.military    + (bl.military    - power.military)    * driftRate)
                power.economy     = clamp100(power.economy     + (bl.economy     - power.economy)     * driftRate)
                power.war_fatigue = clamp100(power.war_fatigue + (bl.war_fatigue - power.war_fatigue) * driftRate)
            end
        end
    end
end

--- 更新阵营标签（章节切换时可能变化）
function GrandPowers._UpdateFactions(state, eraId)
    for id, power in pairs(state.powers) do
        if power.active then
            local newFaction = PowersData.GetFaction(id, eraId)
            if newFaction and newFaction ~= "neutral" then
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
        state._branch_war_accelerated = false  -- 加速只生效一次
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
            -- 征服：目标主权转为攻击方
            local attackerId = ev.attacker
            EuropeData.ChangeSovereignty(state.europe, ev.target, attackerId)

            -- 攻击方 war_fatigue 增加
            local attackerPower = state.powers[attackerId]
            if attackerPower then
                local fatInc = (target.tier == "major") and 8 or 3
                attackerPower.war_fatigue = clamp100(attackerPower.war_fatigue + fatInc)
            end

            local attackerLabel = attackerPower and attackerPower.label or attackerId
            table.insert(report.conquest_msgs,
                string.format("%s 征服了 %s", attackerLabel, target.label))

            GameState.AddLog(state, string.format("大国动态：%s 征服了 %s", attackerLabel, target.label))

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

--- 抵抗增长：被占领国家每季度抵抗度 +2（本地加固时+4）
function GrandPowers._GrowResistance(state)
    if not state.europe then return end

    -- 分支标记影响抵抗增长
    local RESISTANCE_GROWTH = 2
    if state._branch_fortified then
        RESISTANCE_GROWTH = 4  -- 加固后抵抗翻倍
    end
    if state._branch_nazi_collaborator and state.year >= 1941 and state.year <= 1945 then
        RESISTANCE_GROWTH = math.max(1, RESISTANCE_GROWTH - 1)  -- 合作者，占领方压制较温和，但抵抗仍在
    end
    local AUTO_LIBERATE_THRESHOLD = 95

    for id, country in pairs(state.europe) do
        if country.sovereign ~= country.original then
            -- 被占领，抵抗增长
            country.resistance = math.min(100, (country.resistance or 0) + RESISTANCE_GROWTH)

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
            -- 不直接覆盖 growth_mod（可能有情报行动修正），而是通过修正器间接影响
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
