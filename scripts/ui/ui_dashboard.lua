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
---@param callbacks table { onEndTurn, onProcessEvent, onQuickAction, onStateChanged }
---@return table widget
function Dashboard.Create(state, callbacks)
    stateRef_ = state
    callbacks_ = callbacks or {}
    return Dashboard._BuildContent(state)
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
        padding = S.card_padding,
        flexDirection = "column",
        gap = S.card_gap,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = string.format("当前事件（%d）", count),
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    count > 0 and UI.Panel {
                        backgroundColor = era.accent,
                        borderRadius = S.radius_badge,
                        paddingHorizontal = 6, paddingVertical = 2,
                        children = {
                            UI.Label {
                                text = "待处理",
                                fontSize = F.label,
                                fontColor = { 30, 25, 15, 255 },
                                pointerEvents = "none",
                            },
                        },
                    } or UI.Panel { width = 0, height = 0 },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "column",
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
        badge = UI.Panel {
            backgroundColor = C.accent_red,
            borderRadius = S.radius_badge,
            paddingHorizontal = 6, paddingVertical = 2,
            children = {
                UI.Label {
                    text = "❗主线",
                    fontSize = F.body_minor,
                    fontColor = { 255, 255, 255, 255 },
                    pointerEvents = "none",
                },
            },
        }
    else
        badge = UI.Panel {
            backgroundColor = C.paper_mid,
            borderRadius = S.radius_badge,
            paddingHorizontal = 6, paddingVertical = 2,
            children = {
                UI.Label {
                    text = "支线",
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                    pointerEvents = "none",
                },
            },
        }
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
        paddingVertical = 8,
        flexDirection = "row",
        alignItems = "flex-start",
        gap = S.card_gap,
        borderLeftWidth = isMain and 3 or 0,
        borderLeftColor = isMain and accent or nil,
        paddingLeft = isMain and 8 or 0,
        children = {
            UI.Panel {
                width = S.event_img_size,
                height = S.event_img_size,
                backgroundColor = C.paper_mid,
                borderRadius = S.radius_btn,
                justifyContent = "center",
                alignItems = "center",
                flexShrink = 0,
                children = {
                    UI.Label {
                        text = evt.icon or "📜",
                        fontSize = 28,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                },
            },
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                flexDirection = "column",
                gap = 3,
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
                                fontColor = isMain and C.accent_red or C.text_primary,
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
                width = 80, height = S.btn_small_height,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_btn,
                borderWidth = 1, borderColor = accent,
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
                        fontColor = accent,
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

    -- 资源储量
    local region = GameState.GetRegion(state, mine.region_id)
    local goldReserve = region and region.resources.gold_reserve or 0
    local silverReserve = region and region.resources.silver_reserve or 0
    local goldColor = goldReserve < 50 and C.accent_red or C.accent_gold
    local silverColor = silverReserve < 100 and C.accent_red or C.text_secondary

    -- 雇佣费用
    local BW = Balance.WORKERS
    local hireCost = math.floor(BW.hire_cost * GameState.GetLaborCostFactor(state)
        * (1 - GameState.GetInfluenceRecruitDiscount(state)))
    local canHire = state.cash >= hireCost * 5 and state.ap.current >= 1

    return UI.Panel {
        id = "focusCard",
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 头部：资产名 + 类型标签
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                paddingBottom = 6,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = mine.name,
                        fontSize = F.card_title,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Panel {
                        backgroundColor = C.bg_elevated,
                        borderRadius = S.radius_badge,
                        paddingHorizontal = 8, paddingVertical = 3,
                        children = {
                            UI.Label {
                                text = "金矿开采",
                                fontSize = F.label,
                                fontColor = C.paper_light,
                            },
                        },
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Label {
                        text = "Lv." .. mine.level,
                        fontSize = F.body,
                        fontWeight = "bold",
                        fontColor = accent,
                    },
                },
            },

            -- 核心 KPI：图片 + 2x2 指标
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = 6,
                flexDirection = "row",
                gap = 8,
                children = {
                    -- 左：资产图片
                    UI.Panel {
                        width = 80, height = 80,
                        backgroundColor = C.paper_mid,
                        borderRadius = S.radius_btn,
                        justifyContent = "center", alignItems = "center",
                        flexShrink = 0,
                        children = {
                            UI.Label {
                                text = "⛏️",
                                fontSize = 30,
                                textAlign = "center",
                            },
                        },
                    },
                    -- 右：2x2 指标网格
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        flexDirection = "column",
                        gap = 6,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                gap = 6,
                                children = {
                                    Dashboard._KPICell("产量(本季)",
                                        output .. " 单位", nil, accent),
                                    Dashboard._KPICell("产能利用率",
                                        utilization .. "%", nil, utilColor, utilization),
                                },
                            },
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                gap = 6,
                                children = {
                                    Dashboard._KPICell("工人状态",
                                        moraleIcon .. moraleText, nil,
                                        morale >= 60 and C.text_primary or C.accent_red),
                                    Dashboard._KPICell("维护费用",
                                        "-" .. Config.FormatNumber(workerExpense), nil,
                                        workerExpense > state.cash * 0.3 and C.accent_red or C.text_secondary),
                                },
                            },
                        },
                    },
                },
            },

            -- 资源储量 + 雇佣按钮 行
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = S.card_padding,
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    -- 黄金储量
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        children = {
                            UI.Label {
                                text = "🟡",
                                fontSize = 10,
                            },
                            UI.Label {
                                text = tostring(goldReserve),
                                fontSize = F.body_minor,
                                fontWeight = "bold",
                                fontColor = goldColor,
                            },
                        },
                    },
                    -- 白银储量
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        children = {
                            UI.Label {
                                text = "⚪",
                                fontSize = 10,
                            },
                            UI.Label {
                                text = tostring(silverReserve),
                                fontSize = F.body_minor,
                                fontWeight = "bold",
                                fontColor = silverColor,
                            },
                        },
                    },
                    -- 弹性撑开
                    UI.Panel { flexGrow = 1 },
                    -- 雇佣按钮
                    UI.Button {
                        id = "focusHireBtn",
                        text = string.format("招募+5 (💰%d ⚡1)", hireCost * 5),
                        fontSize = F.label,
                        height = 28,
                        paddingHorizontal = 10,
                        variant = canHire and "primary" or "outlined",
                        disabled = not canHire,
                        borderRadius = S.radius_btn,
                        onClick = function(self)
                            Actions.HireWorkers(stateRef_, 5, callbacks_.onStateChanged)
                        end,
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
-- 单行 4 格，紧凑排列
-- ============================================================================
function Dashboard._QuickActions(state, era)
    era = era or Config.GetEraByYear(state.year)
    local items = {}
    for _, action in ipairs(Config.QUICK_ACTIONS) do
        local totalAP = state.ap.current + (state.ap.temp or 0)
        local canAfford = totalAP >= action.ap_cost
        table.insert(items, UI.Panel {
            flexGrow = 1, flexBasis = 0,
            minHeight = 48,
            paddingVertical = 4,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_card,
            borderWidth = 1, borderColor = C.paper_mid,
            justifyContent = "center", alignItems = "center",
            gap = 1,
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
                UI.Label {
                    text = action.icon,
                    fontSize = 18,
                    textAlign = "center",
                    pointerEvents = "none",
                },
                UI.Label {
                    text = action.label,
                    fontSize = F.label,
                    fontColor = C.text_primary,
                    textAlign = "center",
                    pointerEvents = "none",
                },
                UI.Label {
                    text = action.ap_cost .. " AP",
                    fontSize = 9,
                    fontColor = C.text_secondary,
                    textAlign = "center",
                    pointerEvents = "none",
                },
            },
        })
    end

    return UI.Panel {
        id = "quickActions",
        width = "100%",
        flexDirection = "column",
        gap = 4,
        marginBottom = 4,
        children = {
            UI.Label {
                text = "快速行动（消耗AP）",
                fontSize = F.subtitle,
                fontWeight = "medium",
                fontColor = C.text_secondary,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 6,
                children = items,
            },
        },
    }
