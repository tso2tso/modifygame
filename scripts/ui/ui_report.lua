-- ============================================================================
-- 报告子页 UI：从 ui_world.lua 提取
-- 本季结算摘要、称号殿堂、全局态势、历史日志
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local TitlesData = require("data.titles_data")
local Titles = require("systems.titles")
local AudioManager = require("systems.audio_manager")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local ReportPanel = {}

-- ============================================================================
-- 模块状态
-- ============================================================================

---@type table|nil
local stateRef_ = nil
---@type table|nil
local callbacksRef_ = nil
---@type string 当前称号分支
local activeTitleCategoryId_ = "military"
---@type table|nil 当前称号详情弹窗
local currentTitleModal_ = nil
---@type table|nil UI 根节点引用（Modal 需要）
local uiRoot_ = nil

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 设置 UI 根节点（称号详情 Modal 必须 AddChild 到 UI 树才能渲染）
function ReportPanel.SetRoot(root)
    uiRoot_ = root
end

--- 新游戏/读档时重置
function ReportPanel.Reset()
    activeTitleCategoryId_ = "military"
    if currentTitleModal_ then
        currentTitleModal_:Close()
        currentTitleModal_ = nil
    end
    stateRef_ = nil
    callbacksRef_ = nil
end

--- 构建报告面板，返回 widget
---@param state table
---@param callbacks table
---@return table widget
function ReportPanel.Build(state, callbacks)
    stateRef_ = state
    callbacksRef_ = callbacks or {}

    local widgets = {}

    -- 1. 本季结算摘要
    table.insert(widgets, _CreateSeasonSummary(state))

    -- 1.5. 称号殿堂（常驻）
    local titlesCard = _CreateTitlesCard(state)
    if titlesCard then
        table.insert(widgets, titlesCard)
    end

    -- 2. 全局指标变化
    table.insert(widgets, _CreateGlobalIndicators(state))

    -- 3. 历史日志
    table.insert(widgets, _CreateLogCard(state))

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        paddingTop = S.card_gap,
        children = widgets,
    }
end

-- ============================================================================
-- 工具函数（模块内复用）
-- ============================================================================

local function _InfoRow(label, value, valueColor)
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

local function _MetricCell(label, value, color)
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

