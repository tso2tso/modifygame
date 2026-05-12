-- ============================================================================
-- 世界页 UI v3：严格遵循 sarajevo_dynasty_ui_spec v1.1 §8.5
-- 子Tab系统（地图 | 关系 | 势力 | 报告）+ 节点信息抽屉
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local RegionsData = require("data.regions_data")
local MapTilesData = require("data.map_tiles_data")
local MapWidget = require("ui.ui_map_widget")
local GrandPowers = require("systems.grand_powers")
local PlayerActionsGP = require("systems.player_actions_gp")
local ForeignOps = require("systems.foreign_ops")
local EuropeData = require("data.europe_data")
local ActionModals = require("ui.ui_action_modals")
-- TradePanel 已迁移至市场页（ui_market.lua）
local ExpeditionPanel = require("ui.ui_expedition")
local Trade = require("systems.trade")
local Expedition = require("systems.expedition")
local TradeRoutesData = require("data.trade_routes_data")
local BE = Balance.EXPEDITION

local FactionsPanel = require("ui.ui_factions")
local ReportPanel = require("ui.ui_report")
local VenturePanel = require("ui.ui_venture")
local Venture = require("systems.venture")
local BV = Balance.VENTURE

-- 构建国家ID→中文名映射表
local _countryLabels = {}
if EuropeData.COUNTRIES then
    for _, c in ipairs(EuropeData.COUNTRIES) do
        if c.id and c.label then _countryLabels[c.id] = c.label end
    end
end

--- 将 AI 势力 ID 翻译为中文名称（优先从 state 取真实派系名）
local function _ResolveAIName(aiId, state)
    if state and state.ai_factions then
        for _, f in ipairs(state.ai_factions) do
            if f.id == aiId and f.name then return f.name end
        end
    end
    if aiId == "local_clan" then return "本地望族" end
    if aiId == "foreign_capital" then return "外国资本" end
    if aiId == "armed_group" then return "武装集团" end
    if _countryLabels[aiId] then return _countryLabels[aiId] end
    return aiId  -- fallback: 原始 ID
end

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local WorldPage = {}

-- ============================================================================
-- 模块状态
-- ============================================================================

---@type table
local stateRef_ = nil
---@type table
local callbacksRef_ = nil
---@type table
local mapWidget_ = nil
---@type table
local contentRoot_ = nil
---@type table
local tabContentPanel_ = nil
---@type table
local drawerPanel_ = nil
---@type string
local activeSubTab_ = "map"
---@type string|nil
local selectedNodeId_ = nil

--- 设置 UI 根节点（报告页 Modal 需要挂载到 UI 树）
function WorldPage.SetRoot(root)
    ReportPanel.SetRoot(root)
end

--- 标记势力预计算数据为脏（在 onStateChanged / 页面重建时调用）
function WorldPage.InvalidatePrecomputed()
    FactionsPanel.InvalidatePrecomputed()
end

--- 新游戏/读档时重置页面状态（清除选中节点和子标签）
function WorldPage.Reset()
    selectedNodeId_ = nil
    activeSubTab_ = "map"
    FactionsPanel.Reset()
    ReportPanel.Reset()
end

-- 子 Tab 定义（远征始终显示，贸易已迁移至市场页）
local SUB_TABS = {
    { id = "map",        label = "地图" },
    { id = "factions",   label = "势力" },
    { id = "report",     label = "报告" },
    { id = "expedition", label = "远征" },
    { id = "venture",    label = "商路" },
}

--- 构建当前可见的子标签列表（远征始终显示，未解锁时标记 locked）
---@param state table
---@return table[]
local function _GetVisibleSubTabs(state)
    local unlocked = state.unlocked_features or {}
    local tabs = {}
    for _, t in ipairs(SUB_TABS) do
        local entry = { id = t.id, label = t.label }
        if t.id == "expedition" and not unlocked["expedition"] then
            entry.locked = true
        elseif t.id == "venture" and not unlocked["venture"] then
            entry.locked = true
        end
        table.insert(tabs, entry)
    end
    return tabs
end

-- ============================================================================
-- 入口
-- ============================================================================

--- 创建世界页完整内容
---@param state table
---@param callbacks table
---@return table widget
function WorldPage.Create(state, callbacks)
    stateRef_ = state
    callbacksRef_ = callbacks or {}
    MapTilesData.EnsureState(state)
    MapTilesData.SyncTilesFromRegions(state)
    -- 页面重建时保留已选中的节点和子标签（避免操作后跳回默认区域）
    if not selectedNodeId_ then
        selectedNodeId_ = state.map_tiles[1] and state.map_tiles[1].id
            or (state.regions[1] and state.regions[1].id or nil)
    end
    activeSubTab_ = activeSubTab_ or "map"
    WorldPage.InvalidatePrecomputed()
    return WorldPage._BuildContent(state)
end

function WorldPage._BuildContent(state)
    -- 子 Tab 内容区（动态更新）
    tabContentPanel_ = UI.Panel {
        id = "worldTabContent",
        width = "100%",
        flexDirection = "column",
        gap = 0,
        flexGrow = 1,
        flexShrink = 1,
        overflow = "hidden",
    }

    -- 组装页面
    contentRoot_ = UI.Panel {
        id = "worldContent",
        width = "100%",
        flexDirection = "column",
        gap = 0,
        overflow = "hidden",
        children = {
            -- 子 Tab 选择器
            WorldPage._CreateSubTabBar(),
            -- 子 Tab 内容
            tabContentPanel_,
        },
    }

    -- 初始渲染地图子页
    WorldPage._SwitchSubTab(state, activeSubTab_)

    return contentRoot_
end

-- ============================================================================
-- 子 Tab 选择器
-- ============================================================================

function WorldPage._CreateSubTabBar()
    local visibleTabs = _GetVisibleSubTabs(stateRef_ or {})
    local tabButtons = {}
    for _, tab in ipairs(visibleTabs) do
        local isActive = (tab.id == activeSubTab_)
        local isLocked = tab.locked
        local displayLabel = isLocked and ("🔒 " .. tab.label) or tab.label
        table.insert(tabButtons, UI.Button {
            text = displayLabel,
            fontSize = F.body,
            fontWeight = isActive and "bold" or "normal",
            fontColor = isLocked and C.text_tertiary
                or (isActive and C.accent_gold or C.text_muted),
            backgroundColor = isActive and C.bg_elevated or { 0, 0, 0, 0 },
            borderRadius = S.radius_btn,
            paddingHorizontal = 14,
            paddingVertical = 6,
            flexGrow = 1,
            onClick = Config.ClickGuard(function()
                if activeSubTab_ ~= tab.id then
                    activeSubTab_ = tab.id
                    WorldPage._SwitchSubTab(stateRef_, tab.id)
                    WorldPage._RefreshTabBar()
                end
            end),
        })
    end

    return UI.Panel {
        id = "subTabBar",
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        padding = 4,
        flexDirection = "row",
        gap = 2,
        children = tabButtons,
    }
end

--- 刷新 Tab 栏激活状态
function WorldPage._RefreshTabBar()
    if not contentRoot_ then return end
    -- 清除后重新添加子节点（Tab 栏 + 内容区）
    contentRoot_:ClearChildren()
    contentRoot_:AddChild(WorldPage._CreateSubTabBar())
    contentRoot_:AddChild(tabContentPanel_)
end

-- ============================================================================
-- 锁定占位面板（功能未解锁时显示）
-- ============================================================================

---@param title string 功能名称
---@param subtitle string 解锁途径简述
---@param conditions string[] 具体解锁条件列表
---@return table widget
function WorldPage._BuildLockedPanel(title, subtitle, conditions)
    local condRows = {}
    for _, cond in ipairs(conditions) do
        table.insert(condRows, UI.Label {
            text = "• " .. cond,
            fontSize = F.body,
            fontColor = C.text_secondary,
        })
    end
    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        justifyContent = "center",
        alignItems = "center",
        paddingHorizontal = 32,
        paddingVertical = 48,
        gap = 12,
        children = {
            UI.Label { text = "🔒", fontSize = 48 },
            UI.Label {
                text = title,
                fontSize = F.title,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Label {
                text = subtitle,
                fontSize = F.body,
                fontColor = C.text_muted,
                textAlign = "center",
            },
            UI.Panel {
                width = "80%",
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                padding = S.card_padding,
                gap = 6,
                flexDirection = "column",
                children = (function()
                    local c = {}
                    table.insert(c, UI.Label {
                        text = "解锁条件",
                        fontSize = F.body_minor,
                        fontWeight = "bold",
                        fontColor = C.text_muted,
                    })
                    for _, row in ipairs(condRows) do
                        table.insert(c, row)
                    end
                    return c
                end)(),
            },
        },
    }
