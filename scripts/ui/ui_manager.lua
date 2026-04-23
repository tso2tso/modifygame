-- ============================================================================
-- UI 总管理器 — sarajevo_dynasty_ui_spec §4.7 / §4.8
-- 架构：仪表盘为主视图 + §4.7 底部导航 64px + §4.8 右侧 Drawer
-- 设计语言：工业帝国主义时代的家族账簿
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local TopBar = require("ui.ui_top_bar")
local Dashboard = require("ui.ui_dashboard")
local FamilyPage = require("ui.ui_family")
local IndustryPage = require("ui.ui_industry")
local MarketPage = require("ui.ui_market")
local MilitaryPage = require("ui.ui_military")
local WorldPage = require("ui.ui_world")
local MenuPage = require("ui.ui_menu")
local ActionModals = require("ui.ui_action_modals")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local UIManager = {}

---@type table UI 根控件
local uiRoot_ = nil
---@type string 当前视图: "dashboard" 或 Tab id
local activeView_ = "dashboard"
---@type table 各页面容器引用
local pages_ = {}
---@type table 仪表盘容器引用
local dashboardPage_ = nil
---@type table 游戏状态引用
local stateRef_ = nil
---@type function|nil 结束回合回调
local onEndTurn_ = nil
---@type function|nil 新游戏/读档回调
local onNewGame_ = nil
---@type function|nil 事件处理回调
local onProcessEvent_ = nil
---@type table|nil 设置 Drawer 实例
local settingsDrawer_ = nil

--- 初始化 UI 系统
function UIManager.InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

--- 创建完整游戏 UI
---@param state table 游戏状态
---@param callbacks table { onEndTurn, onNewGame, onProcessEvent }
function UIManager.Create(state, callbacks)
    stateRef_ = state
    onEndTurn_ = callbacks and callbacks.onEndTurn
    onNewGame_ = callbacks and callbacks.onNewGame
    onProcessEvent_ = callbacks and callbacks.onProcessEvent

    -- 重置
    pages_ = {}
    dashboardPage_ = nil
    settingsDrawer_ = nil
    activeView_ = "dashboard"

    uiRoot_ = UI.SafeAreaView {
        id = "gameRoot",
        width = "100%",
        height = "100%",
        backgroundColor = C.bg_base,
        flexDirection = "column",
        children = {
            -- §4.1 + §4.2 顶栏（双行）
            TopBar.Create(state, {
                onSettings = function()
                    UIManager._OpenSettings()
                end,
                onStateChanged = function()
                    UIManager.RefreshAll(stateRef_)
                end,
            }),

            -- 内容区域（仪表盘 + 深度页共享）
            UIManager._CreateContentArea(state),

            -- §4.7 底部导航栏
            UIManager._CreateBottomNav(),
        }
    }

    UI.SetRoot(uiRoot_)
    UIManager._ShowView("dashboard")
end

-- ============================================================================
-- 内容区
-- ============================================================================

function UIManager._CreateContentArea(state)
    dashboardPage_ = UI.ScrollView {
        id = "page_dashboard",
        width = "100%",
        height = "100%",
        visible = true,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        padding = S.page_padding,
        children = {
            Dashboard.Create(state, {
                onEndTurn = onEndTurn_,
                onProcessEvent = function(index)
                    if onProcessEvent_ then
                        onProcessEvent_(index)
                    end
                end,
                onQuickAction = function(actionId)
                    UIManager._OnQuickAction(actionId)
                end,
                onStateChanged = function()
                    UIManager.RefreshAll(stateRef_)
                end,
            }),
        },
    }

    local pageChildren = { dashboardPage_ }
    for _, tab in ipairs(Config.TABS) do
        local page = UIManager._CreatePage(tab.id, state)
        pages_[tab.id] = page
        table.insert(pageChildren, page)
    end

    return UI.Panel {
        id = "contentArea",
        flexGrow = 1,
        flexBasis = 0,
        width = "100%",
        overflow = "hidden",
        children = pageChildren,
    }
end

function UIManager._CreatePage(tabId, state)
    local content = UIManager._CreatePageContent(tabId, state)
    return UI.ScrollView {
        id = "page_" .. tabId,
        width = "100%",
        height = "100%",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        padding = S.page_padding,
        children = { content },
    }
