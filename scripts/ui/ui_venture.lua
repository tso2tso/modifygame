-- ============================================================================
-- 商业远征 UI 面板
-- 展示市场渗透状态、活跃远征、商业据点、可渗透目标
-- 架构参照 ui_expedition.lua 的 Section-Card 模式
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local Balance = require("data.balance")
local GameState = require("game_state")
local Venture = require("systems.venture")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE
local BV = Balance.VENTURE

local VenturePanel = {}

-- 模块状态
local stateRef_ = nil
local onStateChanged_ = nil
local currentModal_ = nil

-- ============================================================================
-- 工具组件
-- ============================================================================

--- 指标单元格
local function _MetricCell(label, value, color)
    return UI.Panel {
        flexDirection = "column", alignItems = "center",
        flex = 1, paddingTop = 4, paddingBottom = 4,
        children = {
            UI.Label { text = tostring(value), fontSize = F.data_small, color = color or C.text_primary, textAlign = "center" },
            UI.Label { text = label, fontSize = F.label, color = C.text_secondary, textAlign = "center", marginTop = 2 },
        }
    }
end

--- 分节标题
local function _SectionDivider(text, color)
    return UI.Panel {
        flexDirection = "row", alignItems = "center",
        width = "100%", marginTop = S.section_gap, marginBottom = 4,
        children = {
            UI.Panel { height = 1, flex = 1, backgroundColor = C.divider },
            UI.Label { text = text, fontSize = F.label, color = color or C.text_secondary,
                       marginLeft = 8, marginRight = 8 },
            UI.Panel { height = 1, flex = 1, backgroundColor = C.divider },
        }
    }
end

--- 空状态提示
local function _EmptyHint(text)
    return UI.Label {
        text = text, fontSize = F.body_minor, color = C.text_muted,
        textAlign = "center", width = "100%", marginTop = 12, marginBottom = 12,
    }
end

--- 壁垒进度条
local function _BarrierBar(label, current, max, color)
    local pct = max > 0 and (current / max) or 0
    return UI.Panel {
        flexDirection = "column", width = "100%", marginTop = 4,
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                children = {
                    UI.Label { text = label, fontSize = F.label, color = C.text_secondary },
                    UI.Label { text = string.format("%d / %d", math.floor(current), math.floor(max)),
                               fontSize = F.label, color = C.text_label },
                }
            },
            UI.ProgressBar {
                value = pct, height = 6, marginTop = 2,
                trackColor = C.bg_inset,
                fillColor = color or C.accent_blue,
                borderRadius = 3,
            },
        }
    }
end

-- ============================================================================
-- 总览卡片
-- ============================================================================

local function _BuildSummaryCard(state, summary)
    local tensionColor = C.accent_green
    if summary.market_tension >= BV.sanction_threshold then
        tensionColor = C.accent_red
    elseif summary.market_tension >= BV.sanction_threshold * 0.6 then
        tensionColor = C.accent_amber
    end

    -- 计算实际净收入（与据点卡片、SettleTurn 一致）
    local inflation = GameState.GetInflationFactor(state)
    local sanctionMult = summary.under_sanction and BV.sanction_income_mult or 1.0
    local maintDiscount = GameState.GetModifierValue(state, "venture_maintenance_discount")
    local realNet = 0
    for _, post in pairs(summary.commercial_posts) do
        local inc = math.floor((post.income_per_turn or 0) * inflation * sanctionMult)
        local mnt = math.floor((post.maintenance or 0) * (1 - maintDiscount))
        realNet = realNet + inc - mnt
    end

    return UI.Panel {
        flexDirection = "column", width = "100%",
        backgroundColor = C.paper_dark, borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.border_card,
        padding = S.card_padding, marginBottom = S.card_gap,
        children = {
            UI.Label { text = "📊 商业远征概览", fontSize = F.card_title, color = C.text_primary, marginBottom = 6 },
            UI.Panel {
                flexDirection = "row", width = "100%",
                children = {
                    _MetricCell("紧张度", string.format("%.1f / %d", summary.market_tension, BV.sanction_threshold), tensionColor),
                    _MetricCell("活跃渗透", summary.active_count, C.accent_blue),
                    _MetricCell("商业据点", summary.post_count, C.accent_gold),
                    _MetricCell("净收入", string.format("%+d", realNet), realNet >= 0 and C.accent_green or C.accent_red),
                }
            },
            -- 战绩行
            UI.Panel {
                flexDirection = "row", width = "100%", marginTop = 6,
                children = {
                    _MetricCell("发起", summary.history.ventures_launched or 0, C.text_label),
                    _MetricCell("成功", summary.history.ventures_completed or 0, C.accent_green),
                    _MetricCell("失败", summary.history.ventures_failed or 0, C.accent_red),
                    _MetricCell("总投入", summary.history.total_venture_income or 0, C.accent_amber),
                }
            },
        }
    }
