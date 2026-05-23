-- ============================================================================
-- 商业远征系统：多回合市场渗透 + 据点建立决策
-- 前置：称号"商业大亨"解锁后激活 (unlocked_features["venture"])
-- 设计思路：经济版远征，用金钱投资替代军事征服
-- ============================================================================

local Balance = require("data.balance")
local GameState = require("game_state")
local EuropeData = require("data.europe_data")
local TradeRoutesData = require("data.trade_routes_data")

local BV = Balance.VENTURE

local Venture = {}

-- ============================================================================
-- 门控检查
-- ============================================================================

--- 是否已解锁商业远征功能
---@param state table
---@return boolean
function Venture.CanDoVenture(state)
    return state.unlocked_features and state.unlocked_features["venture"] == true
end

-- ============================================================================
-- 市场壁垒系统（类似远征HP）
-- ============================================================================

--- 初始化所有国家的市场壁垒（在"商业大亨"解锁时调用一次）
---@param state table
function Venture.InitMarketBarriers(state)
    for id, country in pairs(state.europe) do
        if not country.market_barrier then
            local base = country.stability * BV.barrier_per_stability
            -- 大国壁垒加成
            if country.tier == "major" then
                base = math.floor(base * BV.major_barrier_bonus)
            elseif country.tier == "neutral" then
                base = math.floor(base * BV.neutral_barrier_bonus)
            end
            country.market_barrier = base
            country.max_market_barrier = base
        end
    end
end

--- 确保市场壁垒已初始化（幂等）
---@param state table
local function EnsureBarrierInit(state)
    for _, country in pairs(state.europe) do
        if not country.market_barrier then
            Venture.InitMarketBarriers(state)
            return
        end
        break
    end
end

--- 每季市场壁垒恢复（无活跃渗透的国家缓慢恢复壁垒）
---@param state table
function Venture.TickMarketBarriers(state)
    EnsureBarrierInit(state)
    local activeVentures = state.ventures.active or {}

    for id, country in pairs(state.europe) do
        -- 跳过有活跃渗透的国家（活跃期间壁垒不恢复）
        if activeVentures[id] then
            goto continue_barrier
        end

        -- 跳过已有商业据点的国家（据点已建立，壁垒保持为0）
        if (state.ventures.commercial_posts or {})[id] then
            goto continue_barrier
        end

        -- 壁垒恢复
        if country.market_barrier and country.max_market_barrier
            and country.market_barrier < country.max_market_barrier then
            local regen = math.floor(country.stability * BV.barrier_regen_ratio)
            regen = math.max(1, regen)
            country.market_barrier = math.min(country.max_market_barrier,
                country.market_barrier + regen)
        end

        ::continue_barrier::
    end
end

-- ============================================================================
-- 难度系数
-- ============================================================================

--- 根据已建立据点数量获取难度系数
---@param state table
---@return number
function Venture.GetDifficultyMod(state)
    local postCount = 0
    for _ in pairs(state.ventures.commercial_posts or {}) do
        postCount = postCount + 1
    end
    for _, tier in ipairs(BV.difficulty_tiers) do
        if postCount <= tier.max_count then
            return tier.mod
        end
    end
    return 1.50
end

-- ============================================================================
-- 渗透力计算（每回合）
-- ============================================================================

--- 计算商业远征对目标国家的每回合渗透值
---@param state table
---@param record table 活跃渗透记录
---@return number penetration
function Venture.CalcPenetration(state, record)
    EnsureBarrierInit(state)

    -- 基础渗透
    local base = BV.base_penetration_per_turn

    -- 投资等级加成
    local level = record.investment_level or 1
    local levelDef = BV.investment_levels[level]
    if levelDef then
        base = base * levelDef.mult
    end

    -- 策略加成
    local stratDef = BV.strategies[record.strategy_id or "normal"]
    if stratDef then
        base = base * stratDef.penetration_mult
    end

    -- ── 加成叠加 ──
    local totalBonus = 0

    -- 距离惩罚（从贸易路线获取距离）
    local route = TradeRoutesData.GetRouteForBuyer(record.power_id)
    if route then
        local dist = route.distance or 1
        local penalty = BV.distance_penalty[dist] or 0
        totalBonus = totalBonus - penalty
    end

    -- 远征→商业耦合：已被军事占领的国家壁垒减半（在InitMarketBarriers已处理，
    -- 这里额外给渗透加成）
    local isOccupied = false
    for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
        if occ.country_id == record.power_id then
            isOccupied = true
            break
        end
    end
    if isOccupied then
        totalBonus = totalBonus + (1 - BV.occupied_barrier_mult)  -- +50%
    end

    -- 贸易路线加成：已开通贸易路线 +15%
    if route then
        local routeUnlocked = route.unlocked
        if not routeUnlocked and state.trade and state.trade.route_unlocks then
            routeUnlocked = state.trade.route_unlocks[route.id] or false
        end
        if routeUnlocked then
            totalBonus = totalBonus + BV.trade_route_bonus
        end
    end

    -- 声誉加成：每10点正声誉 +5%，上限25%
    local rep = state.reputation or 0
    if rep > 0 then
        local repBonus = math.floor(rep / 10) * BV.reputation_bonus_per_10
        repBonus = math.min(repBonus, BV.reputation_bonus_cap)
        totalBonus = totalBonus + repBonus
    end

    -- 称号modifier加成
    local ventureBonus = GameState.GetModifierValue(state, "venture_penetration_bonus")
    totalBonus = totalBonus + ventureBonus

    -- 加法叠加上限60%
    totalBonus = math.min(totalBonus, 0.60)
    base = base * (1 + totalBonus)

    -- 难度系数
    local diffMod = Venture.GetDifficultyMod(state)
    base = base / diffMod

    return math.max(1, math.floor(base))
