-- ============================================================================
-- 战斗系统：玩家武装 vs AI 势力
-- 包含：AI 主动进攻检查 + 双方战力计算 + 胜负结果
-- ============================================================================

local Balance = require("data.balance")
local Config = require("config")
local GameState = require("game_state")
local Equipment = require("systems.equipment")
local EquipmentData = require("data.equipment_data")

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
    local totalPower = 0

    -- 编队战力（新系统）— 排除已部署到远征的编队
    if m.squads and #m.squads > 0 then
        local homeSquadCount = 0
        for _, squad in ipairs(m.squads) do
            if not squad.deployed_to then  -- 跳过已部署到远征的编队
                totalPower = totalPower + Equipment.CalcSquadPower(squad)
                homeSquadCount = homeSquadCount + 1
            end
        end
        -- 未编队护卫（60% 效率，T1 装备）
        -- 当本土无任何编队驻守时，散兵缺乏指挥，战力大幅下降至20%
        local unassigned = Equipment.GetUnassignedGuards(state)
        local unassignedPower = EquipmentData.SQUAD.unassigned_power
        if homeSquadCount == 0 and unassigned > 0 then
            unassignedPower = unassignedPower * 0.2
        end
        totalPower = totalPower + unassigned * unassignedPower
    else
        -- 兼容：无编队时所有护卫视为未编队，使用 unassigned_power 系数
        local homeGuards = m.guards or 0
        totalPower = homeGuards * BMI.guard_base_power * (EquipmentData.SQUAD.unassigned_power or 0.6)
    end

    local moraleMul = math.max(0.3, m.morale * BMI.morale_multiplier)
    -- 军务主管加成
    local chiefBonus = GameState.GetPositionBonus(state, "military_chief")
    -- 科技护卫战力加成
    local techBonus = state.guard_power_tech_bonus or 0
    return totalPower * moraleMul * (1 + chiefBonus * 0.4) * (1 + techBonus)
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
    local diff = Config.GetDifficulty(state.difficulty)
    local log

    if result.winner == "player" then
        -- 胜：缴获 AI 现金，战意 +，军事胜利分 +
        local loot = math.floor(faction.cash * BC.loot_ratio * (diff.loot_mult or 1.0))
        faction.cash = faction.cash - loot
        faction.power = math.max(0, faction.power - 8)
        faction.attitude = math.max(-100, faction.attitude - 10)
        state.cash = state.cash + loot
        m.morale = math.min(100, m.morale + BC.win_morale)
        state.battle_wins_total = (state.battle_wins_total or 0) + 1
        state.battle_wins_unclaimed = (state.battle_wins_unclaimed or 0) + 1
        -- 家族学位：军事学院（combat_exp_pct）—— 战斗缴获加成
        local degreeCombatExp = GameState.GetActiveDegreeEffect and GameState.GetActiveDegreeEffect(state, "combat_exp_pct") or 0
        if degreeCombatExp > 0 then
            local bonusLoot = math.floor(loot * degreeCombatExp)
            state.cash = state.cash + bonusLoot
            loot = loot + bonusLoot
        end
        -- 编队战后处理：耐久衰减 + 老兵经验
        Equipment.OnBattleEnd(state, nil)
        local mapImpact = Combat.ApplyMapImpact(state, faction, result) or ""
        log = string.format("⚔ 击退 %s（战力 %d vs %d），缴获 %d 现金，战意+%d%s",
            faction.name, math.floor(result.p_power), math.floor(result.a_power),
            loot, BC.win_morale, mapImpact)
        -- 检查是否触发瘫痪
        local colCfg = Balance.AI.collapse
        if not faction.collapsed
            and faction.power <= colCfg.power_threshold
            and faction.cash <= colCfg.cash_threshold then
            faction.collapsed = true
            faction.collapsed_seasons = 0
            log = log .. string.format("\n💀 %s 势力崩溃，陷入瘫痪！", faction.name)
        end
    else
        -- 败：损失护卫 + 战意，丢失一部分现金被抢
        local lost = math.ceil(m.guards * BC.lose_guards_ratio * (diff.combat_loss_mult or 1.0))
        -- 支援装备：战地医疗包减少伤亡（最优一支有 medkit 的编队生效）
        local medkitReduction = 0
        for _, sq in ipairs(m.squads or {}) do
            if sq.support_equip_id == "medkit" and (sq.support_equip_condition or 0) > 0 then
                local sd = EquipmentData.SUPPORT_CATALOG and EquipmentData.SUPPORT_CATALOG.medkit
                if sd then
                    medkitReduction = math.max(medkitReduction, sd.effect_value)
                end
            end
        end
        if medkitReduction > 0 then
            lost = math.ceil(lost * (1 - medkitReduction))
        end
        -- C1: 保底至少保留3名护卫
        local maxLoss = math.max(0, m.guards - 3)
        lost = math.min(lost, maxLoss)
        -- 编队战后处理：先计算耐久衰减（包含即将解散的小队），再减员
        Equipment.OnBattleEnd(state, nil)
        m.guards = math.max(0, m.guards - lost)
        -- 编队减员同步
        Equipment.OnGuardsLost(state, lost)
        m.morale = math.max(0, m.morale + BC.lose_morale)
        local pillage = math.floor(state.cash * 0.06 * (diff.combat_pillage_mult or 1.0))
        -- V2: 记录本季战败次数（用于威慑VP判定）
        state.battle_losses_this_quarter = (state.battle_losses_this_quarter or 0) + 1
        state.cash = math.max(0, state.cash - pillage)
        faction.cash = faction.cash + pillage
        faction.power = math.min(100, faction.power + 5)
        faction.battle_wins_unclaimed = (faction.battle_wins_unclaimed or 0) + 1
        local mapImpact = Combat.ApplyMapImpact(state, faction, result) or ""
        log = string.format("💥 %s 突袭得手（战力 %d vs %d），折损 %d 护卫，被抢走 %d 现金%s",
            faction.name, math.floor(result.p_power), math.floor(result.a_power),
            lost, pillage, mapImpact)
        -- 战力差距过大时给出扩军提示
        if result.a_power > result.p_power * 1.5 then
            log = log .. "\n⚠ 战力悬殊！建议扩招护卫、组建编队提升战力"
        end
    end

    GameState.AddLog(state, log)
    return log
