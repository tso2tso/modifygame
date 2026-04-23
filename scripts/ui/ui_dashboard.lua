-- ============================================================================
-- 仪表盘页（主视图）— sarajevo_dynasty_ui_spec §4.3-§4.6
-- 事件流 + 焦点卡片 + 快速操作 + 本季概览 + 结束回合
-- 设计语言：工业帝国主义时代的家族账簿
-- 严格遵循设计图参考
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Economy = require("systems.economy")
local Events = require("systems.events")
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

    -- §4.3 事件流
    table.insert(children, Dashboard._EventSection(state, era))
    -- §4.4 焦点卡片
    if #state.mines > 0 then
        table.insert(children, Dashboard._FocusCard(state, state.mines[1], era))
    end
    -- §4.5 快速操作
    table.insert(children, Dashboard._QuickActions(state, era))
    -- §4.6 本季概览
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
-- §4.3 事件流（Event Stream）
-- 容器：bg_surface 背景，内边距 16px
-- 标题行：左"当前事件（N）" + 右"查看全部 ›"
-- ============================================================================
function Dashboard._EventSection(state, era)
    era = era or Config.GetEraByYear(state.year)
    local pendingEvents = state.event_queue or {}
    local count = #pendingEvents

    local eventCards = {}
    for i, evt in ipairs(pendingEvents) do
        -- §4.3 卡片间距 12px，0.5px paper_mid 分隔线
        if i > 1 then
            table.insert(eventCards, UI.Panel {
                width = "100%", height = 1,
                backgroundColor = C.paper_mid,
            })
        end
        table.insert(eventCards, Dashboard._EventCard(evt, i, era))
    end

    -- 空状态
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
            -- 标题行：左"当前事件（N）" + 右"查看全部 ›"
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
                    -- 事件数量指示（纯展示）
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
            -- 卡片列表
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                children = eventCards,
            },
        },
    }
end

