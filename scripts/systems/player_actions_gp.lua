-- ============================================================================
-- 玩家与大国互动行动（Phase 3）
-- 四种姿态：合作 / 加入 / 制衡 / 抵抗
-- ============================================================================

local Balance    = require("data.balance")
local GameState  = require("game_state")
local GrandPowers = require("systems.grand_powers")
local Equipment  = require("systems.equipment")
local Trade      = require("systems.trade")

local PlayerActionsGP = {}

-- ============================================================================
-- 行动定义
-- ============================================================================

--- 所有可用行动（按姿态分组）
--- 每个行动: { id, label, stance, icon, ap_cost, condition(state,powerId), execute(state,powerId) }
local ACTIONS = {}

-- ── 合作 (Collaborate) ──

ACTIONS.war_supplier = {
    id = "war_supplier",
    label = "战争供给商",
    desc = "向交战大国出售矿产物资，获取丰厚利润",
    stance = "collaborate",
    icon = "📦",
    ap_cost = 1,
    collab_delta = 5,
    condition = function(state, powerId)
        local power = state.powers and state.powers[powerId]
        if not power or not power.active then return false, "大国不活跃" end
        if power.war_fatigue <= 0 then return false, "该国未在战争中" end
        if power.attitude_to_player < -20 then return false, "关系过差" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        -- E5: 收入跟通胀
        local inflation = GameState.GetInflationFactor(state)
        local income = math.floor((300 + math.floor(power.military * 5)) * inflation)
        state.cash = state.cash + income
        state.collaboration_score = (state.collaboration_score or 0) + 5
        power.attitude_to_player = math.min(100, power.attitude_to_player + 5)
        GameState.AddLog(state, string.format("向 %s 供应战争物资，获利 %d 克朗", power.label, income))

        -- ── P2-3c 外交→贸易耦合：war_supplier 立即生成1个贸易订单 ──
        if Trade and Trade.GenerateBonusOrder then
            local ok, tradeMsg = Trade.GenerateBonusOrder(state, powerId)
            if ok then
                GameState.AddLog(state, "[外交→贸易] " .. tradeMsg)
            end
        end

        return string.format("向 %s 供应物资，获利 %d", power.label, income)
    end,
}

ACTIONS.cooperative_management = {
    id = "cooperative_management",
    label = "合作经营",
    desc = "与占领方合作维持经营，收入稳定但战后可能清算",
    stance = "collaborate",
    icon = "🤝",
    ap_cost = 1,
    collab_delta = 3,
    condition = function(state, powerId)
        local isOccupied, occupierId = GrandPowers.IsSarajevoOccupied(state)
        if not isOccupied then return false, "未被占领" end
        if occupierId ~= powerId then return false, "非当前占领方" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        local income = 200
        state.cash = state.cash + income
        state.collaboration_score = (state.collaboration_score or 0) + 3
        power.attitude_to_player = math.min(100, power.attitude_to_player + 3)
        GameState.AddLog(state, string.format("与 %s 占领当局合作经营，获利 %d 克朗", power.label, income))
        return string.format("合作经营，获利 %d", income)
    end,
}

-- ── 加入 (Join) ──

ACTIONS.send_volunteers = {
    id = "send_volunteers",
    label = "派遣志愿军",
    desc = "派遣武装人员协助大国军事行动，损失部分武装但提升关系",
    stance = "join",
    icon = "⚔️",
    ap_cost = 2,
    collab_delta = 8,
    condition = function(state, powerId)
        local power = state.powers and state.powers[powerId]
        if not power or not power.active then return false, "大国不活跃" end
        if state.military.guards < 5 then return false, "武装不足（需≥5）" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        local loss = math.random(2, 4)
        local oldGuards = state.military.guards
        state.military.guards = math.max(0, state.military.guards - loss)
        local actualLoss = oldGuards - state.military.guards
        if actualLoss > 0 then
            Equipment.OnGuardsLost(state, actualLoss)
        end
        power.military = math.min(100, power.military + 1)
        power.attitude_to_player = math.min(100, power.attitude_to_player + 15)
        state.collaboration_score = (state.collaboration_score or 0) + 8
        GameState.AddLog(state, string.format("向 %s 派遣志愿军，损失 %d 名武装", power.label, actualLoss))
        return string.format("派遣志愿军，损失 %d 武装", actualLoss)
    end,
}

