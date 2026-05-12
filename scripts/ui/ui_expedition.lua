-- ============================================================================
-- 远征面板 UI（多回合并发远征版）
-- 世界页子标签：概览 / 活跃远征 / 待占领 / 可攻击目标 / 已占领列表
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local Expedition = require("systems.expedition")
local Equipment = require("systems.equipment")
local EquipmentData = require("data.equipment_data")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE
local BE = Balance.EXPEDITION

local ExpeditionPanel = {}

-- ── 模块状态 ──
---@type table
local stateRef_ = nil
---@type function|nil
local onStateChanged_ = nil
---@type Modal|nil
local currentModal_ = nil

-- ============================================================================
-- 入口
-- ============================================================================

--- 确保模块级回调已设置（供外部如 ui_world drawer 调用 _ShowDeployDialog 前使用）
---@param state table
---@param callbacks table|nil
function ExpeditionPanel.EnsureInit(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged or nil
end

--- 构建远征面板内容（被 ui_world.lua 的 _SwitchSubTab 调用）
---@param state table
---@param callbacks table
---@return table widget
function ExpeditionPanel.Build(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged or nil
    return ExpeditionPanel._BuildContent(state)
end

-- ============================================================================
-- 主布局
-- ============================================================================

function ExpeditionPanel._BuildContent(state)
    local summary = Expedition.GetSummary(state)
    local children = {}

    -- 1. 概览卡片
    table.insert(children, ExpeditionPanel._BuildSummaryCard(state, summary))

    -- 2. 制裁/干预警告
    local sanctioned, reason = Expedition.CheckSanction(state)
    if sanctioned then
        table.insert(children, ExpeditionPanel._BuildSanctionWarning(state, reason))
    end

    -- 3. 待占领决策（HP归零、等待玩家决策的国家）
    if #summary.awaiting_occupation > 0 then
        table.insert(children, ExpeditionPanel._SectionDivider("待占领决策", C.accent_blue))
        for _, aw in ipairs(summary.awaiting_occupation) do
            table.insert(children, ExpeditionPanel._BuildAwaitingCard(state, aw))
        end
    end

    -- 4. 活跃远征
    if summary.active_count > 0 then
        table.insert(children, ExpeditionPanel._SectionDivider(
            string.format("进行中远征 (%d)", summary.active_count), C.accent_red))
        for countryId, record in pairs(summary.active_expeditions) do
            table.insert(children, ExpeditionPanel._BuildActiveExpeditionCard(state, record))
        end
    end

    -- 5. 可攻击目标
    local targets = Expedition.GetValidTargets(state)
    if #targets > 0 then
        table.insert(children, ExpeditionPanel._SectionDivider("可攻击目标", C.accent_amber))
        for _, target in ipairs(targets) do
            table.insert(children, ExpeditionPanel._BuildTargetCard(state, target))
        end
    else
        if summary.active_count == 0 and #summary.awaiting_occupation == 0 then
            table.insert(children, ExpeditionPanel._SectionDivider("可攻击目标", C.text_muted))
            table.insert(children, ExpeditionPanel._EmptyHint("暂无可攻击的目标国家"))
        end
    end

    -- 6. 已占领国家
    if #(summary.occupied_countries) > 0 then
        table.insert(children, ExpeditionPanel._SectionDivider("已占领领土", C.accent_green))
        for _, occ in ipairs(summary.occupied_countries) do
            table.insert(children, ExpeditionPanel._BuildOccupiedCard(state, occ))
        end
    end

    -- 历史战绩已合并到概览卡片中

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        paddingTop = S.card_gap,
        children = children,
    }
end

-- ============================================================================
-- 概览卡片
-- ============================================================================

function ExpeditionPanel._BuildSummaryCard(state, summary)
    local aggression = summary.aggression or 0
    local aggColor = aggression < 3 and C.accent_green
        or (aggression < BE.sanction_threshold and C.accent_amber or C.accent_red)
    local aggLabel = aggression < 3 and "低"
        or (aggression < BE.sanction_threshold and "中" or "高危")

    local hist = summary.history or {}
    local hasHistory = (hist.expeditions_launched or 0) > 0

    local cardChildren = {
        -- 核心指标：侵略度 + 已占领 + 战绩
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            children = {
                ExpeditionPanel._MetricCell("侵略度",
                    string.format("%.1f/%d (%s)", aggression, BE.sanction_threshold, aggLabel), aggColor),
                ExpeditionPanel._MetricCell("已占领",
                    tostring(summary.occupied_count), C.accent_green),
            },
        },
    }

    -- 有战绩时追加一行
    if hasHistory then
        table.insert(cardChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            children = {
                ExpeditionPanel._MetricCell("远征",
                    tostring(hist.expeditions_launched or 0), C.accent_amber),
                ExpeditionPanel._MetricCell("胜",
                    tostring(hist.expeditions_won or 0), C.accent_green),
                ExpeditionPanel._MetricCell("败",
                    tostring(hist.expeditions_lost or 0), C.accent_red),
                ExpeditionPanel._MetricCell("征服",
                    tostring(hist.countries_conquered or 0), C.accent_gold),
            },
        })
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_gold,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 6,
        children = cardChildren,
    }
