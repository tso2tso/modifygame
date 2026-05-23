-- ============================================================================
-- 菜单页 UI：存档管理、新游戏、游戏统计、版本信息
-- 设计规范：sarajevo_dynasty_ui_spec §4.8 右侧 Drawer 托管
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local SaveLoad = require("utils.save_load")
local Balance = require("data.balance")

local AudioManager = require("systems.audio_manager")
local TechData = require("data.tech_data")
local EquipmentData = require("data.equipment_data")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local MenuPage = {}

-- ============================================================================
-- 测试作弊：连续点击"游戏统计"标题 6 次触发
-- ============================================================================
local cheatTapCount_ = 0
local cheatLastTapTime_ = 0
local CHEAT_TAP_REQUIRED = 6
local CHEAT_TAP_WINDOW = 3.0  -- 秒

---@type table
local stateRef_ = nil
---@type function|nil
local onStateChanged_ = nil
---@type function|nil
local onNewGame_ = nil
---@type function|nil
local onNewGameRequested_ = nil
---@type function|nil
local onDifficultyChanged_ = nil
---@type table|nil 存档操作卡片引用（用于局部刷新）
local saveCardRef_ = nil
---@type table|nil 难度卡片引用（用于局部刷新按钮颜色）
local diffCardRef_ = nil
---@type number 最近一次难度切换帧，用于阻止同一次点击链误触新游戏
local lastDifficultyChangeFrame_ = -1000

--- 创建菜单页完整内容
---@param state table
---@param callbacks table { onStateChanged, onNewGame }
---@return table widget
function MenuPage.Create(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged
    onNewGame_ = callbacks and callbacks.onNewGame
    onNewGameRequested_ = callbacks and callbacks.onNewGameRequested
    onDifficultyChanged_ = callbacks and callbacks.onDifficultyChanged
    saveCardRef_ = nil
    diffCardRef_ = nil
    return MenuPage._BuildContent(state)
end

function MenuPage._BuildContent(state)
    local hasSave = SaveLoad.HasSave()

    saveCardRef_ = MenuPage._CreateSaveCard(state, hasSave)

    return UI.Panel {
        id = "menuContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = {
            -- 游戏标题卡片
            MenuPage._CreateTitleCard(state),

            -- 音量设置卡片
            MenuPage._CreateAudioCard(),

            -- 难度设置卡片
            MenuPage._CreateDifficultyCard(state),

            -- 存档操作卡片（含双槽位读档）
            saveCardRef_,

            -- 游戏统计
            MenuPage._CreateStatsCard(state),

            -- 版本信息
            MenuPage._CreateAboutCard(),
        },
    }
end

--- 游戏标题卡片
function MenuPage._CreateTitleCard(state)
    local turnText = GameState.GetTurnText(state)
    local ending = GameState.GetEndingInfo(state)
    local statusText = ending and (ending.resultLabel .. "：" .. ending.title) or ("当前进度：" .. turnText)
    local statusColor = ending and (ending.variant == "failure" and C.accent_red or C.accent_gold)
        or C.text_secondary

    return UI.Panel {
        width = "100%",
        padding = S.card_padding + 4,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_gold,
        flexDirection = "column",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                text = "⚜️",
                fontSize = 32,
                textAlign = "center",
            },
            UI.Label {
                text = Config.TITLE,
                fontSize = F.card_title,
                fontWeight = "bold",
                fontColor = C.accent_gold,
                textAlign = "center",
            },
            UI.Label {
                text = statusText,
                fontSize = F.body_minor,
                fontColor = statusColor,
                textAlign = "center",
            },
        },
    }
end

--- 音量设置卡片
function MenuPage._CreateAudioCard()
    local function volumeRow(label, category)
        local val = math.floor(AudioManager.GetVolume(category) * 100)
        local valLabel = nil
        valLabel = UI.Label {
            id = "vol_" .. category,
            text = val .. "%",
            fontSize = F.label,
            fontColor = C.text_muted,
            width = 36,
            textAlign = "right",
        }
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = label,
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                    width = 40,
                },
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = {
                        UI.Slider {
                            value = val,
                            min = 0,
                            max = 100,
                            step = 5,
                            width = "100%",
                            trackColor = C.paper_mid,
                            fillColor = C.accent_gold,
                            onChange = (function(cat, lbl)
                                return function(self, v)
                                    AudioManager.SetVolume(cat, v / 100)
                                    if lbl then lbl:SetText(math.floor(v) .. "%") end
                                end
                            end)(category, valLabel),
                        },
                    },
                },
                valLabel,
            },
        }
    end

    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Label {
                text = "🔊 音量设置",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Divider { color = C.divider },
            volumeRow("音乐", "music"),
            volumeRow("音效", "effect"),
            volumeRow("界面", "ui"),
        },
    }