end

-- ============================================================================
-- 本季概览（Season Overview）— 紧凑版
-- 去掉矿产储量进度条（产业页有更详细版本），改为单行 4 格经济指标
-- ============================================================================
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

    return UI.Panel {
        id = "seasonOverview",
        width = "100%",
        flexDirection = "column",
        gap = 4,
        children = {
            UI.Label {
                text = "本季概览",
                fontSize = F.subtitle,
                fontWeight = "medium",
                fontColor = C.text_secondary,
            },
            UI.Panel {
                width = "100%",
                backgroundColor = C.bg_surface,
                borderRadius = S.radius_card,
                flexDirection = "row",
                alignItems = "center",
                paddingVertical = 8,
                paddingHorizontal = 6,
                children = {
                    Dashboard._OverviewCol("💰", "现金流",
                        (cashFlow >= 0 and "+" or "") .. Config.FormatNumber(cashFlow), cashFlowColor),
                    Dashboard._OverviewDivider(),
                    Dashboard._OverviewCol("📊", "负债率", debtRatio .. "%", debtColor),
                    Dashboard._OverviewDivider(),
                    Dashboard._OverviewCol("❤️", "民心", tostring(publicSentiment), sentimentColor),
                    Dashboard._OverviewDivider(),
                    Dashboard._OverviewCol("🌐", "影响力", tostring(influence), C.text_primary),
                },
            },
        },
    }
end

--- 概览列
function Dashboard._OverviewCol(icon, label, value, valueColor)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        paddingVertical = 4,
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

--- 概览竖分隔线
function Dashboard._OverviewDivider()
    return UI.Panel {
        width = 1, height = "60%",
        backgroundColor = C.paper_mid,
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
