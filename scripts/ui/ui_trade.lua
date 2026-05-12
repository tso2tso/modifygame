-- ============================================================================
-- 贸易面板 UI（Phase 5）
-- 世界页子标签：订单池 / 进行中订单 / 路线管理 / 统计
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local Trade = require("systems.trade")
local TradeRoutesData = require("data.trade_routes_data")
local EuropeData = require("data.europe_data")
local EquipmentData = require("data.equipment_data")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE
local BFT = Balance.FOREIGN_TRADE
local CATALOG = EquipmentData.CATALOG

local TradePanel = {}

-- ── 模块状态 ──
---@type table
local stateRef_ = nil
---@type function|nil
local onStateChanged_ = nil
---@type table|nil
local panelRoot_ = nil

-- ============================================================================
-- 入口
-- ============================================================================

--- 构建贸易面板内容（被 ui_world.lua 的 _SwitchSubTab 调用）
---@param state table
---@param callbacks table
---@return table widget
function TradePanel.Build(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged or nil
    return TradePanel._BuildContent(state)
end

-- ============================================================================
-- 主布局
-- ============================================================================

function TradePanel._BuildContent(state)
    local summary = Trade.GetSummary(state)
    local children = {}

    -- 1. 统计概览卡片
    table.insert(children, TradePanel._BuildSummaryCard(state, summary))

    -- 2. 可接取订单（订单池）
    local available = Trade.GetAvailableOrders(state)
    if #available > 0 then
        table.insert(children, TradePanel._SectionDivider("可接取订单", C.accent_gold))
        for _, order in ipairs(available) do
            table.insert(children, TradePanel._BuildAvailableOrderCard(state, order))
        end
    else
        table.insert(children, TradePanel._SectionDivider("可接取订单", C.text_muted))
        table.insert(children, TradePanel._EmptyHint("本季暂无贸易订单，下季刷新"))
    end

    -- 3. 进行中订单
    local active = Trade.GetActiveOrders(state)
    if #active > 0 then
        table.insert(children, TradePanel._SectionDivider("进行中订单", C.accent_blue))
        for _, order in ipairs(active) do
            table.insert(children, TradePanel._BuildActiveOrderCard(state, order))
        end
    end

    -- 4. 路线一览
    table.insert(children, TradePanel._SectionDivider("贸易路线", C.text_secondary))
    table.insert(children, TradePanel._BuildRoutesCard(state))

    panelRoot_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        paddingTop = S.card_gap,
        overflow = "hidden",
        children = children,
    }
    return panelRoot_
end

-- ============================================================================
-- 统计概览
-- ============================================================================

function TradePanel._BuildSummaryCard(state, summary)
    local repColor = (summary.reputation or 0) >= 0 and C.accent_green or C.accent_red
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
            -- 标题行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label { text = "📦", fontSize = S.icon_size },
                    UI.Panel {
                        flexGrow = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = "跨国贸易",
                                fontSize = F.card_title,
                                fontWeight = "bold",
                                fontColor = C.accent_gold,
                            },
                            UI.Label {
                                text = "军火出口 · 装备订单 · 跨境运输",
                                fontSize = F.label,
                                fontColor = C.text_muted,
                            },
                        },
                    },
                },
            },
            UI.Divider { color = C.divider },
            -- 指标网格
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                children = {
                    TradePanel._MetricCell("可接订单",
                        tostring(summary.pool_count), C.accent_gold),
                    TradePanel._MetricCell("进行中",
                        tostring(summary.active_count), C.accent_blue),
                    TradePanel._MetricCell("已完成",
                        tostring(summary.completed), C.accent_green),
                    TradePanel._MetricCell("失败",
                        tostring(summary.failed), C.accent_red),
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                children = {
                    TradePanel._MetricCell("总收入",
                        Config.FormatNumber(summary.total_revenue), C.accent_gold),
                    TradePanel._MetricCell("声誉",
                        string.format("%+d", summary.reputation or 0), repColor),
                },
            },
            -- 制裁状态提示
            state.expeditions and state.expeditions.under_sanction and UI.Panel {
                width = "100%",
                backgroundColor = { 180, 50, 50, 40 },
                borderRadius = 4,
                padding = 6,
                children = {
                    UI.Label {
                        text = string.format("⚠ 列强制裁中（剩余 %d 季），贸易收入可能受影响",
                            state.expeditions.sanction_remaining or 0),
                        fontSize = F.label,
                        fontColor = C.accent_red,
                    },
                },
            } or nil,
        },
    }
end

-- ============================================================================
-- 可接取订单卡片
-- ============================================================================