end

--- 难度设置卡片内部子元素列表（用于局部刷新）
function MenuPage._CreateDifficultyCardInner(state)
    local currentDiff = state.difficulty or Config.DEFAULT_DIFFICULTY

    local function makeDiffBtn(diffId)
        local d = Config.DIFFICULTY[diffId]
        local isActive = (diffId == currentDiff)
        return UI.Button {
            text = d.label,
            fontSize = F.body,
            height = 34,
            flexGrow = 1,
            variant = isActive and "primary" or "outlined",
            backgroundColor = isActive and C.accent_gold or nil,
            fontColor = isActive and C.bg_base or C.text_secondary,
            borderColor = isActive and C.accent_gold or C.border_card,
            borderRadius = S.radius_btn,
            onClick = Config.ClickGuard(function(self)
                if diffId == currentDiff then return end
                stateRef_.difficulty = diffId
                lastDifficultyChangeFrame_ = time.frameNumber or 0
                AudioManager.PlayUI("ui_click")
                -- 立即刷新按钮颜色
                MenuPage._RefreshDifficultyCard()
                -- 优先使用带 Loading 的难度切换回调
                if onDifficultyChanged_ then
                    onDifficultyChanged_()
                elseif onStateChanged_ then
                    onStateChanged_()
                end
            end),
        }
    end

    local diffInfo = Config.GetDifficulty(currentDiff)

    return {
        UI.Label {
            text = "⚔️ 难度设置",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_primary,
        },
        UI.Divider { color = C.divider },
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            children = (function()
                local btns = {}
                for _, diffId in ipairs(Config.DIFFICULTY_ORDER) do
                    table.insert(btns, makeDiffBtn(diffId))
                end
                return btns
            end)(),
        },
        UI.Label {
            text = diffInfo.desc,
            fontSize = F.label,
            fontColor = C.text_muted,
        },
    }
end

--- 难度设置卡片（容器 + 内容）
function MenuPage._CreateDifficultyCard(state)
    diffCardRef_ = UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 8,
        children = MenuPage._CreateDifficultyCardInner(state),
    }
    return diffCardRef_
end

--- 格式化存档时间戳为可读文本
function MenuPage._FormatTimestamp(ts)
    if not ts or ts == 0 then return "未知时间" end
    local d = os.date("*t", ts)
    if not d then return "未知时间" end
    return string.format("%d/%02d/%02d %02d:%02d", d.year, d.month, d.day, d.hour, d.min)
end

--- 创建存档槽位信息行（用于展示 auto/manual 槽位状态）
function MenuPage._CreateSlotInfoRow(label, info, onLoad)
    if not info then
        return UI.Panel {
            width = "100%",
            padding = 8,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_card,
            flexDirection = "row",
            alignItems = "center",
            children = {
                UI.Label {
                    text = label,
                    fontSize = F.body_minor,
                    fontWeight = "bold",
                    fontColor = C.text_muted,
                    width = 70,
                },
                UI.Label {
                    text = "空",
                    fontSize = F.body_minor,
                    fontColor = C.text_muted,
                    flexGrow = 1,
                },
            },
        }
    end

    local timeStr = MenuPage._FormatTimestamp(info.timestamp)
    local turnStr = string.format("%d年Q%d  第%d回合", info.year, info.quarter, info.turn_count)
    local cashStr = string.format("💰%d  🥇%d", info.cash, info.gold)

    return UI.Panel {
        width = "100%",
        padding = 8,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_card,
        flexDirection = "column",
        gap = 4,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = label,
                        fontSize = F.body_minor,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                        width = 70,
                    },
                    UI.Label {
                        text = turnStr,
                        fontSize = F.body_minor,
                        fontColor = C.text_primary,
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    UI.Button {
                        text = "读取",
                        fontSize = F.label,
                        height = 26,
                        paddingHorizontal = 10,
                        variant = "primary",
                        borderRadius = S.radius_btn,
                        onClick = onLoad,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = cashStr,
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                    },
                    UI.Label {
                        text = timeStr,
                        fontSize = F.label,
                        fontColor = C.text_muted,
                    },
                },
            },
        },
    }
end

