-- ============================================================================
-- 快速操作弹窗集合：科技 / 情报 / 外交 / 资产交易 / 市场操盘
-- 每个弹窗呈现对应模块的可用操作，玩家点击执行
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local Tech = require("systems.tech")
local TechData = require("data.tech_data")
local Combat = require("systems.combat")
local StockEngine = require("systems.stock_engine")
local RegionsData = require("data.regions_data")

local AudioManager = require("systems.audio_manager")
local UITech = require("ui.ui_tech")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local ActionModals = {}

local currentModal_ = nil
local onStateChanged_ = nil
local stateRef_ = nil
---@type table|nil UI 根节点引用
local uiRoot_ = nil

--- 设置回调
function ActionModals.SetCallbacks(state, onChanged)
    stateRef_ = state
    onStateChanged_ = onChanged
end

--- 设置 UI 根节点（Modal 必须 AddChild 到 UI 树才能渲染）
function ActionModals.SetRoot(root)
    uiRoot_ = root
end

local function closeModal()
    if currentModal_ then
        AudioManager.PlayUI("ui_modal_close")
        currentModal_:Close()
        -- onClose 回调负责 Destroy 和置 nil
    end
end

local function notifyChanged()
    if onStateChanged_ then onStateChanged_() end
end

-- ============================================================================
-- 通用工具
-- ============================================================================
local function listItem(children)
    return UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.border_card,
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = children,
    }
end

local function actionBtn(label, bg, onClick, disabled)
    return UI.Panel {
        width = 86, height = 32,
        borderRadius = S.radius_btn,
        backgroundColor = disabled and C.paper_mid or bg,
        justifyContent = "center", alignItems = "center",
        pointerEvents = disabled and "none" or "auto",
        opacity = disabled and 0.55 or 1.0,
        onPointerUp = Config.TapGuard(function(self)
            if not disabled then onClick() end
        end),
        children = {
            UI.Label {
                text = label,
                fontSize = F.body_minor,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 科技研发（已拆分至 ui/ui_tech.lua 模块）
-- ============================================================================


function ActionModals.ShowTechnology(state, accent, selectedTechId)
    closeModal()
    UITech.Show(state, accent, uiRoot_, function()
        notifyChanged()
    end)
end

--- 科技树图例项（保留向后兼容）
function ActionModals._TechLegendItem(color, label)
    return UITech._LegendItem(color, label)
end


-- ============================================================================
-- 情报行动弹窗
-- ============================================================================
function ActionModals.ShowIntelligence(state, accent)
    AudioManager.PlayUI("ui_modal_open")
    closeModal()

    local rows = {}
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction  -- 闭包捕获
        -- 瘫痪势力显示特殊卡片
        if faction.collapsed then
            table.insert(rows, UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = { 40, 40, 45, 255 },
                borderRadius = S.radius_card,
                borderLeftWidth = 2,
                borderLeftColor = { 100, 100, 100, 255 },
                flexDirection = "column",
                gap = 6,
                opacity = 0.7,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label {
                                text = "💀 " .. faction.name,
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = { 140, 140, 140, 255 },
                            },
                            UI.Panel {
                                paddingHorizontal = 5,
                                paddingVertical = 1,
                                backgroundColor = { 180, 50, 50, 50 },
                                borderRadius = S.radius_badge,
                                children = {
                                    UI.Label {
                                        text = "已瘫痪",
                                        fontSize = F.label,
                                        fontColor = C.accent_red,
                                    },
                                },
                            },
                        },
                    },
                    UI.Label {
                        text = "该势力已崩溃，无需情报行动",
                        fontSize = F.label,
                        fontColor = { 120, 120, 120, 255 },
                    },
                },
            })
        else
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 2,
            borderLeftColor = accent,
            flexDirection = "column",
            gap = 6,
            children = {
                UI.Label {
                    text = (faction.icon or "") .. " " .. faction.name,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                -- 已知情报（侦察后显示）
                faction.scouted and UI.Label {
                    text = string.format("情报：现金 %d  势力 %d  态度 %d",
                        faction.cash, faction.power, faction.attitude),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                } or UI.Label {
                    text = "情报：未知（先侦察）",
                    fontSize = F.label,
                    fontColor = C.text_muted,
                },
                -- 3 个行动按钮
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    children = {
                        actionBtn("侦察",
                            C.accent_blue,
                            function() ActionModals._IntelScout(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.INTEL.scout)),
                    },
                },
            },
        })
        end
    end

    ActionModals._ShowList("👁️ 情报行动", rows)
end