end

-- ============================================================================
-- 制裁警告
-- ============================================================================

function ExpeditionPanel._BuildSanctionWarning(state, reason)
    local title, desc
    if reason == "military_intervention" then
        title = "列强军事干预"
        desc = string.format(
            "侵略度已达 %.1f（干预阈值 %d），列强可能发动军事打击！",
            state.expeditions.aggression_counter or 0,
            BE.intervention_threshold)
    else
        title = "经济制裁生效"
        desc = string.format(
            "侵略度已达 %.1f（制裁阈值 %d），贸易和外交收入受影响。制裁剩余 %d 季。",
            state.expeditions.aggression_counter or 0,
            BE.sanction_threshold,
            state.expeditions.sanction_remaining or 0)
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 180, 50, 50, 40 },
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.accent_red,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 4,
        children = {
            UI.Label {
                text = "⚠ " .. title,
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = C.accent_red,
            },
            UI.Label {
                text = desc,
                fontSize = F.label,
                fontColor = { 220, 160, 160, 255 },
            },
        },
    }
end

-- ============================================================================
-- 活跃远征卡片
-- ============================================================================

function ExpeditionPanel._BuildActiveExpeditionCard(state, record)
    local countryId = record.country_id
    local country = state.europe[countryId]
    if not country then return ExpeditionPanel._EmptyHint("数据异常: " .. countryId) end

    local deployedPower = Expedition.CalcDeployedPower(state, record)
    local deployedSoldiers = Expedition.CalcDeployedSoldiers(state, record)
    local turnDamage = Expedition.CalcTurnDamage(state, record)
    local estTurns = (country.current_hp or 0) > 0 and turnDamage > 0
        and math.ceil(country.current_hp / turnDamage) or 0
    local successRate = math.floor(Expedition.CalcSuccessRate(state, record) * 100)
    local successColor = successRate >= 70 and C.accent_green
        or (successRate >= 50 and C.accent_amber or C.accent_red)

    local hpPct = country.max_hp > 0 and (country.current_hp / country.max_hp) or 0
    local hpColor = hpPct > 0.5 and C.accent_green
        or (hpPct > 0.2 and C.accent_amber or C.accent_red)

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
                            text = "⚔ " .. (record.label or countryId),
                            fontSize = F.body,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                            flexShrink = 1,
                        },
                        UI.Panel {
                            paddingHorizontal = 5,
                            paddingVertical = 1,
                            backgroundColor = { 180, 60, 60, 40 },
                            borderRadius = S.radius_badge,
                            children = {
                                UI.Label {
                                    text = string.format("第%d回合", record.turns_elapsed or 0),
                                    fontSize = F.label,
                                    fontColor = C.accent_red,
                                },
                            },
                        },
                    },
                },
                UI.Label {
                    text = string.format("成功率 %d%%", successRate),
                    fontSize = F.body_minor,
                    fontWeight = "bold",
                    fontColor = successColor,
                },
            },
        },
        -- HP血条
        ExpeditionPanel._HPBar("军事HP", country.current_hp, country.max_hp, hpColor),
    }

    -- 大国政治HP
    if country.tier == "major" and country.political_hp and country.max_political_hp then
        local polPct = country.max_political_hp > 0
            and (country.political_hp / country.max_political_hp) or 0
        local polColor = polPct > 0.5 and { 100, 149, 237, 255 }
            or (polPct > 0.2 and C.accent_amber or C.accent_red)
        table.insert(cardChildren,
            ExpeditionPanel._HPBar("政治HP", country.political_hp, country.max_political_hp, polColor))
    end

    -- 部署信息行
    table.insert(cardChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 4,
        children = {
            ExpeditionPanel._MetricCell("部署战力",
                tostring(math.floor(deployedPower)), C.accent_gold),
            ExpeditionPanel._MetricCell("部署兵力",
                tostring(deployedSoldiers) .. "人", C.text_primary),
            ExpeditionPanel._MetricCell("每回合伤害",
                tostring(math.floor(turnDamage)), C.accent_red),
            ExpeditionPanel._MetricCell("预估回合",
                estTurns > 0 and ("~" .. tostring(estTurns)) or "-", C.accent_amber),
        },
    })

    -- 部署详情（编队列表）
    if record.deployed_squads and #record.deployed_squads > 0 then
        local squadLabels = {}
        for _, sqId in ipairs(record.deployed_squads) do
            for _, squad in ipairs(state.military.squads or {}) do
                if squad.id == sqId then
                    table.insert(squadLabels,
                        string.format("%s(%d人)", squad.name or sqId, squad.size or 0))
                    break
                end
            end
        end

        table.insert(cardChildren, UI.Label {
            text = "部署: " .. table.concat(squadLabels, ", "),
            fontSize = F.label,
            fontColor = C.text_muted,
        })
    end

    -- 操作按钮行
    local btnRow = {}

    -- 增援按钮
    table.insert(btnRow, UI.Button {
        text = string.format("增援 (%dAP)", BE.expedition_reinforce_ap),
        fontSize = F.label,
        fontColor = C.accent_green,
        backgroundColor = { 60, 120, 60, 40 },
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.accent_green,
        paddingVertical = 5,
        paddingHorizontal = 8,
        flexGrow = 1,
        onClick = Config.ClickGuard(function()
            ExpeditionPanel._ShowDeployDialog(state, countryId, "reinforce")
        end),
    })

    -- 撤退按钮
    table.insert(btnRow, UI.Button {
        text = string.format("撤退 (%dAP)", BE.expedition_withdraw_ap),
        fontSize = F.label,
        fontColor = C.accent_amber,
        backgroundColor = { 120, 100, 40, 40 },
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.accent_amber,
        paddingVertical = 5,
        paddingHorizontal = 8,
        flexGrow = 1,
        onClick = Config.ClickGuard(function()
            ExpeditionPanel._ShowWithdrawDialog(state, countryId)
        end),
    })

    table.insert(cardChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        children = btnRow,
    })

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 2,
        borderColor = C.accent_red,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 5,
        children = cardChildren,
    }
