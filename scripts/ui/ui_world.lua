-- ============================================================================
-- 世界页 UI v3：严格遵循 sarajevo_dynasty_ui_spec v1.1 §8.5
-- 子Tab系统（地图 | 关系 | 势力 | 报告）+ 节点信息抽屉
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local RegionsData = require("data.regions_data")
local MapWidget = require("ui.ui_map_widget")
local GrandPowers = require("systems.grand_powers")
local PlayerActionsGP = require("systems.player_actions_gp")

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

-- 子 Tab 定义（关系+势力合并为"势力与外交"）
local SUB_TABS = {
    { id = "map",       label = "地图" },
    { id = "factions",  label = "势力" },
    { id = "report",    label = "报告" },
}

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
    selectedNodeId_ = state.regions[1] and state.regions[1].id or nil
    activeSubTab_ = "map"
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
    local tabButtons = {}
    for _, tab in ipairs(SUB_TABS) do
        local isActive = (tab.id == activeSubTab_)
        table.insert(tabButtons, UI.Button {
            text = tab.label,
            fontSize = F.body,
            fontWeight = isActive and "bold" or "normal",
            fontColor = isActive and C.accent_gold or C.text_muted,
            backgroundColor = isActive and C.bg_elevated or { 0, 0, 0, 0 },
            borderRadius = S.radius_btn,
            paddingHorizontal = 14,
            paddingVertical = 6,
            flexGrow = 1,
            onClick = function()
                if activeSubTab_ ~= tab.id then
                    activeSubTab_ = tab.id
                    WorldPage._SwitchSubTab(stateRef_, tab.id)
                    WorldPage._RefreshTabBar()
                end
            end,
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
-- 子 Tab 切换
-- ============================================================================

function WorldPage._SwitchSubTab(state, tabId)
    if not tabContentPanel_ then return end
    tabContentPanel_:ClearChildren()

    if tabId == "map" then
        WorldPage._BuildMapTab(state)
    elseif tabId == "factions" then
        WorldPage._BuildFactionsTab(state)
    elseif tabId == "report" then
        WorldPage._BuildReportTab(state)
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
    mapWidget_:SetSelected(selectedNodeId_)
    mapWidget_:UpdateUnlocks(state)
    mapWidget_:SetEuropeState(state.europe)
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

    -- 查找区域数据
    local region = nil
    for _, r in ipairs(state.regions) do
        if r.id == selectedNodeId_ then
            region = r
            break
        end
    end
    if not region then return end

    drawerPanel_:AddChild(WorldPage._CreateNodeDrawer(state, region))
end

--- 创建节点信息抽屉 — 遵循 §8.5 节点信息抽屉规范
function WorldPage._CreateNodeDrawer(state, region)
    local secColor = region.security <= 2 and C.accent_red
        or (region.security >= 4 and C.accent_green or C.accent_amber)
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
                    maxAIName = aiId == "local_clan" and "本地望族"
                        or (aiId == "foreign_capital" and "外国资本"
                        or (aiId == "armed_group" and "武装集团" or aiId))
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
            local aiName = aiId == "local_clan" and "本地望族"
                or (aiId == "foreign_capital" and "外国资本"
                or (aiId == "armed_group" and "武装集团" or aiId))
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
            silver_reserve = { name = "银矿储量", icon = "Ag" },
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

    -- 操作按钮
    local actionChildren = {}
    if region.type == "mine" or region.type == "industrial" then
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
            onClick = function()
                if callbacksRef_ and callbacksRef_.onSwitchTab then
                    callbacksRef_.onSwitchTab("industry")
                end
            end,
        })
    end
    local infCost = Balance.INFLUENCE.cost_infiltrate
    local totalInfluence = GameState.CalcTotalInfluence(state)
    local canInfiltrate = (state.ap.current + (state.ap.temp or 0)) >= 2
        and totalInfluence >= infCost
    table.insert(actionChildren, UI.Button {
        text = string.format("政治渗透（2AP+%d影响力）", infCost),
        fontSize = F.label,
        fontColor = canInfiltrate and C.text_primary or C.text_muted,
        backgroundColor = canInfiltrate and C.paper_mid or C.bg_elevated,
        borderRadius = S.radius_btn,
        paddingHorizontal = 10,
        paddingVertical = 6,
        flexGrow = 1,
        disabled = not canInfiltrate,
        onClick = function(self)
            self.props.disabled = true
            WorldPage._DoPoliticalInfiltration(state, region)
        end,
    })

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

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_drawer,
        borderWidth = 1,
        borderColor = ctrlColor,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 头部：节点名称 + 类型 Badge + 控制方
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.bg_elevated,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = region.icon, fontSize = 24 },
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
                                        text = region.name,
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

            -- 属性区
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "column",
                gap = 5,
                children = {
                    WorldPage._InfoRow("治安",
                        RegionsData.GetSecurityText(region.security), secColor),
                    WorldPage._InfoRow("劳动力",
                        Config.FormatNumber(region.population) .. " 人", C.text_primary),
                    WorldPage._InfoRow("基建等级",
                        WorldPage._StarRating(region.development, 5), C.accent_gold),
                    WorldPage._InfoRow("文化价值",
                        tostring(region.culture), C.text_primary),
                    WorldPage._InfoRow("影响力",
                        tostring(region.influence or 0), C.accent_gold),
                },
            },

            -- 资源区（如果有）
            #resourceRows > 0 and (function()
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
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                gap = 8,
                children = actionChildren,
            },
        },
    }
