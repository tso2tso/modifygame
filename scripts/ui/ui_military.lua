-- ============================================================================
-- 武装页 UI：护矿队管理、战意、编队、装备、补给
-- 设计规范：sarajevo_dynasty_ui_spec §6.5
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local Combat = require("systems.combat")
local Equipment = require("systems.equipment")
local EquipmentData = require("data.equipment_data")
local EquipModals = require("ui.ui_equipment_modals")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE
local BMI = Balance.MILITARY
local CATALOG = EquipmentData.CATALOG
local SUPPORT_CATALOG = EquipmentData.SUPPORT_CATALOG

local MilitaryPage = {}

---@type table
local stateRef_ = nil
---@type function|nil
local onStateChanged_ = nil
local currentModal_ = nil
---@type number 弹窗关闭时间戳（防止手机端触摸穿透导致立即重新打开）
local modalCloseTime_ = 0
-- 键盘抑制已移至 Config.SuppressKeyboard()（全局时间制方案）

--- 创建武装页完整内容
---@param state table
---@param callbacks table
---@return table widget
function MilitaryPage.Create(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged
    return MilitaryPage._BuildContent(state)
end

function MilitaryPage._BuildContent(state)
    local mil = state.military or { morale = 50, squads = {}, inventory = {}, production_queue = {}, outsource_slots = {}, supply = 20 }
    local moraleColor = mil.morale >= 60 and C.accent_green
        or (mil.morale >= 40 and C.accent_amber or C.accent_red)
    local moraleText = mil.morale >= 80 and "高昂" or (mil.morale >= 60 and "稳定"
        or (mil.morale >= 40 and "低迷" or "崩溃"))

    -- 军务主管信息
    local chiefMember = GameState.GetMemberAtPosition(state, "military_chief")
    local chiefName = chiefMember and chiefMember.name or "空缺"
    local chiefColor = chiefMember and C.accent_green or C.accent_red
    local chiefBonus = GameState.GetPositionBonus(state, "military_chief")

    -- 战力计算
    local combatPower = math.floor(Combat.PlayerPower(state))

    -- 每季军费（与 economy.lua 保持一致：使用 hedgedInflation + supply_reduction_bonus）
    local inflation = GameState.GetInflationFactor(state)
    local BG = Balance.GOLD
    local goldHeld = state.gold or 0
    local goldHedgePct = math.min(BG.inflation_hedge_cap,
        math.floor(goldHeld / 10) * BG.inflation_hedge_per_10)
    local hedgedInflation = inflation * (1 - goldHedgePct)
    local quarterCost = math.floor(mil.guards * mil.wage * hedgedInflation)
    -- 装备维护费
    local equipMaint, factoryMaint = Equipment.CalcMaintenanceCost(state)
    local totalMaint = quarterCost + equipMaint + factoryMaint

    -- 招募费用
    local recruitCost = math.floor(BMI.recruit_cost * inflation
        * (1 - GameState.GetControlRecruitDiscount(state)))
    local moraleBoostCost = math.floor((BMI.morale_boost_cost_per_guard or 40)
        * (mil.guards or 0) * inflation)
    local moraleBoostAP = BMI.morale_boost_ap or 1
    local moraleBoostAmount = BMI.morale_boost_amount or 6

    -- 编队信息
    local squads = mil.squads or {}
    local assigned = Equipment.GetAssignedGuards(state)
    local unassigned = Equipment.GetUnassignedGuards(state)

    -- 工厂信息
    local factory = mil.factory
    local factoryLabel = "未建造"
    local factoryColor = C.text_muted
    if factory then
        if factory.building then
            factoryLabel = string.format("建造中 %d/%d 季", factory.building.progress, factory.building.total)
            factoryColor = C.accent_blue
        elseif factory.level and factory.level > 0 then
            factoryLabel = string.format("Lv%d 运行中", factory.level)
            factoryColor = C.accent_green
        end
    end

    -- 库存 / 生产队列
    local invCount = #(mil.inventory or {})
    local queueCount = #(mil.production_queue or {}) + #(mil.outsource_slots or {})

    local accent = Config.GetEraAccent(state)

    return UI.Panel {
        id = "militaryContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = {
            -- §6.5 总兵力大字 + 战意进度条
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = C.border_gold,
                flexDirection = "column",
                gap = 8,
                children = {
                    UI.Label {
                        text = "护矿队",
                        fontSize = F.card_title,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                    },
                    UI.Divider { color = C.divider },
                    -- §6.5 兵力数字 32px bold + 数据行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "flex-end",
                        children = {
                            -- 总兵力大字
                            UI.Panel {
                                flexDirection = "column",
                                gap = 2,
                                children = {
                                    UI.Label {
                                        text = tostring(mil.guards),
                                        fontSize = F.data_large,
                                        fontWeight = "bold",
                                        fontColor = C.text_primary,
                                    },
                                    UI.Label {
                                        text = "总兵力",
                                        fontSize = F.label,
                                        fontColor = C.text_muted,
                                    },
                                },
                            },
                            MilitaryPage._StatCol("战意", moraleText, moraleColor),
                            MilitaryPage._StatCol("战力", tostring(combatPower), C.accent_gold),
                            MilitaryPage._StatCol("军费/季", tostring(totalMaint), C.accent_red),
                        },
                    },
                    -- §6.5 战意进度条
                    UI.ProgressBar {
                        value = mil.morale / 100,
                        width = "100%",
                        height = 8,
                        borderRadius = 4,
                        trackColor = C.bg_surface,
                        fillColor = moraleColor,
                    },
                },
            },

            -- 编队概览卡片
            MilitaryPage._BuildSquadCard(state, squads, assigned, unassigned, accent),

            -- 兵工厂 & 库存卡片
            MilitaryPage._BuildFactoryCard(state, factoryLabel, factoryColor,
                invCount, queueCount, accent),

            -- 详细信息卡片
            UI.Panel {
                width = "100%",
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = C.border_card,
                padding = S.card_padding,
                flexDirection = "column",
                gap = 6,
                children = {
                    MilitaryPage._InfoRow("军务主管", chiefName, chiefColor),
                    MilitaryPage._InfoRow("主管加成", string.format("%+d%%", math.floor(chiefBonus * 100)),
                        chiefBonus >= 0 and C.accent_green or C.accent_red),
                    MilitaryPage._InfoRow("护卫工资", mil.wage .. " /人/季", C.text_primary),
                    MilitaryPage._InfoRow("装备维护", equipMaint > 0
                        and (equipMaint .. " /季") or "无", C.text_primary),
                    MilitaryPage._InfoRow("工厂维护", factoryMaint > 0
                        and (factoryMaint .. " /季") or "无", C.text_primary),
                    UI.Divider { color = C.divider },
                    UI.Label {
                        text = (state.flags and state.flags.at_war)
                            and "当前处于战争状态，战意每季自然衰减 " .. math.abs(BMI.morale_decay)
                            or "和平时期，战意每季自然衰减 " .. math.abs(BMI.morale_decay),
                        fontSize = F.label,
                        fontColor = (state.flags and state.flags.at_war) and C.accent_red or C.text_muted,
                        whiteSpace = "normal",
                    },
                    UI.Label {
                        text = string.format("可通过犒赏军心花费现金恢复战意（+%d）。",
                            moraleBoostAmount),
                        fontSize = F.label,
                        fontColor = C.text_muted,
                        whiteSpace = "normal",
                    },
                },
            },

            -- 操作按钮
            UI.Panel {
                width = "100%",
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = C.border_card,
                padding = S.card_padding,
                flexDirection = "column",
                gap = 8,
                children = {
                    UI.Label {
                        text = "军事操作",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = string.format("单价: %d₿/人 (⚡每1000人1AP)", recruitCost),
                        fontSize = F.label,
                        fontColor = C.text_muted,
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Button {
                                text = "招募护卫",
                                fontSize = F.body_minor,
                                height = S.btn_small_height,
                                flexGrow = 1,
                                flexBasis = 0,
                                variant = (state.cash >= recruitCost and (state.ap.current + (state.ap.temp or 0)) >= 1)
                                    and "primary" or "outlined",
                                disabled = state.cash < recruitCost or (state.ap.current + (state.ap.temp or 0)) < 1,
                                borderRadius = S.radius_btn,
                                onClick = Config.ClickGuard(function(self)
                                    MilitaryPage._ShowRecruitDialog()
                                end),
                            },
                            UI.Button {
                                text = "裁军",
                                fontSize = F.body_minor,
                                height = S.btn_small_height,
                                flexGrow = 1,
                                flexBasis = 0,
                                variant = "outlined",
                                disabled = unassigned < 1,
                                borderRadius = S.radius_btn,
                                onClick = Config.ClickGuard(function(self)
                                    MilitaryPage._ShowDisbandDialog()
                                end),
                            },
                        },
                    },
                    UI.Button {
                        text = string.format("犒赏军心 +%d (💰%d ⚡%d)",
                            moraleBoostAmount, moraleBoostCost, moraleBoostAP),
                        fontSize = F.body_minor,
                        height = S.btn_small_height,
                        width = "100%",
                        variant = (mil.morale < 100
                                and state.cash >= moraleBoostCost
                                and (state.ap.current + (state.ap.temp or 0)) >= moraleBoostAP)
                            and "primary" or "outlined",
                        disabled = mil.morale >= 100
                            or state.cash < moraleBoostCost
                            or (state.ap.current + (state.ap.temp or 0)) < moraleBoostAP,
                        borderRadius = S.radius_btn,
                        onClick = Config.ClickGuard(function(self)
                            self.props.disabled = true
                            MilitaryPage._OnBoostMorale()
                        end),
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 编队概览卡片
-- ============================================================================

function MilitaryPage._BuildSquadCard(state, squads, assigned, unassigned, accent)
    local children = {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "🛡️ 编队",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = string.format("%d 编队 | 编入 %d | 待编 %d",
                        #squads, assigned, unassigned),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
            },
        },
    }

    if #squads > 0 then
        table.insert(children, UI.Divider { color = C.divider })
        -- 每个编队一行摘要
        for _, sq in ipairs(squads) do
            local ed = CATALOG[sq.equip_id] or CATALOG.rifle
            local vet = EquipmentData.VETERANCY[sq.veterancy] or EquipmentData.VETERANCY[0]
            local power = math.floor(Equipment.CalcSquadPower(sq))
            local condColor = sq.condition >= 60 and C.accent_green
                or (sq.condition >= 30 and C.accent_amber or C.accent_red)

            table.insert(children, UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingTop = 2,
                paddingBottom = 2,
                children = {
                    -- 左侧：名称 + 装备
                    UI.Panel {
                        flexShrink = 1,
                        flexDirection = "row",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = sq.name,
                                fontSize = F.body_minor,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = string.format("%s%s", ed.icon, vet.name),
                                fontSize = F.label,
                                fontColor = sq.veterancy >= 3 and C.accent_gold or C.text_muted,
                            },
                            (function()
                                if sq.support_equip_id then
                                    local sd = SUPPORT_CATALOG[sq.support_equip_id]
                                    if sd then
                                        return UI.Label {
                                            text = sd.icon,
                                            fontSize = F.label,
                                            fontColor = {180, 160, 220, 255},
                                        }
                                    end
                                end
                                return nil
                            end)(),
                        },
                    },
                    -- 右侧：人数 + 耐久 + 战力
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = string.format("%d人", sq.size),
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                            UI.Label {
                                text = sq.condition .. "%",
                                fontSize = F.label,
                                fontColor = condColor,
                            },
                            UI.Label {
                                text = string.format("⚔%d", power),
                                fontSize = F.label,
                                fontWeight = "bold",
                                fontColor = C.accent_gold,
                            },
                        },
                    },
                },
            })
        end
    else
        table.insert(children, UI.Label {
            text = "暂无编队，编组护卫可提升战力。",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
            paddingTop = 4,
        })
    end

    -- 编队管理按钮
    table.insert(children, UI.Divider { color = C.divider })
    table.insert(children, UI.Panel {
        width = "100%",
        height = 34,
        borderRadius = S.radius_btn,
        backgroundColor = accent,
        justifyContent = "center",
        alignItems = "center",
        onPointerUp = Config.TapGuard(function()
            EquipModals.SetCallbacks(stateRef_, function()
                if onStateChanged_ then onStateChanged_() end
            end)
            EquipModals.ShowSquadManagement(stateRef_, accent)
        end),
        children = {
            UI.Label {
                text = "编队管理",
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
                pointerEvents = "none",
            },
        },
    })

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 6,
        children = children,
    }
