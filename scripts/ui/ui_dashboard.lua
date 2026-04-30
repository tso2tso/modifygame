-- ============================================================================
-- 仪表盘页（主视图）— 精简版
-- 事件流 + 焦点卡片(纯展示) + 快速操作(4项) + 本季概览(紧凑) + 结束回合
-- 设计语言：工业帝国主义时代的家族账簿
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Economy = require("systems.economy")
local Events = require("systems.events")
local Actions = require("systems.actions")
local Balance = require("data.balance")
local RegionsData = require("data.regions_data")
local PlayerActionsGP = require("systems.player_actions_gp")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local Dashboard = {}

---@type table 游戏状态引用
local stateRef_ = nil
---@type table 回调集合
local callbacks_ = {}

--- 创建仪表盘内容
---@param state table
---@param callbacks table { onEndTurn, onProcessEvent, onQuickAction, onStateChanged, onLightRefresh }
---@return table widget
function Dashboard.Create(state, callbacks)
    stateRef_ = state
    callbacks_ = callbacks or {}
    return Dashboard._BuildContent(state)
end

--- 轻量刷新：仅通过 FindById 更新关键控件属性，不修改控件树结构
--- 避免 ScrollView 因子树变化而重置滚动位置
function Dashboard.RefreshDynamic(root, state)
    stateRef_ = state
    if not root then return end

    -- 1. 招募按钮：更新 disabled + text
    local BW = Balance.WORKERS
    local hireCost = math.floor(BW.hire_cost * GameState.GetLaborCostFactor(state)
        * (1 - GameState.GetInfluenceRecruitDiscount(state)))
    local hireBtn = root:FindById("focusHireBtn")
    if hireBtn then
        local canHire = state.cash >= hireCost * 5 and (state.ap.current + (state.ap.temp or 0)) >= 1
        hireBtn.props.disabled = not canHire
        if hireBtn.SetText then
            hireBtn:SetText(string.format("招募工人 +5    %d 克朗 / 1 AP", hireCost * 5))
        end
    end

    -- 1.5 利用率 + 维护费：招募后实时更新
    local utilLabel = root:FindById("focusUtil")
    if utilLabel then
        local totalIdealWorkers = 0
        for _, m in ipairs(state.mines) do
            totalIdealWorkers = totalIdealWorkers + m.level * 10
        end
        local utilization = math.floor(state.workers.hired / math.max(1, totalIdealWorkers) * 100)
        local utilColor = Config.GetUtilColor(utilization)
        utilLabel:SetText(utilization .. "%")
        if utilLabel.SetFontColor then utilLabel:SetFontColor(utilColor) end
    end
    local maintLabel = root:FindById("focusMaint")
    if maintLabel then
        local workerExpense = state.workers.hired * state.workers.wage
        maintLabel:SetText("-" .. Config.FormatNumber(workerExpense))
        if maintLabel.SetFontColor then
            maintLabel:SetFontColor(workerExpense > state.cash * 0.3 and C.accent_red or C.text_secondary)
        end
    end

    -- 2. 快速操作：更新可用状态标签 + 外层透明度
    for _, action in ipairs(Config.QUICK_ACTIONS) do
        local totalAP = state.ap.current + (state.ap.temp or 0)
        local canAfford = totalAP >= action.ap_cost

        local qaPanel = root:FindById("qa_" .. action.id)
        if qaPanel then
            qaPanel:SetStyle({ opacity = canAfford and 1.0 or 0.45 })
        end

        local qaStatus = root:FindById("qa_status_" .. action.id)
        if qaStatus then
            qaStatus:SetText(canAfford and "可执行" or "AP不足")
            if qaStatus.SetFontColor then
                qaStatus:SetFontColor(canAfford and C.text_secondary or C.accent_red)
            end
        end
    end
end