end

-- ============================================================================
-- 待占领决策卡片
-- ============================================================================

function ExpeditionPanel._BuildAwaitingCard(state, aw)
    local countryId = aw.country_id
    local country = state.europe[countryId]
    local label = aw.label or (country and country.label) or countryId
    local isMajor = country and country.tier == "major"

    -- 占领收益预估
    local income = isMajor and BE.occupy_income_major or BE.occupy_income_minor
    local maintenance = isMajor and BE.occupy_maintenance_major or BE.occupy_maintenance_minor
    local netIncome = income - maintenance

    -- 可用势力列表
    local factions = {}
    for _, f in ipairs(state.ai_factions or {}) do
        table.insert(factions, { id = f.id, name = f.name, attitude = f.attitude or 0 })
    end

    local cardChildren = {
        -- 标题
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = "🏴 " .. label,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.accent_blue,
                    flexShrink = 1,
                },
                UI.Panel {
                    paddingHorizontal = 5,
                    paddingVertical = 1,
                    backgroundColor = { 41, 128, 185, 40 },
                    borderRadius = S.radius_badge,
                    children = {
                        UI.Label {
                            text = "等待决策",
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = C.accent_blue,
                        },
                    },
                },
            },
        },
        -- 占领收益预估
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            children = {
                ExpeditionPanel._MetricCell("季收入", "+" .. tostring(income), C.accent_gold),
                ExpeditionPanel._MetricCell("维护费", tostring(maintenance), C.accent_amber),
                ExpeditionPanel._MetricCell("净收益",
                    (netIncome >= 0 and "+" or "") .. tostring(netIncome),
                    netIncome >= 0 and C.accent_green or C.accent_red),
            },
        },
    }

    -- 操作按钮

    -- A. 自行占领
    local canOccupySelf = state.ap.current >= BE.occupy_ap_cost
        and state.cash >= BE.occupy_cash_cost
    table.insert(cardChildren, UI.Button {
        text = string.format("自行占领 (%dAP+%d₿)", BE.occupy_ap_cost, BE.occupy_cash_cost),
        fontSize = F.label,
        fontColor = canOccupySelf and C.text_primary or C.text_muted,
        backgroundColor = canOccupySelf and { 41, 128, 185, 60 } or C.bg_surface,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = canOccupySelf and C.accent_blue or C.border_soft,
        paddingVertical = 6,
        width = "100%",
        disabled = not canOccupySelf,
        onClick = Config.ClickGuard(function(self)
            self.props.disabled = true
            local ok, msg = Expedition.OccupySelf(state, countryId)
            if ok then
                UI.Toast.Show(msg, { variant = "success", duration = 2.5 })
            else
                UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
            end
            if onStateChanged_ then onStateChanged_() end
        end),
    })

    -- B. 交给势力（选好感度最高的）
    if #factions > 0 then
        -- 显示好感度最高势力
        table.sort(factions, function(a, b) return a.attitude > b.attitude end)
        local bestFaction = factions[1]
        local canGive = state.ap.current >= BE.give_to_faction_ap
        table.insert(cardChildren, UI.Button {
            text = string.format("交给%s (+%d关系, %dAP)",
                bestFaction.name or bestFaction.id,
                BE.give_to_faction_relation,
                BE.give_to_faction_ap),
            fontSize = F.label,
            fontColor = canGive and { 100, 200, 100, 255 } or C.text_muted,
            backgroundColor = canGive and { 60, 120, 60, 40 } or C.bg_surface,
            borderRadius = S.radius_btn,
            borderWidth = 1,
            borderColor = canGive and C.accent_green or C.border_soft,
            paddingVertical = 6,
            width = "100%",
            disabled = not canGive,
            onClick = Config.ClickGuard(function(self)
                self.props.disabled = true
                local ok, msg = Expedition.OccupyGiveToFaction(state, countryId, bestFaction.id)
                if ok then
                    UI.Toast.Show(msg, { variant = "success", duration = 2.5 })
                else
                    UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                end
                if onStateChanged_ then onStateChanged_() end
            end),
        })
    end

    -- C. 放弃
    table.insert(cardChildren, UI.Button {
        text = "放弃占领（HP恢复30%）",
        fontSize = F.label,
        fontColor = C.text_muted,
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.border_soft,
        paddingVertical = 5,
        width = "100%",
        onClick = Config.ClickGuard(function(self)
            self.props.disabled = true
            local ok, msg = Expedition.AbandonOccupation(state, countryId)
            if ok then
                UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
            else
                UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
            end
            if onStateChanged_ then onStateChanged_() end
        end),
    })

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 2,
        borderColor = C.accent_blue,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 5,
        children = cardChildren,
    }
