-- ============================================================================
-- 世界页 UI：地区节点、AI 势力、历史日志
-- 设计规范：sarajevo_dynasty_ui_spec §6.6
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local RegionsData = require("data.regions_data")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local WorldPage = {}

---@type table
local stateRef_ = nil

--- 创建世界页完整内容
---@param state table
---@param callbacks table
---@return table widget
function WorldPage.Create(state, callbacks)
    stateRef_ = state
    return WorldPage._BuildContent(state)
end

function WorldPage._BuildContent(state)
    local children = {}

    -- 1. 地区标题卡片
    table.insert(children, UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_gold,
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Label {
                text = "波黑地区",
                fontSize = F.card_title,
                fontWeight = "bold",
                fontColor = C.accent_gold,
            },
            UI.Divider { color = C.divider },
            UI.Label {
                text = state.flags.at_war and "战争时期 - 局势动荡不安"
                    or "和平时期 - " .. state.year .. "年",
                fontSize = F.body_minor,
                fontColor = state.flags.at_war and C.accent_red or C.text_secondary,
            },
        },
    })

    -- 地区卡片
    for _, region in ipairs(state.regions) do
        table.insert(children, WorldPage._CreateRegionCard(state, region))
    end

    -- 2. AI 势力（§6.6 关系面板）
    table.insert(children, UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 6,
        children = WorldPage._CreateAISection(state),
    })

    -- 3. 近期日志
    table.insert(children, WorldPage._CreateLogCard(state))

    return UI.Panel {
        id = "worldContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = children,
    }
end

--- 地区卡片（§6.6 地图区 图钉样式）
function WorldPage._CreateRegionCard(state, region)
    local secColor = region.security <= 2 and C.accent_red
        or (region.security >= 4 and C.accent_green or C.accent_amber)
    local devColor = region.development <= 1 and C.text_muted
        or (region.development >= 3 and C.accent_green or C.text_primary)

    -- 控制度颜色
    local ctrlColor = region.control >= 60 and C.accent_green
        or (region.control >= 30 and C.accent_amber or C.accent_red)

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 标题行
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = region.icon, fontSize = S.icon_size },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        gap = 1,
                        children = {
                            UI.Label {
                                text = region.name,
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = region.desc,
                                fontSize = F.label,
                                fontColor = C.text_muted,
                                whiteSpace = "normal",
                                lineHeight = 1.3,
                            },
                        },
                    },
                },
            },
            -- 属性行
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = S.card_padding,
                flexDirection = "column",
                gap = 4,
                children = {
                    WorldPage._InfoRow("治安",
                        RegionsData.GetSecurityText(region.security), secColor),
                    WorldPage._InfoRow("基建",
                        RegionsData.GetDevelopmentText(region.development), devColor),
                    WorldPage._InfoRow("控制度",
                        region.control .. "%", ctrlColor),
                    -- 控制度条
                    UI.ProgressBar {
                        value = region.control / 100,
                        width = "100%",
                        height = 5,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = ctrlColor,
                    },
                    WorldPage._InfoRow("人口", tostring(region.population), C.text_primary),
                    WorldPage._InfoRow("文化", tostring(region.culture), C.text_primary),
                },
            },
        },
    }
end

--- AI 势力部分（§6.6 关系面板 — 关系值进度条 -100~+100）
function WorldPage._CreateAISection(state)
    local widgets = {
        UI.Label {
            text = "势力动态",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_primary,
        },
        UI.Divider { color = C.divider },
    }

    for _, faction in ipairs(state.ai_factions) do
        local attColor = faction.attitude >= 10 and C.accent_green
            or (faction.attitude >= -10 and C.accent_amber or C.accent_red)
        local attText = faction.attitude >= 20 and "友善"
            or (faction.attitude >= 0 and "中立"
            or (faction.attitude >= -20 and "警惕" or "敌对"))

        -- §6.6 关系值进度条（-100~+100，从中心展开）
        -- 标准化到 0-1 范围：(attitude + 100) / 200
        local normalizedAtt = (faction.attitude + 100) / 200
        local barColor = faction.attitude >= 0 and C.accent_green or C.accent_red

        table.insert(widgets, UI.Panel {
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
                        UI.Label { text = faction.icon, fontSize = S.icon_size },
                        UI.Label {
                            text = faction.name,
                            fontSize = F.body,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                            flexGrow = 1,
                        },
                        -- 态度标签
                        UI.Panel {
                            paddingHorizontal = 6,
                            paddingVertical = 2,
                            backgroundColor = C.paper_dark,
                            borderRadius = S.radius_badge,
                            children = {
                                UI.Label {
                                    text = attText .. " " .. tostring(faction.attitude),
                                    fontSize = F.label,
                                    fontColor = attColor,
                                },
                            },
                        },
                    },
                },
                -- §6.6 关系值进度条
                UI.ProgressBar {
                    value = normalizedAtt,
                    width = "100%",
                    height = 6,
                    borderRadius = 3,
                    trackColor = C.bg_surface,
                    fillColor = barColor,
                },
                WorldPage._InfoRow("势力值", tostring(faction.power), C.text_primary),
                UI.Label {
                    text = faction.desc,
                    fontSize = F.label,
                    fontColor = C.text_muted,
                    whiteSpace = "normal",
                    lineHeight = 1.3,
                },
            },
        })
    end

    return widgets
end

--- 近期日志卡片
function WorldPage._CreateLogCard(state)
    -- 注意：table.unpack 放在表构造器中间位置只会展开第一个元素
    -- 所以先构建 children 数组再整体传入
    local logChildren = {
        UI.Label {
            text = "近期记事",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_primary,
        },
        UI.Divider { color = C.divider },
    }

    local start = math.max(1, #state.history_log - 9)
    local hasEntries = false
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

function WorldPage._InfoRow(label, value, valueColor)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label { text = label, fontSize = F.body_minor, fontColor = C.text_secondary },
            UI.Label { text = value, fontSize = F.body_minor, fontWeight = "bold", fontColor = valueColor or C.text_primary },
        },
    }
end

function WorldPage.Refresh(root, state)
    stateRef_ = state
end

return WorldPage