function TradePanel._BuildAvailableOrderCard(state, order)
    -- 构建需求物品列表
    local itemRows = {}
    for _, item in ipairs(order.items_required or {}) do
        local catInfo = CATALOG[item.equip_id]
        local name = catInfo and catInfo.name or item.equip_id
        -- 检查库存
        local inStock = TradePanel._CountInventory(state, item.equip_id)
        local stockColor = inStock >= item.qty and C.accent_green or C.accent_red
        table.insert(itemRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "  · " .. name,
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
                UI.Label {
                    text = string.format("需 %d（库存 %d）", item.qty, inStock),
                    fontSize = F.label,
                    fontColor = stockColor,
                },
            },
        })
    end

    -- 风险等级颜色
    local riskColors = {
        low = C.accent_green,
        medium = C.accent_amber,
        high = C.accent_red,
    }
    local riskLabels = {
        low = "低风险",
        medium = "中风险",
        high = "高风险",
    }
    local riskColor = riskColors[order.risk_level] or C.text_muted
    local riskLabel = riskLabels[order.risk_level] or "未知"

    local canAccept = (state.ap.current + (state.ap.temp or 0)) >= BFT.accept_ap_cost

    -- 构建所有 children
    local cardChildren = {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = order.template_label or order.id,
                            fontSize = F.body,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                            flexShrink = 1,
                        },
                        UI.Panel {
                            paddingHorizontal = 5,
                            paddingVertical = 1,
                            backgroundColor = { riskColor[1], riskColor[2], riskColor[3], 40 },
                            borderRadius = S.radius_badge,
                            children = {
                                UI.Label {
                                    text = riskLabel,
                                    fontSize = F.label,
                                    fontColor = riskColor,
                                },
                            },
                        },
                    },
                },
                UI.Label {
                    text = Config.FormatNumber(order.payment_base) .. " ₿",
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.accent_gold,
                },
            },
        },
        -- 买家 + 时限
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = "买家：" .. (order.buyer_label or "未知"),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
                UI.Label {
                    text = "时限 " .. (order.deadline_turns or "?") .. " 季",
                    fontSize = F.label,
                    fontColor = C.text_muted,
                },
            },
        },
        -- 需求物品标题
        UI.Label {
            text = "需求装备：",
            fontSize = F.label,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        },
    }
    -- 追加物品行
    for _, row in ipairs(itemRows) do
        table.insert(cardChildren, row)
    end
    -- 按钮行：接单 + 一键完成
    local canQuick, quickReason = Trade.CanQuickFulfill(state, order)
    table.insert(cardChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        overflow = "hidden",
        children = {
            -- 接单按钮
            UI.Button {
                text = string.format("接单（%dAP）", BFT.accept_ap_cost),
                fontSize = F.body_minor,
                fontColor = canAccept and C.text_primary or C.text_muted,
                backgroundColor = canAccept and { 212, 175, 55, 60 } or C.bg_surface,
                borderRadius = S.radius_btn,
                borderWidth = 1,
                borderColor = canAccept and C.border_gold or C.border_soft,
                paddingVertical = 6,
                flexGrow = 1,
                flexShrink = 1,
                flexBasis = 0,
                disabled = not canAccept,
                onClick = Config.ClickGuard(function(self)
                    self.props.disabled = true
                    local ok, msg = Trade.AcceptOrder(state, order.id)
                    if ok then
                        UI.Toast.Show(msg, { variant = "success", duration = 1.5 })
                    else
                        UI.Toast.Show(msg, { variant = "error", duration = 1.5 })
                    end
                    if onStateChanged_ then onStateChanged_() end
                end),
            },
            -- 一键完成按钮
            UI.Button {
                text = "⚡一键发货（1AP）",
                fontSize = F.body_minor,
                fontColor = canQuick and C.text_primary or C.text_muted,
                backgroundColor = canQuick and { 74, 124, 89, 60 } or C.bg_surface,
                borderRadius = S.radius_btn,
                borderWidth = 1,
                borderColor = canQuick and { 74, 124, 89, 120 } or C.border_soft,
                paddingVertical = 6,
                flexGrow = 1,
                flexShrink = 1,
                flexBasis = 0,
                disabled = not canQuick,
                onClick = Config.ClickGuard(function(self)
                    self.props.disabled = true
                    local ok, msg = Trade.QuickFulfill(state, order.id, nil)
                    if ok then
                        UI.Toast.Show(msg, { variant = "success", duration = 2 })
                    else
                        UI.Toast.Show(msg, { variant = "error", duration = 1.5 })
                    end
                    if onStateChanged_ then onStateChanged_() end
                end),
            },
        },
    })
    -- 一键完成不可用时显示原因提示
    if not canQuick and quickReason then
        table.insert(cardChildren, UI.Label {
            text = "⚡ " .. quickReason,
            fontSize = F.label - 1,
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
        gap = 5,
        overflow = "hidden",
        children = cardChildren,
    }
end

-- ============================================================================
-- 进行中订单卡片
-- ============================================================================

function TradePanel._BuildActiveOrderCard(state, order)
    local statusLabels = {
        accepted = "已接取·待发货",
        shipping = "运输中",
    }
    local statusColors = {
        accepted = C.accent_amber,
        shipping = C.accent_blue,
    }
    local statusText = statusLabels[order.status] or order.status
    local statusColor = statusColors[order.status] or C.text_muted

    -- 需求 vs 已分配
    local itemRows = {}
    local allocMap = {}
    for _, item in ipairs(order.items_allocated or {}) do
        allocMap[item.equip_id] = (allocMap[item.equip_id] or 0) + 1
    end

    local allFulfilled = true
    for _, req in ipairs(order.items_required or {}) do
        local catInfo = CATALOG[req.equip_id]
        local name = catInfo and catInfo.name or req.equip_id
        local allocated = allocMap[req.equip_id] or 0
        local fulfilled = allocated >= req.qty
        if not fulfilled then allFulfilled = false end
        table.insert(itemRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = "  · " .. name,
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
                UI.Label {
                    text = string.format("%d/%d", allocated, req.qty),
                    fontSize = F.label,
                    fontWeight = "bold",
                    fontColor = fulfilled and C.accent_green or C.accent_red,
                },
            },
        })
    end

    local cardChildren = {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = order.template_label or order.id,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                    flexShrink = 1,
                },
                UI.Panel {
                    paddingHorizontal = 6,
                    paddingVertical = 2,
                    backgroundColor = { statusColor[1], statusColor[2], statusColor[3], 40 },
                    borderRadius = S.radius_badge,
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
        -- 报酬 + 剩余时间
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = "报酬：" .. Config.FormatNumber(order.payment_base) .. " ₿",
                    fontSize = F.label,
                    fontColor = C.accent_gold,
                },
                UI.Label {
                    text = order.status == "shipping"
                        and ("运输剩余 " .. (order.shipping_remaining or 0) .. " 季")
                        or ("时限剩余 " .. (order.remaining_turns or 0) .. " 季"),
                    fontSize = F.label,
                    fontColor = (order.remaining_turns or 99) <= 1
                        and C.accent_red or C.text_muted,
                },
            },
        },
    }

    -- 装备需求（仅已接取状态展开）
    if order.status == "accepted" then
        table.insert(cardChildren, UI.Label {
            text = "装备分配：",
            fontSize = F.label,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        })
        for _, row in ipairs(itemRows) do
            table.insert(cardChildren, row)
        end

        -- 一键分配按钮
        if not allFulfilled then
            table.insert(cardChildren, UI.Button {
                text = "一键分配库存装备",
                fontSize = F.body_minor,
                fontColor = C.accent_amber,
                backgroundColor = C.bg_elevated,
                borderRadius = S.radius_btn,
                borderWidth = 1,
                borderColor = C.accent_amber,
                paddingVertical = 5,
                width = "100%",
                onClick = Config.ClickGuard(function(self)
                    self.props.disabled = true
                    local allocations = {}
                    for _, req in ipairs(order.items_required or {}) do
                        local already = allocMap[req.equip_id] or 0
                        local need = req.qty - already
                        if need > 0 then
                            table.insert(allocations, {
                                equip_id = req.equip_id,
                                qty = need,
                            })
                        end
                    end
                    if #allocations > 0 then
                        local ok, msg = Trade.AllocateEquipment(state, order.id, allocations)
                        if ok then
                            UI.Toast.Show("装备分配完成", { variant = "success", duration = 1.5 })
                        else
                            UI.Toast.Show(msg, { variant = "error", duration = 1.5 })
                        end
                    end
                    if onStateChanged_ then onStateChanged_() end
                end),
            })
        end

        -- 发货按钮
        local canShip = allFulfilled
            and (state.ap.current + (state.ap.temp or 0)) >= BFT.ship_ap_cost
        if allFulfilled then
            -- 计算运费
            local routeDef = TradeRoutesData.GetRoute(order.route_id)
            local transportCost = routeDef
                and math.floor(routeDef.base_cost * GameState.GetInflationFactor(state))
                or 0
            local canAfford = state.cash >= transportCost
            local safetyPct = routeDef
                and math.floor(Trade.CalcRouteSafety(state, order.route_id, nil) * 100)
                or 0

            table.insert(cardChildren, UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = string.format("运费 %d · 安全 %d%%",
                            transportCost, safetyPct),
                        fontSize = F.label,
                        fontColor = C.text_muted,
                    },
                },
            })

            table.insert(cardChildren, UI.Button {
                text = string.format("发货（%d AP + %d₿ 运费）",
                    BFT.ship_ap_cost, transportCost),
                fontSize = F.body_minor,
                fontColor = (canShip and canAfford) and C.text_primary or C.text_muted,
                backgroundColor = (canShip and canAfford)
                    and { 41, 128, 185, 60 } or C.bg_surface,
                borderRadius = S.radius_btn,
                borderWidth = 1,
                borderColor = (canShip and canAfford)
                    and { 41, 128, 185, 120 } or C.border_soft,
                paddingVertical = 6,
                width = "100%",
                disabled = not (canShip and canAfford),
                onClick = Config.ClickGuard(function(self)
                    self.props.disabled = true
                    local ok, msg = Trade.ShipOrder(state, order.id, nil)
                    if ok then
                        UI.Toast.Show(msg, { variant = "success", duration = 1.5 })
                    else
                        UI.Toast.Show(msg, { variant = "error", duration = 1.5 })
                    end
                    if onStateChanged_ then onStateChanged_() end
                end),
            })
        end
    end

    -- 运输中状态：显示安全度
    if order.status == "shipping" then
        local safetyPct = math.floor(
            Trade.CalcRouteSafety(state, order.route_id, order.escort_squad_id) * 100)
        table.insert(cardChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = "安全度",
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                    width = 50,
                },
                UI.ProgressBar {
                    value = safetyPct / 100,
                    flexGrow = 1,
                    height = 5,
                    borderRadius = 3,
                    trackColor = C.bg_surface,
                    fillColor = safetyPct >= 70 and C.accent_green
                        or (safetyPct >= 40 and C.accent_amber or C.accent_red),
                },
                UI.Label {
                    text = safetyPct .. "%",
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                    width = 35,
                    textAlign = "right",
                },
            },
        })
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = { statusColor[1], statusColor[2], statusColor[3], 80 },
        padding = S.card_padding,
        flexDirection = "column",
        gap = 5,
        children = cardChildren,
    }