--- 检查是否负担得起（AP + 现金×通胀 + 可选 influence）
---@param state table
---@param cfg table { ap, cash }
---@param influenceCost number|nil 额外的影响力消耗（可选）
function ActionModals._CanAfford(state, cfg, influenceCost)
    local inflation = GameState.GetInflationFactor(state)
    if state.cash < math.floor((cfg.cash or 0) * inflation) then return false end
    if (state.ap.current + (state.ap.temp or 0)) < (cfg.ap or 0) then return false end
    if influenceCost and influenceCost > 0 then
        local totalInfluence = GameState.CalcTotalInfluence(state)
        if totalInfluence < influenceCost then return false end
    end
    return true
end

--- 原子扣费：同时扣 AP、现金×通胀、可选 influence
---@param state table
---@param cfg table
---@param influenceCost number|nil
function ActionModals._Spend(state, cfg, influenceCost)
    if not ActionModals._CanAfford(state, cfg, influenceCost) then return false end
    local apOk = GameState.SpendAP(state, cfg.ap or 0)
    if not apOk then return false end
    local inflation = GameState.GetInflationFactor(state)
    state.cash = state.cash - math.floor((cfg.cash or 0) * inflation)
    -- 扣除 influence：按比例从各地区扣减
    if influenceCost and influenceCost > 0 then
        local totalInf = GameState.CalcTotalInfluence(state)
        if totalInf > 0 then
            for _, r in ipairs(state.regions) do
                local ratio = (r.influence or 0) / totalInf
                local loss = math.floor(influenceCost * ratio + 0.5)
                r.influence = math.max(0, (r.influence or 0) - loss)
            end
        end
    end
    return true
end

function ActionModals._IntelScout(state, faction)
    local cfg = Balance.INTEL.scout
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.scouted = true
    state.flags = state.flags or {}
    state.flags.intel_unlocked = true
    GameState.AddLog(state, string.format("[情报] 侦察 %s：现金 %d，势力 %d",
        faction.name, faction.cash, faction.power))
    UI.Toast.Show("侦察完成，情报已更新", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 外交弹窗
-- ============================================================================
function ActionModals.ShowDiplomacy(state, accent)
    AudioManager.PlayUI("ui_modal_open")
    closeModal()

    local rows = {}
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction
        if faction.collapsed then
            table.insert(rows, UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = { 40, 40, 45, 255 },
                borderRadius = S.radius_card,
                borderLeftWidth = 2,
                borderLeftColor = { 100, 100, 100, 255 },
                flexDirection = "column",
                gap = 6,
                opacity = 0.7,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label { text = "💀 " .. faction.name, fontSize = F.body,
                                fontWeight = "bold", fontColor = { 140, 140, 140, 255 } },
                            UI.Panel { paddingHorizontal = 5, paddingVertical = 1,
                                backgroundColor = { 180, 50, 50, 50 }, borderRadius = S.radius_badge,
                                children = { UI.Label { text = "已瘫痪", fontSize = F.label,
                                    fontColor = C.accent_red } } },
                        },
                    },
                    UI.Label { text = "该势力已崩溃，无法进行外交", fontSize = F.label,
                        fontColor = { 120, 120, 120, 255 } },
                },
            })
        else
        local pactText = (faction.pact_remaining and faction.pact_remaining > 0)
            and string.format("  🤝协议剩 %d 季", faction.pact_remaining) or ""
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 2,
            borderLeftColor = accent,
            flexDirection = "column",
            gap = 6,
            children = {
                UI.Label {
                    text = (faction.icon or "") .. " " .. faction.name
                        .. "  态度 " .. faction.attitude .. pactText,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                -- 情报信息（侦察后显示）
                faction.scouted and UI.Label {
                    text = string.format("📋 情报：现金 %d  势力 %d  态度 %d",
                        faction.cash, faction.power, faction.attitude),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                } or UI.Label {
                    text = "📋 情报：未知（先侦察）",
                    fontSize = F.label,
                    fontColor = C.text_muted,
                },
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    flexWrap = "wrap",
                    children = {
                        actionBtn("侦察",
                            { 100, 140, 180, 255 },
                            function() ActionModals._IntelScout(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.INTEL.scout)),
                        actionBtn("送礼",
                            C.accent_green,
                            function() ActionModals._DiploGift(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.gift)),
                        actionBtn("协议",
                            C.accent_blue,
                            function() ActionModals._DiploTreaty(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.treaty, Balance.INFLUENCE.cost_treaty)),
                        actionBtn("敌对",
                            C.accent_red,
                            function() ActionModals._DiploHostile(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.hostile)),
                    },
                },
            },
        })
        end
    end

    ActionModals._ShowList("🤝 政治外交 / 情报", rows)
end

