-- ============================================================================
-- 势力子页 UI：从 ui_world.lua 提取
-- 大国档案、本地势力、控制度里程碑、合作度指示器
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local GrandPowers = require("systems.grand_powers")
local PlayerActionsGP = require("systems.player_actions_gp")
local EuropeData = require("data.europe_data")
local ActionModals = require("ui.ui_action_modals")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local FactionsPanel = {}

-- ============================================================================
-- 模块状态
-- ============================================================================

---@type table|nil
local stateRef_ = nil
---@type table|nil
local callbacksRef_ = nil

-- ── 势力页缓存：避免每次切 Tab 都重新计算 ──
---@type table|nil
local cachedPrecomputed_ = nil
---@type boolean
local precomputedDirty_ = true

-- 构建国家ID→中文名映射表
local _countryLabels = {}
if EuropeData.COUNTRIES then
    for _, c in ipairs(EuropeData.COUNTRIES) do
        if c.id and c.label then _countryLabels[c.id] = c.label end
    end
end

--- 将 AI 势力 ID 翻译为中文名称（优先从 state 取真实派系名）
local function _ResolveAIName(aiId, state)
    if state and state.ai_factions then
        for _, f in ipairs(state.ai_factions) do
            if f.id == aiId and f.name then return f.name end
        end
    end
    if aiId == "local_clan" then return "本地望族" end
    if aiId == "foreign_capital" then return "外国资本" end
    if aiId == "armed_group" then return "武装集团" end
    if _countryLabels[aiId] then return _countryLabels[aiId] end
    return aiId
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 标记势力预计算数据为脏（在 onStateChanged / 页面重建时调用）
function FactionsPanel.InvalidatePrecomputed()
    precomputedDirty_ = true
    cachedPrecomputed_ = nil
end

--- 新游戏/读档时重置
function FactionsPanel.Reset()
    cachedPrecomputed_ = nil
    precomputedDirty_ = true
    stateRef_ = nil
    callbacksRef_ = nil
end

--- 构建势力面板，返回 widget 供 tabContentPanel_ 添加
---@param state table
---@param callbacks table
---@return table widget
function FactionsPanel.Build(state, callbacks)
    stateRef_ = state
    callbacksRef_ = callbacks or {}

    -- 带缓存的预计算
    if precomputedDirty_ or not cachedPrecomputed_ then
        cachedPrecomputed_ = _PrecomputeFactionsData(state)
        precomputedDirty_ = false
    end
    local precomputed = cachedPrecomputed_

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

    -- ── 控制度里程碑 ──
    table.insert(widgets, _CreateControlMilestones(state, precomputed))

    -- ── 合作度指示器 ──
    table.insert(widgets, _CreateCollaborationHeader(state))

    -- ── 大国卡片 ──
    local activePowers = precomputed.activePowers
    if #activePowers > 0 then
        table.insert(widgets, _SectionDivider("欧洲列强", C.accent_gold))
        for _, power in ipairs(activePowers) do
            table.insert(widgets, _CreateGrandPowerCard(state, power, precomputed))
        end
    end

    -- ── 本地 AI 势力 ──
    if state.ai_factions and #state.ai_factions > 0 then
        table.insert(widgets, _SectionDivider("本地势力", C.text_secondary))
        for _, faction in ipairs(state.ai_factions) do
            table.insert(widgets, _CreateUnifiedFactionCard(state, faction, precomputed))
        end
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        paddingTop = S.card_gap,
        children = widgets,
    }
end

-- ============================================================================
-- 预计算
-- ============================================================================