--- §4.3 单个事件卡片
--- 紧急事件：左侧 3px solid era_accent 竖向边框线（主线事件与时代同色）
--- 优先级徽章：!主线 红色实底白字 / 支线 paper_mid 底
--- 处理按钮：72x32，paper_dark 背景，era_accent 边框
function Dashboard._EventCard(evt, index, era)
    local accent = (era and era.accent) or C.accent_gold
    local isMain = (evt.priority == "main")

    -- 优先级徽章
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

    -- §4.3 剩余时间格式："剩余时间：X天"，红色倒计时感
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
        -- §4.3 紧急事件：左侧 3px 时代 accent 竖向边框线
        -- （HTML 参考中主线事件使用 --era-accent 而非固定红）
        borderLeftWidth = isMain and 3 or 0,
        borderLeftColor = isMain and accent or nil,
        paddingLeft = isMain and 8 or 0,
        children = {
            -- 左侧：图片区 64x64（sepia 图片占位）
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
            -- 中间：信息区
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                flexDirection = "column",
                gap = 3,
                children = {
                    -- 徽章 + 标题
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
                    -- 描述（2行 ellipsis） — 使用渲染层 maxLines 裁剪，
                    -- 避免 string.sub 按字节切割中文 UTF-8 造成乱码
                    UI.Label {
                        text = evt.desc or "",
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                        whiteSpace = "normal",
                        lineHeight = 1.3,
                        maxLines = 2,
                    },
                    -- 剩余时间
                    deadlineWidget or UI.Panel { width = 0, height = 0 },
                },
            },
            -- 右侧：处理按钮（§4.3 72x32）— 边框与文字使用 era_accent
            UI.Panel {
                width = 72, height = S.btn_small_height,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_btn,
                borderWidth = 1, borderColor = accent,
                justifyContent = "center", alignItems = "center",
                flexShrink = 0,
                pointerEvents = "auto",
                onPointerUp = function(self)
                    if callbacks_.onProcessEvent then
                        callbacks_.onProcessEvent(index)
                    end
                end,
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
-- §4.4 经营焦点卡片（Focus Card）
-- 容器：全宽，圆角6px，边框1px paper_light(40%)，paper_dark 背景
-- 头部：资产名 + 类型标签胶囊 + 更多
-- 图片+核心KPI区：横向双栏，左图片右2x2指标
-- 次要指标行：4格横排 + 小图标前缀
-- 操作按钮组：4个等宽，高度40px
-- ============================================================================
function Dashboard._FocusCard(state, mine, era)
    era = era or Config.GetEraByYear(state.year)
    local accent = era.accent
    local region = GameState.GetRegion(state, mine.region_id)
    local goldReserve = region and region.resources.gold_reserve or 0
    local security = region and region.security or 0
    local secText = RegionsData.GetSecurityText(security)
    local secColor = security <= 2 and C.accent_red
        or (security >= 4 and C.accent_green or C.accent_amber)

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
    local idealWorkers = mine.level * 10
    local utilization = math.min(100,
        math.floor(state.workers.hired / math.max(1, idealWorkers) * 100))
    local utilColor = Config.GetUtilColor(utilization)

    return UI.Panel {
        id = "focusCard",
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 头部：资产名 + 类型标签胶囊 + 更多
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
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
                    -- §4.4 类型标签胶囊（bg_elevated 底，paper_light 字，11px）
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
                        text = "…",
                        fontSize = F.card_title,
                        fontColor = C.text_muted,
                    },
                },
            },

            -- 图片 + 核心 KPI 区（§4.4 横向双栏）
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                flexDirection = "row",
                gap = S.card_gap,
                children = {
                    -- 左：资产图片占位（sepia 感 120px 高，圆角4px）
                    UI.Panel {
                        width = 120, height = S.focus_img_height,
                        backgroundColor = C.paper_mid,
                        borderRadius = S.radius_btn,
                        justifyContent = "center", alignItems = "center",
                        flexShrink = 0,
                        children = {
                            UI.Label {
                                text = "⛏️",
                                fontSize = 40,
                                textAlign = "center",
                            },
                        },
                    },
                    -- 右：2x2 指标网格（§4.4 数值大字22px+单位13px+标签12px）
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        flexDirection = "column",
                        gap = 8,
                        children = {
                            -- Row 1：产量(本季) | 产能利用率
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                gap = 8,
                                children = {
                                    Dashboard._KPICell("产量(本季)",
                                        output .. " 单位", nil, accent),
                                    Dashboard._KPICell("产能利用率",
                                        utilization .. "%", nil, utilColor, utilization),
                                },
                            },
                            -- Row 2：工人状态 | 维护费用
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                gap = 8,
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

            -- 次要指标行（§4.4 4格横排小卡片，每格：图标+标题11px+数值15px bold）
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                justifyContent = "space-between",
                gap = 4,
                children = {
                    Dashboard._MiniStat("📦", "库存",
                        goldReserve .. " 吨"),
                    Dashboard._MiniStat("💎", "品质",
                        mine.level >= 3 and "高" or (mine.level >= 2 and "中" or "低")),
                    Dashboard._MiniStat("💰", "开采成本",
                        Balance.MINE.gold_price .. "/单位"),
                    Dashboard._MiniStatBadge("安全等级", secText, secColor),
                },
            },

            -- 分隔线 0.5px
            UI.Panel {
                width = "100%",
                height = 1,
                backgroundColor = C.paper_mid,
            },

            -- §4.4 操作按钮组（4个等宽，高度40px，4px圆角）
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                gap = 8,
                children = {
                    Dashboard._FocusActionBtn("调整生产", 1, function()
                        if callbacks_.onQuickAction then
                            callbacks_.onQuickAction("industry")
                        end
                    end),
                    Dashboard._FocusActionBtn("雇佣工人", 1, function()
                        Dashboard._OnHireWorkers(state)
                    end),
                    Dashboard._FocusActionBtn("武装护卫", 1, function()
                        if callbacks_.onQuickAction then
                            callbacks_.onQuickAction("military")
                        end
                    end),
                    Dashboard._FocusActionBtn("升级设施", 2, function()
                        Dashboard._OnUpgradeMine(state, mine)
                    end),
                },
            },
        },
    }