end

function UIManager._CreatePageContent(tabId, state)
    local callbacks = {
        onStateChanged = function()
            UIManager.RefreshAll(stateRef_)
        end,
    }

    if tabId == "family" then
        return FamilyPage.Create(state, callbacks)
    elseif tabId == "industry" then
        return IndustryPage.Create(state, callbacks)
    elseif tabId == "market" then
        return MarketPage.Create(state, callbacks)
    elseif tabId == "military" then
        return MilitaryPage.Create(state, callbacks)
    elseif tabId == "world" then
        return WorldPage.Create(state, callbacks)
    end

    return UI.Label { text = tabId, fontSize = F.body, fontColor = C.text_muted }
end

-- ============================================================================
-- §4.7 底部导航（Bottom Navigation）
-- 高度 64px，bg_base 背景，顶部 1px paper_light 边框
-- 选中：accent_gold 图标+文字 + 顶部 2px accent_gold 指示线
-- 未选中：text_muted
-- ============================================================================

function UIManager._CreateBottomNav()
    local tabButtons = {}
    local eraAccent = Config.GetEraAccent(stateRef_)

    for _, tab in ipairs(Config.TABS) do
        local isActive = (tab.id == activeView_)
        table.insert(tabButtons, UI.Panel {
            id = "tab_" .. tab.id,
            flexGrow = 1,
            flexBasis = 0,
            height = S.bottom_nav_height,
            justifyContent = "center",
            alignItems = "center",
            gap = 3,
            pointerEvents = "auto",
            -- §4.7：选中 Tab 顶部 2px era_accent 指示线 + 微妙背景高亮
            borderTopWidth = isActive and 2 or 0,
            borderTopColor = eraAccent,
            backgroundColor = isActive and C.bg_elevated or nil,
            onPointerUp = (function(tabId)
                return function(self)
                    UIManager.SwitchTab(tabId)
                end
            end)(tab.id),
            children = {
                UI.Label {
                    id = "tabIcon_" .. tab.id,
                    text = tab.icon,
                    fontSize = S.icon_size,
                    fontColor = isActive and eraAccent or C.tab_inactive,
                    textAlign = "center",
                    pointerEvents = "none",
                },
                UI.Label {
                    id = "tabLabel_" .. tab.id,
                    text = tab.label,
                    fontSize = F.label,
                    fontColor = isActive and eraAccent or C.tab_inactive,
                    textAlign = "center",
                    pointerEvents = "none",
                },
            },
        })
    end

    return UI.Panel {
        id = "bottomNav",
        width = "100%",
        height = S.bottom_nav_height,
        flexDirection = "row",
        backgroundColor = C.bg_base,
        borderTopWidth = 1,
        borderTopColor = C.paper_light,
        children = tabButtons,
    }
end

-- ============================================================================
-- 导航逻辑
-- ============================================================================

function UIManager.SwitchTab(tabId)
    if tabId == activeView_ then
        UIManager._ShowView("dashboard")
        return
    end
    UIManager._ShowView(tabId)
end

function UIManager.BackToDashboard()
    UIManager._ShowView("dashboard")
end

function UIManager._ShowView(viewId)
    -- 隐藏所有页面
    if dashboardPage_ then
        dashboardPage_:SetVisible(viewId == "dashboard")
    end
    for id, page in pairs(pages_) do
        page:SetVisible(id == viewId)
    end

    -- 更新 Tab 高亮样式（§4.7 指示线 + 背景 + 图标/文字颜色）
    local eraAccent = Config.GetEraAccent(stateRef_)
    if uiRoot_ then
        for _, tab in ipairs(Config.TABS) do
            local isActive = (tab.id == viewId)
            local tabPanel = uiRoot_:FindById("tab_" .. tab.id)
            if tabPanel then
                tabPanel:SetStyle({
                    borderTopWidth = isActive and 2 or 0,
                    borderTopColor = eraAccent,
                    backgroundColor = isActive and C.bg_elevated or C.bg_base,
                })
            end
            local tabIcon = uiRoot_:FindById("tabIcon_" .. tab.id)
            if tabIcon then
                tabIcon:SetFontColor(isActive and eraAccent or C.tab_inactive)
            end
            local tabLabel = uiRoot_:FindById("tabLabel_" .. tab.id)
            if tabLabel then
                tabLabel:SetFontColor(isActive and eraAccent or C.tab_inactive)
            end
        end
    end

    activeView_ = viewId