function ActionModals._DiploGift(state, faction)
    local cfg = Balance.DIPLOMACY.gift
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.attitude = math.min(100, faction.attitude + cfg.attitude)
    GameState.AddLog(state, string.format("[外交] 向 %s 送礼，态度 +%d",
        faction.name, cfg.attitude))
    UI.Toast.Show("礼物已送达", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._DiploTreaty(state, faction)
    local cfg = Balance.DIPLOMACY.treaty
    local infCost = Balance.INFLUENCE.cost_treaty
    if faction.attitude < cfg.attitude_req then
        UI.Toast.Show(string.format("需要态度 ≥ %d 才能签订协议", cfg.attitude_req),
            { variant = "warning", duration = 1.5 })
        return
    end
    if not ActionModals._CanAfford(state, cfg, infCost) then
        UI.Toast.Show("资源不足（需影响力≥" .. infCost .. "）", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg, infCost)
    faction.attitude = math.min(100, faction.attitude + cfg.attitude)
    faction.pact_remaining = cfg.pact_turns
    GameState.AddLog(state, string.format("[外交] 与 %s 签订协议，%d 季互不侵犯",
        faction.name, cfg.pact_turns))
    UI.Toast.Show("协议已签订", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._DiploHostile(state, faction)
    local cfg = Balance.DIPLOMACY.hostile
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.attitude = math.max(-100, faction.attitude + cfg.attitude)
    faction.pact_remaining = 0
    GameState.AddLog(state, string.format("[外交] 与 %s 断交，态度 %d",
        faction.name, faction.attitude))
    UI.Toast.Show("已宣布敌对", { variant = "warning", duration = 1.5 })
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 资产交易弹窗
-- ============================================================================
function ActionModals.ShowTrade(state, accent)
    AudioManager.PlayUI("ui_modal_open")
    closeModal()

    local rows = {}

    -- 开发新矿
    local maxMines = (Balance.TRADE.new_mine.max_mines or 4) + (state.mine_slots_bonus or 0)
    local minesFull = #state.mines >= maxMines
    local assetPriceFactor = GameState.GetAssetPriceFactor(state)
    local newMineCost = math.floor(Balance.TRADE.new_mine.cash * assetPriceFactor)
    table.insert(rows, ActionModals._TradeOption(
        "⛏️ 开发新矿区",
        string.format("投入 %d 克朗 / %d AP 建立一座新矿（%d/%d）",
            newMineCost, Balance.TRADE.new_mine.ap,
            #state.mines, maxMines),
        accent,
        function() ActionModals._TradeNewMine(state) end,
        minesFull or state.cash < newMineCost or (state.ap.current + (state.ap.temp or 0)) < Balance.TRADE.new_mine.ap
    ))

    -- 本地煤矿（采矿科技解锁，复用矿山槽位）
    if state.local_coal_mine_unlocked then
        local coalCfg = Balance.TRADE.local_coal_mine or {}
        local coalMineCost = math.floor((coalCfg.cash or 700) * assetPriceFactor)
        local coalMineAP = coalCfg.ap or 1
        table.insert(rows, ActionModals._TradeOption(
            "⚫ 开发本地煤矿",
            string.format("投入 %d 克朗 / %d AP 建立一座煤矿（%d/%d）",
                coalMineCost, coalMineAP, #state.mines, maxMines),
            accent,
            function() ActionModals._TradeNewCoalMine(state) end,
            minesFull or state.cash < coalMineCost or (state.ap.current + (state.ap.temp or 0)) < coalMineAP
        ))
    end

    -- 出售矿山
    for _, mine in ipairs(state.mines) do
        if mine.active and #state.mines > 1 then
            local mineLocal = mine
            local salePrice = math.floor(mine.level * Balance.TRADE.sell_mine.cash_per_level * assetPriceFactor)
            table.insert(rows, ActionModals._TradeOption(
                "💸 出售 " .. mine.name,
                string.format("得现金 %d 克朗（Lv.%d）",
                    salePrice, mine.level),
                accent,
                function() ActionModals._TradeSellMine(state, mineLocal, salePrice) end,
                false
            ))
        end
    end

    -- 对 AI 发起资本攻击
    local inflationFactor = GameState.GetInflationFactor(state)
    for _, faction in ipairs(state.ai_factions) do
        -- 瘫痪势力：显示已瘫痪提示，跳过攻击选项
        if faction.collapsed then
            table.insert(rows, ActionModals._TradeOption(
                "💀 " .. faction.name .. "（已瘫痪）",
                "该势力已崩溃，无需进一步打击",
                { 100, 100, 100, 255 },
                function() end,
                true
            ))
        else
        local factionLocal = faction
        table.insert(rows, ActionModals._TradeOption(
            "🚫 破坏招募：" .. faction.name,
            string.format("花 %d 克朗封锁招募渠道，%d 季内无法扩张势力",
                math.floor(Balance.TRADE.raid_ai.cash * inflationFactor),
                Balance.TRADE.raid_ai.recruit_block_duration),
            accent,
            function() ActionModals._TradeRaid(state, factionLocal) end,
            not ActionModals._CanAfford(state, Balance.TRADE.raid_ai)
        ))
        local attackCfg = { ap = Balance.COMBAT.player_attack_ap, cash = Balance.COMBAT.player_attack_cash }
        table.insert(rows, ActionModals._TradeOption(
            "🛡 武装突袭：" .. faction.name,
            string.format("花 %d 克朗 / %d AP 发动一次军事打击，胜负会改变地区控制",
                math.floor(attackCfg.cash * inflationFactor), attackCfg.ap),
            C.accent_red,
            function() ActionModals._TradeMilitaryStrike(state, factionLocal) end,
            not ActionModals._CanAfford(state, attackCfg)
        ))
        end
    end

    -- ----------------------------------------------------------------
    -- 📊 市场操盘分组（需前置科技解锁）
    -- ----------------------------------------------------------------
    local hasAnyManipTech = (state.tech and state.tech.researched)
        and (state.tech.researched["d3_newspaper"]
            or state.tech.researched["d5_radio"]
            or state.tech.researched["d7_wartime_media"])
    if hasAnyManipTech then
        -- 分组标题 + 公信力显示
        local credibility = state.press_credibility or 100
        local credMult = StockEngine.GetCredibilityMultiplier(state)
        local credColor = credibility >= 70 and C.accent_green
            or credibility >= 40 and C.accent_amber
            or C.accent_red
        -- 标题行
        table.insert(rows, UI.Panel {
            width = "100%",
            paddingTop = 6,
            paddingBottom = 2,
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "📊 市场操盘",
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.accent_amber,
                },
            },
        })
        -- 公信力信息条：进度条 + 数值 + 效果说明
        table.insert(rows, UI.Panel {
            width = "100%",
            paddingVertical = 4,
            paddingHorizontal = 4,
            marginBottom = 4,
            borderRadius = 4,
            backgroundColor = C.bg_inset,
            children = {
                -- 第一行：标签 + 数值
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    marginBottom = 4,
                    children = {
                        UI.Label {
                            text = "📰 媒体公信力",
                            fontSize = F.body_minor,
                            fontColor = C.text_secondary,
                        },
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            children = {
                                UI.Label {
                                    text = string.format("%d", credibility),
                                    fontSize = F.body,
                                    fontWeight = "bold",
                                    fontColor = credColor,
                                },
                                UI.Label {
                                    text = " / 100",
                                    fontSize = F.body_minor,
                                    fontColor = C.text_tertiary,
                                },
                            },
                        },
                    },
                },
                -- 进度条
                UI.ProgressBar {
                    value = credibility / 100,
                    width = "100%",
                    height = 6,
                    borderRadius = 3,
                    trackColor = C.bg_surface,
                    fillColor = credColor,
                },
                -- 第二行：效果说明
                UI.Label {
                    text = string.format("操盘成功率 ×%.0f%%", credMult * 100),
                    fontSize = F.label,
                    fontColor = credColor,
                    marginTop = 3,
                },
            },
        })

        local manipCfg = Balance.MARKET_MANIPULATION
        local cd = state.manipulation_cooldowns or {}
        local researched = state.tech.researched

        -- 1) 做多操盘
        local pumpUnlocked = researched["d3_newspaper"]
            and StockEngine.GetHoldingLevel(state, "balkan_press") ~= "none"
        local pumpCd = cd.pump or 0
        local pumpDesc
        if pumpCd > 0 then
            pumpDesc = string.format("冷却中（%d 季）", pumpCd)
        elseif not researched["d3_newspaper"] then
            pumpDesc = "需研究「地方报纸」"
        elseif StockEngine.GetHoldingLevel(state, "balkan_press") == "none" then
            pumpDesc = "需持有新闻社 ≥ 战略持股"
        else
            local pumpRate = manipCfg.pump.base_success * credMult
            pumpDesc = string.format("%d AP / 市值×15%%（≥%d）  成功率 %.0f%%",
                manipCfg.pump.ap, manipCfg.pump.min_cash,
                pumpRate * 100)
        end
        table.insert(rows, ActionModals._TradeOption(
            "📈 做多操盘",
            pumpDesc,
            C.accent_green,
            function()
                ActionModals._ShowStockPicker(state, "pump")
            end,
            not pumpUnlocked or pumpCd > 0 or state.cash < manipCfg.pump.min_cash
        ))

        -- 2) 做空操盘
        local pressLevel = StockEngine.GetHoldingLevel(state, "balkan_press")
        local dumpUnlocked = researched["d5_radio"]
            and (pressLevel == "influence" or pressLevel == "control")
        local dumpCd = cd.dump or 0
        local dumpDesc
        if dumpCd > 0 then
            dumpDesc = string.format("冷却中（%d 季）", dumpCd)
        elseif not researched["d5_radio"] then
            dumpDesc = "需研究「广播电台」"
        elseif pressLevel ~= "influence" and pressLevel ~= "control" then
            dumpDesc = "需持有新闻社 ≥ 重要持股"
        else
            local dumpRate = manipCfg.dump.base_success * credMult
            dumpDesc = string.format("%d AP / 市值×20%%（≥%d）  成功率 %.0f%%",
                manipCfg.dump.ap, manipCfg.dump.min_cash,
                dumpRate * 100)
        end
        table.insert(rows, ActionModals._TradeOption(
            "📉 做空操盘",
            dumpDesc,
            C.accent_red,
            function()
                ActionModals._ShowStockPicker(state, "dump")
            end,
            not dumpUnlocked or dumpCd > 0 or state.cash < manipCfg.dump.min_cash
        ))

        -- 3) 联合操盘
        local cultureBonus = GameState.GetPositionBonus(state, "culture_advisor")
        local coordUnlocked = researched["d7_wartime_media"]
            and pressLevel == "control"
            and cultureBonus >= 0.8
        local coordCd = cd.coordinated or 0
        local coordDesc
        if coordCd > 0 then
            coordDesc = string.format("冷却中（%d 季）", coordCd)
        elseif not researched["d7_wartime_media"] then
            coordDesc = "需研究「战时媒体管控」"
        elseif pressLevel ~= "control" then
            coordDesc = "需持有新闻社 ≥ 控股"
        elseif cultureBonus < 0.8 then
            coordDesc = string.format("需文化顾问加成 ≥ 0.8（当前 %.1f）", cultureBonus)
        else
            local coordRate = manipCfg.coordinated.base_success * credMult
            coordDesc = string.format("%d AP / 固定 %d  成功率 %.0f%%",
                manipCfg.coordinated.ap, manipCfg.coordinated.fixed_cost,
                coordRate * 100)
        end
        table.insert(rows, ActionModals._TradeOption(
            "⚡ 联合操盘",
            coordDesc,
            C.accent_gold,
            function()
                ActionModals._ShowCoordinatedPicker(state)
            end,
            not coordUnlocked or coordCd > 0 or state.cash < manipCfg.coordinated.fixed_cost
        ))
    end

    ActionModals._ShowList("🏭 资产交易", rows)