--- 构建全部内容
function Dashboard._BuildContent(state)
    local era = Config.GetEraByYear(state.year)
    local children = {}

    -- 本季动态（战斗结果、AI行动、警告）
    local msgSection = Dashboard._TurnMessagesSection(state, era)
    if msgSection then
        table.insert(children, msgSection)
    end
    -- 合作度状态栏（大国系统激活后显示）
    local collabBar = Dashboard._CollaborationBar(state)
    if collabBar then
        table.insert(children, collabBar)
    end
    -- 事件流
    table.insert(children, Dashboard._EventSection(state, era))
    -- 焦点卡片（纯展示，无操作按钮）
    if #state.mines > 0 then
        table.insert(children, Dashboard._FocusCard(state, state.mines[1], era))
    end
    -- 快速操作（仅消耗 AP 的 4 项）
    table.insert(children, Dashboard._QuickActions(state, era))
    -- 本季概览（紧凑单行）
    table.insert(children, Dashboard._SeasonOverview(state))
    -- 结束回合
    table.insert(children, Dashboard._EndTurnButton(state, era))

    return UI.Panel {
        id = "dashboardContent",
        width = "100%",
        flexDirection = "column",
        gap = S.section_gap,
        children = children,
    }
end

-- ============================================================================
-- 本季动态（Turn Messages）
-- ============================================================================

local MSG_TYPE_STYLE = {
    combat_win  = { icon = "⚔",  bg = { 45, 100, 55, 255 },  fg = { 180, 255, 180, 255 } },
    combat_lose = { icon = "💥", bg = { 120, 35, 35, 255 },  fg = { 255, 200, 200, 255 } },
    ai_move     = { icon = "📢", bg = { 60, 55, 45, 255 },   fg = { 200, 195, 175, 255 } },
    warning     = { icon = "⚠",  bg = { 110, 85, 30, 255 },  fg = { 255, 230, 160, 255 } },
}

function Dashboard._SectionHeader(title, badgeText, badgeColor)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 7,
                children = {
                    UI.Panel {
                        width = 3,
                        height = 16,
                        borderRadius = 2,
                        backgroundColor = badgeColor or C.accent_gold,
                    },
                    UI.Label {
                        text = title,
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                },
            },
            badgeText and Dashboard._Badge(badgeText, badgeColor or C.paper_mid) or UI.Panel { width = 0, height = 0 },
        },
    }
end

function Dashboard._Badge(text, bg, fg)
    return UI.Panel {
        backgroundColor = bg or C.paper_mid,
        borderRadius = S.radius_badge,
        paddingHorizontal = 7,
        paddingVertical = 3,
        children = {
            UI.Label {
                text = text,
                fontSize = F.label,
                fontWeight = "bold",
                fontColor = fg or { 30, 25, 15, 255 },
                pointerEvents = "none",
            },
        },
    }
end

function Dashboard._FineDivider()
    return UI.Panel {
        width = "100%",
        height = S.hairline_height,
        backgroundColor = C.divider,
    }
end

--- 仪表盘合作度状态栏（紧凑单行）
function Dashboard._CollaborationBar(state)
    if not state._gp_initialized then return nil end

    local score = state.collaboration_score or 0
    local label = PlayerActionsGP.GetCollaborationLabel(score)

    -- 颜色：抵抗→绿系 / 合作→红系 / 中间→琥珀
    local barColor
    if score <= -20 then
        barColor = C.accent_green
    elseif score >= 20 then
        barColor = C.accent_red
    else
        barColor = C.accent_amber
    end

    -- 进度条值：-50~+50 映射到 0~100
    local pct = math.max(0, math.min(100, (score + 50) * 100 / 100))

    return UI.Panel {
        width = "100%",
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_soft,
        padding = 8,
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Label {
                text = "🤝",
                fontSize = 16,
                width = 20,
                pointerEvents = "none",
            },
            UI.Label {
                text = "合作度",
                fontSize = F.label,
                fontColor = C.text_secondary,
                pointerEvents = "none",
            },
            -- 进度条容器
            UI.Panel {
                flexGrow = 1,
                height = 6,
                borderRadius = 3,
                backgroundColor = { 50, 45, 35, 255 },
                children = {
                    UI.Panel {
                        width = string.format("%.0f%%", pct),
                        height = "100%",
                        borderRadius = 3,
                        backgroundColor = barColor,
                    },
                },
            },
            -- 数值标签
            UI.Label {
                text = string.format("%s%d", score > 0 and "+" or "", score),
                fontSize = F.label,
                fontWeight = "bold",
                fontColor = barColor,
                pointerEvents = "none",
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_muted,
                pointerEvents = "none",
            },
        },
    }