end

--- §4.4 焦点卡片 KPI 单元格（2x2 网格内的每格）
--- 标签12px text_secondary + 数值22px bold + 可选进度条
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

    -- §4.4 进度条规范（产能利用率等）
    -- 高度6px，圆角3px，≥80%绿/50-79%橙/<50%红
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

--- §4.4 次要指标 — 带图标前缀（设计图：📦库存/💎品质/💰开采成本）
function Dashboard._MiniStat(icon, label, value)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = icon,
                fontSize = 14,
                textAlign = "center",
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
                textAlign = "center",
            },
            UI.Label {
                text = value,
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
                textAlign = "center",
            },
        },
    }
end

--- §4.4 次要指标 — 安全等级带颜色徽章
function Dashboard._MiniStatBadge(label, value, badgeColor)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = "🛡️",
                fontSize = 14,
                textAlign = "center",
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
                textAlign = "center",
            },
            UI.Panel {
                backgroundColor = badgeColor,
                borderRadius = S.radius_btn,
                paddingHorizontal = 8, paddingVertical = 2,
                children = {
                    UI.Label {
                        text = "🛡 " .. value,
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = { 255, 255, 255, 255 },
                    },
                },
            },
        },
    }
end

--- §4.4 焦点卡片操作按钮（高度40px, 4px圆角, bg_elevated, paper_light边框）
--- 主文字13px + 下方(X AP)11px text_secondary
--- 2AP 按钮右上角 amber 色徽章
function Dashboard._FocusActionBtn(label, apCost, onClick)
    local isExpensive = (apCost >= 2)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        height = S.btn_height,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_btn,
        borderWidth = 1, borderColor = C.paper_light,
        justifyContent = "center", alignItems = "center",
        gap = 2,
        pointerEvents = "auto",
        onPointerUp = function(self)
            if onClick then onClick() end
        end,
        children = {
            UI.Label {
                text = label,
                fontSize = F.body,
                fontColor = C.text_primary,
                textAlign = "center",
                pointerEvents = "none",
            },
            UI.Label {
                text = "(" .. apCost .. " AP)",
                fontSize = F.label,
                fontColor = C.text_secondary,
                textAlign = "center",
                pointerEvents = "none",
            },
            -- §4.4 2AP 按钮：右上角小徽章标注"2"，amber 色
            isExpensive and UI.Panel {
                position = "absolute",
                top = -4, right = -4,
                backgroundColor = C.accent_amber,
                borderRadius = S.radius_badge,
                paddingHorizontal = 4, paddingVertical = 1,
                children = {
                    UI.Label {
                        text = "2",
                        fontSize = 9,
                        fontWeight = "bold",
                        fontColor = { 255, 255, 255, 255 },
                        pointerEvents = "none",
                    },
                },
            } or nil,
        },
    }
end