end

-- ============================================================================
-- 势力子页 — §8.5 势力子页
-- ============================================================================

function WorldPage._BuildFactionsTab(state)
    local widgets = {
        UI.Panel {
            width = "100%",
            padding = S.card_padding,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = {
                UI.Label { text = "🤝", fontSize = S.icon_size },
                UI.Panel {
                    flexGrow = 1,
                    flexDirection = "column",
                    gap = 2,
                    children = {
                        UI.Label {
                            text = "势力与外交",
                            fontSize = F.card_title,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                        },
                        UI.Label {
                            text = "各方势力档案、外交关系与行动",
                            fontSize = F.label,
                            fontColor = C.text_muted,
                        },
                    },
                },
            },
        },
    }

    -- ── 合作度指示器 ──
    table.insert(widgets, WorldPage._CreateCollaborationHeader(state))

    -- ── 大国卡片 ──
    local activePowers = GrandPowers.GetActivePowers(state)
    if #activePowers > 0 then
        table.insert(widgets, WorldPage._SectionDivider("欧洲列强", C.accent_gold))
        for _, power in ipairs(activePowers) do
            table.insert(widgets, WorldPage._CreateGrandPowerCard(state, power))
        end
    end

    -- ── 本地 AI 势力（合并：关系 + 势力详情） ──
    if state.ai_factions and #state.ai_factions > 0 then
        table.insert(widgets, WorldPage._SectionDivider("本地势力", C.text_secondary))
        for _, faction in ipairs(state.ai_factions) do
            table.insert(widgets, WorldPage._CreateUnifiedFactionCard(state, faction))
        end
    end

    tabContentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        paddingTop = S.card_gap,
        children = widgets,
    })
end

--- 段落分隔线（复用）
function WorldPage._SectionDivider(text, color)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        paddingTop = 4,
        children = {
            UI.Divider { flexGrow = 1, color = C.divider },
            UI.Label {
                text = text,
                fontSize = F.label,
                fontColor = color,
                fontWeight = "bold",
            },
            UI.Divider { flexGrow = 1, color = C.divider },
        },
    }
end

-- ============================================================================
-- 合作度指示器
-- ============================================================================