end

function ActionModals._TradeOption(title, desc, accent, onClick, disabled)
    return UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderLeftWidth = 2,
        borderLeftColor = accent,
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                flexDirection = "column",
                gap = 2,
                children = {
                    UI.Label {
                        text = title,
                        fontSize = F.body,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = desc,
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                        whiteSpace = "normal",
                    },
                },
            },
            actionBtn("执行", accent, onClick, disabled),
        },
    }
end

function ActionModals._TradeNewMine(state)
    local cfg = Balance.TRADE.new_mine
    local cashCost = math.floor(cfg.cash * GameState.GetAssetPriceFactor(state))
    -- 检查矿山数量上限（基础 + 科技加成）
    local maxMines = (cfg.max_mines or 4) + (state.mine_slots_bonus or 0)
    if #state.mines >= maxMines then
        UI.Toast.Show(string.format("矿山已达上限（%d/%d）", #state.mines, maxMines),
            { variant = "warning", duration = 1.5 })
        return
    end
    if state.cash < cashCost or (state.ap.current + (state.ap.temp or 0)) < cfg.ap then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    if not GameState.SpendAP(state, cfg.ap) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.2 })
        return
    end
    state.cash = state.cash - cashCost
    local id = "mine_" .. tostring(state.turn_count) .. "_" .. tostring(math.random(1000, 9999))
    local region = state.regions[1]
    for _, r in ipairs(state.regions) do
        if r.id == "mine_district" then region = r; break end
    end
    -- 新矿使用独立储量，同时同步到 region
    local newReserve = cfg.base_reserve or 1500
    table.insert(state.mines, {
        id = id,
        name = "新矿井 #" .. (#state.mines + 1),
        region_id = region and region.id or "mine_district",
        level = 1,
        output_bonus = 0,
        active = true,
        reserve = newReserve,
        initial_reserve = newReserve,
    })
    -- 同步 region.gold_reserve（兼容显示）
    if region and region.resources then
        region.resources.gold_reserve = (region.resources.gold_reserve or 0) + newReserve
    end
    GameState.AddLog(state, string.format("[交易] 新矿开发完成，独立储量 %d", newReserve))
    UI.Toast.Show("新矿已建成", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._TradeNewCoalMine(state)
    if not state.local_coal_mine_unlocked then
        UI.Toast.Show("需要先研发电气化矿井", { variant = "warning", duration = 1.5 })
        return
    end

    local cfg = Balance.TRADE.local_coal_mine or {}
    local cashCost = math.floor((cfg.cash or 700) * GameState.GetAssetPriceFactor(state))
    local apCost = cfg.ap or 1
    local maxMines = (Balance.TRADE.new_mine.max_mines or 4) + (state.mine_slots_bonus or 0)
    if #state.mines >= maxMines then
        UI.Toast.Show(string.format("矿山已达上限（%d/%d）", #state.mines, maxMines),
            { variant = "warning", duration = 1.5 })
        return
    end
    if state.cash < cashCost or (state.ap.current + (state.ap.temp or 0)) < apCost then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    if not GameState.SpendAP(state, apCost) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.2 })
        return
    end

    state.cash = state.cash - cashCost
    local id = "coal_mine_" .. tostring(state.turn_count) .. "_" .. tostring(math.random(1000, 9999))
    local region = state.regions[1]
    for _, r in ipairs(state.regions) do
        if r.id == "industrial_town" then region = r; break end
    end
    local newReserve = cfg.base_reserve or 1500
    table.insert(state.mines, {
        id = id,
        name = "本地煤矿 #" .. (#state.mines + 1),
        region_id = region and region.id or "industrial_town",
        resource = "coal",
        level = 1,
        output_bonus = 0,
        active = true,
        reserve = newReserve,
        initial_reserve = newReserve,
    })
    GameState.AddLog(state, string.format("[交易] 本地煤矿开发完成，独立煤储量 %d", newReserve))
    UI.Toast.Show("本地煤矿已建成", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._TradeSellMine(state, mine, price)
    if not GameState.SpendAP(state, Balance.TRADE.sell_mine.ap) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.2 })
        return
    end
    state.cash = state.cash + price
    -- 从矿山数组移除
    local kept = {}
    for _, m in ipairs(state.mines) do
        if m ~= mine then table.insert(kept, m) end
    end
    state.mines = kept
    GameState.AddLog(state, string.format("[交易] 出售 %s，得 %d 克朗", mine.name, price))
    UI.Toast.Show("已出售 " .. mine.name, { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._TradeRaid(state, faction)
    local cfg = Balance.TRADE.raid_ai
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.recruit_blocked = cfg.recruit_block_duration
    faction.attitude = math.max(-100, faction.attitude - 10)
    GameState.AddLog(state, string.format("[交易] 破坏 %s 的招募渠道，%d 季内无法扩张",
        faction.name, cfg.recruit_block_duration))
    UI.Toast.Show("招募渠道已破坏", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._TradeMilitaryStrike(state, faction)
    local cfg = { ap = Balance.COMBAT.player_attack_ap, cash = Balance.COMBAT.player_attack_cash }
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    local ok, msg = Combat.PlayerAttack(state, faction.id)
    if ok then
        faction.attitude = math.max(-100, (faction.attitude or 0) - 20)
        UI.Toast.Show("突袭完成", { variant = "success", duration = 1.5 })
    else
        UI.Toast.Show(msg or "突袭失败", { variant = "error", duration = 1.5 })
    end
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 掠夺行动弹窗
-- ============================================================================
function ActionModals.ShowPlunder(state, accent)
    AudioManager.PlayUI("ui_modal_open")
    closeModal()

    local rows = {}
    local repTier = GameState.GetReputationTier(state)
    local repLabel = GameState.GetReputationLabel(repTier)
    local repColor = repTier <= 2 and C.accent_green or (repTier <= 3 and C.accent_amber or C.accent_red)

    -- 声誉状态栏
    table.insert(rows, UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = { 45, 30, 30, 255 },
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = repColor,
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Label {
                text = "声誉等级",
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Panel { flexGrow = 1 },
            UI.Label {
                text = string.format("%s（%d）", repLabel, state.reputation or 0),
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = repColor,
            },
        },
    })

    -- 声誉效果提示（仅非清白时显示）
    if repTier >= 2 then
        local penalty = GameState.GetTradePenalty(state)
        local effectText = string.format("交易加价 +%d%%", math.floor(penalty * 100))
        if repTier >= 4 then
            effectText = effectText .. "  AI攻击+20%"
        end
        if repTier >= 5 then
            effectText = effectText .. "  控制力-2/季"
        end
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 8,
            backgroundColor = { 60, 30, 30, 200 },
            borderRadius = S.radius_badge,
            children = {
                UI.Label {
                    text = "⚠ " .. effectText,
                    fontSize = F.label,
                    fontColor = C.accent_amber,
                },
            },
        })
    end

    -- 已夺取矿脉信息
    local veins = state.seized_veins or {}
    if #veins > 0 then
        local veinText = {}
        for i, v in ipairs(veins) do
            table.insert(veinText, string.format("矿脉%d：剩余 %d 季，每季 %d 克朗", i, v.remaining, v.gold_per_turn))
        end
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 8,
            backgroundColor = { 30, 45, 30, 200 },
            borderRadius = S.radius_badge,
            children = {
                UI.Label {
                    text = "⛏ " .. table.concat(veinText, "\n"),
                    fontSize = F.label,
                    fontColor = C.accent_green,
                    whiteSpace = "normal",
                },
            },
        })
    end

    -- 三个掠夺选项
    local plunderActions = {
        {
            key = "raid_caravan",
            title = "🗡️ 劫掠商队",
            desc = "截击过路商队，掠取现金",
            fn = function() ActionModals._PlunderRaidCaravan(state) end,
        },
        {
            key = "seize_vein",
            title = "⛏️ 夺取矿脉",
            desc = "强占 AI 矿产，获得临时矿脉",
            fn = function() ActionModals._PlunderSeizeVein(state) end,
        },
        {
            key = "extort_foreign",
            title = "💰 勒索外资",
            desc = "威胁外国资本索取赎金",
            fn = function() ActionModals._PlunderExtortForeign(state) end,
        },
    }

    for _, act in ipairs(plunderActions) do
        local cfg = Balance.PLUNDER[act.key]
        local cd = (state.plunder_cooldowns or {})[act.key] or 0
        local onCooldown = cd > 0
        local canPay = ActionModals._CanAfford(state, cfg)
        local disabled = onCooldown or not canPay
        local inflation = GameState.GetInflationFactor(state)
        local cashCost = math.floor(cfg.cash * inflation)

        local statusText
        if onCooldown then
            statusText = string.format("冷却中（%d 季）", cd)
        else
            statusText = string.format("%d AP / %d 克朗  声誉 %d", cfg.ap, cashCost, cfg.rep_cost)
        end

        table.insert(rows, ActionModals._TradeOption(
            act.title,
            act.desc .. "\n" .. statusText,
            onCooldown and C.text_muted or C.accent_red,
            act.fn,
            disabled
        ))
    end

    ActionModals._ShowList("⚔️ 掠夺行动", rows)