end

-- ============================================================================
-- 子 Tab 切换
-- ============================================================================

function WorldPage._SwitchSubTab(state, tabId)
    if not tabContentPanel_ then return end
    tabContentPanel_:ClearChildren()

    if tabId == "map" then
        WorldPage._BuildMapTab(state)
    elseif tabId == "factions" then
        tabContentPanel_:AddChild(FactionsPanel.Build(state, callbacksRef_))
    elseif tabId == "report" then
        tabContentPanel_:AddChild(ReportPanel.Build(state, callbacksRef_))
    elseif tabId == "expedition" then
        local unlocked = state.unlocked_features
            and state.unlocked_features["expedition"]
        if unlocked then
            local panel = ExpeditionPanel.Build(state, callbacksRef_)
            tabContentPanel_:AddChild(panel)
        else
            tabContentPanel_:AddChild(WorldPage._BuildLockedPanel(
                "军事远征",
                "获得称号「幕后执政」后解锁",
                {
                    "三大区域控制度均 ≥ 70",
                    "武装力量 ≥ 15 人",
                }
            ))
        end
    elseif tabId == "venture" then
        local unlocked = state.unlocked_features
            and state.unlocked_features["venture"]
        if unlocked then
            local panel = VenturePanel.Build(state, callbacksRef_)
            tabContentPanel_:AddChild(panel)
        else
            tabContentPanel_:AddChild(WorldPage._BuildLockedPanel(
                "商业远征",
                "研究科技后解锁",
                {
                    "研究「金融网络」科技（经济B线第5层）",
                }
            ))
        end
    end
end

-- ============================================================================
-- 地图子页 — §8.5 核心
-- ============================================================================

--- 计算前线数据并传递给地图控件
function WorldPage._UpdateFrontLineData(state)
    if not mapWidget_ then return end
    if not state._gp_initialized or not state.powers then
        mapWidget_:SetFrontLineData(nil)
        return
    end

    local frontData = {}
    local phaseIdx = 0
    for powerId, power in pairs(state.powers) do
        if power.active then
            local fronts = GrandPowers.GetFrontLines(state, powerId)
            for _, fl in ipairs(fronts) do
                if fl.status == "active" then
                    phaseIdx = phaseIdx + 1
                    table.insert(frontData, {
                        from_id = powerId,
                        to_id   = fl.target_id,
                        status  = fl.status,
                        _phase  = phaseIdx * 0.7,
                    })
                end
            end
        end
    end

    mapWidget_:SetFrontLineData(#frontData > 0 and frontData or nil)
end

function WorldPage._BuildMapTab(state)
    -- 1. 地图控件
    mapWidget_ = MapWidget {
        width = "100%",
        height = 420,
        onRegionSelect = function(regionId)
            selectedNodeId_ = regionId
            WorldPage._RefreshDrawer(state)
        end,
    }
    mapWidget_:SetRegions(state.regions)
    mapWidget_:SetMapTiles(state.map_tiles)
    mapWidget_:SetSelected(selectedNodeId_)
    mapWidget_:UpdateUnlocks(state)
    mapWidget_:SetEuropeState(state.europe)
    mapWidget_:SetForeignOps(state.foreign_ops)
    WorldPage._UpdateFrontLineData(state)

    -- 设置时代
    local era = Config.GetEraByYear(state.year)
    if era then
        mapWidget_:SetEra(era.id)
    end

    -- 2. 节点信息抽屉（底部滑出面板）
    drawerPanel_ = UI.Panel {
        id = "nodeDrawer",
        width = "100%",
        flexDirection = "column",
        gap = 0,
    }
    WorldPage._RefreshDrawer(state)

    -- 组装
    tabContentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        paddingTop = S.card_gap,
        paddingBottom = 12,
        children = {
            mapWidget_,
            drawerPanel_,
        },
    })
end

-- ============================================================================
-- 节点信息抽屉 — §8.5 节点交互
-- ============================================================================

function WorldPage._RefreshDrawer(state)
    if not drawerPanel_ then return end
    drawerPanel_:ClearChildren()

    if not selectedNodeId_ then
        drawerPanel_:AddChild(UI.Panel {
            width = "100%",
            padding = S.card_padding,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            children = {
                UI.Label {
                    text = "点击地图节点查看详情",
                    fontSize = F.body,
                    fontColor = C.text_muted,
                },
            },
        })
        return
    end

    -- 查找 hex 模块和关联区域数据
    local tile = MapTilesData.GetTile(state, selectedNodeId_)
    local region = nil
    for _, r in ipairs(state.regions) do
        if r.id == (tile and tile.region_id or selectedNodeId_) then
            region = r
            break
        end
    end
    if not region and not tile then return end

    drawerPanel_:AddChild(WorldPage._CreateNodeDrawer(state, region, tile))
end