--- 合作度指示条
function WorldPage._CreateCollaborationHeader(state)
    local score = state.collaboration_score or 0
    local label, labelColor = PlayerActionsGP.GetCollaborationLabel(score)

    -- 把合作度映射到 0-100 范围条 (-50 ~ +50 → 0 ~ 100)
    local barValue = math.max(0, math.min(100, score + 50))
    -- 颜色：负分偏绿（抵抗），正分偏红（合作）
    local barColor = score >= 0 and C.accent_red or C.accent_green

    return UI.Panel {
        width = "100%",
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "合作立场",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label {
                                text = label,
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = labelColor,
                            },
                            UI.Label {
                                text = "(" .. (score >= 0 and "+" or "") .. score .. ")",
                                fontSize = F.body_minor,
                                fontColor = C.text_secondary,
                            },
                        },
                    },
                },
            },
            -- 双向进度条（中间是 0，左侧抵抗，右侧合作）
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Label { text = "抵抗", fontSize = F.label, fontColor = C.accent_green, width = 28 },
                    UI.ProgressBar {
                        value = barValue / 100,
                        flexGrow = 1,
                        height = 6,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = barColor,
                    },
                    UI.Label { text = "合作", fontSize = F.label, fontColor = C.accent_red, width = 28 },
                },
            },
            UI.Label {
                text = "你的合作立场将影响战后清算结局",
                fontSize = F.label,
                fontColor = C.text_muted,
            },
        },
    }
end

-- ============================================================================
-- 大国卡片 + 玩家行动
-- ============================================================================

--- 大国势力标签颜色映射
local FACTION_COLORS = {
    central  = { 160, 50, 20, 255 },   -- 同盟国 铁锈色
    entente  = { 58, 107, 138, 255 },  -- 协约国 钢蓝
    axis     = { 140, 40, 40, 255 },   -- 轴心国 暗红
    allies   = { 74, 124, 89, 255 },   -- 同盟国(WWII) 暗绿
    neutral  = { 168, 152, 128, 255 }, -- 中立 灰棕
    communist = { 192, 57, 43, 255 },  -- 共产 红
}

local FACTION_LABELS = {
    central  = "同盟国",
    entente  = "协约国",
    axis     = "轴心国",
    allies   = "盟军",
    neutral  = "中立",
    communist = "东方阵营",
}

--- 姿态图标与标签
local STANCE_META = {
    collaborate = { icon = "🤝", label = "合作", color = { 212, 129, 10, 255 } },
    join        = { icon = "⚔️",  label = "加入", color = { 192, 57, 43, 255 } },
    counter     = { icon = "🛡️", label = "制衡", color = { 58, 107, 138, 255 } },
    resist      = { icon = "🔥", label = "抵抗", color = { 74, 124, 89, 255 } },
}

