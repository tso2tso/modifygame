-- ============================================================================
-- 游戏状态：核心数据结构（阶段 B 完整版）
-- ============================================================================

local Config = require("config")
local Balance = require("data.balance")
local FamiliesData = require("data.families_data")
local RegionsData = require("data.regions_data")
local EuropeData = require("data.europe_data")
local MapTilesData = require("data.map_tiles_data")

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
        -- 难度
        -- ============================
        difficulty = Config.DEFAULT_DIFFICULTY,

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
        copper = 0,     -- 铜库存（矿山副产品，工业原料）
        coal   = 0,     -- 煤炭库存（工业区开采，每季可售卖）
        gold_auto_sell = false,  -- 黄金自动出售开关（默认关闭，玩家手动在产业页出售）
        copper_auto_sell = false,  -- 铜自动出售开关
        coal_auto_sell = false,    -- 煤炭自动出售开关
        coal_to_mines = 0,         -- 分配给矿山的煤炭数量
        factory_coal_shortage = false,  -- 工厂煤炭短缺标记
        mine_coal_power_bonus = 0, -- 运行时计算的煤炭动力加成
        local_coal_mine_unlocked = false, -- 科技解锁：本地煤矿开发

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
                inst.fair_value = inst.price  -- 初始公允价值 = 初始价格（inflation=1, sectorBonus≈0）
                table.insert(list, inst)
            end
            return list
        end)(),
        portfolio = {
            holdings = {},  -- { [stock_id] = { shares, avg_cost } }
            short_positions = {},  -- { [stock_id] = { shares, entry_price, margin, seasons_held } }
        },

        -- ============================
        -- 贷款
        -- ============================
        loans = {},  -- { { id, principal, interest, remaining_turns, total_paid } }
        loan_consecutive_defaults = 0,   -- 连续违约季度数
        negative_net_worth_turns = 0,    -- 净资产为负连续季度数
        bankrupt = false,                -- 是否已破产（游戏结束条件）

        -- ============================
        -- 新手引导
        -- ============================
        tutorial_done = false,           -- 是否已完成新手引导

        -- ============================
        -- 广告幸运事件
        -- ============================
        lucky_ad_watched = 0,            -- 本季已看广告次数
        lucky_ad_decay = 1.0,            -- 本季广告奖励衰减系数

        -- ============================
        -- 免广告卡（看广告充能，每回合免费使用广告点）
        -- ============================
        ad_free_card_charges = 0,        -- 已充能广告次数（满10激活）
        ad_free_card_active = false,     -- 免广告卡是否已激活
        ad_free_lucky_used = 0,          -- 本回合已用免费广告金次数
        ad_free_reroll_used = 0,         -- 本回合已用免费重随次数

        -- ============================
        -- 破产免死广告（每局限一次）
        -- ============================
        bankrupt_ad_used = 0,            -- 已使用破产免死次数

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
            claimed = nil,
            claimed_year = nil,
            claimed_quarter = nil,
            prompt_pending = nil,
        },
        battle_wins_total = 0,            -- 累计战斗胜利场次（用于军事胜利快照/记录）
        battle_wins_unclaimed = 0,        -- 尚未结算进军事胜利点的近期胜场
        emergency_gold_sold = false,      -- 本回合是否触发过紧急变卖黄金（快照验证用）
        culture_action_this_turn = false,  -- 本季是否执行过文化行动

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
        map_tiles = MapTilesData.CreateInitialTiles(),

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
                reserve = 500,     -- 独立储量（与初始 region gold_reserve 一致）
                initial_reserve = 500,
            },
        },
        mine_slots_bonus = 0,  -- 科技解锁的额外矿山槽位
        prospect_reserves = {},     -- 备用矿列表 { {id, name, reserve} }
        prospecting = nil,          -- 进行中 { progress, total, success_chance }
        prospect_success_count = 0, -- 累计成功次数（驱动递减）
        prospect_success_bonus = 0, -- 科技提供的成功率加成

        -- 铜矿探矿
        copper_prospecting = nil,           -- 进行中 { progress, total, success_chance }
        copper_prospect_count = 0,          -- 累计铜探矿成功次数
        -- 煤矿探矿
        coal_prospecting = nil,             -- 进行中 { progress, total, success_chance }
        coal_prospect_count = 0,            -- 累计煤探矿成功次数

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
            equipment = 1,  -- 旧字段保留兼容（新系统不再使用）
            -- 编队系统（新）
            squads = {},    -- { id, name, size, equip_id, veterancy, condition, battles }
            inventory = {}, -- 库存装备 { equip_id, condition }（未分配给编队的装备）
            -- 兵工厂
            factory = nil,  -- nil=未建造, { level, building={progress,total}|nil }
            -- 生产队列
            production_queue = {},  -- { equip_id, progress, total, source="factory" }
            outsource_slots = {},   -- { equip_id, progress, total, source="outsource" }

        },

        -- ============================
        -- 大国博弈系统
        -- ============================
        europe = EuropeData.CreateInitial(),  -- 17国领土状态（以id为key）
        collaboration_score = 0,              -- 玩家合作度（-100~+100）
        powers = {},                          -- 活跃大国AI（Phase 2 填充）
        fronts = {},                          -- 活跃前线（Phase 2 填充）
        _gp_initialized = false,              -- 大国博弈初始化标志

        -- ============================
        -- 远征系统（幕后执政解锁后激活）
        -- ============================
        expeditions = {
            active = {},               -- 活跃远征 { [country_id] = record }
            awaiting_occupation = {},  -- 待占领队列 { { country_id, label, defeated_turn } }
            occupied_countries = {},   -- 已占领国家列表
            aggression_counter = 0,    -- 侵略计数器（制裁触发）
            under_sanction = false,    -- 是否处于制裁状态
            sanction_remaining = 0,    -- 制裁剩余季度
            history = {
                expeditions_launched = 0,
                expeditions_won = 0,
                expeditions_lost = 0,
                support_missions = 0,
                total_loot = 0,
                countries_conquered = 0,
            },
        },

        -- ============================
        -- 商业远征系统（商业大亨解锁后激活）
        -- ============================
        ventures = {
            active = {},               -- 活跃渗透 { [power_id] = venture_record }
            -- venture_record = {
            --   power_id      = string,  -- 目标国家/势力 id
            --   route_id      = string,  -- 对应贸易路线 id
            --   city          = string,  -- 目标城市名
            --   strategy_id   = string,  -- 当前策略 (normal/dumping/bribery/tech_export)
            --   investment_level = number, -- 投资等级 1-3
            --   total_invested = number,  -- 累计投资额
            --   started_turn  = number,   -- 发起时回合数
            --   turns_active  = number,   -- 已进行回合数
            -- }
            awaiting_decision = {},    -- 待决策队列 { { power_id, city, label, completed_turn } }
            commercial_posts = {},     -- 已建立据点 { [power_id] = { type, city, established_turn } }
            market_tension = 0,        -- 市场紧张度（类似侵略计数器）
            under_trade_sanction = false,  -- 是否处于贸易制裁
            trade_sanction_remaining = 0,  -- 制裁剩余季度
            history = {
                ventures_launched  = 0,
                ventures_completed = 0,
                ventures_failed    = 0,
                total_venture_income = 0,
                posts_established  = 0,
            },
        },

        -- ============================
        -- 贸易系统（外贸解锁后激活）
        -- ============================
        trade = {
            order_pool = {},           -- 可接取订单池
            active_orders = {},        -- 已接取/运输中订单
            completed_count = 0,       -- 累计完成订单
            failed_count = 0,          -- 累计失败订单
            total_revenue = 0,         -- 累计贸易总收入
            -- (贸易信誉已合并到统一声誉 state.reputation)
            last_quarter_revenue = 0,  -- 上季度贸易收入（用于经济结算）
        },

        -- ============================
        -- 事件干旱计数器
        -- ============================
        event_drought_counter = 0,

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
                victory = { economic = 0, military = 0 },
                battle_wins_unclaimed = 0,
                recruit_blocked = 0,
                attack_cooldown = 0,
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
                victory = { economic = 0, military = 0 },
                battle_wins_unclaimed = 0,
                recruit_blocked = 0,
                attack_cooldown = 0,
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
        -- 掠夺系统（武力掠夺发展路线）
        -- ============================
        reputation = Balance.REPUTATION.initial,  -- 统一声誉 (-100 ~ +100)
        plunder_cooldowns = {
            raid_caravan   = 0,
            seize_vein     = 0,
            extort_foreign = 0,
        },
        manipulation_cooldowns = {
            pump        = 0,
            dump        = 0,
            coordinated = 0,
        },
        -- M2: 方向互斥锁 { [stockId] = { no_buy = N, no_short = N } }
        direction_locks = {},
        -- (press_credibility 已合并到统一声誉 state.reputation)
        has_seized_veins = false,  -- 是否曾成功夺取过矿脉（科技/事件触发条件）
        seized_veins = {},  -- { { remaining = N, gold_per_turn = M } }

        -- ============================
        -- 外国矿产操作
        -- ============================
        foreign_ops = {
            scouted = {},       -- { [tile_id] = true } 已侦察的外国矿
            scouting = nil,     -- { tile_id=string, remaining=number } 进行中侦察
            active = {},        -- { [tile_id] = { damage=0.8, reserve={gold,copper,coal} } }
        },

        -- ============================
        -- 被动效果（科技/事件累积）
        -- ============================
        passive_control = 0,         -- 被动控制度增益/季（科技"印刷宣传"等）
        regulation_pressure = 0,     -- 监管压力（事件/外交行为累积）
        special_content = {
            quota_active = false,
            black_market_active = false,
            foreign_trade_window = false,
            technocrat_route = false,
        },

        -- ============================
        -- 科技派生效果（运行时由科技系统累计，存档持久化）
        -- ============================
        mine_output_base_bonus = 0,
        mine_output_mult_bonus = 0,
        worker_efficiency_bonus = 0,
        guard_power_tech_bonus = 0,
        research_speed_bonus = 0,
        trade_passive_income = 0,
        finance_passive_income = 0,
        gold_price_bonus = 0,
        hire_cost_discount = 0,
        accident_rate_mod = 0,
        plunder_loot_mult_bonus = 0,    -- 掠夺收益倍率加成（科技累积）
        rep_recovery_bonus = 0,         -- 声誉恢复速度加成（科技累积）
        plunder_cooldown_reduction = 0, -- 掠夺冷却缩减季度数（科技累积）

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

        -- ============================
        -- 称号系统统计
        -- ============================
        stats = {
            attacks_initiated     = 0,  -- 主动发起攻击次数
            plunder_successes     = 0,  -- 掠夺成功次数
            manipulation_successes = 0, -- 操纵股市成功次数
            trades_completed      = 0,  -- 股票交易完成次数（买+卖）
            short_profit_total    = 0,  -- 做空累计盈利
        },
        titles_unlocked = {},  -- { [title_id] = unlocked_turn }
        titles_new      = {},  -- 本回合新解锁（回合末填充，展示后清空）
    }

    -- 起始资源受难度影响
    local diff = Config.GetDifficulty(state.difficulty)
    state.cash = math.floor(state.cash * (diff.start_cash_mult or 1.0))

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
    -- 重置本季广告次数
    state.lucky_ad_watched = 0
    state.lucky_ad_decay = 1.0
    -- 重置免广告卡本回合使用次数
    state.ad_free_lucky_used = 0
    state.ad_free_reroll_used = 0
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