--- 存档操作卡片内部子元素列表
function MenuPage._CreateSaveCardInner(state, hasSave)
    local autoInfo = SaveLoad.GetSlotInfo(SaveLoad.SLOT_AUTO)
    local manualInfo = SaveLoad.GetSlotInfo(SaveLoad.SLOT_MANUAL)
    -- 兼容旧版 autosave
    if not autoInfo then
        autoInfo = SaveLoad.GetSlotInfo()
    end

    return {
        UI.Label {
            text = "存档管理",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_primary,
        },
        UI.Divider { color = C.divider },
        -- 快速存档（存到 manual 槽）
        UI.Button {
            text = "快速存档",
            width = "100%",
            height = 36,
            fontSize = F.body,
            variant = "primary",
            backgroundColor = C.accent_gold,
            fontColor = C.bg_base,
            borderRadius = S.radius_btn,
            onClick = Config.ClickGuard(function(self)
                MenuPage._OnQuickSave()
            end),
        },
        UI.Divider { color = C.divider },
        -- 双槽位读档
        UI.Label {
            text = "选择存档读取",
            fontSize = F.body_minor,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        },
        MenuPage._CreateSlotInfoRow("自动存档", autoInfo, function(self)
            MenuPage._OnLoadSlot(autoInfo and SaveLoad.SLOT_AUTO or nil)
        end),
        MenuPage._CreateSlotInfoRow("手动存档", manualInfo, function(self)
            if manualInfo then
                MenuPage._OnLoadSlot(SaveLoad.SLOT_MANUAL)
            else
                UI.Toast.Show("暂无手动存档", { variant = "warning", duration = 1.5 })
            end
        end),
        UI.Divider { color = C.divider },
        -- 新游戏
        UI.Button {
            text = "开始新游戏",
            width = "100%",
            height = 36,
            fontSize = F.body,
            variant = "outlined",
            fontColor = C.accent_red,
            borderColor = C.accent_red,
            borderRadius = S.radius_btn,
            onClick = Config.ClickGuard(function(self)
                MenuPage._OnNewGame()
            end),
        },
        UI.Label {
            text = "新游戏将覆盖当前进度",
            fontSize = F.label,
            fontColor = C.text_muted,
            textAlign = "center",
            whiteSpace = "normal",
        },
    }
end

--- 存档操作卡片（容器 + 内容）
function MenuPage._CreateSaveCard(state, hasSave)
    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 8,
        children = MenuPage._CreateSaveCardInner(state, hasSave),
    }
end

-- ============================================================================
-- 作弊模式：拉满所有属性
-- ============================================================================