--- 创建节点信息抽屉 — 遵循 §8.5 节点信息抽屉规范
function WorldPage._CreateNodeDrawer(state, region, tile)
    if not region and tile then
        local isPlayer = tile.controller == "player"
        local aiPresence = {}
        if not isPlayer and tile.controller and tile.controller ~= "contested" and tile.controller ~= "neutral" then
            aiPresence[tile.controller] = 100
        end
        region = {
            id = tile.id,
            name = tile.label,
            icon = tile.type == "capital" and "◆" or "⬡",
            type = tile.type,
            control = isPlayer and 100 or 0,
            security = 3,
            population = tile.population or 0,
            development = tile.development or 1,
            culture = tile.culture or 0,
            -- influence 已合并到 control
            resources = {},
            ai_presence = aiPresence,
        }
    end
    local displayName = tile and tile.label or region.name
    local CONTROLLER_LABELS = {
        player          = "玩家",
        local_clan      = "本地望族",      -- fallback（state 不可用时）
        foreign_capital = "外国资本",      -- fallback（state 不可用时）
        armed_group     = "武装集团",
        neutral         = "中立",
        contested       = "争议",
    }
    -- 从 state 取真实派系名称（米洛舍维奇家族、维也纳矿业公司等），覆盖 fallback
    if state and state.ai_factions then
        for _, f in ipairs(state.ai_factions) do
            if f.id and f.name then
                CONTROLLER_LABELS[f.id] = f.name
            end
        end
    end
    local controllerText = tile and (CONTROLLER_LABELS[tile.controller] or _countryLabels[tile.controller] or CONTROLLER_LABELS.contested) or nil
    local security = GameState.CalcRegionSecurity(state, region)
    local secColor = security <= 2 and C.accent_red
        or (security >= 4 and C.accent_green or C.accent_amber)
    local ctrlColor = region.control >= 60 and C.accent_green
        or (region.control >= 30 and C.accent_amber or C.accent_red)

    -- 节点类型 Badge 文本
    local typeBadge = "未知"
    local typeColors = { C.text_muted[1], C.text_muted[2], C.text_muted[3] }
    if region.type == "mine" then
        typeBadge = "矿山区"; typeColors = { 212, 175, 55 }
    elseif region.type == "industrial" then
        typeBadge = "工业城"; typeColors = { 58, 107, 138 }
    elseif region.type == "capital" then
        typeBadge = "首都"; typeColors = { 192, 57, 43 }
    elseif region.type == "port" then
        typeBadge = "港口"; typeColors = { 39, 174, 96 }
    elseif region.type == "border" then
        typeBadge = "边境"; typeColors = { 107, 94, 78 }
    elseif region.type == "cultural" then
        typeBadge = "文化"; typeColors = { 243, 156, 18 }
    elseif region.type == "strategic" then
        typeBadge = "山口"; typeColors = { 44, 62, 80 }
    elseif region.type == "rail" then
        typeBadge = "铁路"; typeColors = { 46, 204, 113 }
    end

    -- 主导控制方
    local dominantText = "中立"
    if region.control >= 50 then
        dominantText = "玩家控制"
    else
        local maxAI, maxAIName = 0, nil
        if region.ai_presence then
            for aiId, presence in pairs(region.ai_presence) do
                if presence > maxAI then
                    maxAI = presence
                    maxAIName = _ResolveAIName(aiId, state)
                end
            end
        end
        if maxAIName and maxAI >= 40 then
            dominantText = maxAIName .. "控制"
        else
            dominantText = "争议区域"
        end
    end

    -- 控制比例条目
    local controlRows = {}
    -- 玩家
    table.insert(controlRows, WorldPage._ControlBar(
        "玩家", region.control, { 41, 128, 185 }))
    -- AI 势力
    if region.ai_presence then
        for aiId, presence in pairs(region.ai_presence) do
            local aiName = _ResolveAIName(aiId, state)
            local aiColor = aiId == "local_clan" and { 139, 69, 19 }
                or (aiId == "foreign_capital" and { 39, 174, 96 }
                or { 44, 62, 80 })
            table.insert(controlRows, WorldPage._ControlBar(
                aiName, presence, aiColor))
        end
    end
    -- 中立份额
    local totalUsed = region.control
    if region.ai_presence then
        for _, p in pairs(region.ai_presence) do totalUsed = totalUsed + p end
    end
    local neutralPct = math.max(0, 100 - totalUsed)
    if neutralPct > 0 then
        table.insert(controlRows, WorldPage._ControlBar(
            "中立", neutralPct, { 110, 110, 110 }))
    end

    -- 资源行
    local resourceRows = {}
    if region.resources then
        local resMap = {
            gold_reserve   = { name = "金矿储量", icon = "Au" },
            copper_reserve = { name = "铜矿储量", icon = "Cu" },
            coal_reserve   = { name = "煤炭储量", icon = "C" },
            steel_capacity = { name = "钢铁产能", icon = "Fe" },
        }
        for resKey, resVal in pairs(region.resources) do
            if resMap[resKey] and resVal > 0 then
                table.insert(resourceRows, WorldPage._InfoRow(
                    resMap[resKey].icon .. " " .. resMap[resKey].name,
                    Config.FormatNumber(resVal),
                    C.accent_gold))
            end
        end
    end

    -- 外国矿资源（已侦察或正在开采）
    if tile and tile.country_id ~= "bosnia" then
        local fmr = MapTilesData.FOREIGN_MINE_RESOURCES[tile.id]
        local fo = state.foreign_ops or {}
        local isScouted = fo.scouted and fo.scouted[tile.id]
        local isActive = fo.active and fo.active[tile.id]
        if fmr and (isScouted or isActive) then
            local FOREIGN_RES_MAP = {
                gold   = { name = "金矿储量", icon = "Au" },
                copper = { name = "铜矿储量", icon = "Cu" },
                coal   = { name = "煤炭储量", icon = "C" },
            }
            local resSource = isActive and (fo.active[tile.id].reserve or fmr) or fmr
            for _, rk in ipairs({ "gold", "copper", "coal" }) do
                local rv = resSource[rk] or 0
                if rv > 0 and FOREIGN_RES_MAP[rk] then
                    local resColor = isActive and { 46, 204, 113, 255 } or C.accent_amber
                    table.insert(resourceRows, WorldPage._InfoRow(
                        FOREIGN_RES_MAP[rk].icon .. " " .. FOREIGN_RES_MAP[rk].name,
                        Config.FormatNumber(rv),
                        resColor))
                end
            end
            if isActive then
                local dmgPct = math.floor((fo.active[tile.id].damage or 0) * 100)
                local effPct = 100 - dmgPct
                table.insert(resourceRows, WorldPage._InfoRow(
                    "⚙ 产出效率", effPct .. "%",
                    dmgPct > 20 and C.accent_red or C.accent_green))
            end
        elseif fmr and not isScouted and not isActive then
            table.insert(resourceRows, WorldPage._InfoRow(
                "? 未侦察", "需先侦察矿产", C.text_muted))
        end
    end

    -- ── 外国 tile 占领状态检测（提前到操作按钮前，供后续使用）──
    local isForeignTile = tile and tile.country_id and tile.country_id ~= "bosnia"
    local isOccupied = false
    local occupationInfo = nil  -- { income_per_turn, maintenance, since_turn, ... }
    if isForeignTile and state.expeditions and state.expeditions.occupied_countries then
        for _, occ in ipairs(state.expeditions.occupied_countries) do
            if occ.country_id == tile.country_id then
                isOccupied = true
                occupationInfo = occ
                break
            end
        end
    end

    -- 操作按钮
    local actionChildren = {}
    if (region.type == "mine" or region.type == "industrial") and not isForeignTile then
        table.insert(actionChildren, UI.Button {
            text = "前往产业页管理",
            fontSize = F.label,
            fontColor = C.accent_gold,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_btn,
            borderWidth = 1,
            borderColor = C.border_gold,
            paddingHorizontal = 10,
            paddingVertical = 6,
            flexGrow = 1,
            onClick = Config.ClickGuard(function()
                if callbacksRef_ and callbacksRef_.onSwitchTab then
                    callbacksRef_.onSwitchTab("industry")
                end
            end),
        })
    end
    if (not tile) or tile.region_id then
        local infiltrateAP = 2  -- TODO: 提取到 Balance 配置（当前硬编码）
        local alreadyFull = (region.control or 0) >= 100
        local canInfiltrate = not alreadyFull
            and (state.ap.current + (state.ap.temp or 0)) >= infiltrateAP
        local btnText = alreadyFull
            and string.format("%s 已完全控制", region.name)
            or string.format("渗透%s（%dAP）", region.name, infiltrateAP)
        table.insert(actionChildren, UI.Button {
            text = btnText,
            fontSize = F.label,
            fontColor = canInfiltrate and C.text_primary or C.text_muted,
            backgroundColor = canInfiltrate and C.paper_mid or C.bg_elevated,
            borderRadius = S.radius_btn,
            paddingHorizontal = 10,
            paddingVertical = 6,
            flexGrow = 1,
            disabled = not canInfiltrate,
            onClick = Config.ClickGuard(function(self)
                self.props.disabled = true
                WorldPage._DoPoliticalInfiltration(state, region)
            end),
        })
    end

    -- 外国矿操作按钮（侦察 / 开采 / 重建）
    if tile and tile.country_id ~= "bosnia"
       and MapTilesData.FOREIGN_MINE_RESOURCES[tile.id] then
        local canScout, scoutReason = ForeignOps.CanScout(state, tile.id)
        local canExploit, exploitReason = ForeignOps.CanExploit(state, tile.id)
        local canRebuild, rebuildReason = ForeignOps.CanRebuild(state, tile.id)
        local fo = state.foreign_ops or {}
        local isScouted = fo.scouted and fo.scouted[tile.id]
        local isActive = fo.active and fo.active[tile.id]
        local isScouting = fo.scouting and fo.scouting.tile_id == tile.id
        local BFO = Balance.FOREIGN_OPS

        if isScouting then
            local rem = fo.scouting.remaining or 0
            table.insert(actionChildren, UI.Button {
                text = "侦察中…（剩余" .. rem .. "回合）",
                fontSize = F.label,
                fontColor = C.text_muted,
                backgroundColor = C.bg_elevated,
                borderRadius = S.radius_btn,
                paddingHorizontal = 10,
                paddingVertical = 6,
                flexGrow = 1,
                disabled = true,
            })
        elseif not isScouted and not isActive then
            table.insert(actionChildren, UI.Button {
                text = string.format("侦察矿产（%dAP+%d₿）",
                    BFO.scout_ap, BFO.scout_cash),
                fontSize = F.label,
                fontColor = canScout and C.accent_gold or C.text_muted,
                backgroundColor = canScout and C.bg_elevated or C.paper_dark,
                borderRadius = S.radius_btn,
                borderWidth = canScout and 1 or 0,
                borderColor = canScout and C.border_gold or nil,
                paddingHorizontal = 10,
                paddingVertical = 6,
                flexGrow = 1,
                disabled = not canScout,
                onClick = Config.ClickGuard(function(self)
                    self.props.disabled = true
                    local ok, err = ForeignOps.StartScout(state, tile.id)
                    if ok then
                        UI.Toast.Show("开始侦察 " .. (tile.label or tile.id), { variant = "success", duration = 1.5 })
                    else
                        UI.Toast.Show(err or "无法侦察", { variant = "warning", duration = 1.5 })
                    end
                    if callbacksRef_ and callbacksRef_.onStateChanged then callbacksRef_.onStateChanged() end
                    WorldPage._RefreshDrawer(state)
                end),
            })
        end

        if isScouted and not isActive then
            local exploitBtnText = string.format("开采矿产（%dAP+%d₿）",
                BFO.exploit_ap, BFO.exploit_cash)
            if not canExploit and exploitReason then
                exploitBtnText = exploitBtnText .. " - " .. exploitReason
            end
            table.insert(actionChildren, UI.Button {
                text = exploitBtnText,
                fontSize = F.label,
                fontColor = canExploit and C.accent_green or C.text_muted,
                backgroundColor = canExploit and C.bg_elevated or C.paper_dark,
                borderRadius = S.radius_btn,
                borderWidth = canExploit and 1 or 0,
                borderColor = canExploit and { 46, 204, 113, 120 } or nil,
                paddingHorizontal = 10,
                paddingVertical = 6,
                flexGrow = 1,
                disabled = not canExploit,
                onClick = Config.ClickGuard(function(self)
                    self.props.disabled = true
                    local ok, err = ForeignOps.StartExploit(state, tile.id)
                    if ok then
                        UI.Toast.Show("开始开采 " .. (tile.label or tile.id), { variant = "success", duration = 1.5 })
                    else
                        UI.Toast.Show(err or "无法开采", { variant = "warning", duration = 1.5 })
                    end
                    if callbacksRef_ and callbacksRef_.onStateChanged then callbacksRef_.onStateChanged() end
                    WorldPage._RefreshDrawer(state)
                end),
            })
        end

        if isActive then
            local act = fo.active[tile.id]
            local dmgPct = math.floor((act.damage or 0) * 100)
            if canRebuild then
                table.insert(actionChildren, UI.Button {
                    text = string.format("重建（%dAP+%d₿）损毁%d%%",
                        BFO.rebuild_ap, BFO.rebuild_cash, dmgPct),
                    fontSize = F.label,
                    fontColor = C.accent_amber,
                    backgroundColor = C.bg_elevated,
                    borderRadius = S.radius_btn,
                    borderWidth = 1,
                    borderColor = C.accent_amber,
                    paddingHorizontal = 10,
                    paddingVertical = 6,
                    flexGrow = 1,
                    onClick = Config.ClickGuard(function(self)
                        self.props.disabled = true
                        local ok, err = ForeignOps.DoRebuild(state, tile.id)
                        if ok then
                            UI.Toast.Show("重建完成，损毁降低", { variant = "success", duration = 1.5 })
                        else
                            UI.Toast.Show(err or "无法重建", { variant = "warning", duration = 1.5 })
                        end
                        if callbacksRef_ and callbacksRef_.onStateChanged then callbacksRef_.onStateChanged() end
                        WorldPage._RefreshDrawer(state)
                    end),
                })
            else
                table.insert(actionChildren, UI.Button {
                    text = dmgPct > 0 and ("开采中·损毁" .. dmgPct .. "%") or "开采中·运转正常",
                    fontSize = F.label,
                    fontColor = dmgPct > 20 and C.accent_amber or C.accent_green,
                    backgroundColor = C.bg_elevated,
                    borderRadius = S.radius_btn,
                    paddingHorizontal = 10,
                    paddingVertical = 6,
                    flexGrow = 1,
                    disabled = true,
                })
            end
        end
    end

    -- ── 远征行动区（多回合并发远征版）──
    local expeditionSection = nil
    if tile and tile.country_id ~= "bosnia"
       and state.unlocked_features and state.unlocked_features["expedition"]
       and Expedition.CanDoExpedition(state) then
        local countryId = tile.country_id
        -- 确保HP已初始化（幂等）
        if state.europe then
            Expedition.InitCountryHP(state)
        end
        -- 确保 ExpeditionPanel 模块回调就绪（供 _ShowDeployDialog 使用）
        ExpeditionPanel.EnsureInit(state, callbacksRef_)

        local cs = state.europe and state.europe[countryId]
        if cs and cs.current_hp then
            local summary = Expedition.GetSummary(state)
            local hpPct = cs.max_hp > 0 and (cs.current_hp / cs.max_hp) or 0
            local hpColor = hpPct > 0.5 and C.accent_green
                or (hpPct > 0.2 and C.accent_amber or C.accent_red)
            local isMajor = cs.tier == "major"
            local aggression = summary.aggression or 0

            -- 检查该国是否有活跃远征
            local activeRecord = state.expeditions
                and state.expeditions.active
                and state.expeditions.active[countryId]
            -- 检查该国是否待占领
            local awaitingOcc = nil
            if summary.awaiting_occupation then
                for _, aw in ipairs(summary.awaiting_occupation) do
                    if aw.country_id == countryId then awaitingOcc = aw; break end
                end
            end

            local expChildren = {
                UI.Divider { color = C.divider },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "⚔ 远征行动",
                            fontSize = F.body_minor,
                            fontWeight = "bold",
                            fontColor = C.accent_red,
                        },
                        UI.Label {
                            text = string.format("进行中 %d  侵略度 %.1f",
                                summary.active_count or 0, aggression),
                            fontSize = F.label,
                            fontColor = aggression >= (BE.sanction_threshold or 10)
                                and C.accent_red or C.text_secondary,
                        },
                    },
                },
                -- 军事HP血条
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    children = {
                        UI.Label {
                            text = "军事HP",
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                            width = 50,
                        },
                        UI.ProgressBar {
                            value = hpPct,
                            flexGrow = 1,
                            height = 6,
                            borderRadius = 3,
                            trackColor = C.bg_surface,
                            fillColor = hpColor,
                        },
                        UI.Label {
                            text = string.format("%d/%d", cs.current_hp, cs.max_hp),
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                            width = 55,
                            textAlign = "right",
                        },
                    },
                },
            }

            -- 大国政治HP
            if isMajor and cs.political_hp and cs.max_political_hp then
                local polPct = cs.max_political_hp > 0
                    and (cs.political_hp / cs.max_political_hp) or 0
                local polColor = polPct > 0.5 and { 100, 149, 237, 255 }
                    or (polPct > 0.2 and C.accent_amber or C.accent_red)
                table.insert(expChildren, UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    children = {
                        UI.Label {
                            text = "政治HP",
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                            width = 50,
                        },
                        UI.ProgressBar {
                            value = polPct,
                            flexGrow = 1,
                            height = 6,
                            borderRadius = 3,
                            trackColor = C.bg_surface,
                            fillColor = polColor,
                        },
                        UI.Label {
                            text = string.format("%d/%d", cs.political_hp, cs.max_political_hp),
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                            width = 55,
                            textAlign = "right",
                        },
                    },
                })
            end

            -- ── 状态分支：已占领 / 活跃远征 / 待占领 / 可攻击 ──
            if isOccupied then
                -- 已占领：显示占领状态
                table.insert(expChildren, UI.Panel {
                    width = "100%",
                    backgroundColor = { 41, 128, 185, 30 },
                    borderRadius = 4,
                    padding = 6,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "已纳入版图，无需继续军事行动",
                            fontSize = F.label,
                            fontColor = C.accent_blue,
                        },
                    },
                })
            elseif activeRecord then
                -- 有活跃远征：显示进度 + 增援/撤军按钮
                local deployedPower = math.floor(Expedition.CalcDeployedPower(state, activeRecord))
                local deployedSoldiers = math.floor(Expedition.CalcDeployedSoldiers(state, activeRecord))
                local turnDmg = math.floor(Expedition.CalcTurnDamage(state, activeRecord))
                local estTurns = Expedition.EstimateTurns(state, activeRecord)
                local successRate = Expedition.CalcSuccessRate(state, activeRecord)
                local successPct = math.floor(successRate * 100)
                local successColor = successPct >= 70 and C.accent_green
                    or (successPct >= 40 and C.accent_amber or C.accent_red)

                table.insert(expChildren, UI.Panel {
                    width = "100%",
                    backgroundColor = { 180, 60, 60, 25 },
                    borderRadius = 4,
                    padding = 6,
                    gap = 3,
                    children = {
                        UI.Label {
                            text = string.format("远征进行中（第 %d 回合）",
                                activeRecord.turns_elapsed or 0),
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = C.accent_red,
                        },
                        UI.Label {
                            text = string.format(
                                "兵力 %d人 | 战力 %d | 每回合伤害 %d",
                                deployedSoldiers, deployedPower, turnDmg),
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                        },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            justifyContent = "space-between",
                            children = {
                                UI.Label {
                                    text = string.format("成功率 %d%%", successPct),
                                    fontSize = F.label,
                                    fontColor = successColor,
                                },
                                UI.Label {
                                    text = string.format("预计 %s 回合",
                                        estTurns == math.huge and "∞" or tostring(estTurns)),
                                    fontSize = F.label,
                                    fontColor = C.text_secondary,
                                },
                            },
                        },
                    },
                })

                -- 增援 / 撤军按钮
                local totalAP = (state.ap.current or 0) + (state.ap.temp or 0)
                local canReinforce = totalAP >= (BE.expedition_reinforce_ap or 1)
                local canWithdraw = totalAP >= (BE.expedition_withdraw_ap or 1)
                table.insert(expChildren, UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 6,
                    children = {
                        UI.Button {
                            text = string.format("增援 %dAP", BE.expedition_reinforce_ap or 1),
                            fontSize = F.label,
                            fontColor = canReinforce and C.text_primary or C.text_muted,
                            backgroundColor = canReinforce and { 60, 120, 60, 50 } or C.bg_surface,
                            borderRadius = S.radius_btn,
                            borderWidth = 1,
                            borderColor = canReinforce and C.accent_green or C.border_soft,
                            paddingVertical = 5,
                            paddingHorizontal = 8,
                            flexGrow = 1,
                            disabled = not canReinforce,
                            onClick = Config.ClickGuard(function(self)
                                ExpeditionPanel._ShowDeployDialog(state, countryId, "reinforce")
                            end),
                        },
                        UI.Button {
                            text = string.format("撤军 %dAP", BE.expedition_withdraw_ap or 1),
                            fontSize = F.label,
                            fontColor = canWithdraw and C.text_primary or C.text_muted,
                            backgroundColor = canWithdraw and { 180, 60, 60, 40 } or C.bg_surface,
                            borderRadius = S.radius_btn,
                            borderWidth = 1,
                            borderColor = canWithdraw and C.accent_red or C.border_soft,
                            paddingVertical = 5,
                            paddingHorizontal = 8,
                            flexGrow = 1,
                            disabled = not canWithdraw,
                            onClick = Config.ClickGuard(function(self)
                                ExpeditionPanel._ShowWithdrawDialog(state, countryId)
                            end),
                        },
                    },
                })
            elseif awaitingOcc then
                -- 待占领：显示占领决策按钮
                table.insert(expChildren, UI.Panel {
                    width = "100%",
                    backgroundColor = { 41, 128, 185, 35 },
                    borderRadius = 4,
                    padding = 6,
                    gap = 4,
                    children = {
                        UI.Label {
                            text = (function()
                                local elapsed = (state.turn_count or 0) - (awaitingOcc.defeated_turn or 0)
                                local remaining = math.max(0, 2 - elapsed)
                                if remaining > 0 then
                                    return string.format("🏴 军事HP归零，可执行占领！（剩余 %d 回合窗口期）", remaining)
                                else
                                    return "🏴 军事HP归零，可执行占领！（窗口期即将结束）"
                                end
                            end)(),
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = C.accent_blue,
                        },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            gap = 4,
                            children = {
                                UI.Button {
                                    text = string.format("自行占领 %dAP+%d₿",
                                        BE.occupy_ap_cost or 2, BE.occupy_cash_cost or 300),
                                    fontSize = F.label,
                                    fontColor = C.text_primary,
                                    backgroundColor = { 41, 128, 185, 60 },
                                    borderRadius = S.radius_btn,
                                    paddingVertical = 5,
                                    paddingHorizontal = 6,
                                    flexGrow = 1,
                                    onClick = Config.ClickGuard(function(self)
                                        local ok, msg = Expedition.OccupySelf(state, countryId)
                                        if ok then
                                            UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                                        else
                                            UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                                        end
                                        if callbacksRef_ and callbacksRef_.onStateChanged then
                                            callbacksRef_.onStateChanged()
                                        end
                                    end),
                                },
                                UI.Button {
                                    text = string.format("交给盟友 %dAP",
                                        BE.give_to_faction_ap or 1),
                                    fontSize = F.label,
                                    fontColor = C.text_primary,
                                    backgroundColor = { 60, 120, 60, 50 },
                                    borderRadius = S.radius_btn,
                                    paddingVertical = 5,
                                    paddingHorizontal = 6,
                                    flexGrow = 1,
                                    onClick = Config.ClickGuard(function(self)
                                        -- 选择关系最好的势力
                                        local bestFaction, bestRel = nil, -999
                                        for fid, fdata in pairs(state.factions or {}) do
                                            local rel = fdata.relation or 0
                                            if rel > bestRel then
                                                bestFaction = fid; bestRel = rel
                                            end
                                        end
                                        if not bestFaction then
                                            UI.Toast.Show("无可用盟友势力", { variant = "error", duration = 1.5 })
                                            return
                                        end
                                        local ok, msg = Expedition.OccupyGiveToFaction(
                                            state, countryId, bestFaction)
                                        if ok then
                                            UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                                        else
                                            UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                                        end
                                        if callbacksRef_ and callbacksRef_.onStateChanged then
                                            callbacksRef_.onStateChanged()
                                        end
                                    end),
                                },
                            },
                        },
                        UI.Button {
                            text = "放弃占领",
                            fontSize = F.label,
                            fontColor = C.text_muted,
                            backgroundColor = C.bg_surface,
                            borderRadius = S.radius_btn,
                            paddingVertical = 4,
                            width = "100%",
                            onClick = Config.ClickGuard(function(self)
                                local ok, msg = Expedition.AbandonOccupation(state, countryId)
                                if ok then
                                    UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                                else
                                    UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                                end
                                if callbacksRef_ and callbacksRef_.onStateChanged then
                                    callbacksRef_.onStateChanged()
                                end
                            end),
                        },
                    },
                })
            else
                -- 无活跃远征：显示发起远征按钮
                local diffMod = Expedition.GetConquestDifficultyMod(state, countryId)
                local fwdBonus = Expedition.GetForwardBaseBonus(state, countryId)
                local diffLabel = diffMod > 1.2 and "困难" or (diffMod < 0.8 and "容易" or "正常")
                local diffColor = diffMod > 1.2 and C.accent_red
                    or (diffMod < 0.8 and C.accent_green or C.text_secondary)

                table.insert(expChildren, UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    children = {
                        UI.Label {
                            text = string.format("难度: %s (×%.2f)", diffLabel, diffMod),
                            fontSize = F.label,
                            fontColor = diffColor,
                        },
                        fwdBonus > 0 and UI.Label {
                            text = string.format("前线基地 +%d%%", math.floor(fwdBonus * 100)),
                            fontSize = F.label,
                            fontColor = C.accent_green,
                        } or nil,
                    },
                })

                local totalAP = (state.ap.current or 0) + (state.ap.temp or 0)
                local inflation = GameState.GetInflationFactor
                    and GameState.GetInflationFactor(state) or 1.0
                local canLaunch = totalAP >= (BE.expedition_ap_cost or 2)
                table.insert(expChildren, UI.Button {
                    text = string.format("发起远征 %dAP + 兵×%d₿",
                        BE.expedition_ap_cost or 2,
                        math.floor((BE.expedition_cost_per_soldier or 40) * inflation)),
                    fontSize = F.label,
                    fontColor = canLaunch and C.text_primary or C.text_muted,
                    backgroundColor = canLaunch and { 180, 60, 60, 60 } or C.bg_surface,
                    borderRadius = S.radius_btn,
                    borderWidth = 1,
                    borderColor = canLaunch and C.accent_red or C.border_soft,
                    paddingVertical = 6,
                    width = "100%",
                    disabled = not canLaunch,
                    onClick = Config.ClickGuard(function(self)
                        ExpeditionPanel._ShowDeployDialog(state, countryId, "launch")
                    end),
                })
            end

            -- 支援按钮（仅对大国）
            if isMajor and not isOccupied then
                local totalAP = (state.ap.current or 0) + (state.ap.temp or 0)
                local canSupport = totalAP >= (BE.support_ap_cost or 1)
                    and state.cash >= (BE.support_cash_cost or 100)
                table.insert(expChildren, UI.Button {
                    text = string.format("支援作战 %dAP+%d₿",
                        BE.support_ap_cost or 1, BE.support_cash_cost or 100),
                    fontSize = F.label,
                    fontColor = canSupport and { 100, 200, 100, 255 } or C.text_muted,
                    backgroundColor = canSupport and { 60, 120, 60, 40 } or C.bg_surface,
                    borderRadius = S.radius_btn,
                    borderWidth = 1,
                    borderColor = canSupport and C.accent_green or C.border_soft,
                    paddingVertical = 5,
                    width = "100%",
                    disabled = not canSupport,
                    onClick = Config.ClickGuard(function(self)
                        self.props.disabled = true
                        local ok, msg = Expedition.Support(state, countryId, nil)
                        if ok then
                            UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                        else
                            UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                        end
                        if callbacksRef_ and callbacksRef_.onStateChanged then
                            callbacksRef_.onStateChanged()
                        end
                    end),
                })
            end

            -- 制裁警告
            local sanctioned, sanctionReason = Expedition.CheckSanction(state)
            if sanctioned then
                local warnText = sanctionReason == "military_intervention"
                    and "列强军事干预中！"
                    or string.format("经济制裁中（剩余 %d 季）",
                        state.expeditions and state.expeditions.sanction_remaining or 0)
                table.insert(expChildren, UI.Label {
                    text = "⚠ " .. warnText,
                    fontSize = F.label,
                    fontColor = C.accent_red,
                })
            end

            expeditionSection = UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = 4,
                flexDirection = "column",
                gap = 5,
                children = expChildren,
            }
        end
    elseif tile and tile.country_id and tile.country_id ~= "bosnia" then
        -- 外国地块但远征未解锁：显示提示
        local countryLabel = _countryLabels[tile.country_id] or tile.country_id
        expeditionSection = UI.Panel {
            width = "100%",
            paddingHorizontal = S.card_padding,
            paddingVertical = 6,
            flexDirection = "column",
            gap = 4,
            children = {
                UI.Divider { color = C.divider },
                UI.Label {
                    text = "🔒 远征行动（未解锁）",
                    fontSize = F.label,
                    fontColor = C.text_muted,
                },
                UI.Label {
                    text = "获得「幕后执政」称号后可对" .. countryLabel .. "发起远征行动（需三区域控制度≥70）",
                    fontSize = F.body_minor,
                    fontColor = C.text_muted,
                },
            },
        }
    end

    -- ── 商业远征区 ──
    local ventureSection = nil
    if tile and tile.country_id ~= "bosnia"
       and state.unlocked_features and state.unlocked_features["venture"]
       and Venture.CanDoVenture(state) then
        local countryId = tile.country_id
        Venture.InitMarketBarriers(state)
        VenturePanel.EnsureInit(state, callbacksRef_)

        local cs = state.europe and state.europe[countryId]
        if cs and cs.max_market_barrier then
            local summary = Venture.GetSummary(state)
            local barrierPct = cs.max_market_barrier > 0
                and (cs.market_barrier / cs.max_market_barrier) or 0
            local barrierColor = barrierPct > 0.5 and C.accent_amber
                or (barrierPct > 0.2 and C.accent_red or C.accent_green)

            -- 检查该国是否有活跃商业远征
            local activeRecord = (state.ventures.active or {})[countryId]
            -- 检查该国是否有商业据点
            local existingPost = (state.ventures.commercial_posts or {})[countryId]
            -- 检查该国是否待决策
            local awaitingDec = nil
            for _, aw in ipairs(state.ventures.awaiting_decision or {}) do
                if aw.power_id == countryId then awaitingDec = aw; break end
            end

            local ventChildren = {
                UI.Divider { color = C.divider },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "💰 商业远征",
                            fontSize = F.body_minor,
                            fontWeight = "bold",
                            fontColor = C.accent_gold,
                        },
                        UI.Label {
                            text = string.format("进行中 %d/%d  紧张度 %.1f",
                                summary.active_count or 0,
                                BV.max_concurrent_ventures or 2,
                                summary.market_tension or 0),
                            fontSize = F.label,
                            fontColor = (summary.market_tension or 0) >= (BV.sanction_threshold or 5)
                                and C.accent_red or C.text_secondary,
                        },
                    },
                },
                -- 市场壁垒血条
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    children = {
                        UI.Label {
                            text = "壁垒",
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                            width = 50,
                        },
                        UI.ProgressBar {
                            value = barrierPct,
                            flexGrow = 1,
                            height = 6,
                            borderRadius = 3,
                            trackColor = C.bg_surface,
                            fillColor = barrierColor,
                        },
                        UI.Label {
                            text = string.format("%d/%d",
                                cs.market_barrier or 0, cs.max_market_barrier or 0),
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                            width = 55,
                            textAlign = "right",
                        },
                    },
                },
            }

            if existingPost then
                -- 已有商业据点：显示据点信息
                local estDef = BV.establishments[existingPost.type]
                table.insert(ventChildren, UI.Panel {
                    width = "100%",
                    backgroundColor = { 180, 150, 50, 25 },
                    borderRadius = 4,
                    padding = 6,
                    gap = 3,
                    children = {
                        UI.Label {
                            text = string.format("%s %s（已建立）",
                                estDef and estDef.icon or "🏪",
                                estDef and estDef.label or existingPost.type),
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = C.accent_gold,
                        },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            justifyContent = "space-between",
                            children = {
                                UI.Label {
                                    text = string.format("收入 +%d₿/季", existingPost.income_per_turn or 0),
                                    fontSize = F.label,
                                    fontColor = C.accent_green,
                                },
                                UI.Label {
                                    text = string.format("维护 -%d₿/季", existingPost.maintenance or 0),
                                    fontSize = F.label,
                                    fontColor = C.accent_red,
                                },
                            },
                        },
                    },
                })
            elseif awaitingDec then
                -- 壁垒已清零，待决策
                table.insert(ventChildren, UI.Panel {
                    width = "100%",
                    backgroundColor = { 180, 150, 50, 35 },
                    borderRadius = 4,
                    padding = 6,
                    gap = 4,
                    children = {
                        UI.Label {
                            text = "🏴 市场壁垒已突破，可建立商业据点！",
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = C.accent_gold,
                        },
                        UI.Label {
                            text = "前往「商路」面板选择据点类型",
                            fontSize = F.body_minor,
                            fontColor = C.text_secondary,
                        },
                    },
                })
            elseif activeRecord then
                -- 有活跃商业远征：显示进度
                local detail = Venture.GetVentureDetail(state, countryId)
                if detail then
                    local stratDef = BV.strategies[activeRecord.strategy_id or "normal"]
                    table.insert(ventChildren, UI.Panel {
                        width = "100%",
                        backgroundColor = { 180, 150, 50, 25 },
                        borderRadius = 4,
                        padding = 6,
                        gap = 3,
                        children = {
                            UI.Label {
                                text = string.format("渗透进行中（第 %d 回合）",
                                    detail.turns_active or 0),
                                fontSize = F.label,
                                fontWeight = "bold",
                                fontColor = C.accent_gold,
                            },
                            UI.Label {
                                text = string.format(
                                    "%s %s | %s | 渗透 %d/回合",
                                    stratDef and stratDef.icon or "📦",
                                    detail.strategy_label or "",
                                    detail.investment_label or "",
                                    detail.penetration_per_turn or 0),
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "space-between",
                                children = {
                                    UI.Label {
                                        text = string.format("费用 %d₿/季", detail.turn_cost or 0),
                                        fontSize = F.label,
                                        fontColor = C.accent_amber,
                                    },
                                    UI.Label {
                                        text = string.format("预计 %s 回合",
                                            (detail.estimated_turns or 0) >= 999
                                                and "∞" or tostring(detail.estimated_turns or 0)),
                                        fontSize = F.label,
                                        fontColor = C.text_secondary,
                                    },
                                },
                            },
                        },
                    })

                    -- 调整/撤出按钮
                    local totalAP = (state.ap.current or 0) + (state.ap.temp or 0)
                    local canAdjust = totalAP >= (BV.reinforce_ap_cost or 1)
                    local canWithdraw = totalAP >= (BV.withdraw_ap_cost or 1)
                    table.insert(ventChildren, UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 6,
                        children = {
                            UI.Button {
                                text = string.format("调整投资 %dAP", BV.reinforce_ap_cost or 1),
                                fontSize = F.label,
                                fontColor = canAdjust and C.text_primary or C.text_muted,
                                backgroundColor = canAdjust and { 180, 150, 50, 40 } or C.bg_surface,
                                borderRadius = S.radius_btn,
                                borderWidth = 1,
                                borderColor = canAdjust and C.accent_gold or C.border_soft,
                                paddingVertical = 5,
                                paddingHorizontal = 8,
                                flexGrow = 1,
                                disabled = not canAdjust,
                                onClick = Config.ClickGuard(function(self)
                                    VenturePanel._ShowInvestmentDialog(state, countryId)
                                end),
                            },
                            UI.Button {
                                text = string.format("撤出 %dAP", BV.withdraw_ap_cost or 1),
                                fontSize = F.label,
                                fontColor = canWithdraw and C.text_primary or C.text_muted,
                                backgroundColor = canWithdraw and { 180, 60, 60, 40 } or C.bg_surface,
                                borderRadius = S.radius_btn,
                                borderWidth = 1,
                                borderColor = canWithdraw and C.accent_red or C.border_soft,
                                paddingVertical = 5,
                                paddingHorizontal = 8,
                                flexGrow = 1,
                                disabled = not canWithdraw,
                                onClick = Config.ClickGuard(function(self)
                                    local ok, msg = Venture.WithdrawVenture(state, countryId)
                                    if ok then
                                        UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                                    else
                                        UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                                    end
                                    if callbacksRef_ and callbacksRef_.onStateChanged then
                                        callbacksRef_.onStateChanged()
                                    end
                                    WorldPage._RefreshDrawer(state)
                                end),
                            },
                        },
                    })
                end
            else
                -- 无活跃远征：显示发起按钮
                local diffMod = Venture.GetDifficultyMod(state)
                local diffLabel = diffMod > 1.2 and "困难" or (diffMod < 0.8 and "容易" or "正常")
                local diffColor = diffMod > 1.2 and C.accent_red
                    or (diffMod < 0.8 and C.accent_green or C.text_secondary)

                table.insert(ventChildren, UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    children = {
                        UI.Label {
                            text = string.format("难度: %s (×%.2f)", diffLabel, diffMod),
                            fontSize = F.label,
                            fontColor = diffColor,
                        },
                    },
                })

                -- 检查是否可以发起（贸易路线、并发限制等）
                local totalAP = (state.ap.current or 0) + (state.ap.temp or 0)
                local maxConc = BV.max_concurrent_ventures or 2
                local atConcLimit = (summary.active_count or 0) >= maxConc
                local route = TradeRoutesData.GetRouteForBuyer(countryId)
                local routeUnlocked = route and route.unlocked
                if not routeUnlocked and route and state.trade and state.trade.route_unlocks then
                    routeUnlocked = state.trade.route_unlocks[route.id] or false
                end
                local canLaunch = totalAP >= (BV.venture_ap_cost or 2)
                    and not atConcLimit
                    and routeUnlocked
                local inflation = GameState.GetInflationFactor
                    and GameState.GetInflationFactor(state) or 1.0

                local btnText
                if not routeUnlocked then
                    btnText = "贸易路线未开通"
                elseif atConcLimit then
                    btnText = string.format("并发上限 %d/%d", summary.active_count, maxConc)
                else
                    btnText = string.format("发起渗透 %dAP + %d₿起",
                        BV.venture_ap_cost or 2,
                        math.floor((BV.base_investment_cost or 300) * inflation))
                end

                table.insert(ventChildren, UI.Button {
                    text = btnText,
                    fontSize = F.label,
                    fontColor = canLaunch and C.text_primary or C.text_muted,
                    backgroundColor = canLaunch and { 180, 150, 50, 50 } or C.bg_surface,
                    borderRadius = S.radius_btn,
                    borderWidth = 1,
                    borderColor = canLaunch and C.accent_gold or C.border_soft,
                    paddingVertical = 6,
                    width = "100%",
                    disabled = not canLaunch,
                    onClick = Config.ClickGuard(function(self)
                        VenturePanel._ShowLaunchDialog(state, countryId)
                    end),
                })
            end

            -- 制裁警告
            if summary.under_sanction then
                table.insert(ventChildren, UI.Label {
                    text = string.format("⚠ 贸易制裁中（剩余 %d 季）",
                        summary.sanction_remaining or 0),
                    fontSize = F.label,
                    fontColor = C.accent_red,
                })
            end

            ventureSection = UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = 4,
                flexDirection = "column",
                gap = 5,
                children = ventChildren,
            }
        end
    elseif tile and tile.country_id and tile.country_id ~= "bosnia"
        and state.unlocked_features and not state.unlocked_features["venture"] then
        -- 外国地块但商业远征未解锁：显示提示
        local countryLabel = _countryLabels[tile.country_id] or tile.country_id
        ventureSection = UI.Panel {
            width = "100%",
            paddingHorizontal = S.card_padding,
            paddingVertical = 6,
            flexDirection = "column",
            gap = 4,
            children = {
                UI.Divider { color = C.divider },
                UI.Label {
                    text = "🔒 商业远征（未解锁）",
                    fontSize = F.label,
                    fontColor = C.text_muted,
                },
                UI.Label {
                    text = "研发「金融网络」科技后可对" .. countryLabel .. "发起商业渗透",
                    fontSize = F.body_minor,
                    fontColor = C.text_muted,
                },
            },
        }
    end

    -- 构建控制比例 children
    local controlSectionChildren = {
        UI.Divider { color = C.divider },
        UI.Label {
            text = "控制比例",
            fontSize = F.label,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        },
    }
    for _, row in ipairs(controlRows) do
        table.insert(controlSectionChildren, row)
    end

    -- ── 外国 tile：精简布局 ──
    if isForeignTile then
        local countryId = tile.country_id
        local countryLabel = _countryLabels[countryId] or countryId
        local cs = state.europe and state.europe[countryId]
        local tierLabels = { major = "列强", minor = "小国", micro = "微国" }
        local tierText = cs and tierLabels[cs.tier] or "未知"

        -- 边框颜色：占领=蓝色，普通=灰色
        local foreignBorder = isOccupied and C.accent_blue or C.border_soft

        -- 头部背景色：占领时加深蓝色调
        local headerBg = isOccupied and { 41, 128, 185, 50 } or C.bg_elevated

        -- 状态 badge
        local statusBadge = nil
        if isOccupied then
            statusBadge = UI.Panel {
                paddingHorizontal = 6,
                paddingVertical = 2,
                backgroundColor = { 41, 128, 185, 80 },
                borderRadius = S.radius_badge,
                children = {
                    UI.Label {
                        text = "已占领",
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = { 130, 200, 255, 255 },
                    },
                },
            }
        end

        -- 占领收益信息
        local occupyInfoSection = nil
        if isOccupied and occupationInfo then
            local incomeText = string.format("+%d₿/季", occupationInfo.income_per_turn or 0)
            local maintText = string.format("-%d₿/季", occupationInfo.maintenance or 0)
            occupyInfoSection = UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingVertical = 6,
                backgroundColor = { 41, 128, 185, 25 },
                flexDirection = "column",
                gap = 4,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = "占领收入",
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                            UI.Label {
                                text = incomeText,
                                fontSize = F.label,
                                fontWeight = "bold",
                                fontColor = C.accent_green,
                            },
                        },
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = "维持费用",
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                            UI.Label {
                                text = maintText,
                                fontSize = F.label,
                                fontColor = C.accent_red,
                            },
                        },
                    },
                },
            }
        end

        -- 外国属性：精简版（只显示国力等级 + 稳定度）
        local foreignAttrChildren = {}
        local stabilityVal = cs and cs.stability or 0
        local stabColor = stabilityVal >= 60 and C.accent_green
            or (stabilityVal >= 30 and C.accent_amber or C.accent_red)
        table.insert(foreignAttrChildren, WorldPage._InfoRow("国力", tierText, C.accent_gold))
        table.insert(foreignAttrChildren, WorldPage._InfoRow("稳定度", tostring(stabilityVal), stabColor))

        -- 贸易路线状态
        if TradeRoutesData and TradeRoutesData.ROUTES then
            for _, route in ipairs(TradeRoutesData.ROUTES) do
                if route.buyer_power_id == countryId then
                    local hasActiveOrder = false
                    if state.trade and state.trade.active_orders then
                        for _, order in ipairs(state.trade.active_orders) do
                            if order.buyer_power_id == countryId then
                                hasActiveOrder = true
                                break
                            end
                        end
                    end
                    local tradeText = hasActiveOrder and "贸易进行中"
                        or (route.unlocked and "路线已开通" or "路线未开通")
                    local tradeColor = hasActiveOrder and C.accent_green
                        or (route.unlocked and C.accent_amber or C.text_muted)
                    table.insert(foreignAttrChildren, WorldPage._InfoRow("贸易", tradeText, tradeColor))
                    break
                end
            end
        end

        -- 资源区（外国版）
        local foreignResSection = nil
        if #resourceRows > 0 then
            local resChildren = {
                UI.Divider { color = C.divider },
                UI.Label {
                    text = "矿产资源",
                    fontSize = F.label,
                    fontWeight = "bold",
                    fontColor = C.text_secondary,
                },
            }
            for _, row in ipairs(resourceRows) do
                table.insert(resChildren, row)
            end
            foreignResSection = UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = 4,
                flexDirection = "column",
                gap = 4,
                children = resChildren,
            }
        end

        -- 动态构建 children（避免 nil 中断渲染）
        local foreignChildren = {}

        -- 1) 头部
        local headerNameChildren = {
            UI.Label {
                text = countryLabel,
                fontSize = F.card_title,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
        }
        if statusBadge then
            table.insert(headerNameChildren, statusBadge)
        end

        table.insert(foreignChildren, UI.Panel {
            width = "100%",
            padding = S.card_padding,
            backgroundColor = headerBg,
            borderRadius = S.radius_drawer,
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = {
                UI.Label { text = "🏴", fontSize = 22 },
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    gap = 2,
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = headerNameChildren,
                        },
                        UI.Label {
                            text = displayName .. " · " .. typeBadge,
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                        },
                    },
                },
            },
        })

        -- 2) 占领收益区
        if occupyInfoSection then
            table.insert(foreignChildren, occupyInfoSection)
        end

        -- 3) 属性区（精简）
        table.insert(foreignChildren, UI.Panel {
            width = "100%",
            padding = S.card_padding,
            flexDirection = "column",
            gap = 5,
            children = foreignAttrChildren,
        })

        -- 4) 矿产资源区
        if foreignResSection then
            table.insert(foreignChildren, foreignResSection)
        end

        -- 5) 远征行动区
        if expeditionSection then
            table.insert(foreignChildren, expeditionSection)
        end

        -- 5.5) 商业远征区
        if ventureSection then
            table.insert(foreignChildren, ventureSection)
        end

        -- 6) 操作按钮区
        if #actionChildren > 0 then
            table.insert(foreignChildren, UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                gap = 8,
                children = actionChildren,
            })
        end

        return UI.Panel {
            width = "100%",
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_drawer,
            borderWidth = isOccupied and 2 or 1,
            borderColor = foreignBorder,
            flexDirection = "column",
            overflow = "hidden",
            children = foreignChildren,
        }
    end

    -- ── 国内 tile：完整布局 ──
    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_drawer,
        borderWidth = 1,
        borderColor = ctrlColor,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 头部：节点名称 + 类型 Badge + 控制度
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.bg_elevated,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = region.icon or "⬡", fontSize = 24 },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 6,
                                children = {
                                    UI.Label {
                                        text = displayName,
                                        fontSize = F.card_title,
                                        fontWeight = "bold",
                                        fontColor = C.text_primary,
                                    },
                                    UI.Panel {
                                        paddingHorizontal = 5,
                                        paddingVertical = 1,
                                        backgroundColor = { typeColors[1], typeColors[2], typeColors[3], 40 },
                                        borderRadius = S.radius_badge,
                                        children = {
                                            UI.Label {
                                                text = typeBadge,
                                                fontSize = F.label,
                                                fontColor = { typeColors[1], typeColors[2], typeColors[3], 255 },
                                            },
                                        },
                                    },
                                },
                            },
                            UI.Label {
                                text = dominantText,
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                        },
                    },
                    -- 控制度大数字
                    UI.Panel {
                        flexDirection = "column",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = region.control .. "%",
                                fontSize = F.data_mid,
                                fontWeight = "bold",
                                fontColor = ctrlColor,
                            },
                            UI.Label {
                                text = "控制度",
                                fontSize = F.label,
                                fontColor = C.text_muted,
                            },
                        },
                    },
                },
            },

            -- 属性区（去掉重复控制度和调试模块行）
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "column",
                gap = 5,
                children = {
                    WorldPage._InfoRow("治安",
                        RegionsData.GetSecurityText(security), secColor),
                    WorldPage._InfoRow("劳动力",
                        Config.FormatNumber(region.population) .. " 人", C.text_primary),
                    WorldPage._InfoRow("基建等级",
                        WorldPage._StarRating(region.development, 5), C.accent_gold),
                    WorldPage._InfoRow("文化价值",
                        tostring(region.culture), C.text_primary),
                },
            },

            -- 资源区
            (function()
                if #resourceRows == 0 then return nil end
                local resChildren = {
                    UI.Divider { color = C.divider },
                    UI.Label {
                        text = "资源",
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = C.text_secondary,
                    },
                }
                for _, row in ipairs(resourceRows) do
                    table.insert(resChildren, row)
                end
                return UI.Panel {
                    width = "100%",
                    paddingHorizontal = S.card_padding,
                    paddingBottom = 4,
                    flexDirection = "column",
                    gap = 4,
                    children = resChildren,
                }
            end)() or nil,

            -- 控制比例区
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = 4,
                flexDirection = "column",
                gap = 4,
                children = controlSectionChildren,
            },

            -- 操作按钮区
            #actionChildren > 0 and UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                gap = 8,
                children = actionChildren,
            } or nil,
        },
    }