end

-- ============================================================================
-- 制裁警告
-- ============================================================================

local function _BuildSanctionWarning(summary)
    if not summary.under_sanction then return nil end
    return UI.Panel {
        width = "100%", backgroundColor = C.danger_bg,
        borderRadius = S.radius_card, borderWidth = 1, borderColor = C.accent_red,
        padding = S.card_padding, marginBottom = S.card_gap,
        children = {
            UI.Label {
                text = string.format("⚠ 贸易制裁中！商业据点收入减半，剩余 %d 季度", summary.sanction_remaining),
                fontSize = F.body, color = C.accent_red,
            },
        }
    }
end

-- ============================================================================
-- 待决策卡片（渗透成功，等待选择据点类型）
-- ============================================================================

local function _BuildAwaitingCard(state, powerId, awRecord)
    local country = state.europe and state.europe[powerId]
    local countryLabel = country and country.label or powerId

    local establishments = Venture.GetAvailableEstablishments(state)

    local estButtons = {}
    for _, est in ipairs(establishments) do
        local isMajor = country and country.tier == "major"
        local income = isMajor and est.income_major or est.income_minor
        local maint = isMajor and est.maintenance_major or est.maintenance_minor

        table.insert(estButtons, UI.Button {
            text = string.format("%s %s (+%d/-%d)", est.icon, est.label, income, maint),
            fontSize = F.body_minor,
            variant = est.available and "primary" or "ghost",
            disabled = not est.available,
            marginTop = 4, width = "100%",
            onClick = Config.ClickGuard(function(self)
                self.props.disabled = true
                local ok, msg = Venture.EstablishPost(state, powerId, est.id)
                if ok then
                    UI.Toast.Show(msg, { variant = "success", duration = 2.5 })
                else
                    UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                end
                if onStateChanged_ then onStateChanged_() end
            end),
        })
        -- 不可用原因提示
        if not est.available and est.unavailable_reason then
            table.insert(estButtons, UI.Label {
                text = "  └ " .. est.unavailable_reason,
                fontSize = F.label, color = C.text_muted, marginBottom = 2,
            })
        end
    end

    -- 放弃按钮
    table.insert(estButtons, UI.Button {
        text = "🚫 放弃建立据点",
        fontSize = F.body_minor, variant = "ghost",
        marginTop = 8, width = "100%",
        onClick = Config.ClickGuard(function(self)
            self.props.disabled = true
            local ok, msg = Venture.AbandonDecision(state, powerId)
            if ok then
                UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
            else
                UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
            end
            if onStateChanged_ then onStateChanged_() end
        end),
    })

    return UI.Panel {
        flexDirection = "column", width = "100%",
        backgroundColor = C.success_bg, borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.accent_green,
        padding = S.card_padding, marginBottom = S.card_gap,
        children = {
            UI.Label {
                text = string.format("🎉 %s - 渗透成功！", countryLabel),
                fontSize = F.card_title, color = C.accent_green, marginBottom = 4,
            },
            UI.Label {
                text = "选择要建立的商业据点类型：",
                fontSize = F.body, color = C.text_primary, marginBottom = 6,
            },
            table.unpack(estButtons),
        }
    }
end

-- ============================================================================
-- 活跃渗透卡片
-- ============================================================================

