-- ============================================================================
-- 玩家与大国互动行动（Phase 3）
-- 四种姿态：合作 / 加入 / 制衡 / 抵抗
-- ============================================================================

local Balance    = require("data.balance")
local GameState  = require("game_state")
local GrandPowers = require("systems.grand_powers")

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
        local income = 300 + math.floor(power.military * 5)
        state.cash = state.cash + income
        state.collaboration_score = (state.collaboration_score or 0) + 5
        power.attitude_to_player = math.min(100, power.attitude_to_player + 5)
        GameState.AddLog(state, string.format("向 %s 供应战争物资，获利 %d 克朗", power.label, income))
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
        state.military.guards = math.max(0, state.military.guards - loss)
        power.military = math.min(100, power.military + 1)
        power.attitude_to_player = math.min(100, power.attitude_to_player + 15)
        state.collaboration_score = (state.collaboration_score or 0) + 8
        GameState.AddLog(state, string.format("向 %s 派遣志愿军，损失 %d 名武装", power.label, loss))
        return string.format("派遣志愿军，损失 %d 武装", loss)
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
        local totalInfluence = GameState.CalcTotalInfluence(state)
        if totalInfluence < 30 then return false, "影响力不足（需≥30）" end
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
        -- 提升本地抵抗
        if state.europe then
            local ah = state.europe["austria_hungary"]
            if ah then
                ah.resistance = math.min(100, (ah.resistance or 0) + 5)
            end
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
        -- 声望（影响力）提升
        for _, r in ipairs(state.regions) do
            r.influence = math.min(100, (r.influence or 0) + 3)
        end
        -- 人口增加
        state.workers.count = state.workers.count + 50
        power.attitude_to_player = math.max(-100, power.attitude_to_player - 5)
        state.collaboration_score = (state.collaboration_score or 0) - 5
        GameState.AddLog(state, "庇护了一批战争难民，声望提升，人口 +50")
        return "庇护难民，声望 +3，人口 +50"
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
        state.military.guards = math.max(0, state.military.guards - loss)
        power.war_fatigue = math.min(100, power.war_fatigue + 3)
        power.military = math.max(0, power.military - 1)
        state.collaboration_score = (state.collaboration_score or 0) - 10
        power.attitude_to_player = math.max(-100, power.attitude_to_player - 15)
        GameState.AddLog(state, string.format("破坏 %s 补给线，损失 %d 名武装", power.label, loss))
        return string.format("破坏补给线，%s 军事 -1，损失 %d 武装", power.label, loss)
    end,
}

-- ============================================================================
-- 公开 API
-- ============================================================================

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
    local action = ACTIONS[actionId]
    if not action then
        return false, "未知行动"
    end

    -- 前置检查
    local available, reason = action.condition(state, powerId)
    if not available then
        return false, reason or "条件不满足"
    end

    -- AP 检查
    if state.ap.current < action.ap_cost then
        return false, string.format("行动点不足（需要 %d AP）", action.ap_cost)
    end

    -- 扣 AP
    state.ap.current = state.ap.current - action.ap_cost

    -- 执行
    local msg = action.execute(state, powerId)
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