--- 拉满所有属性用于测试
---@param state table
function MenuPage._ApplyCheat(state)
    -- 1. 资源拉满
    state.cash = 999999
    state.gold = 9999
    state.copper = 9999
    state.coal = 9999

    -- 2. AP 拉满
    state.ap.max = 10
    state.ap.current = 10
    state.ap.temp = 5

    -- 3. 家族成员属性拉满
    for _, m in ipairs(state.family.members) do
        m.attrs.management = 10
        m.attrs.strategy = 10
        m.attrs.charisma = 10
        m.attrs.knowledge = 10
        m.attrs.ambition = 10
        if m.hidden then
            m.hidden.loyalty = 10
            m.hidden.corruption = 1
            m.hidden.radical = 1
        end
        m.status = "active"
        m.disabled_turns = 0
        m.onboarding_remaining = nil
        m.cooldown_turns = nil
    end

    -- 4. 矿山拉满
    for _, mine in ipairs(state.mines) do
        mine.level = 5
        mine.reserve = 9999
        mine.output_bonus = 5
    end
    state.mine_slots_bonus = 4

    -- 5. 科技全部研发（每个分支选 a 路线）
    local techPicks = {
        "a1_hand_drill", "a2_steam_drill", "a3_electric_mine",
        "a4a_ventilation", "a5_conveyor", "a6a_hydraulic", "a7_wartime_extraction",
        "b1_bookkeeping", "b2_accounting", "b3_telegraph",
        "b4a_trade_route", "b5_finance_net", "b6_stock_exchange",
        "b7a_intl_trade", "b8_central_banking",
        "c1_rifled_arms", "c2_logistics", "c3_machine_gun",
        "c4a_fortification", "c5_motorized", "c6a_intelligence", "c7_elite_force",
        "d1_propaganda", "d2_education", "d3_newspaper",
        "d4a_nationalism", "d5_radio", "d5b_cinema", "d6a_university", "d7_wartime_media",
        "d8_cultural_hegemony", "d9_propaganda_art", "d10_cultural_bureau", "d11_cultural_renaissance",
    }
    state.tech = state.tech or { researched = {} }
    state.tech.in_progress = nil
    for _, tid in ipairs(techPicks) do
        state.tech.researched[tid] = true
    end

    -- 5.5. 遍历已研发科技，应用 unlock_* 类特殊效果（避免遗漏新增解锁）
    state.unlocked_features = state.unlocked_features or {}
    for _, tid in ipairs(techPicks) do
        local tech = TechData.GetById(tid)
        if tech and tech.effects then
            for _, eff in ipairs(tech.effects) do
                if eff.kind == "unlock_foreign_trade" then
                    state.unlocked_features["foreign_trade"] = true
                elseif eff.kind == "unlock_venture" then
                    state.unlocked_features["venture"] = true
                elseif eff.kind == "unlock_local_coal_mine" then
                    state.local_coal_mine_unlocked = true
                end
            end
        end
    end

    -- 6. 科技派生加成拉满
    state.mine_output_base_bonus = 10
    state.mine_output_mult_bonus = 1.0
    state.worker_efficiency_bonus = 0.5
    state.guard_power_tech_bonus = 1.0
    state.research_speed_bonus = 3
    state.trade_passive_income = 200
    state.finance_passive_income = 200
    state.gold_price_bonus = 0.3
    state.hire_cost_discount = -0.3
    state.accident_rate_mod = -0.5
    state.passive_control = 20
    state.prospect_success_bonus = 0.3

    -- 7. 军事拉满
    state.military.guards = 200
    state.military.morale = 100
    state.military.factory = { level = 3 }
    -- 创建满编精英小队
    local EquipmentModule = require("systems.equipment")
    state.military.squads = {}
    for i = 1, 6 do
        local squadSize = 8
        local equipId = "elite_kit"
        local neededCount = EquipmentModule.CalcNeededCount(equipId, squadSize)
        local equipItems = {}
        for _ = 1, neededCount do
            table.insert(equipItems, { condition = 100, uid = 0 })
        end
        table.insert(state.military.squads, {
            id = "cheat_squad_" .. i,
            name = "精锐第" .. i .. "队",
            size = squadSize,
            equip_id = equipId,
            veterancy = 3,
            condition = 100,
            equip_items = equipItems,
            battles = 20,
        })
    end

    -- 8. 工人拉满
    state.workers.hired = 200
    state.workers.morale = 100

    -- 9. 地区拉满
    for _, r in ipairs(state.regions) do
        r.control = 100
        r.security = 5
        r.development = 5
        r.ai_presence.local_clan = 0
        r.ai_presence.foreign_capital = 0
        if r.resources then
            if r.resources.gold_reserve then r.resources.gold_reserve = 9999 end
            if r.resources.copper_reserve then r.resources.copper_reserve = 9999 end
            if r.resources.coal_reserve then r.resources.coal_reserve = 9999 end
        end
    end

    -- 10. 胜利分数拉满
    state.victory = state.victory or {}
    state.victory.economic = 2000
    state.victory.military = 2500
    -- 重置即时胜利标记，允许重复测试
    state.victory.instant_claimed = {}
    state.victory.instant_label = nil
    state.victory.instant_desc = nil

    -- 11. 清除负面状态
    state.loans = {}
    state.loan_consecutive_defaults = 0
    state.negative_net_worth_turns = 0
    state.bankrupt = false
    state.regulation_pressure = 0

    -- 12. 战斗记录
    state.battle_wins_total = 50
    state.battle_wins_unclaimed = 3

    -- 13. 弱化 AI + 改善对玩家态度
    if state.ai_factions then
        for _, ai in ipairs(state.ai_factions) do
            ai.cash = 100
            ai.power = 10
            ai.attitude = 70  -- 改善为友好态度（避免敌意行动）
            if ai.victory then
                ai.victory.economic = 0
                ai.victory.military = 0
            end
        end
    end

    -- 14. 通胀保持正常
    state.inflation_factor = 1.0

    -- 15. 累计统计拉满（称号检测依赖）
    state.stats = state.stats or {}
    state.stats.attacks_initiated      = math.max(state.stats.attacks_initiated or 0, 50)
    state.stats.plunder_successes      = math.max(state.stats.plunder_successes or 0, 30)
    state.stats.trades_completed       = math.max(state.stats.trades_completed or 0, 120)
    state.stats.manipulation_successes = math.max(state.stats.manipulation_successes or 0, 30)
    state.stats.short_profit_total     = math.max(state.stats.short_profit_total or 0, 60000)

    -- 16. 累计收支拉满
    state.total_income  = math.max(state.total_income or 0, 1200000)
    state.total_expense = state.total_expense or 0

    -- 17. 声誉归零（默认中立，方便测试正负两端）
    state.reputation = 0

    -- 18. 称号全解锁 + 应用称号奖励（modifier + unlock_features）
    local TitlesData = require("data.titles_data")
    local Expedition = require("systems.expedition")
    local Trade = require("systems.trade")
    state.titles_unlocked = state.titles_unlocked or {}
    state.unlocked_features = state.unlocked_features or {}
    local newlyUnlocked = {}
    for _, title in ipairs(TitlesData.TITLES) do
        if not state.titles_unlocked[title.id] then
            state.titles_unlocked[title.id] = state.turn_count or 1
            table.insert(newlyUnlocked, { id = title.id })
        end
        -- 应用称号奖励（幂等：modifier 重复插入无大碍，unlock_features 是 set）
        if title.rewards then
            if title.rewards.unlock_features then
                for _, feat in ipairs(title.rewards.unlock_features) do
                    state.unlocked_features[feat] = true
                end
            end
            if title.rewards.modifiers then
                for _, mod in ipairs(title.rewards.modifiers) do
                    local modId = "title_" .. title.id .. "_" .. mod.key
                    -- 避免重复添加
                    local exists = false
                    for _, m in ipairs(state.modifiers or {}) do
                        if m.id == modId then exists = true; break end
                    end
                    if not exists then
                        GameState.AddModifier(state, modId, mod.key, mod.value, 0)
                    end
                end
            end
        end
    end
    if #newlyUnlocked > 0 then
        state.titles_new = newlyUnlocked
    end

    -- 19. 远征系统初始化（解锁后必须初始化国家HP）
    if state.unlocked_features["expedition"] then
        Expedition.InitCountryHP(state)
        -- 确保远征数据结构存在
        state.expeditions = state.expeditions or {
            active = {},
            occupied_countries = {},
            aggression_counter = 0,
            under_sanction = false,
            sanction_remaining = 0,
            history = {
                raids_won = 0, raids_lost = 0,
                support_missions = 0, total_loot = 0,
                countries_conquered = 0,
            },
        }
        -- 作弊：占领除 greece 外的所有国家（差一个即可触发全占领即时胜利）
        state.expeditions.occupied_countries = {}
        for id, country in pairs(state.europe or {}) do
            if id ~= "bosnia" and id ~= "greece" then
                table.insert(state.expeditions.occupied_countries, {
                    country_id = id,
                    label = country.label or id,
                    income_per_turn = 500,
                    maintenance = 100,
                    since_turn = state.turn_count or 1,
                })
            end
        end
        state.expeditions.history.countries_conquered = #state.expeditions.occupied_countries
    end

    -- 20. 贸易系统初始化（解锁后生成订单池）
    if state.unlocked_features["foreign_trade"] then
        state.trade = state.trade or {}
        state.trade.order_pool = state.trade.order_pool or {}
        state.trade.active_orders = state.trade.active_orders or {}
        state.trade.routes = state.trade.routes or {}
        state.trade.route_unlocks = state.trade.route_unlocks or {}
        state.trade.completed_count = state.trade.completed_count or 0
        state.trade.failed_count = state.trade.failed_count or 0
        state.trade.total_revenue = state.trade.total_revenue or 0
        -- (trade.reputation 已合并到统一声誉 state.reputation)
        state.trade.last_quarter_revenue = state.trade.last_quarter_revenue or 0
        -- 生成订单池
        Trade.GenerateOrders(state)
    end

    -- 20.5. 商业远征系统初始化（解锁后初始化市场壁垒）
    if state.unlocked_features["venture"] then
        local Venture = require("systems.venture")
        Venture.InitMarketBarriers(state)
        -- 确保远征数据结构存在
        state.ventures = state.ventures or {
            active = {},
            awaiting_decision = {},
            commercial_posts = {},
            market_tension = 0,
            under_trade_sanction = false,
            trade_sanction_remaining = 0,
            history = {
                ventures_launched = 0, ventures_completed = 0,
                ventures_failed = 0, posts_established = 0,
                total_trade_income = 0, total_invested = 0,
            },
        }
    end

    -- 21. 外国矿产操作数据结构
    state.foreign_ops = state.foreign_ops or {
        scouted = {},
        scouting = nil,
        active = {},
    }

    -- 22. 军事库存：给每个编队补充备用装备
    state.military.inventory = state.military.inventory or {}
    for _, eid in ipairs({ "rifle", "improved_rifle", "mg", "mortar", "motorized", "elite_kit" }) do
        table.insert(state.military.inventory, { equip_id = eid, condition = 100 })
        table.insert(state.military.inventory, { equip_id = eid, condition = 100 })
    end

    -- 23. 重算 AP 上限
    state.ap.max = GameState.CalcMaxAP(state)
    state.ap.current = state.ap.max

    -- 25. C5 文化系统初始化 + 拉满
    local Culture = require("systems.culture")
    -- 确保 state.culture 结构存在
    if not state.culture then
        state.culture = {
            ci = 0, score = 0,
            region_cp = {}, cp_level_seen = {},
            works = {}, sports_cooldown = 0,
            exhibition_done = false, exhibition_progress = 0,
            missions = {}, mission_paused = {},
        }
    end
    -- 拉满 CI 和 culture_score
    state.culture.ci = 200
    state.culture.score = 800
    state.victory = state.victory or {}
    state.victory.culture = 800
    -- 创建三类作品（剧团×3、电影×5、史诗×3）
    -- 电影使用新系统格式：screenings[], archived, prod_turns, total_income
    local BC = Balance.CULTURE
    state.culture.works = {
        { type = "theater_troupe", location = "sarajevo",   created_turn = 1 },
        { type = "theater_troupe", location = "mostar",     created_turn = 1 },
        { type = "theater_troupe", location = "banja_luka", created_turn = 1 },
        -- 3部待发行（ready=true，占据制作槽，可多地区选择上映）
        {
            type = "film", theme = "historical",
            ready = true, archived = false,
            prod_progress = 3, prod_turns = BC and BC.film_prod_turns_by_theme and BC.film_prod_turns_by_theme.historical or 3,
            screenings = {}, total_income = 0, created_turn = 1,
        },
        {
            type = "film", theme = "national",
            ready = true, archived = false,
            prod_progress = 2, prod_turns = BC and BC.film_prod_turns_by_theme and BC.film_prod_turns_by_theme.national or 2,
            screenings = {}, total_income = 0, created_turn = 1,
        },
        {
            type = "film", theme = "propaganda",
            ready = true, archived = false,
            prod_progress = 2, prod_turns = BC and BC.film_prod_turns_by_theme and BC.film_prod_turns_by_theme.propaganda or 2,
            screenings = {}, total_income = 0, created_turn = 1,
        },
        -- 1部制作中（展示制作进度 UI）
        {
            type = "film", theme = "comedy",
            ready = false, archived = false,
            prod_progress = 1, prod_turns = BC and BC.film_prod_turns_by_theme and BC.film_prod_turns_by_theme.comedy or 2,
            screenings = {}, total_income = 0, created_turn = 1,
        },
        -- 1部已归档（展示归档 UI 和累计票房）
        {
            type = "film", theme = "adventure",
            ready = false, archived = true,
            prod_progress = 3, prod_turns = 3,
            screenings = {}, total_income = 480, created_turn = 1,
        },
        { type = "national_epic", theme = "national",   created_turn = 1 },
        { type = "national_epic", theme = "religious",  created_turn = 1 },
        { type = "national_epic", theme = "historical", created_turn = 1 },
    }
    -- 将所有已追踪地区的 CP 拉满到 identity 阈值（70）以上
    if state.europe then
        for regionId, _ in pairs(state.europe) do
            Culture.SetRegionCP(state, regionId, 72)
        end
    end
    for _, r in ipairs(state.regions or {}) do
        Culture.SetRegionCP(state, r.id, 80)
    end
    -- 世界博览会已举办（无需再筹备）
    state.culture.exhibition_done = true
    state.culture.sports_cooldown = 0
    state.culture_action_this_turn = false  -- 解除本季行动锁
    -- 同步 AI 文化分（防止 AI 超越玩家触发错误判断）
    for _, faction in ipairs(state.ai_factions or {}) do
        if not faction.is_player then
            faction.culture_score = math.min(faction.culture_score or 0, 200)
        end
    end

    -- 26. C3 大国博弈初始化（确保 state.powers 存在并设置有利参数）
    local GrandPowers = require("systems.grand_powers")
    GrandPowers.Init(state)  -- 幂等：已初始化则直接返回
    -- 降低所有大国军事/经济威胁，提升合作分，改善对玩家态度
    for _, power in pairs(state.powers or {}) do
        power.war_fatigue = math.max(power.war_fatigue or 0, 60)  -- 高疲惫 → 扩张意愿低
        power.military    = math.min(power.military or 0, 40)
        power.economy     = math.min(power.economy  or 0, 50)
        power.attitude_to_player = 70  -- 友好态度（允许条约、避免制裁）
    end
    state.collaboration_score = math.max(state.collaboration_score or 0, 60)
    -- 清除待处理的战争事件
    state.fronts = state.fronts or {}
    for _, front in pairs(state.fronts) do
        front.pending_wars = {}
    end

    -- 27. A2 占领地区开发政策（对所有已占领国家设置开发政策）
    if state.expeditions and state.expeditions.occupied_countries then
        for _, occ in ipairs(state.expeditions.occupied_countries) do
            if not occ.development_policy then
                occ.development_policy = "extraction"  -- 默认掠夺性开发
            end
            -- 作弊：升级到最高收益政策并提升发展等级
            occ.development_policy = "exploitation"
            occ.development_level  = occ.development_level or 3
            occ.income_per_turn    = math.max(occ.income_per_turn or 0, 600)
        end
    end

    -- 28. 股票市场：提升价格 + 赠送各股持仓 + 清空空头亏损
    for _, stock in ipairs(state.stocks or {}) do
        -- 价格提升 50%（模拟牛市）
        stock.prev_price = stock.price
        stock.price      = math.floor(stock.price * 1.5)
        stock.fair_value = stock.price
        stock.change_pct = 50
        -- 更新历史记录（避免 K 线图报错）
        if type(stock.history) == "table" then
            table.insert(stock.history, stock.price)
        end
    end
    -- 赠送持仓（每只股票 200 股，成本价设为当前价的 60%，保证浮盈）
    state.portfolio = state.portfolio or { holdings = {}, short_positions = {} }
    state.portfolio.short_positions = {}  -- 清除空头（避免保证金追缴）
    for _, stock in ipairs(state.stocks or {}) do
        local existing = state.portfolio.holdings[stock.id]
        if not existing then
            state.portfolio.holdings[stock.id] = {
                shares   = 200,
                avg_cost = math.floor(stock.price * 0.6),
            }
        else
            -- 已有持仓：追加到 200 股并拉低成本
            existing.shares   = math.max(existing.shares, 200)
            existing.avg_cost = math.min(existing.avg_cost, math.floor(stock.price * 0.6))
        end
    end

    -- 24. 存档
    SaveLoad.Save(state, SaveLoad.SLOT_AUTO)

    print("[CHEAT] 所有属性已拉满！（含称号+功能解锁+远征HP+贸易订单+装备库存+文化系统+大国博弈+占领政策+股票持仓+AI/大国好感）")