end

--- 预估剩余回合数（UI展示用）
---@param state table
---@param powerId string 目标国家ID
---@param strategyId string|nil
---@param investmentLevel number|nil
---@return number estimatedTurns
function Venture.EstimateTurns(state, powerId, strategyId, investmentLevel)
    EnsureBarrierInit(state)
    local country = state.europe[powerId]
    if not country then return 999 end

    local record = (state.ventures.active or {})[powerId]
    local pen
    if record then
        pen = Venture.CalcPenetration(state, record)
    else
        -- 预估模式：创建虚拟记录
        local virtualRecord = {
            power_id = powerId,
            strategy_id = strategyId or "normal",
            investment_level = investmentLevel or 1,
        }
        pen = Venture.CalcPenetration(state, virtualRecord)
    end

    if pen <= 0 then return 999 end
    local remainingBarrier = country.market_barrier or country.max_market_barrier or 1
    return math.ceil(remainingBarrier / pen)
end

-- ============================================================================
-- 可渗透目标
-- ============================================================================

--- 获取可进行商业远征的目标列表
--- 条件：有已开通的贸易路线、无活跃渗透、无已建据点
---@param state table
---@return table[] targets
function Venture.GetValidTargets(state)
    EnsureBarrierInit(state)
    local targets = {}

    -- 获取所有已开通的贸易路线
    local unlockedRoutes = TradeRoutesData.GetUnlockedRoutes(state)

    for _, route in ipairs(unlockedRoutes) do
        local powerId = route.buyer_power_id
        local country = state.europe[powerId]
        if not country then goto continue_target end

        -- 排除已有活跃渗透的
        if (state.ventures.active or {})[powerId] then
            goto continue_target
        end

        -- 排除已建立据点的
        if (state.ventures.commercial_posts or {})[powerId] then
            goto continue_target
        end

        -- 排除待决策队列中的
        local inDecision = false
        for _, aw in ipairs(state.ventures.awaiting_decision or {}) do
            if aw.power_id == powerId then
                inDecision = true
                break
            end
        end
        if inDecision then goto continue_target end

        table.insert(targets, {
            power_id = powerId,
            route_id = route.id,
            city = route.dest_city,
            label = country.label,
            tier = country.tier,
            distance = route.distance,
            market_barrier = country.market_barrier or country.max_market_barrier,
            max_market_barrier = country.max_market_barrier,
        })

        ::continue_target::
    end

    return targets
end

-- ============================================================================
-- 策略检查
-- ============================================================================

--- 检查某个策略是否可用
---@param state table
---@param strategyId string
---@return boolean available
---@return string|nil reason
function Venture.IsStrategyAvailable(state, strategyId)
    local stratDef = BV.strategies[strategyId]
    if not stratDef then
        return false, "策略不存在"
    end

    if not stratDef.requires then
        return true, nil
    end

    local req = stratDef.requires
    if req.type == "reputation" then
        local rep = state.reputation or 0
        if rep < req.min then
            return false, string.format("需要声誉 ≥ %d（当前 %d）", req.min, rep)
        end
    elseif req.type == "tech" then
        if not state.tech or not state.tech.researched or not state.tech.researched[req.tech_id] then
            return false, string.format("需要研究科技「%s」", req.tech_id)
        end
    end

    return true, nil
end

--- 检查某个据点类型是否可用
---@param state table
---@param establishmentType string
---@return boolean available
---@return string|nil reason
function Venture.IsEstablishmentAvailable(state, establishmentType)
    local estDef = BV.establishments[establishmentType]
    if not estDef then
        return false, "据点类型不存在"
    end

    if not estDef.requires then
        return true, nil
    end

    local req = estDef.requires
    if req.type == "tech" then
        if not state.tech or not state.tech.researched or not state.tech.researched[req.tech_id] then
            return false, string.format("需要研究科技「%s」", req.tech_id)
        end
    end

    return true, nil
end

-- ============================================================================
-- 商业远征行动：发起 / 调整 / 撤出
-- ============================================================================

