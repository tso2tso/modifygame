-- ============================================================================
-- 科技研发系统
-- ============================================================================

local TechData = require("data.tech_data")
local GameState = require("game_state")
local Balance = require("data.balance")

local Tech = {}

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
    if tech.requires and not state.tech.researched[tech.requires] then
        local req = TechData.GetById(tech.requires)
        return false, "需要先研发：" .. (req and req.name or tech.requires)
    end
    if state.cash < tech.cost then
        return false, "资金不足"
    end
    if not GameState.SpendAP(state, Balance.TECH.base_research_ap) then
        return false, "行动点不足（需要 " .. Balance.TECH.base_research_ap .. " AP）"
    end
    state.cash = state.cash - tech.cost
    -- 科技顾问加成：减少研发周期
    local bonus = GameState.GetPositionBonus(state, "tech_advisor")
    local total = math.max(1, math.floor(tech.turns * (1 - bonus * 0.5)))
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

--- 完成并应用科技效果
---@param state table
---@param techId string
function Tech.Complete(state, techId)
    local tech = TechData.GetById(techId)
    if not tech then return end
    state.tech.researched[techId] = true

    local eff = tech.effects or {}
    if eff.kind == "mine_output_base" then
        for _, mine in ipairs(state.mines) do
            mine.output_bonus = (mine.output_bonus or 0) + eff.value
        end
    elseif eff.kind == "security_bonus" then
        for _, r in ipairs(state.regions) do
            if r.id == "mine_district" then
                r.security = math.min(5, r.security + eff.value)
            end
        end
    elseif eff.kind == "tax_reduction" then
        -- 永久减税修正
        GameState.AddModifier(state, "tech_" .. techId, "tax_rate", eff.value, 0)
    elseif eff.kind == "ap_bonus" then
        -- ap.max 由 CalcMaxAP 统一计算（含科技加成），此处只需刷新
        state.ap.max = GameState.CalcMaxAP(state)
        -- 当季立即获得可用 AP
        state.ap.current = state.ap.current + eff.value
    elseif eff.kind == "equipment_up" then
        state.military.equipment = math.min(5, state.military.equipment + eff.value)
    elseif eff.kind == "supply_reduction" then
        -- 简单做法：降低武装工资以模拟补给节省
        state.military.wage = math.max(6, state.military.wage - 1)
    elseif eff.kind == "finance_network" then
        -- 降低补给成本 20%（通过减少 supply_cost 实现）
        state.finance_supply_discount = 0.20
        -- 每季被动收入 +80
        state.finance_passive_income = 80
    elseif eff.kind == "stock_boost" and eff.stock_id then
        for _, s in ipairs(state.stocks or {}) do
            if s.id == eff.stock_id then
                s.mu = s.mu + eff.value
            end
        end
    elseif eff.kind == "influence_gain" then
        state.passive_influence = (state.passive_influence or 0) + eff.value
    end

    GameState.AddLog(state, string.format("✓ 科技完成：%s", tech.name))
end

--- 可立即研发的科技清单（满足前置 / 未研发 / 未进行中）
---@param state table
---@return table[]
function Tech.GetAvailable(state)
    state.tech = state.tech or { researched = {} }
    local avail = {}
    for _, t in ipairs(TechData.GetAll()) do
        if not state.tech.researched[t.id]
            and (not state.tech.in_progress or state.tech.in_progress.id ~= t.id) then
            if (not t.requires) or state.tech.researched[t.requires] then
                table.insert(avail, t)
            end
        end
    end
    return avail
end

return Tech