local function _BuildActiveCard(state, powerId)
    local detail = Venture.GetVentureDetail(state, powerId)
    if not detail then return _EmptyHint("数据异常") end

    local children = {
        -- 标题行
        UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%",
            children = {
                UI.Label {
                    text = string.format("%s %s", detail.strategy_icon, detail.label),
                    fontSize = F.card_title, color = C.text_primary,
                },
                UI.Label {
                    text = string.format("🏷 %s", detail.investment_label),
                    fontSize = F.label, color = C.accent_gold,
                },
            }
        },
        -- 策略+城市
        UI.Label {
            text = string.format("策略: %s  |  目标: %s  |  已投 %d 金",
                detail.strategy_label, detail.city or "未知", detail.total_invested),
            fontSize = F.body_minor, color = C.text_secondary, marginTop = 2,
        },
        -- 壁垒进度条
        _BarrierBar("市场壁垒", detail.market_barrier, detail.max_market_barrier, C.accent_blue),
        -- 数据行
        UI.Panel {
            flexDirection = "row", width = "100%", marginTop = 6,
            children = {
                _MetricCell("渗透/回合", string.format("%.1f", detail.penetration_per_turn), C.accent_blue),
                _MetricCell("费用/回合", detail.turn_cost, C.accent_amber),
                _MetricCell("预估", detail.estimated_turns > 0
                    and string.format("~%d季", detail.estimated_turns) or "计算中", C.text_label),
                _MetricCell("已进行", string.format("%d季", detail.turns_active), C.text_label),
            }
        },
    }

    -- 操作按钮行
    local btnRow = {}

    -- 调整投资等级
    table.insert(btnRow, UI.Button {
        text = "📈 调整投资", fontSize = F.body_minor, variant = "ghost",
        flex = 1, marginRight = 4,
        onClick = Config.ClickGuard(function()
            VenturePanel._ShowInvestmentDialog(state, powerId)
        end),
    })

    -- 切换策略
    table.insert(btnRow, UI.Button {
        text = "🔄 换策略", fontSize = F.body_minor, variant = "ghost",
        flex = 1, marginRight = 4,
        onClick = Config.ClickGuard(function()
            VenturePanel._ShowStrategyDialog(state, powerId)
        end),
    })

    -- 撤退
    table.insert(btnRow, UI.Button {
        text = "🚪 撤出", fontSize = F.body_minor, variant = "danger",
        flex = 1,
        onClick = Config.ClickGuard(function(self)
            self.props.disabled = true
            local ok, msg = Venture.WithdrawVenture(state, powerId)
            if ok then
                UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
            else
                UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
            end
            if onStateChanged_ then onStateChanged_() end
        end),
    })

    table.insert(children, UI.Panel {
        flexDirection = "row", width = "100%", marginTop = 8,
        children = btnRow,
    })

    return UI.Panel {
        flexDirection = "column", width = "100%",
        backgroundColor = C.paper_dark, borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.accent_blue,
        padding = S.card_padding, marginBottom = S.card_gap,
        children = children,
    }
end

-- ============================================================================
-- 可渗透目标卡片
-- ============================================================================

local function _BuildTargetCard(state, target)
    local country = state.europe and state.europe[target.power_id]
    local countryLabel = country and country.label or target.power_id
    local stability = country and country.stability or 50
    local maxBarrier = target.max_market_barrier or target.max_barrier or 1
    local curBarrier = target.market_barrier or target.current_barrier or maxBarrier
    local barrierPct = maxBarrier > 0
        and math.floor((curBarrier / maxBarrier) * 100) or 100

    return UI.Panel {
        flexDirection = "column", width = "100%",
        backgroundColor = C.bg_surface, borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.border_soft,
        padding = S.card_padding, marginBottom = S.card_gap,
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                children = {
                    UI.Label { text = string.format("🏙 %s", countryLabel), fontSize = F.subtitle, color = C.text_primary },
                    UI.Label { text = string.format("稳定度 %d", stability), fontSize = F.label, color = C.text_secondary },
                }
            },
            UI.Panel {
                flexDirection = "row", width = "100%", marginTop = 4,
                children = {
                    _MetricCell("壁垒", string.format("%d%%", barrierPct), C.accent_blue),
                    _MetricCell("城市", target.city or "未知", C.text_label),
                    _MetricCell("距离", target.distance or "?", C.text_label),
                }
            },
            UI.Button {
                text = string.format("📦 发起渗透 (%dAP)", BV.venture_ap_cost),
                fontSize = F.body, variant = "primary",
                width = "100%", marginTop = 6,
                onClick = Config.ClickGuard(function()
                    VenturePanel._ShowLaunchDialog(state, target.power_id)
                end),
            },
        }
    }
end

-- ============================================================================
-- 已建立据点卡片
-- ============================================================================