end

--- 处理统计标题点击（连续 6 次触发作弊）
function MenuPage._OnStatsTitleTap()
    local now = os.clock()
    if now - cheatLastTapTime_ > CHEAT_TAP_WINDOW then
        cheatTapCount_ = 0
    end
    cheatTapCount_ = cheatTapCount_ + 1
    cheatLastTapTime_ = now

    if cheatTapCount_ >= CHEAT_TAP_REQUIRED then
        cheatTapCount_ = 0
        if stateRef_ then
            MenuPage._ApplyCheat(stateRef_)
            AudioManager.PlayEffect("event_trigger")
            UI.Toast.Show("🔓 测试模式：属性+称号+统计 全部拉满！", { variant = "success", duration = 3 })
            if onStateChanged_ then
                onStateChanged_()
            end
        end
    else
        local remaining = CHEAT_TAP_REQUIRED - cheatTapCount_
        print(string.format("[DEBUG] 统计点击 %d/%d", cheatTapCount_, CHEAT_TAP_REQUIRED))
    end
end

--- 游戏统计卡片
function MenuPage._CreateStatsCard(state)
    local totalTurns = state.turn_count
    local totalIncome = state.total_income or 0
    local totalExpense = state.total_expense or 0
    local members = #state.family.members
    local logCount = #state.history_log
    state.victory = state.victory or { economic = 0, military = 0, claimed = false }
    local standing = GameState.GetVictoryStanding(state)
    local ecoTarget = (standing.best_ai.economic.score or 0)
        + (((Balance.VICTORY.relative.lead_margin or {}).economic) or 200)
    local milTarget = (standing.best_ai.military.score or 0)
        + (((Balance.VICTORY.relative.lead_margin or {}).military) or 250)

    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Panel {
                width = "100%",
                onClick = function()
                    MenuPage._OnStatsTitleTap()
                end,
                children = {
                    UI.Label {
                        text = "游戏统计",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                },
            },
            UI.Divider { color = C.divider },
            MenuPage._InfoRow("已度过回合", tostring(totalTurns)),
            MenuPage._InfoRow("累计收入", string.format("%d", totalIncome)),
            MenuPage._InfoRow("累计支出", string.format("%d", totalExpense)),
            MenuPage._InfoRow("净利润", string.format("%d", totalIncome - totalExpense)),
            MenuPage._InfoRow("家族成员", tostring(members) .. " 人"),
            MenuPage._InfoRow("事件记录", tostring(logCount) .. " 条"),
            MenuPage._InfoRow("经济领先", string.format("%d / %d", state.victory.economic, ecoTarget)),
            MenuPage._InfoRow("军事领先", string.format("%d / %d", state.victory.military, milTarget)),
            MenuPage._InfoRow("胜利声明", state.victory.claimed and "已宣布" or "未宣布"),
        },
    }