end

-- ============================================================================
-- 目标国家卡片（发起远征入口）
-- ============================================================================

function ExpeditionPanel._BuildTargetCard(state, target)
    local isMajor = target.tier == "major"
    local tierLabel = isMajor and "列强" or "中小国"
    local tierColor = isMajor and C.accent_red or C.accent_amber

    local hpPct = target.max_hp > 0
        and (target.current_hp / target.max_hp) or 0
    local hpColor = hpPct > 0.5 and C.accent_green
        or (hpPct > 0.2 and C.accent_amber or C.accent_red)

    local fbBonus = Expedition.GetForwardBaseBonus(state, target.country_id)
    local diffMod = Expedition.GetConquestDifficultyMod(state)

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
                            text = target.label,
                            fontSize = F.body,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                            flexShrink = 1,
                        },
                        UI.Panel {
                            paddingHorizontal = 5,
                            paddingVertical = 1,
                            backgroundColor = { tierColor[1], tierColor[2], tierColor[3], 40 },
                            borderRadius = S.radius_badge,
                            children = {
                                UI.Label {
                                    text = tierLabel,
                                    fontSize = F.label,
                                    fontColor = tierColor,
                                },
                            },
                        },
                    },
                },
                -- 难度标签
                UI.Label {
                    text = string.format("难度 ×%.1f", diffMod),
                    fontSize = F.label,
                    fontColor = diffMod > 1.2 and C.accent_red or C.accent_green,
                },
            },
        },
        -- HP血条
        ExpeditionPanel._HPBar("军事HP", target.current_hp, target.max_hp, hpColor),
    }

    -- 大国政治HP
    if isMajor and target.political_hp and target.max_political_hp then
        local polPct = target.max_political_hp > 0
            and (target.political_hp / target.max_political_hp) or 0
        local polColor = polPct > 0.5 and { 100, 149, 237, 255 }
            or (polPct > 0.2 and C.accent_amber or C.accent_red)
        table.insert(cardChildren,
            ExpeditionPanel._HPBar("政治HP", target.political_hp, target.max_political_hp, polColor))
    end

    -- 详情行
    local infoItems = {}
    if fbBonus > 0 then
        table.insert(infoItems, string.format("前进基地 +%d%%", math.floor(fbBonus * 100)))
    end
    if #infoItems > 0 then
        table.insert(cardChildren, UI.Label {
            text = table.concat(infoItems, "  ·  "),
            fontSize = F.label,
            fontColor = C.text_muted,
        })
    end

    -- 发起远征按钮
    table.insert(cardChildren, UI.Button {
        text = string.format("发起远征 (%dAP + 兵×%d₿)", BE.expedition_ap_cost, BE.expedition_cost_per_soldier),
        fontSize = F.label,
        fontColor = C.text_primary,
        backgroundColor = { 180, 60, 60, 60 },
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.accent_red,
        paddingVertical = 6,
        width = "100%",
        onClick = Config.ClickGuard(function()
            ExpeditionPanel._ShowDeployDialog(state, target.country_id, "launch")
        end),
    })

    -- 支援按钮（仅对处于战争中的大国）
    if isMajor then
        local hasWar = false
        for _, front in ipairs(state.fronts or {}) do
            if front.attacker == target.country_id or front.defender == target.country_id then
                hasWar = true; break
            end
        end
        if hasWar then
            local canSupport = (state.ap.current + (state.ap.temp or 0)) >= BE.support_ap_cost
                and state.cash >= BE.support_cash_cost
            table.insert(cardChildren, UI.Button {
                text = string.format("支援作战 %dAP+%d₿",
                    BE.support_ap_cost, BE.support_cash_cost),
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
                    local ok, msg = Expedition.Support(state, target.country_id, nil)
                    if ok then
                        UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                    else
                        UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                    end
                    if onStateChanged_ then onStateChanged_() end
                end),
            })
        end
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
-- 部队部署对话框（发起远征 / 增援共用）
-- ============================================================================