--- 创建大国详细卡片（军事/经济/厌战 + 阵营标签 + 行动按钮）
function WorldPage._CreateGrandPowerCard(state, power)
    local attColor = power.attitude_to_player >= 10 and C.accent_green
        or (power.attitude_to_player >= -10 and C.accent_amber or C.accent_red)

    local attText = power.attitude_to_player >= 0
        and ("+" .. power.attitude_to_player) or tostring(power.attitude_to_player)

    -- 阵营标签
    local factionLabel = FACTION_LABELS[power.faction] or "未知"
    local factionColor = FACTION_COLORS[power.faction] or C.text_muted

    -- 控制领土数量
    local territories = GrandPowers.GetControlledTerritories(state, power.id)
    local frontLines = GrandPowers.GetFrontLines(state, power.id)

    -- 属性行
    local statRows = {
        WorldPage._ControlBar("军事", math.floor(power.military), C.accent_red),
        WorldPage._ControlBar("经济", math.floor(power.economy), C.accent_gold),
        WorldPage._ControlBar("厌战", math.floor(power.war_fatigue), C.accent_amber),
        WorldPage._InfoRow("对我方态度", attText, attColor),
    }

    -- 控制领土
    if #territories > 0 then
        local names = {}
        for i, t in ipairs(territories) do
            if i <= 4 then
                table.insert(names, t.label)
            end
        end
        local suffix = #territories > 4 and ("…等" .. #territories .. "国") or ""
        table.insert(statRows, WorldPage._InfoRow(
            "控制领土", table.concat(names, "、") .. suffix, C.text_secondary))
    end

    -- 活跃前线
    if #frontLines > 0 then
        local targets = {}
        for _, fl in ipairs(frontLines) do
            if fl.status == "active" then
                table.insert(targets, "→" .. fl.target_label)
            end
        end
        if #targets > 0 then
            table.insert(statRows, WorldPage._InfoRow(
                "前线", table.concat(targets, " "), C.accent_red))
        end
    end

    -- ── 行动按钮区域 ──
    local actionChildren = {}
    local actions = PlayerActionsGP.GetAvailableActions(state, power.id)
    local stanceOrder = { "collaborate", "join", "counter", "resist" }

    for _, stanceId in ipairs(stanceOrder) do
        local group = actions[stanceId]
        if group and #group > 0 then
            local meta = STANCE_META[stanceId]
            -- 姿态分组标题
            local btnRow = {}
            for _, act in ipairs(group) do
                local enabled = act.available and (state.ap.current + (state.ap.temp or 0)) >= act.ap_cost
                local btnColor = enabled and meta.color or C.text_muted

                table.insert(btnRow, UI.Button {
                    text = act.icon .. " " .. act.label,
                    fontSize = F.label,
                    fontColor = enabled and C.text_primary or C.text_muted,
                    backgroundColor = enabled and { btnColor[1], btnColor[2], btnColor[3], 60 } or C.bg_surface,
                    borderRadius = S.radius_btn,
                    borderWidth = 1,
                    borderColor = enabled and { btnColor[1], btnColor[2], btnColor[3], 120 } or C.border_soft,
                    paddingHorizontal = 8,
                    paddingVertical = 5,
                    flexShrink = 1,
                    onClick = function(self)
                        self.props.disabled = true
                        if not enabled then
                            local reason = act.reason or "行动点不足"
                            UI.Toast.Show(reason, { variant = "error", duration = 1.5 })
                            return
                        end
                        local ok, msg = PlayerActionsGP.ExecuteAction(state, power.id, act.id)
                        if ok then
                            UI.Toast.Show(msg, { variant = "success", duration = 2 })
                        else
                            UI.Toast.Show(msg, { variant = "error", duration = 1.5 })
                        end
                        if callbacksRef_ and callbacksRef_.onStateChanged then
                            callbacksRef_.onStateChanged()
                        end
                    end,
                })
            end

            table.insert(actionChildren, UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 3,
                children = {
                    UI.Label {
                        text = meta.icon .. " " .. meta.label,
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = meta.color,
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        gap = 4,
                        children = btnRow,
                    },
                },
            })
        end
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 标题栏
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.bg_elevated,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    -- 阵营标签
                    UI.Panel {
                        backgroundColor = { factionColor[1], factionColor[2], factionColor[3], 50 },
                        borderRadius = 4,
                        paddingHorizontal = 6,
                        paddingVertical = 2,
                        children = {
                            UI.Label {
                                text = factionLabel,
                                fontSize = F.label,
                                fontWeight = "bold",
                                fontColor = factionColor,
                            },
                        },
                    },
                    -- 名称
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        gap = 1,
                        children = {
                            UI.Label {
                                text = power.label,
                                fontSize = F.card_title,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                        },
                    },
                    -- 军事值大数字
                    UI.Panel {
                        flexDirection = "column",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = tostring(math.floor(power.military)),
                                fontSize = F.data_mid,
                                fontWeight = "bold",
                                fontColor = C.accent_red,
                            },
                            UI.Label {
                                text = "军事",
                                fontSize = F.label,
                                fontColor = C.text_muted,
                            },
                        },
                    },
                },
            },

            -- 属性区
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "column",
                gap = 5,
                children = statRows,
            },

            -- 行动区（仅在有可用行动时显示）
            #actionChildren > 0 and WorldPage._BuildActionSection(state, actionChildren) or nil,
        },
    }
end

--- 行动区段（避免 table.unpack 不在最后位置的展开问题）
function WorldPage._BuildActionSection(state, actionChildren)
    local sectionChildren = {
        UI.Divider { color = C.divider },
        UI.Label {
            text = "可用行动 (AP:" .. (state.ap.current + (state.ap.temp or 0)) .. ")",
            fontSize = F.body_minor,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        },
    }
    for _, child in ipairs(actionChildren) do
        table.insert(sectionChildren, child)
    end
    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        paddingTop = 0,
        flexDirection = "column",
        gap = 6,
        children = sectionChildren,
    }
end