end

--- 版本信息
function MenuPage._CreateAboutCard()
    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Label {
                text = Config.TITLE,
                fontSize = F.body_minor,
                fontColor = C.text_muted,
                textAlign = "center",
            },
            UI.Label {
                text = "版本 " .. Config.VERSION .. " | MVP 竖版纵切片",
                fontSize = F.label,
                fontColor = C.text_muted,
                textAlign = "center",
            },
            UI.Label {
                text = "1904-1918 巴尔干半岛·波斯尼亚",
                fontSize = F.label,
                fontColor = C.text_muted,
                textAlign = "center",
            },
        },
    }
end

--- 信息行
function MenuPage._InfoRow(label, value)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label { text = label, fontSize = F.body_minor, fontColor = C.text_secondary },
            UI.Label { text = value, fontSize = F.body_minor, fontWeight = "bold", fontColor = C.text_primary },
        },
    }
end

-- ============================================================================
-- 操作回调
-- ============================================================================

--- 快速存档（存到 manual 槽）
function MenuPage._OnQuickSave()
    if not stateRef_ then return end
    local ok = SaveLoad.Save(stateRef_, SaveLoad.SLOT_MANUAL)
    if ok then
        UI.Toast.Show("手动存档成功", { variant = "success", duration = 1.5 })
    else
        UI.Toast.Show("存档失败", { variant = "error", duration = 1.5 })
    end
    if onStateChanged_ then onStateChanged_() end
    -- 局部刷新存档卡片（不重建 Modal）
    MenuPage._RefreshSaveCards()
