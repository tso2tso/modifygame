-- ============================================================================
-- 武装页 UI：护矿队管理、士气、装备、补给
-- 设计规范：sarajevo_dynasty_ui_spec §6.5
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local Combat = require("systems.combat")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE
local BMI = Balance.MILITARY

local MilitaryPage = {}

---@type table
local stateRef_ = nil
---@type function|nil
local onStateChanged_ = nil

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
    local mil = state.military
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

    -- 每季军费
    local inflation = GameState.GetInflationFactor(state)
    local quarterCost = math.floor(mil.guards * mil.wage * inflation
        + mil.guards * BMI.supply_per_guard * BMI.supply_cost * inflation)

    -- 招募费用
    local recruitCost = math.floor(BMI.recruit_cost * inflation
        * (1 - GameState.GetInfluenceRecruitDiscount(state)))

    return UI.Panel {
        id = "militaryContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = {
            -- §6.5 总兵力大字 + 士气进度条
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
                            MilitaryPage._StatCol("士气", moraleText, moraleColor),
                            MilitaryPage._StatCol("战力", tostring(combatPower), C.accent_gold),
                            MilitaryPage._StatCol("军费/季", tostring(quarterCost), C.accent_red),
                        },
                    },
                    -- §6.5 士气进度条
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
                    MilitaryPage._InfoRow("装备等级", mil.equipment .. "/5", C.text_primary),
                    MilitaryPage._InfoRow("补给储备", mil.supply .. " 单位", C.text_primary),
                    UI.Divider { color = C.divider },
                    UI.Label {
                        text = state.flags.at_war and "当前处于战争状态，士气衰减加速"
                            or "和平时期，士气每季自然衰减 " .. math.abs(BMI.morale_decay),
                        fontSize = F.label,
                        fontColor = state.flags.at_war and C.accent_red or C.text_muted,
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
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            UI.Button {
                                text = string.format("招募 +3 (💰%d ⚡1)", recruitCost * 3),
                                fontSize = F.body_minor,
                                height = S.btn_small_height,
                                flexGrow = 1,
                                flexBasis = 0,
                                variant = (state.cash >= recruitCost * 3 and state.ap.current >= 1)
                                    and "primary" or "outlined",
                                disabled = state.cash < recruitCost * 3 or state.ap.current < 1,
                                borderRadius = S.radius_btn,
                                onClick = function(self)
                                    MilitaryPage._OnRecruit(3)
                                end,
                            },
                            UI.Button {
                                text = "裁军 -3",
                                fontSize = F.body_minor,
                                height = S.btn_small_height,
                                flexGrow = 1,
                                flexBasis = 0,
                                variant = "outlined",
                                disabled = mil.guards < 3,
                                borderRadius = S.radius_btn,
                                onClick = function(self)
                                    MilitaryPage._OnDisband(3)
                                end,
                            },
                        },
                    },
                    -- 补给按钮
                    UI.Button {
                        text = string.format("补充补给 +20 (💰%d ⚡1)", 20 * BMI.supply_cost),
                        fontSize = F.body_minor,
                        height = S.btn_small_height,
                        width = "100%",
                        variant = (state.cash >= 20 * BMI.supply_cost and state.ap.current >= 1)
                            and "primary" or "outlined",
                        disabled = state.cash < 20 * BMI.supply_cost or state.ap.current < 1,
                        borderRadius = S.radius_btn,
                        onClick = function(self)
                            MilitaryPage._OnResupply(20)
                        end,
                    },
                },
            },
        },
    }
end

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

--- 招募护卫
function MilitaryPage._OnRecruit(count)
    if not stateRef_ then return end
    local cost = math.floor(BMI.recruit_cost * GameState.GetInflationFactor(stateRef_)
        * (1 - GameState.GetInfluenceRecruitDiscount(stateRef_))) * count
    if stateRef_.cash < cost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 }); return
    end
    if not GameState.SpendAP(stateRef_, 1) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 }); return
    end
    stateRef_.cash = stateRef_.cash - cost
    stateRef_.military.guards = stateRef_.military.guards + count
    GameState.AddLog(stateRef_, string.format("招募 %d 名护卫，花费 %d", count, cost))
    UI.Toast.Show(string.format("护卫 +%d", count), { variant = "success", duration = 1.5 })
    if onStateChanged_ then onStateChanged_() end
end

--- 裁军
function MilitaryPage._OnDisband(count)
    if not stateRef_ then return end
    count = math.min(count, stateRef_.military.guards)
    if count <= 0 then return end
    stateRef_.military.guards = stateRef_.military.guards - count
    stateRef_.military.morale = math.max(0, stateRef_.military.morale - 3)
    GameState.AddLog(stateRef_, string.format("裁撤 %d 名护卫", count))
    UI.Toast.Show(string.format("护卫 -%d", count), { variant = "warning", duration = 1.5 })
    if onStateChanged_ then onStateChanged_() end
end

--- 补充补给
function MilitaryPage._OnResupply(amount)
    if not stateRef_ then return end
    local cost = math.floor(amount * BMI.supply_cost * GameState.GetInflationFactor(stateRef_))
    if stateRef_.cash < cost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 }); return
    end
    if not GameState.SpendAP(stateRef_, 1) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 }); return
    end
    stateRef_.cash = stateRef_.cash - cost
    stateRef_.military.supply = stateRef_.military.supply + amount
    GameState.AddLog(stateRef_, string.format("补充补给 %d，花费 %d", amount, cost))
    UI.Toast.Show(string.format("补给 +%d", amount), { variant = "success", duration = 1.5 })
    if onStateChanged_ then onStateChanged_() end
end

function MilitaryPage.Refresh(root, state)
    stateRef_ = state
end

return MilitaryPage