--- 一次性预计算势力面板所需的所有遍历数据
---@param state table
---@return table precomputed
function _PrecomputeFactionsData(state)
    local result = {}

    -- 1. 活跃大国列表（排序后）
    result.activePowers = GrandPowers.GetActivePowers(state)

    -- 2. 批量计算所有大国的领土和前线
    result.territories = {}
    result.frontLines = {}

    if state.europe then
        for _, country in pairs(state.europe) do
            local sid = country.sovereign
            if sid then
                if not result.territories[sid] then
                    result.territories[sid] = {}
                end
                table.insert(result.territories[sid], country)
            end
        end
    end

    for _, power in ipairs(result.activePowers) do
        result.frontLines[power.id] = GrandPowers.GetFrontLines(state, power.id)
    end

    -- 3. 可用行动：懒加载
    result.actions = {}

    -- 3.5 缓存 CalcTotalControl
    result.totalControl = GameState.CalcTotalControl(state)

    -- 4. 本地势力：一次遍历 regions 建立 ai_presence 索引
    result.factionNodes = {}
    if state.regions then
        for _, r in ipairs(state.regions) do
            if r.ai_presence then
                for aiId, presence in pairs(r.ai_presence) do
                    if presence >= 30 then
                        if not result.factionNodes[aiId] then
                            result.factionNodes[aiId] = {}
                        end
                        table.insert(result.factionNodes[aiId],
                            r.name .. "(" .. presence .. "%)")
                    end
                end
            end
        end
    end

    -- 5. 本地势力：一次遍历 history_log，按 faction 分组最近记录
    result.factionLogs = {}
    if state.history_log and state.ai_factions then
        local neededCount = {}
        for _, f in ipairs(state.ai_factions) do
            neededCount[f.id] = 3
            result.factionLogs[f.id] = {}
        end
        local totalNeeded = #state.ai_factions * 3
        local scanned = 0
        for i = #state.history_log, 1, -1 do
            if totalNeeded <= 0 then break end
            scanned = scanned + 1
            if scanned > 50 then break end
            local entry = state.history_log[i]
            if entry.text then
                for _, f in ipairs(state.ai_factions) do
                    if neededCount[f.id] > 0 then
                        if (f.name and string.find(entry.text, f.name, 1, true))
                            or (f.id and string.find(entry.text, f.id, 1, true)) then
                            table.insert(result.factionLogs[f.id], entry)
                            neededCount[f.id] = neededCount[f.id] - 1
                            totalNeeded = totalNeeded - 1
                        end
                    end
                end
            end
        end
    end

    return result
end

-- ============================================================================
-- 段落分隔线
-- ============================================================================

function _SectionDivider(text, color)
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

local function _ControlBar(name, pct, color)
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
                width = 72,
                flexShrink = 0,
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
                text = string.format("%02d%%", pct),
                fontSize = F.label,
                fontColor = { color[1], color[2], color[3], 255 },
                width = 40,
                flexShrink = 0,
                textAlign = "right",
            },
        },
    }
end

-- ============================================================================
-- 控制度里程碑
-- ============================================================================