local function _CalcTotalControl(state)
    if not state.regions or #state.regions == 0 then return 0 end
    local total = 0
    for _, r in ipairs(state.regions) do
        total = total + (r.control or 0)
    end
    return math.floor(total / #state.regions)
end

local function _CalcThreatLevel(state)
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
-- 称号相关
-- ============================================================================

local TITLE_BRANCH_COLORS = {
    military      = { 200, 80, 80, 255 },
    plunder       = { 120, 110, 100, 255 },
    economy       = { 218, 165, 32, 255 },
    stock         = { 58, 107, 138, 255 },
    comprehensive = { 120, 140, 220, 255 },
}

local function getTitleBranchColor(catId)
    return TITLE_BRANCH_COLORS[catId] or C.accent_gold
end

local function getTitleCategoryById(catId)
    for _, cat in ipairs(TitlesData.CATEGORIES) do
        if cat.id == catId then return cat end
    end
    return TitlesData.CATEGORIES[1]
end

--- 自刷新：重新构建报告面板
local function refreshReportTab()
    if callbacksRef_ and callbacksRef_.onStateChanged then
        callbacksRef_.onStateChanged()
    end
end

local function getNewTitleIds(state)
    local ids = {}
    for _, item in ipairs(state.titles_new or {}) do
        local id = type(item) == "table" and item.id or item
        if id then ids[id] = true end
    end
    return ids
end

-- ============================================================================
-- 称号分支 Tab
-- ============================================================================

function _CreateTitleBranchTab(state, cat, isActive)
    local unlocked, total = Titles.CategoryProgress(state, cat.id)
    local progress = total > 0 and (unlocked / total) or 0
    local accent = getTitleBranchColor(cat.id)

    return UI.Panel {
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        minWidth = 70,
        padding = 6,
        backgroundColor = isActive and { accent[1], accent[2], accent[3], 55 } or C.bg_elevated,
        borderRadius = S.radius_card,
        borderWidth = isActive and 1.5 or 1,
        borderColor = isActive and accent or { 60, 60, 70, 255 },
        flexDirection = "column",
        alignItems = "center",
        gap = 2,
        pointerEvents = "auto",
        onPointerUp = Config.TapGuard(function()
            if activeTitleCategoryId_ ~= cat.id then
                activeTitleCategoryId_ = cat.id
                refreshReportTab()
            end
        end),
        children = {
            UI.Label {
                text = (cat.icon or "•") .. " " .. cat.label,
                fontSize = isActive and F.body or F.body_minor,
                fontWeight = isActive and "bold" or "medium",
                fontColor = isActive and accent or C.text_secondary,
                pointerEvents = "none",
            },
            UI.Panel {
                width = "90%",
                height = 3,
                borderRadius = 2,
                backgroundColor = { 50, 50, 60, 255 },
                children = {
                    UI.Panel {
                        width = string.format("%d%%", math.floor(progress * 100)),
                        height = "100%",
                        borderRadius = 2,
                        backgroundColor = accent,
                    },
                },
            },
            UI.Label {
                text = string.format("%d/%d", unlocked, total),
                fontSize = 10,
                fontColor = C.text_muted,
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 称号肖像
-- ============================================================================

function _CreateTitlePortrait(title, isUnlocked, accent, size)
    local isDetail = (size == "detail")
    local detailSize = 380
    local w = isDetail and detailSize or (size or 92)
    local h = isDetail and detailSize or (size or 92)

    if title.portraitImage then
        return UI.Panel {
            width = w,
            height = h,
            borderRadius = S.radius_card,
            backgroundImage = title.portraitImage,
            backgroundFit = "cover",
            borderWidth = 1,
            borderColor = isUnlocked and accent or C.border_card,
            imageTint = isUnlocked and nil or { 120, 120, 120, 255 },
            flexShrink = 0,
        }
    end

    return UI.Panel {
        width = isDetail and detailSize or (size or 92),
        height = isDetail and detailSize or (size or 92),
        borderRadius = S.radius_card,
        backgroundColor = C.bg_inset,
        borderWidth = 1,
        borderColor = isUnlocked and accent or C.border_soft,
        justifyContent = "center",
        alignItems = "center",
        flexDirection = "column",
        gap = 3,
        flexShrink = 0,
        children = {
            UI.Label {
                text = title.icon or "🏅",
                fontSize = isDetail and 72 or 36,
                fontColor = isUnlocked and accent or C.text_muted,
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 称号详情弹窗
-- ============================================================================

local function _CloseTitleModal()
    if currentTitleModal_ then
        currentTitleModal_:Close()
        currentTitleModal_ = nil
    end
end

local function _ShowTitleDetail(state, title, cat)
    _CloseTitleModal()

    local isUnlocked = state.titles_unlocked and state.titles_unlocked[title.id]
    local accent = getTitleBranchColor(cat.id)
    local statusText = isUnlocked and "已获得" or "未达成"
    local statusColor = isUnlocked and C.accent_green or C.text_muted
    local unlockedTurn = isUnlocked and tostring(isUnlocked) or "尚未获得"

    local content = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 10,
                paddingBottom = 12,
                children = {
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        justifyContent = "center",
                        children = {
                            _CreateTitlePortrait(title, isUnlocked, accent, "detail"),
                        },
                    },
                    UI.Panel {
                        width = "100%",
                        backgroundColor = C.paper_dark,
                        borderRadius = S.radius_card,
                        borderWidth = 1,
                        borderColor = accent,
                        padding = 7,
                        flexDirection = "column",
                        gap = 3,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "space-between",
                                alignItems = "center",
                                children = {
                                    UI.Panel {
                                        flexDirection = "row",
                                        alignItems = "center",
                                        gap = 8,
                                        flexShrink = 1,
                                        children = {
                                            UI.Label { text = title.icon or "🏅", fontSize = S.icon_size },
                                            UI.Label {
                                                text = title.name,
                                                fontSize = F.card_title,
                                                fontWeight = "bold",
                                                fontColor = isUnlocked and C.text_primary or C.text_muted,
                                                flexShrink = 1,
                                            },
                                        },
                                    },
                                    UI.Panel {
                                        paddingHorizontal = 8,
                                        paddingVertical = 3,
                                        borderRadius = S.radius_badge,
                                        backgroundColor = { statusColor[1], statusColor[2], statusColor[3], 45 },
                                        children = {
                                            UI.Label {
                                                text = statusText,
                                                fontSize = F.label,
                                                fontWeight = "bold",
                                                fontColor = statusColor,
                                            },
                                        },
                                    },
                                },
                            },
                            UI.Divider { color = C.divider },
                            UI.Label {
                                text = title.desc,
                                fontSize = F.body,
                                fontColor = C.text_secondary,
                                whiteSpace = "normal",
                                lineHeight = 1.35,
                            },
                            _InfoRow("所属分支", (cat.icon or "•") .. " " .. cat.label, accent),
                            _InfoRow("获得回合", unlockedTurn, isUnlocked and C.accent_green or C.text_muted),
                            -- 称号奖励展示
                            (function()
                                local rewards = title.rewards
                                if not rewards then return nil end
                                local rewardChildren = {}
                                if rewards.modifiers then
                                    for _, mod in ipairs(rewards.modifiers) do
                                        table.insert(rewardChildren, UI.Label {
                                            text = "• " .. mod.label,
                                            fontSize = F.body,
                                            fontColor = isUnlocked and C.accent_green or C.text_muted,
                                        })
                                    end
                                end
                                if rewards.unlock_features then
                                    for _, feat in ipairs(rewards.unlock_features) do
                                        local featLabel = feat
                                        if feat == "foreign_trade" then featLabel = "解锁跨国贸易订单"
                                        elseif feat == "expedition" then featLabel = "解锁军事远征"
                                        elseif feat == "venture" then featLabel = "解锁商业远征"
                                        elseif feat == "gp_actions" then featLabel = "解锁大国外交互动" end
                                        table.insert(rewardChildren, UI.Label {
                                            text = "★ " .. featLabel,
                                            fontSize = F.body,
                                            fontWeight = "bold",
                                            fontColor = isUnlocked and C.accent_gold or C.text_muted,
                                        })
                                    end
                                end
                                if #rewardChildren == 0 then return nil end
                                return UI.Panel {
                                    width = "100%",
                                    flexDirection = "column",
                                    gap = 3,
                                    marginTop = 4,
                                    children = {
                                        UI.Label {
                                            text = "奖励",
                                            fontSize = F.label,
                                            fontWeight = "bold",
                                            fontColor = C.text_secondary,
                                        },
                                        table.unpack(rewardChildren),
                                    },
                                }
                            end)(),
                        },
                    },
                },
            },
        },
    }

    currentTitleModal_ = UI.Modal {
        title = title.name,
        size = "fullscreen",
        closeOnOverlay = true,
        closeOnEscape = true,
        contentPadding = { 0, 12, 12, 12 },
        onClose = function()
            Config.ConsumeTap()
            currentTitleModal_ = nil
        end,
    }
    currentTitleModal_:AddContent(content)
    if uiRoot_ then
        uiRoot_:AddChild(currentTitleModal_)
    end
    currentTitleModal_:Open()
end

-- ============================================================================
-- 称号节点
-- ============================================================================

function _CreateTitleNode(state, title, cat, isNew)
    local isUnlocked = state.titles_unlocked and state.titles_unlocked[title.id]
    local accent = getTitleBranchColor(cat.id)
    local statusText = isUnlocked and "已获得" or "未达成"
    local statusColor = isUnlocked and C.accent_green or C.text_muted
    if isNew then
        statusText = "新称号"
        statusColor = C.accent_gold
    end

    local topRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        pointerEvents = "none",
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 7,
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = isUnlocked and (title.icon or "🏅") or "◇",
                        fontSize = F.body,
                        fontColor = isUnlocked and accent or C.text_muted,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = title.name,
                        fontSize = F.body,
                        fontWeight = isUnlocked and "bold" or "medium",
                        fontColor = isUnlocked and C.text_primary or C.text_muted,
                        flexShrink = 1,
                        pointerEvents = "none",
                    },
                },
            },
            UI.Panel {
                paddingHorizontal = 6,
                paddingVertical = 2,
                borderRadius = S.radius_badge,
                backgroundColor = { statusColor[1], statusColor[2], statusColor[3], 38 },
                children = {
                    UI.Label {
                        text = statusText,
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = statusColor,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }

    local descRow = UI.Label {
        text = title.desc,
        fontSize = F.label,
        fontColor = C.text_muted,
        pointerEvents = "none",
        marginLeft = 21,
    }

    local nodeChildren = { topRow, descRow }

    return UI.Panel {
        width = "100%",
        paddingVertical = 6,
        paddingHorizontal = 9,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderLeftWidth = 3,
        borderLeftColor = isUnlocked and accent or { 60, 60, 70, 255 },
        borderWidth = 0,
        flexDirection = "column",
        gap = 3,
        pointerEvents = "auto",
        onPointerUp = (isUnlocked or isNew) and Config.TapGuard(function()
            _ShowTitleDetail(state, title, cat)
        end) or nil,
        children = nodeChildren,
    }
end

-- ============================================================================
-- 称号卡片
-- ============================================================================

function _CreateTitlesCard(state)
    local unlockedCount = Titles.UnlockedCount(state)
    local totalCount = #TitlesData.TITLES
    local hasNew = state.titles_new and #state.titles_new > 0
    local newIds = getNewTitleIds(state)
    local activeCat = getTitleCategoryById(activeTitleCategoryId_)
    if not activeCat then
        activeCat = TitlesData.CATEGORIES[1]
        activeTitleCategoryId_ = activeCat and activeCat.id or activeTitleCategoryId_
    end
    local activeAccent = getTitleBranchColor(activeCat.id)
    local children = {}

    -- 标题行
    table.insert(children, UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = "🏅", fontSize = S.icon_size },
                    UI.Label {
                        text = "称号殿堂",
                        fontSize = F.card_title,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                    },
                },
            },
            UI.Label {
                text = string.format("%d/%d", unlockedCount, totalCount),
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = unlockedCount > 0 and C.accent_gold or C.text_muted,
            },
        },
    })
    table.insert(children, UI.Divider { color = C.divider })

    -- 新解锁提示
    if hasNew then
        AudioManager.PlayEffect("title_unlock")
        local newNames = {}
        for _, tid in ipairs(state.titles_new) do
            local id = type(tid) == "table" and tid.id or tid
            local t = TitlesData.GetById(id)
            if t then
                table.insert(newNames, "「" .. t.name .. "」")
            end
        end
        table.insert(children, UI.Panel {
            width = "100%",
            backgroundColor = "#3a2a00",
            borderRadius = 4,
            padding = 7,
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label { text = "✨", fontSize = F.body },
                UI.Label {
                    text = "新获得：" .. table.concat(newNames, "  "),
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = "#FFD700",
                    flexShrink = 1,
                },
            },
        })
        state.titles_new = {}
    end

    -- 一级目录：称号分支
    local tabChildren = {}
    for _, cat in ipairs(TitlesData.CATEGORIES) do
        table.insert(tabChildren, _CreateTitleBranchTab(state, cat, cat.id == activeCat.id))
    end
    table.insert(children, UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 5,
        children = tabChildren,
    })

    -- 二级目录：当前分支称号
    local catTitles = TitlesData.GetByCategory(activeCat.id)
    local unlockedInCat = 0
    for _, title in ipairs(catTitles) do
        if state.titles_unlocked and state.titles_unlocked[title.id] then
            unlockedInCat = unlockedInCat + 1
        end
    end

    table.insert(children, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingHorizontal = 2,
        children = {
            UI.Label {
                text = (activeCat.icon or "•") .. " " .. activeCat.label .. "分支",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = activeAccent,
            },
            UI.Label {
                text = string.format("解锁后可点击查看详情  (%d/%d)", unlockedInCat, #catTitles),
                fontSize = F.label,
                fontColor = C.text_secondary,
            },
        },
    })

    local titleNodes = {}
    for _, title in ipairs(catTitles) do
        table.insert(titleNodes, _CreateTitleNode(
            state,
            title,
            activeCat,
            newIds[title.id] == true
        ))
    end
    table.insert(children, UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
        children = titleNodes,
    })

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_gold,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 7,
        children = children,
    }