-- ============================================================================
-- §4.5 快速操作区（Quick Actions）
-- 标题：15px 500，text_secondary，"快速行动（消耗AP）"
-- 按钮网格：3列×2行，每个约80x80
-- 图标28px线性 + 功能名12px + AP消耗11px text_secondary
-- 2AP：右上角红色小圆角标签
-- ============================================================================
function Dashboard._QuickActions(state, era)
    era = era or Config.GetEraByYear(state.year)
    local rows = {}
    for rowStart = 1, #Config.QUICK_ACTIONS, 3 do
        local rowItems = {}
        for col = 0, 2 do
            local idx = rowStart + col
            local action = Config.QUICK_ACTIONS[idx]
            if action then
                local totalAP = state.ap.current + (state.ap.temp or 0)
                local canAfford = totalAP >= action.ap_cost
                local isExpensive = action.ap_cost >= 2
                table.insert(rowItems, UI.Panel {
                    flexGrow = 1, flexBasis = 0,
                    height = S.quick_action_size,
                    backgroundColor = C.bg_elevated,
                    borderRadius = S.radius_card,
                    borderWidth = 1, borderColor = C.paper_mid,
                    justifyContent = "center", alignItems = "center",
                    gap = 4,
                    pointerEvents = "auto",
                    opacity = canAfford and 1.0 or 0.45,
                    onPointerUp = (function(actionId)
                        return function(self)
                            if callbacks_.onQuickAction then
                                callbacks_.onQuickAction(actionId)
                            end
                        end
                    end)(action.id),
                    children = {
                        UI.Label {
                            text = action.icon,
                            fontSize = 28,
                            textAlign = "center",
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = action.label,
                            fontSize = F.body_minor,
                            fontColor = C.text_primary,
                            textAlign = "center",
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = action.ap_cost .. " AP",
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                            textAlign = "center",
                            pointerEvents = "none",
                        },
                        -- §4.5 2AP 操作：按钮右上角显示"2AP"红色小圆角标签
                        isExpensive and UI.Panel {
                            position = "absolute",
                            top = 4, right = 4,
                            backgroundColor = C.accent_amber,
                            borderRadius = S.radius_badge,
                            paddingHorizontal = 4, paddingVertical = 1,
                            children = {
                                UI.Label {
                                    text = "2AP",
                                    fontSize = 9,
                                    fontWeight = "bold",
                                    fontColor = { 255, 255, 255, 255 },
                                    pointerEvents = "none",
                                },
                            },
                        } or nil,
                    },
                })
            end
        end
        table.insert(rows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = S.card_gap,
            children = rowItems,
        })
    end

    -- 避免 table.unpack 陷阱（Rule #4.5），手动构建 children
    local sectionChildren = {
        UI.Label {
            text = "快速行动（消耗AP）",
            fontSize = F.subtitle,
            fontWeight = "medium",
            fontColor = C.text_secondary,
            marginBottom = 4,
        },
    }
    for _, row in ipairs(rows) do
        table.insert(sectionChildren, row)
    end

    return UI.Panel {
        id = "quickActions",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = sectionChildren,
    }
end

-- ============================================================================
-- §4.6 本季概览（Season Overview Bar）
-- 6列等宽横排，高度64px，背景bg_surface，0.5px竖线paper_mid分隔
-- 每格：标签11px text_secondary居中 + 数值16px 700居中
-- 数值颜色规则：现金流正绿负红，负债率>30%橙，民心<50红
-- 设计图参考：增加小图标前缀
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
    -- 监管压力
    local regulation = state.regulation_pressure or 0

    -- §4.6 数值颜色规则
    local cashFlowColor = cashFlow >= 0 and C.accent_green or C.accent_red
    local debtColor = debtRatio > 30 and C.accent_amber or C.text_primary
    local sentimentColor = publicSentiment < 50 and C.accent_red or C.text_primary

    -- §4.6 民心下降标注"(-5)"效果
    local sentimentSuffix = ""
    if publicSentiment < 50 then
        sentimentSuffix = " (-5)"
    end

    local columns = {
        Dashboard._OverviewCol("💰", "现金流",
            (cashFlow >= 0 and "+" or "") .. Config.FormatNumber(cashFlow), cashFlowColor),
        Dashboard._OverviewDivider(),
        Dashboard._OverviewCol("📊", "负债率", debtRatio .. "%", debtColor),
        Dashboard._OverviewDivider(),
        Dashboard._OverviewCol("❤️", "民心",
            tostring(publicSentiment) .. sentimentSuffix, sentimentColor),
        Dashboard._OverviewDivider(),
        Dashboard._OverviewCol("🌐", "地区影响力", tostring(influence), C.text_primary),
        Dashboard._OverviewDivider(),
        Dashboard._OverviewCol("⚖️", "监管压力", tostring(regulation), C.text_primary),
    }

    return UI.Panel {
        id = "seasonOverview",
        width = "100%",
        flexDirection = "column",
        gap = 6,
        children = {
            -- §4.6 标题行
            UI.Label {
                text = "本季概览",
                fontSize = F.subtitle,
                fontWeight = "medium",
                fontColor = C.text_secondary,
            },
            -- 概览数据栏
            UI.Panel {
                width = "100%",
                height = S.season_bar_height,
                backgroundColor = C.bg_surface,
                borderRadius = S.radius_card,
                flexDirection = "row",
                alignItems = "center",
                children = columns,
            },
        },
    }