end

-- ============================================================================
-- 掠夺系统：轻量级力量检定（不走完整 Combat.Resolve）
-- ============================================================================

local BP = Balance.PLUNDER
local BR = Balance.REPUTATION

--- 掠夺力量检定（成功率 = clamp(玩家战力 / (难度 × 随机因子), floor, ceil)）
---@param state table
---@param actionKey string "raid_caravan"|"seize_vein"|"extort_foreign"
---@return boolean success
---@return number successRate
function Combat.PlunderCheck(state, actionKey)
    local cfg = BP[actionKey]
    if not cfg then return false, 0 end
    local playerPower = Combat.PlayerPower(state)
    local randomFactor = 0.8 + math.random() * 0.4  -- 0.8~1.2
    local successRate = Clamp(playerPower / (cfg.difficulty * randomFactor), BP.success_floor, BP.success_ceil)
    local roll = math.random()
    return roll < successRate, successRate
end

--- 劫掠商队
---@param state table
---@return boolean success
---@return string msg
function Combat.RaidCaravan(state)
    local cfg = BP.raid_caravan
    local success, rate = Combat.PlunderCheck(state, "raid_caravan")
    -- 声誉代价（无论成败）
    state.reputation = math.max(BR.min, (state.reputation or 0) + cfg.rep_cost)
    -- 设置冷却
    state.plunder_cooldowns = state.plunder_cooldowns or {}
    state.plunder_cooldowns.raid_caravan = cfg.cooldown

    -- 科技加成：冷却缩减
    local cdReduction = state.plunder_cooldown_reduction or 0
    if cdReduction > 0 then
        state.plunder_cooldowns.raid_caravan = math.max(1, state.plunder_cooldowns.raid_caravan - cdReduction)
    end

    if success then
        -- 称号计数：掠夺成功
        state.stats = state.stats or {}
        state.stats.plunder_successes = (state.stats.plunder_successes or 0) + 1
        local loot = math.random(cfg.loot_min, cfg.loot_max)
        -- 通胀调整
        local inflation = GameState.GetInflationFactor(state)
        loot = math.floor(loot * inflation)
        -- 科技加成：掠夺收益倍率
        local lootMult = state.plunder_loot_mult_bonus or 0
        if lootMult > 0 then
            loot = math.floor(loot * (1 + lootMult))
        end
        state.cash = state.cash + loot
        local msg = string.format("⚔ 劫掠商队成功！缴获 %d 克朗（成功率 %d%%，声誉 %d）",
            loot, math.floor(rate * 100), state.reputation)
        GameState.AddLog(state, msg)
        return true, msg
    else
        -- 失败：损失护卫
        local lost = math.min(cfg.fail_guard_loss, state.military.guards)
        state.military.guards = math.max(0, state.military.guards - lost)
        Equipment.OnGuardsLost(state, lost)
        local msg = string.format("💥 劫掠商队失败，折损 %d 名护卫（成功率 %d%%，声誉 %d）",
            lost, math.floor(rate * 100), state.reputation)
        GameState.AddLog(state, msg)
        return false, msg
    end