end

function Dashboard._TurnMessagesSection(state, era)
    local messages = state.turn_messages or {}
    if #messages == 0 then return nil end

    local accent = (era and era.accent) or C.accent_gold

    local cards = {}
    for i, msg in ipairs(messages) do
        local style = MSG_TYPE_STYLE[msg.type] or MSG_TYPE_STYLE.ai_move
        if i > 1 then
            table.insert(cards, UI.Panel {
                width = "100%", height = 1,
                backgroundColor = { 80, 70, 55, 100 },
            })
        end
        table.insert(cards, UI.Panel {
            width = "100%",
            paddingVertical = 6, paddingHorizontal = 10,
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            backgroundColor = style.bg,
            borderRadius = S.radius_btn,
            children = {
                UI.Label {
                    text = style.icon,
                    fontSize = 18,
                    width = 24,
                    textAlign = "center",
                    pointerEvents = "none",
                },
                UI.Label {
                    text = msg.text or "",
                    fontSize = F.body_minor,
                    fontColor = style.fg,
                    flexShrink = 1, flexGrow = 1,
                    pointerEvents = "none",
                },
            },
        })
    end

    return UI.Panel {
        id = "turnMessagesSection",
        width = "100%",
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_card,
        padding = S.card_padding,
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
                        text = string.format("本季动态（%d）", #messages),
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Panel {
                        backgroundColor = accent,
                        borderRadius = S.radius_badge,
                        paddingHorizontal = 6, paddingVertical = 2,
                        children = {
                            UI.Label {
                                text = "通知",
                                fontSize = F.label,
                                fontColor = { 30, 25, 15, 255 },
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                children = cards,
            },
        },
    }
end

-- ============================================================================
-- 事件流（Event Stream）
-- ============================================================================
function Dashboard._EventSection(state, era)
    era = era or Config.GetEraByYear(state.year)
    local pendingEvents = state.event_queue or {}
    local count = #pendingEvents

    local eventCards = {}
    for i, evt in ipairs(pendingEvents) do
        if i > 1 then
            table.insert(eventCards, UI.Panel {
                width = "100%", height = 1,
                backgroundColor = C.paper_mid,
            })
        end
        table.insert(eventCards, Dashboard._EventCard(evt, i, era))
    end

    if count == 0 then
        table.insert(eventCards, UI.Panel {
            width = "100%",
            paddingVertical = 24,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "暂无待处理事件",
                    fontSize = F.body,
                    fontColor = C.text_muted,
                },
            },
        })
    end

    return UI.Panel {
        id = "eventSection",
        width = "100%",
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_soft,
        padding = S.card_padding,
        flexDirection = "column",
        gap = S.card_gap,
        children = {
            Dashboard._SectionHeader(string.format("当前事件（%d）", count),
                count > 0 and "待处理" or nil, era.accent),
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                children = eventCards,
            },
        },
    }
end

