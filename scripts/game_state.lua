-- ============================================================================
-- 游戏状态：核心数据结构（阶段 B 完整版）
-- ============================================================================

local Config = require("config")
local Balance = require("data.balance")
local FamiliesData = require("data.families_data")
local RegionsData = require("data.regions_data")

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

        -- ============================
        -- 行动点
        -- ============================
        ap = {
            current = BA.base,
            max     = BA.base,
            temp    = 0,  -- 事件奖励的临时 AP
        },

        -- ============================
        -- 胜利进度
        -- ============================
        victory = {
            economic = 0,
            military = 0,
        },

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
                attitude = 0,    -- 对玩家态度 -100~100
                power = 30,      -- 势力值
                desc = "扎根当地百年的传统望族，控制着大片土地和人脉网络。",
            },
            {
                id = "foreign_capital",
                name = "维也纳矿业公司",
                icon = "💼",
                type = "foreign_capital",
                cash = Balance.AI.foreign_capital.start_cash,
                attitude = 10,
                power = 40,
                desc = "来自帝国首都的资本集团，资金雄厚但在本地根基较浅。",
            },
        },

        -- ============================
        -- 事件
        -- ============================
        event_queue = {},       -- 当前季度待处理事件
        events_fired = {},      -- 已触发事件 id 集合（防重复）
        random_cooldowns = {},  -- 随机事件冷却 { [event_id] = remaining_quarters }

        -- ============================
        -- 修正器（来自事件的持续效果）
        -- ============================
        modifiers = {},
        -- 格式: { id, target, value, remaining_turns }

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
    -- 重置 AP（基础 + 临时归零）
    state.ap.current = state.ap.max
    state.ap.temp = 0
end

--- 检查游戏是否结束
---@param state table
---@return boolean
function GameState.IsGameOver(state)
    if state.year > BT.end_year then
        return true
    end
    if state.year == BT.end_year and state.quarter > BT.end_quarter then
        return true
    end
    -- 胜利条件
    if state.victory.economic >= Balance.VICTORY.threshold then
        return true
    end
    if state.victory.military >= Balance.VICTORY.threshold then
        return true
    end
    return false
end

--- 获取胜利类型（如果已胜利）
---@param state table
---@return string|nil victoryType "economic" / "military" / "timeout" / nil
function GameState.GetVictoryType(state)
    if state.victory.economic >= Balance.VICTORY.threshold then
        return "economic"
    end
    if state.victory.military >= Balance.VICTORY.threshold then
        return "military"
    end
    if state.year > BT.end_year or
       (state.year == BT.end_year and state.quarter > BT.end_quarter) then
        return "timeout"
    end
    return nil
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

    -- TODO: 阶段 D 添加加成（高级经理、科技、特质、通讯基建）

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
    for _, mod in ipairs(state.modifiers) do
        if mod.target == target then
            total = total + mod.value
        end
    end
    return total
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

return GameState