end

-- ============================================================================
-- 路线一览
-- ============================================================================

function TradePanel._BuildRoutesCard(state)
    local routes = TradeRoutesData.GetUnlockedRoutes(state)
    local locked = TradeRoutesData.GetLockedRoutes
        and TradeRoutesData.GetLockedRoutes(state) or {}

    local routeRows = {}
    for _, route in ipairs(routes) do
        local safety = math.floor(Trade.CalcRouteSafety(state, route.id, nil) * 100)
        local safeColor = safety >= 70 and C.accent_green
            or (safety >= 40 and C.accent_amber or C.accent_red)
        -- 组合路线名：波黑→城市（国家）
        local europe = state.europe or {}
        local countryLabel = route.buyer_power_id
        if europe[route.buyer_power_id] then
            countryLabel = europe[route.buyer_power_id].label or countryLabel
        end
        local routeDisplayName = route.dest_city
            and ("波黑→" .. route.dest_city .. "（" .. countryLabel .. "）")
            or route.name
        table.insert(routeRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingVertical = 3,
            children = {
                UI.Label {
                    text = routeDisplayName,
                    fontSize = F.body_minor,
                    fontColor = C.text_primary,
                    flexShrink = 1,
                },
                UI.Panel {
                    flexDirection = "row",
                    gap = 8,
                    children = {
                        UI.Label {
                            text = "距离 " .. (route.distance or 1),
                            fontSize = F.label,
                            fontColor = C.text_muted,
                        },
                        UI.Label {
                            text = safety .. "% 安全",
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = safeColor,
                        },
                    },
                },
            },
        })
    end

    if #routeRows == 0 then
        table.insert(routeRows, UI.Label {
            text = "尚无已开通路线",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
        })
    end

    local cardChildren = {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "已开通路线",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = #routes .. " 条",
                    fontSize = F.body_minor,
                    fontColor = C.accent_gold,
                },
            },
        },
        UI.Divider { color = C.divider },
    }
    for _, row in ipairs(routeRows) do
        table.insert(cardChildren, row)
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 5,
        children = cardChildren,
    }
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 统计库存中某装备数量
function TradePanel._CountInventory(state, equipId)
    local count = 0
    local inv = state.military and state.military.inventory or {}
    for _, item in ipairs(inv) do
        if item.equip_id == equipId and not item.repairing then
            count = count + 1
        end
    end
    return count
end

--- 指标格子
function TradePanel._MetricCell(label, value, color)
    return UI.Panel {
        flexGrow = 1, flexShrink = 1, flexBasis = 0,
        flexDirection = "column",
        alignItems = "center",
        gap = 2,
        padding = 4,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_badge,
        overflow = "hidden",
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

--- 段落分隔线
function TradePanel._SectionDivider(text, color)
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

--- 空状态提示
function TradePanel._EmptyHint(text)
    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        alignItems = "center",
        children = {
            UI.Label {
                text = text,
                fontSize = F.body_minor,
                fontColor = C.text_muted,
            },
        },
    }
end

return TradePanel