end

-- ============================================================================
-- 掠夺行动处理
-- ============================================================================
function ActionModals._PlunderRaidCaravan(state)
    local cfg = Balance.PLUNDER.raid_caravan
    local cd = (state.plunder_cooldowns or {}).raid_caravan or 0
    if cd > 0 then
        UI.Toast.Show(string.format("冷却中，还需 %d 季", cd), { variant = "warning", duration = 1.2 })
        return
    end
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    local ok, msg = Combat.RaidCaravan(state)
    if ok then
        UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
    else
        UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
    end
    closeModal()
    notifyChanged()
end

function ActionModals._PlunderSeizeVein(state)
    local cfg = Balance.PLUNDER.seize_vein
    local cd = (state.plunder_cooldowns or {}).seize_vein or 0
    if cd > 0 then
        UI.Toast.Show(string.format("冷却中，还需 %d 季", cd), { variant = "warning", duration = 1.2 })
        return
    end
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    local ok, msg = Combat.SeizeVein(state)
    if ok then
        UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
    else
        UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
    end
    closeModal()
    notifyChanged()
end

function ActionModals._PlunderExtortForeign(state)
    local cfg = Balance.PLUNDER.extort_foreign
    local cd = (state.plunder_cooldowns or {}).extort_foreign or 0
    if cd > 0 then
        UI.Toast.Show(string.format("冷却中，还需 %d 季", cd), { variant = "warning", duration = 1.2 })
        return
    end
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    local ok, msg = Combat.ExtortForeign(state)
    if ok then
        UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
    else
        UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
    end
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 市场操盘 — 股票选择器
-- ============================================================================