end

-- ============================================================================
-- 兵工厂 & 库存卡片
-- ============================================================================

function MilitaryPage._BuildFactoryCard(state, factoryLabel, factoryColor,
    invCount, queueCount, accent)
    local children = {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "⚒️ 装备与生产",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
            },
        },
        UI.Divider { color = C.divider },
        MilitaryPage._InfoRow("兵工厂", factoryLabel, factoryColor),
        MilitaryPage._InfoRow("库存装备", invCount > 0
            and (invCount .. " 件") or "无", C.text_primary),
        MilitaryPage._InfoRow("生产中", queueCount > 0
            and (queueCount .. " 项") or "无",
            queueCount > 0 and C.accent_blue or C.text_muted),
    }

    -- 装备生产按钮
    table.insert(children, UI.Divider { color = C.divider })
    table.insert(children, UI.Panel {
        width = "100%",
        height = 34,
        borderRadius = S.radius_btn,
        backgroundColor = accent,
        justifyContent = "center",
        alignItems = "center",
        onPointerUp = Config.TapGuard(function()
            EquipModals.SetCallbacks(stateRef_, function()
                if onStateChanged_ then onStateChanged_() end
            end)
            EquipModals.ShowProduction(stateRef_, accent)
        end),
        children = {
            UI.Label {
                text = "装备生产与管理",
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
                pointerEvents = "none",
            },
        },
    })

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 6,
        children = children,
    }
