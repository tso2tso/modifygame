-- ============================================================================
-- 游戏状态：核心数据结构（阶段 B 完整版）
-- ============================================================================

local Config = require("config")
local Balance = require("data.balance")
local FamiliesData = require("data.families_data")
local RegionsData = require("data.regions_data")

--- 深拷贝（用于把 Balance.STOCKS 模板实例化进 state，避免共享引用）
local function deepcopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local t = {}
    for k, v in pairs(tbl) do t[k] = deepcopy(v) end
    return t
end

local BT = Balance.TIME
local BA = Balance.AP
local BS = Balance.START
local BM = Balance.MINE
local BW = Balance.WORKERS
local BMI = Balance.MILITARY

local GameState = {}

--- 创建初始游戏状态（完整版）
---@return table state
function GameState.CreateNew()
    local state = {
        -- ============================
        -- 时间
        -- ============================
        year    = BT.start_year,
        quarter = BT.start_quarter,

        -- ============================
        -- 资源
        -- ============================
        cash = BS.cash,
        gold = BS.gold,
        silver = 0,     -- 白银库存（副产品，每季可售卖）
        coal   = 0,     -- 煤炭库存（工业区开采，每季可售卖）
        gold_auto_sell = false,  -- 黄金自动出售开关（默认关闭，玩家手动在产业页出售）

        -- ============================
        -- 行动点
        -- ============================
        ap = {
            current = BA.base,
            max     = BA.base,
            temp    = 0,   -- 事件奖励的临时 AP
            bonus_used = 0, -- 本季通过 [+] 按钮购买的 AP 次数
        },

        -- ============================
        -- 通胀（累积乘数，战时显著上升）
        -- ============================
        inflation_factor = Balance.INFLATION.base_factor,

        -- ============================
        -- 股市 + 持仓（GBM 模拟）
        -- ============================
        stocks = (function()
            local list = {}
            for _, s in ipairs(Balance.STOCKS) do
                local inst = deepcopy(s)
                inst.prev_price = inst.price
                inst.change_pct = 0
                inst.history    = { inst.price }
                inst.event_mu_mods = {}
                table.insert(list, inst)
            end
            return list
        end)(),
        portfolio = {
            holdings = {},  -- { [stock_id] = { shares, avg_cost } }
        },

        -- ============================
        -- 贷款
        -- ============================
        loans = {},  -- { { id, principal, interest, remaining_turns, total_paid } }
        loan_consecutive_defaults = 0,   -- 连续违约季度数
        negative_net_worth_turns = 0,    -- 净资产为负连续季度数
        bankrupt = false,                -- 是否已破产（游戏结束条件）

        -- ============================
        -- 科技
        -- ============================
        tech = {
            researched  = {},   -- { [tech_id] = true }
            in_progress = nil,  -- { id, progress, total }
            bonus_points = 0,   -- 事件/家族特质贡献的额外点数
        },

        -- ============================
        -- 胜利进度（v2：分离累积分与即时统计）
        -- ============================
        victory = {
            economic = 0,
            military = 0,
        },
        battle_wins_total = 0,            -- 累计战斗胜利场次（用于军事胜利快照/记录）
        battle_wins_unclaimed = 0,        -- 尚未结算进军事胜利点的近期胜场
        emergency_gold_sold = false,      -- 本回合是否触发过紧急变卖黄金（快照验证用）
        culture_action_this_turn = false,  -- 本季是否执行过文化行动（Influence 衰减豁免）

        -- ============================
        -- 回合阶段
        -- ============================
        phase = "action",  -- settlement / event / action / end_turn

        -- ============================
        -- 家族
        -- ============================
        family = {
            members = FamiliesData.CreateInitialMembers(),
            training = nil,  -- 培养中的新成员 { progress, total, member_template }
        },

        -- ============================
        -- 地区
        -- ============================
        regions = RegionsData.CreateInitialRegions(),

        -- ============================
        -- 矿山
        -- ============================
        mines = {
            {
                id = "main_mine",
                name = "科瓦奇金矿",
                region_id = "mine_district",
                level = 1,
                output_bonus = 0,  -- 来自科技/岗位等额外加成
                active = true,
            },
        },

        -- ============================
        -- 工人
        -- ============================
        workers = {
            hired  = BS.workers,
            wage   = BW.base_wage,
            morale = 70,  -- 0-100
        },

        -- ============================
        -- 武装
        -- ============================
        military = {
            guards    = BS.guards,
            morale    = BMI.base_morale,
            wage      = BMI.guard_wage,
            equipment = 1,  -- 装备等级 1-5
            supply    = 20, -- 补给储备
        },

        -- ============================
        -- AI 势力
        -- ============================
        ai_factions = {
            {
                id = "local_clan",
                name = "米洛舍维奇家族",
                icon = "🏰",
                type = "local_clan",
                cash = Balance.AI.local_clan.start_cash,
                attitude = -5,   -- 对玩家态度 -100~100（初始微妙敌意）
                power = 38,      -- 势力值（起步更强）
                desc = "扎根当地百年的传统望族，控制着大片土地和人脉网络。",
            },
            {
                id = "foreign_capital",
                name = "维也纳矿业公司",
                icon = "💼",
                type = "foreign_capital",
                cash = Balance.AI.foreign_capital.start_cash,
                attitude = 5,    -- 外资初始中立偏友好
                power = 45,      -- 资本集团势力更强
                desc = "来自帝国首都的资本集团，资金雄厚但在本地根基较浅。",
            },
        },

        -- ============================
        -- 事件
        -- ============================
        event_queue = {},       -- 当前季度待处理事件
        events_fired = {},      -- 已触发事件 id 集合（防重复）
        turn_messages = {},     -- 本季动态通知 { {text, type} }
        random_cooldowns = {},  -- 随机事件冷却 { [event_id] = remaining_quarters }

        -- ============================
        -- 修正器（来自事件的持续效果）
        -- ============================
        modifiers = {},
        -- 格式: { id, target, value, remaining_turns }

        -- ============================
        -- 被动效果（科技/事件累积）
        -- ============================
        passive_influence = 0,       -- 被动地区影响力增益/季（科技"印刷宣传"等）
        regulation_pressure = 0,     -- 监管压力（事件/外交行为累积）

        -- ============================
        -- 全局状态标记
        -- ============================
        flags = {
            at_war = false,       -- 是否处于战争状态
            war_start_turn = 0,   -- 战争开始回合
        },

        -- ============================
        -- 历史日志
        -- ============================
        history_log = {},
        -- 格式: { turn, year, quarter, text }

        -- ============================
        -- 计数器
        -- ============================
        turn_count = 0,
        total_income = 0,   -- 累计总收入
        total_expense = 0,  -- 累计总支出
    }

    return state