--- 单目标选择器（做多/做空操盘）
---@param state table
---@param mode string "pump"|"dump"
function ActionModals._ShowStockPicker(state, mode)
    closeModal()
    AudioManager.PlayUI("ui_modal_open")

    local isPump = (mode == "pump")
    local titleText = isPump and "📈 选择做多目标" or "📉 选择做空目标"
    local accentColor = isPump and C.accent_green or C.accent_red

    local rows = {}
    for _, stock in ipairs(state.stocks or {}) do
        local stockLocal = stock
        local maxShares = StockEngine.GetMaxShares(stock)
        local marketCap = stock.price * maxShares
        local cfg = isPump and Balance.MARKET_MANIPULATION.pump or Balance.MARKET_MANIPULATION.dump
        local baseCost = math.ceil(marketCap * cfg.cost_ratio)
        -- 外交总监折扣
        local discountKey = isPump and "pump" or "dump"
        local diplomBonus = GameState.GetPositionBonus(state, "diplomat")
        local discount = (diplomBonus > 0) and (Balance.MARKET_MANIPULATION.diplomat_discount[discountKey] or 0) or 0
        local actualCost = math.ceil(baseCost * (1 - discount))
        local finalCost = math.max(cfg.min_cash, actualCost)
        local canAfford = state.cash >= finalCost
            and (state.ap.current + (state.ap.temp or 0)) >= cfg.ap

        local costText = string.format("价格 %.2f  市值 %d\n投入 %d 克朗",
            stock.price, math.floor(marketCap), math.floor(finalCost))
        if discount > 0 then
            costText = costText .. string.format("（外交优惠 -%d%%）", math.floor(discount * 100))
        end

        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 2,
            borderLeftColor = accentColor,
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = {
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    flexDirection = "column",
                    gap = 2,
                    children = {
                        UI.Label {
                            text = (stock.name or stock.id),
                            fontSize = F.body,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                        },
                        UI.Label {
                            text = costText,
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                            whiteSpace = "normal",
                        },
                    },
                },
                actionBtn("选择", accentColor,
                    function()
                        closeModal()
                        ActionModals._ExecManipulation(state, mode, stockLocal.id)
                    end,
                    not canAfford
                ),
            },
        })
    end

    ActionModals._ShowList(titleText, rows)
