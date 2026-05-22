-- ============================================================================
-- 远征系统：多回合并发远征 + 手动占领决策
-- 前置：称号"幕后执政"解锁后激活
-- ============================================================================

local Balance = require("data.balance")
local GameState = require("game_state")
local Equipment = require("systems.equipment")
local EuropeData = require("data.europe_data")
local Combat = require("systems.combat")
local TradeRoutesData = require("data.trade_routes_data")
local EventsData = require("data.events_data")
local Culture = require("systems.culture")

local BE = Balance.EXPEDITION

local Expedition = {}

-- ============================================================================
-- 门控检查
-- ============================================================================

--- 是否已解锁远征功能
---@param state table
---@return boolean
function Expedition.CanDoExpedition(state)
    return state.unlocked_features and state.unlocked_features["expedition"] == true
end

-- ============================================================================
-- HP 系统
-- ============================================================================

--- 初始化所有国家的HP（在"幕后执政"解锁时调用一次）
---@param state table
function Expedition.InitCountryHP(state)
    for id, country in pairs(state.europe) do
        if not country.max_hp then
            country.max_hp = country.stability * BE.hp_per_stability
            country.current_hp = country.max_hp
            country.hp_regen = country.stability * BE.hp_regen_ratio
            if country.tier == "major" then
                country.political_hp = country.stability * BE.political_hp_ratio
                country.max_political_hp = country.political_hp
            end
        end
    end
end

--- 查询HP是否已初始化
---@param state table
---@return boolean
function Expedition.IsHPInitialized(state)
    for _, country in pairs(state.europe) do
        return country.max_hp ~= nil
    end
    return false
end

--- 确保HP已初始化（幂等）
---@param state table
local function EnsureHPInit(state)
    for _, country in pairs(state.europe) do
        if not country.max_hp then
            Expedition.InitCountryHP(state)
            return
        end
        break
    end
end

--- 每季HP恢复（有活跃远征的国家跳过恢复）
---@param state table
function Expedition.TickCountryHP(state)
    EnsureHPInit(state)
    local activeExpeditions = state.expeditions.active or {}

    for id, country in pairs(state.europe) do
        -- 跳过已被玩家占领的国家
        local isPlayerOccupied = false
        for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
            if occ.country_id == id then isPlayerOccupied = true; break end
        end
        if isPlayerOccupied then goto continue_hp end

        -- 待占领队列：2回合窗口期内不恢复HP，超过窗口期后正常恢复
        for _, aw in ipairs(state.expeditions.awaiting_occupation or {}) do
            if aw.country_id == id then
                local turnsSinceDefeat = (state.turn_count or 0) - (aw.defeated_turn or 0)
                if turnsSinceDefeat < 2 then
                    -- 窗口期内：不恢复HP，等待玩家占领决策
                    goto continue_hp
                end
                -- 超过窗口期：允许HP恢复（下方正常恢复逻辑）
                break
            end
        end

        -- 有活跃远征的国家完全不恢复
        if activeExpeditions[id] then
            goto continue_hp
        end

        -- HP恢复
        if country.current_hp < country.max_hp then
            local regen = country.hp_regen
            -- 被大国保护的小国恢复 ×1.5
            if country.sovereign ~= country.original then
                regen = regen * BE.sovereign_regen_mult
            end
            country.current_hp = math.min(country.max_hp,
                math.floor(country.current_hp + regen))
        end

        -- 大国政治HP恢复
        if country.political_hp and country.max_political_hp
            and country.political_hp < country.max_political_hp then
            local polRegen = math.floor(country.hp_regen * 0.5)
            country.political_hp = math.min(country.max_political_hp,
                country.political_hp + polRegen)
        end

        ::continue_hp::
    end

    -- 清理超过窗口期且HP已恢复的国家：移出待占领队列
    local awList = state.expeditions.awaiting_occupation or {}
    for i = #awList, 1, -1 do
        local aw = awList[i]
        local turnsSinceDefeat = (state.turn_count or 0) - (aw.defeated_turn or 0)
        if turnsSinceDefeat >= 2 then
            local country = state.europe[aw.country_id]
            if country and (country.current_hp or 0) > 0 then
                GameState.AddLog(state, string.format(
                    "⚠ %s防御已恢复，占领窗口期已过！", aw.label or aw.country_id))
                table.remove(awList, i)
            end
        end
    end
end

-- ============================================================================
-- 征服难度系数
-- ============================================================================

--- 根据已占领数量获取难度系数
---@param state table
---@return number
function Expedition.GetConquestDifficultyMod(state)
    local occupiedCount = #(state.expeditions.occupied_countries or {})
    for _, tier in ipairs(BE.difficulty_tiers) do
        if occupiedCount <= tier.max_count then
            return tier.mod
        end
    end
    return 1.60
end

--- 前进基地加成（目标邻接已占领国家）
---@param state table
---@param targetCountryId string
---@return number bonus
function Expedition.GetForwardBaseBonus(state, targetCountryId)
    for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
        if EuropeData.AreAdjacent(state.europe, occ.country_id, targetCountryId) then
            return BE.forward_base_attack_bonus
        end
    end
    return 0
end

-- ============================================================================
-- C1 钳形攻势辅助函数
-- ============================================================================

--- 发动新远征后检测是否形成钳形攻势（目标互相邻接）
--- 若成立，互相写入 pincer_partner，同时从双方扣除额外 AP
---@param state table
---@param newExpId string  刚发动的远征目标国家 ID
local function check_pincer(state, newExpId)
    local newExp = (state.expeditions.active or {})[newExpId]
    if not newExp then return end

    local currentTurn = state.turn_count or 0

    for existId, existExp in pairs(state.expeditions.active or {}) do
        if existId == newExpId then goto continue_pincer end
        -- 已有钳形伙伴则跳过
        if existExp.pincer_partner then goto continue_pincer end
        -- 时机容忍：两条远征发动间隔 ≤ 1 季
        local turnDiff = math.abs((newExp.started_turn or 0) - (existExp.started_turn or 0))
        if turnDiff > 1 then goto continue_pincer end
        -- 相邻检测
        if EuropeData.AreAdjacent(state.europe, newExpId, existId) then
            -- 形成钳形！额外消耗 1 AP
            local apExtra = BE.pincer_ap_extra or 1
            local available = (state.ap.current or 0) + (state.ap.temp or 0)
            if available >= apExtra then
                GameState.SpendAP(state, apExtra)
            end
            -- 互相绑定
            newExp.pincer_partner = existId
            existExp.pincer_partner = newExpId
            -- 日志
            local a = state.europe[newExpId]
            local b = state.europe[existId]
            GameState.AddLog(state, string.format(
                "⚔⚔ 钳形攻势激活！%s ↔ %s（防御各-15%%，成功率各+5%%）",
                a and a.label or newExpId,
                b and b.label or existId))
            return
        end
        ::continue_pincer::
    end
end

--- 检测指定两个目标是否可以形成钳形攻势（用于 UI 提示，不消耗 AP）
---@param state table
---@param idA string
---@param idB string
---@return boolean
function Expedition.CanFormPincer(state, idA, idB)
    if not EuropeData.AreAdjacent(state.europe, idA, idB) then return false end
    local activeA = (state.expeditions.active or {})[idA]
    local activeB = (state.expeditions.active or {})[idB]
    -- 一个正在进行、一个是有效目标，或两个都是有效目标
    return true
end

--- 获取所有可能的钳形攻势组合列表（UI 战略态势提示用）
---@param state table
---@return table[]  每项 {a_id, a_label, b_id, b_label, is_active}
function Expedition.GetPincerCombinations(state)
    local result = {}
    local targets = Expedition.GetValidTargets(state)
    local activeIds = {}
    for id in pairs(state.expeditions.active or {}) do
        activeIds[id] = true
    end

    -- 合并活跃远征和有效目标
    local pool = {}
    for _, t in ipairs(targets) do
        pool[t.country_id] = t.label or t.country_id
    end
    for id, rec in pairs(state.expeditions.active or {}) do
        pool[id] = rec.label or id
    end

    local seen = {}
    for idA, labelA in pairs(pool) do
        for idB, labelB in pairs(pool) do
            if idA >= idB then goto next_combo end
            local key = idA .. "|" .. idB
            if seen[key] then goto next_combo end
            seen[key] = true
            if EuropeData.AreAdjacent(state.europe, idA, idB) then
                local activeA = activeIds[idA]
                local activeB = activeIds[idB]
                table.insert(result, {
                    a_id    = idA,
                    a_label = labelA,
                    b_id    = idB,
                    b_label = labelB,
                    is_active = activeA and activeB,  -- 两侧都已激活远征
                    a_active  = activeA,
                    b_active  = activeB,
                })
            end
            ::next_combo::
        end
    end
    return result
end

-- ============================================================================
-- 兵力计算
-- ============================================================================

--- 计算远征记录的部署总战力
---@param state table
---@param record table  活跃远征记录
---@return number totalPower
function Expedition.CalcDeployedPower(state, record)
    local totalPower = 0
    -- 编队战力
    for _, squadId in ipairs(record.deployed_squads or {}) do
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == squadId then
                totalPower = totalPower + Equipment.CalcSquadPower(squad)
                break
            end
        end
    end
    -- 预估模式：虚拟战力（用于 EstimateTurnsToComplete）
    if record._virtual_power and record._virtual_power > 0 then
        totalPower = totalPower + record._virtual_power
    end
    return totalPower