end

-- ============================================================================
-- 政治渗透操作
-- ============================================================================

--- 执行政治渗透：花费 2AP，增加玩家对目标地区的控制度 +8，等比减少 AI 势力占比
function WorldPage._DoPoliticalInfiltration(state, region)
    local infiltrateAP = 2  -- TODO: 提取到 Balance 配置（当前硬编码）

    -- 检查 AP
    if (state.ap.current + (state.ap.temp or 0)) < infiltrateAP then
        UI.Toast.Show(string.format("行动点不足（需要%dAP）", infiltrateAP), { variant = "error", duration = 1.5 })
        return
    end

    -- 扣除 AP
    if not GameState.SpendAP(state, infiltrateAP) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return
    end

    -- 计算渗透效果
    local gainBase = 8  -- 基础控制度增长
    -- 控制度越高，渗透收益递减
    if region.control >= 80 then
        gainBase = 3
    elseif region.control >= 60 then
        gainBase = 5
    end

    local oldControl = region.control
    region.control = math.min(100, region.control + gainBase)
    local actualGain = region.control - oldControl

    -- 等比减少 AI 势力占比
    if region.ai_presence and actualGain > 0 then
        local totalAI = 0
        for _, presence in pairs(region.ai_presence) do
            totalAI = totalAI + presence
        end
        if totalAI > 0 then
            local reduction = actualGain  -- 总共需要减少的 AI 占比
            for aiId, presence in pairs(region.ai_presence) do
                local ratio = presence / totalAI
                local loss = math.floor(reduction * ratio + 0.5)
                region.ai_presence[aiId] = math.max(0, presence - loss)
            end
        end
    end

    -- 渗透同时标记本季有文化行动
    state.culture_action_this_turn = true

    -- 日志
    GameState.AddLog(state, string.format(
        "[渗透] 在 %s 开展政治渗透，控制度 %d%% → %d%%（+%d）",
        region.name, oldControl, region.control, actualGain))

    UI.Toast.Show(string.format("%s 控制度 +%d%%", region.name, actualGain),
        { variant = "success", duration = 1.5 })

    -- 刷新 UI
    if callbacksRef_ and callbacksRef_.onStateChanged then
        callbacksRef_.onStateChanged()
    end