function _CreateControlMilestones(state, precomputed)
    local totalCtrl = (precomputed and precomputed.totalControl)
        or GameState.CalcTotalControl(state)
    local thresholds = Balance.CONTROL_MILESTONES.thresholds

    local reachedIdx = 0
    for i, t in ipairs(thresholds) do
        if totalCtrl >= t.min then reachedIdx = i end
    end
    local nextThreshold = thresholds[reachedIdx + 1]

    local progressValue = 0
    if nextThreshold then
        local prevMin = reachedIdx > 0 and thresholds[reachedIdx].min or 0
        local range = nextThreshold.min - prevMin
        if range > 0 then
            progressValue = math.min(1, (totalCtrl - prevMin) / range)
        end
    else
        progressValue = 1
    end

    local milestoneRows = {}
    for i, t in ipairs(thresholds) do
        local reached = totalCtrl >= t.min
        local isCurrent = (i == reachedIdx + 1)

        local icon = reached and "✅" or (isCurrent and "🔜" or "🔒")
        local labelColor = reached and C.accent_green
            or (isCurrent and C.accent_gold or C.text_muted)
        local valueColor = reached and C.accent_green or C.text_muted

        table.insert(milestoneRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            opacity = reached and 1.0 or 0.7,
            children = {
                UI.Label { text = icon, fontSize = 14, width = 20 },
                UI.Label {
                    text = t.label,
                    fontSize = F.body_minor,
                    fontWeight = reached and "bold" or "normal",
                    fontColor = labelColor,
                    width = 80,
                },
                UI.Label {
                    text = t.desc,
                    fontSize = F.label,
                    fontColor = valueColor,
                    flexGrow = 1,
                    flexShrink = 1,
                },
                UI.Label {
                    text = tostring(t.min),
                    fontSize = F.label,
                    fontColor = reached and C.accent_green or C.text_muted,
                    width = 30,
                    textAlign = "right",
                },
            },
        })
    end

    local nextHint = nextThreshold
        and string.format("下一目标：%s（还需 %d）", nextThreshold.label, nextThreshold.min - totalCtrl)
        or "已达成全部里程碑"

    local cardChildren = {
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
                        UI.Label { text = "🌐", fontSize = S.icon_size },
                        UI.Label {
                            text = "控制度里程碑",
                            fontSize = F.subtitle,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                        },
                    },
                },
                UI.Label {
                    text = "当前：" .. totalCtrl,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.accent_blue,
                },
            },
        },
        UI.ProgressBar {
            value = progressValue,
            width = "100%",
            height = 6,
            borderRadius = 3,
            trackColor = C.bg_surface,
            fillColor = C.accent_blue,
        },
        UI.Label {
            text = nextHint,
            fontSize = F.label,
            fontColor = C.text_muted,
        },
        UI.Divider { color = C.divider },
    }
    for _, row in ipairs(milestoneRows) do
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
        gap = 6,
        children = cardChildren,
    }
end

-- ============================================================================
-- 合作度指示器
-- ============================================================================

function _CreateCollaborationHeader(state)
    local score = state.collaboration_score or 0
    local label, labelColor = PlayerActionsGP.GetCollaborationLabel(score)

    local barValue = math.max(0, math.min(100, score + 50))
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

local FACTION_COLORS = {
    central   = { 160, 50, 20, 255 },
    entente   = { 58, 107, 138, 255 },
    axis      = { 140, 40, 40, 255 },
    allies    = { 74, 124, 89, 255 },
    neutral   = { 168, 152, 128, 255 },
    communist = { 192, 57, 43, 255 },
}

local FACTION_LABELS = {
    central   = "同盟国",
    entente   = "协约国",
    axis      = "轴心国",
    allies    = "盟军",
    neutral   = "中立",
    communist = "东方阵营",
}

local STANCE_META = {
    collaborate = { icon = "🤝", label = "合作", color = { 212, 129, 10, 255 } },
    join        = { icon = "⚔️",  label = "加入", color = { 192, 57, 43, 255 } },
    counter     = { icon = "🛡️", label = "制衡", color = { 58, 107, 138, 255 } },
    resist      = { icon = "🔥", label = "抵抗", color = { 74, 124, 89, 255 } },
}