ACTIONS.share_intel = {
    id = "share_intel",
    label = "情报共享",
    desc = "向大国提供本地情报，加速其征服目标",
    stance = "join",
    icon = "👁️",
    ap_cost = 1,
    collab_delta = 5,
    condition = function(state, powerId)
        local power = state.powers and state.powers[powerId]
        if not power or not power.active then return false, "大国不活跃" end
        if not power.war_goals or #power.war_goals == 0 then return false, "该国无征服目标" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        -- 加速征服（通过降低目标抵抗）
        if power.war_goals and #power.war_goals > 0 and state.europe then
            local targetId = power.war_goals[1]
            local target = state.europe[targetId]
            if target then
                target.stability = math.max(10, target.stability - 5)
            end
        end
        power.attitude_to_player = math.min(100, power.attitude_to_player + 10)
        state.collaboration_score = (state.collaboration_score or 0) + 5
        GameState.AddLog(state, string.format("向 %s 提供情报支援", power.label))
        return string.format("向 %s 提供情报", power.label)
    end,
}

-- ── 制衡 (Counter) ──

ACTIONS.economic_sanction = {
    id = "economic_sanction",
    label = "经济制裁",
    desc = "利用贸易网络削弱目标大国的经济实力",
    stance = "counter",
    icon = "💰",
    ap_cost = 2,
    collab_delta = -3,
    condition = function(state, powerId)
        local power = state.powers and state.powers[powerId]
        if not power or not power.active then return false, "大国不活跃" end
        local totalControl = GameState.CalcTotalControl(state)
        if totalControl < 30 then return false, "控制度不足（需≥30）" end
        if state.cash < 100 then return false, "现金不足（需≥100）" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        power.economy = math.max(0, power.economy - 3)
        power.attitude_to_player = math.max(-100, power.attitude_to_player - 10)
        state.collaboration_score = (state.collaboration_score or 0) - 3
        -- 自身贸易收入受损
        state.cash = math.max(0, state.cash - 100)
        GameState.AddLog(state, string.format("对 %s 实施经济制裁，贸易收入减少 100", power.label))
        return string.format("制裁 %s，经济 -3", power.label)
    end,
}

ACTIONS.currency_war = {
    id = "currency_war",
    label = "货币战争",
    desc = "投入大量资金加速目标大国的厌战情绪",
    stance = "counter",
    icon = "🏦",
    ap_cost = 2,
    collab_delta = -5,
    condition = function(state, powerId)
        local power = state.powers and state.powers[powerId]
        if not power or not power.active then return false, "大国不活跃" end
        if state.cash < 2000 then return false, "现金不足（需≥2000）" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        power.war_fatigue = math.min(100, power.war_fatigue + 3)
        power.attitude_to_player = math.max(-100, power.attitude_to_player - 15)
        state.cash = state.cash - 2000
        state.collaboration_score = (state.collaboration_score or 0) - 5
        GameState.AddLog(state, string.format("对 %s 发动货币战争，花费 2000 克朗", power.label))
        return string.format("货币战 %s，厌战 +3，花费 2000", power.label)
    end,
}

-- ── 抵抗 (Resist) ──