end

-- ============================================================================
-- 时间
-- ============================================================================

--- 获取当前回合的显示文本
---@param state table
---@return string
function GameState.GetTurnText(state)
    return string.format("%d年 %s", state.year, Config.QUARTER_NAMES[state.quarter])
end

--- 推进到下一季度
---@param state table
function GameState.AdvanceQuarter(state)
    state.quarter = state.quarter + 1
    if state.quarter > 4 then
        state.quarter = 1
        state.year = state.year + 1
    end
    state.turn_count = state.turn_count + 1
    -- 重置 AP（基础 + 临时归零 + AP 购买计数归零）
    state.ap.current = state.ap.max
    state.ap.temp = 0
    state.ap.bonus_used = 0
end

--- 计算玩家地区总控制度
---@param state table
---@return number
function GameState.CalcTotalControl(state)
    local total = 0
    for _, r in ipairs(state.regions) do
        total = total + (r.control or 0)
    end
    return total
end

--- 计算玩家总影响力（所有地区 influence 之和）
---@param state table
---@return number
function GameState.CalcTotalInfluence(state)
    local total = 0
    for _, r in ipairs(state.regions) do
        total = total + (r.influence or 0)
    end
    return total
end

--- 是否达到某个总影响力阈值
---@param state table
---@param threshold number
---@return boolean
function GameState.HasInfluenceThreshold(state, threshold)
    return GameState.CalcTotalInfluence(state) >= threshold