end

--- §4.6 概览列（带图标）
function Dashboard._OverviewCol(icon, label, value, valueColor)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        height = "100%",
        justifyContent = "center", alignItems = "center",
        gap = 1,
        children = {
            UI.Label {
                text = icon,
                fontSize = 12,
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

--- 概览竖分隔线（0.5px paper_mid）
function Dashboard._OverviewDivider()
    return UI.Panel {
        width = 1, height = "60%",
        backgroundColor = C.paper_mid,
    }
end

-- ============================================================================
-- 结束回合按钮 — 最醒目的时代色填充按钮
-- ============================================================================
function Dashboard._EndTurnButton(state, era)
    era = era or Config.GetEraByYear(state.year)
    local accent = era.accent
    return UI.Panel {
        id = "endTurnArea",
        width = "100%",
        paddingTop = 4,
        children = {
            UI.Panel {
                id = "endTurnBtn",
                width = "100%",
                height = 44,
                backgroundColor = accent,
                borderRadius = S.radius_card,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "auto",
                onPointerUp = function(self)
                    if callbacks_.onEndTurn then
                        callbacks_.onEndTurn()
                    end
                end,
                children = {
                    UI.Label {
                        text = "结束回合",
                        fontSize = F.card_title,
                        fontWeight = "bold",
                        fontColor = { 30, 25, 15, 255 },
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 焦点卡片快捷操作
-- ============================================================================

--- 快捷雇佣工人
function Dashboard._OnHireWorkers(state)
    if not stateRef_ then return end
    local hireCost = Balance.WORKERS.hire_cost * 5
    if stateRef_.cash < hireCost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return
    end
    if not GameState.SpendAP(stateRef_, 1) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return
    end
    stateRef_.cash = stateRef_.cash - hireCost
    stateRef_.workers.hired = stateRef_.workers.hired + 5
    GameState.AddLog(stateRef_, string.format("招募了 5 名工人，花费 %d", hireCost))
    UI.Toast.Show("招募 +5 工人", { variant = "success", duration = 1.5 })
    if callbacks_.onStateChanged then callbacks_.onStateChanged() end
end

--- 快捷升级矿山
function Dashboard._OnUpgradeMine(state, mine)
    if not stateRef_ then return end
    if mine.level >= Balance.MINE.max_level then
        UI.Toast.Show("矿山已达最高等级", { variant = "warning", duration = 1.5 })
        return
    end
    local cost = Balance.MINE.upgrade_cost * mine.level
    if stateRef_.cash < cost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return
    end
    if not GameState.SpendAP(stateRef_, 2) then
        UI.Toast.Show("行动点不足（需要2 AP）", { variant = "error", duration = 1.5 })
        return
    end
    stateRef_.cash = stateRef_.cash - cost
    mine.level = mine.level + 1
    GameState.AddLog(stateRef_, string.format("%s 升级到 %d 级", mine.name, mine.level))
    UI.Toast.Show(string.format("%s → Lv.%d", mine.name, mine.level),
        { variant = "success", duration = 1.5 })
    if callbacks_.onStateChanged then callbacks_.onStateChanged() end
end

return Dashboard