--- 发起商业远征
---@param state table
---@param powerId string 目标国家ID（buyer_power_id）
---@param strategyId string 策略ID
---@param investmentLevel number 投资等级（1-3）
---@return boolean ok
---@return string msg
function Venture.LaunchVenture(state, powerId, strategyId, investmentLevel)
    if not Venture.CanDoVenture(state) then
        return false, "需要解锁[商业大亨]称号"
    end

    local country = state.europe[powerId]
    if not country then return false, "目标国家不存在" end

    -- 并发数检查
    local activeCount = 0
    for _ in pairs(state.ventures.active or {}) do
        activeCount = activeCount + 1
    end
    if activeCount >= (BV.max_concurrent_ventures or 2) then
        return false, string.format("同时进行的商业远征已达上限（%d）", BV.max_concurrent_ventures or 2)
    end

    -- 检查不在活跃渗透中
    if (state.ventures.active or {})[powerId] then
        return false, "已有对该国的活跃渗透"
    end

    -- 检查无已建据点
    if (state.ventures.commercial_posts or {})[powerId] then
        return false, "已在该国建立商业据点"
    end

    -- 检查可达性（需要已开通贸易路线）
    local route = TradeRoutesData.GetRouteForBuyer(powerId)
    if not route then
        return false, "该国没有贸易路线"
    end
    local routeUnlocked = route.unlocked
    if not routeUnlocked and state.trade and state.trade.route_unlocks then
        routeUnlocked = state.trade.route_unlocks[route.id] or false
    end
    if not routeUnlocked then
        return false, "贸易路线未开通"
    end

    -- 检查策略可用性
    strategyId = strategyId or "normal"
    local stratAvail, stratReason = Venture.IsStrategyAvailable(state, strategyId)
    if not stratAvail then
        return false, stratReason
    end

    -- 投资等级验证
    investmentLevel = investmentLevel or 1
    if investmentLevel < 1 or investmentLevel > #BV.investment_levels then
        return false, "无效的投资等级"
    end

    -- 制裁检查
    if state.ventures.under_trade_sanction then
        return false, string.format("贸易制裁中，剩余 %d 季度", state.ventures.trade_sanction_remaining or 0)
    end

    -- AP检查
    local apCost = BV.venture_ap_cost
    local totalAP = (state.ap.current or 0) + (state.ap.temp or 0)
    if totalAP < apCost then
        return false, string.format("行动点不足（需要 %d AP）", apCost)
    end

    -- 首次投资费用
    local levelDef = BV.investment_levels[investmentLevel]
    local inflation = GameState.GetInflationFactor(state)
    local cashCost = math.floor(BV.base_investment_cost * levelDef.cost_mult * inflation)

    -- 策略费用加成
    local stratDef = BV.strategies[strategyId]
    cashCost = math.floor(cashCost * stratDef.cost_mult)

    if state.cash < cashCost then
        return false, string.format("现金不足（需要 %d 克朗）", cashCost)
    end

    EnsureBarrierInit(state)

    -- 消耗资源
    GameState.SpendAP(state, apCost)
    state.cash = state.cash - cashCost

    -- 声誉代价
    if stratDef.rep_cost and stratDef.rep_cost ~= 0 then
        state.reputation = (state.reputation or 0) + stratDef.rep_cost
    end

    -- 创建渗透记录
    state.ventures.active = state.ventures.active or {}
    state.ventures.active[powerId] = {
        power_id = powerId,
        route_id = route.id,
        city = route.dest_city,
        strategy_id = strategyId,
        investment_level = investmentLevel,
        total_invested = cashCost,
        started_turn = state.turn_count or 0,
        turns_active = 0,
    }

    -- 市场紧张度
    state.ventures.market_tension = (state.ventures.market_tension or 0)
        + BV.tension_per_venture
    -- 策略额外紧张度
    state.ventures.market_tension = state.ventures.market_tension
        + (stratDef.tension_add or 0)

    -- 统计
    state.ventures.history = state.ventures.history or {}
    state.ventures.history.ventures_launched =
        (state.ventures.history.ventures_launched or 0) + 1

    local msg = string.format(
        "📦 对%s（%s）发起商业渗透！策略：%s，投资等级：%s，花费 %d 克朗",
        country.label, route.dest_city,
        stratDef.label or strategyId,
        levelDef.label or tostring(investmentLevel),
        cashCost)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 调整投资策略（进行中切换策略）
---@param state table
---@param powerId string
---@param newStrategyId string
---@return boolean ok
---@return string msg
function Venture.ChangeStrategy(state, powerId, newStrategyId)
    local record = (state.ventures.active or {})[powerId]
    if not record then return false, "没有对该国的活跃渗透" end

    if record.strategy_id == newStrategyId then
        return false, "已是此策略"
    end

    local stratAvail, stratReason = Venture.IsStrategyAvailable(state, newStrategyId)
    if not stratAvail then
        return false, stratReason
    end

    local apCost = BV.reinforce_ap_cost
    if (state.ap.current or 0) + (state.ap.temp or 0) < apCost then
        return false, string.format("行动点不足（需要 %d AP）", apCost)
    end

    GameState.SpendAP(state, apCost)

    local oldStrat = BV.strategies[record.strategy_id] or {}
    local newStrat = BV.strategies[newStrategyId] or {}

    record.strategy_id = newStrategyId

    -- 声誉代价
    if newStrat.rep_cost and newStrat.rep_cost ~= 0 then
        state.reputation = (state.reputation or 0) + newStrat.rep_cost
    end

    -- 紧张度变化
    local tensionDiff = (newStrat.tension_add or 0) - (oldStrat.tension_add or 0)
    if tensionDiff > 0 then
        state.ventures.market_tension = (state.ventures.market_tension or 0) + tensionDiff
    end

    local country = state.europe[powerId]
    local label = country and country.label or powerId
    local msg = string.format("📋 %s渗透策略调整为：%s",
        label, newStrat.label or newStrategyId)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 调整投资等级
---@param state table
---@param powerId string
---@param newLevel number
---@return boolean ok
---@return string msg
function Venture.ChangeInvestment(state, powerId, newLevel)
    local record = (state.ventures.active or {})[powerId]
    if not record then return false, "没有对该国的活跃渗透" end

    if newLevel < 1 or newLevel > #BV.investment_levels then
        return false, "无效的投资等级"
    end

    if record.investment_level == newLevel then
        return false, "已是此投资等级"
    end

    local apCost = BV.reinforce_ap_cost
    if (state.ap.current or 0) + (state.ap.temp or 0) < apCost then
        return false, string.format("行动点不足（需要 %d AP）", apCost)
    end

    GameState.SpendAP(state, apCost)
    record.investment_level = newLevel

    local levelDef = BV.investment_levels[newLevel]
    local country = state.europe[powerId]
    local label = country and country.label or powerId
    local msg = string.format("📊 %s投资等级调整为：%s",
        label, levelDef.label or tostring(newLevel))
    GameState.AddLog(state, msg)
    return true, msg