local function _BuildPostCard(state, powerId, post)
    local country = state.europe and state.europe[powerId]
    local countryLabel = country and country.label or powerId
    local inflation = GameState.GetInflationFactor(state)
    local sanctionMult = (state.ventures.under_trade_sanction) and BV.sanction_income_mult or 1.0
    local maintDiscount = GameState.GetModifierValue(state, "venture_maintenance_discount")
    local actualIncome = math.floor((post.income_per_turn or 0) * inflation * sanctionMult)
    local actualMaint = math.floor((post.maintenance or 0) * (1 - maintDiscount))

    return UI.Panel {
        flexDirection = "column", width = "100%",
        backgroundColor = C.paper_dark, borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.border_gold,
        padding = S.card_padding, marginBottom = S.card_gap,
        children = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                children = {
                    UI.Label {
                        text = string.format("%s %s · %s", post.icon or "🏪", post.label or "贸易站", countryLabel),
                        fontSize = F.subtitle, color = C.accent_gold,
                    },
                    UI.Label {
                        text = string.format("%+d 金/季", actualIncome - actualMaint),
                        fontSize = F.body, color = (actualIncome - actualMaint) >= 0 and C.accent_green or C.accent_red,
                    },
                }
            },
            UI.Panel {
                flexDirection = "row", width = "100%", marginTop = 4,
                children = {
                    _MetricCell("收入", actualIncome, C.accent_green),
                    _MetricCell("维护", actualMaint, C.accent_red),
                    _MetricCell("城市", post.city or "未知", C.text_label),
                }
            },
            UI.Button {
                text = "🗑 关闭据点", fontSize = F.body_minor, variant = "ghost",
                width = "100%", marginTop = 6,
                onClick = Config.ClickGuard(function(self)
                    self.props.disabled = true
                    local ok, msg = Venture.DismantlePost(state, powerId)
                    if ok then
                        UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                    else
                        UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                    end
                    if onStateChanged_ then onStateChanged_() end
                end),
            },
        }
    }
end

-- ============================================================================
-- 主面板构建
-- ============================================================================

function VenturePanel._BuildContent(state)
    local summary = Venture.GetSummary(state)
    local children = {}

    -- 1. 总览卡片
    table.insert(children, _BuildSummaryCard(state, summary))

    -- 2. 制裁警告
    local sanctionWarn = _BuildSanctionWarning(summary)
    if sanctionWarn then
        table.insert(children, sanctionWarn)
    end

    -- 3. 待决策（渗透成功，选择据点类型）
    -- awaiting_decision 是数组（table.insert），用 ipairs 迭代，从元素中取 power_id
    local awaitingList = summary.awaiting_decision or {}
    local awaitingCount = #awaitingList
    if awaitingCount > 0 then
        table.insert(children, _SectionDivider("⏳ 待决策", C.accent_green))
        for _, aw in ipairs(awaitingList) do
            table.insert(children, _BuildAwaitingCard(state, aw.power_id, aw))
        end
    end

    -- 4. 活跃渗透
    local activeCount = 0
    for powerId, _ in pairs(summary.active_ventures) do
        activeCount = activeCount + 1
    end
    if activeCount > 0 then
        table.insert(children, _SectionDivider("🔄 进行中", C.accent_blue))
        for powerId, _ in pairs(summary.active_ventures) do
            table.insert(children, _BuildActiveCard(state, powerId))
        end
    end

    -- 5. 可渗透目标
    local targets = Venture.GetValidTargets(state)
    if #targets > 0 then
        table.insert(children, _SectionDivider("🎯 可渗透市场", C.text_secondary))
        for _, target in ipairs(targets) do
            table.insert(children, _BuildTargetCard(state, target))
        end
    elseif activeCount == 0 and awaitingCount == 0 then
        table.insert(children, _SectionDivider("🎯 可渗透市场", C.text_secondary))
        table.insert(children, _EmptyHint("暂无可渗透的市场目标"))
    end

    -- 6. 已建立据点
    local postCount = 0
    for _ in pairs(summary.commercial_posts) do
        postCount = postCount + 1
    end
    if postCount > 0 then
        table.insert(children, _SectionDivider("🏪 商业据点", C.accent_gold))
        for powerId, post in pairs(summary.commercial_posts) do
            table.insert(children, _BuildPostCard(state, powerId, post))
        end
    end

    return UI.Panel {
        flexDirection = "column", width = "100%",
        padding = S.page_padding,
        children = children,
    }
end

-- ============================================================================
-- 发起渗透弹窗
-- ============================================================================