end

--- 计算远征部署的总人数
---@param state table
---@param record table
---@return number totalSoldiers
function Expedition.CalcDeployedSoldiers(state, record)
    local total = 0
    for _, squadId in ipairs(record.deployed_squads or {}) do
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == squadId then
                total = total + (squad.size or 0)
                break
            end
        end
    end
    return total
end

-- ============================================================================
-- 伤害计算（每回合）
-- ============================================================================

--- 计算远征对目标国家的每回合HP伤害
---@param state table
---@param record table  活跃远征记录
---@return number damage
function Expedition.CalcTurnDamage(state, record)
    EnsureHPInit(state)
    local country = state.europe[record.country_id]
    if not country then return 0 end

    local attackerPower = Expedition.CalcDeployedPower(state, record)
    local defenderBase = country.stability * BE.expedition_defender_mult

    -- 称号modifier：威慑削弱敌方防御
    local defDebuff = GameState.GetModifierValue(state, "intimidation_defense_debuff")
    defenderBase = defenderBase * (1 - defDebuff)

    -- C1 钳形攻势：目标防御 -15%（双侧均有有效钳形伙伴时生效）
    if record.pincer_partner and (state.expeditions.active or {})[record.pincer_partner] then
        defenderBase = defenderBase * (1 - (BE.pincer_defense_reduce or 0.15))
    end

    local powerRatio = attackerPower / math.max(1, defenderBase)
    local scaledDamage = BE.expedition_base_damage_per_turn
        * (powerRatio ^ BE.expedition_power_scaling)

    -- 大国伤害减免
    if country.tier == "major" then
        scaledDamage = scaledDamage * BE.major_damage_reduction
    end

    -- ── 加成叠加 ──
    local totalBonus = 0

    -- 远征战力加成 modifier
    totalBonus = totalBonus + GameState.GetModifierValue(state, "expedition_power_bonus")

    -- 贸易→远征耦合：军事物资储备buff
    local supplyBoost = GameState.GetModifierValue(state, "expedition_supply_boost")
    if supplyBoost > 0 then
        totalBonus = totalBonus + supplyBoost
    end

    -- A4 军务主管专精：strategy 属性每点 +2% 远征伤害（上限 20%）
    local specExpedDmg = GameState.GetModifierValue(state, "spec_expedition_dmg")
    if specExpedDmg > 0 then
        totalBonus = totalBonus + specExpedDmg
    end

    -- 外交→远征耦合：与敌对大国控制区作战伤害+10%
    if state.powers and state.europe then
        local targetCountry = state.europe[record.country_id]
        if targetCountry then
            local sovId = targetCountry.sovereign or record.country_id
            local sovPower = state.powers[sovId]
            if sovPower and sovPower.active then
                local att = sovPower.attitude_to_player or 0
                if att <= -30 then
                    totalBonus = totalBonus + 0.10
                end
            end
        end
    end

    -- 前进基地加成
    totalBonus = totalBonus + Expedition.GetForwardBaseBonus(state, record.country_id)

    -- 支援装备加成：侦察装具(expedition_damage) + 攻城器材(siege_damage)
    local EquipmentData = require("data.equipment_data")
    local SUPPORT_CATALOG = EquipmentData.SUPPORT_CATALOG
    for _, sid in ipairs(record.deployed_squads or {}) do
        local sq = nil
        for _, s in ipairs((state.military and state.military.squads) or {}) do
            if s.id == sid then sq = s; break end
        end
        if sq and sq.support_equip_id and (sq.support_equip_condition or 0) > 0 then
            local sd = SUPPORT_CATALOG[sq.support_equip_id]
            if sd then
                if sd.effect_type == "expedition_damage" then
                    totalBonus = totalBonus + sd.effect_value
                elseif sd.effect_type == "siege_damage" and country.tier == "major" then
                    totalBonus = totalBonus + sd.effect_value
                end
            end
        end
    end

    -- 加法叠加上限60%
    totalBonus = math.min(totalBonus, 0.60)
    scaledDamage = scaledDamage * (1 + totalBonus)

    -- 征服难度系数
    local diffMod = Expedition.GetConquestDifficultyMod(state)

    -- 外交→远征耦合：游击队降低远征难度
    local guerrillaReduction = GameState.GetModifierValue(state, "guerrilla_difficulty_reduction")
    if guerrillaReduction > 0 then
        diffMod = diffMod * (1 - guerrillaReduction)
    end

    scaledDamage = scaledDamage / diffMod

    -- A1 事件效果：补给线受袭（-25% 伤害）
    if record.supply_penalty and record.supply_penalty > 0 then
        scaledDamage = scaledDamage * 0.75
    end

    -- A1 事件效果：拒绝谈判激怒奖励（rage_bonus，一次性）
    if record.rage_bonus and record.rage_bonus > 0 then
        scaledDamage = scaledDamage * (1 + record.rage_bonus)
    end

    -- A1 事件效果：叛逃情报成功率加成（defector_bonus 已用于 CalcSuccessRate，不影响伤害）

    -- C1 钳形攻势失败惩罚：伙伴失败后本季伤害 ×0.80（持续 1 季，用后清除）
    if record.pincer_failed_penalty then
        scaledDamage = scaledDamage * record.pincer_failed_penalty
        record.pincer_failed_penalty = nil  -- 消耗一次性惩罚
    end

    return math.max(1, math.floor(scaledDamage))
end

--- 预估剩余回合数（UI展示用）
---@param state table
---@param countryId string
---@param deployedPower number|nil  如果为nil则从活跃远征中获取
---@return number estimatedTurns
function Expedition.EstimateTurns(state, countryId, deployedPower)
    EnsureHPInit(state)
    local country = state.europe[countryId]
    if not country then return 999 end

    local record = (state.expeditions.active or {})[countryId]
    local dmg
    if record then
        dmg = Expedition.CalcTurnDamage(state, record)
    else
        -- 预估模式：用传入的deployedPower创建虚拟记录
        local virtualRecord = {
            country_id = countryId,
            deployed_squads = {},
            _virtual_power = deployedPower or 0,
        }
        dmg = Expedition.CalcTurnDamage(state, virtualRecord)
    end

    if dmg <= 0 then return 999 end
    local remainingHP = country.current_hp or country.max_hp or 1
    -- 大国需要两层HP
    if country.tier == "major" and country.political_hp then
        remainingHP = remainingHP + country.political_hp
    end
    return math.ceil(remainingHP / dmg)
end

-- ============================================================================
-- 成功率 / 损失计算
-- ============================================================================

--- 计算远征完成时的成功率
---@param state table
---@param record table  活跃远征记录
---@return number successRate 0~1
function Expedition.CalcSuccessRate(state, record)
    local attackerPower = Expedition.CalcDeployedPower(state, record)
    local country = state.europe[record.country_id]
    if not country then return BE.expedition_success_base end

    local defenderBase = country.stability * BE.expedition_defender_mult
    local powerAdvantage = (attackerPower - defenderBase) / math.max(1, defenderBase)

    local rate = BE.expedition_success_base
        + powerAdvantage * BE.expedition_success_power_weight

    -- A1 事件效果：叛逃情报（+8% 成功率）
    if record.defector_bonus and record.defector_bonus > 0 then
        rate = rate + record.defector_bonus
    end

    -- C1 钳形攻势：伙伴仍活跃时成功率 +5%
    if record.pincer_partner and (state.expeditions.active or {})[record.pincer_partner] then
        rate = rate + (BE.pincer_success_bonus or 0.05)
    end

    return math.max(BE.expedition_success_floor,
        math.min(BE.expedition_success_cap, rate))
end

--- 计算远征完成时的兵力损失数量
---@param state table
---@param record table
---@param failed boolean  是否为失败结算
---@return number lostSoldiers
function Expedition.CalcLosses(state, record, failed)
    local totalSoldiers = Expedition.CalcDeployedSoldiers(state, record)
    local attackerPower = Expedition.CalcDeployedPower(state, record)
    local country = state.europe[record.country_id]

    local defenderBase = 1
    if country then
        defenderBase = country.stability * BE.expedition_defender_mult
    end
    local powerAdvantage = (attackerPower - defenderBase) / math.max(1, defenderBase)

    local lossRatio = BE.expedition_loss_base_ratio
        - powerAdvantage * BE.expedition_loss_power_reduction
    lossRatio = math.max(BE.expedition_loss_min_ratio, lossRatio)

    if failed then
        lossRatio = lossRatio * BE.expedition_fail_loss_mult
    end

    return math.max(1, math.floor(totalSoldiers * lossRatio))
end

-- ============================================================================
-- 可攻击目标
-- ============================================================================