--- 单个事件卡片
function Dashboard._EventCard(evt, index, era)
    local accent = (era and era.accent) or C.accent_gold
    local isMain = (evt.priority == "main")

    local badge
    if isMain then
        badge = Dashboard._Badge("主线", C.danger_bg, { 255, 220, 210, 255 })
    else
        badge = Dashboard._Badge("支线", C.paper_mid, C.text_secondary)
    end

    local deadlineWidget = nil
    if evt.deadline then
        deadlineWidget = UI.Label {
            text = "剩余时间：" .. evt.deadline .. "天",
            fontSize = F.label,
            fontColor = C.accent_red,
        }
    end

    return UI.Panel {
        width = "100%",
        padding = 8,
        backgroundColor = isMain and C.bg_inset or C.bg_elevated,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = isMain and { accent[1], accent[2], accent[3], 120 } or C.border_soft,
        flexDirection = "row",
        alignItems = "flex-start",
        gap = 9,
        borderLeftWidth = isMain and 3 or 0,
        borderLeftColor = isMain and accent or nil,
        children = {
            UI.Panel {
                width = 58,
                height = 58,
                backgroundColor = C.paper_mid,
                borderRadius = S.radius_btn,
                borderWidth = 1,
                borderColor = C.border_soft,
                justifyContent = "center",
                alignItems = "center",
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = evt.icon or "📜",
                        fontSize = 27,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                },
            },
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                flexDirection = "column",
                gap = 4,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            badge,
                            UI.Label {
                                text = evt.title or "未知事件",
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = isMain and accent or C.text_primary,
                                flexShrink = 1,
                            },
                        },
                    },
                    UI.Label {
                        text = evt.desc or "",
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                        whiteSpace = "normal",
                        lineHeight = 1.3,
                        maxLines = 2,
                    },
                    deadlineWidget or UI.Panel { width = 0, height = 0 },
                },
            },
            UI.Panel {
                width = 66, height = S.btn_small_height,
                backgroundColor = isMain and accent or C.paper_dark,
                borderRadius = S.radius_btn,
                borderWidth = isMain and 0 or 1,
                borderColor = accent,
                justifyContent = "center", alignItems = "center",
                flexShrink = 0,
                pointerEvents = "auto",
                onPointerUp = Config.TapGuard(function(self)
                    if callbacks_.onProcessEvent then
                        callbacks_.onProcessEvent(index)
                    end
                end),
                children = {
                    UI.Label {
                        text = "处理",
                        fontSize = F.body,
                        fontWeight = "bold",
                        fontColor = isMain and { 30, 25, 15, 255 } or accent,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 焦点卡片（Focus Card）— 核心 KPI + 资源储量 + 雇佣快捷按钮
-- ============================================================================
function Dashboard._FocusMetric(label, value, valueColor, barPct)
    local children = {
        UI.Label {
            text = label,
            fontSize = F.label,
            fontColor = C.text_secondary,
        },
        UI.Label {
            text = value,
            fontSize = F.data_mid,
            fontWeight = "bold",
            fontColor = valueColor or C.text_primary,
        },
    }

    if barPct then
        table.insert(children, UI.Panel {
            width = "100%",
            height = 5,
            backgroundColor = C.paper_mid,
            borderRadius = 3,
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = math.min(140, math.max(0, barPct)) .. "%",
                    height = 5,
                    backgroundColor = valueColor or C.accent_green,
                    borderRadius = 3,
                },
            },
        })
    end

    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        minHeight = 54,
        padding = 8,
        backgroundColor = C.bg_inset,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.border_soft,
        flexDirection = "column",
        gap = 3,
        children = children,
    }
end

