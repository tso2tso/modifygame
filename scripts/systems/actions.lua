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
        * (1 - GameState.GetInfluenceRecruitDiscount(state))
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

return Actions