end

-- ============================================================================
-- 快速操作处理
-- ============================================================================

function UIManager._OnQuickAction(actionId)
    local action = nil
    for _, a in ipairs(Config.QUICK_ACTIONS) do
        if a.id == actionId then
            action = a
            break
        end
    end
    if not action then return end

    local accent = Config.GetEraAccent(stateRef_)

    -- 注册回调
    ActionModals.SetCallbacks(stateRef_, function()
        UIManager.RefreshAll(stateRef_)
    end)

    -- 纯导航型（旧的两个，跳转到对应 Tab）
    if actionId == "personnel" then
        UIManager.SwitchTab("family")
        return
    elseif actionId == "finance" then
        UIManager.SwitchTab("market")
        return
    end

    -- 功能型弹窗（不扣 AP，由具体操作扣）
    if actionId == "technology" then
        ActionModals.ShowTechnology(stateRef_, accent)
    elseif actionId == "intelligence" then
        ActionModals.ShowIntelligence(stateRef_, accent)
    elseif actionId == "diplomacy" then
        ActionModals.ShowDiplomacy(stateRef_, accent)
    elseif actionId == "trade" then
        ActionModals.ShowTrade(stateRef_, accent)
    else
        UI.Toast.Show(action.label .. " 暂未开放", { variant = "info", duration = 1.2 })
    end
end

-- ============================================================================
-- §4.8 右侧 Drawer（Side Drawer Panel）
-- 从右侧滑入，宽度约 58%（drawer_width_pct），左侧 1px accent_gold 竖线
-- 左上+左下圆角 8px
-- ============================================================================

function UIManager._OpenSettings()
    if settingsDrawer_ then
        settingsDrawer_:Open()
        return
    end

    local menuCallbacks = {
        onStateChanged = function()
            UIManager.RefreshAll(stateRef_)
        end,
        onNewGame = onNewGame_,
    }

    settingsDrawer_ = UI.Drawer {
        id = "settingsDrawer",
        position = "right",
        size = S.drawer_width_pct .. "%",
        backgroundColor = C.bg_elevated,
        borderLeftWidth = 1,
        borderLeftColor = Config.GetEraAccent(stateRef_),
        borderTopLeftRadius = S.radius_drawer,
        borderBottomLeftRadius = S.radius_drawer,
        title = "⚙️ 设置与存档",
        titleFontSize = F.subtitle,
        titleFontColor = C.text_primary,
        children = {
            UI.ScrollView {
                width = "100%",
                height = "100%",
                padding = S.page_padding,
                children = {
                    MenuPage.Create(stateRef_, menuCallbacks),
                },
            },
        },
    }

    settingsDrawer_:Open()
end

-- ============================================================================
-- 刷新
-- ============================================================================

function UIManager.RefreshAll(state)
    stateRef_ = state
    if not uiRoot_ then return end

    TopBar.Refresh(uiRoot_, state)

    -- 重建仪表盘
    if dashboardPage_ then
        dashboardPage_:ClearChildren()
        local dashContent = Dashboard.Create(state, {
            onEndTurn = onEndTurn_,
            onProcessEvent = function(index)
                if onProcessEvent_ then
                    onProcessEvent_(index)
                end
            end,
            onQuickAction = function(actionId)
                UIManager._OnQuickAction(actionId)
            end,
            onStateChanged = function()
                UIManager.RefreshAll(stateRef_)
            end,
        })
        dashboardPage_:AddChild(dashContent)
    end

    -- 重建深度页
    for _, tabId in ipairs({ "family", "industry", "market", "military", "world" }) do
        local page = pages_[tabId]
        if page then
            page:ClearChildren()
            page:AddChild(UIManager._CreatePageContent(tabId, state))
        end
    end

    settingsDrawer_ = nil
end

function UIManager.GetRoot()
    return uiRoot_
end

function UIManager.GetActiveView()
    return activeView_
end

return UIManager