--- 是否达到某个总控制度里程碑
---@param state table
---@param threshold number
---@return boolean
function GameState.HasControlMilestone(state, threshold)
    return GameState.CalcTotalControl(state) >= threshold
end

--- 控制度里程碑带来的招募/雇佣折扣
---@param state table
---@return number discount 0..0.10
function GameState.GetControlRecruitDiscount(state)
    if GameState.HasControlMilestone(state, 150) then
        return 0.10
    end
    return 0
end

local function GetFactionPresenceScore(state, factionId)
    local totalPresence = 0
    local weightedValue = 0
    for _, r in ipairs(state.regions or {}) do
        local presence = r.ai_presence and (r.ai_presence[factionId] or 0) or 0
        totalPresence = totalPresence + presence

        local regionWeight = 10
        if r.type == "mine" then
            regionWeight = 24
        elseif r.type == "industrial" then
            regionWeight = 20
        elseif r.type == "capital" then
            regionWeight = 18
        end
        weightedValue = weightedValue + math.floor(presence * regionWeight / 100)
    end
    return totalPresence, weightedValue
end

--- 计算玩家当前胜利评分
---@param state table
---@return table scores { economic, military, dominance }
function GameState.CalcPlayerVictoryScores(state)
    local economic = (state.victory and state.victory.economic) or 0
    local military = (state.victory and state.victory.military) or 0
    local controlBonus = math.floor(GameState.CalcTotalControl(state) / 5)
    return {
        economic = economic,
        military = military,
        dominance = economic + military + controlBonus,
    }