function ExpeditionPanel._ShowDeployDialog(state, countryId, mode)
    -- mode = "launch" | "reinforce"
    local titleText = mode == "launch" and "发起远征 - 选择部署兵力" or "增援远征 - 选择增援兵力"
    local country = state.europe[countryId]
    local countryLabel = country and country.label or countryId

    -- 可用编队（不在其他远征中的）
    local availableSquads = {}
    for _, squad in ipairs(state.military.squads or {}) do
        if not squad.deployed_to then
            table.insert(availableSquads, squad)
        end
    end

    -- 选择状态（闭包内持久，刷新不丢失）
    local selectedSquads = {}  -- { [squadId] = true }

    local function _CalcCost()
        local soldiers = 0
        for sqId, _ in pairs(selectedSquads) do
            for _, sq in ipairs(availableSquads) do
                if sq.id == sqId then
                    soldiers = soldiers + (sq.size or 0)
                    break
                end
            end
        end
        local inflation = GameState.GetInflationFactor(state)
        return soldiers, math.floor(soldiers * BE.expedition_cost_per_soldier * inflation)
    end

    -- 对话框内容构建器 → 返回单个 ScrollView widget
    local function _BuildDialogScrollView()
        -- 计算可用内容高度（屏幕60%，减去 Modal 标题栏约 50px）
        local screenH = graphics:GetHeight() / graphics:GetDPR()
        local scrollH = math.floor(screenH * 0.6) - 50

        local dialogChildren = {
            UI.Label {
                text = string.format("目标: %s", countryLabel),
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = C.accent_red,
            },
        }

        -- 编队选择（3列紧凑方块）
        if #availableSquads > 0 then
            table.insert(dialogChildren, UI.Label {
                text = "选择编队:",
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            })
            local squadCards = {}
            for _, squad in ipairs(availableSquads) do
                local isSelected = selectedSquads[squad.id] == true
                local power = Equipment.CalcSquadPower(squad)
                -- 提取编队序号（如"精锐第1队"→"1"）
                local shortName = (squad.name or squad.id):match("%d+") or squad.id
                table.insert(squadCards, UI.Panel {
                    flexGrow = 1,
                    flexBasis = "30%",
                    minWidth = 80,
                    paddingVertical = 8,
                    paddingHorizontal = 4,
                    borderRadius = S.radius_btn,
                    borderWidth = 1,
                    borderColor = isSelected and C.accent_gold or C.border_soft,
                    backgroundColor = isSelected and { 212, 175, 55, 30 } or C.bg_surface,
                    alignItems = "center",
                    gap = 2,
                    onPointerUp = Config.TapGuard(function()
                        if selectedSquads[squad.id] then
                            selectedSquads[squad.id] = nil
                        else
                            selectedSquads[squad.id] = true
                        end
                        _RefreshContent()
                    end),
                    children = {
                        UI.Label {
                            text = isSelected and "✔" or "○",
                            fontSize = F.body,
                            fontColor = isSelected and C.accent_gold or C.text_muted,
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = "第" .. shortName .. "队",
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = isSelected and C.accent_gold or C.text_primary,
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = string.format("%d人 ⚔%.0f", squad.size or 0, power),
                            fontSize = F.label - 1,
                            fontColor = C.text_secondary,
                            pointerEvents = "none",
                        },
                    },
                })
            end
            table.insert(dialogChildren, UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 6,
                children = squadCards,
            })
        else
            table.insert(dialogChildren, UI.Label {
                text = "无可用编队",
                fontSize = F.label,
                fontColor = C.text_muted,
            })
        end

        -- 费用显示
        local soldiers, cost = _CalcCost()
        local apCost = mode == "launch" and BE.expedition_ap_cost or BE.expedition_reinforce_ap
        table.insert(dialogChildren, UI.Divider { color = C.divider })
        table.insert(dialogChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 4,
            children = {
                ExpeditionPanel._MetricCell("总兵力", tostring(soldiers), C.text_primary),
                ExpeditionPanel._MetricCell("费用", tostring(cost) .. "₿", C.accent_gold),
                ExpeditionPanel._MetricCell("AP", tostring(apCost), C.accent_amber),
            },
        })

        -- 难度提示（仅发起时）
        if mode == "launch" then
            local diffMod = Expedition.GetConquestDifficultyMod(state, countryId)
            local fwdBonus = Expedition.GetForwardBaseBonus(state, countryId)
            local hints = {}
            if diffMod ~= 1.0 then
                table.insert(hints, string.format("难度: ×%.2f", diffMod))
            end
            if fwdBonus > 0 then
                table.insert(hints, string.format("前哨加成: +%d%%", math.floor(fwdBonus * 100)))
            end
            if #hints > 0 then
                table.insert(dialogChildren, UI.Label {
                    text = table.concat(hints, "  |  "),
                    fontSize = F.label,
                    fontColor = C.text_muted,
                })
            end
        end

        -- 确认按钮
        local btnLabel
        if mode == "launch" then
            btnLabel = string.format("发起远征 %dAP + 兵×%d₿", apCost, BE.expedition_cost_per_soldier)
        else
            btnLabel = string.format("确认增援 %dAP + 兵×%d₿", apCost, BE.expedition_cost_per_soldier)
        end
        local canConfirm = soldiers > 0
            and state.ap.current >= apCost
            and state.cash >= cost
        table.insert(dialogChildren, UI.Button {
            text = canConfirm and btnLabel or
                (soldiers <= 0 and "请选择兵力" or "资源不足"),
            fontSize = F.body,
            fontWeight = "bold",
            fontColor = canConfirm and C.text_primary or C.text_muted,
            backgroundColor = canConfirm and { 180, 60, 60, 80 } or C.bg_surface,
            borderRadius = S.radius_btn,
            borderWidth = 1,
            borderColor = canConfirm and C.accent_red or C.border_soft,
            paddingVertical = 8,
            width = "100%",
            disabled = not canConfirm,
            onClick = Config.ClickGuard(function(self)
                self.props.disabled = true
                local sqIds = {}
                for sqId, _ in pairs(selectedSquads) do
                    table.insert(sqIds, sqId)
                end
                local ok, msg
                if mode == "launch" then
                    ok, msg = Expedition.LaunchExpedition(state, countryId, sqIds)
                else
                    ok, msg = Expedition.Reinforce(state, countryId, sqIds)
                end
                if ok then
                    UI.Toast.Show(msg, { variant = "success", duration = 2.5 })
                    if currentModal_ then currentModal_:Close() end
                else
                    UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
                end
                if onStateChanged_ then onStateChanged_() end
            end),
        })

        -- 固定高度 ScrollView（Modal 不约束子高度，必须显式设定）
        return UI.ScrollView {
            scrollY = true,
            width = "100%",
            height = scrollH,
            gap = 6,
            paddingHorizontal = 2,
            children = dialogChildren,
        }
    end

    -- 就地刷新弹窗内容（不销毁重建）
    function _RefreshContent()
        if not currentModal_ then return end
        currentModal_:ClearContent()
        currentModal_:AddContent(_BuildDialogScrollView())
    end

    -- 关闭已有弹窗
    if currentModal_ then currentModal_:Close() end

    currentModal_ = UI.Modal {
        title = titleText,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            currentModal_ = nil
            self:Destroy()
        end,
    }
    currentModal_:AddContent(_BuildDialogScrollView())
    currentModal_:Open()