function Dashboard._FocusPill(icon, label, value, color)
    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        minHeight = 40,
        paddingVertical = 6,
        paddingHorizontal = 7,
        backgroundColor = C.bg_inset,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.border_soft,
        flexDirection = "row",
        alignItems = "center",
        gap = 5,
        children = {
            UI.Label {
                text = icon,
                fontSize = 14,
                pointerEvents = "none",
            },
            UI.Panel {
                flexDirection = "column",
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = label,
                        fontSize = 9,
                        fontColor = C.text_muted,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = value,
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = color or C.text_primary,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

function Dashboard._FocusCard(state, mine, era)
    era = era or Config.GetEraByYear(state.year)
    local accent = era.accent

    -- 产量计算
    local output = Economy._CalcMineOutput(state, mine)
    -- 工人状态
    local morale = state.workers.morale
    local moraleIcon = morale >= 80 and "😊" or (morale >= 60 and "😐" or "😠")
    local moraleText = morale >= 80 and "高涨" or (morale >= 60 and "稳定"
        or (morale >= 40 and "低落" or "极差"))
    -- 维护费用
    local workerExpense = state.workers.hired * state.workers.wage
    -- 利用率
    local totalIdealWorkers = 0
    for _, m in ipairs(state.mines) do
        totalIdealWorkers = totalIdealWorkers + m.level * 10
    end
    local utilization = math.floor(state.workers.hired / math.max(1, totalIdealWorkers) * 100)
    local utilColor = Config.GetUtilColor(utilization)

    -- 雇佣费用
    local BW = Balance.WORKERS
    local hireCost = math.floor(BW.hire_cost * GameState.GetLaborCostFactor(state)
        * (1 - GameState.GetInfluenceRecruitDiscount(state)))
    local canHire = state.cash >= hireCost * 5 and (state.ap.current + (state.ap.temp or 0)) >= 1

    return UI.Panel {
        id = "focusCard",
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            UI.Panel {
                width = "100%",
                height = 1,
                backgroundColor = C.highlight,
            },
            -- 插画横幅 + 标题叠加
            UI.Panel {
                width = "100%",
                height = 160,
                backgroundImage = "image/mine_banner.png",
                children = {
                    -- 底部渐变遮罩（让文字可读）
                    UI.Panel {
                        position = "absolute",
                        left = 0, right = 0, bottom = 0, height = 60,
                        backgroundColor = { 0, 0, 0, 120 },
                    },
                    -- 标题行叠在图片上
                    UI.Panel {
                        position = "absolute",
                        left = 0, right = 0, bottom = 0,
                        paddingHorizontal = S.card_padding,
                        paddingVertical = 8,
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            UI.Label {
                                text = mine.name,
                                fontSize = F.card_title,
                                fontWeight = "bold",
                                fontColor = { 240, 230, 208, 255 },
                                pointerEvents = "none",
                            },
                            UI.Panel {
                                backgroundColor = { 0, 0, 0, 100 },
                                borderRadius = S.radius_badge,
                                borderWidth = 1,
                                borderColor = { accent[1], accent[2], accent[3], 150 },
                                paddingHorizontal = 8, paddingVertical = 3,
                                children = {
                                    UI.Label {
                                        text = "金矿开采",
                                        fontSize = F.label,
                                        fontColor = { 240, 230, 208, 220 },
                                        pointerEvents = "none",
                                    },
                                },
                            },
                            UI.Panel { flexGrow = 1 },
                            UI.Label {
                                text = "Lv." .. mine.level,
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = accent,
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },

            -- 状态指标一排
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingVertical = 8,
                flexDirection = "row",
                gap = 5,
                children = {
                    Dashboard._StatusPill("⛏", "产量", output .. " 单位", accent),
                    Dashboard._StatusPill("📊", "利用率", utilization .. "%", utilColor, "focusUtil"),
                    Dashboard._StatusPill(moraleIcon, "工人", moraleText,
                        morale >= 60 and C.text_primary or C.accent_red),
                    Dashboard._StatusPill("💰", "维护", "-" .. Config.FormatNumber(workerExpense),
                        workerExpense > state.cash * 0.3 and C.accent_red or C.text_secondary, "focusMaint"),
                },
            },

            -- 招募按钮
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = S.card_padding,
                children = {
                    UI.Button {
                        id = "focusHireBtn",
                        text = string.format("招募工人 +5    %d 克朗 / 1 AP", hireCost * 5),
                        fontSize = F.body_minor,
                        height = 32,
                        width = "100%",
                        variant = canHire and "primary" or "outlined",
                        disabled = not canHire,
                        borderRadius = S.radius_btn,
                        onClick = function(self)
                            Actions.HireWorkers(stateRef_, 5, callbacks_.onLightRefresh)
                        end,
                    },
                },
            },
        },
    }
end

--- 状态胶囊（与安全等级大小一致的紧凑样式）
--- @param icon string 图标
--- @param label string 标签
--- @param value string 数值文本
--- @param valueColor table 数值颜色
--- @param valueId string|nil 可选：value Label 的 id，用于 RefreshDynamic 实时更新
function Dashboard._StatusPill(icon, label, value, valueColor, valueId)
    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        paddingVertical = 5,
        paddingHorizontal = 7,
        backgroundColor = C.bg_inset,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.border_soft,
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Label {
                text = icon,
                fontSize = 12,
                pointerEvents = "none",
            },
            UI.Panel {
                flexDirection = "column",
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = label,
                        fontSize = 9,
                        fontColor = C.text_muted,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        id = valueId,
                        text = value,
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = valueColor or C.text_primary,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

--- KPI 单元格（2x2 网格内的每格）
function Dashboard._KPICell(label, value, unit, valueColor, barPct)
    local children = {
        UI.Label {
            text = label,
            fontSize = F.body_minor,
            fontColor = C.text_secondary,
        },
        UI.Panel {
            flexDirection = "row",
            alignItems = "baseline",
            gap = 2,
            children = {
                UI.Label {
                    text = value,
                    fontSize = F.data_mid,
                    fontWeight = "bold",
                    fontColor = valueColor or C.text_primary,
                },
            },
        },
    }

    if barPct then
        local barColor = Config.GetUtilColor(barPct)
        table.insert(children, UI.Panel {
            width = "100%", height = 6,
            backgroundColor = C.paper_mid,
            borderRadius = 3,
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = barPct .. "%",
                    height = 6,
                    backgroundColor = barColor,
                    borderRadius = 3,
                },
            },
        })
    end

    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        flexDirection = "column",
        gap = 3,
        children = children,
    }
