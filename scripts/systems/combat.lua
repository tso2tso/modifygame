-- ============================================================================
-- 战斗系统：玩家武装 vs AI 势力
-- 包含：AI 主动进攻检查 + 双方战力计算 + 胜负结果
-- ============================================================================

local Balance = require("data.balance")
local GameState = require("game_state")

local BC = Balance.COMBAT
local BMI = Balance.MILITARY

local Combat = {}

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

---@param state table
---@param faction table
---@return table|nil
function Combat.PickConflictRegion(state, faction)
    local bestRegion = nil
    local bestScore = -math.huge
    for _, r in ipairs(state.regions or {}) do
        local presence = r.ai_presence and r.ai_presence[faction.id] or 0
        if presence > 0 then
            local control = r.control or 0
            local resourceScore = 0
            if r.type == "mine" then resourceScore = resourceScore + 18 end
            if r.type == "industrial" then resourceScore = resourceScore + 14 end
            if r.type == "capital" then resourceScore = resourceScore + 10 end
            local score = presence * 1.4 + math.max(0, 60 - control) + resourceScore
                + (100 - (r.security or 3) * 15)
            if score > bestScore then
                bestScore = score
                bestRegion = r
            end
        end
    end
    return bestRegion
end

-- ============================================================================
-- 战力计算
-- ============================================================================

---@param state table
---@return number power
function Combat.PlayerPower(state)
    local m = state.military
    local base = m.guards * BMI.guard_base_power
    local moraleMul = math.max(0.3, m.morale * BMI.morale_multiplier)
    local equipMul = 1.0 + (m.equipment - 1) * BC.equipment_bonus
    -- 军务主管加成
    local chiefBonus = GameState.GetPositionBonus(state, "military_chief")
    -- 科技护卫战力加成
    local techBonus = state.guard_power_tech_bonus or 0
    return base * moraleMul * equipMul * (1 + chiefBonus) * (1 + techBonus)
end

---@param faction table
---@return number power
function Combat.FactionPower(faction)
    return faction.power * 1.0
end

function Combat.FactionPowerInRegion(faction, region)
    local presence = region and region.ai_presence and region.ai_presence[faction.id] or 0
    return Combat.FactionPower(faction) * (1 + presence / 200)
end

-- ============================================================================
-- 解析一次战斗（不改状态，只算结果）
-- ============================================================================
---@param state table
---@param faction table
---@param attackerIsAI boolean
---@return table result { winner = "player"|"ai", ratio, log }
function Combat.Resolve(state, faction, attackerIsAI)
    local region = Combat.PickConflictRegion(state, faction)
    local pPower = Combat.PlayerPower(state)
    local aPower = Combat.FactionPowerInRegion(faction, region)
    -- 随机因子 ±20%
    local pRoll = pPower * (0.8 + math.random() * 0.4)
    local aRoll = aPower * (0.8 + math.random() * 0.4)
    local winner = pRoll >= aRoll and "player" or "ai"
    local ratio = pRoll / math.max(1, aRoll)
    return {
        winner = winner,
        ratio = ratio,
        p_power = pPower,
        a_power = aPower,
        attacker_is_ai = attackerIsAI,
        region = region,
    }
end

function Combat.ApplyMapImpact(state, faction, result)
    local region = result.region
    if not region then return nil end
    region.ai_presence = region.ai_presence or {}
    local currentPresence = region.ai_presence[faction.id] or 0

    if result.winner == "player" then
        region.ai_presence[faction.id] = Clamp(currentPresence - 8, 0, 100)
        region.control = Clamp((region.control or 0) + 3, 0, 100)
        return string.format("，%s 控制度+3，%s存在度-8", region.name, faction.name)
    end

    region.ai_presence[faction.id] = Clamp(currentPresence + 7, 0, 100)
    region.control = Clamp((region.control or 0) - 5, 0, 100)
    region.security = Clamp((region.security or 3) - 1, 1, 5)
    return string.format("，%s 控制度-5，%s存在度+7，治安-1", region.name, faction.name)
end

-- ============================================================================
-- 应用结果（改状态）
-- ============================================================================
---@param state table
---@param faction table
---@param result table
---@return string logText
function Combat.ApplyResult(state, faction, result)
    local m = state.military
    local log

    if result.winner == "player" then
        -- 胜：缴获 AI 现金，士气 +，军事胜利分 +
        local loot = math.floor(faction.cash * BC.loot_ratio)
        faction.cash = faction.cash - loot
        faction.power = math.max(0, faction.power - 8)
        faction.attitude = math.max(-100, faction.attitude - 10)
        state.cash = state.cash + loot
        m.morale = math.min(100, m.morale + BC.win_morale)
        state.battle_wins_total = (state.battle_wins_total or 0) + 1
        state.battle_wins_unclaimed = (state.battle_wins_unclaimed or 0) + 1
        local mapImpact = Combat.ApplyMapImpact(state, faction, result) or ""
        log = string.format("⚔ 击退 %s，缴获 %d 现金，护卫士气+%d%s",
            faction.name, loot, BC.win_morale, mapImpact)
    else
        -- 败：损失护卫 + 士气，丢失一部分现金被抢
        local lost = math.ceil(m.guards * BC.lose_guards_ratio)
        m.guards = math.max(0, m.guards - lost)
        m.morale = math.max(0, m.morale + BC.lose_morale)
        local pillage = math.floor(state.cash * 0.10)
        state.cash = math.max(0, state.cash - pillage)
        faction.cash = faction.cash + pillage
        faction.power = math.min(100, faction.power + 5)
        local mapImpact = Combat.ApplyMapImpact(state, faction, result) or ""
        log = string.format("💥 %s 突袭得手，折损 %d 护卫，被抢走 %d 现金%s",
            faction.name, lost, pillage, mapImpact)
    end

    GameState.AddLog(state, log)
    return log
end

-- ============================================================================
-- AI 行动：每季度调用，AI 可能主动进攻玩家
-- ============================================================================
---@param state table
---@return string[] messages
function Combat.ResolveAIActions(state)
    local messages = {}
    for _, faction in ipairs(state.ai_factions) do
        if not faction.pact_remaining or faction.pact_remaining <= 0 then
            local aiConfig = Balance.AI[faction.type] or {}
            local chance = BC.ai_attack_chance * (1 + (aiConfig.aggression or 0))
            if faction.attitude <= BC.ai_attack_threshold
                and faction.power >= BC.ai_attack_power_req
                and math.random() < math.min(0.85, chance) then
                local result = Combat.Resolve(state, faction, true)
                local log = Combat.ApplyResult(state, faction, result)
                table.insert(messages, log)
            end
        end
    end
    return messages
end

-- ============================================================================
-- 玩家主动袭击（供情报/外交/交易模块调用）
-- ============================================================================
---@param state table
---@param factionId string
---@return boolean ok, string msg
function Combat.PlayerAttack(state, factionId)
    local target
    for _, f in ipairs(state.ai_factions) do
        if f.id == factionId then target = f; break end
    end
    if not target then return false, "目标不存在" end
    local result = Combat.Resolve(state, target, false)
    local log = Combat.ApplyResult(state, target, result)
    return true, log
end

return Combat
