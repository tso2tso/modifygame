-- ============================================================================
-- 共享操作模块 — 统一"雇佣工人"和"升级矿山"的业务逻辑
-- 消除 ui_dashboard / ui_industry 之间的重复实现与 AP 不一致 bug
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")

local Actions = {}

--- 招募工人（统一入口）
---@param state table 游戏状态
---@param count number 招募数量（默认5）
---@param onDone function|nil 完成后回调
---@return boolean success
function Actions.HireWorkers(state, count, onDone)
    count = count or 5
    local hireCostMul = math.max(0.5, 1.0 + (state.hire_cost_discount or 0))
    local hireCost = math.floor(
        Balance.WORKERS.hire_cost
        * GameState.GetLaborCostFactor(state)
        * (1 - GameState.GetControlRecruitDiscount(state))
        * hireCostMul
    ) * count

    if state.cash < hireCost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return false
    end
    if not GameState.SpendAP(state, 1) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return false
    end

    state.cash = state.cash - hireCost
    state.workers.hired = state.workers.hired + count
    GameState.AddLog(state, string.format("招募了 %d 名工人，花费 %d", count, hireCost))
    UI.Toast.Show(string.format("招募 +%d 工人", count),
        { variant = "success", duration = 1.5 })

    if onDone then onDone() end
    return true
end

--- 升级矿山（统一入口，AP 消耗统一为 1）
---@param state table 游戏状态
---@param mine table 矿山对象
---@param onDone function|nil 完成后回调
---@return boolean success
function Actions.UpgradeMine(state, mine, onDone)
    if mine.level >= Balance.MINE.max_level then
        UI.Toast.Show("矿山已达最高等级", { variant = "warning", duration = 1.5 })
        return false
    end

    -- 矿山储量耗尽检查
    if (mine.reserve or 0) <= 0 then
        UI.Toast.Show("矿山储量已耗尽，无法升级", { variant = "error", duration = 2 })
        return false
    end

    local cost = math.floor(
        Balance.MINE.upgrade_cost * mine.level * GameState.GetAssetPriceFactor(state)
    )
    if state.cash < cost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return false
    end
    if not GameState.SpendAP(state, 1) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return false
    end

    state.cash = state.cash - cost
    mine.level = mine.level + 1
    GameState.AddLog(state, string.format(
        "%s 升级到 %d 级，花费 %d", mine.name, mine.level, cost))
    UI.Toast.Show(string.format("%s → Lv.%d", mine.name, mine.level),
        { variant = "success", duration = 1.5 })

    if onDone then onDone() end
    return true
end

-- ============================================================================
-- 声誉恢复行动
-- ============================================================================

--- 获取声誉恢复行动列表（带可用状态）
---@param state table
---@return table[] { id, cfg, available, reason }
function Actions.GetReputationActions(state)
    local BR = Balance.REPUTATION
    local actions = BR.actions or {}
    local result = {}
    local cooldowns = state.rep_action_cooldowns or {}
    local currentTurn = (state.year or 1878) * 4 + (state.quarter or 1)

    for id, cfg in pairs(actions) do
        local available = true
        local reason = nil

        -- AP 检查
        local totalAP = (state.ap and state.ap.current or 0) + (state.ap and state.ap.temp or 0)
        if totalAP < cfg.ap_cost then
            available = false
            reason = string.format("行动点不足（需 %d AP）", cfg.ap_cost)
        end

        -- 资金检查
        if available and state.cash < cfg.cash_cost then
            available = false
            reason = string.format("资金不足（需 %d 克朗）", cfg.cash_cost)
        end

        -- 冷却检查
        if available and cfg.cooldown > 0 then
            local lastUsed = cooldowns[id] or 0
            local remaining = lastUsed + cfg.cooldown - currentTurn
            if remaining > 0 then
                available = false
                reason = string.format("冷却中（剩余 %d 季）", remaining)
            end
        end

        -- 声誉已满不需要恢复
        if available and (state.reputation or 0) >= BR.max then
            available = false
            reason = "声誉已达上限"
        end

        table.insert(result, {
            id = id,
            cfg = cfg,
            available = available,
            reason = reason,
        })
    end

    -- 按 rep_gain 排序（小→大）
    table.sort(result, function(a, b) return a.cfg.rep_gain < b.cfg.rep_gain end)
    return result
end

--- 执行声誉恢复行动
---@param state table
---@param actionId string
---@param onDone function|nil
---@return boolean success, string|nil message
function Actions.ExecuteReputationAction(state, actionId, onDone)
    local BR = Balance.REPUTATION
    local cfg = BR.actions and BR.actions[actionId]
    if not cfg then return false, "未知行动" end

    -- 前置检查
    local totalAP = (state.ap and state.ap.current or 0) + (state.ap and state.ap.temp or 0)
    if totalAP < cfg.ap_cost then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return false, "行动点不足"
    end
    if state.cash < cfg.cash_cost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return false, "资金不足"
    end

    -- 冷却检查
    local cooldowns = state.rep_action_cooldowns or {}
    local currentTurn = (state.year or 1878) * 4 + (state.quarter or 1)
    if cfg.cooldown > 0 then
        local lastUsed = cooldowns[actionId] or 0
        if lastUsed + cfg.cooldown > currentTurn then
            UI.Toast.Show("行动冷却中", { variant = "warning", duration = 1.5 })
            return false, "冷却中"
        end
    end

    -- 声誉已满
    if (state.reputation or 0) >= BR.max then
        UI.Toast.Show("声誉已达上限", { variant = "warning", duration = 1.5 })
        return false, "声誉已满"
    end

    -- 扣 AP
    if not GameState.SpendAP(state, cfg.ap_cost) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return false, "行动点不足"
    end

    -- 扣资金
    state.cash = state.cash - cfg.cash_cost

    -- 恢复声誉
    local oldRep = state.reputation or 0
    GameState.ModifyReputation(state, cfg.rep_gain)
    local newRep = state.reputation or 0
    local actualGain = newRep - oldRep

    -- 记录冷却
    if cfg.cooldown > 0 then
        if not state.rep_action_cooldowns then state.rep_action_cooldowns = {} end
        state.rep_action_cooldowns[actionId] = currentTurn
    end

    -- 日志 & 提示
    GameState.AddLog(state, string.format(
        "%s %s：花费 %d 克朗，声誉 %+d（%d → %d）",
        cfg.icon, cfg.label, cfg.cash_cost, actualGain, oldRep, newRep))
    UI.Toast.Show(string.format("%s 声誉 %+d", cfg.icon, actualGain),
        { variant = "success", duration = 1.5 })

    if onDone then onDone() end
    return true, string.format("声誉 %+d", actualGain)
end

return Actions