end

-- ============================================================================
-- 撤退对话框
-- ============================================================================

function ExpeditionPanel._ShowWithdrawDialog(state, countryId)
    local record = (state.expeditions.active or {})[countryId]
    if not record then
        UI.Toast.Show("没有活跃的远征", { variant = "error", duration = 1.5 })
        return
    end

    local label = record.label or countryId
    local deployedSoldiers = Expedition.CalcDeployedSoldiers(state, record)

    -- 显示部署详情
    local deployDetails = {}
    for _, sqId in ipairs(record.deployed_squads or {}) do
        for _, squad in ipairs(state.military.squads or {}) do
            if squad.id == sqId then
                table.insert(deployDetails,
                    string.format("• %s（%d人）", squad.name or sqId, squad.size or 0))
                break
            end
        end
    end


    local dialogChildren = {
        UI.Label {
            text = string.format("从 %s 撤退", label),
            fontSize = F.body,
            fontWeight = "bold",
            fontColor = C.accent_amber,
        },
        UI.Label {
            text = string.format("全部撤退将取消远征，部署兵力（%d人）返回本土",
                deployedSoldiers),
            fontSize = F.body_minor,
            fontColor = C.text_secondary,
        },
    }

    if #deployDetails > 0 then
        table.insert(dialogChildren, UI.Label {
            text = "当前部署:",
            fontSize = F.label,
            fontColor = C.text_muted,
        })
        for _, detail in ipairs(deployDetails) do
            table.insert(dialogChildren, UI.Label {
                text = detail,
                fontSize = F.label,
                fontColor = C.text_secondary,
            })
        end
    end

    -- 全部撤退按钮
    local canWithdraw = state.ap.current >= BE.expedition_withdraw_ap
    table.insert(dialogChildren, UI.Divider { color = C.divider })
    table.insert(dialogChildren, UI.Button {
        text = string.format("全部撤退 (%dAP)", BE.expedition_withdraw_ap),
        fontSize = F.body,
        fontWeight = "bold",
        fontColor = canWithdraw and C.text_primary or C.text_muted,
        backgroundColor = canWithdraw and { 120, 100, 40, 60 } or C.bg_surface,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = canWithdraw and C.accent_amber or C.border_soft,
        paddingVertical = 8,
        width = "100%",
        disabled = not canWithdraw,
        onClick = Config.ClickGuard(function(self)
            self.props.disabled = true
            -- 全撤退：传入所有编队ID
            local sqIds = {}
            for _, sqId in ipairs(record.deployed_squads or {}) do
                table.insert(sqIds, sqId)
            end
            local ok, msg = Expedition.Withdraw(state, countryId, sqIds)
            if ok then
                UI.Toast.Show(msg, { variant = "success", duration = 2.0 })
                if currentModal_ then currentModal_:Close() end
            else
                UI.Toast.Show(msg, { variant = "error", duration = 2.0 })
            end
            if onStateChanged_ then onStateChanged_() end
        end),
    })

    -- 关闭已有弹窗
    if currentModal_ then currentModal_:Close() end

    currentModal_ = UI.Modal {
        title = "撤退确认",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            currentModal_ = nil
            self:Destroy()
        end,
    }
    currentModal_:AddContent(UI.ScrollView {
        scrollY = true,
        flexGrow = 1,
        flexBasis = 0,
        width = "100%",
        gap = 6,
        paddingHorizontal = 2,
        children = dialogChildren,
    })
    currentModal_:Open()
