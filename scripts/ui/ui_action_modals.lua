-- ============================================================================
-- 快速操作弹窗集合：科技 / 情报 / 外交 / 资产交易
-- 每个弹窗呈现对应模块的可用操作，玩家点击执行
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local Tech = require("systems.tech")
local TechData = require("data.tech_data")
local Combat = require("systems.combat")
local RegionsData = require("data.regions_data")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local ActionModals = {}

local currentModal_ = nil
local onStateChanged_ = nil
local stateRef_ = nil

--- 设置回调
function ActionModals.SetCallbacks(state, onChanged)
    stateRef_ = state
    onStateChanged_ = onChanged
end

local function closeModal()
    if currentModal_ then
        currentModal_:Close()
        currentModal_ = nil
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
        onPointerUp = function(self)
            if not disabled then onClick() end
        end,
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
-- 科技研发弹窗
-- ============================================================================
function ActionModals.ShowTechnology(state, accent)
    closeModal()

    local rows = {}

    -- 进行中
    if state.tech and state.tech.in_progress then
        local ip = state.tech.in_progress
        local t = TechData.GetById(ip.id)
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 2,
            borderLeftColor = accent,
            flexDirection = "column",
            gap = 4,
            children = {
                UI.Label {
                    text = "⏳ 研发中：" .. (t and t.name or ip.id),
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = accent,
                },
                UI.ProgressBar {
                    value = ip.progress / math.max(1, ip.total),
                    width = "100%", height = 6,
                    borderRadius = 3,
                    trackColor = C.bg_surface,
                    fillColor = accent,
                },
                UI.Label {
                    text = string.format("进度 %d / %d 季", ip.progress, ip.total),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
            },
        })
    end

    -- 已研发
    if state.tech and next(state.tech.researched) then
        local names = {}
        for id, _ in pairs(state.tech.researched) do
            local t = TechData.GetById(id)
            if t then table.insert(names, (t.icon or "") .. t.name) end
        end
        table.insert(rows, UI.Label {
            text = "✓ 已掌握：" .. table.concat(names, "、"),
            fontSize = F.body_minor,
            fontColor = C.text_secondary,
            whiteSpace = "normal",
        })
    end

    -- 可研发
    local available = Tech.GetAvailable(state)
    if #available == 0 and not (state.tech and state.tech.in_progress) then
        table.insert(rows, UI.Label {
            text = "所有科技均已研发完成或前置未满足",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
        })
    end
    for _, t in ipairs(available) do
        local disabled = state.cash < t.cost
            or state.ap.current + (state.ap.temp or 0) < Balance.TECH.base_research_ap
            or (state.tech and state.tech.in_progress)
        local tCopy = t
        table.insert(rows, listItem({
            UI.Label {
                text = t.icon or "🔬",
                fontSize = 22,
                pointerEvents = "none",
            },
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                flexDirection = "column",
                gap = 2,
                children = {
                    UI.Label {
                        text = t.name,
                        fontSize = F.body,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = t.desc,
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                        whiteSpace = "normal",
                    },
                    UI.Label {
                        text = string.format("花费 %d 克朗 / %d AP / %d 季",
                            t.cost, Balance.TECH.base_research_ap, t.turns),
                        fontSize = F.label,
                        fontColor = C.text_muted,
                    },
                },
            },
            actionBtn("研发", accent, function()
                local ok, msg = Tech.Start(state, tCopy.id)
                UI.Toast.Show(msg, {
                    variant = ok and "success" or "error", duration = 1.5,
                })
                if ok then
                    closeModal()
                    notifyChanged()
                end
            end, disabled),
        }))
    end

    ActionModals._ShowList("🔬 科技研发", rows)
end

-- ============================================================================
-- 情报行动弹窗
-- ============================================================================
function ActionModals.ShowIntelligence(state, accent)
    closeModal()

    local rows = {}
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction  -- 闭包捕获
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
                        actionBtn("渗透",
                            C.accent_amber,
                            function() ActionModals._IntelInfiltrate(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.INTEL.infiltrate)),
                        actionBtn("收买",
                            C.accent_green,
                            function() ActionModals._IntelBribe(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.INTEL.bribe)),
                    },
                },
            },
        })
    end

    ActionModals._ShowList("👁️ 情报行动", rows)
end

function ActionModals._CanAfford(state, cfg)
    return state.cash >= (cfg.cash or 0)
        and (state.ap.current + (state.ap.temp or 0)) >= (cfg.ap or 0)
end