--- 统一势力卡片：合并关系 + 势力详情为一体
function WorldPage._CreateUnifiedFactionCard(state, faction)
    local att = faction.attitude or 0
    local attColor = att >= 10 and C.accent_green
        or (att >= -10 and C.accent_amber or C.accent_red)
    local attText = att >= 40 and "同盟"
        or (att >= 20 and "友善"
        or (att >= 0 and "中立"
        or (att >= -20 and "警惕"
        or "敌对")))
    local attIcon = att >= 40 and "🤝"
        or (att >= 20 and "😊"
        or (att >= 0 and "😐"
        or (att >= -20 and "😠"
        or "⚔️")))

    -- 关系值标准化到 0-1（-100 → 0, +100 → 1）
    local normalizedAtt = (att + 100) / 200
    local barColor = att >= 0 and C.accent_green or C.accent_red

    -- ── 势力属性行 ──
    local statRows = {}

    -- 核心资产（从地区数据推算）
    local controlledNodes = {}
    for _, r in ipairs(state.regions) do
        if r.ai_presence then
            for aiId, presence in pairs(r.ai_presence) do
                if aiId == faction.id and presence >= 30 then
                    table.insert(controlledNodes, r.name .. "(" .. presence .. "%)")
                end
            end
        end
    end
    if #controlledNodes > 0 then
        table.insert(statRows, WorldPage._InfoRow("控制区域",
            table.concat(controlledNodes, "、"), C.accent_amber))
    end

    -- 行动重心推测
    local focusText = "情报不足，无法判断"
    local focusColor = C.text_muted
    if faction.power then
        if faction.power >= 120 then
            focusText = "积极扩张"; focusColor = C.accent_red
        elseif faction.power >= 80 then
            focusText = "稳固发展"; focusColor = C.accent_amber
        else
            focusText = "保守防御"; focusColor = C.accent_green
        end
    end
    table.insert(statRows, WorldPage._InfoRow("行动倾向", focusText, focusColor))

    -- ── 近期互动记录（最近3条历史日志中关于该势力的） ──
    local recentLogs = {}
    if state.history_log then
        for i = #state.history_log, math.max(1, #state.history_log - 20), -1 do
            local entry = state.history_log[i]
            if entry.text and (
                string.find(entry.text, faction.name or "", 1, true) or
                string.find(entry.text, faction.id or "", 1, true)
            ) then
                table.insert(recentLogs, entry)
                if #recentLogs >= 3 then break end
            end
        end
    end

    local logChildren = {}
    if #recentLogs > 0 then
        for _, entry in ipairs(recentLogs) do
            table.insert(logChildren, UI.Label {
                text = string.format("[%d %s] %s",
                    entry.year, Config.QUARTER_NAMES[entry.quarter] or "", entry.text),
                fontSize = F.label,
                fontColor = C.text_muted,
                whiteSpace = "normal",
                lineHeight = 1.3,
            })
        end
    else
        table.insert(logChildren, UI.Label {
            text = "暂无近期互动记录",
            fontSize = F.label,
            fontColor = C.text_muted,
        })
    end

    -- ── 构建近期动向 section children ──
    local logSectionChildren = {
        UI.Label {
            text = "近期动向",
            fontSize = F.label,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        },
    }
    for _, c in ipairs(logChildren) do
        table.insert(logSectionChildren, c)
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 头部：图标 + 名称描述 + 势力值大数字
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.bg_elevated,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = faction.icon or "🏴", fontSize = S.icon_size },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = faction.name,
                                fontSize = F.card_title,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = faction.desc or "",
                                fontSize = F.label,
                                fontColor = C.text_muted,
                                whiteSpace = "normal",
                                lineHeight = 1.3,
                            },
                        },
                    },
                    -- 势力值大数字
                    UI.Panel {
                        flexDirection = "column",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = tostring(faction.power or 0),
                                fontSize = F.data_mid,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = "势力值",
                                fontSize = F.label,
                                fontColor = C.text_muted,
                            },
                        },
                    },
                },
            },

            -- 外交关系行：态度图标 + Badge + 关系值进度条
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingTop = 6,
                flexDirection = "column",
                gap = 4,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = "外交关系",
                                fontSize = F.label,
                                fontWeight = "bold",
                                fontColor = C.text_secondary,
                            },
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 4,
                                children = {
                                    UI.Label { text = attIcon, fontSize = 16 },
                                    UI.Panel {
                                        paddingHorizontal = 5,
                                        paddingVertical = 1,
                                        backgroundColor = { attColor[1], attColor[2], attColor[3], 40 },
                                        borderRadius = S.radius_badge,
                                        children = {
                                            UI.Label {
                                                text = attText .. " " .. tostring(att),
                                                fontSize = F.label,
                                                fontColor = attColor,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                    UI.ProgressBar {
                        value = normalizedAtt,
                        width = "100%",
                        height = 6,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = barColor,
                    },
                },
            },

            -- 属性区：控制区域、行动倾向
            #statRows > 0 and UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingTop = 6,
                flexDirection = "column",
                gap = 5,
                children = statRows,
            } or nil,

            -- 近期动向
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "column",
                gap = 3,
                children = logSectionChildren,
            },

            -- 外交按钮
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = S.card_padding,
                children = {
                    UI.Button {
                        text = "外交行动（2AP）",
                        fontSize = F.body_minor,
                        fontColor = C.accent_gold,
                        backgroundColor = C.bg_elevated,
                        borderWidth = 1,
                        borderColor = C.border_gold,
                        borderRadius = S.radius_btn,
                        paddingVertical = 6,
                        width = "100%",
                        onClick = function()
                            if callbacksRef_ and callbacksRef_.onAction then
                                callbacksRef_.onAction("diplomacy", { target = faction.id })
                            end
                        end,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 报告子页 — §8.5 报告子页
-- ============================================================================

function WorldPage._BuildReportTab(state)
    local widgets = {}

    -- 1. 本季结算摘要
    table.insert(widgets, WorldPage._CreateSeasonSummary(state))

    -- 2. 全局指标变化
    table.insert(widgets, WorldPage._CreateGlobalIndicators(state))

    -- 3. 历史日志
    table.insert(widgets, WorldPage._CreateLogCard(state))

    tabContentPanel_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        paddingTop = S.card_gap,
        children = widgets,
    })