ACTIONS.support_guerrilla = {
    id = "support_guerrilla",
    label = "支持游击队",
    desc = "资助被占领区域的地下抵抗组织",
    stance = "resist",
    icon = "🔥",
    ap_cost = 2,
    collab_delta = -8,
    condition = function(state, powerId)
        local isOccupied, occupierId = GrandPowers.IsSarajevoOccupied(state)
        if not isOccupied then return false, "未被占领" end
        if occupierId ~= powerId then return false, "非当前占领方" end
        if state.cash < 200 then return false, "现金不足（需≥200）" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        power.war_fatigue = math.min(100, power.war_fatigue + 2)
        state.cash = state.cash - 200
        state.collaboration_score = (state.collaboration_score or 0) - 8
        -- 提升被占领区域的抵抗值（根据实际被占领的区域动态查找）
        if state.europe then
            for _, regionId in ipairs({"austria_hungary", "serbia"}) do
                local region = state.europe[regionId]
                if region and region.sovereign ~= region.original then
                    region.resistance = math.min(100, (region.resistance or 0) + 5)
                end
            end
        end
        -- ── P2-3c 外交→远征耦合：游击队降低远征难度 ──
        -- 如果玩家已占领某些区域或正在远征，降低远征难度10%，持续2回合
        if state.expeditions and #(state.expeditions.occupied_countries or {}) > 0 then
            GameState.AddModifier(state,
                "guerrilla_support",              -- source
                "guerrilla_difficulty_reduction",  -- target
                0.10,                              -- -10% 难度
                2)                                 -- 持续2回合
            GameState.AddLog(state, "[外交→远征] 游击队破坏敌方补给线，远征难度降低10%（2回合）")
        end

        GameState.AddLog(state, string.format("资助对 %s 的游击队，花费 200 克朗", power.label))
        return string.format("资助游击队，%s 厌战 +2", power.label)
    end,
}

ACTIONS.shelter_refugees = {
    id = "shelter_refugees",
    label = "庇护难民",
    desc = "接收战争难民，提升声望和人口",
    stance = "resist",
    icon = "🏠",
    ap_cost = 1,
    collab_delta = -5,
    condition = function(state, powerId)
        local power = state.powers and state.powers[powerId]
        if not power or not power.active then return false, "大国不活跃" end
        -- S2: 4季冷却
        if (state._shelter_cooldown or 0) > 0 then
            return false, string.format("冷却中（剩余 %d 季）", state._shelter_cooldown)
        end
        -- 需要有被占领的国家
        local hasOccupied = false
        if state.europe then
            for _, country in pairs(state.europe) do
                if country.sovereign ~= country.original then
                    hasOccupied = true
                    break
                end
            end
        end
        if not hasOccupied then return false, "无被占领国家" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        -- 声望（控制度）提升
        for _, r in ipairs(state.regions) do
            r.control = math.min(100, (r.control or 0) + 3)
        end
        -- S2: 人口 50→20，加4季冷却
        state.workers.hired = state.workers.hired + 20
        state._shelter_cooldown = 4
        power.attitude_to_player = math.max(-100, power.attitude_to_player - 5)
        state.collaboration_score = (state.collaboration_score or 0) - 5
        GameState.AddLog(state, "庇护了一批战争难民，声望提升，人口 +20")
        return "庇护难民，声望 +3，人口 +20"
    end,
}

ACTIONS.sabotage_supply = {
    id = "sabotage_supply",
    label = "破坏补给线",
    desc = "派武装人员破坏占领方的后勤补给",
    stance = "resist",
    icon = "💣",
    ap_cost = 2,
    collab_delta = -10,
    condition = function(state, powerId)
        local isOccupied, occupierId = GrandPowers.IsSarajevoOccupied(state)
        if not isOccupied then return false, "未被占领" end
        if occupierId ~= powerId then return false, "非当前占领方" end
        if state.military.guards < 5 then return false, "武装不足（需≥5）" end
        return true
    end,
    execute = function(state, powerId)
        local power = state.powers[powerId]
        local loss = math.random(1, 3)
        local oldGuards = state.military.guards
        state.military.guards = math.max(0, state.military.guards - loss)
        local actualLoss = oldGuards - state.military.guards
        if actualLoss > 0 then
            Equipment.OnGuardsLost(state, actualLoss)
        end
        power.war_fatigue = math.min(100, power.war_fatigue + 3)
        power.military = math.max(0, power.military - 1)
        state.collaboration_score = (state.collaboration_score or 0) - 10
        power.attitude_to_player = math.max(-100, power.attitude_to_player - 15)
        GameState.AddLog(state, string.format("破坏 %s 补给线，损失 %d 名武装", power.label, actualLoss))
        return string.format("破坏补给线，%s 军事 -1，损失 %d 武装", power.label, actualLoss)
    end,
}

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 检查大国外交行动是否已解锁
---@param state table
---@return boolean
function PlayerActionsGP.IsUnlocked(state)
    return state.unlocked_features ~= nil
        and state.unlocked_features["gp_actions"] == true