end

-- ============================================================================
-- 快速操作区（Quick Actions）
-- 仅展示消耗 AP 的操作项，导航类已由底部 Tab 承担
-- 2x2 网格，突出 AP 消耗与可用状态
-- ============================================================================
function Dashboard._QuickActions(state, era)
    era = era or Config.GetEraByYear(state.year)
    local items = {}
    for index, action in ipairs(Config.QUICK_ACTIONS) do
        local totalAP = state.ap.current + (state.ap.temp or 0)
        local canAfford = totalAP >= action.ap_cost
        table.insert(items, UI.Panel {
            id = "qa_" .. action.id,
            flexGrow = 1, flexBasis = 0,
            minHeight = S.quick_action_height,
            padding = 9,
            backgroundColor = canAfford and C.bg_pressed or C.bg_inset,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = canAfford and C.border_card or C.border_soft,
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            pointerEvents = "auto",
            opacity = canAfford and 1.0 or 0.45,
            onPointerUp = (function(actionId)
                return Config.TapGuard(function(self)
                    if callbacks_.onQuickAction then
                        callbacks_.onQuickAction(actionId)
                    end
                end)
            end)(action.id),
            children = {
                UI.Panel {
                    width = 34,
                    height = 34,
                    borderRadius = S.radius_btn,
                    backgroundColor = canAfford and C.bg_inset or C.bg_surface,
                    borderWidth = 1,
                    borderColor = canAfford and era.accent or C.border_soft,
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = action.icon,
                            fontSize = 18,
                            textAlign = "center",
                            pointerEvents = "none",
                        },
                    },
                },
                UI.Panel {
                    flexGrow = 1,
                    flexDirection = "column",
                    gap = 2,
                    children = {
                        UI.Label {
                            text = action.label,
                            fontSize = F.body_minor,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                            pointerEvents = "none",
                        },
                        UI.Label {
                            id = "qa_status_" .. action.id,
                            text = canAfford and "可执行" or "AP不足",
                            fontSize = F.label,
                            fontColor = canAfford and C.text_secondary or C.accent_red,
                            pointerEvents = "none",
                        },
                    },
                },
                UI.Panel {
                    backgroundColor = action.ap_cost >= 2 and C.warning_bg or C.bg_inset,
                    borderRadius = S.radius_badge,
                    paddingHorizontal = 6,
                    paddingVertical = 3,
                    children = {
                        UI.Label {
                            text = action.ap_cost .. " AP",
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = action.ap_cost >= 2 and { 255, 220, 160, 255 } or C.text_secondary,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        })
        if index == 2 then
            table.insert(items, "__break__")
        end
    end

    local row1, row2 = {}, {}
    local current = row1
    for _, item in ipairs(items) do
        if item == "__break__" then
            current = row2
        else
            table.insert(current, item)
        end
    end

    return UI.Panel {
        id = "quickActions",
        width = "100%",
        flexDirection = "column",
        gap = 7,
        marginBottom = 4,
        children = {
            Dashboard._SectionHeader("快速行动", "消耗 AP", era.accent),
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 7,
                children = row1,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 7,
                children = row2,
            },
        },
    }
end

-- ============================================================================
-- 本季概览（Season Overview）— 储量 + 经济指标
-- ============================================================================
function Dashboard._ReserveRow(icon, label, value, maxValue, color)
    local pct = math.floor(math.min(1, math.max(0, value / math.max(1, maxValue))) * 100)
    local barColor = pct > 50 and C.accent_green or (pct >= 20 and C.accent_amber or C.accent_red)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                text = icon,
                fontSize = 12,
                width = 18,
                textAlign = "center",
                pointerEvents = "none",
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
                width = 34,
                pointerEvents = "none",
            },
            UI.Panel {
                flexGrow = 1,
                height = 5,
                backgroundColor = C.paper_mid,
                borderRadius = 3,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = pct .. "%",
                        height = 5,
                        borderRadius = 3,
                        backgroundColor = barColor,
                    },
                },
            },
            UI.Label {
                text = tostring(value),
                fontSize = F.label,
                fontWeight = "bold",
                fontColor = color or C.text_primary,
                width = 36,
                textAlign = "right",
                pointerEvents = "none",
            },
        },
    }