end

--- 计算 AI 当前胜利评分
---@param state table
---@param faction table
---@return table scores { economic, military, dominance, presence }
function GameState.CalcAIVictoryScores(state, faction)
    faction.victory = faction.victory or { economic = 0, military = 0 }
    local totalPresence, weightedValue = GetFactionPresenceScore(state, faction.id)
    local economic = faction.victory.economic or 0
    local military = faction.victory.military or 0
    local dominance = economic + military + math.floor(totalPresence / 2) + weightedValue
    return {
        economic = economic,
        military = military,
        dominance = dominance,
        presence = totalPresence,
    }
end

--- 计算 AI 本季胜利评分增量
---@param state table
---@param faction table
---@return table delta { economic, military }
function GameState.CalcAIVictoryDelta(state, faction)
    local totalPresence, weightedValue = GetFactionPresenceScore(state, faction.id)
    local economic = 0
    local military = 0

    if state.year >= Balance.VICTORY.economic.gate_year then
        economic = math.floor((faction.cash or 0) / Balance.VICTORY.economic.cash_divisor)
            + math.floor(totalPresence / 15)
            + math.floor(weightedValue / 20)
    end
    if state.year >= Balance.VICTORY.military.gate_year then
        local relative = (Balance.VICTORY and Balance.VICTORY.relative) or {}
        local powerMultiplier = relative.ai_military_power_multiplier or 0.20
        military = math.floor((faction.power or 0) * powerMultiplier)
            + math.floor(totalPresence / 18)
            + math.min(faction.battle_wins_unclaimed or 0, Balance.VICTORY.military.battle_wins_cap)
    end

    return { economic = economic, military = military }