end

-- ============================================================================
-- 本季结算摘要
-- ============================================================================

function _CreateSeasonSummary(state)
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
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                children = {
                    _MetricCell("现金",
                        Config.FormatNumber(state.cash or 0),
                        C.accent_gold),
                    _MetricCell("黄金",
                        tostring(state.gold or 0),
                        C.accent_amber),
                    _MetricCell("控制度",
                        tostring(GameState.CalcTotalControl(state)),
                        C.accent_blue),
                    _MetricCell("武装",
                        tostring(state.military and state.military.guards or 0),
                        C.accent_red),
                },
            },
        },
    }
end

-- ============================================================================
-- 全局指标
-- ============================================================================

function _CreateGlobalIndicators(state)
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
            _InfoRow("当前时代", era and era.label or "未知", C.accent_gold),
            _InfoRow("战争状态",
                state.flags and state.flags.at_war and "⚔️ 战时" or "和平",
                state.flags and state.flags.at_war and C.accent_red or C.accent_green),
            _InfoRow("地区总控制",
                _CalcTotalControl(state) .. "%", C.text_primary),
            _InfoRow("AI 威胁",
                _CalcThreatLevel(state), C.accent_amber),
            _InfoRow("经济领先",
                string.format("%+d", standing.lead.economic), standing.lead.economic >= 0 and C.accent_green or C.accent_red),
            _InfoRow("军事领先",
                string.format("%+d", standing.lead.military), standing.lead.military >= 0 and C.accent_green or C.accent_red),
            _InfoRow("统治领先",
                string.format("%+d", standing.lead.dominance), standing.lead.dominance >= 0 and C.accent_green or C.accent_red),
            _InfoRow("胜利声明", claimText, state.victory and state.victory.claimed and C.accent_gold or C.text_secondary),
        },
    }
end

-- ============================================================================
-- 历史日志
-- ============================================================================

function _CreateLogCard(state)
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

return ReportPanel