end

--- 影响力带来的招募/雇佣折扣
---@param state table
---@return number discount 0..0.25
function GameState.GetInfluenceRecruitDiscount(state)
    if GameState.HasInfluenceThreshold(state, 70) then
        return 0.10
    end
    return 0
end

--- 经济胜利快照验证
---@param state table
---@return boolean
function GameState.CheckEconomicSnapshot(state)
    local snap = Balance.VICTORY.economic.snapshot
    local totalAssets = GameState.GetModifierValue(state, "total_assets")
    if state.cash < snap.min_cash then return false end
    if state.gold < snap.min_gold then return false end
    if GameState.CalcTotalControl(state) < snap.min_total_control then return false end
    if snap.min_total_assets and totalAssets < snap.min_total_assets then return false end
    return true
end

--- 军事胜利快照验证
---@param state table
---@return boolean
function GameState.CheckMilitarySnapshot(state)
    local snap = Balance.VICTORY.military.snapshot
    if state.military.guards < snap.min_guards then return false end
    if state.military.morale < snap.min_morale then return false end
    if GameState.CalcTotalControl(state) < snap.min_total_control then return false end
    return true
end

--- 检查游戏是否结束
---@param state table
---@return boolean
function GameState.IsGameOver(state)
    -- 破产失败
    if state.bankrupt then
        return true
    end
    if state.year > BT.end_year then
        return true
    end
    if state.year == BT.end_year and state.quarter > BT.end_quarter then
        return true
    end
    -- 经济胜利：分数达标 + 章节门控 + 快照验证
    local BVE = Balance.VICTORY.economic
    if state.victory.economic >= BVE.threshold
        and state.year >= BVE.gate_year
        and GameState.CheckEconomicSnapshot(state) then
        return true
    end
    -- 军事胜利：分数达标 + 章节门控 + 快照验证
    local BVM = Balance.VICTORY.military
    if state.victory.military >= BVM.threshold
        and state.year >= BVM.gate_year
        and GameState.CheckMilitarySnapshot(state) then
        return true
    end
    return false
end

--- 获取胜利类型（如果已胜利）
---@param state table
---@return string|nil victoryType "economic" / "military" / "timeout" / "bankrupt" / nil
function GameState.GetVictoryType(state)
    -- 破产失败
    if state.bankrupt then
        return "bankrupt"
    end
    local BVE = Balance.VICTORY.economic
    if state.victory.economic >= BVE.threshold
        and state.year >= BVE.gate_year
        and GameState.CheckEconomicSnapshot(state) then
        return "economic"
    end
    local BVM = Balance.VICTORY.military
    if state.victory.military >= BVM.threshold
        and state.year >= BVM.gate_year
        and GameState.CheckMilitarySnapshot(state) then
        return "military"
    end
    if state.year > BT.end_year or
       (state.year == BT.end_year and state.quarter > BT.end_quarter) then
        return "timeout"
    end
    return nil
end