end

-- ============================================================================
-- 已占领国家卡片
-- ============================================================================

function ExpeditionPanel._BuildOccupiedCard(state, occ)
    local netIncome = (occ.income_per_turn or 0) - (occ.maintenance or 0)
    local netColor = netIncome >= 0 and C.accent_green or C.accent_red
    local sinceTurn = occ.since_turn or 0
    local heldTurns = (state.turn_count or 0) - sinceTurn

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = { C.accent_green[1], C.accent_green[2], C.accent_green[3], 60 },
        padding = S.card_padding,
        flexDirection = "column",
        gap = 4,
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
                        gap = 6,
                        children = {
                            UI.Label { text = "🏴", fontSize = F.body },
                            UI.Label {
                                text = occ.label or occ.country_id,
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                        },
                    },
                    UI.Label {
                        text = string.format("占领 %d 季", heldTurns),
                        fontSize = F.label,
                        fontColor = C.text_muted,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                children = {
                    ExpeditionPanel._MetricCell("季收入",
                        Config.FormatNumber(occ.income_per_turn or 0), C.accent_gold),
                    ExpeditionPanel._MetricCell("维护费",
                        Config.FormatNumber(occ.maintenance or 0), C.accent_amber),
                    ExpeditionPanel._MetricCell("净收益",
                        (netIncome >= 0 and "+" or "") .. Config.FormatNumber(netIncome), netColor),
                },
            },
        },
    }
end

-- _BuildHistoryCard 已移除，战绩已合并到概览卡片中

-- ============================================================================
-- HP 血条组件
-- ============================================================================

function ExpeditionPanel._HPBar(label, current, max, color)
    local pct = max > 0 and (current / max) or 0
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
                width = 50,
            },
            UI.ProgressBar {
                value = pct,
                flexGrow = 1,
                height = 6,
                borderRadius = 3,
                trackColor = C.bg_surface,
                fillColor = color,
            },
            UI.Label {
                text = string.format("%d/%d", current, max),
                fontSize = F.label,
                fontColor = C.text_secondary,
                width = 55,
                textAlign = "right",
            },
        },
    }
end

-- ============================================================================
-- 工具函数
-- ============================================================================

function ExpeditionPanel._MetricCell(label, value, color)
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

function ExpeditionPanel._SectionDivider(text, color)
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

function ExpeditionPanel._EmptyHint(text)
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

return ExpeditionPanel