end

--- 夺取矿脉
---@param state table
---@return boolean success
---@return string msg
function Combat.SeizeVein(state)
    local cfg = BP.seize_vein
    local success, rate = Combat.PlunderCheck(state, "seize_vein")
    -- 声誉代价
    state.reputation = math.max(BR.min, (state.reputation or 0) + cfg.rep_cost)
    state.plunder_cooldowns = state.plunder_cooldowns or {}
    state.plunder_cooldowns.seize_vein = cfg.cooldown
    -- 科技加成：冷却缩减
    local cdReduction = state.plunder_cooldown_reduction or 0
    if cdReduction > 0 then
        state.plunder_cooldowns.seize_vein = math.max(1, state.plunder_cooldowns.seize_vein - cdReduction)
    end

    if success then
        -- 称号计数：掠夺成功
        state.stats = state.stats or {}
        state.stats.plunder_successes = (state.stats.plunder_successes or 0) + 1
        state.has_seized_veins = true
        state.seized_veins = state.seized_veins or {}
        table.insert(state.seized_veins, {
            remaining = cfg.vein_duration,
            gold_per_turn = cfg.vein_gold_per_turn,
        })
        local msg = string.format("⛏ 夺取矿脉成功！获得临时矿脉（%d季，每季产%d克朗，成功率%d%%，声誉%d）",
            cfg.vein_duration, cfg.vein_gold_per_turn, math.floor(rate * 100), state.reputation)
        GameState.AddLog(state, msg)
        return true, msg
    else
        -- 失败：声誉额外暴跌
        state.reputation = math.max(BR.min, state.reputation + cfg.fail_rep_extra)
        local msg = string.format("💥 夺取矿脉失败，声誉暴跌（成功率 %d%%，声誉 %d）",
            math.floor(rate * 100), state.reputation)
        GameState.AddLog(state, msg)
        return false, msg
    end
end

--- 勒索外资
---@param state table
---@return boolean success
---@return string msg
function Combat.ExtortForeign(state)
    local cfg = BP.extort_foreign
    local success, rate = Combat.PlunderCheck(state, "extort_foreign")
    -- 声誉代价
    state.reputation = math.max(BR.min, (state.reputation or 0) + cfg.rep_cost)
    state.plunder_cooldowns = state.plunder_cooldowns or {}
    state.plunder_cooldowns.extort_foreign = cfg.cooldown
    -- 科技加成：冷却缩减
    local cdReduction = state.plunder_cooldown_reduction or 0
    if cdReduction > 0 then
        state.plunder_cooldowns.extort_foreign = math.max(1, state.plunder_cooldowns.extort_foreign - cdReduction)
    end

    if success then
        -- 称号计数：掠夺成功
        state.stats = state.stats or {}
        state.stats.plunder_successes = (state.stats.plunder_successes or 0) + 1
        local loot = math.random(cfg.loot_min, cfg.loot_max)
        local inflation = GameState.GetInflationFactor(state)
        loot = math.floor(loot * inflation)
        -- 科技加成：掠夺收益倍率
        local lootMult = state.plunder_loot_mult_bonus or 0
        if lootMult > 0 then
            loot = math.floor(loot * (1 + lootMult))
        end
        state.cash = state.cash + loot
        local msg = string.format("💰 勒索外资成功！获得 %d 克朗（成功率 %d%%，声誉 %d）",
            loot, math.floor(rate * 100), state.reputation)
        GameState.AddLog(state, msg)
        return true, msg
    else
        -- 失败：外资反击加速
        for _, faction in ipairs(state.ai_factions) do
            if faction.type == "foreign_capital" and not faction.defeated then
                faction.attitude = math.max(-100, faction.attitude - cfg.fail_aggression_boost)
            end
        end
        local msg = string.format("💥 勒索外资失败，外资加速反击（成功率 %d%%，声誉 %d）",
            math.floor(rate * 100), state.reputation)
        GameState.AddLog(state, msg)
        return false, msg
    end