--- 获取完整结局信息（胜利/失败/时间到）
---@param state table
---@return table|nil ending
function GameState.GetEndingInfo(state)
    local victoryType = GameState.GetVictoryType(state)
    if not victoryType then return nil end

    local BVE = Balance.VICTORY.economic
    local BVM = Balance.VICTORY.military
    local totalControl = GameState.CalcTotalControl(state)
    local totalInfluence = GameState.CalcTotalInfluence(state)
    local totalAssets = GameState.CalcTotalAssets(state)
    local totalDebt = GameState.CalcTotalDebt(state)
    local netWorth = totalAssets - totalDebt

    local ending = {
        type = victoryType,
        title = "百年家族史已书写完毕",
        subtitle = GameState.GetTurnText(state),
        description = "科瓦奇家族的账簿合上了最后一页。",
        resultLabel = "结局",
        variant = "info",
        icon = "⚜️",
        stats = {
            { label = "现金", value = Config.FormatNumber(state.cash or 0) },
            { label = "黄金库存", value = tostring(state.gold or 0) },
            { label = "净资产", value = Config.FormatNumber(netWorth) },
            { label = "地区控制", value = tostring(totalControl) },
            { label = "地区影响力", value = tostring(totalInfluence) },
            { label = "度过季度", value = tostring(state.turn_count or 0) },
        },
        progress = {
            economic = {
                label = "经济胜利",
                value = state.victory.economic or 0,
                threshold = BVE.threshold,
            },
            military = {
                label = "军事胜利",
                value = state.victory.military or 0,
                threshold = BVM.threshold,
            },
        },
    }

    if victoryType == "economic" then
        ending.title = "经济胜利：黄金帝国"
        ending.resultLabel = "胜利"
        ending.variant = "success"
        ending.icon = "💰"
        ending.description = "家族以黄金、资本与地区控制建立了跨越时代的财富秩序。"
    elseif victoryType == "military" then
        ending.title = "军事胜利：钢铁执政者"
        ending.resultLabel = "胜利"
        ending.variant = "success"
        ending.icon = "🛡️"
        ending.description = "武装力量、士气与领地控制支撑起家族不可撼动的统治。"
    elseif victoryType == "bankrupt" then
        ending.title = "失败：家族破产"
        ending.resultLabel = "失败"
        ending.variant = "failure"
        ending.icon = "💀"
        if (state.loan_consecutive_defaults or 0) >= (Balance.LOAN.bankruptcy.consecutive_defaults or 4) then
            ending.description = string.format(
                "连续 %d 季贷款违约——黄金被强制变卖、矿山被逐级降级，仍无力偿还。债权人接管了家族全部资产。",
                state.loan_consecutive_defaults or 0)
        elseif (state.negative_net_worth_turns or 0) >= (Balance.LOAN.bankruptcy.negative_net_worth_turns or 4) then
            ending.description = string.format("净资产连续 %d 季为负，黄金王朝轰然倒塌。",
                state.negative_net_worth_turns or 0)
        else
            ending.description = "债务与现金流危机压垮了家族的最后防线。"
        end
    elseif victoryType == "timeout" then
        ending.title = "失败：百年落幕"
        ending.resultLabel = "失败"
        ending.variant = "failure"
        ending.icon = "⌛"
        ending.description = string.format("时间推进至 %d 年后，家族未能完成经济或军事胜利目标。",
            Balance.TIME.end_year)
    end

    return ending
end

-- ============================================================================
-- 行动点
-- ============================================================================

--- 计算当季 AP 上限（含加成和惩罚）
---@param state table
---@return number maxAP
function GameState.CalcMaxAP(state)
    local ap = BA.base

    -- 惩罚
    if state.flags.at_war then
        ap = ap + BA.war_penalty
    end

    -- 治安极差惩罚：检查矿区安全
    for _, r in ipairs(state.regions) do
        if r.id == "mine_district" and r.security <= 1 then
            ap = ap + BA.low_security_penalty
            break
        end
    end

    -- 空缺岗位惩罚
    local vacantCount = 0
    for _, pos in ipairs(Config.POSITIONS) do
        local filled = false
        for _, m in ipairs(state.family.members) do
            if m.position == pos.id and m.status == "active" then
                filled = true
                break
            end
        end
        if not filled then
            vacantCount = vacantCount + 1
        end
    end
    if vacantCount >= 2 then
        ap = ap + BA.vacant_penalty
    end

    -- 科技加成：遍历已研究科技的 effects 数组，累加 ap_bonus
    if state.tech and state.tech.researched then
        local TechData = require("data.tech_data")
        local allTechs = TechData.GetAll()
        for _, t in ipairs(allTechs) do
            if state.tech.researched[t.id] and t.effects then
                for _, eff in ipairs(t.effects) do
                    if eff.kind == "ap_bonus" then
                        ap = ap + (eff.value or 0)
                    end
                end
            end
        end
    end

    -- 影响力里程碑"政治联盟"（>=120 影响力）→ AP +1
    local totalInfluence = GameState.CalcTotalInfluence(state)
    if totalInfluence >= 120 then
        ap = ap + 1
    end

    -- 上限和下限
    ap = math.min(ap, BA.base + BA.max_bonus)
    ap = math.max(ap, 1)  -- 至少保留 1 AP

    return ap