end

-- ============================================================================
-- 辅助组件
-- ============================================================================

function MilitaryPage._StatCol(label, value, color)
    return UI.Panel {
        flexDirection = "column",
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = value,
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = color,
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_muted,
            },
        },
    }
end

function MilitaryPage._InfoRow(label, value, valueColor)
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

--- 招募护卫对话框
function MilitaryPage._ShowRecruitDialog()
    -- 安全网：强制隐藏系统键盘 & 清除残留焦点
    input:SetScreenKeyboardVisible(false)
    UI.ClearFocus()
    -- 防止手机端触摸穿透：弹窗刚关闭 0.3 秒内不再打开
    if time:GetElapsedTime() - modalCloseTime_ < 0.3 then return end
    if not stateRef_ then return end
    local state = stateRef_
    local inflation = GameState.GetInflationFactor(state)
    local unitCost = math.floor(BMI.recruit_cost * inflation
        * (1 - GameState.GetControlRecruitDiscount(state)))
    local maxAfford = unitCost > 0 and math.floor(state.cash / unitCost) or 0
    local inputVal = { text = "", count = 0 }

    local function _ParseCount(text)
        local n = tonumber(text)
        if not n then return 0 end
        n = math.floor(n)
        if n < 0 then return 0 end
        return math.min(n, maxAfford)
    end

    -- 预创建动态控件引用，避免 ClearContent/AddContent 重建
    local countLabel = UI.Label { text = "-", fontSize = F.body, fontWeight = "bold", fontColor = C.text_primary }
    local costLabel = UI.Label { text = "-", fontSize = F.body, fontWeight = "bold", fontColor = C.accent_gold }
    local apLabel = UI.Label { text = "-", fontSize = F.body, fontWeight = "bold", fontColor = C.accent_amber }
    local confirmBtn = UI.Button {
        text = "请输入数量",
        fontSize = F.body,
        fontWeight = "bold",
        fontColor = C.text_muted,
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.border_soft,
        paddingVertical = 8,
        width = "100%",
        disabled = true,
        onClick = Config.ClickGuard(function(self)
            self.props.disabled = true
            local cnt = inputVal.count
            if currentModal_ then currentModal_:Close() end
            MilitaryPage._OnRecruit(cnt)
        end),
    }

    local function _UpdateSummary()
        local count = inputVal.count
        local totalCost = count * unitCost
        local apCost = math.max(1, math.ceil(count / 1000))
        local canConfirm = count > 0
            and state.cash >= totalCost
            and (state.ap.current + (state.ap.temp or 0)) >= apCost

        countLabel.props.text = count > 0 and tostring(count) or "-"
        costLabel.props.text = count > 0 and (tostring(totalCost) .. "₿") or "-"
        apLabel.props.text = count > 0 and tostring(apCost) or "-"

        confirmBtn.props.disabled = not canConfirm
        confirmBtn.props.fontColor = canConfirm and C.text_primary or C.text_muted
        confirmBtn.props.backgroundColor = canConfirm and { 60, 120, 60, 80 } or C.bg_surface
        confirmBtn.props.borderColor = canConfirm and C.accent_green or C.border_soft
        if canConfirm then
            confirmBtn.props.text = string.format("确认招募 %d 人", count)
        elseif count <= 0 then
            confirmBtn.props.text = "请输入数量"
        elseif (state.ap.current + (state.ap.temp or 0)) < apCost then
            confirmBtn.props.text = "AP不足"
        else
            confirmBtn.props.text = "资金不足"
        end
    end

    local content = UI.Panel {
        width = "100%",
        gap = 8,
        children = {
            UI.Label {
                text = string.format("单价: %d₿/人（含通胀）| 每1000人消耗1AP", unitCost),
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            },
            UI.Label {
                text = string.format("最多可招: %d 人", maxAfford),
                fontSize = F.label,
                fontColor = C.text_muted,
            },
            UI.TextField {
                value = inputVal.text,
                placeholder = "输入招募人数",
                fontSize = F.body,
                width = "100%",
                height = 40,
                onChange = function(self, v)
                    inputVal.text = v
                    inputVal.count = _ParseCount(v)
                    _UpdateSummary()
                end,
                onSubmit = function(self, v)
                    inputVal.count = _ParseCount(v)
                    if inputVal.count > 0 then
                        local tc = inputVal.count * unitCost
                        local ac = math.max(1, math.ceil(inputVal.count / 1000))
                        if state.cash >= tc and (state.ap.current + (state.ap.temp or 0)) >= ac then
                            local cnt = inputVal.count
                            if currentModal_ then currentModal_:Close() end
                            MilitaryPage._OnRecruit(cnt)
                        end
                    end
                end,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                children = {
                    UI.Panel {
                        flexGrow = 1, flexBasis = 0, alignItems = "center",
                        children = {
                            countLabel,
                            UI.Label { text = "人数", fontSize = F.label, fontColor = C.text_muted },
                        },
                    },
                    UI.Panel {
                        flexGrow = 1, flexBasis = 0, alignItems = "center",
                        children = {
                            costLabel,
                            UI.Label { text = "总费用", fontSize = F.label, fontColor = C.text_muted },
                        },
                    },
                    UI.Panel {
                        flexGrow = 1, flexBasis = 0, alignItems = "center",
                        children = {
                            apLabel,
                            UI.Label { text = "AP", fontSize = F.label, fontColor = C.text_muted },
                        },
                    },
                },
            },
            confirmBtn,
        },
    }

    if currentModal_ then currentModal_:Close() end
    currentModal_ = UI.Modal {
        title = "招募护卫",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            Config.ConsumeTap()
            UI.ClearFocus()
            Config.SuppressKeyboard()
            modalCloseTime_ = time:GetElapsedTime()
            currentModal_ = nil
            self:Destroy()
        end,
    }
    currentModal_:AddContent(content)
    currentModal_:Open()