--- 原子扣费：同时扣 AP 与现金，任一不够都全部回滚
function ActionModals._Spend(state, cfg)
    if not ActionModals._CanAfford(state, cfg) then return false end
    local apOk = GameState.SpendAP(state, cfg.ap or 0)
    if not apOk then return false end
    state.cash = state.cash - (cfg.cash or 0)
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
    GameState.AddLog(state, string.format("[情报] 侦察 %s：现金 %d，势力 %d",
        faction.name, faction.cash, faction.power))
    UI.Toast.Show("侦察完成，情报已更新", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._IntelInfiltrate(state, faction)
    local cfg = Balance.INTEL.infiltrate
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.growth_mod = cfg.growth_debuff
    faction.growth_mod_remaining = cfg.duration
    GameState.AddLog(state, string.format("[情报] 渗透 %s，%d 季内增长 %.0f%%",
        faction.name, cfg.duration, cfg.growth_debuff * 100))
    UI.Toast.Show("渗透成功", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._IntelBribe(state, faction)
    local cfg = Balance.INTEL.bribe
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.attitude = math.min(100, faction.attitude + cfg.attitude_gain)
    GameState.AddLog(state, string.format("[情报] 收买 %s，态度 +%d → %d",
        faction.name, cfg.attitude_gain, faction.attitude))
    UI.Toast.Show("收买完成", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 外交弹窗
-- ============================================================================
function ActionModals.ShowDiplomacy(state, accent)
    closeModal()

    local rows = {}
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction
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
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    children = {
                        actionBtn("送礼",
                            C.accent_green,
                            function() ActionModals._DiploGift(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.gift)),
                        actionBtn("协议",
                            C.accent_blue,
                            function() ActionModals._DiploTreaty(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.treaty)),
                        actionBtn("敌对",
                            C.accent_red,
                            function() ActionModals._DiploHostile(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.hostile)),
                    },
                },
            },
        })
    end

    ActionModals._ShowList("🤝 政治外交", rows)
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
    if faction.attitude < cfg.attitude_req then
        UI.Toast.Show(string.format("需要态度 ≥ %d 才能签订协议", cfg.attitude_req),
            { variant = "warning", duration = 1.5 })
        return
    end
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
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
    closeModal()

    local rows = {}

    -- 开发新矿
    table.insert(rows, ActionModals._TradeOption(
        "⛏️ 开发新矿区",
        string.format("投入 %d 克朗 / %d AP 建立一座新矿",
            Balance.TRADE.new_mine.cash, Balance.TRADE.new_mine.ap),
        accent,
        function() ActionModals._TradeNewMine(state) end,
        not ActionModals._CanAfford(state, Balance.TRADE.new_mine)
    ))

    -- 出售矿山
    for _, mine in ipairs(state.mines) do
        if mine.active and #state.mines > 1 then
            local mineLocal = mine
            local salePrice = mine.level * Balance.TRADE.sell_mine.cash_per_level
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
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction
        table.insert(rows, ActionModals._TradeOption(
            "⚔ 资本攻击：" .. faction.name,
            string.format("花 %d 克朗削弱 AI 资金 %d / 势力 -%d",
                Balance.TRADE.raid_ai.cash,
                Balance.TRADE.raid_ai.ai_cash_loss,
                Balance.TRADE.raid_ai.power_loss),
            accent,
            function() ActionModals._TradeRaid(state, factionLocal) end,
            not ActionModals._CanAfford(state, Balance.TRADE.raid_ai)
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
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    local id = "mine_" .. tostring(state.turn_count) .. "_" .. tostring(math.random(1000, 9999))
    -- 扩展矿区资源
    local region = state.regions[1]  -- 放在主矿区上
    for _, r in ipairs(state.regions) do
        if r.id == "mine_district" then region = r; break end
    end
    if region and region.resources then
        region.resources.gold_reserve = (region.resources.gold_reserve or 0) + cfg.base_reserve
    end
    table.insert(state.mines, {
        id = id,
        name = "新矿井 #" .. (#state.mines + 1),
        region_id = region and region.id or "mine_district",
        level = 1,
        output_bonus = 0,
        active = true,
    })
    GameState.AddLog(state, string.format("[交易] 新矿开发完成，储量 +%d", cfg.base_reserve))
    UI.Toast.Show("新矿已建成", { variant = "success", duration = 1.5 })
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
    faction.cash = math.max(0, faction.cash - cfg.ai_cash_loss)
    faction.power = math.max(0, faction.power - cfg.power_loss)
    faction.attitude = math.max(-100, faction.attitude - 15)
    GameState.AddLog(state, string.format("[交易] 对 %s 发动资本攻击：现金 -%d 势力 -%d",
        faction.name, cfg.ai_cash_loss, cfg.power_loss))
    UI.Toast.Show("资本攻击成功", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 通用列表弹窗
-- ============================================================================
function ActionModals._ShowList(title, rows)
    currentModal_ = UI.Modal {
        isOpen = true,
        title = title,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
    }
    local content = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 8,
        children = rows,
    }
    currentModal_:AddContent(content)
    currentModal_:Open()
end

return ActionModals