end

-- ============================================================================
-- AI 行动：每季度调用，AI 可能主动进攻玩家
-- ============================================================================
---@param state table
---@return string[] messages
function Combat.ResolveAIActions(state)
    local messages = {}
    -- 年代攻击加成：(year - base) / scale，1910年+0，1935年+0.25，1960年+0.5
    local yearBase  = BC.ai_attack_year_base  or 1910
    local yearScale = BC.ai_attack_year_scale or 100
    local yearBonus = math.max(0, ((state.year or yearBase) - yearBase) / yearScale)
    for _, faction in ipairs(state.ai_factions) do
        -- 已击败或瘫痪状态的势力不会主动进攻
        if faction.defeated then goto continue_ai end
        if faction.collapsed then goto continue_ai end
        -- 攻击冷却：触发攻击后若干季内不再进攻
        if faction.attack_cooldown and faction.attack_cooldown > 0 then goto continue_ai end
        if not faction.pact_remaining or faction.pact_remaining <= 0 then
            local aiConfig = Balance.AI[faction.type] or {}
            local chance = (BC.ai_attack_chance + yearBonus) * (1 + (aiConfig.aggression or 0))
            -- 声誉系统：声誉差时 AI 更积极进攻
            local repTier = GameState.GetReputationTier(state)
            local repAttackBonus = BR.ai_attack_bonus[repTier] or 0
            chance = chance + repAttackBonus
            -- 年代上限：防止概率无限叠加
            chance = math.min(BC.ai_attack_chance_cap or 0.75, chance)
            -- 声誉 < -30 时降低攻击阈值（更容易触发）
            local effectiveThreshold = BC.ai_attack_threshold
            if (state.reputation or 0) < BR.thresholds.notorious then
                effectiveThreshold = effectiveThreshold + 10  -- 阈值从 -20 升至 -10（更容易满足）
            end
            if faction.attitude <= effectiveThreshold
                and faction.power >= BC.ai_attack_power_req
                and math.random() < chance then
                local result = Combat.Resolve(state, faction, true)
                local log = Combat.ApplyResult(state, faction, result)
                table.insert(messages, log)
                -- 设置攻击冷却，防止同一势力连续进攻
                faction.attack_cooldown = BC.ai_attack_cooldown or 2
            end
        end
        ::continue_ai::
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
    if target.defeated then return false, "该势力已被击败" end
    if target.collapsed then return false, "该势力已瘫痪，无法发起进攻" end
    -- 称号计数：主动攻击
    state.stats = state.stats or {}
    state.stats.attacks_initiated = (state.stats.attacks_initiated or 0) + 1
    local result = Combat.Resolve(state, target, false)
    local log = Combat.ApplyResult(state, target, result)
    return true, log
end

-- ============================================================================
-- 远征战力检定：供 Expedition 模块调用，返回胜负和战力比
-- ============================================================================

--- 远征战力检定（玩家编队 vs 目标国防御力）
---@param state table
---@param squadId string|nil 编队ID（nil 则取全部战力）
---@param defenderPower number 防御方战力
---@return table result { winner, ratio, p_power, d_power }
function Combat.ResolveExpedition(state, squadId, defenderPower)
    local pPower
    if squadId then
        -- 使用指定编队的战力
        local m = state.military
        for _, squad in ipairs(m.squads or {}) do
            if squad.id == squadId then
                pPower = Equipment.CalcSquadPower(squad)
                break
            end
        end
        if not pPower then
            pPower = Combat.PlayerPower(state) * 0.5
        end
    else
        pPower = Combat.PlayerPower(state)
    end
    -- 随机因子 ±20%
    local pRoll = pPower * (0.8 + math.random() * 0.4)
    local dRoll = defenderPower * (0.8 + math.random() * 0.4)
    local winner = pRoll >= dRoll and "player" or "defender"
    local ratio = pRoll / math.max(1, dRoll)
    return {
        winner = winner,
        ratio = ratio,
        p_power = pPower,
        d_power = defenderPower,
    }
end

return Combat