end

function Dashboard._SeasonOverview(state)
    local estIncome, estExpense = Economy.GetEstimate(state)
    local cashFlow = estIncome - estExpense
    local debtRatio = state.cash > 0
        and math.floor(estExpense / state.cash * 100) or 0
    local publicSentiment = state.workers.morale
    local influence = 0
    for _, r in ipairs(state.regions) do
        influence = influence + (r.influence or 0)
    end

    local cashFlowColor = cashFlow >= 0 and C.accent_green or C.accent_red
    local debtColor = debtRatio > 30 and C.accent_amber or C.text_primary
    local sentimentColor = publicSentiment < 50 and C.accent_red or C.text_primary
    local mineRegion = GameState.GetRegion(state, "mine_district")
    local industrialRegion = GameState.GetRegion(state, "industrial_town")
    local mineResources = mineRegion and mineRegion.resources or {}
    local industrialResources = industrialRegion and industrialRegion.resources or {}

    return UI.Panel {
        id = "seasonOverview",
        width = "100%",
        flexDirection = "column",
        gap = 7,
        children = {
            Dashboard._SectionHeader("本季概览", "经营摘要", C.accent_blue),
            UI.Panel {
                width = "100%",
                backgroundColor = C.bg_surface,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = C.border_soft,
                flexDirection = "row",
                padding = S.inset_padding,
                gap = 10,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexBasis = 0,
                        flexDirection = "column",
                        gap = 6,
                        children = {
                            UI.Label {
                                text = "矿产储量",
                                fontSize = F.label,
                                fontWeight = "bold",
                                fontColor = C.text_secondary,
                            },
                            Dashboard._ReserveRow("●", "金矿", mineResources.gold_reserve or 0, 500, C.accent_gold),
                            Dashboard._ReserveRow("○", "银矿", mineResources.silver_reserve or 0, 1200, C.text_secondary),
                            Dashboard._ReserveRow("◆", "煤矿", industrialResources.coal_reserve or 0, 2500, C.text_primary),
                        },
                    },
                    Dashboard._OverviewDivider(),
                    UI.Panel {
                        flexGrow = 1,
                        flexBasis = 0,
                        flexDirection = "column",
                        gap = 5,
                        children = {
                            Dashboard._OverviewRow("💰", "现金流",
                                (cashFlow >= 0 and "+" or "") .. Config.FormatNumber(cashFlow), cashFlowColor),
                            Dashboard._OverviewRow("📊", "负债率", debtRatio .. "%", debtColor),
                            Dashboard._OverviewRow("❤️", "民心", tostring(publicSentiment), sentimentColor),
                            Dashboard._OverviewRow("🌐", "影响力", tostring(influence), C.text_primary),
                        },
                    },
                },
            },
        },
    }
end

--- 概览列
function Dashboard._OverviewCol(icon, label, value, valueColor)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        minHeight = 44,
        backgroundColor = C.bg_inset,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.border_soft,
        paddingVertical = 5,
        justifyContent = "center", alignItems = "center",
        gap = 1,
        children = {
            UI.Label {
                text = icon,
                fontSize = 13,
                textAlign = "center",
            },
            UI.Label {
                text = value,
                fontSize = F.data_small,
                fontWeight = "bold",
                fontColor = valueColor or C.text_primary,
                textAlign = "center",
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
                textAlign = "center",
            },
        },
    }
end

