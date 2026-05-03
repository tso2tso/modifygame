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