end

--- 联合操盘双目标选择器
---@param state table
function ActionModals._ShowCoordinatedPicker(state)
    closeModal()
    AudioManager.PlayUI("ui_modal_open")

    -- 第一步：选择做多目标
    ActionModals._ShowCoordinatedStep1(state)
end

function ActionModals._ShowCoordinatedStep1(state)
    local rows = {}
    for _, stock in ipairs(state.stocks or {}) do
        local stockLocal = stock
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 2,
            borderLeftColor = C.accent_green,
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = {
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = (stock.name or stock.id),
                            fontSize = F.body,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                        },
                        UI.Label {
                            text = string.format("当前价格 %.2f", stock.price),
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                        },
                    },
                },
                actionBtn("做多", C.accent_green,
                    function()
                        closeModal()
                        ActionModals._ShowCoordinatedStep2(state, stockLocal.id)
                    end,
                    false
                ),
            },
        })
    end

    ActionModals._ShowList("⚡ 联合操盘 — 选择做多目标", rows)
end

function ActionModals._ShowCoordinatedStep2(state, pumpStockId)
    local rows = {}
    local pumpStock = StockEngine.Find(state, pumpStockId)
    local pumpName = pumpStock and pumpStock.name or pumpStockId

    -- 提示已选做多目标
    table.insert(rows, UI.Panel {
        width = "100%",
        padding = 8,
        backgroundColor = { 30, 50, 30, 200 },
        borderRadius = S.radius_badge,
        children = {
            UI.Label {
                text = string.format("📈 做多目标：%s", pumpName),
                fontSize = F.label,
                fontColor = C.accent_green,
            },
        },
    })

    for _, stock in ipairs(state.stocks or {}) do
        if stock.id ~= pumpStockId then
            local stockLocal = stock
            table.insert(rows, UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderLeftWidth = 2,
                borderLeftColor = C.accent_red,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        children = {
                            UI.Label {
                                text = (stock.name or stock.id),
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = string.format("当前价格 %.2f", stock.price),
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                        },
                    },
                    actionBtn("做空", C.accent_red,
                        function()
                            closeModal()
                            ActionModals._ExecCoordinated(state, pumpStockId, stockLocal.id)
                        end,
                        false
                    ),
                },
            })
        end
    end

    ActionModals._ShowList("⚡ 联合操盘 — 选择做空目标", rows)