--- 获取可攻击的目标国家列表
--- 波斯尼亚邻接 + 已占领国家邻接（排除已占领和已有活跃远征的）
---@param state table
---@return table[] targets
function Expedition.GetValidTargets(state)
    EnsureHPInit(state)
    local targets = {}
    local targetSet = {}

    -- 波斯尼亚直接邻接的国家
    local bosniaAdj = { "austria_hungary", "serbia", "montenegro" }
    for _, adjId in ipairs(bosniaAdj) do
        targetSet[adjId] = true
    end

    -- 已占领国家的邻接
    for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
        local occCountry = state.europe[occ.country_id]
        if occCountry and occCountry.adjacency then
            for _, adjId in ipairs(occCountry.adjacency) do
                targetSet[adjId] = true
            end
        end
    end

    -- 排除已占领的国家
    for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
        targetSet[occ.country_id] = nil
    end

    -- 排除已有活跃远征的国家
    for countryId, _ in pairs(state.expeditions.active or {}) do
        targetSet[countryId] = nil
    end

    -- 排除待占领队列中的国家
    for _, aw in ipairs(state.expeditions.awaiting_occupation or {}) do
        targetSet[aw.country_id] = nil
    end

    -- 构建目标列表
    for countryId, _ in pairs(targetSet) do
        local country = state.europe[countryId]
        if country then
            table.insert(targets, {
                country_id = countryId,
                label = country.label,
                tier = country.tier,
                current_hp = country.current_hp or country.max_hp,
                max_hp = country.max_hp,
                political_hp = country.political_hp,
                max_political_hp = country.max_political_hp,
            })
        end
    end

    return targets
end

-- ============================================================================
-- 远征行动：发起 / 增援 / 撤退
-- ============================================================================

--- 发起远征
---@param state table
---@param countryId string
---@param squadIds string[]  选择的编队ID列表
---@return boolean ok
---@return string msg
function Expedition.LaunchExpedition(state, countryId, squadIds)
    if not Expedition.CanDoExpedition(state) then
        return false, "需要解锁[幕后执政]称号"
    end

    local country = state.europe[countryId]
    if not country then return false, "目标国家不存在" end

    -- 检查不在活跃远征中
    if (state.expeditions.active or {})[countryId] then
        return false, "已有对该国的活跃远征"
    end

    -- 检查可达性
    local validTargets = Expedition.GetValidTargets(state)
    local isValid = false
    for _, t in ipairs(validTargets) do
        if t.country_id == countryId then isValid = true; break end
    end
    if not isValid then return false, "目标国家不可达" end

    -- 计算总兵力
    squadIds = squadIds or {}
    local totalSoldiers = 0

    -- 验证编队可用性（不在其他远征中）
    for _, sqId in ipairs(squadIds) do
        local found = false
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == sqId then
                found = true
                if squad.deployed_to then
                    return false, string.format("编队 %s 已部署到 %s",
                        squad.name or sqId, squad.deployed_to)
                end
                totalSoldiers = totalSoldiers + (squad.size or 0)
                break
            end
        end
        if not found then
            return false, string.format("编队 %s 不存在", sqId)
        end
    end

    if totalSoldiers <= 0 then
        return false, "至少需要部署1名士兵"
    end

    -- 计算费用
    local inflation = GameState.GetInflationFactor(state)
    local cashCost = math.floor(totalSoldiers * BE.expedition_cost_per_soldier * inflation)
    local apCost = BE.expedition_ap_cost

    local availableAP = state.ap.current + (state.ap.temp or 0)
    if availableAP < apCost then
        return false, string.format("行动点不足（需要 %d AP）", apCost)
    end
    if state.cash < cashCost then
        return false, string.format("现金不足（需要 %d 克朗）", cashCost)
    end

    EnsureHPInit(state)

    -- 消耗资源
    GameState.SpendAP(state, apCost)
    state.cash = state.cash - cashCost

    -- 标记编队部署
    for _, sqId in ipairs(squadIds) do
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == sqId then
                squad.deployed_to = countryId
                break
            end
        end
    end

    -- 创建远征记录（garrison_init：发起远征时目标国 HP，用于事件触发比例计算）
    EnsureHPInit(state)
    state.expeditions.active = state.expeditions.active or {}
    state.expeditions.active[countryId] = {
        country_id = countryId,
        label = country.label,
        started_turn = state.turn_count or 0,
        deployed_squads = squadIds,
        total_damage_dealt = 0,
        turns_elapsed = 0,
        garrison_init = country.current_hp or country.max_hp,
    }

    -- 文化路线与武力扩张互斥：开战会削弱目标地区已有 CP。
    if state.culture then
        Culture.ApplyWarPenalty(state, countryId)
    end

    -- 侵略度
    state.expeditions.aggression_counter = (state.expeditions.aggression_counter or 0)
        + BE.aggression_per_expedition

    -- 统计
    state.expeditions.history = state.expeditions.history or {}
    state.expeditions.history.expeditions_launched =
        (state.expeditions.history.expeditions_launched or 0) + 1
    state.stats = state.stats or {}
    state.stats.attacks_initiated = (state.stats.attacks_initiated or 0) + 1

    -- C1 钳形攻势检测
    check_pincer(state, countryId)

    local msg = string.format(
        "⚔ 对%s发起远征！部署 %d 名士兵，花费 %d 克朗",
        country.label, totalSoldiers, cashCost)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 增援远征
---@param state table
---@param countryId string
---@param squadIds string[]  增援的编队ID列表
---@return boolean ok
---@return string msg
function Expedition.Reinforce(state, countryId, squadIds)
    local record = (state.expeditions.active or {})[countryId]
    if not record then return false, "没有对该国的活跃远征" end

    squadIds = squadIds or {}
    local addedSoldiers = 0

    -- 验证编队可用性
    for _, sqId in ipairs(squadIds) do
        local found = false
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == sqId then
                found = true
                if squad.deployed_to then
                    return false, string.format("编队 %s 已部署到 %s",
                        squad.name or sqId, squad.deployed_to)
                end
                addedSoldiers = addedSoldiers + (squad.size or 0)
                break
            end
        end
        if not found then
            return false, string.format("编队 %s 不存在", sqId)
        end
    end

    if addedSoldiers <= 0 then
        return false, "至少增援1名士兵"
    end

    -- 费用
    local inflation = GameState.GetInflationFactor(state)
    local cashCost = math.floor(addedSoldiers * BE.expedition_cost_per_soldier * inflation)
    local apCost = BE.expedition_reinforce_ap

    local availableAP = state.ap.current + (state.ap.temp or 0)
    if availableAP < apCost then
        return false, string.format("行动点不足（需要 %d AP）", apCost)
    end
    if state.cash < cashCost then
        return false, string.format("现金不足（需要 %d 克朗）", cashCost)
    end

    -- 消耗
    GameState.SpendAP(state, apCost)
    state.cash = state.cash - cashCost

    -- 标记编队
    for _, sqId in ipairs(squadIds) do
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == sqId then
                squad.deployed_to = countryId
                break
            end
        end
        table.insert(record.deployed_squads, sqId)
    end

    local country = state.europe[countryId]
    local label = country and country.label or countryId
    local msg = string.format("🔄 增援%s远征！增派 %d 名士兵，花费 %d 克朗",
        label, addedSoldiers, cashCost)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 撤退（部分或全部）
---@param state table
---@param countryId string
---@param squadIds string[]|nil  撤回的编队ID列表（nil=不撤编队）
---@return boolean ok
---@return string msg
function Expedition.Withdraw(state, countryId, squadIds)
    local record = (state.expeditions.active or {})[countryId]
    if not record then return false, "没有对该国的活跃远征" end

    local apCost = BE.expedition_withdraw_ap
    local availableAP = state.ap.current + (state.ap.temp or 0)
    if availableAP < apCost then
        return false, string.format("行动点不足（需要 %d AP）", apCost)
    end

    squadIds = squadIds or {}
    local withdrawnSoldiers = 0

    -- 先验证所有编队都在远征中，避免部分修改后返回错误
    for _, sqId in ipairs(squadIds) do
        local found = false
        for _, deployedId in ipairs(record.deployed_squads) do
            if deployedId == sqId then found = true; break end
        end
        if not found then
            return false, string.format("编队 %s 未部署在此远征中", sqId)
        end
    end

    -- 消耗AP（验证全部通过后再修改状态）
    GameState.SpendAP(state, apCost)

    -- 撤回编队
    for _, sqId in ipairs(squadIds) do
        for i, deployedId in ipairs(record.deployed_squads) do
            if deployedId == sqId then
                table.remove(record.deployed_squads, i)
                break
            end
        end
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == sqId then
                squad.deployed_to = nil
                withdrawnSoldiers = withdrawnSoldiers + (squad.size or 0)
                break
            end
        end
    end

    -- 检查是否全部撤出 → 取消远征
    local remainingSoldiers = Expedition.CalcDeployedSoldiers(state, record)
    if remainingSoldiers <= 0 then
        state.expeditions.active[countryId] = nil
        local country = state.europe[countryId]
        local label = country and country.label or countryId
        local msg = string.format("🏳 从%s全部撤退，远征已取消", label)
        GameState.AddLog(state, msg)
        return true, msg
    end

    local country = state.europe[countryId]
    local label = country and country.label or countryId
    local msg = string.format("🔄 从%s撤回 %d 名士兵，剩余 %d 名",
        label, withdrawnSoldiers, remainingSoldiers)
    GameState.AddLog(state, msg)
    return true, msg
end