function _CreateGrandPowerCard(state, power, precomputed)
    local attColor = power.attitude_to_player >= 10 and C.accent_green
        or (power.attitude_to_player >= -10 and C.accent_amber or C.accent_red)

    local attText = power.attitude_to_player >= 0
        and ("+" .. power.attitude_to_player) or tostring(power.attitude_to_player)

    local factionLabel = FACTION_LABELS[power.faction] or "未知"
    local factionColor = FACTION_COLORS[power.faction] or C.text_muted

    local territories = precomputed.territories[power.id] or {}
    local frontLines = precomputed.frontLines[power.id] or {}

    local statRows = {
        _ControlBar("军事", math.floor(power.military), C.accent_red),
        _ControlBar("经济", math.floor(power.economy), C.accent_gold),
        _ControlBar("厌战", math.floor(power.war_fatigue), C.accent_amber),
        _InfoRow("对我方态度", attText, attColor),
    }

    if #territories > 0 then
        local names = {}
        for i, t in ipairs(territories) do
            if i <= 4 then
                table.insert(names, t.label)
            end
        end
        local suffix = #territories > 4 and ("…等" .. #territories .. "国") or ""
        table.insert(statRows, _InfoRow(
            "控制领土", table.concat(names, "、") .. suffix, C.text_secondary))
    end

    if #frontLines > 0 then
        local targets = {}
        for _, fl in ipairs(frontLines) do
            if fl.status == "active" then
                table.insert(targets, "→" .. fl.target_label)
            end
        end
        if #targets > 0 then
            table.insert(statRows, _InfoRow(
                "前线", table.concat(targets, " "), C.accent_red))
        end
    end

    -- ── 行动按钮区域（懒加载） ──
    local actionContainer = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 0,
    }

    local actionsExpanded = false

    local expandBtn = UI.Button {
        text = "📋 查看行动",
        fontSize = F.body_minor,
        fontColor = C.accent_gold,
        backgroundColor = { 0, 0, 0, 0 },
        paddingVertical = 6,
        alignSelf = "center",
        textAlign = "center",
        onClick = Config.ClickGuard(function(self)
            if actionsExpanded then
                actionsExpanded = false
                self:SetText("📋 查看行动")
                actionContainer:ClearChildren()
                return
            end

            actionsExpanded = true
            self:SetText("📋 收起行动")

            if not PlayerActionsGP.IsUnlocked(state) then
                actionContainer:AddChild(UI.Panel {
                    width = "100%",
                    padding = S.card_padding,
                    children = {
                        UI.Label {
                            text = "🔒 大国外交行动（未解锁）",
                            fontSize = F.label,
                            fontColor = C.text_muted,
                        },
                        UI.Label {
                            text = "获得「情报网络」称号后解锁外交行动（总控制度≥20）",
                            fontSize = F.body_minor,
                            fontColor = C.text_muted,
                        },
                    },
                })
                return
            end

            local actions = PlayerActionsGP.GetAvailableActions(state, power.id)
            local stanceOrder = { "collaborate", "join", "counter", "resist" }
            local actionWidgets = {}

            for _, stanceId in ipairs(stanceOrder) do
                local group = actions[stanceId]
                if group and #group > 0 then
                    local meta = STANCE_META[stanceId]
                    local btnRow = {}
                    for _, act in ipairs(group) do
                        -- 家族天赋：巧舌如簧 — 外交 AP 折扣
                        local _diploReduce = GameState.GetActiveTraitEffect and GameState.GetActiveTraitEffect(state, "diplomacy_ap_reduction") or 0
                        local _effAP = math.max(0, act.ap_cost - _diploReduce)
                        local enabled = act.available and (state.ap.current + (state.ap.temp or 0)) >= _effAP
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
                            onClick = Config.ClickGuard(function(btn)
                                btn.props.disabled = true
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
                            end),
                        })
                    end

                    table.insert(actionWidgets, UI.Panel {
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

            if #actionWidgets > 0 then
                actionContainer:AddChild(_BuildActionSection(state, actionWidgets))
            else
                actionContainer:AddChild(UI.Label {
                    text = "暂无可用行动",
                    fontSize = F.label,
                    fontColor = C.text_muted,
                    padding = S.card_padding,
                })
            end
        end),
    }

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
            -- 分隔线 + 展开按钮
            UI.Divider { color = C.divider },
            expandBtn,
            -- 行动区容器（懒加载后填充）
            actionContainer,
        },
    }
end

--- 行动区段
function _BuildActionSection(state, actionChildren)
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

-- ============================================================================
-- 本地势力卡片
-- ============================================================================