end

--- 执行单目标操盘
function ActionModals._ExecManipulation(state, mode, stockId)
    local ok, msg
    if mode == "pump" then
        ok, msg = StockEngine.MarketPump(state, stockId)
    else
        ok, msg = StockEngine.MarketDump(state, stockId)
    end
    if ok then
        UI.Toast.Show(msg or "操盘成功", { variant = "success", duration = 2.0 })
    else
        UI.Toast.Show(msg or "操盘失败", { variant = "error", duration = 2.0 })
    end
    notifyChanged()
end

--- 执行联合操盘
function ActionModals._ExecCoordinated(state, pumpStockId, dumpStockId)
    local ok, msg = StockEngine.CoordinatedOp(state, pumpStockId, dumpStockId)
    if ok then
        UI.Toast.Show(msg or "联合操盘成功", { variant = "success", duration = 2.0 })
    else
        UI.Toast.Show(msg or "联合操盘失败", { variant = "error", duration = 2.0 })
    end
    notifyChanged()
end

-- ============================================================================
-- 通用列表弹窗
-- ============================================================================
function ActionModals._ShowList(title, rows)
    currentModal_ = UI.Modal {
        title = title,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            Config.ConsumeTap()
            currentModal_ = nil
            self:Destroy()
        end,
    }
    local content = UI.ScrollView {
        width = "100%",
        maxHeight = 480,
        flexShrink = 1,
        bounces = false,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                children = rows,
            },
        },
    }
    currentModal_:AddContent(content)
    -- Modal 必须加入 UI 树才能渲染
    if uiRoot_ then
        uiRoot_:AddChild(currentModal_)
    end
    currentModal_:Open()
end

return ActionModals