function VenturePanel._ShowLaunchDialog(state, powerId)
    if currentModal_ then currentModal_:Close() end

    local country = state.europe and state.europe[powerId]
    local countryLabel = country and country.label or powerId
    local strategies = Venture.GetAvailableStrategies(state)

    local selectedStrategy = "normal"
    local selectedLevel = 1

    local function _BuildDialogContent()
        local inflation = GameState.GetInflationFactor(state)
        local levelDef = BV.investment_levels[selectedLevel]
        local stratDef = BV.strategies[selectedStrategy]
        local turnCost = math.floor(
            BV.base_investment_cost
            * (levelDef and levelDef.cost_mult or 1)
            * (stratDef and stratDef.cost_mult or 1)
            * inflation)
        local estimatedTurns = Venture.EstimateTurns(state, powerId, selectedStrategy, selectedLevel)

        local contentChildren = {}

        -- 费用预览
        table.insert(contentChildren, UI.Panel {
            flexDirection = "row", width = "100%", marginBottom = 8,
            children = {
                _MetricCell("AP消耗", BV.venture_ap_cost, C.accent_amber),
                _MetricCell("费用/季", turnCost, C.accent_gold),
                _MetricCell("预估", estimatedTurns > 0
                    and string.format("~%d季", estimatedTurns) or "?", C.accent_blue),
            }
        })

        -- 策略选择
        table.insert(contentChildren, UI.Label {
            text = "选择渗透策略：", fontSize = F.subtitle, color = C.text_primary, marginBottom = 4,
        })
        for _, strat in ipairs(strategies) do
            local isSelected = strat.id == selectedStrategy
            table.insert(contentChildren, UI.Panel {
                flexDirection = "row", alignItems = "center",
                width = "100%", padding = 8, marginBottom = 4,
                backgroundColor = isSelected and C.info_bg or C.bg_surface,
                borderRadius = S.radius_card,
                borderWidth = isSelected and 1 or 0,
                borderColor = C.accent_blue,
                opacity = strat.available and 1.0 or 0.5,
                onPointerUp = strat.available and Config.TapGuard(function()
                    selectedStrategy = strat.id
                    _RefreshLaunchContent()
                end) or nil,
                children = {
                    UI.Panel {
                        flex = 1, flexDirection = "column",
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", width = "100%",
                                children = {
                                    UI.Label { text = strat.icon .. " " .. strat.label, fontSize = F.body,
                                               color = isSelected and C.accent_blue or C.text_primary, flex = 1 },
                                    UI.Label {
                                        text = strat.available and string.format("×%.1f渗透 ×%.1f费用", strat.penetration_mult, strat.cost_mult)
                                            or (strat.unavailable_reason or "不可用"),
                                        fontSize = F.label, color = strat.available and C.text_secondary or C.accent_red,
                                    },
                                }
                            },
                            strat.available and strat.desc and UI.Label {
                                text = strat.desc, fontSize = F.label - 1,
                                color = isSelected and C.accent_gold or C.text_hint,
                                marginTop = 2,
                            } or nil,
                        }
                    },
                }
            })
        end

        -- 投资等级选择
        table.insert(contentChildren, UI.Label {
            text = "投资等级：", fontSize = F.subtitle, color = C.text_primary,
            marginTop = 8, marginBottom = 4,
        })
        for i, lvl in ipairs(BV.investment_levels) do
            local isSelected = i == selectedLevel
            table.insert(contentChildren, UI.Panel {
                flexDirection = "row", alignItems = "center",
                width = "100%", padding = 8, marginBottom = 4,
                backgroundColor = isSelected and C.info_bg or C.bg_surface,
                borderRadius = S.radius_card,
                borderWidth = isSelected and 1 or 0,
                borderColor = C.accent_blue,
                onPointerUp = Config.TapGuard(function()
                    selectedLevel = i
                    _RefreshLaunchContent()
                end),
                children = {
                    UI.Label { text = lvl.label, fontSize = F.body,
                               color = isSelected and C.accent_gold or C.text_primary, flex = 1 },
                    UI.Label {
                        text = string.format("×%.1f渗透 ×%.1f费用", lvl.mult, lvl.cost_mult),
                        fontSize = F.label, color = C.text_secondary,
                    },
                }
            })
        end

        return UI.ScrollView {
            width = "100%", flex = 1, maxHeight = 400,
            children = contentChildren,
        }
    end

    function _RefreshLaunchContent()
        if not currentModal_ then return end
        currentModal_:ClearContent()
        currentModal_:AddContent(_BuildDialogContent())

        -- 确认按钮
        local canAfford = (state.ap.current or 0) >= BV.venture_ap_cost
        currentModal_:AddContent(UI.Button {
            text = canAfford and "✅ 确认发起" or "❌ AP不足",
            variant = canAfford and "primary" or "ghost",
            disabled = not canAfford,
            width = "100%", marginTop = 8,
            onClick = Config.ClickGuard(function(self)
                self.props.disabled = true
                local ok, msg = Venture.LaunchVenture(state, powerId, selectedStrategy, selectedLevel)
                if ok then
                    UI.Toast.Show(msg, { variant = "success", duration = 2.5 })
                    if currentModal_ then currentModal_:Close() end
                else
                    UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                end
                if onStateChanged_ then onStateChanged_() end
            end),
        })
    end

    currentModal_ = UI.Modal {
        title = string.format("📦 商业渗透 · %s", countryLabel),
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            currentModal_ = nil
            self:Destroy()
        end,
    }
    _RefreshLaunchContent()
    currentModal_:Open()