end

--- 裁军对话框
function MilitaryPage._ShowDisbandDialog()
    -- 安全网：强制隐藏系统键盘 & 清除残留焦点
    input:SetScreenKeyboardVisible(false)
    UI.ClearFocus()
    -- 防止手机端触摸穿透：弹窗刚关闭 0.3 秒内不再打开
    if time:GetElapsedTime() - modalCloseTime_ < 0.3 then return end
    if not stateRef_ then return end
    local state = stateRef_
    local unassigned = Equipment.GetUnassignedGuards(state)
    if unassigned <= 0 then
        UI.Toast.Show("没有可裁撤的未编队护卫", { variant = "error", duration = 1.5 })
        return
    end
    local inputVal = { text = "", count = 0 }

    local function _ParseCount(text)
        local n = tonumber(text)
        if not n then return 0 end
        n = math.floor(n)
        if n < 0 then return 0 end
        return math.min(n, unassigned)
    end

    -- 预创建动态控件引用
    local hintLabel = UI.Label {
        text = "请输入裁撤人数",
        fontSize = F.body,
        fontWeight = "bold",
        fontColor = C.text_muted,
        textAlign = "center",
        width = "100%",
    }
    local confirmBtn = UI.Button {
        text = "请输入数量",
        fontSize = F.body,
        fontWeight = "bold",
        fontColor = C.text_muted,
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = C.border_soft,
        paddingVertical = 8,
        width = "100%",
        disabled = true,
        onClick = Config.ClickGuard(function(self)
            self.props.disabled = true
            local cnt = inputVal.count
            if currentModal_ then currentModal_:Close() end
            MilitaryPage._OnDisband(cnt)
        end),
    }

    local function _UpdateSummary()
        local count = inputVal.count
        if count > 0 then
            hintLabel.props.text = string.format("裁撤 %d 人（战意 -3）", count)
            hintLabel.props.fontColor = C.accent_amber
            confirmBtn.props.text = string.format("确认裁军 %d 人", count)
            confirmBtn.props.fontColor = C.text_primary
            confirmBtn.props.backgroundColor = { 120, 80, 40, 60 }
            confirmBtn.props.borderColor = C.accent_amber
            confirmBtn.props.disabled = false
        else
            hintLabel.props.text = "请输入裁撤人数"
            hintLabel.props.fontColor = C.text_muted
            confirmBtn.props.text = "请输入数量"
            confirmBtn.props.fontColor = C.text_muted
            confirmBtn.props.backgroundColor = C.bg_surface
            confirmBtn.props.borderColor = C.border_soft
            confirmBtn.props.disabled = true
        end
    end

    local content = UI.Panel {
        width = "100%",
        gap = 8,
        children = {
            UI.Label {
                text = string.format("可裁撤未编队护卫: %d 人", unassigned),
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            },
            UI.TextField {
                value = inputVal.text,
                placeholder = "输入裁撤人数",
                fontSize = F.body,
                width = "100%",
                height = 40,
                onChange = function(self, v)
                    inputVal.text = v
                    inputVal.count = _ParseCount(v)
                    _UpdateSummary()
                end,
                onSubmit = function(self, v)
                    inputVal.count = _ParseCount(v)
                    if inputVal.count > 0 then
                        local cnt = inputVal.count
                        if currentModal_ then currentModal_:Close() end
                        MilitaryPage._OnDisband(cnt)
                    end
                end,
            },
            hintLabel,
            confirmBtn,
        },
    }

    if currentModal_ then currentModal_:Close() end
    currentModal_ = UI.Modal {
        title = "裁军",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            Config.ConsumeTap()
            UI.ClearFocus()
            Config.SuppressKeyboard()
            modalCloseTime_ = time:GetElapsedTime()
            currentModal_ = nil
            self:Destroy()
        end,
    }
    currentModal_:AddContent(content)
    currentModal_:Open()