--- 概览行（紧凑横排：图标 + 标签 + 数值靠右）
function Dashboard._OverviewRow(icon, label, value, valueColor)
    return UI.Panel {
        width = "100%",
        paddingVertical = 4,
        paddingHorizontal = 7,
        backgroundColor = C.bg_inset,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.border_soft,
        flexDirection = "row",
        alignItems = "center",
        gap = 5,
        children = {
            UI.Label {
                text = icon,
                fontSize = 11,
                width = 16,
                textAlign = "center",
                pointerEvents = "none",
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
                pointerEvents = "none",
            },
            UI.Panel { flexGrow = 1 },
            UI.Label {
                text = value,
                fontSize = F.body_minor,
                fontWeight = "bold",
                fontColor = valueColor or C.text_primary,
                pointerEvents = "none",
            },
        },
    }
end

--- 概览竖分隔线
function Dashboard._OverviewDivider()
    return UI.Panel {
        width = 1,
        height = "100%",
        backgroundColor = C.divider,
    }
end

-- ============================================================================
-- 结束回合按钮
-- ============================================================================
function Dashboard._EndTurnButton(state, era)
    era = era or Config.GetEraByYear(state.year)
    local accent = era.accent

    local warningWidgets = {}
    if state.loans and #state.loans > 0 then
        local currentLeverage = GameState.CalcLeverage(state)
        local leverageMul = Balance.LOAN.leverage_interest_multiplier or 1.5
        local totalInterest = 0
        for _, loan in ipairs(state.loans) do
            local effectiveRate = loan.interest * (1 + currentLeverage * leverageMul)
            totalInterest = totalInterest + math.ceil(loan.principal * effectiveRate)
        end
        if totalInterest > state.cash then
            local shortfall = totalInterest - state.cash
            table.insert(warningWidgets, UI.Panel {
                width = "100%",
                backgroundColor = { 120, 35, 35, 230 },
                borderRadius = S.radius_btn,
                paddingVertical = 8, paddingHorizontal = 12,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = "⚠",
                        fontSize = 18,
                        width = 24,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = string.format(
                            "现金不足以支付利息！需 %s，缺口 %s，结算时将强制清算资产",
                            Config.FormatNumber(totalInterest),
                            Config.FormatNumber(shortfall)),
                        fontSize = F.body_minor,
                        fontColor = { 255, 200, 200, 255 },
                        flexShrink = 1, flexGrow = 1,
                        whiteSpace = "normal",
                        lineHeight = 1.3,
                        pointerEvents = "none",
                    },
                },
            })
        end
    end

    local totalAssets = GameState.CalcTotalAssets(state)
    local totalDebt = GameState.CalcTotalDebt(state)
    local netWorth = totalAssets - totalDebt
    if netWorth < 0 then
        local negTurns = state.negative_net_worth_turns or 0
        local bkNegTurns = (Balance.LOAN.bankruptcy or {}).negative_net_worth_turns or 4
        local remaining = bkNegTurns - negTurns
        if remaining > 0 and remaining <= 3 then
            table.insert(warningWidgets, UI.Panel {
                width = "100%",
                backgroundColor = { 110, 85, 30, 230 },
                borderRadius = S.radius_btn,
                paddingVertical = 6, paddingHorizontal = 12,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = "💀",
                        fontSize = 16,
                        width = 24,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = string.format("净资产为负（%s），再持续 %d 季将破产",
                            Config.FormatNumber(netWorth), remaining),
                        fontSize = F.body_minor,
                        fontColor = { 255, 230, 160, 255 },
                        flexShrink = 1, flexGrow = 1,
                        whiteSpace = "normal",
                        pointerEvents = "none",
                    },
                },
            })
        end
    end

    local areaChildren = {}
    for _, w in ipairs(warningWidgets) do
        table.insert(areaChildren, w)
    end
    table.insert(areaChildren, UI.Panel {
        id = "endTurnBtn",
        width = "100%",
        height = 38,
        backgroundColor = accent,
        borderRadius = S.radius_card,
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onPointerUp = Config.TapGuard(function(self)
            if callbacks_.onEndTurn then
                callbacks_.onEndTurn()
            end
        end),
        children = {
            UI.Label {
                text = "结束回合",
                fontSize = F.card_title,
                fontWeight = "bold",
                fontColor = { 30, 25, 15, 255 },
                pointerEvents = "none",
            },
        },
    })

    return UI.Panel {
        id = "endTurnArea",
        width = "100%",
        paddingTop = 2,
        flexDirection = "column",
        gap = 4,
        children = areaChildren,
    }
end

return Dashboard