end

-- ============================================================================
-- 工具函数
-- ============================================================================

function WorldPage._InfoRow(label, value, valueColor)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label {
                text = label,
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            },
            UI.Label {
                text = value,
                fontSize = F.body_minor,
                fontWeight = "bold",
                fontColor = valueColor or C.text_primary,
                flexShrink = 1,
                textAlign = "right",
            },
        },
    }
end

--- 控制比例条
function WorldPage._ControlBar(name, pct, color)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                text = name,
                fontSize = F.label,
                fontColor = C.text_secondary,
                width = 72,
                flexShrink = 0,
            },
            UI.ProgressBar {
                value = pct / 100,
                flexGrow = 1,
                height = 5,
                borderRadius = 3,
                trackColor = C.bg_surface,
                fillColor = { color[1], color[2], color[3], 255 },
            },
            UI.Label {
                text = string.format("%02d%%", pct),
                fontSize = F.label,
                fontColor = { color[1], color[2], color[3], 255 },
                width = 40,
                flexShrink = 0,
                textAlign = "right",
            },
        },
    }
end

--- 星级评分文本
function WorldPage._StarRating(level, maxLevel)
    local stars = ""
    for i = 1, maxLevel do
        stars = stars .. (i <= level and "★" or "☆")
    end
    return stars
end

-- ============================================================================
-- 刷新接口
-- ============================================================================

function WorldPage.Refresh(root, state)
    stateRef_ = state
    if mapWidget_ then
        mapWidget_:SetRegions(state.regions)
        mapWidget_:UpdateUnlocks(state)
        mapWidget_:SetEuropeState(state.europe)
        mapWidget_:SetForeignOps(state.foreign_ops)
        WorldPage._UpdateFrontLineData(state)
        local era = Config.GetEraByYear(state.year)
        if era then mapWidget_:SetEra(era.id) end
    end
    -- 如果当前在地图页且有选中节点，刷新抽屉
    if activeSubTab_ == "map" and selectedNodeId_ then
        WorldPage._RefreshDrawer(state)
    end
end

return WorldPage