-- ============================================================================
-- A1：远征过程事件候选池构建
-- ============================================================================

--- 构建当前可触发的远征事件候选列表
---@param state table
---@param countryId string
---@param record table  活跃远征记录
---@return table[]  candidates
local function BuildExpeditionEventCandidates(state, countryId, record)
    local country = state.europe[countryId]
    local allEvents = EventsData.GetExpeditionEvents()
    local candidates = {}

    -- 计算活跃远征数（用于 rear_unrest 判断）
    local activeCount = 0
    for _ in pairs(state.expeditions.active or {}) do activeCount = activeCount + 1 end

    -- 目标 HP 比例（用于 negotiate 判断）
    -- 分母用 garrison_init（发起远征时的 HP），比用 max_hp 更准确反映本次战役进度
    local hpRatio = 1.0
    local garrisonBase = record.garrison_init
        or (country and (country.current_hp or country.max_hp))
        or 1
    if country and garrisonBase > 0 then
        hpRatio = (country.current_hp or garrisonBase) / garrisonBase
    end

    -- 已有此 ID 事件在队列中，跳过（防重复）
    local queuedIds = {}
    for _, ev in ipairs(state.event_queue or {}) do
        queuedIds[ev.id] = true
    end

    for _, ev in ipairs(allEvents) do
        if queuedIds[ev.id] then goto continue_cand end

        -- 各事件的触发条件
        if ev.id == "exp_evt_supply_raid" then
            if (record.turns_elapsed or 0) < (BE.event_supply_min_turns or 4) then
                goto continue_cand
            end

        elseif ev.id == "exp_evt_negotiate" then
            local lo = BE.event_negotiate_hp_lo or 0.30
            local hi = BE.event_negotiate_hp_hi or 0.50
            if hpRatio < lo or hpRatio > hi then goto continue_cand end

        elseif ev.id == "exp_evt_gp_warning" then
            if (state.expeditions.aggression_counter or 0) < 4 then
                goto continue_cand
            end

        elseif ev.id == "exp_evt_ally_passage" then
            -- 要求玩家至少有一个占领国邻接目标
            local hasAdj = false
            for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
                if EuropeData.AreAdjacent(state.europe, occ.country_id, countryId) then
                    hasAdj = true; break
                end
            end
            if not hasAdj then goto continue_cand end

        elseif ev.id == "exp_evt_defector" then
            if (record.turns_elapsed or 0) < (BE.event_defector_min_turns or 6) then
                goto continue_cand
            end

        elseif ev.id == "exp_evt_rear_unrest" then
            if activeCount < 2 then goto continue_cand end
        end

        table.insert(candidates, ev)
        ::continue_cand::
    end

    return candidates
end

-- ============================================================================
-- 回合推进：活跃远征造成伤害
-- ============================================================================