end

--- 消耗行动点
---@param state table
---@param cost number
---@return boolean 是否成功
function GameState.SpendAP(state, cost)
    local available = state.ap.current + state.ap.temp
    if available >= cost then
        -- 优先消耗临时 AP
        if state.ap.temp >= cost then
            state.ap.temp = state.ap.temp - cost
        else
            cost = cost - state.ap.temp
            state.ap.temp = 0
            state.ap.current = state.ap.current - cost
        end
        return true
    end
    return false
end

-- ============================================================================
-- 家族
-- ============================================================================

--- 获取岗位上的成员
---@param state table
---@param positionId string
---@return table|nil member
function GameState.GetMemberAtPosition(state, positionId)
    for _, m in ipairs(state.family.members) do
        if m.position == positionId and m.status == "active" then
            return m
        end
    end
    return nil
end

--- 分配成员到岗位
---@param state table
---@param memberId string
---@param positionId string|nil nil 表示解除岗位
---@return boolean
function GameState.AssignPosition(state, memberId, positionId)
    -- 如果目标岗位已有人，先清除
    if positionId then
        for _, m in ipairs(state.family.members) do
            if m.position == positionId then
                m.position = nil
            end
        end
    end

    -- 分配
    for _, m in ipairs(state.family.members) do
        if m.id == memberId then
            m.position = positionId
            return true
        end
    end
    return false
end

--- 获取岗位加成系数
---@param state table
---@param positionId string
---@return number bonus 加成系数 (1.0 / 0.5 / -0.1 / 0)
function GameState.GetPositionBonus(state, positionId)
    local member = GameState.GetMemberAtPosition(state, positionId)
    if not member then
        return Balance.FAMILY.vacant_efficiency_penalty
    end

    -- 查找岗位定义
    local posConfig = nil
    for _, p in ipairs(Config.POSITIONS) do
        if p.id == positionId then
            posConfig = p
            break
        end
    end
    if not posConfig then return 0 end

    local _, bonus = FamiliesData.GetPositionFit(member, posConfig.attr1, posConfig.attr2)
    return bonus
end

-- ============================================================================
-- 修正器
-- ============================================================================

--- 添加持续修正器
---@param state table
---@param id string
---@param target string
---@param value number
---@param duration number 持续回合数（0 = 永久）
function GameState.AddModifier(state, id, target, value, duration)
    state.modifiers = state.modifiers or {}
    table.insert(state.modifiers, {
        id = id,
        target = target,
        value = value,
        remaining = duration,
    })
end

--- 获取某个目标的修正总值
---@param state table
---@param target string
---@return number
function GameState.GetModifierValue(state, target)
    local total = 0
    if not state.modifiers then return total end
    for _, mod in ipairs(state.modifiers) do
        if mod.target == target then
            total = total + mod.value
        end
    end
    return total
end

--- 当前通胀乘数
---@param state table
---@return number
function GameState.GetInflationFactor(state)
    return state.inflation_factor or Balance.INFLATION.base_factor or 1.0
end