function _CreateUnifiedFactionCard(state, faction, precomputed)
    if faction.defeated then
        return UI.Panel {
            width = "100%",
            padding = S.card_padding,
            backgroundColor = { 35, 35, 38, 255 },
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = { 95, 95, 95, 255 },
            flexDirection = "column",
            gap = 6,
            opacity = 0.78,
            children = {
                UI.Label {
                    text = (faction.icon or "×") .. " " .. faction.name .. "（已击败）",
                    fontSize = F.card_title,
                    fontWeight = "bold",
                    fontColor = C.text_muted,
                },
                UI.Label {
                    text = "该势力已失去主要地盘和行动能力，相关模块转入玩家或地方代理控制。",
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                    whiteSpace = "normal",
                    lineHeight = 1.4,
                },
            },
        }
    end

    -- ── 瘫痪状态 ──
    if faction.collapsed then
        local colCfg = Balance.COLLAPSE or (Balance.AI and Balance.AI.collapse)
            or { recovery_seasons = 6 }
        local remaining = math.max(0,
            (colCfg.recovery_seasons or 6) - (faction.collapsed_seasons or 0))
        return UI.Panel {
            width = "100%",
            backgroundColor = { 40, 40, 45, 255 },
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = { 80, 80, 80, 255 },
            flexDirection = "column",
            overflow = "hidden",
            opacity = 0.75,
            children = {
                UI.Panel {
                    width = "100%",
                    padding = S.card_padding,
                    backgroundColor = { 50, 50, 55, 255 },
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Label {
                            text = "💀",
                            fontSize = S.icon_size,
                        },
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
                                            text = faction.name,
                                            fontSize = F.card_title,
                                            fontWeight = "bold",
                                            fontColor = { 160, 160, 160, 255 },
                                        },
                                        UI.Panel {
                                            paddingHorizontal = 6,
                                            paddingVertical = 2,
                                            backgroundColor = { 180, 50, 50, 60 },
                                            borderRadius = S.radius_badge,
                                            children = {
                                                UI.Label {
                                                    text = "已瘫痪",
                                                    fontSize = F.label,
                                                    fontWeight = "bold",
                                                    fontColor = C.accent_red,
                                                },
                                            },
                                        },
                                    },
                                },
                                UI.Label {
                                    text = faction.desc or "",
                                    fontSize = F.label,
                                    fontColor = { 120, 120, 120, 255 },
                                    whiteSpace = "normal",
                                    lineHeight = 1.3,
                                },
                            },
                        },
                    },
                },
                UI.Panel {
                    width = "100%",
                    padding = S.card_padding,
                    flexDirection = "column",
                    gap = 6,
                    children = {
                        UI.Label {
                            text = "势力已崩溃，组织结构瓦解",
                            fontSize = F.body_minor,
                            fontColor = { 160, 120, 100, 255 },
                            whiteSpace = "normal",
                        },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            justifyContent = "space-between",
                            children = {
                                _InfoRow("残余势力",
                                    tostring(faction.power or 0), { 160, 160, 160, 255 }),
                                _InfoRow("残余资金",
                                    tostring(faction.cash or 0), { 160, 160, 160, 255 }),
                            },
                        },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                UI.Label {
                                    text = "⏳",
                                    fontSize = 14,
                                },
                                UI.Label {
                                    text = remaining > 0
                                        and string.format("预计 %d 季后可能重组", remaining)
                                        or "即将恢复活动",
                                    fontSize = F.label,
                                    fontColor = C.accent_amber,
                                },
                            },
                        },
                        UI.Label {
                            text = "📉 控制区域正在收缩，地区存在度持续下降",
                            fontSize = F.label,
                            fontColor = { 140, 140, 140, 255 },
                            whiteSpace = "normal",
                        },
                    },
                },
            },
        }
    end

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

    local normalizedAtt = (att + 100) / 200
    local barColor = att >= 0 and C.accent_green or C.accent_red

    local statRows = {}

    local controlledNodes = precomputed.factionNodes[faction.id] or {}
    if #controlledNodes > 0 then
        table.insert(statRows, _InfoRow("控制区域",
            table.concat(controlledNodes, "、"), C.accent_amber))
    end

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
    table.insert(statRows, _InfoRow("行动倾向", focusText, focusColor))

    local recentLogs = precomputed.factionLogs[faction.id] or {}

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
            -- 头部
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
            -- 外交关系
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
            -- 属性区
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
                        onClick = Config.ClickGuard(function()
                            local accent = Config.GetEraAccent(stateRef_)
                            ActionModals.ShowDiplomacy(stateRef_, accent)
                        end),
                    },
                },
            },
        },
    }
end

return FactionsPanel