end

--- 获取玩家相对 AI 的胜利领先态势
---@param state table
---@return table standing
function GameState.GetVictoryStanding(state)
    local player = GameState.CalcPlayerVictoryScores(state)
    local bestAI = {
        economic = { score = 0, faction = nil },
        military = { score = 0, faction = nil },
        dominance = { score = 0, faction = nil },
    }

    for _, faction in ipairs(state.ai_factions or {}) do
        local scores = GameState.CalcAIVictoryScores(state, faction)
        if scores.economic > bestAI.economic.score then
            bestAI.economic = { score = scores.economic, faction = faction }
        end
        if scores.military > bestAI.military.score then
            bestAI.military = { score = scores.military, faction = faction }
        end
        if scores.dominance > bestAI.dominance.score then
            bestAI.dominance = { score = scores.dominance, faction = faction }
        end
    end

    local relative = (Balance.VICTORY and Balance.VICTORY.relative) or {}
    local margins = relative.lead_margin or {}
    local ecoLead = player.economic - bestAI.economic.score
    local milLead = player.military - bestAI.military.score
    local domLead = player.dominance - bestAI.dominance.score

    local claimable = nil
    local minClaimYear = relative.min_claim_year or 1945
    if not (state.victory and state.victory.claimed) and state.year >= minClaimYear then
        if player.economic >= (Balance.VICTORY.economic.threshold or 0)
            and ecoLead >= (margins.economic or 200)
            and GameState.CheckEconomicSnapshot(state) then
            claimable = { type = "economic", lead = ecoLead, margin = margins.economic or 200 }
        elseif player.military >= (Balance.VICTORY.military.threshold or 0)
            and milLead >= (margins.military or 250)
            and GameState.CheckMilitarySnapshot(state) then
            claimable = { type = "military", lead = milLead, margin = margins.military or 250 }
        elseif domLead >= (relative.dominance_margin or 300)
            and ((not relative.dominance_requires_positive_track) or ecoLead > 0 or milLead > 0) then
            claimable = { type = "dominance", lead = domLead, margin = relative.dominance_margin or 300 }
        end
    end

    return {
        player = player,
        best_ai = bestAI,
        lead = {
            economic = ecoLead,
            military = milLead,
            dominance = domLead,
        },
        claimable = claimable,
    }
end

function GameState.UpdateVictoryPrompt(state)
    state.victory = state.victory or { economic = 0, military = 0 }
    if state.victory.claimed then
        state.victory.prompt_pending = nil
        return nil
    end

    local standing = GameState.GetVictoryStanding(state)
    if standing.claimable then
        local prompt = {
            type = standing.claimable.type,
            lead = standing.claimable.lead,
            margin = standing.claimable.margin,
            year = state.year,
            quarter = state.quarter,
        }
        state.victory.prompt_pending = prompt
        return prompt
    end

    state.victory.prompt_pending = nil
    return nil
end