--- 当前资产价格乘数：通胀 + 历史事件造成的资产溢价/折价
---@param state table
---@return number
function GameState.GetAssetPriceFactor(state)
    local infl = GameState.GetInflationFactor(state)
    local cfg = Balance.INFLATION
    local assetMod = GameState.GetModifierValue(state, "asset_price_mod")
    assetMod = math.max(cfg.asset_mod_floor or -0.45,
        math.min(cfg.asset_mod_cap or 0.60, assetMod))
    return math.max(0.1, infl * (1 + assetMod))
end

--- 人力成本乘数：通胀 + 事件造成的工资/配给压力
---@param state table
---@return number
function GameState.GetLaborCostFactor(state)
    local laborMod = GameState.GetModifierValue(state, "worker_cost_multiplier")
    laborMod = math.max(-0.35, math.min(0.75, laborMod))
    return GameState.GetInflationFactor(state) * (1 + laborMod)
end

--- 推进修正器（每回合调用，减少剩余时间，移除到期的）
---@param state table
function GameState.TickModifiers(state)
    local kept = {}
    for _, mod in ipairs(state.modifiers) do
        if mod.remaining == 0 then
            -- 永久修正，保留
            table.insert(kept, mod)
        elseif mod.remaining > 1 then
            mod.remaining = mod.remaining - 1
            table.insert(kept, mod)
        end
        -- remaining == 1 → 本回合到期，不保留
    end
    state.modifiers = kept
end

-- ============================================================================
-- 历史日志
-- ============================================================================

--- 添加日志条目
---@param state table
---@param text string
function GameState.AddLog(state, text)
    table.insert(state.history_log, {
        turn = state.turn_count,
        year = state.year,
        quarter = state.quarter,
        text = text,
    })
    -- 限制日志长度
    if #state.history_log > 200 then
        table.remove(state.history_log, 1)
    end
end

-- ============================================================================
-- 地区
-- ============================================================================

--- 获取地区
---@param state table
---@param regionId string
---@return table|nil
function GameState.GetRegion(state, regionId)
    for _, r in ipairs(state.regions) do
        if r.id == regionId then
            return r
        end
    end
    return nil
end

-- ============================================================================
-- 资产估值（贷款额度、破产判断用）
-- ============================================================================

--- 计算玩家总资产估值
--- 现金 + 黄金市值 + 矿山估值 + 股票持仓市值
---@param state table
---@return number totalAssets
---@return table details { cash, gold_value, mine_value, stock_value }
function GameState.CalcTotalAssets(state)
    local inflation = GameState.GetInflationFactor(state)
    local goldPrice = math.floor(Balance.MINE.gold_price * inflation)

    local cash = math.max(0, state.cash)
    local goldValue = (state.gold or 0) * goldPrice

    -- 矿山估值：等级 × 基础价值
    local mineValue = 0
    for _, mine in ipairs(state.mines) do
        mineValue = mineValue + mine.level * math.floor(Balance.MINE.upgrade_cost
            * GameState.GetAssetPriceFactor(state))
    end

    -- 股票持仓市值
    local stockValue = 0
    if state.portfolio and state.portfolio.holdings then
        for stockId, h in pairs(state.portfolio.holdings) do
            for _, s in ipairs(state.stocks or {}) do
                if s.id == stockId then
                    stockValue = stockValue + math.floor(s.price * h.shares)
                    break
                end
            end
        end
    end

    local total = cash + goldValue + mineValue + stockValue
    return total, {
        cash = cash,
        gold_value = goldValue,
        mine_value = mineValue,
        stock_value = stockValue,
    }
end

--- 计算当前总负债
---@param state table
---@return number totalDebt
function GameState.CalcTotalDebt(state)
    local total = 0
    for _, loan in ipairs(state.loans or {}) do
        total = total + loan.principal
    end
    return total
end

--- 计算杠杆率（负债/资产）
---@param state table
---@return number leverage 0~∞
function GameState.CalcLeverage(state)
    local assets = GameState.CalcTotalAssets(state)
    if assets <= 0 then return 999 end
    return GameState.CalcTotalDebt(state) / assets
end

return GameState