end

--- 读取指定存档
function MenuPage._OnLoadSlot(slotName)
    local loaded = SaveLoad.Load(slotName)
    if loaded then
        loaded.ap.max = GameState.CalcMaxAP(loaded)
        loaded.ap.current = math.min(loaded.ap.current, loaded.ap.max)
        GameState.RecalcSecurity(loaded)

        UI.Toast.Show("读档成功：" .. slotName, { variant = "success", duration = 1.5 })
        if onNewGame_ then
            onNewGame_(loaded)
        end
    else
        UI.Toast.Show("读档失败：" .. slotName, { variant = "error", duration = 1.5 })
    end
end

--- 新游戏
function MenuPage._OnNewGame()
    local frame = time.frameNumber or 0
    if frame - lastDifficultyChangeFrame_ < 12 then
        return
    end

    if onNewGameRequested_ then
        onNewGameRequested_(true)
    elseif onNewGame_ then
        local newState = GameState.CreateNew()
        newState.tutorial_done = true
        newState.ap.max = GameState.CalcMaxAP(newState)
        newState.ap.current = newState.ap.max
        -- 继承免广告卡状态（账号级永久解锁，不随存档重置）
        if stateRef_ then
            newState.ad_free_card_active = stateRef_.ad_free_card_active or false
            newState.ad_free_card_charges = stateRef_.ad_free_card_charges or 0
        end
        GameState.AddLog(newState, "科瓦奇家族在巴科维奇矿区开始了创业之路。")
        UI.Toast.Show("新的百年传奇开始了！", { variant = "info", duration = 2 })
        onNewGame_(newState)
    end
end

--- 局部刷新难度卡片按钮颜色（不重建整个 Modal）
function MenuPage._RefreshDifficultyCard()
    if not diffCardRef_ or not stateRef_ then return end
    diffCardRef_:ClearChildren()
    for _, child in ipairs(MenuPage._CreateDifficultyCardInner(stateRef_)) do
        diffCardRef_:AddChild(child)
    end
end

--- 局部刷新存档相关卡片（不重建整个 Modal）
function MenuPage._RefreshSaveCards()
    if not stateRef_ then return end
    local hasSave = SaveLoad.HasSave()

    -- 替换存档操作卡片内容（含双槽位读档）
    if saveCardRef_ then
        saveCardRef_:ClearChildren()
        for _, child in ipairs(MenuPage._CreateSaveCardInner(stateRef_, hasSave)) do
            saveCardRef_:AddChild(child)
        end
    end
end

function MenuPage.Refresh(root, state)
    stateRef_ = state
end

return MenuPage
