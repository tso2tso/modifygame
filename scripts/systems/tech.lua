-- ============================================================================
-- 科技研发系统（扩展版 — 支持分叉互斥 + 管道式前置）
-- requires 支持 "a|b" 语法：只要 a 或 b 其中之一已研发即可
-- excludes: 互斥科技id，若对方已研发则本项不可研发
-- ============================================================================

local TechData = require("data.tech_data")
local GameState = require("game_state")
local Balance = require("data.balance")

local Tech = {}

--- 检查前置科技是否满足（支持 "a|b" 管道语法）
---@param requires string|nil
---@param researched table
---@return boolean
local function checkRequires(requires, researched)
    if not requires then return true end
    -- 管道语法: "a|b" 表示 a 或 b 任一已研发即可
    if requires:find("|") then
        for part in requires:gmatch("[^|]+") do
            if researched[part] then return true end
        end
        return false
    end
    -- 普通单一前置
    return researched[requires] == true
end

--- 检查互斥科技是否阻止研发
---@param excludes string|nil
---@param researched table
---@return boolean blocked
local function checkExcludes(excludes, researched)
    if not excludes then return false end
    return researched[excludes] == true
end

--- 获取前置科技名称列表（用于提示信息）
---@param requires string|nil
---@return string
local function getRequiresNames(requires)
    if not requires then return "" end
    local names = {}
    for part in requires:gmatch("[^|]+") do
        local t = TechData.GetById(part)
        table.insert(names, t and t.name or part)
    end
    return table.concat(names, " 或 ")
end

--- 开始研发一项科技
---@param state table
---@param techId string
---@return boolean ok, string msg
function Tech.Start(state, techId)
    state.tech = state.tech or { researched = {}, in_progress = nil }

    if state.tech.in_progress then
        return false, "已有科技研发中"
    end
    if state.tech.researched[techId] then
        return false, "该科技已研发"
    end
    local tech = TechData.GetById(techId)
    if not tech then return false, "科技不存在" end
    local researched = state.tech.researched or {}
    if not checkRequires(tech.requires, researched) then
        return false, "需要先研发：" .. getRequiresNames(tech.requires)
    end
    if checkExcludes(tech.excludes, researched) then
        local exTech = TechData.GetById(tech.excludes)
        return false, "与已研发的[" .. (exTech and exTech.name or tech.excludes) .. "]互斥"
    end
    if state.cash < tech.cost then
        return false, "资金不足"
    end
    if not GameState.SpendAP(state, Balance.TECH.base_research_ap) then
        return false, "行动点不足（需要 " .. Balance.TECH.base_research_ap .. " AP）"
    end
    state.cash = state.cash - tech.cost

    -- 基础研发周期
    local total = tech.turns

    -- 科技顾问加成：减少研发周期
    local bonus = GameState.GetPositionBonus(state, "tech_advisor")
    total = math.max(1, math.floor(total * (1 - bonus * 0.5)))

    -- 影响力里程碑加成
    if GameState.HasInfluenceThreshold(state, 200) then
        total = math.max(1, total - 1)
    end

    -- 科技加成：research_speed 缩短研发
    local speedBonus = state.research_speed_bonus or 0
    if speedBonus > 0 then
        total = math.max(1, math.floor(total * (1 - speedBonus)))
    end

    -- 科技奖励点数
    if state.tech.bonus_points and state.tech.bonus_points > 0 then
        local used = math.min(state.tech.bonus_points, total - 1)
        total = total - used
        state.tech.bonus_points = state.tech.bonus_points - used
    end

    state.tech.in_progress = { id = techId, progress = 0, total = total }
    GameState.AddLog(state, string.format("[科技] 启动：%s（预计 %d 季）", tech.name, total))
    return true, "启动研发：" .. tech.name
end