end

--- 本季结算摘要
function WorldPage._CreateSeasonSummary(state)
    local quarterName = Config.QUARTER_NAMES[state.quarter] or ""
    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_gold,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = "📊", fontSize = S.icon_size },
                    UI.Label {
                        text = state.year .. "年" .. quarterName .. "季报",
                        fontSize = F.card_title,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                    },
                },
            },
            UI.Divider { color = C.divider },
            -- 关键指标网格（4列）
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                children = {
                    WorldPage._MetricCell("现金",
                        Config.FormatNumber(state.cash or 0),
                        C.accent_gold),
                    WorldPage._MetricCell("黄金",
                        tostring(state.gold or 0),
                        C.accent_amber),
                    WorldPage._MetricCell("影响力",
                        tostring(GameState.CalcTotalInfluence(state)),
                        C.accent_blue),
                    WorldPage._MetricCell("武装",
                        tostring(state.military and state.military.guards or 0),
                        C.accent_red),
                },
            },
        },
    }
end

--- 全局指标变化
function WorldPage._CreateGlobalIndicators(state)
    local era = Config.GetEraByYear(state.year)
    local standing = GameState.GetVictoryStanding(state)
    local claimText = state.victory and state.victory.claimed and "已宣布" or "未宣布"
    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Label {
                text = "全局态势",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Divider { color = C.divider },
            WorldPage._InfoRow("当前时代", era and era.label or "未知", C.accent_gold),
            WorldPage._InfoRow("战争状态",
                state.flags and state.flags.at_war and "⚔️ 战时" or "和平",
                state.flags and state.flags.at_war and C.accent_red or C.accent_green),
            WorldPage._InfoRow("地区总控制",
                WorldPage._CalcTotalControl(state) .. "%", C.text_primary),
            WorldPage._InfoRow("AI 威胁",
                WorldPage._CalcThreatLevel(state), C.accent_amber),
            WorldPage._InfoRow("经济领先",
                string.format("%+d", standing.lead.economic), standing.lead.economic >= 0 and C.accent_green or C.accent_red),
            WorldPage._InfoRow("军事领先",
                string.format("%+d", standing.lead.military), standing.lead.military >= 0 and C.accent_green or C.accent_red),
            WorldPage._InfoRow("统治领先",
                string.format("%+d", standing.lead.dominance), standing.lead.dominance >= 0 and C.accent_green or C.accent_red),
            WorldPage._InfoRow("胜利声明", claimText, state.victory and state.victory.claimed and C.accent_gold or C.text_secondary),
        },
    }