--- 推进所有活跃远征（每季调用一次）
---@param state table
---@return table[] reports  { country_id, label, damage, remaining_hp, completed }
function Expedition.TickActiveExpeditions(state)
    EnsureHPInit(state)
    local reports = {}
    local completedIds = {}

    for countryId, record in pairs(state.expeditions.active or {}) do
        local country = state.europe[countryId]
        if not country then goto continue_tick end

        -- 计算本回合伤害
        local damage = Expedition.CalcTurnDamage(state, record)
        record.turns_elapsed = (record.turns_elapsed or 0) + 1
        record.total_damage_dealt = (record.total_damage_dealt or 0) + damage

        -- 军事HP伤害
        country.current_hp = math.max(0, (country.current_hp or country.max_hp) - damage)

        -- 大国政治HP也受伤（50%伤害）
        if country.political_hp and country.tier == "major" then
            local polDamage = math.floor(damage * 0.5)
            country.political_hp = math.max(0, country.political_hp - polDamage)
        end

        -- A1 事件效果：游击队额外HP恢复（每季 +8 HP 给目标）
        if record.guerrilla_regen and record.guerrilla_regen > 0 then
            country.current_hp = math.min(country.max_hp,
                (country.current_hp or 0) + 8)
        end

        -- A1 事件效果：友军借道阻断目标HP恢复（本季跳过自然恢复已在 TickCountryHP 中处理）

        -- A1 事件计时器递减
        if record.supply_penalty and record.supply_penalty > 0 then
            record.supply_penalty = record.supply_penalty - 1
        end
        if record.guerrilla_regen and record.guerrilla_regen > 0 then
            record.guerrilla_regen = record.guerrilla_regen - 1
        end
        if record.rage_bonus then
            record.rage_bonus = nil  -- 一次性效果，用后清除
        end
        if record.ally_passage_regen_block and record.ally_passage_regen_block > 0 then
            record.ally_passage_regen_block = record.ally_passage_regen_block - 1
        end

        -- 编队战后耐久衰减（每回合）— 传入完整编队ID表
        Equipment.OnBattleEnd(state, record.deployed_squads)

        -- 检查HP归零
        local hpZero = country.current_hp <= 0
        local polZero = true
        if country.tier == "major" and country.political_hp then
            polZero = country.political_hp <= 0
        end

        local completed = hpZero and polZero
        table.insert(reports, {
            country_id = countryId,
            label = country.label,
            damage = damage,
            remaining_hp = country.current_hp,
            remaining_pol_hp = country.political_hp,
            turns_elapsed = record.turns_elapsed,
            completed = completed,
        })

        if completed then
            table.insert(completedIds, countryId)
        end

        ::continue_tick::
    end

    -- 处理HP归零的远征 → 进入完成判定
    for _, cid in ipairs(completedIds) do
        Expedition.CompleteExpedition(state, cid)
    end

    -- ── A1：远征过程事件触发 ──
    -- 在 completedIds 处理完之后，对仍活跃的远征做一次事件抽检
    local Events = require("systems.events")
    for countryId, record in pairs(state.expeditions.active or {}) do
        -- 冷却递减
        record.event_cooldown = math.max(0, (record.event_cooldown or 0) - 1)

        -- 已有挂起事件 或 冷却中 → 跳过
        if record.pending_event then goto skip_event end
        if (record.event_cooldown or 0) > 0 then goto skip_event end

        -- 概率抽取
        if math.random() < (BE.event_trigger_chance or 0.25) then
            local candidates = BuildExpeditionEventCandidates(state, countryId, record)
            if #candidates > 0 then
                -- 随机选一条，克隆并注入 expedition_id
                local picked = candidates[math.random(#candidates)]
                local evt = {}
                for k, v in pairs(picked) do evt[k] = v end
                evt.expedition_id = countryId  -- 供选项回调读取

                record.pending_event = evt.id
                record.event_cooldown = BE.event_cooldown or 3
                Events.Enqueue(state, { evt })

                local country = state.europe[countryId]
                GameState.AddLog(state, string.format(
                    "[远征事件] %s → %s", country and country.label or countryId, evt.title))
            end
        end

        ::skip_event::
    end

    return reports
end

-- ============================================================================
-- 远征完成判定
-- ============================================================================

--- 远征完成：掷骰成功/失败 → 损失 + 掠夺/恢复
---@param state table
---@param countryId string
function Expedition.CompleteExpedition(state, countryId)
    local record = (state.expeditions.active or {})[countryId]
    if not record then return end

    local country = state.europe[countryId]
    if not country then return end

    local successRate = Expedition.CalcSuccessRate(state, record)
    local roll = math.random()
    local won = roll < successRate

    if won then
        -- 成功：损失 + 掠夺 + 进入待占领
        local losses = Expedition.CalcLosses(state, record, false)
        Expedition._ApplyLosses(state, record, losses)

        -- 掠夺收入
        local inflation = GameState.GetInflationFactor(state)
        local loot = math.floor(country.stability * BE.expedition_loot_per_stability * inflation)
        -- 科技/称号加成
        local lootMult = state.plunder_loot_mult_bonus or 0
        local titleBonus = GameState.GetModifierValue(state, "plunder_income_bonus")
        lootMult = lootMult + titleBonus
        if lootMult > 0 then
            loot = math.floor(loot * (1 + lootMult))
        end
        state.cash = state.cash + loot

        -- 进入待占领队列
        state.expeditions.awaiting_occupation = state.expeditions.awaiting_occupation or {}
        table.insert(state.expeditions.awaiting_occupation, {
            country_id = countryId,
            label = country.label,
            defeated_turn = state.turn_count or 0,
        })

        -- 统计
        state.expeditions.history.expeditions_won =
            (state.expeditions.history.expeditions_won or 0) + 1
        state.expeditions.history.total_loot =
            (state.expeditions.history.total_loot or 0) + loot

        local msg = string.format(
            "⚔ 远征%s胜利！掠夺 %d 克朗，损失 %d 名士兵（%d回合，成功率%d%%）\n🏳️ 等待占领决策！",
            country.label, loot, losses,
            record.turns_elapsed, math.floor(successRate * 100))
        GameState.AddLog(state, msg)

        -- C1 钳形攻势：己方胜利，解除伙伴钳形绑定（伙伴继续获益 forward_base_bonus）
        if record.pincer_partner then
            local partner = (state.expeditions.active or {})[record.pincer_partner]
            if partner then partner.pincer_partner = nil end
            record.pincer_partner = nil
        end
    else
        -- 失败：更大损失 + 目标HP恢复
        local losses = Expedition.CalcLosses(state, record, true)
        Expedition._ApplyLosses(state, record, losses)

        -- 目标HP恢复到30%
        country.current_hp = math.floor(country.max_hp * BE.expedition_fail_hp_restore)
        if country.political_hp and country.max_political_hp then
            country.political_hp = math.floor(country.max_political_hp * BE.expedition_fail_hp_restore)
        end

        -- 统计
        state.expeditions.history.expeditions_lost =
            (state.expeditions.history.expeditions_lost or 0) + 1

        local msg = string.format(
            "💥 远征%s失败！损失 %d 名士兵（%d回合，成功率%d%%）\n敌方防御恢复至%d%%",
            country.label, losses,
            record.turns_elapsed, math.floor(successRate * 100),
            math.floor(BE.expedition_fail_hp_restore * 100))
        GameState.AddLog(state, msg)

        -- C1 钳形攻势：己方失败，通知伙伴远征受挫（本季伤害 -20%）
        if record.pincer_partner then
            local partner = (state.expeditions.active or {})[record.pincer_partner]
            if partner then
                partner.pincer_failed_penalty = 1.0 - (BE.pincer_fail_penalty or 0.20)
                partner.pincer_partner = nil  -- 解除绑定
                local partnerCountry = state.europe[record.pincer_partner]
                GameState.AddLog(state, string.format(
                    "😟 钳形伙伴远征%s失败，%s士气受挫（本季伤害-20%%）",
                    country.label,
                    partnerCountry and partnerCountry.label or record.pincer_partner))
            end
            record.pincer_partner = nil
        end
    end

    -- 释放部队回本土
    Expedition._ReleaseForces(state, record)

    -- 清除远征事件挂起标记
    record.pending_event = nil

    -- 移除活跃远征记录
    state.expeditions.active[countryId] = nil
end

--- 应用兵力损失（从编队和散兵中扣除）
---@param state table
---@param record table
---@param lostSoldiers number
function Expedition._ApplyLosses(state, record, lostSoldiers)
    local remaining = lostSoldiers

    -- 从编队中扣（按顺序，损失分摊）
    if remaining > 0 then
        for _, sqId in ipairs(record.deployed_squads or {}) do
            if remaining <= 0 then break end
            for _, squad in ipairs(state.military.squads or {}) do
                if squad.id == sqId and (squad.size or 0) > 0 then
                    local squadLoss = math.min(remaining, squad.size)
                    squad.size = squad.size - squadLoss
                    state.military.guards = math.max(0, state.military.guards - squadLoss)
                    remaining = remaining - squadLoss
                    break
                end
            end
        end
    end

    -- 士气打击
    state.military.morale = math.max(0,
        (state.military.morale or 70) - math.floor(lostSoldiers * 0.5))
end

--- 释放远征部队回本土（清除deployed标记）
---@param state table
---@param record table
function Expedition._ReleaseForces(state, record)
    -- 释放编队
    for _, sqId in ipairs(record.deployed_squads or {}) do
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == sqId then
                squad.deployed_to = nil
                break
            end
        end
    end
end

-- ============================================================================
-- 占领决策
-- ============================================================================

--- 自行占领
---@param state table
---@param countryId string
---@return boolean ok
---@return string msg
function Expedition.OccupySelf(state, countryId)
    if not Expedition.CanDoExpedition(state) then
        return false, "需要解锁[幕后执政]称号"
    end

    -- 检查是否在待占领队列
    local found = false
    local idx = 0
    for i, aw in ipairs(state.expeditions.awaiting_occupation or {}) do
        if aw.country_id == countryId then
            found = true
            idx = i
            break
        end
    end
    if not found then return false, "该国家不在待占领队列中" end

    EnsureHPInit(state)
    local country = state.europe[countryId]
    if not country then return false, "目标国家不存在" end

    -- 窗口期内HP不恢复可直接占领；超过2回合窗口期后HP会恢复，需检查
    if country.current_hp and country.current_hp > 0 then
        return false, "占领窗口期已过，目标HP已恢复"
    end
    if country.tier == "major" and (country.political_hp or 0) > 0 then
        return false, "占领窗口期已过，目标政治HP已恢复"
    end

    -- 检查AP和现金
    local availableAP = state.ap.current + (state.ap.temp or 0)
    if availableAP < BE.occupy_ap_cost then
        return false, string.format("行动点不足（需要 %d AP）", BE.occupy_ap_cost)
    end
    if state.cash < BE.occupy_cash_cost then
        return false, string.format("现金不足（需要 %d 克朗）", BE.occupy_cash_cost)
    end

    -- 消耗
    GameState.SpendAP(state, BE.occupy_ap_cost)
    state.cash = state.cash - BE.occupy_cash_cost

    -- 确定收入和维护
    local isMajor = country.tier == "major"
    local income = isMajor and BE.occupy_income_major or BE.occupy_income_minor
    local maintenance = isMajor and BE.occupy_maintenance_major or BE.occupy_maintenance_minor

    -- 称号modifier：占领维护费折扣
    local maintDiscount = GameState.GetModifierValue(state, "occupation_maintenance_discount")
    if maintDiscount > 0 then
        maintenance = math.floor(maintenance * (1 - maintDiscount))
    end

    -- 添加到已占领列表
    table.insert(state.expeditions.occupied_countries, {
        country_id = countryId,
        label = country.label,
        income_per_turn = income,
        maintenance = maintenance,
        since_turn = state.turn_count or 0,
        -- A2 稳定度与发展策略
        stability_control    = BE.stability_init or 40,
        development_policy   = "tax",
        policy_lock_turn     = 0,
        policy_delay_remaining = 0,
    })

    -- 清除HP
    country.current_hp = 0

    -- 更新主权为玩家（bosnia），使地图色块同步变化
    country.sovereign = "bosnia"

    -- 从待占领队列移除
    table.remove(state.expeditions.awaiting_occupation, idx)

    -- 侵略度 +2
    state.expeditions.aggression_counter = (state.expeditions.aggression_counter or 0)
        + BE.aggression_per_occupy

    -- C4-2 行为性敌意：占领领土 → 所有 AI 势力态度 -8（一次性）
    local occupyPenalty = Balance.AI.behavior_penalty and Balance.AI.behavior_penalty.occupy_territory or -8
    for _, f in ipairs(state.ai_factions or {}) do
        if not f.defeated and not f.collapsed then
            f.attitude = math.max(-100, (f.attitude or 0) + occupyPenalty)
        end
    end

    -- 统计
    state.expeditions.history.countries_conquered =
        (state.expeditions.history.countries_conquered or 0) + 1

    -- 贸易路线自动解锁
    local routeDef = TradeRoutesData.GetRouteForBuyer(countryId)
    if routeDef and not routeDef.unlocked then
        state.trade = state.trade or {}
        state.trade.route_unlocks = state.trade.route_unlocks or {}
        if not state.trade.route_unlocks[routeDef.id] then
            state.trade.route_unlocks[routeDef.id] = true
            GameState.AddLog(state, string.format(
                "[远征→贸易] 占领%s后，贸易路线「%s」已自动开通！",
                country.label, routeDef.name))
        end
    end

    local msg = string.format(
        "🏴 成功占领%s！每季收入 %d，维护费 %d（净收益 %d）",
        country.label, income, maintenance, income - maintenance)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 交给势力占领
---@param state table
---@param countryId string
---@param factionId string|nil  指定势力ID（nil=第一个友好势力）
---@return boolean ok
---@return string msg
function Expedition.OccupyGiveToFaction(state, countryId, factionId)
    if not Expedition.CanDoExpedition(state) then
        return false, "需要解锁[幕后执政]称号"
    end

    -- 检查是否在待占领队列
    local found = false
    local idx = 0
    for i, aw in ipairs(state.expeditions.awaiting_occupation or {}) do
        if aw.country_id == countryId then
            found = true
            idx = i
            break
        end
    end
    if not found then return false, "该国家不在待占领队列中" end

    local country = state.europe[countryId]
    if not country then return false, "目标国家不存在" end

    -- 找到目标势力
    local targetFaction = nil
    if factionId then
        for _, f in ipairs(state.ai_factions or {}) do
            if f.id == factionId then targetFaction = f; break end
        end
    else
        -- 选择好感度最高的势力
        local bestAtt = -999
        for _, f in ipairs(state.ai_factions or {}) do
            if (f.attitude or 0) > bestAtt then
                bestAtt = f.attitude or 0
                targetFaction = f
            end
        end
    end
    if not targetFaction then return false, "没有可用的势力" end

    -- AP消耗
    local availableAP = state.ap.current + (state.ap.temp or 0)
    if availableAP < BE.give_to_faction_ap then
        return false, string.format("行动点不足（需要 %d AP）", BE.give_to_faction_ap)
    end

    GameState.SpendAP(state, BE.give_to_faction_ap)

    -- 关系加成
    targetFaction.attitude = math.min(100,
        (targetFaction.attitude or 0) + BE.give_to_faction_relation)

    -- 从待占领队列移除
    table.remove(state.expeditions.awaiting_occupation, idx)

    -- 恢复该国HP到50%（势力接管但不完全控制）
    country.current_hp = math.floor((country.max_hp or 1) * 0.5)
    if country.political_hp and country.max_political_hp then
        country.political_hp = math.floor(country.max_political_hp * 0.5)
    end

    -- 侵略度 +1（比自占低）
    state.expeditions.aggression_counter = (state.expeditions.aggression_counter or 0)
        + BE.aggression_per_give

    local msg = string.format(
        "🤝 将%s交给%s管理！关系 +%d（侵略度仅+%d）",
        country.label, targetFaction.name or targetFaction.id,
        BE.give_to_faction_relation, BE.aggression_per_give)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 放弃占领（让待占领国家自行恢复）
---@param state table
---@param countryId string
---@return boolean ok
---@return string msg
function Expedition.AbandonOccupation(state, countryId)
    local found = false
    local idx = 0
    for i, aw in ipairs(state.expeditions.awaiting_occupation or {}) do
        if aw.country_id == countryId then
            found = true
            idx = i
            break
        end
    end
    if not found then return false, "该国家不在待占领队列中" end

    local country = state.europe[countryId]
    table.remove(state.expeditions.awaiting_occupation, idx)

    -- 恢复HP到30%
    if country then
        country.current_hp = math.floor((country.max_hp or 1) * 0.3)
        if country.political_hp and country.max_political_hp then
            country.political_hp = math.floor(country.max_political_hp * 0.3)
        end
    end

    local label = country and country.label or countryId
    local msg = string.format("放弃对%s的占领，该国防御将逐步恢复", label)
    GameState.AddLog(state, msg)
    return true, msg
end

-- ============================================================================
-- 支援作战（保留原逻辑）
-- ============================================================================

--- 支援作战（佣兵支援正在交战的列强）
---@param state table
---@param targetPowerId string
---@param squadId string|nil
---@return boolean ok
---@return string msg
function Expedition.Support(state, targetPowerId, squadId)
    if not Expedition.CanDoExpedition(state) then
        return false, "需要解锁[幕后执政]称号"
    end

    local targetCountry = state.europe[targetPowerId]
    if not targetCountry then return false, "目标国家不存在" end

    -- 检查是否有活跃战线涉及该大国
    local hasWar = false
    for _, front in ipairs(state.fronts or {}) do
        if front.attacker == targetPowerId or front.defender == targetPowerId then
            hasWar = true; break
        end
    end
    if not hasWar then
        return false, string.format("%s 当前未处于战争状态", targetCountry.label)
    end

    local availableAP = state.ap.current + (state.ap.temp or 0)
    if availableAP < BE.support_ap_cost then
        return false, string.format("行动点不足（需要 %d AP）", BE.support_ap_cost)
    end
    if state.cash < BE.support_cash_cost then
        return false, string.format("现金不足（需要 %d）", BE.support_cash_cost)
    end

    GameState.SpendAP(state, BE.support_ap_cost)
    state.cash = state.cash - BE.support_cash_cost

    -- 成功判定
    local playerPower = Combat.PlayerPower(state)
    local successRate = math.min(0.95,
        BE.support_base_success + playerPower * BE.support_power_factor)
    local roll = math.random()
    local won = roll < successRate

    if won then
        local inflation = GameState.GetInflationFactor(state)
        local reward = math.floor(
            math.random(BE.support_reward_min, BE.support_reward_max) * inflation)
        state.cash = state.cash + reward
        -- 家族学位：外交学院（collaboration_pct）—— 合作度增益加成
        local baseCollab = 5
        local degreeCollabPct = GameState.GetActiveDegreeEffect and GameState.GetActiveDegreeEffect(state, "collaboration_pct") or 0
        if degreeCollabPct > 0 then
            baseCollab = math.floor(baseCollab * (1 + degreeCollabPct))
        end
        state.collaboration_score = (state.collaboration_score or 0) + baseCollab
        Equipment.OnBattleEnd(state, squadId and {squadId} or nil)
        state.expeditions.history.support_missions =
            (state.expeditions.history.support_missions or 0) + 1

        local msg = string.format(
            "🤝 支援%s作战成功！获得佣兵报酬 %d 克朗，合作度+5",
            targetCountry.label, reward)
        GameState.AddLog(state, msg)
        return true, msg
    else
        local lost = math.random(1, 2)
        lost = math.min(lost, state.military.guards)
        state.military.guards = math.max(0, state.military.guards - lost)
        Equipment.OnGuardsLost(state, lost)

        local msg = string.format(
            "💥 支援%s作战失败，折损 %d 名护卫（成功率 %d%%）",
            targetCountry.label, lost, math.floor(successRate * 100))
        GameState.AddLog(state, msg)
        return false, msg
    end
end

-- ============================================================================
-- 每季结算
-- ============================================================================

--- 每季结算：占领收入/维护 + 侵略衰减 + 制裁检查
---@param state table
---@return table report
function Expedition.SettleTurn(state)
    local report = {
        income = 0,
        maintenance = 0,
        net = 0,
        lost_countries = {},
        aggression = state.expeditions.aggression_counter or 0,
    }

    -- 称号modifier：占领维护费折扣
    local maintDiscount = GameState.GetModifierValue(state, "occupation_maintenance_discount")

    -- 占领收入/维护
    local kept = {}
    for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
        local actualMaint = math.floor(occ.maintenance * (1 - maintDiscount))
        local inflation = GameState.GetInflationFactor(state)
        local inflatedIncome = math.floor(occ.income_per_turn * inflation)

        -- A2: 策略效果 & 稳定度结算
        local BP = BE.policies or {}
        local policyId = occ.development_policy or "tax"
        local polCfg = BP[policyId] or BP.tax or {}

        -- 策略延迟倒计时
        if (occ.policy_delay_remaining or 0) > 0 then
            occ.policy_delay_remaining = occ.policy_delay_remaining - 1
        end
        local policyActive = (occ.policy_delay_remaining or 0) <= 0

        -- 稳定度自然回复（每季 +recovery×stab_mult）
        local stabRecovery = BE.stability_recovery or 8
        local stabMult = policyActive and (polCfg.stab_mult or 1.0) or 1.0
        occ.stability_control = math.min(100,
            (occ.stability_control or 40) + math.floor(stabRecovery * stabMult))

        -- 收入按稳定度打折（低于阈值则按比例削减）
        local stabThreshold = BE.stability_threshold or 50
        local stabRatio = math.min(1.0, (occ.stability_control or 40) / stabThreshold)
        local incomeMult = policyActive and (polCfg.income_mult or 1.0) or 1.0
        -- 工业开发：额外奖励收入
        local incomeBonus = 0
        if policyActive and polCfg.income_bonus_minor then
            local isMajorOcc = (state.europe[occ.country_id] or {}).tier == "major"
            incomeBonus = isMajorOcc and (polCfg.income_bonus_major or 0) or polCfg.income_bonus_minor
        end
        local finalIncome = math.floor((inflatedIncome * incomeMult + incomeBonus) * stabRatio)

        -- 傀儡策略：加速侵略衰减（在 SettleTurn 末尾处理）
        if policyActive and polCfg.aggr_decay_mult and polCfg.aggr_decay_mult > 1.0 then
            occ._puppet_decay_mult = polCfg.aggr_decay_mult
        else
            occ._puppet_decay_mult = nil
        end

        -- 文化同化：每季加全局控制度
        if policyActive and (polCfg.control_bonus or 0) > 0 then
            for _, r in ipairs(state.regions or {}) do
                r.control = math.min(100, (r.control or 0) + polCfg.control_bonus)
            end
        end

        if state.cash >= actualMaint then
            state.cash = state.cash + finalIncome - actualMaint
            report.income = report.income + finalIncome
            report.maintenance = report.maintenance + actualMaint
            table.insert(kept, occ)
        else
            table.insert(report.lost_countries, occ.label or occ.country_id)
            local country = state.europe[occ.country_id]
            if country then
                country.current_hp = math.floor((country.max_hp or 0) * 0.5)
                if country.political_hp then
                    country.political_hp = math.floor((country.max_political_hp or 0) * 0.5)
                end
                -- 恢复原始主权
                country.sovereign = country.original
            end
        end
    end
    state.expeditions.occupied_countries = kept

    report.net = report.income - report.maintenance

    -- 侵略衰减（基础 + A4 外交官专精 + A2 傀儡策略加成）
    local specAggrDecay = GameState.GetModifierValue(state, "spec_aggression_decay")
    local totalDecay = BE.aggression_decay + specAggrDecay
    -- A2：傀儡策略加速衰减（取所有占领地中最高的 aggr_decay_mult）
    local maxPuppetMult = 1.0
    for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
        if (occ._puppet_decay_mult or 1.0) > maxPuppetMult then
            maxPuppetMult = occ._puppet_decay_mult
        end
    end
    totalDecay = totalDecay * maxPuppetMult
    state.expeditions.aggression_counter = math.max(0,
        (state.expeditions.aggression_counter or 0) - totalDecay)
    report.aggression = state.expeditions.aggression_counter

    return report
end

-- ============================================================================
-- 查询/汇总 API（供UI使用）
-- ============================================================================

-- ============================================================================
-- A2: 发展策略设置
-- ============================================================================

--- 为已占领国家设置发展策略
---@param state table
---@param countryId string
---@param policyId string  "tax"|"industrial"|"puppet"|"culture"
---@return boolean ok
---@return string msg
function Expedition.SetPolicy(state, countryId, policyId)
    local BP = BE.policies or {}
    local polCfg = BP[policyId]
    if not polCfg then return false, "未知策略: " .. tostring(policyId) end

    -- 找到占领记录
    local occ = nil
    for _, o in ipairs(state.expeditions.occupied_countries or {}) do
        if o.country_id == countryId then occ = o; break end
    end
    if not occ then return false, "该国家未被占领" end

    -- 检查锁定期
    local currentTurn = state.turn_count or 0
    if (occ.policy_lock_turn or 0) > currentTurn then
        local remaining = occ.policy_lock_turn - currentTurn
        return false, string.format("策略锁定中（还需 %d 季）", remaining)
    end

    -- 检查文化同化的魅力需求
    if policyId == "culture" then
        local leader = GameState.GetMemberAtPosition(state, "diplomat")
        local charisma = leader and (leader.charisma or 0) or 0
        local req = polCfg.charisma_req or 3
        if charisma < req then
            return false, string.format("文化同化需要外交官魅力≥%d（当前%d）", req, charisma)
        end
    end

    -- 检查前置费用
    local upfrontCost = polCfg.upfront_cost or 0
    if upfrontCost > 0 and state.cash < upfrontCost then
        return false, string.format("资金不足（需要 %d 克朗）", upfrontCost)
    end
    if upfrontCost > 0 then
        state.cash = state.cash - upfrontCost
    end

    -- 设置策略
    local lockDuration = BE.policy_lock_duration or 4
    occ.development_policy = policyId
    occ.policy_lock_turn = currentTurn + lockDuration
    occ.policy_delay_remaining = polCfg.delay_seasons or 0

    local msg = string.format(
        "🏛 %s 已切换为「%s」（锁定 %d 季%s）",
        occ.label or countryId, polCfg.name or policyId, lockDuration,
        (polCfg.delay_seasons or 0) > 0
            and string.format("，%d 季后生效", polCfg.delay_seasons) or "")
    GameState.AddLog(state, msg)
    return true, msg
end

--- 获取远征系统摘要
---@param state table
---@return table summary
function Expedition.GetSummary(state)
    local exp = state.expeditions or {}
    -- 计算活跃远征数
    local activeCount = 0
    for _ in pairs(exp.active or {}) do
        activeCount = activeCount + 1
    end
    return {
        active_count = activeCount,
        active_expeditions = exp.active or {},
        awaiting_occupation = exp.awaiting_occupation or {},
        occupied_count = #(exp.occupied_countries or {}),
        occupied_countries = exp.occupied_countries or {},
        aggression = exp.aggression_counter or 0,
        sanction_active = (exp.aggression_counter or 0) >= BE.sanction_threshold,
        history = exp.history or {},
    }
end

--- 检查是否触发制裁
---@param state table
---@return boolean sanctioned
---@return string|nil reason
function Expedition.CheckSanction(state)
    local agg = state.expeditions.aggression_counter or 0
    local collabScore = state.collaboration_score or 0
    local sanctionBonus = 0
    if collabScore > -30 and collabScore <= -10 then
        sanctionBonus = 3
    end
    if agg >= BE.intervention_threshold + sanctionBonus then
        return true, "military_intervention"
    elseif agg >= BE.sanction_threshold + sanctionBonus then
        return true, "economic_sanction"
    end
    return false, nil
end

-- ============================================================================
-- C2 外交路线（非战争扩张）
-- ============================================================================

--- 计算目标国家在指定国家的贸易路线数量
---@param state table
---@param countryId string
---@return number
local function CountTradeRoutesToCountry(state, countryId)
    local count = 0
    for _, route in ipairs((state.trade and state.trade.routes) or {}) do
        if route.buyer_power_id == countryId and route.active then
            count = count + 1
        end
    end
    return count
end

--- 获取可发起外交施压的目标列表
---@param state table
---@return table[]  每项 { country_id, label, stability, charisma_ok, routes, pool }
function Expedition.GetDiplomacyTargets(state)
    local results = {}
    local leader = GameState.GetMemberAtPosition(state, "diplomat")
    local charisma = leader and (leader.charisma or 0) or 0
    local reqCharisma = BE.diplomacy_charisma_req or 3
    local maxStab = BE.diplomacy_stability_max or 8

    for countryId, country in pairs(state.europe or {}) do
        -- 排除已占领、已在远征、已在外交中的
        local isOccupied = false
        for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
            if occ.country_id == countryId then isOccupied = true; break end
        end
        if isOccupied then goto skip_dip end
        if (state.expeditions.active or {})[countryId] then goto skip_dip end
        if (state.expeditions.diplomacy_active or {})[countryId] then goto skip_dip end

        -- 稳定度检查
        local stab = country.stability or 10
        if stab > maxStab then goto skip_dip end

        -- 至少有一条贸易路线
        local routes = CountTradeRoutesToCountry(state, countryId)
        if routes <= 0 then goto skip_dip end

        table.insert(results, {
            country_id   = countryId,
            label        = country.label or countryId,
            stability    = stab,
            charisma_ok  = charisma >= reqCharisma,
            charisma     = charisma,
            routes       = routes,
            pool         = math.floor(stab * (BE.diplomacy_influence_pool_mult or 15)),
        })
        ::skip_dip::
    end

    table.sort(results, function(a, b) return a.stability < b.stability end)
    return results
end

--- 发起外交施压
---@param state table
---@param countryId string
---@return boolean ok
---@return string msg
function Expedition.LaunchDiplomacy(state, countryId)
    local country = state.europe[countryId]
    if not country then return false, "目标国家不存在" end

    -- 前置检查
    local leader = GameState.GetMemberAtPosition(state, "diplomat")
    local charisma = leader and (leader.charisma or 0) or 0
    local reqCharisma = BE.diplomacy_charisma_req or 3
    if charisma < reqCharisma then
        return false, string.format("需要外交官魅力≥%d（当前%d）", reqCharisma, charisma)
    end

    local stab = country.stability or 10
    if stab > (BE.diplomacy_stability_max or 8) then
        return false, string.format("%s稳定度过高（%d），无法外交渗透", country.label, stab)
    end

    local routes = CountTradeRoutesToCountry(state, countryId)
    if routes <= 0 then
        return false, string.format("需要先开通对%s的贸易路线", country.label)
    end

    if (state.expeditions.active or {})[countryId] then
        return false, "正在对该国进行军事远征，无法同时外交施压"
    end
    if (state.expeditions.diplomacy_active or {})[countryId] then
        return false, "已在对该国进行外交施压"
    end

    -- 消耗检查
    local apCost = BE.diplomacy_ap_cost or 1
    local infCost = BE.diplomacy_influence_cost or 20
    local availAP = (state.ap.current or 0) + (state.ap.temp or 0)
    if availAP < apCost then
        return false, string.format("行动点不足（需要 %d AP）", apCost)
    end
    state.diplomatic_influence = state.diplomatic_influence or 0
    if state.diplomatic_influence < infCost then
        return false, string.format("外交影响力不足（需要 %d，当前 %d）",
            infCost, state.diplomatic_influence)
    end

    -- 消耗资源
    GameState.SpendAP(state, apCost)
    state.diplomatic_influence = state.diplomatic_influence - infCost

    -- 初始化记录
    local pool = math.floor(stab * (BE.diplomacy_influence_pool_mult or 15))
    state.expeditions.diplomacy_active = state.expeditions.diplomacy_active or {}
    state.expeditions.diplomacy_active[countryId] = {
        country_id         = countryId,
        label              = country.label,
        started_turn       = state.turn_count or 0,
        influence_progress = 0,
        influence_pool     = pool,
        treaty_type        = nil,
        treaty_turn        = 0,
        fail_penalty       = 0,
    }

    local msg = string.format("🤝 对%s发起外交施压（需积累 %d 点影响力）", country.label, pool)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 计算每季影响力增量
---@param state table
---@param rec table  外交记录
---@return number delta
local function CalcDiplomacyDelta(state, rec)
    local leader = GameState.GetMemberAtPosition(state, "diplomat")
    local charisma = leader and (leader.charisma or 0) or 0
    local routes = CountTradeRoutesToCountry(state, rec.country_id)
    local country = state.europe[rec.country_id]
    local stab = country and country.stability or 5
    local delta = charisma * 3 + routes * 2 - stab * 1.5

    -- 军事征服后加速 +50%
    local alreadyConquered = false
    for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
        if occ.country_id == rec.country_id then alreadyConquered = true; break end
    end
    if alreadyConquered then
        delta = delta * (1 + (BE.diplomacy_military_bonus or 0.50))
    end

    return math.max(1, math.floor(delta))
end

--- 每季外交结算（TickDiplomacy）
---@param state table
function Expedition.TickDiplomacy(state)
    state.expeditions.diplomacy_active = state.expeditions.diplomacy_active or {}
    local Events = require("systems.events")
    local toRemove = {}

    for countryId, rec in pairs(state.expeditions.diplomacy_active) do
        local country = state.europe[countryId]
        if not country then
            table.insert(toRemove, countryId); goto continue_dip
        end

        -- 协议已破裂 → 清除记录
        if rec.treaty_type == "broken" then
            table.insert(toRemove, countryId)
            GameState.AddLog(state, string.format("❌ 与%s的外交关系已终止", rec.label))
            goto continue_dip
        end

        -- 协议进行中结算
        if rec.treaty_type then
            if rec.treaty_type == "protection" then
                state.cash = (state.cash or 0) + (BE.diplomacy_protection_income or 50)
            elseif rec.treaty_type == "vassal" then
                state.cash = (state.cash or 0) + (BE.diplomacy_vassal_income or 60)
                -- 5% 反叛检查
                if math.random() < (BE.diplomacy_revolt_chance or 0.05) then
                    Events.Enqueue(state, {{
                        id = "diplomacy_vassal_revolt_" .. countryId,
                        title = string.format("%s臣服反叛", rec.label),
                        description = string.format(
                            "%s的臣服关系出现动荡，当地势力要求恢复自主权。",
                            rec.label),
                        options = {
                            {
                                text = string.format("强力镇压（花费 %d 克朗）",
                                    BE.diplomacy_revolt_cost or 200),
                                effects = {
                                    custom = function(st, _)
                                        local cost = BE.diplomacy_revolt_cost or 200
                                        if (st.cash or 0) >= cost then
                                            st.cash = st.cash - cost
                                            GameState.AddLog(st, string.format(
                                                "🗡 镇压%s叛乱，花费 %d 克朗", rec.label, cost))
                                        else
                                            -- 现金不足，自动退回保护协议
                                            local dipRec = st.expeditions.diplomacy_active[countryId]
                                            if dipRec then
                                                dipRec.treaty_type = "protection"
                                                dipRec.fail_penalty = (dipRec.fail_penalty or 0) + (BE.diplomacy_failed_penalty or 0.20)
                                            end
                                            GameState.AddLog(st, string.format(
                                                "⚠ 现金不足，%s退回保护协议状态", rec.label))
                                        end
                                    end,
                                },
                            },
                            {
                                text = "接受反叛（退回保护协议）",
                                effects = {
                                    custom = function(st, _)
                                        local dipRec = st.expeditions.diplomacy_active[countryId]
                                        if dipRec then
                                            dipRec.treaty_type = "protection"
                                            dipRec.fail_penalty = (dipRec.fail_penalty or 0) + (BE.diplomacy_failed_penalty or 0.20)
                                        end
                                        GameState.AddLog(st, string.format(
                                            "🏳 接受%s反叛，退回保护协议，下次谈判难度+20%%", rec.label))
                                    end,
                                },
                            },
                        },
                    }})
                end
            elseif rec.treaty_type == "trade_concession" then
                -- 写入贸易加成 modifier（每季刷新）
                state.modifiers = state.modifiers or {}
                state.modifiers["diplomacy_trade_bonus_" .. countryId] = {
                    type = "trade_route_income_mult",
                    value = BE.diplomacy_trade_bonus or 0.20,
                    country_id = countryId,
                    source = "diplomacy_trade_concession",
                }
            elseif rec.treaty_type == "military_alliance" then
                -- 守备加成写入临时 modifier（每季刷新）
                state.modifiers = state.modifiers or {}
                state.modifiers["diplomacy_alliance_" .. countryId] = {
                    type = "guard_bonus",
                    value = 1,
                    country_id = countryId,
                    source = "diplomacy_military_alliance",
                }
            end
            goto continue_dip
        end

        -- 渗透推进阶段
        local delta = CalcDiplomacyDelta(state, rec)
        rec.influence_progress = math.min(rec.influence_pool,
            (rec.influence_progress or 0) + delta)

        -- 检查是否到达谈判阈值
        if rec.influence_progress >= rec.influence_pool then
            Expedition.ResolveDiplomacy(state, countryId)
        end

        ::continue_dip::
    end

    for _, id in ipairs(toRemove) do
        -- 清除协议 modifier
        if state.modifiers then
            state.modifiers["diplomacy_trade_bonus_" .. id] = nil
            state.modifiers["diplomacy_alliance_" .. id] = nil
        end
        state.expeditions.diplomacy_active[id] = nil
    end

    -- 全局 diplomatic_influence 自然积累
    state.diplomatic_influence = (state.diplomatic_influence or 0)
        + (BE.diplomacy_influence_per_turn or 5)
end

--- 影响力满时触发谈判窗口（推入事件队列）
---@param state table
---@param countryId string
function Expedition.ResolveDiplomacy(state, countryId)
    local rec = (state.expeditions.diplomacy_active or {})[countryId]
    if not rec then return end
    local country = state.europe[countryId]
    if not country then return end

    local leader = GameState.GetMemberAtPosition(state, "diplomat")
    local charisma = leader and (leader.charisma or 0) or 0
    local failPenalty = rec.fail_penalty or 0

    -- 构建可用协议选项（魅力过滤）
    local options = {}

    -- 贸易特许（始终可用，有贸易路线）
    local routes = CountTradeRoutesToCountry(state, countryId)
    if routes > 0 then
        table.insert(options, {
            text = string.format("贸易特许（该国所有贸易路线利润+20%%）"),
            effects = {
                custom = function(st, _)
                    local dr = st.expeditions.diplomacy_active[countryId]
                    if dr then
                        dr.treaty_type = "trade_concession"
                        dr.treaty_turn = st.turn_count or 0
                    end
                    GameState.AddLog(st, string.format("📜 与%s签订贸易特许协议", rec.label))
                end,
            },
        })
    end

    -- 保护协议（始终可用）
    table.insert(options, {
        text = string.format("保护协议（每季 +%d 克朗，主权不变）",
            BE.diplomacy_protection_income or 50),
        effects = {
            custom = function(st, _)
                local dr = st.expeditions.diplomacy_active[countryId]
                if dr then
                    dr.treaty_type = "protection"
                    dr.treaty_turn = st.turn_count or 0
                end
                GameState.AddLog(st, string.format("🛡 与%s签订保护协议", rec.label))
            end,
        },
    })

    -- 军事同盟（魅力 ≥ 4）
    if charisma >= (BE.diplomacy_charisma_req_vassal or 4) then
        table.insert(options, {
            text = "军事同盟（守备+1等效编队，好感+10）",
            effects = {
                custom = function(st, _)
                    local dr = st.expeditions.diplomacy_active[countryId]
                    if dr then
                        dr.treaty_type = "military_alliance"
                        dr.treaty_turn = st.turn_count or 0
                    end
                    -- 好感 +10
                    if st.powers and st.powers[countryId] then
                        st.powers[countryId].attitude_to_player =
                            math.min(100, (st.powers[countryId].attitude_to_player or 0) + 10)
                    end
                    state.expeditions.aggression_counter =
                        (state.expeditions.aggression_counter or 0) + 1
                    GameState.AddLog(st, string.format("⚔ 与%s缔结军事同盟", rec.label))
                end,
            },
        })
    end

    -- 臣服关系（魅力 ≥ 4，需 1.5× 影响力池）
    local vassalPool = math.floor(rec.influence_pool * (BE.diplomacy_vassal_influence_mult or 1.5))
    if charisma >= (BE.diplomacy_charisma_req_vassal or 4)
        and rec.influence_progress >= vassalPool * (1 - failPenalty) then
        table.insert(options, {
            text = string.format("臣服关系（每季 +%d 克朗，侵略度+1，可能反叛）",
                BE.diplomacy_vassal_income or 60),
            effects = {
                custom = function(st, _)
                    local dr = st.expeditions.diplomacy_active[countryId]
                    if dr then
                        dr.treaty_type = "vassal"
                        dr.treaty_turn = st.turn_count or 0
                    end
                    st.expeditions.aggression_counter =
                        (st.expeditions.aggression_counter or 0) + 1
                    GameState.AddLog(st, string.format(
                        "👑 %s臣服！每季 +%d 克朗（注意反叛风险）",
                        rec.label, BE.diplomacy_vassal_income or 60))
                end,
            },
        })
    end

    -- 推入事件队列
    local Events = require("systems.events")
    Events.Enqueue(state, {{
        id = "diplomacy_negotiate_" .. countryId,
        title = string.format("外交谈判：%s", rec.label),
        description = string.format(
            "长期外交施压已奏效，%s愿意就双边关系进行谈判。请选择协议类型：",
            rec.label),
        options = options,
    }})

    GameState.AddLog(state, string.format(
        "🤝 外交施压奏效！%s已进入谈判窗口", rec.label))
end

--- 取消外交施压（清除记录和协议 modifier）
---@param state table
---@param countryId string
---@return boolean ok
---@return string msg
function Expedition.CancelDiplomacy(state, countryId)
    local rec = (state.expeditions.diplomacy_active or {})[countryId]
    if not rec then return false, "无该国外交记录" end
    -- 清除 modifier
    if state.modifiers then
        state.modifiers["diplomacy_trade_bonus_" .. countryId] = nil
        state.modifiers["diplomacy_alliance_" .. countryId] = nil
    end
    state.expeditions.diplomacy_active[countryId] = nil
    return true, string.format("已撤回对%s的外交施压", rec.label)
end

return Expedition