end

--- 撤出商业渗透
---@param state table
---@param powerId string
---@return boolean ok
---@return string msg
function Venture.WithdrawVenture(state, powerId)
    local record = (state.ventures.active or {})[powerId]
    if not record then return false, "没有对该国的活跃渗透" end

    local apCost = BV.withdraw_ap_cost
    if (state.ap.current or 0) + (state.ap.temp or 0) < apCost then
        return false, string.format("行动点不足（需要 %d AP）", apCost)
    end

    GameState.SpendAP(state, apCost)

    -- 移除活跃渗透
    state.ventures.active[powerId] = nil

    local country = state.europe[powerId]
    local label = country and country.label or powerId
    local msg = string.format("🏳 撤出对%s的商业渗透（累计投资 %d 克朗）",
        label, record.total_invested or 0)
    GameState.AddLog(state, msg)
    return true, msg
end

-- ============================================================================
-- 回合推进：活跃渗透削减壁垒
-- ============================================================================

--- 推进所有活跃渗透（每季调用一次）
---@param state table
---@return table[] reports { power_id, label, penetration, remaining_barrier, completed }
function Venture.TickActiveVentures(state)
    EnsureBarrierInit(state)
    local reports = {}
    local completedIds = {}

    for powerId, record in pairs(state.ventures.active or {}) do
        local country = state.europe[powerId]
        if not country then goto continue_tick end

        -- 每回合投资费用扣除
        local levelDef = BV.investment_levels[record.investment_level or 1]
        local stratDef = BV.strategies[record.strategy_id or "normal"]
        local inflation = GameState.GetInflationFactor(state)
        local turnCost = math.floor(
            BV.base_investment_cost
            * (levelDef and levelDef.cost_mult or 1.0)
            * (stratDef and stratDef.cost_mult or 1.0)
            * inflation)

        -- 如果现金不足，自动降低投资等级或暂停
        if state.cash < turnCost then
            -- 尝试降级
            local downgraded = false
            for lvl = (record.investment_level or 1) - 1, 1, -1 do
                local lowerDef = BV.investment_levels[lvl]
                local lowerCost = math.floor(
                    BV.base_investment_cost
                    * lowerDef.cost_mult
                    * (stratDef and stratDef.cost_mult or 1.0)
                    * inflation)
                if state.cash >= lowerCost then
                    record.investment_level = lvl
                    turnCost = lowerCost
                    downgraded = true
                    GameState.AddLog(state, string.format(
                        "⚠ %s渗透因资金不足自动降至%s",
                        country.label, lowerDef.label))
                    break
                end
            end
            if not downgraded then
                -- 本回合暂停渗透，不扣费也不产生进度
                GameState.AddLog(state, string.format(
                    "⚠ %s渗透因资金不足暂停一季", country.label))
                table.insert(reports, {
                    power_id = powerId,
                    label = country.label,
                    city = record.city,
                    penetration = 0,
                    remaining_barrier = country.market_barrier,
                    max_barrier = country.max_market_barrier,
                    completed = false,
                    paused = true,
                })
                goto continue_tick
            end
        end

        -- A3: 腐败调查冷却倒计时（强制暂停）
        if (record._corruption_cooldown or 0) > 0 then
            record._corruption_cooldown = record._corruption_cooldown - 1
            GameState.AddLog(state, string.format(
                "🔍 %s渗透因腐败调查冷却，还需 %d 季（本季跳过）",
                country.label, record._corruption_cooldown))
            goto continue_tick
        end

        -- A3: 关税壁垒飙升 → 投资费用×1.3（一次性，触发后自动清除）
        if record._tariff_spike and record._tariff_spike > 1.0 then
            local spikeExtra = math.floor(turnCost * (record._tariff_spike - 1.0))
            if state.cash >= turnCost + spikeExtra then
                turnCost = turnCost + spikeExtra
            end
            record._tariff_spike = nil  -- 消耗一次后清除
        end

        -- 扣除投资费用
        state.cash = state.cash - turnCost
        record.total_invested = (record.total_invested or 0) + turnCost
        record.turns_active = (record.turns_active or 0) + 1

        -- A3: 危机事件抽检（20% 概率，每条活跃渗透独立）
        -- _crisis_efficiency 由上季危机A"暂不处理"设置，本季消耗后清除
        local crisisEffMod = record._crisis_efficiency or 1.0
        record._crisis_efficiency = nil  -- 消耗一次后清除

        -- 本季随机触发新危机（20%）
        if math.random() < 0.20 then
            local EventsData = require("data.events_data")
            local crisisPool = EventsData.GetVentureCrisisEvents()
            if #crisisPool > 0 then
                local evt = crisisPool[math.random(#crisisPool)]
                -- 注入 venture_id，供事件 effects.custom 读取
                local evtCopy = {}
                for k, v in pairs(evt) do evtCopy[k] = v end
                evtCopy._ctx = { venture_id = powerId }
                -- 存入待处理队列（turn_engine 会提交给事件系统）
                state.ventures._pending_crisis = state.ventures._pending_crisis or {}
                table.insert(state.ventures._pending_crisis, evtCopy)
            end
        end

        -- 计算渗透值（乘以危机效率修正 × A3策略时机窗口）
        local stratBonus, stratHint = Venture.GetStrategyBonus(state, record)
        if stratHint then
            -- 首次触发窗口时提示玩家（用 _last_strat_hint 去重）
            if record._last_strat_hint ~= stratHint then
                GameState.AddLog(state, "💡 " .. stratHint)
                record._last_strat_hint = stratHint
            end
        else
            record._last_strat_hint = nil
        end
        local penetration = math.floor(Venture.CalcPenetration(state, record) * crisisEffMod * stratBonus)

        -- 削减壁垒
        country.market_barrier = math.max(0,
            (country.market_barrier or country.max_market_barrier) - penetration)

        -- ── 策略独特效果（渗透期间） ──

        -- 倾销战：每季削弱目标国稳定度
        if stratDef and stratDef.stability_damage_per_turn and stratDef.stability_damage_per_turn > 0 then
            local oldStab = country.stability or 50
            country.stability = math.max(10, oldStab - stratDef.stability_damage_per_turn)
            if country.stability < oldStab then
                -- 稳定度降低会自动降低壁垒上限（壁垒 = stability × barrier_per_stability × tier_bonus）
                local tierBonus = country.tier == "major" and BV.major_barrier_bonus
                    or (country.tier == "neutral" and BV.neutral_barrier_bonus or 1.0)
                country.max_market_barrier = math.floor(
                    country.stability * BV.barrier_per_stability * tierBonus)
                -- 当前壁垒不超过新上限
                country.market_barrier = math.min(country.market_barrier, country.max_market_barrier)
            end
        end

        -- 常规贸易：每季额外衰减紧张度
        if stratDef and stratDef.extra_tension_decay and stratDef.extra_tension_decay > 0 then
            state.ventures.market_tension = math.max(0,
                (state.ventures.market_tension or 0) - stratDef.extra_tension_decay)
        end

        -- 检查壁垒归零
        local completed = country.market_barrier <= 0

        table.insert(reports, {
            power_id = powerId,
            label = country.label,
            city = record.city,
            penetration = penetration,
            turn_cost = turnCost,
            remaining_barrier = country.market_barrier,
            max_barrier = country.max_market_barrier,
            turns_active = record.turns_active,
            completed = completed,
        })

        if completed then
            table.insert(completedIds, powerId)
        end

        ::continue_tick::
    end

    -- 处理壁垒归零的渗透 → 进入完成判定
    for _, pid in ipairs(completedIds) do
        Venture.CompleteVenture(state, pid)
    end

    return reports
end

-- ============================================================================
-- 渗透完成判定
-- ============================================================================

--- 计算渗透完成时的成功率
---@param state table
---@param record table
---@return number successRate 0~1
function Venture.CalcSuccessRate(state, record)
    local rate = BV.completion_success_base

    -- 声誉加成
    local rep = state.reputation or 0
    if rep > 0 then
        rate = rate + rep * BV.completion_rep_weight
    elseif rep < 0 then
        rate = rate + rep * BV.completion_rep_weight  -- 负声誉减少成功率
    end

    -- 策略独特效果：成功率加成
    local stratDef = BV.strategies[record.strategy_id or "normal"]
    if stratDef and stratDef.success_rate_bonus then
        rate = rate + stratDef.success_rate_bonus
    end

    return math.max(BV.completion_success_floor,
        math.min(BV.completion_success_cap, rate))
end

--- 渗透完成：成功/失败判定
---@param state table
---@param powerId string
function Venture.CompleteVenture(state, powerId)
    local record = (state.ventures.active or {})[powerId]
    if not record then return end

    local country = state.europe[powerId]
    if not country then return end

    local successRate = Venture.CalcSuccessRate(state, record)
    local roll = math.random()
    local won = roll < successRate

    if won then
        -- 成功 → 进入待决策队列（携带策略信息，据点建立时应用独特效果）
        state.ventures.awaiting_decision = state.ventures.awaiting_decision or {}
        table.insert(state.ventures.awaiting_decision, {
            power_id = powerId,
            city = record.city,
            label = country.label,
            strategy_id = record.strategy_id or "normal",
            completed_turn = state.turn_count or 0,
            total_invested = record.total_invested or 0,
            turns_active = record.turns_active or 0,
        })

        -- 统计
        state.ventures.history.ventures_completed =
            (state.ventures.history.ventures_completed or 0) + 1

        local msg = string.format(
            "📦 商业渗透%s（%s）成功！累计投资 %d 克朗，耗时 %d 季（成功率%d%%）\n🏪 选择建立何种商业据点！",
            country.label, record.city,
            record.total_invested or 0,
            record.turns_active or 0,
            math.floor(successRate * 100))
        GameState.AddLog(state, msg)
    else
        -- 失败：壁垒部分恢复
        country.market_barrier = math.floor(
            (country.max_market_barrier or 1) * BV.fail_barrier_restore)

        -- 统计
        state.ventures.history.ventures_failed =
            (state.ventures.history.ventures_failed or 0) + 1

        local msg = string.format(
            "💥 商业渗透%s（%s）失败！累计投入 %d 克朗（%d季，成功率%d%%）\n市场壁垒恢复至%d%%",
            country.label, record.city,
            record.total_invested or 0,
            record.turns_active or 0,
            math.floor(successRate * 100),
            math.floor(BV.fail_barrier_restore * 100))
        GameState.AddLog(state, msg)
    end

    -- 移除活跃渗透记录
    state.ventures.active[powerId] = nil
end

-- ============================================================================
-- 据点建立决策（三选一）
-- ============================================================================

--- 建立商业据点
---@param state table
---@param powerId string
---@param establishmentType string "trading_post" / "joint_venture" / "monopoly"
---@return boolean ok
---@return string msg
function Venture.EstablishPost(state, powerId, establishmentType)
    if not Venture.CanDoVenture(state) then
        return false, "需要解锁[商业大亨]称号"
    end

    -- 检查是否在待决策队列
    local found = false
    local idx = 0
    local decisionRecord = nil
    for i, aw in ipairs(state.ventures.awaiting_decision or {}) do
        if aw.power_id == powerId then
            found = true
            idx = i
            decisionRecord = aw
            break
        end
    end
    if not found then return false, "该国家不在待决策队列中" end

    -- 检查据点类型可用性
    local estAvail, estReason = Venture.IsEstablishmentAvailable(state, establishmentType)
    if not estAvail then
        return false, estReason
    end

    local estDef = BV.establishments[establishmentType]
    local country = state.europe[powerId]
    if not country then return false, "目标国家不存在" end

    local isMajor = country.tier == "major"
    local income = isMajor and estDef.income_major or estDef.income_minor
    local maintenance = isMajor and estDef.maintenance_major or estDef.maintenance_minor

    -- 渗透策略独特效果
    local usedStratId = decisionRecord.strategy_id or "normal"
    local usedStrat = BV.strategies[usedStratId]

    -- 倾销战独特效果：据点收入加成
    if usedStrat and usedStrat.post_income_bonus and usedStrat.post_income_bonus > 0 then
        income = math.floor(income * (1 + usedStrat.post_income_bonus))
    end

    -- 贿赂独特效果：据点维护费折扣
    if usedStrat and usedStrat.maintenance_discount and usedStrat.maintenance_discount > 0 then
        maintenance = math.floor(maintenance * (1 - usedStrat.maintenance_discount))
    end

    -- 注意：venture_maintenance_discount 由 SettleTurn 每季动态计算，不在此处烘焙，避免双重折扣

    -- 添加到已建据点（记录策略ID用于SettleTurn的独特效果）
    state.ventures.commercial_posts = state.ventures.commercial_posts or {}
    state.ventures.commercial_posts[powerId] = {
        type = establishmentType,
        strategy_id = usedStratId,
        city = decisionRecord.city or "",
        label = country.label,
        income_per_turn = income,
        maintenance = maintenance,
        established_turn = state.turn_count or 0,
    }

    -- 壁垒清零（据点已建立）
    country.market_barrier = 0

    -- 从待决策队列移除
    table.remove(state.ventures.awaiting_decision, idx)

    -- 市场紧张度增加
    state.ventures.market_tension = (state.ventures.market_tension or 0)
        + (estDef.tension_add or 0)

    -- 外交影响
    local diploChange = estDef.diplo_penalty or 0
    -- 技术输出独特效果：改善外交关系
    if usedStrat and usedStrat.diplo_bonus then
        diploChange = diploChange + usedStrat.diplo_bonus
    end
    if diploChange ~= 0 and state.powers and state.powers[powerId] then
        local power = state.powers[powerId]
        if power.active then
            power.attitude_to_player = (power.attitude_to_player or 0) + diploChange
        end
    end

    -- 统计
    state.ventures.history.posts_established =
        (state.ventures.history.posts_established or 0) + 1

    local msg = string.format(
        "%s 在%s（%s）建立了%s！每季收入 %d，维护费 %d（净收益 %d）",
        estDef.icon or "🏪",
        country.label, decisionRecord.city or "",
        estDef.label or establishmentType,
        income, maintenance, income - maintenance)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 放弃建立据点（让目标国市场自行恢复）
---@param state table
---@param powerId string
---@return boolean ok
---@return string msg
function Venture.AbandonDecision(state, powerId)
    local found = false
    local idx = 0
    for i, aw in ipairs(state.ventures.awaiting_decision or {}) do
        if aw.power_id == powerId then
            found = true
            idx = i
            break
        end
    end
    if not found then return false, "该国家不在待决策队列中" end

    local country = state.europe[powerId]
    table.remove(state.ventures.awaiting_decision, idx)

    -- 壁垒恢复至30%
    if country then
        country.market_barrier = math.floor(
            (country.max_market_barrier or 1) * BV.fail_barrier_restore)
    end

    local label = country and country.label or powerId
    local msg = string.format("放弃在%s建立据点，该国市场壁垒将逐步恢复", label)
    GameState.AddLog(state, msg)
    return true, msg
end

--- 拆除已建据点
---@param state table
---@param powerId string
---@return boolean ok
---@return string msg
function Venture.DismantlePost(state, powerId)
    local post = (state.ventures.commercial_posts or {})[powerId]
    if not post then return false, "该国没有商业据点" end

    local country = state.europe[powerId]
    local label = country and country.label or powerId

    -- 移除据点
    state.ventures.commercial_posts[powerId] = nil

    -- 壁垒恢复至50%
    if country and country.max_market_barrier then
        country.market_barrier = math.floor(country.max_market_barrier * 0.5)
    end

    -- 紧张度减少（拆除是善意行为）
    state.ventures.market_tension = math.max(0,
        (state.ventures.market_tension or 0) - 1)

    local estDef = BV.establishments[post.type] or {}
    local msg = string.format("🔧 拆除了%s的%s", label, estDef.label or post.type)
    GameState.AddLog(state, msg)
    return true, msg
end

-- ============================================================================
-- 每季结算
-- ============================================================================

--- 每季结算：据点收入/维护 + 紧张度衰减 + 制裁检查
---@param state table
---@return table report
function Venture.SettleTurn(state)
    local report = {
        income = 0,
        maintenance = 0,
        net = 0,
        posts_lost = {},
        market_tension = state.ventures.market_tension or 0,
        under_sanction = state.ventures.under_trade_sanction or false,
    }

    -- 称号modifier：据点维护费折扣
    local maintDiscount = GameState.GetModifierValue(state, "venture_maintenance_discount")

    -- 制裁期间收入减半
    local sanctionMult = 1.0
    if state.ventures.under_trade_sanction then
        sanctionMult = BV.sanction_income_mult
    end

    -- 据点收入/维护
    local postsToKeep = {}
    local techFromPosts = 0
    for powerId, post in pairs(state.ventures.commercial_posts or {}) do
        local actualMaint = math.floor(post.maintenance * (1 - maintDiscount))
        local inflation = GameState.GetInflationFactor(state)
        local inflatedIncome = math.floor(post.income_per_turn * inflation * sanctionMult)

        if state.cash >= actualMaint then
            state.cash = state.cash + inflatedIncome - actualMaint
            report.income = report.income + inflatedIncome
            report.maintenance = report.maintenance + actualMaint
            postsToKeep[powerId] = post

            -- 技术输出独特效果：据点每季产科技点
            local postStrat = BV.strategies[post.strategy_id or ""]
            if postStrat and postStrat.post_tech_per_turn and postStrat.post_tech_per_turn > 0 then
                techFromPosts = techFromPosts + postStrat.post_tech_per_turn
            end
        else
            -- 付不起维护费，据点丢失
            table.insert(report.posts_lost, post.label or powerId)
            -- 壁垒恢复至50%
            local country = state.europe[powerId]
            if country and country.max_market_barrier then
                country.market_barrier = math.floor(country.max_market_barrier * 0.5)
            end
            GameState.AddLog(state, string.format(
                "⚠ %s的商业据点因维护费不足而关闭", post.label or powerId))
        end
    end
    state.ventures.commercial_posts = postsToKeep

    -- 技术输出据点产出科技点
    if techFromPosts > 0 then
        state.tech = state.tech or {}
        state.tech.points = (state.tech.points or 0) + techFromPosts
        report.tech_from_posts = techFromPosts
    end

    report.net = report.income - report.maintenance

    -- 统计收入
    state.ventures.history = state.ventures.history or {}
    state.ventures.history.total_venture_income =
        (state.ventures.history.total_venture_income or 0) + report.net

    -- 紧张度衰减
    state.ventures.market_tension = math.max(0,
        (state.ventures.market_tension or 0) - BV.tension_decay)

    -- 制裁处理
    if state.ventures.under_trade_sanction then
        state.ventures.trade_sanction_remaining =
            (state.ventures.trade_sanction_remaining or 0) - 1
        if state.ventures.trade_sanction_remaining <= 0 then
            state.ventures.under_trade_sanction = false
            state.ventures.trade_sanction_remaining = 0
            GameState.AddLog(state, "📜 贸易制裁已解除！")
            report.sanction_lifted = true
        end
    end

    -- 制裁触发检查
    local tension = state.ventures.market_tension or 0
    if not state.ventures.under_trade_sanction and tension >= BV.sanction_threshold then
        state.ventures.under_trade_sanction = true
        state.ventures.trade_sanction_remaining = BV.sanction_duration
        report.sanction_triggered = true

        if tension >= BV.intervention_threshold then
            GameState.AddLog(state, string.format(
                "🚫 市场紧张度过高（%.1f）！列强联合贸易抵制，商业收入减半 %d 季！",
                tension, BV.sanction_duration))
        else
            GameState.AddLog(state, string.format(
                "⚠ 市场紧张度达到警戒线（%.1f）！遭受贸易制裁，商业收入减半 %d 季",
                tension, BV.sanction_duration))
        end
    end

    report.market_tension = state.ventures.market_tension
    report.under_sanction = state.ventures.under_trade_sanction

    return report
end

-- ============================================================================
-- 股市联动
-- ============================================================================

--- 计算商业据点对东方贸易商行股票的 mu 加成
---@param state table
---@return number muBonus
function Venture.CalcStockBonus(state)
    local bonus = 0
    for _, post in pairs(state.ventures.commercial_posts or {}) do
        if post.type == "trading_post" then
            bonus = bonus + BV.stock_bonus_per_post
        elseif post.type == "joint_venture" then
            bonus = bonus + BV.stock_bonus_per_joint
        elseif post.type == "monopoly" then
            bonus = bonus + BV.stock_bonus_per_monopoly
        end
    end
    return bonus
end

-- ============================================================================
-- 查询/汇总 API（供UI使用）
-- ============================================================================

--- 获取商业远征系统摘要
---@param state table
---@return table summary
function Venture.GetSummary(state)
    local vent = state.ventures or {}

    -- 计算活跃渗透数
    local activeCount = 0
    for _ in pairs(vent.active or {}) do
        activeCount = activeCount + 1
    end

    -- 计算据点数
    local postCount = 0
    local totalIncome = 0
    local totalMaint = 0
    for _, post in pairs(vent.commercial_posts or {}) do
        postCount = postCount + 1
        totalIncome = totalIncome + (post.income_per_turn or 0)
        totalMaint = totalMaint + (post.maintenance or 0)
    end

    return {
        can_venture = Venture.CanDoVenture(state),
        active_count = activeCount,
        active_ventures = vent.active or {},
        awaiting_decision = vent.awaiting_decision or {},
        post_count = postCount,
        commercial_posts = vent.commercial_posts or {},
        total_income = totalIncome,
        total_maintenance = totalMaint,
        net_income = totalIncome - totalMaint,
        market_tension = vent.market_tension or 0,
        under_sanction = vent.under_trade_sanction or false,
        sanction_remaining = vent.trade_sanction_remaining or 0,
        sanction_threshold = BV.sanction_threshold,
        history = vent.history or {},
    }
end

--- 获取指定活跃渗透的详细信息（UI展示用）
---@param state table
---@param powerId string
---@return table|nil detail
function Venture.GetVentureDetail(state, powerId)
    local record = (state.ventures.active or {})[powerId]
    if not record then return nil end

    local country = state.europe[powerId]
    if not country then return nil end

    local penetration = Venture.CalcPenetration(state, record)
    local estimatedTurns = Venture.EstimateTurns(state, powerId)
    local levelDef = BV.investment_levels[record.investment_level or 1]
    local stratDef = BV.strategies[record.strategy_id or "normal"]

    -- 每回合费用计算
    local inflation = GameState.GetInflationFactor(state)
    local turnCost = math.floor(
        BV.base_investment_cost
        * (levelDef and levelDef.cost_mult or 1.0)
        * (stratDef and stratDef.cost_mult or 1.0)
        * inflation)

    return {
        power_id = powerId,
        label = country.label,
        city = record.city,
        strategy_id = record.strategy_id,
        strategy_label = stratDef and stratDef.label or record.strategy_id,
        strategy_icon = stratDef and stratDef.icon or "📦",
        investment_level = record.investment_level,
        investment_label = levelDef and levelDef.label or "",
        penetration_per_turn = penetration,
        turn_cost = turnCost,
        total_invested = record.total_invested or 0,
        turns_active = record.turns_active or 0,
        market_barrier = country.market_barrier or 0,
        max_market_barrier = country.max_market_barrier or 1,
        barrier_percent = math.floor(
            ((country.market_barrier or 0) / math.max(1, country.max_market_barrier or 1)) * 100),
        estimated_turns = estimatedTurns,
    }
end

--- 获取可用策略列表（标注是否可用）
---@param state table
---@return table[] strategies
function Venture.GetAvailableStrategies(state)
    local result = {}
    for sid, sDef in pairs(BV.strategies) do
        local avail, reason = Venture.IsStrategyAvailable(state, sid)
        table.insert(result, {
            id = sid,
            label = sDef.label,
            icon = sDef.icon,
            desc = sDef.desc,
            cost_mult = sDef.cost_mult,
            penetration_mult = sDef.penetration_mult,
            tension_add = sDef.tension_add,
            rep_cost = sDef.rep_cost,
            available = avail,
            unavailable_reason = reason,
        })
    end
    -- 按penetration_mult排序
    table.sort(result, function(a, b) return a.penetration_mult < b.penetration_mult end)
    return result
end

--- 获取可用据点类型列表
---@param state table
---@return table[] establishments
function Venture.GetAvailableEstablishments(state)
    local result = {}
    for eid, eDef in pairs(BV.establishments) do
        local avail, reason = Venture.IsEstablishmentAvailable(state, eid)
        table.insert(result, {
            id = eid,
            label = eDef.label,
            icon = eDef.icon,
            desc = eDef.desc,
            income_minor = eDef.income_minor,
            income_major = eDef.income_major,
            maintenance_minor = eDef.maintenance_minor,
            maintenance_major = eDef.maintenance_major,
            tension_add = eDef.tension_add,
            diplo_penalty = eDef.diplo_penalty,
            available = avail,
            unavailable_reason = reason,
        })
    end
    -- 按收入排序（低→高）
    table.sort(result, function(a, b) return a.income_minor < b.income_minor end)
    return result
end

-- ============================================================================
-- A3: 策略时机窗口奖励
-- ============================================================================

--- 计算当前策略的时机窗口加成倍率
--- - 倾销 + 壁垒<50% → ×1.25 渗透速度
--- - 技术出口 + 目标国处于战争状态 → 合作度加成×2.0
---@param state table
---@param record table  活跃渗透记录
---@return number  渗透速度倍率（默认 1.0）
---@return string|nil  窗口提示文本（nil=无窗口）
function Venture.GetStrategyBonus(state, record)
    local stratId = record.strategy_id or "normal"
    local powerId = record.power_id
    local country = state.europe[powerId]
    if not country then return 1.0, nil end

    -- 窗口一：倾销 + 壁垒降至50%以下 → 渗透速度 ×1.25
    if stratId == "dumping" then
        local maxBarrier = country.max_market_barrier or 1
        local curBarrier = country.market_barrier or maxBarrier
        if curBarrier < maxBarrier * 0.5 then
            return 1.25, string.format("壁垒已降至50%%以下，倾销效率+25%%（还有 %d 可渗透）", curBarrier)
        end
    end

    -- 窗口二：技术出口 + 目标大国处于战争状态 → 合作度加成×2.0（返回给 CalcPenetration 使用）
    if stratId == "tech_export" then
        for _, conflict in pairs(state.active_conflicts or {}) do
            if conflict.faction_a == powerId or conflict.faction_b == powerId then
                return 2.0, string.format("%s正处于战争状态，技术出口合作度加成翻倍", country.label or powerId)
            end
        end
    end

    return 1.0, nil
end

return Venture