--- 每季推进（由 TurnEngine 调用）
---@param state table
---@param report table
function Tech.Tick(state, report)
    if not state.tech or not state.tech.in_progress then return end
    local ip = state.tech.in_progress
    ip.progress = ip.progress + 1
    -- 科技顾问加成：偶尔额外 +1 进度
    local bonus = GameState.GetPositionBonus(state, "tech_advisor")
    if bonus > 0 and math.random() < bonus then
        ip.progress = ip.progress + 1
    end
    if ip.progress >= ip.total then
        Tech.Complete(state, ip.id)
        state.tech.in_progress = nil
        report.tech_completed = ip.id
    end
end

--- 应用单个效果
---@param state table
---@param eff table { kind, value, ... }
---@param techId string
local function applyEffect(state, eff, techId)
    if eff.kind == "mine_output_base" then
        for _, mine in ipairs(state.mines) do
            mine.output_bonus = (mine.output_bonus or 0) + eff.value
        end

    elseif eff.kind == "mine_output_mult" then
        state.mine_output_mult_bonus = (state.mine_output_mult_bonus or 0) + eff.value

    elseif eff.kind == "security_bonus" then
        for _, r in ipairs(state.regions) do
            if r.id == "mine_district" then
                r.security = math.min(5, r.security + eff.value)
            end
        end

    elseif eff.kind == "accident_reduction" then
        state.accident_rate_mod = (state.accident_rate_mod or 0) + eff.value

    elseif eff.kind == "worker_efficiency" then
        state.worker_efficiency_bonus = (state.worker_efficiency_bonus or 0) + eff.value

    elseif eff.kind == "tax_reduction" then
        GameState.AddModifier(state, "tech_" .. techId, "tax_rate", eff.value, 0)

    elseif eff.kind == "ap_bonus" then
        state.ap.max = GameState.CalcMaxAP(state)
        state.ap.current = state.ap.current + eff.value

    elseif eff.kind == "equipment_up" then
        state.military.equipment = math.min(5, state.military.equipment + eff.value)

    elseif eff.kind == "supply_reduction" then
        state.military.wage = math.max(6, state.military.wage - 1)

    elseif eff.kind == "finance_network" then
        state.finance_supply_discount = 0.20
        state.finance_passive_income = 80

    elseif eff.kind == "stock_boost_all" then
        for _, s in ipairs(state.stocks or {}) do
            s.mu = s.mu + (eff.value or 0.02)
        end

    elseif eff.kind == "influence_gain" then
        state.passive_influence = (state.passive_influence or 0) + eff.value

    elseif eff.kind == "morale_bonus" then
        state.morale = (state.morale or 50) + eff.value

    elseif eff.kind == "guard_power_bonus" then
        state.guard_power_tech_bonus = (state.guard_power_tech_bonus or 0) + eff.value

    elseif eff.kind == "research_speed" then
        state.research_speed_bonus = (state.research_speed_bonus or 0) + eff.value

    elseif eff.kind == "trade_income" then
        state.trade_passive_income = (state.trade_passive_income or 0) + eff.value

    elseif eff.kind == "gold_price_bonus" then
        state.gold_price_bonus = (state.gold_price_bonus or 0) + eff.value

    elseif eff.kind == "hire_cost_reduction" then
        state.hire_cost_discount = (state.hire_cost_discount or 0) + eff.value
    end
end

--- 完成并应用科技效果
---@param state table
---@param techId string
function Tech.Complete(state, techId)
    local tech = TechData.GetById(techId)
    if not tech then return end
    state.tech.researched[techId] = true

    local effects = tech.effects or {}
    for _, eff in ipairs(effects) do
        applyEffect(state, eff, techId)
    end

    GameState.AddLog(state, string.format("[科技] 完成：%s", tech.name))
end

--- 可立即研发的科技清单（满足前置 / 未被互斥 / 未研发 / 未进行中）
---@param state table
---@return table[]
function Tech.GetAvailable(state)
    state.tech = state.tech or { researched = {} }
    local researched = state.tech.researched or {}
    local avail = {}
    for _, t in ipairs(TechData.GetAll()) do
        if not researched[t.id]
            and (not state.tech.in_progress or state.tech.in_progress.id ~= t.id)
            and checkRequires(t.requires, researched)
            and not checkExcludes(t.excludes, researched) then
            table.insert(avail, t)
        end
    end
    return avail
end

return Tech