function GameState.ClaimVictory(state, victoryType)
    state.victory = state.victory or { economic = 0, military = 0 }
    local prompt = state.victory.prompt_pending
    state.victory.claimed = victoryType or (prompt and prompt.type) or "dominance"
    state.victory.claimed_year = (prompt and prompt.year) or state.year
    state.victory.claimed_quarter = (prompt and prompt.quarter) or state.quarter
    state.victory.prompt_pending = nil
    GameState.AddLog(state, string.format("家族宣布%s胜利，但继续经营至时代终局。", state.victory.claimed))
end

function GameState.DismissVictoryPrompt(state)
    if state.victory then
        state.victory.prompt_pending = nil
    end
end

--- 经济胜利快照验证
---@param state table
---@return boolean
function GameState.CheckEconomicSnapshot(state)
    local snap = Balance.VICTORY.economic.snapshot
    local totalAssets = GameState.CalcTotalAssets(state)
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
    if state.year > BT.end_year or
       (state.year == BT.end_year and state.quarter > BT.end_quarter) then
        if state.victory and state.victory.claimed then
            return state.victory.claimed
        end
        local standing = GameState.GetVictoryStanding(state)
        if standing.claimable then
            return standing.claimable.type
        end
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
    local totalAssets = GameState.CalcTotalAssets(state)
    local totalDebt = GameState.CalcTotalDebt(state)
    local netWorth = totalAssets - totalDebt
    local standing = GameState.GetVictoryStanding(state)
    local claimedText = state.victory and state.victory.claimed
        and string.format("%d年%s宣布", state.victory.claimed_year or state.year,
            Config.QUARTER_NAMES[state.victory.claimed_quarter or state.quarter] or "")
        or "未宣布"

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
            { label = "地区控制度", value = tostring(totalControl) },
            { label = "度过季度", value = tostring(state.turn_count or 0) },
            { label = "胜利声明", value = claimedText },
        },
        progress = {
            economic = {
                label = "经济胜利",
                value = state.victory.economic or 0,
                threshold = (standing.best_ai.economic.score or 0) + ((Balance.VICTORY.relative.lead_margin or {}).economic or 200),
            },
            military = {
                label = "军事胜利",
                value = state.victory.military or 0,
                threshold = (standing.best_ai.military.score or 0) + ((Balance.VICTORY.relative.lead_margin or {}).military or 250),
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
    elseif victoryType == "dominance" then
        ending.title = "统治胜利：巴尔干霸主"
        ending.resultLabel = "胜利"
        ending.variant = "success"
        ending.icon = "★"
        ending.description = "家族在财富、武装与地区影响上全面压过所有竞争势力。"
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

local SECURITY_AI_THREAT_SCALE = 0.15

local function CalcRegionSecurityWithPower(state, region, playerPower)
    -- AI 势力值是宏观影响力，不能和护卫战力 1:1 相比；折算后才用于治安压力。
    local aiThreat = 0
    for _, faction in ipairs(state.ai_factions or {}) do
        if not faction.defeated then
            local presence = (region.ai_presence and region.ai_presence[faction.id]) or 0
            aiThreat = aiThreat + (faction.power or 0) * presence / 100 * SECURITY_AI_THREAT_SCALE
        end
    end

    local control = region.control or 0
    local target
    if aiThreat < 0.5 then
        -- 几乎无 AI 威胁：主要按玩家控制度决定。
        if control >= 60 then target = 5
        elseif control >= 30 then target = 4
        else target = 3 end
    else
        local ratio = playerPower / aiThreat
        if ratio >= 2.5 then target = 5
        elseif ratio >= 1.5 then target = 4
        elseif ratio >= 0.85 then target = 3
        elseif ratio >= 0.4 then target = 2
        else target = 1 end

        if control >= 80 then
            target = target + 1
        elseif control < 20 and target > 2 then
            target = target - 1
        end
    end

    return math.max(1, math.min(5, target))
end

--- 根据玩家军事力量 vs AI 区域威胁，纯计算单个区域治安等级（不改写状态）
---@param state table
---@param region table
---@return number security
function GameState.CalcRegionSecurity(state, region)
    local Combat = require("systems.combat")
    return CalcRegionSecurityWithPower(state, region, Combat.PlayerPower(state))
end

--- 计算顶栏安全等级：用全区域动态治安的均值表达整体态势，最差区域只限制上限。
--- 这样局部风险会被提示，但不会让单个低控制区把全局直接压成“极度危险”。
---@param state table
---@return number security
---@return number weakest
function GameState.CalcGlobalSecurity(state)
    local Combat = require("systems.combat")
    local playerPower = Combat.PlayerPower(state)
    local total, count, weakest = 0, 0, 5
    for _, r in ipairs(state.regions or {}) do
        local s = CalcRegionSecurityWithPower(state, r, playerPower)
        total = total + s
        count = count + 1
        if s < weakest then weakest = s end
    end
    if count == 0 then return 3, 3 end

    local aggregate = math.floor(total / count + 0.5)
    if weakest <= 1 then
        aggregate = math.min(aggregate, 2)
    elseif weakest <= 2 then
        aggregate = math.min(aggregate, 3)
    end
    return math.max(1, math.min(5, aggregate)), weakest
end

--- 根据玩家军事力量 vs AI 区域威胁，直接计算并写入各区域治安等级
--- 用于回合结算；UI 显示应使用 CalcGlobalSecurity，避免渲染过程改写状态。
---@param state table
function GameState.RecalcSecurity(state)
    local Combat = require("systems.combat")
    local playerPower = Combat.PlayerPower(state)
    for _, r in ipairs(state.regions or {}) do
        r.security = CalcRegionSecurityWithPower(state, r, playerPower)
    end
end

--- 计算当季 AP 上限（含加成和惩罚）
---@param state table
---@return number maxAP
function GameState.CalcMaxAP(state)
    local ap = BA.base

    -- 惩罚
    if state.flags and state.flags.at_war then
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

    -- 控制度里程碑"政治联盟"（总控制度 >=200）→ AP +1
    if GameState.HasControlMilestone(state, 200) then
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
    local temp = state.ap.temp or 0
    local available = state.ap.current + temp
    if available >= cost then
        -- 优先消耗临时 AP
        if temp >= cost then
            state.ap.temp = temp - cost
        else
            cost = cost - temp
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
    -- 如果目标岗位已有人，先清除（即时下岗，进入冷却）
    if positionId then
        for _, m in ipairs(state.family.members) do
            if m.position == positionId then
                m.position = nil
                m.onboarding_remaining = 0
                m.cooldown_turns = Balance.FAMILY.unassign_cooldown or 2
            end
        end
    end

    -- 分配
    for _, m in ipairs(state.family.members) do
        if m.id == memberId then
            if positionId then
                -- 上岗：设置适应期（称号modifier：适应期缩短）
                m.position = positionId
                local onboardReduction = GameState.GetModifierValue(state, "onboarding_reduction")
                m.onboarding_remaining = math.max(0,
                    (Balance.FAMILY.onboarding_turns or 2) - onboardReduction)
                m.cooldown_turns = 0  -- 上岗清除冷却
            else
                -- 下岗：即时生效，进入冷却期
                m.position = nil
                m.onboarding_remaining = 0
                m.cooldown_turns = Balance.FAMILY.unassign_cooldown or 2
            end
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
    -- 适应期间仅获得部分加成
    if (member.onboarding_remaining or 0) > 0 then
        local ratio = Balance.FAMILY.onboarding_bonus_ratio or 0.3
        bonus = bonus * ratio
    end
    return bonus
end

--- 统计在岗成员的隐藏倾向，用于灰色经营、监管、强硬路线等轻量联动。
---@param state table
---@param kind string corruption|loyalty|radical
---@return number avg
function GameState.GetActiveFamilyHiddenAverage(state, kind)
    local total = 0
    local count = 0
    for _, m in ipairs((state.family and state.family.members) or {}) do
        if m.status == "active" and m.position then
            total = total + FamiliesData.GetHiddenValue(m, kind)
            count = count + 1
        end
    end
    if count == 0 then return 0 end
    return total / count
end

--- 判断某岗位是否达到满配（excellent）。
---@param state table
---@param positionId string
---@return boolean
function GameState.HasExcellentPosition(state, positionId)
    local bonus = GameState.GetPositionBonus(state, positionId)
    return bonus >= 1.0
end

--- 内政总监满配时是否可揭示隐藏属性（便捷别名）。
---@param state table
---@return boolean
function GameState.CanRevealHiddenAttrs(state)
    return GameState.HasExcellentPosition(state, "civil_director")
end

--- 开始培养新成员。
---@param state table
---@return boolean ok
---@return string msg
function GameState.StartFamilyTraining(state)
    state.family = state.family or { members = {} }
    if state.family.training then
        return false, "已有成员正在培养"
    end
    local memberCount = #state.family.members
    if memberCount >= Balance.FAMILY.max_members then
        return false, "家族成员已达上限"
    end
    -- 立绘池耗尽检查（peek：不实际分配，只检查是否还有可用立绘）
    local hasPortrait = false
    for i = 1, #FamiliesData.PORTRAIT_POOL do
        if not FamiliesData.IsPoolPortraitUsed(i) then
            hasPortrait = true
            break
        end
    end
    if not hasPortrait then
        return false, "无可用立绘，无法培养"
    end
    -- 递增培养费用：根据当前成员数查阶梯表
    local cost = Balance.FAMILY.train_cost or 200
    local tiers = Balance.FAMILY.train_cost_tiers
    if tiers then
        -- 新成员将成为第 memberCount+1 个成员
        local nextCount = memberCount + 1
        for _, tier in ipairs(tiers) do
            if nextCount <= tier.max_count then
                cost = tier.cost
                break
            end
        end
        -- 超出所有阶梯则使用最后一档
        if nextCount > tiers[#tiers].max_count then
            cost = tiers[#tiers].cost
        end
    end
    if state.cash < cost then
        return false, string.format("现金不足（需要 %d）", cost)
    end
    state.cash = state.cash - cost
    local total = Balance.FAMILY.train_duration
        or (Balance.FAMILY.training and Balance.FAMILY.training.turns)
        or 10
    state.family.training = {
        progress = 0,
        total = total,
        member_template = FamiliesData.CreateTraineeTemplate(
            (state.turn_count or 0) + #state.family.members + 1,
            (function()
                local names = {}
                for _, m in ipairs(state.family.members) do
                    table.insert(names, m.name)
                end
                return names
            end)()
        ),
    }
    GameState.AddLog(state, string.format("开始培养新家族成员，预计 %d 季完成", total))
    return true, "已开始培养新成员"
end

--- 永久移除家族成员（投靠离队等P1事件调用）。
--- 释放立绘回池、清除岗位、从列表中删除。
---@param state table
---@param memberId string
---@return boolean ok
---@return string|nil removedName
function GameState.RemoveFamilyMember(state, memberId)
    local members = (state.family and state.family.members) or {}
    for i, m in ipairs(members) do
        if m.id == memberId then
            -- 释放池立绘
            if m.portraitImage then
                FamiliesData.ReleasePoolPortrait(m.portraitImage)
            end
            local name = m.name
            table.remove(members, i)
            GameState.AddLog(state, string.format("%s 永久离开了家族", name))
            return true, name
        end
    end
    return false, nil
end

--- 处理家族成员退休（年满退休年龄）。
--- 释放岗位、释放立绘，从列表中删除。
---@param state table
---@param memberId string
---@return boolean ok
---@return string|nil retiredName
function GameState.RetireFamilyMember(state, memberId)
    local members = (state.family and state.family.members) or {}
    for i, m in ipairs(members) do
        if m.id == memberId then
            -- 释放池立绘
            if m.portraitImage then
                FamiliesData.ReleasePoolPortrait(m.portraitImage)
            end
            local name = m.name
            local age  = m.age or 60
            table.remove(members, i)
            GameState.AddLog(state, string.format(
                "%s 年满 %d 岁，光荣退休，离开家族核心圈", name, age))
            return true, name
        end
    end
    return false, nil
end

--- 通过 hex 模块控制状态重算本地 region 的控制度与 AI 存在度。
---@param state table
function GameState.SyncRegionsFromMapTiles(state)
    if not state.map_tiles then return end
    MapTilesData.SyncRegionsFromTiles(state)
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
    local BG = Balance.GOLD
    local goldPrice = math.floor(Balance.MINE.gold_price * (inflation ^ BG.price_inflation_exponent))
    -- 战时溢价
    if state.flags and state.flags.at_war then
        goldPrice = math.floor(goldPrice * (1 + BG.war_premium))
    end
    local copperPrice = math.floor(Balance.MINE.copper_price * inflation)
    local coalPrice = math.floor(Balance.MINE.coal_price * inflation)

    local cash = math.max(0, state.cash)
    local goldValue = (state.gold or 0) * goldPrice
    local copperValue = (state.copper or 0) * copperPrice
    local coalValue = (state.coal or 0) * coalPrice

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

    local total = cash + goldValue + copperValue + coalValue + mineValue + stockValue
    return total, {
        cash = cash,
        gold_value = goldValue,
        copper_value = copperValue,
        coal_value = coalValue,
        mine_value = mineValue,
        stock_value = stockValue,
    }
end

--- 计算贷款抵押价值
--- 实体资产抵押率高，股票资产因波动性只按较低比例计入可贷基础。
---@param state table
---@return number collateralValue
---@return table details { real_asset_value, stock_value, real_collateral, stock_collateral }
function GameState.CalcLoanCollateralValue(state)
    local _, assets = GameState.CalcTotalAssets(state)
    local cfg = (Balance.LOAN and Balance.LOAN.collateral) or {}
    local realRatio = cfg.real_asset_ratio or 0.80
    local stockRatio = cfg.stock_asset_ratio or 0.25

    local realAssetValue = (assets.cash or 0) + (assets.gold_value or 0)
        + (assets.copper_value or 0) + (assets.coal_value or 0) + (assets.mine_value or 0)
    local stockValue = assets.stock_value or 0
    local realCollateral = math.floor(realAssetValue * realRatio)
    local stockCollateral = math.floor(stockValue * stockRatio)

    return realCollateral + stockCollateral, {
        real_asset_value = realAssetValue,
        stock_value = stockValue,
        real_collateral = realCollateral,
        stock_collateral = stockCollateral,
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

--- 计算贷款杠杆率（负债/抵押价值）
---@param state table
---@return number leverage 0~∞
function GameState.CalcLeverage(state)
    local collateralValue = GameState.CalcLoanCollateralValue(state)
    if collateralValue <= 0 then return 999 end
    return GameState.CalcTotalDebt(state) / collateralValue
end

-- ============================================================================
-- 声誉系统（掠夺路线平衡机制）
-- ============================================================================

--- 获取声誉等级 (1=清白, 2=可疑, 3=恶名, 4=臭名昭著, 5=公敌)
---@param state table
---@return number tier 1-5
function GameState.GetReputationTier(state)
    local rep = state.reputation or 0
    local t = Balance.REPUTATION.thresholds
    if rep <= t.public_enemy then return 5 end
    if rep <= t.infamous     then return 4 end
    if rep <= t.notorious    then return 3 end
    if rep <= t.suspicious   then return 2 end
    return 1
end

--- 获取声誉等级的显示名称
---@param tier number
---@return string
function GameState.GetReputationLabel(tier)
    local labels = { "清白", "可疑", "恶名", "臭名昭著", "公敌" }
    return labels[tier] or "未知"
end

--- 获取声誉导致的交易溢价比例（负面声誉时）
---@param state table
---@return number penalty 0~0.40
function GameState.GetTradePenalty(state)
    local tier = GameState.GetReputationTier(state)
    return Balance.REPUTATION.trade_penalty[tier] or 0
end

--- 获取正面声誉带来的贸易订单加成（替代原贸易信誉）
---@param state table
---@return number bonus 0~0.5
function GameState.GetTradeOrderBonus(state)
    local rep = math.max(0, state.reputation or 0)
    return rep * Balance.REPUTATION.trade_order_bonus
end

--- 获取正面声誉带来的路线安全加成（替代原贸易信誉）
---@param state table
---@return number bonus 0~0.2
function GameState.GetTradeSafetyBonus(state)
    local rep = math.max(0, state.reputation or 0)
    return rep * Balance.REPUTATION.trade_safety_bonus
end

--- 获取操盘乘数（替代原公信力系统）
--- rep=100 → ×1.0, rep=0 → ×0.75, rep=-100 → ×0.5
---@param state table
---@return number multiplier [0.5, 1.0]
function GameState.GetMarketManipulationMultiplier(state)
    local BR = Balance.REPUTATION
    local rep = state.reputation or 0
    local floor = BR.market_multiplier_floor
    local normalized = (rep - BR.min) / (BR.max - BR.min)  -- 0~1
    return floor + (1.0 - floor) * math.max(0, math.min(1, normalized))
end

--- 操盘消耗声誉（替代原公信力消耗）
---@param state table
---@param costKey string "pump"|"dump"|"coordinated"
---@param success boolean
function GameState.ConsumeMarketReputation(state, costKey, success)
    local BR = Balance.REPUTATION
    local baseCost = BR["market_cost_" .. costKey] or 15
    local cost = success and baseCost or math.ceil(baseCost * BR.market_cost_fail_mult)
    state.reputation = math.max(BR.min, (state.reputation or 0) - cost)
end

--- 修改声誉值（统一入口，自动 clamp）
---@param state table
---@param delta number
function GameState.ModifyReputation(state, delta)
    local BR = Balance.REPUTATION
    state.reputation = math.max(BR.min, math.min(BR.max, (state.reputation or 0) + delta))
end

return GameState