end

--- 历史日志
function WorldPage._CreateLogCard(state)
    local logChildren = {
        UI.Label {
            text = "近期记事",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_primary,
        },
        UI.Divider { color = C.divider },
    }

    local hasEntries = false
    if state.history_log then
        local start = math.max(1, #state.history_log - 14)
        for i = #state.history_log, start, -1 do
            local entry = state.history_log[i]
            hasEntries = true
            table.insert(logChildren, UI.Label {
                text = string.format("[%d %s] %s",
                    entry.year, Config.QUARTER_NAMES[entry.quarter] or "", entry.text),
                fontSize = F.label,
                fontColor = C.text_secondary,
                whiteSpace = "normal",
                lineHeight = 1.3,
            })
        end
    end

    if not hasEntries then
        table.insert(logChildren, UI.Label {
            text = "暂无记录",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
        })
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 6,
        children = logChildren,
    }
end

-- ============================================================================
-- 政治渗透操作
-- ============================================================================

--- 执行政治渗透：花费 2AP + 20影响力，增加玩家对目标地区的控制度 +8，等比减少 AI 势力占比
function WorldPage._DoPoliticalInfiltration(state, region)
    local infCost = Balance.INFLUENCE.cost_infiltrate

    -- 检查 AP
    if (state.ap.current + (state.ap.temp or 0)) < 2 then
        UI.Toast.Show("行动点不足（需要2AP）", { variant = "error", duration = 1.5 })
        return
    end

    -- 检查 Influence
    local totalInf = GameState.CalcTotalInfluence(state)
    if totalInf < infCost then
        UI.Toast.Show(string.format("影响力不足（需要%d，当前%d）", infCost, totalInf),
            { variant = "error", duration = 1.5 })
        return
    end

    -- 扣除 AP
    if not GameState.SpendAP(state, 2) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return
    end

    -- 扣除 Influence（按比例从各地区扣减）
    if totalInf > 0 then
        for _, r in ipairs(state.regions) do
            local ratio = (r.influence or 0) / totalInf
            local loss = math.floor(infCost * ratio + 0.5)
            r.influence = math.max(0, (r.influence or 0) - loss)
        end
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

    -- 增加地区影响力
    region.influence = (region.influence or 0) + 2

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
                width = 52,
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
                text = pct .. "%",
                fontSize = F.label,
                fontColor = { color[1], color[2], color[3], 255 },
                width = 32,
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

--- 指标格子（报告页用）
function WorldPage._MetricCell(label, value, color)
    return UI.Panel {
        flexGrow = 1,
        flexDirection = "column",
        alignItems = "center",
        gap = 2,
        padding = 4,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_badge,
        children = {
            UI.Label {
                text = value,
                fontSize = F.data_small,
                fontWeight = "bold",
                fontColor = color or C.text_primary,
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_muted,
            },
        },
    }
end

--- 计算地区总控制度
function WorldPage._CalcTotalControl(state)
    if not state.regions or #state.regions == 0 then return 0 end
    local total = 0
    for _, r in ipairs(state.regions) do
        total = total + (r.control or 0)
    end
    return math.floor(total / #state.regions)
end

--- 计算 AI 威胁等级
function WorldPage._CalcThreatLevel(state)
    if not state.ai_factions then return "未知" end
    local maxPower = 0
    for _, f in ipairs(state.ai_factions) do
        if (f.power or 0) > maxPower then maxPower = f.power end
    end
    if maxPower >= 150 then return "极高" end
    if maxPower >= 100 then return "较高" end
    if maxPower >= 60 then return "中等" end
    return "较低"
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