end

-- ============================================================================
-- 调整投资等级弹窗
-- ============================================================================

function VenturePanel._ShowInvestmentDialog(state, powerId)
    if currentModal_ then currentModal_:Close() end

    local record = (state.ventures.active or {})[powerId]
    if not record then return end

    local country = state.europe and state.europe[powerId]
    local countryLabel = country and country.label or powerId

    local children = {}
    for i, lvl in ipairs(BV.investment_levels) do
        local isCurrent = i == (record.investment_level or 1)
        table.insert(children, UI.Button {
            text = string.format("%s%s (×%.1f费用)",
                isCurrent and "✓ " or "", lvl.label, lvl.cost_mult),
            variant = isCurrent and "ghost" or "primary",
            disabled = isCurrent,
            width = "100%", marginBottom = 4,
            onClick = Config.ClickGuard(function(self)
                self.props.disabled = true
                local ok, msg = Venture.ChangeInvestment(state, powerId, i)
                if ok then
                    UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                    if currentModal_ then currentModal_:Close() end
                else
                    UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                end
                if onStateChanged_ then onStateChanged_() end
            end),
        })
    end

    currentModal_ = UI.Modal {
        title = string.format("📈 调整投资 · %s", countryLabel),
        size = "sm",
        closeOnOverlay = true, closeOnEscape = true, showCloseButton = true,
        onClose = function(self)
            currentModal_ = nil
            self:Destroy()
        end,
    }
    currentModal_:AddContent(UI.Panel {
        flexDirection = "column", width = "100%", padding = 8,
        children = children,
    })
    currentModal_:Open()
end

-- ============================================================================
-- 切换策略弹窗
-- ============================================================================

function VenturePanel._ShowStrategyDialog(state, powerId)
    if currentModal_ then currentModal_:Close() end

    local record = (state.ventures.active or {})[powerId]
    if not record then return end

    local country = state.europe and state.europe[powerId]
    local countryLabel = country and country.label or powerId
    local strategies = Venture.GetAvailableStrategies(state)

    local children = {}
    for _, strat in ipairs(strategies) do
        local isCurrent = strat.id == record.strategy_id
        table.insert(children, UI.Panel {
            flexDirection = "column", width = "100%", marginBottom = 6,
            children = {
                UI.Button {
                    text = string.format("%s%s %s", isCurrent and "✓ " or "", strat.icon, strat.label),
                    variant = isCurrent and "ghost" or (strat.available and "primary" or "ghost"),
                    disabled = isCurrent or not strat.available,
                    width = "100%",
                    onClick = Config.ClickGuard(function(self)
                        self.props.disabled = true
                        local ok, msg = Venture.ChangeStrategy(state, powerId, strat.id)
                        if ok then
                            UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                            if currentModal_ then currentModal_:Close() end
                        else
                            UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                        end
                        if onStateChanged_ then onStateChanged_() end
                    end),
                },
                UI.Label {
                    text = strat.desc .. (not strat.available and (" (" .. (strat.unavailable_reason or "不可用") .. ")") or ""),
                    fontSize = F.label, color = strat.available and C.text_secondary or C.text_muted,
                    marginTop = 2,
                },
            }
        })
    end

    currentModal_ = UI.Modal {
        title = string.format("🔄 切换策略 · %s", countryLabel),
        size = "sm",
        closeOnOverlay = true, closeOnEscape = true, showCloseButton = true,
        onClose = function(self)
            currentModal_ = nil
            self:Destroy()
        end,
    }
    currentModal_:AddContent(UI.Panel {
        flexDirection = "column", width = "100%", padding = 8,
        children = children,
    })
    currentModal_:Open()
end

-- ============================================================================
-- 公开 API
-- ============================================================================

function VenturePanel.EnsureInit(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged or nil
end

function VenturePanel.Build(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged or nil
    return VenturePanel._BuildContent(state)
end

return VenturePanel