end

--- 招募护卫
function MilitaryPage._OnRecruit(count)
    if not stateRef_ then return end
    local cost = math.floor(BMI.recruit_cost * GameState.GetInflationFactor(stateRef_)
        * (1 - GameState.GetControlRecruitDiscount(stateRef_))) * count
    local apCost = math.max(1, math.ceil(count / 1000))
    if stateRef_.cash < cost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 }); return
    end
    if not GameState.SpendAP(stateRef_, apCost) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 }); return
    end
    stateRef_.cash = stateRef_.cash - cost
    stateRef_.military.guards = stateRef_.military.guards + count
    GameState.AddLog(stateRef_, string.format("招募 %d 名护卫，花费 %d", count, cost))
    UI.Toast.Show(string.format("护卫 +%d", count), { variant = "success", duration = 1.5 })
    if onStateChanged_ then onStateChanged_() end
end

--- 裁军（只能裁撤未编队的护卫）
function MilitaryPage._OnDisband(count)
    if not stateRef_ then return end
    local unassigned = Equipment.GetUnassignedGuards(stateRef_)
    count = math.min(count, unassigned)
    if count <= 0 then
        UI.Toast.Show("没有可裁撤的未编队护卫", { variant = "error", duration = 1.5 })
        return
    end
    stateRef_.military.guards = stateRef_.military.guards - count
    stateRef_.military.morale = math.max(0, stateRef_.military.morale - 3)
    GameState.AddLog(stateRef_, string.format("裁撤 %d 名护卫", count))
    UI.Toast.Show(string.format("护卫 -%d", count), { variant = "warning", duration = 1.5 })
    if onStateChanged_ then onStateChanged_() end
end

--- 犒赏军心
function MilitaryPage._OnBoostMorale()
    if not stateRef_ then return end
    local amount = BMI.morale_boost_amount or 6
    local cost = math.floor((BMI.morale_boost_cost_per_guard or 40)
        * (stateRef_.military.guards or 0) * GameState.GetInflationFactor(stateRef_))
    local apCost = BMI.morale_boost_ap or 1

    if stateRef_.military.morale >= 100 then
        UI.Toast.Show("战意已满", { variant = "warning", duration = 1.5 })
        return
    end
    if stateRef_.cash < cost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 }); return
    end
    if not GameState.SpendAP(stateRef_, apCost) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 }); return
    end

    local before = stateRef_.military.morale
    stateRef_.cash = stateRef_.cash - cost
    stateRef_.military.morale = math.min(100, before + amount)
    local gained = stateRef_.military.morale - before
    GameState.AddLog(stateRef_, string.format("犒赏军心，花费 %d，战意 +%d", cost, gained))
    UI.Toast.Show(string.format("战意 +%d", gained), { variant = "success", duration = 1.5 })
    if onStateChanged_ then onStateChanged_() end
end

function MilitaryPage.Refresh(root, state)
    stateRef_ = state
end

return MilitaryPage