end

--- 获取可用行动列表（按姿态分组）
---@param state table
---@param powerId string
---@return table { collaborate={}, join={}, counter={}, resist={} }
function PlayerActionsGP.GetAvailableActions(state, powerId)
    local result = {
        collaborate = {},
        join = {},
        counter = {},
        resist = {},
    }

    -- 大国外交行动未解锁时，返回空列表
    if not PlayerActionsGP.IsUnlocked(state) then
        return result
    end

    for _, action in pairs(ACTIONS) do
        local available, reason = action.condition(state, powerId)
        table.insert(result[action.stance], {
            id = action.id,
            label = action.label,
            desc = action.desc,
            icon = action.icon,
            ap_cost = action.ap_cost,
            available = available,
            reason = reason,
            collab_delta = action.collab_delta,
        })
    end

    -- 每组内按 id 排序保证稳定顺序
    for _, group in pairs(result) do
        table.sort(group, function(a, b) return a.id < b.id end)
    end

    return result
end

--- 执行一个行动
---@param state table
---@param powerId string
---@param actionId string
---@return boolean success, string message
function PlayerActionsGP.ExecuteAction(state, powerId, actionId)
    -- 大国外交行动未解锁
    if not PlayerActionsGP.IsUnlocked(state) then
        return false, "大国外交行动未解锁（需获得「情报网络」称号）"
    end

    local action = ACTIONS[actionId]
    if not action then
        return false, "未知行动"
    end

    -- 前置检查
    local available, reason = action.condition(state, powerId)
    if not available then
        return false, reason or "条件不满足"
    end

    -- 家族天赋：巧舌如簧（diplomacy_ap_reduction）—— 外交行动 AP 折扣
    local traitDiploReduce = GameState.GetActiveTraitEffect and GameState.GetActiveTraitEffect(state, "diplomacy_ap_reduction") or 0
    local effectiveAP = math.max(0, action.ap_cost - traitDiploReduce)

    -- AP 检查（含临时 AP）
    local totalAP = state.ap.current + (state.ap.temp or 0)
    if totalAP < effectiveAP then
        return false, string.format("行动点不足（需要 %d AP）", effectiveAP)
    end

    -- 扣 AP（优先消耗临时 AP）
    GameState.SpendAP(state, effectiveAP)

    -- ── 干预惯性机制（P2-2）：连续同姿态行动加成 ──
    local streakKey = powerId .. "_" .. action.stance
    local streaks = state._action_streaks or {}
    streaks[streakKey] = (streaks[streakKey] or 0) + 1
    -- 对同一大国的其他姿态计数重置
    for k, _ in pairs(streaks) do
        if k ~= streakKey and k:sub(1, #powerId + 1) == powerId .. "_" then
            streaks[k] = 0
        end
    end
    state._action_streaks = streaks
    local streakCount = streaks[streakKey]
    local streakBonus = (streakCount >= 3) and 0.20 or 0

    -- 记录 execute 前的关键状态（用于惯性加成计算）
    local power = state.powers and state.powers[powerId]
    local attBefore = power and power.attitude_to_player or 0
    local cashBefore = state.cash
    local collabBefore = state.collaboration_score or 0

    -- 执行
    local msg = action.execute(state, powerId)

    -- 应用惯性加成：对本次行动的数值变化额外 +20%
    if streakBonus > 0 and power then
        -- 好感度变化加成
        local attDelta = (power.attitude_to_player or 0) - attBefore
        if attDelta ~= 0 then
            local extra = math.floor(math.abs(attDelta) * streakBonus + 0.5)
            if attDelta > 0 then
                power.attitude_to_player = math.min(100, power.attitude_to_player + extra)
            else
                power.attitude_to_player = math.max(-100, power.attitude_to_player - extra)
            end
        end
        -- 现金收益加成（仅对收益，不加成支出）
        local cashDelta = state.cash - cashBefore
        if cashDelta > 0 then
            local extra = math.floor(cashDelta * streakBonus)
            state.cash = state.cash + extra
        end
        -- 合作度变化加成（绝对值放大）
        local collabDelta = (state.collaboration_score or 0) - collabBefore
        if collabDelta ~= 0 then
            local extra = math.floor(math.abs(collabDelta) * streakBonus + 0.5)
            if extra >= 1 then
                if collabDelta > 0 then
                    state.collaboration_score = (state.collaboration_score or 0) + extra
                else
                    state.collaboration_score = (state.collaboration_score or 0) - extra
                end
            end
        end
        -- 添加惯性提示
        msg = (msg or "") .. string.format(" 🔄惯性×%d(+%d%%)", streakCount, math.floor(streakBonus * 100))
    end

    -- 记录行动历史（用于分支标记触发器 P2-1）
    if not state.gp_action_history then state.gp_action_history = {} end
    table.insert(state.gp_action_history, {
        action = actionId,
        power = powerId,
        stance = action.stance,
        year = state.year,
        quarter = state.quarter,
    })

    -- 外交总监：正向好感度按比例加成
    if power then
        local attAfter = power.attitude_to_player or 0
        local delta = attAfter - attBefore
        if delta > 0 then
            local dipBonus = GameState.GetPositionBonus(state, "diplomat")
            if dipBonus > 0 then
                local extra = math.floor(delta * dipBonus * 0.5)
                power.attitude_to_player = math.min(100, attAfter + extra)
            end
        end
        -- 外交总监满配独有：外交密件，额外 +3 固定好感度
        if delta >= 0 and GameState.HasExcellentPosition(state, "diplomat") then
            power.attitude_to_player = math.min(100, (power.attitude_to_player or 0) + 3)
        end
    end

    -- ── E.2 抵抗/制衡路线即时反馈 ──
    local collabAfter = state.collaboration_score or 0
    local collabDelta = collabAfter - collabBefore
    if collabDelta ~= 0 and (action.stance == "resist" or action.stance == "counter") then
        -- 附加合作度变化信息
        msg = (msg or "") .. string.format("\n[合作度 %d → %d]", collabBefore, collabAfter)
        -- 里程碑阈值与奖励预告
        local milestones = {
            { threshold = -10, label = "民间同情" },
            { threshold = -20, label = "人民支持" },
            { threshold = -30, label = "抵抗英雄" },
            { threshold = -50, label = "解放先驱" },
        }
        -- 查找下一个未达到的里程碑
        for _, ms in ipairs(milestones) do
            if collabAfter > ms.threshold then
                local gap = collabAfter - ms.threshold
                msg = msg .. string.format(" 再降低%d点解锁「%s」！", gap, ms.label)
                break
            end
        end
        -- 检查本次行动是否刚好跨越了某个里程碑
        for _, ms in ipairs(milestones) do
            if collabBefore > ms.threshold and collabAfter <= ms.threshold then
                msg = msg .. string.format(" 🏆 达成「%s」里程碑！", ms.label)
                break
            end
        end
    end

    return true, msg
end

--- 获取合作度描述
---@param score number
---@return string label, table color
function PlayerActionsGP.GetCollaborationLabel(score)
    if score >= 30 then
        return "合作者", { 192, 57, 43, 255 }      -- 红色警告
    elseif score >= 10 then
        return "偏向合作", { 212, 129, 10, 255 }    -- 琥珀
    elseif score > -10 then
        return "中间路线", { 168, 152, 128, 255 }   -- 灰色
    elseif score > -30 then
        return "消极抵抗", { 58, 107, 138, 255 }    -- 蓝色
    else
        return "人民英雄", { 74, 124, 89, 255 }     -- 绿色
    end
end

return PlayerActionsGP
