-- ============================================================================
-- 家族页 UI：按岗位分块布局 + 候选人弹窗 + 待命成员区域
-- 设计规范：sarajevo_dynasty_ui_spec §6.2 (v2 — 岗位优先布局)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local FamiliesData = require("data.families_data")
local Balance = require("data.balance")
local SaveLoad = require("utils.save_load")
local AudioManager = require("systems.audio_manager")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local FamilyPage = {}

---@type table 游戏状态引用
local stateRef_ = nil
---@type function|nil 状态变化回调
local onStateChanged_ = nil
---@type table|nil UI 根节点引用（Modal 需要）
local uiRoot_ = nil
---@type table|nil 当前打开的弹窗
local currentModal_ = nil
---@type table|nil 重随子弹窗
local rerollModal_ = nil

-- ============================================================================
-- 天赋/缺陷/学位 Chip 生成工具
-- ============================================================================

--- 为成员生成天赋 Chip（绿色）
function FamilyPage._TraitChip(member)
    if not member.trait then return nil end
    local def = FamiliesData.GetTraitDef(member.trait)
    if not def then return nil end
    return UI.Chip {
        label = def.icon .. " " .. def.name,
        color = "success",
        variant = "soft",
        size = "sm",
    }
end

--- 为成员生成缺陷 Chip（红色）
function FamilyPage._FlawChip(member)
    if not member.flaw then return nil end
    local def = FamiliesData.GetFlawDef(member.flaw)
    if not def then return nil end
    return UI.Chip {
        label = def.icon .. " " .. def.name,
        color = "error",
        variant = "soft",
        size = "sm",
    }
end

--- 为成员生成学位 Chips（蓝色数组）
function FamilyPage._DegreeChips(member)
    if not member.degrees or #member.degrees == 0 then return {} end
    local chips = {}
    for _, degId in ipairs(member.degrees) do
        local def = FamiliesData.GetDegreeDef(degId)
        if def then
            table.insert(chips, UI.Chip {
                label = def.icon .. " " .. def.name,
                color = "primary",
                variant = "soft",
                size = "sm",
            })
        end
    end
    return chips
end

--- 检查成员是否正在大学进修
function FamilyPage._IsStudying(state, memberId)
    if not state.family.university then return false, nil end
    for _, u in ipairs(state.family.university) do
        if u.member_id == memberId then
            return true, u
        end
    end
    return false, nil
end

-- 属性条颜色映射
local ATTR_COLORS = {
    management = C.accent_blue,
    strategy   = C.accent_red,
    charisma   = C.accent_gold,
    knowledge  = C.accent_green,
    ambition   = C.accent_amber,
}

-- 属性显示顺序
local ATTR_ORDER = { "management", "strategy", "charisma", "knowledge", "ambition" }

-- 岗位适配标签
local FIT_LABELS = {
    excellent = "满配",
    good      = "半配",
    poor      = "差配",
}
local FIT_CHIP_COLORS = {
    excellent = "success",
    good      = "warning",
    poor      = "error",
}

local TRAIT_CHIP_COLORS = {
    ["可靠"]     = "success",
    ["清廉"]     = "success",
    ["稳健"]     = "default",
    ["易动摇"]   = "warning",
    ["灰色倾向"] = "warning",
    ["激进"]     = "error",
}

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 设置 UI 根节点（Modal 必须 AddChild 到 UI 树才能渲染）
function FamilyPage.SetRoot(root)
    uiRoot_ = root
end

--- 创建家族页完整内容
---@param state table
---@param callbacks table { onStateChanged = function }
---@return table widget
function FamilyPage.Create(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged
    return FamilyPage._BuildContent(state)
end

--- 刷新家族页
function FamilyPage.Refresh(root, state)
    stateRef_ = state
end

-- ============================================================================
-- 页面构建
-- ============================================================================

function FamilyPage._BuildContent(state)
    local children = {}

    -- 1) 家族概况卡片
    table.insert(children, FamilyPage._CreateSummaryCard(state))

    -- 2) 岗位网格（2列布局）
    table.insert(children, FamilyPage._CreatePositionGrid(state))

    -- 3) 待命成员区域
    table.insert(children, FamilyPage._CreateIdleSection(state))

    return UI.Panel {
        id = "familyContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = children,
    }
end

-- ============================================================================
-- 家族概况卡片
-- ============================================================================

function FamilyPage._CreateSummaryCard(state)
    local activeCount = 0
    local assignedCount = 0
    for _, m in ipairs(state.family.members) do
        if m.status == "active" then activeCount = activeCount + 1 end
        if m.position then assignedCount = assignedCount + 1 end
    end

    return UI.Panel {
        id = "familySummary",
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
                text = "科瓦奇家族",
                fontSize = F.card_title,
                fontWeight = "bold",
                fontColor = C.accent_gold,
            },
            UI.Divider { color = C.divider },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 12,
                children = {
                    FamilyPage._StatItem("成员", string.format("%d/%d", activeCount, Balance.FAMILY.max_members)),
                    FamilyPage._StatItem("在岗", string.format("%d/%d", assignedCount, #Config.POSITIONS)),
                    FamilyPage._StatItem("空缺", tostring(#Config.POSITIONS - assignedCount)),
                    UI.Panel { flexGrow = 1 },  -- 弹性间隔
                    (function()
                        local memberCount = #state.family.members
                        local trainCost = Balance.FAMILY.train_cost
                        for _, tier in ipairs(Balance.FAMILY.train_cost_tiers or {}) do
                            if memberCount < tier.max_count then
                                trainCost = tier.cost
                                break
                            end
                            trainCost = tier.cost
                        end
                        local portraitAvailable = false
                        for i = 1, #FamiliesData.PORTRAIT_POOL do
                            if not FamiliesData.IsPoolPortraitUsed(i) then
                                portraitAvailable = true
                                break
                            end
                        end
                        local atMax = memberCount >= Balance.FAMILY.max_members
                        local btnText
                        if state.family.training then
                            btnText = string.format("培养中 %d/%d",
                                state.family.training.progress or 0,
                                state.family.training.total or 0)
                        elseif atMax then
                            btnText = "已达上限"
                        elseif not portraitAvailable then
                            btnText = "立绘已用尽"
                        else
                            btnText = string.format("培养新成员(💰%d)", trainCost)
                        end
                        return UI.Button {
                            text = btnText,
                            fontSize = F.body_minor,
                            fontColor = C.text_primary,
                            backgroundColor = state.family.training and C.bg_elevated or C.paper_mid,
                            borderRadius = S.radius_btn,
                            paddingHorizontal = 10,
                            paddingVertical = 6,
                            disabled = state.family.training ~= nil or atMax or not portraitAvailable,
                            onClick = Config.ClickGuard(function()
                                local ok, msg = GameState.StartFamilyTraining(state)
                                if ok then AudioManager.PlayEffect("family_train") end
                                UI.Toast.Show(msg, { variant = ok and "success" or "warning", duration = 1.8 })
                                if ok and onStateChanged_ then onStateChanged_() end
                            end),
                        }
                    end)(),
                },
            },
            -- 大学入口（科技解锁后显示）
            GameState.IsUniversityUnlocked(state) and UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = "🎓 萨拉热窝大学",
                        fontSize = F.body,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Button {
                        text = string.format("进修（💰%d）", math.floor((Balance.FAMILY.university_cost or 300) * GameState.GetInflationFactor(state))),
                        fontSize = F.body_minor,
                        variant = "outlined",
                        size = "sm",
                        onClick = Config.ClickGuard(function()
                            FamilyPage._ShowUniversityModal(state)
                        end),
                    },
                },
            } or nil,
            UI.Label {
                text = "分配家族成员到岗位可获得对应方向经营加成，上岗需适应2季度",
                fontSize = F.body_minor,
                fontColor = C.text_muted,
                whiteSpace = "normal",
                lineHeight = 1.4,
            },
        },
    }
end

function FamilyPage._StatItem(label, value)
    return UI.Panel {
        flexDirection = "column",
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = value,
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_muted,
            },
        },
    }
end

-- ============================================================================
-- 岗位网格（2列 × 3行）
-- ============================================================================

function FamilyPage._CreatePositionGrid(state)
    local cards = {}
    for _, pos in ipairs(Config.POSITIONS) do
        table.insert(cards, FamilyPage._CreatePositionCard(state, pos))
    end

    -- 两列布局：每行两个岗位卡
    local rows = {}
    for i = 1, #cards, 2 do
        local rowChildren = { cards[i] }
        if cards[i + 1] then
            table.insert(rowChildren, cards[i + 1])
        end
        table.insert(rows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = S.card_gap,
            children = rowChildren,
        })
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = rows,
    }
end

--- 创建单个岗位卡片
function FamilyPage._CreatePositionCard(state, pos)
    -- 查找当前任职者
    local occupant = nil
    for _, m in ipairs(state.family.members) do
        if m.position == pos.id then
            occupant = m
            break
        end
    end

    local attr1Name = Config.ATTR_NAMES[pos.attr1] or pos.attr1
    local attr2Name = Config.ATTR_NAMES[pos.attr2] or pos.attr2

    local cardChildren = {}

    -- 岗位名称 + 关键属性标签
    table.insert(cardChildren, UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 2,
        children = {
            UI.Label {
                text = pos.name,
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.accent_gold,
            },
            UI.Label {
                text = attr1Name .. " · " .. attr2Name,
                fontSize = F.label,
                fontColor = C.text_muted,
            },
        },
    })

    if occupant then
        -- 有人在岗：展示任职者简要信息
        local rating, bonus = FamiliesData.GetPositionFit(occupant, pos.attr1, pos.attr2)
        local fitLabel = FIT_LABELS[rating] or ""
        local fitColor = FIT_CHIP_COLORS[rating] or "default"

        -- 适应期状态
        local onboarding = (occupant.onboarding_remaining or 0) > 0
        local statusChips = {}
        table.insert(statusChips, UI.Chip {
            label = fitLabel,
            color = fitColor,
            variant = "soft",
            size = "sm",
        })
        if onboarding then
            table.insert(statusChips, UI.Chip {
                label = "适应中 " .. occupant.onboarding_remaining .. "季",
                color = "warning",
                variant = "outlined",
                size = "sm",
            })
        end
        -- 天赋/缺陷标签
        local tc = FamilyPage._TraitChip(occupant)
        if tc then table.insert(statusChips, tc) end
        local fc = FamilyPage._FlawChip(occupant)
        if fc then table.insert(statusChips, fc) end

        -- 立绘 + 信息 横向布局
        local portraitWidget
        if occupant.portraitImage then
            portraitWidget = UI.Panel {
                width = 48,
                height = 96,
                borderRadius = S.radius_badge,
                backgroundImage = occupant.portraitImage,
                backgroundFit = "cover",
                borderWidth = 1,
                borderColor = C.border_card,
                flexShrink = 0,
            }
        else
            portraitWidget = UI.Avatar {
                name = occupant.name,
                initials = occupant.portrait,
                size = 40,
                shape = "rounded",
                backgroundColor = C.paper_mid,
                showBorder = true,
                borderColor = C.border_card,
            }
        end

        -- 关键属性紧凑显示（只显示岗位关键的两个属性）
        local attr1Val = (occupant.attrs and occupant.attrs[pos.attr1]) or 0
        local attr2Val = (occupant.attrs and occupant.attrs[pos.attr2]) or 0
        local attrLine = string.format("%s %s  %s %s",
            attr1Name, FamilyPage._DotRatingShort(attr1Val),
            attr2Name, FamilyPage._DotRatingShort(attr2Val))

        table.insert(cardChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "flex-start",
            gap = 8,
            children = {
                portraitWidget,
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    gap = 3,
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                UI.Label {
                                    text = occupant.name,
                                    fontSize = F.body,
                                    fontWeight = "bold",
                                    fontColor = C.text_primary,
                                },
                                occupant.age and UI.Label {
                                    text = tostring(occupant.age) .. "岁",
                                    fontSize = F.label,
                                    fontColor = (occupant.age >= (Balance.FAMILY.retirement_warning_age or 55))
                                        and C.accent_red or C.text_muted,
                                } or nil,
                            },
                        },
                        UI.Panel {
                            flexDirection = "row",
                            gap = 4,
                            flexWrap = "wrap",
                            children = statusChips,
                        },
                        UI.Label {
                            text = attrLine,
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                        },
                    },
                },
            },
        })

        -- 加成预览：按岗位实际系数显示
        local effectBonus = bonus
        local posEffectCoeff = ({
            mine_director   = 0.5,   -- 产出 ×(1+bonus×0.5)
            military_chief  = 0.4,   -- 战力 ×(1+bonus×0.4)
            tech_advisor    = 0.3,   -- 周期 ×(1-bonus×0.3) → 显示为正值加速
            civil_director  = 0.2,   -- 税率 ×(1-bonus×0.2) → 显示为正值减税
            culture_advisor = 0.5,   -- 控制度 ×(1+bonus×0.5)
            diplomat        = 0.5,   -- 好感 +delta×bonus×0.5
        })[pos.id] or 1.0
        local actualPct = math.floor(bonus * posEffectCoeff * 100)
        local displayPct = actualPct
        if onboarding then
            displayPct = math.floor(bonus * (Balance.FAMILY.onboarding_bonus_ratio or 0.3) * posEffectCoeff * 100)
        end
        local posEffectLabel = ({
            mine_director   = "产出",
            military_chief  = "战力",
            tech_advisor    = "研发加速",
            civil_director  = "减税",
            culture_advisor = "控制度",
            diplomat        = "好感加成",
        })[pos.id] or "加成"
        local signChar = (pos.id == "civil_director" or pos.id == "tech_advisor") and "-" or "+"
        local bonusText = string.format("%s %s%d%%", posEffectLabel, signChar, math.abs(displayPct))
        if onboarding then
            bonusText = bonusText .. string.format(" (适应后 %s%d%%)", signChar, math.abs(actualPct))
        end
        -- 满配独有标记
        if rating == "excellent" then
            local excellentLabel = ({
                mine_director   = " | 矿脉洞察",
                military_chief  = " | 精锐操练 +3战意/季",
                tech_advisor    = " | 学术权威 费用-20%",
                civil_director  = " | 内政洞察",
                culture_advisor = " | 文化感召 免疫衰减",
                diplomat        = " | 外交密件 +3好感/次",
            })[pos.id] or ""
            bonusText = bonusText .. excellentLabel
        end
        table.insert(cardChildren, UI.Label {
            text = bonusText,
            fontSize = F.label,
            fontColor = onboarding and C.text_muted or (bonus > 0 and C.success or C.danger),
        })

        -- 操作按钮行
        table.insert(cardChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 6,
            children = {
                UI.Button {
                    text = "详情",
                    fontSize = F.label,
                    variant = "outlined",
                    size = "sm",
                    flexGrow = 1,
                    onClick = Config.ClickGuard(function()
                        FamilyPage._ShowMemberDetail(occupant)
                    end),
                },
                UI.Button {
                    text = "更换",
                    fontSize = F.label,
                    variant = "outlined",
                    size = "sm",
                    flexGrow = 1,
                    onClick = Config.ClickGuard(function()
                        FamilyPage._ShowCandidateModal(pos)
                    end),
                },
                UI.Button {
                    text = "撤下",
                    fontSize = F.label,
                    variant = "text",
                    size = "sm",
                    fontColor = C.danger,
                    onClick = Config.ClickGuard(function()
                        FamilyPage._DoUnassign(occupant.id, pos)
                    end),
                },
            },
        })
    else
        -- 空缺：展示虚位以待
        table.insert(cardChildren, UI.Panel {
            width = "100%",
            height = 48,
            justifyContent = "center",
            alignItems = "center",
            borderWidth = 1,
            borderColor = C.divider,
            borderRadius = S.radius_badge,
            borderStyle = "dashed",
            children = {
                UI.Label {
                    text = "空缺",
                    fontSize = F.body,
                    fontColor = C.text_muted,
                },
            },
        })

        table.insert(cardChildren, UI.Button {
            text = "分配成员",
            fontSize = F.body_minor,
            variant = "primary",
            size = "sm",
            width = "100%",
            onClick = Config.ClickGuard(function()
                FamilyPage._ShowCandidateModal(pos)
            end),
        })
    end

    return UI.Panel {
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = "45%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = occupant and C.border_card or C.divider,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 6,
        children = cardChildren,
    }
end

-- ============================================================================
-- 待命成员区域
-- ============================================================================

function FamilyPage._CreateIdleSection(state)
    local idleMembers = {}
    local cooldownMembers = {}
    for _, m in ipairs(state.family.members) do
        if not m.position and m.status == "active" then
            if (m.cooldown_turns or 0) > 0 then
                table.insert(cooldownMembers, m)
            else
                table.insert(idleMembers, m)
            end
        end
    end

    -- 包含失能成员
    local disabledMembers = {}
    for _, m in ipairs(state.family.members) do
        if m.status == "disabled" then
            table.insert(disabledMembers, m)
        end
    end

    local children = {
        UI.Label {
            text = "待命成员",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        },
    }

    if #idleMembers == 0 and #cooldownMembers == 0 and #disabledMembers == 0 then
        table.insert(children, UI.Label {
            text = "所有成员均已在岗",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
        })
    else
        for _, m in ipairs(idleMembers) do
            table.insert(children, FamilyPage._CreateIdleMemberRow(m, false))
        end
        for _, m in ipairs(cooldownMembers) do
            table.insert(children, FamilyPage._CreateIdleMemberRow(m, false, true))
        end
        for _, m in ipairs(disabledMembers) do
            table.insert(children, FamilyPage._CreateIdleMemberRow(m, true))
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
        gap = 8,
        children = children,
    }
end



--- 创建待命成员行
function FamilyPage._CreateIdleMemberRow(member, isDisabled, isCooldown)
    -- 天赋/缺陷/学位 chips
    local traitChips = {}
    local tc = FamilyPage._TraitChip(member)
    if tc then table.insert(traitChips, tc) end
    local fc = FamilyPage._FlawChip(member)
    if fc then table.insert(traitChips, fc) end
    for _, dc in ipairs(FamilyPage._DegreeChips(member)) do
        table.insert(traitChips, dc)
    end
    -- 进修状态
    local studying, studyInfo = FamilyPage._IsStudying(stateRef_, member.id)

    local statusLabel, statusColor
    if studying and studyInfo then
        local deg = FamiliesData.GetDegreeDef(studyInfo.degree_id)
        statusLabel = "进修中 " .. (studyInfo.progress or 0) .. "/" .. (studyInfo.total or 4)
        if deg then statusLabel = deg.icon .. " " .. statusLabel end
        statusColor = "primary"
    elseif isDisabled then
        statusLabel = "失能 " .. (member.disabled_turns or 0) .. "回合"
        statusColor = "error"
    elseif isCooldown then
        statusLabel = "冷却中 " .. (member.cooldown_turns or 0) .. "回合"
        statusColor = "warning"
    else
        statusLabel = "待命"
        statusColor = "default"
    end

    -- 立绘或 Avatar
    local portraitWidget
    if member.portraitImage then
        portraitWidget = UI.Panel {
            width = 36,
            height = 72,
            borderRadius = S.radius_badge,
            backgroundImage = member.portraitImage,
            backgroundFit = "cover",
            borderWidth = 1,
            borderColor = C.border_card,
            flexShrink = 0,
            imageTint = isDisabled and { 120, 120, 120, 255 } or nil,
        }
    else
        portraitWidget = UI.Avatar {
            name = member.name,
            initials = member.portrait,
            size = 28,
            shape = "rounded",
            backgroundColor = isDisabled and C.bg_elevated or C.paper_mid,
            showBorder = true,
            borderColor = C.border_card,
        }
    end

    -- 紧凑属性行：显示全部5个属性的数值
    local attrParts = {}
    for _, key in ipairs(ATTR_ORDER) do
        local val = (member.attrs and member.attrs[key]) or 0
        local shortName = Config.ATTR_NAMES[key] or key
        table.insert(attrParts, shortName .. tostring(val))
    end
    local attrLine = table.concat(attrParts, " ")

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "flex-start",
        gap = 8,
        paddingVertical = 4,
        children = {
            portraitWidget,
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
                                text = member.name,
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = isDisabled and C.text_muted or C.text_primary,
                            },
                            member.age and UI.Label {
                                text = tostring(member.age) .. "岁",
                                fontSize = F.label,
                                fontColor = (member.age >= (Balance.FAMILY.retirement_warning_age or 55))
                                    and C.accent_red or C.text_muted,
                            } or nil,
                            UI.Chip {
                                label = statusLabel,
                                color = statusColor,
                                variant = isDisabled and "soft" or "outlined",
                                size = "sm",
                            },
                        },
                    },
                    UI.Label {
                        text = attrLine,
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                    },
                    #traitChips > 0 and UI.Panel {
                        flexDirection = "row",
                        gap = 4,
                        children = traitChips,
                    } or nil,
                },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 4,
                flexShrink = 0,
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "详情",
                        fontSize = F.label,
                        variant = "outlined",
                        size = "sm",
                        onClick = Config.ClickGuard(function()
                            FamilyPage._ShowMemberDetail(member)
                        end),
                    },
                    (member.reroll_available or 0) > 0 and UI.Button {
                        text = "🎰 重随",
                        fontSize = F.label,
                        variant = "primary",
                        size = "sm",
                        onClick = Config.ClickGuard(function()
                            FamilyPage._ShowRerollModal(member)
                        end),
                    } or nil,
                },
            },
        },
    }
end

-- ============================================================================
-- 候选人选择弹窗
-- ============================================================================

function FamilyPage._ShowCandidateModal(pos)
    FamilyPage._CloseModal()
    if not stateRef_ then return end

    local attr1Name = Config.ATTR_NAMES[pos.attr1] or pos.attr1
    local attr2Name = Config.ATTR_NAMES[pos.attr2] or pos.attr2

    -- 筛选可用候选人：活跃且未在其他岗位上
    local candidates = {}
    for _, m in ipairs(stateRef_.family.members) do
        if m.status == "active" and m.position ~= pos.id and (m.cooldown_turns or 0) <= 0 then
            table.insert(candidates, m)
        end
    end

    -- 按适配度排序：excellent > good > poor
    local fitOrder = { excellent = 1, good = 2, poor = 3 }
    table.sort(candidates, function(a, b)
        local rA = FamiliesData.GetPositionFit(a, pos.attr1, pos.attr2)
        local rB = FamiliesData.GetPositionFit(b, pos.attr1, pos.attr2)
        return (fitOrder[rA] or 9) < (fitOrder[rB] or 9)
    end)

    local rows = {}
    if #candidates == 0 then
        table.insert(rows, UI.Label {
            text = "没有可用的候选人",
            fontSize = F.body,
            fontColor = C.text_muted,
            paddingVertical = 16,
            textAlign = "center",
            width = "100%",
        })
    else
        for _, m in ipairs(candidates) do
            table.insert(rows, FamilyPage._CreateCandidateRow(m, pos))
        end
    end

    local content = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 8,
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        children = {
            UI.Label {
                text = "关键属性：" .. attr1Name .. " · " .. attr2Name,
                fontSize = F.body,
                fontColor = C.text_muted,
                paddingBottom = 4,
            },
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                flexBasis = 0,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 8,
                        children = rows,
                    },
                },
            },
        },
    }

    currentModal_ = UI.Modal {
        title = "选择 " .. pos.name,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        onClose = function()
            Config.ConsumeTap()
            currentModal_ = nil
        end,
    }
    currentModal_:AddContent(content)
    if uiRoot_ then
        uiRoot_:AddChild(currentModal_)
    end
    currentModal_:Open()
end

--- 创建候选人行
function FamilyPage._CreateCandidateRow(member, pos)
    local rating, bonus = FamiliesData.GetPositionFit(member, pos.attr1, pos.attr2)
    local fitLabel = FIT_LABELS[rating] or ""
    local fitColor = FIT_CHIP_COLORS[rating] or "default"

    local attr1Val = (member.attrs and member.attrs[pos.attr1]) or 0
    local attr2Val = (member.attrs and member.attrs[pos.attr2]) or 0

    -- 如果该成员当前在别的岗位上，标注需要先撤下
    local fromOtherPos = member.position ~= nil
    local otherPosName = nil
    if fromOtherPos then
        for _, p in ipairs(Config.POSITIONS) do
            if p.id == member.position then otherPosName = p.name; break end
        end
    end

    -- 立绘或 Avatar
    local candidatePortrait
    if member.portraitImage then
        candidatePortrait = UI.Panel {
            width = 48,
            height = 80,
            borderRadius = S.radius_badge,
            backgroundImage = member.portraitImage,
            backgroundFit = "cover",
            borderWidth = 1,
            borderColor = C.border_card,
            flexShrink = 0,
        }
    else
        candidatePortrait = UI.Avatar {
            name = member.name,
            initials = member.portrait,
            size = 28,
            shape = "rounded",
            backgroundColor = C.paper_mid,
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        paddingVertical = 6,
        paddingHorizontal = 4,
        borderRadius = S.radius_badge,
        backgroundColor = C.paper_dark,
        children = {
            candidatePortrait,
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
                                text = member.name,
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            member.age and UI.Label {
                                text = tostring(member.age) .. "岁",
                                fontSize = F.label,
                                fontColor = (member.age >= (Balance.FAMILY.retirement_warning_age or 55))
                                    and C.accent_red or C.text_muted,
                            } or nil,
                            UI.Chip {
                                label = fitLabel,
                                color = fitColor,
                                variant = "soft",
                                size = "sm",
                            },
                        },
                    },
                    UI.Label {
                        text = string.format("%s %d · %s %d → %+d%%",
                            Config.ATTR_NAMES[pos.attr1] or "", attr1Val,
                            Config.ATTR_NAMES[pos.attr2] or "", attr2Val,
                            math.floor(bonus * 100)),
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 4,
                        flexWrap = "wrap",
                        children = {
                            FamilyPage._TraitChip(member),
                            FamilyPage._FlawChip(member),
                            table.unpack(FamilyPage._DegreeChips(member)),
                        },
                    },
                    fromOtherPos and UI.Label {
                        text = "当前在岗：" .. (otherPosName or ""),
                        fontSize = F.label,
                        fontColor = C.accent_amber,
                    } or nil,
                },
            },
            UI.Button {
                text = "任命",
                fontSize = F.label,
                variant = "primary",
                size = "sm",
                onClick = Config.ClickGuard(function()
                    FamilyPage._DoAssign(member.id, pos)
                end),
            },
        },
    }
end

-- ============================================================================
-- 成员详情弹窗
-- ============================================================================

function FamilyPage._ShowMemberDetail(member)
    FamilyPage._CloseModal()

    local isHead = (member.id == "patriarch")

    -- 属性横向条形图（带颜色进度条）
    local attrRows = {}
    for _, attrKey in ipairs(ATTR_ORDER) do
        local val = (member.attrs and member.attrs[attrKey]) or 0
        local attrName = Config.ATTR_NAMES[attrKey] or attrKey
        local color = ATTR_COLORS[attrKey] or C.text_primary
        local pct = math.min(val * 10, 100)  -- 10分制 → 百分比

        table.insert(attrRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            paddingVertical = 2,
            children = {
                -- 属性名
                UI.Label {
                    text = attrName,
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                    width = 30,
                    textAlign = "right",
                },
                -- 进度条背景
                UI.Panel {
                    flexGrow = 1,
                    height = 10,
                    backgroundColor = C.bg_elevated,
                    borderRadius = 5,
                    overflow = "hidden",
                    children = {
                        -- 进度条填充
                        UI.Panel {
                            width = tostring(pct) .. "%",
                            height = "100%",
                            backgroundColor = color,
                            borderRadius = 5,
                        },
                    },
                },
                -- 数值
                UI.Label {
                    text = tostring(val),
                    fontSize = F.body_minor,
                    fontWeight = "bold",
                    fontColor = color,
                    width = 18,
                    textAlign = "right",
                },
            },
        })
    end

    -- 隐藏特性
    local traitChips = {}
    for _, hint in ipairs(FamiliesData.GetHiddenTraitHints(member)) do
        table.insert(traitChips, UI.Chip {
            label = hint,
            color = TRAIT_CHIP_COLORS[hint] or "default",
            variant = "soft",
            size = "sm",
        })
    end

    -- 适应期状态
    local onboardingInfo = nil
    if member.position and (member.onboarding_remaining or 0) > 0 then
        onboardingInfo = UI.Panel {
            width = "100%",
            paddingVertical = 6,
            paddingHorizontal = 10,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_badge,
            children = {
                UI.Label {
                    text = string.format("适应中，剩余 %d 季度（当前仅 %d%% 加成）",
                        member.onboarding_remaining,
                        math.floor((Balance.FAMILY.onboarding_bonus_ratio or 0.3) * 100)),
                    fontSize = F.body_minor,
                    fontColor = C.accent_amber,
                    whiteSpace = "normal",
                },
            },
        }
    end

    -- ================================================================
    -- 构建内容：立绘大图 + 底部渐变叠加名字信息
    -- ================================================================
    local contentChildren = {}

    if member.portraitImage then
        -- 立绘区域：cover 裁切，展示上半身（约 2/3），高度 360px
        -- 名字/身份/特性叠加在立绘底部（渐变遮罩）
        local ageText = member.age and (tostring(member.age) .. "岁") or nil
        local ageNearRetire = member.age and member.age >= (Balance.FAMILY.retirement_warning_age or 55)
        local overlayChildren = {
            UI.Label {
                text = member.name,
                fontSize = F.super_title,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                flexWrap = "wrap",
                children = {
                    UI.Label {
                        text = member.title,
                        fontSize = F.body,
                        fontColor = C.text_secondary,
                    },
                    ageText and UI.Label {
                        text = ageText,
                        fontSize = F.body,
                        fontColor = ageNearRetire and C.accent_red or C.text_muted,
                    } or nil,
                    table.unpack(traitChips),
                },
            },
        }

        table.insert(contentChildren, UI.Panel {
            width = "100%",
            height = 560,
            borderRadius = S.radius_card,
            overflow = "hidden",
            borderWidth = 1,
            borderColor = isHead and C.accent_gold or C.border_card,
            children = {
                -- 立绘背景层：超高面板迫使 cover 按高度缩放，图片从顶部铺满
                UI.Panel {
                    width = "100%",
                    height = 1000,
                    backgroundImage = member.portraitImage,
                    backgroundFit = "cover",
                },
                -- 底部渐变遮罩 + 名字信息
                UI.Panel {
                    position = "absolute",
                    bottom = 0,
                    left = 0,
                    right = 0,
                    paddingTop = 48,
                    paddingBottom = 12,
                    paddingHorizontal = 14,
                    flexDirection = "column",
                    gap = 4,
                    backgroundGradient = {
                        direction = "to-bottom",
                        colors = {
                            { color = { 26, 24, 20, 0 },   stop = 0 },
                            { color = { 26, 24, 20, 200 }, stop = 50 },
                            { color = { 26, 24, 20, 240 }, stop = 100 },
                        },
                    },
                    children = overlayChildren,
                },
            },
        })
    else
        -- 无立绘：Avatar + 名字横排
        table.insert(contentChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 12,
            paddingVertical = 8,
            children = {
                UI.Avatar {
                    name = member.name,
                    initials = member.portrait,
                    size = 56,
                    shape = "rounded",
                    backgroundColor = C.paper_mid,
                    showBorder = true,
                    borderColor = isHead and C.accent_gold or C.border_card,
                },
                UI.Panel {
                    flexGrow = 1,
                    flexDirection = "column",
                    gap = 2,
                    children = {
                        UI.Label {
                            text = member.name,
                            fontSize = F.card_title,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                        },
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                UI.Label {
                                    text = member.title,
                                    fontSize = F.body,
                                    fontColor = C.text_secondary,
                                },
                                member.age and UI.Label {
                                    text = tostring(member.age) .. "岁",
                                    fontSize = F.body,
                                    fontColor = (member.age >= (Balance.FAMILY.retirement_warning_age or 55))
                                        and C.accent_red or C.text_muted,
                                } or nil,
                                table.unpack(traitChips),
                            },
                        },
                    },
                },
            },
        })
    end

    -- 2) 适应期
    if onboardingInfo then
        table.insert(contentChildren, onboardingInfo)
    end

    -- 3) 能力值 — 紧凑条形图
    table.insert(contentChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        paddingTop = 6,
        children = {
            UI.Label {
                text = "能力值",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_secondary,
            },
        },
    })
    table.insert(contentChildren, UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 1,
        children = attrRows,
    })

    -- 3.5) 天赋 / 缺陷 / 学位
    do
        local traitFlawDegreeChildren = {}

        -- 天赋
        if member.trait then
            local tDef = FamiliesData.GetTraitDef(member.trait)
            if tDef then
                table.insert(traitFlawDegreeChildren, UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Chip {
                            label = tDef.icon .. " " .. tDef.name,
                            color = "success",
                            variant = "soft",
                            size = "sm",
                        },
                        UI.Label {
                            text = tDef.effect_desc,
                            fontSize = F.body_minor,
                            fontColor = C.accent_green,
                            flexShrink = 1,
                        },
                    },
                })
            end
        end

        -- 缺陷
        if member.flaw then
            local fDef = FamiliesData.GetFlawDef(member.flaw)
            if fDef then
                table.insert(traitFlawDegreeChildren, UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Chip {
                            label = fDef.icon .. " " .. fDef.name,
                            color = "error",
                            variant = "soft",
                            size = "sm",
                        },
                        UI.Label {
                            text = fDef.effect_desc,
                            fontSize = F.body_minor,
                            fontColor = C.accent_red,
                            flexShrink = 1,
                        },
                    },
                })
            end
        end

        -- 学位
        if member.degrees and #member.degrees > 0 then
            for _, degId in ipairs(member.degrees) do
                local dDef = FamiliesData.GetDegreeDef(degId)
                if dDef then
                    table.insert(traitFlawDegreeChildren, UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        children = {
                            UI.Chip {
                                label = dDef.icon .. " " .. dDef.name,
                                color = "primary",
                                variant = "soft",
                                size = "sm",
                            },
                            UI.Label {
                                text = dDef.effect_desc,
                                fontSize = F.body_minor,
                                fontColor = C.accent_blue or C.text_secondary,
                                flexShrink = 1,
                            },
                        },
                    })
                end
            end
        end

        -- 进修中状态
        if stateRef_ then
            local studying, studyInfo = FamilyPage._IsStudying(stateRef_, member.id)
            if studying and studyInfo then
                local sDef = FamiliesData.GetDegreeDef(studyInfo.degree_id)
                local sLabel = string.format("进修中 %d/%d 季",
                    studyInfo.progress or 0, studyInfo.total or 4)
                if sDef then sLabel = sDef.icon .. " " .. sDef.name .. " — " .. sLabel end
                table.insert(traitFlawDegreeChildren, UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Chip {
                            label = "📖 进修中",
                            color = "info",
                            variant = "soft",
                            size = "sm",
                        },
                        UI.Label {
                            text = sLabel,
                            fontSize = F.body_minor,
                            fontColor = C.text_secondary,
                            flexShrink = 1,
                        },
                    },
                })
            end
        end

        if #traitFlawDegreeChildren > 0 then
            table.insert(contentChildren, UI.Divider { color = C.divider })
            table.insert(contentChildren, UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = "特质与学位",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_secondary,
                    },
                },
            })
            table.insert(contentChildren, UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 4,
                children = traitFlawDegreeChildren,
            })
        end
    end

    -- 4) 内政洞察：满配内政总监时显示隐藏属性数值
    if stateRef_ and GameState.CanRevealHiddenAttrs(stateRef_) then
        local hiddenDefs = {
            { key = "loyalty",    name = "忠诚", low = 4, high = 8,
              colorLow = C.danger, colorHigh = C.accent_green },
            { key = "corruption", name = "腐化", low = 3, high = 7,
              colorLow = C.accent_green, colorHigh = C.danger },
            { key = "radical",    name = "激进", low = 3, high = 7,
              colorLow = C.accent_green, colorHigh = C.accent_amber },
        }
        local hiddenRows = {}
        for _, def in ipairs(hiddenDefs) do
            local val = FamiliesData.GetHiddenValue(member, def.key)
            local barColor = val >= def.high and def.colorHigh
                or val <= def.low and def.colorLow
                or C.text_secondary
            table.insert(hiddenRows, UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = def.name,
                        fontSize = F.body_minor,
                        fontColor = C.text_muted,
                        width = 32,
                    },
                    UI.ProgressBar {
                        value = val * 10,
                        height = 10,
                        flexGrow = 1,
                        backgroundColor = C.bg_elevated,
                        color = barColor,
                        borderRadius = 3,
                    },
                    UI.Label {
                        text = tostring(val),
                        fontSize = F.body_minor,
                        fontWeight = "bold",
                        fontColor = barColor,
                        width = 18,
                        textAlign = "right",
                    },
                },
            })
        end
        table.insert(contentChildren, UI.Divider { color = C.divider })
        table.insert(contentChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = "内政洞察",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.accent_amber,
                },
                UI.Label {
                    text = "(内政总监满配)",
                    fontSize = F.label,
                    fontColor = C.text_muted,
                },
            },
        })
        table.insert(contentChildren, UI.Panel {
            width = "100%",
            flexDirection = "column",
            gap = 1,
            children = hiddenRows,
        })
    end

    -- 5) 简介
    if member.bio and member.bio ~= "" then
        table.insert(contentChildren, UI.Divider { color = C.divider })
        table.insert(contentChildren, UI.Label {
            text = member.bio,
            fontSize = F.body_minor,
            fontColor = C.text_muted,
            whiteSpace = "normal",
            lineHeight = 1.4,
        })
    end

    -- 6) 重随属性按钮 → 点击弹出子弹窗
    if (member.reroll_available or 0) > 0 then
        table.insert(contentChildren, UI.Divider { color = C.divider })
        table.insert(contentChildren, UI.Button {
            text = "🎲 重随属性（" .. member.reroll_available .. " 次）",
            variant = "outlined",
            size = "md",
            width = "100%",
            onClick = Config.ClickGuard(function()
                FamilyPage._ShowRerollModal(member)
            end),
        })
    end

    local content = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                paddingBottom = 12,
                children = contentChildren,
            },
        },
    }

    currentModal_ = UI.Modal {
        title = member.name,
        size = "fullscreen",
        closeOnOverlay = true,
        closeOnEscape = true,
        contentPadding = { 0, 12, 12, 12 },
        onClose = function()
            Config.ConsumeTap()
            currentModal_ = nil
        end,
    }
    currentModal_:AddContent(content)
    if uiRoot_ then
        uiRoot_:AddChild(currentModal_)
    end
    currentModal_:Open()
end

-- ============================================================================
-- 操作处理
-- ============================================================================

--- 任命成员到岗位
function FamilyPage._DoAssign(memberId, pos)
    if not stateRef_ then return end

    local success = GameState.AssignPosition(stateRef_, memberId, pos.id)
    if success then
        stateRef_.ap.max = GameState.CalcMaxAP(stateRef_)
        stateRef_.ap.current = math.min(stateRef_.ap.current, stateRef_.ap.max)

        local memberName = memberId
        for _, m in ipairs(stateRef_.family.members) do
            if m.id == memberId then memberName = m.name; break end
        end
        GameState.AddLog(stateRef_, memberName .. " 被任命为" .. pos.name .. "（适应期2季度）")
        AudioManager.PlayEffect("family_assign")
        UI.Toast.Show(memberName .. " → " .. pos.name, { variant = "success", duration = 1.5 })

        FamilyPage._CloseModal()
        if onStateChanged_ then onStateChanged_() end
    end
end

--- 撤下成员
function FamilyPage._DoUnassign(memberId, pos)
    if not stateRef_ then return end

    local success = GameState.AssignPosition(stateRef_, memberId, nil)
    if success then
        stateRef_.ap.max = GameState.CalcMaxAP(stateRef_)
        stateRef_.ap.current = math.min(stateRef_.ap.current, stateRef_.ap.max)

        local memberName = memberId
        for _, m in ipairs(stateRef_.family.members) do
            if m.id == memberId then memberName = m.name; break end
        end
        GameState.AddLog(stateRef_, memberName .. " 被解除" .. pos.name .. "职务")
        UI.Toast.Show(memberName .. " 已撤下", { variant = "info", duration = 1.5 })

        if onStateChanged_ then onStateChanged_() end
    end
end

-- ============================================================================
-- 重随属性弹窗（参考顶部广告金弹窗风格）
-- ============================================================================

---@type table|nil 重随弹窗引用的成员
local rerollMember_ = nil

--- 构建重随弹窗内容
function FamilyPage._BuildRerollModalContent(member)
    local cfg = Balance.AD_FREE_CARD
    local remaining = member.reroll_available or 0
    local active = stateRef_ and stateRef_.ad_free_card_active or false
    local freeUsed = stateRef_ and stateRef_.ad_free_reroll_used or 0
    local freeRemaining = active and (cfg.free_rerolls_per_turn - freeUsed) or 0
    local charges = stateRef_ and stateRef_.ad_free_card_charges or 0

    local children = {}

    -- === 重随属性区域 ===
    table.insert(children, UI.Label {
        text = "🎲 重随属性",
        fontSize = F.subtitle,
        fontWeight = "bold",
        fontColor = C.text_primary,
    })
    table.insert(children, UI.Label {
        text = "剩余 " .. remaining .. " 次",
        fontSize = F.body_minor,
        fontColor = remaining > 0 and C.text_secondary or C.text_muted,
    })

    if remaining > 0 then
        -- 免广告重随按钮
        if active and freeRemaining > 0 then
            table.insert(children, UI.Button {
                text = "🎰 免广告重随（免广剩 " .. freeRemaining .. " 次）",
                variant = "success",
                size = "md",
                width = "100%",
                onClick = Config.ClickGuard(function()
                    FamilyPage._DoFreeReroll(member)
                end),
            })
        end
        -- 看广告重随按钮
        table.insert(children, UI.Button {
            text = "🎬 看广告重随",
            variant = "primary",
            size = "md",
            width = "100%",
            onClick = Config.ClickGuard(function()
                FamilyPage._DoReroll(member)
            end),
        })
    else
        table.insert(children, UI.Label {
            text = "该成员重随次数已用完",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
        })
    end

    -- === 分割线 ===
    table.insert(children, UI.Divider { color = C.divider })

    -- === 免广告卡区域 ===
    table.insert(children, UI.Label {
        text = "🃏 免广告卡",
        fontSize = F.subtitle,
        fontWeight = "bold",
        fontColor = C.text_primary,
    })

    if active then
        local freeRerollAll = cfg.free_rerolls_per_turn - freeUsed
        table.insert(children, UI.Panel {
            width = "100%",
            backgroundColor = "#4CAF5018",
            borderRadius = 6,
            padding = 8,
            flexDirection = "column",
            gap = 4,
            children = {
                UI.Label {
                    text = "✅ 已激活",
                    fontSize = F.body,
                    fontColor = "#4CAF50",
                    fontWeight = "bold",
                },
                UI.Label {
                    text = "重随：本回合免广剩 " .. freeRerollAll
                        .. "/" .. cfg.free_rerolls_per_turn .. " 次",
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                },
            },
        })
    else
        -- 未激活：充能进度 + 充能按钮
        local progress = charges / cfg.charge_ads_needed
        table.insert(children, UI.Label {
            text = "看 " .. cfg.charge_ads_needed .. " 次广告激活，激活后每回合可免广告使用广告金和重随",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
            whiteSpace = "normal",
        })
        -- 进度条
        table.insert(children, UI.Panel {
            width = "100%",
            height = 8,
            backgroundColor = "#333333",
            borderRadius = 4,
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = math.floor(progress * 100) .. "%",
                    height = "100%",
                    backgroundColor = "#F0A030",
                    borderRadius = 4,
                },
            },
        })
        table.insert(children, UI.Button {
            text = "🎬 看广告充能（" .. charges .. "/" .. cfg.charge_ads_needed .. "）",
            variant = "outlined",
            size = "md",
            width = "100%",
            onClick = Config.ClickGuard(function()
                FamilyPage._ChargeAdFreeCardFromReroll()
            end),
        })
    end

    return UI.ScrollView {
        width = "100%",
        maxHeight = 380,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                padding = 4,
                children = children,
            },
        },
    }
end

--- 刷新重随弹窗内容
function FamilyPage._RefreshRerollModal()
    if not rerollModal_ or not rerollMember_ then return end
    local content = FamilyPage._BuildRerollModalContent(rerollMember_)
    rerollModal_:ClearContent()
    rerollModal_:AddContent(content)
end

--- 显示重随属性弹窗
function FamilyPage._ShowRerollModal(member)
    -- 关闭已有的重随弹窗
    if rerollModal_ then
        rerollModal_:Close()
        rerollModal_ = nil
    end
    rerollMember_ = member

    rerollModal_ = UI.Modal {
        title = "🎲 重随属性",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function()
            Config.ConsumeTap()
            rerollModal_ = nil
            rerollMember_ = nil
        end,
    }
    rerollModal_:AddContent(FamilyPage._BuildRerollModalContent(member))
    if uiRoot_ then
        uiRoot_:AddChild(rerollModal_)
    end
    rerollModal_:Open()
end

--- 看广告为免广告卡充能（重随弹窗版本）
function FamilyPage._ChargeAdFreeCardFromReroll()
    if not stateRef_ then return end
    local cfg = Balance.AD_FREE_CARD
    if stateRef_.ad_free_card_active then
        UI.Toast.Show("免广告卡已激活", { variant = "info", duration = 1.5 })
        return
    end

    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        sdk:ShowRewardVideoAd(function(result)
            if not result.success then
                if result.msg == "embed manual close" then
                    UI.Toast.Show("需完整观看广告才能获得奖励",
                        { variant = "warning", duration = 1.5 })
                else
                    UI.Toast.Show("广告播放失败: " .. (result.msg or "未知错误"),
                        { variant = "error", duration = 1.5 })
                end
                return
            end

            local ok2, err2 = pcall(function()
                stateRef_.ad_free_card_charges = (stateRef_.ad_free_card_charges or 0) + 1
                if stateRef_.ad_free_card_charges >= cfg.charge_ads_needed then
                    stateRef_.ad_free_card_active = true
                    stateRef_.ad_free_lucky_used = 0
                    stateRef_.ad_free_reroll_used = 0
                    UI.Toast.Show("免广告卡已激活！\n重随每回合免广 "
                        .. cfg.free_rerolls_per_turn .. " 次",
                        { variant = "success", duration = 3.0 })
                    GameState.AddLog(stateRef_, "免广告卡激活")
                else
                    UI.Toast.Show("充能 " .. stateRef_.ad_free_card_charges
                        .. "/" .. cfg.charge_ads_needed,
                        { variant = "info", duration = 1.5 })
                end

                SaveLoad.Save(stateRef_, SaveLoad.SLOT_AUTO)
                FamilyPage._RefreshRerollModal()
                if onStateChanged_ then onStateChanged_() end
            end)
            if not ok2 then
                print("[免广告卡充能-重随] 回调异常: " .. tostring(err2))
            end
        end)
    end)
    if not ok then
        print("[免广告卡充能-重随] SDK 调用异常: " .. tostring(err))
        UI.Toast.Show("广告服务暂不可用", { variant = "error", duration = 1.5 })
    end
end

--- 重随成功后的通用处理
function FamilyPage._ApplyReroll(member)
    FamiliesData.RerollMemberAttrs(member)
    member.reroll_available = (member.reroll_available or 0) - 1
    if member.reroll_available < 0 then member.reroll_available = 0 end

    local attrSum = 0
    for _, v in pairs(member.attrs) do attrSum = attrSum + v end
    UI.Toast.Show(member.name .. " 属性已重随（总和 " .. attrSum .. "）",
        { variant = "success", duration = 2.0 })

    -- 重随后立即存档，防止闪退导致进度丢失
    SaveLoad.Save(stateRef_, SaveLoad.SLOT_AUTO)

    -- 如果重随弹窗打开，刷新内容而不是关闭
    if rerollModal_ then
        FamilyPage._RefreshRerollModal()
        -- 如果次数用完，关闭重随弹窗
        if (member.reroll_available or 0) <= 0 then
            rerollModal_:Close()
            rerollModal_ = nil
            rerollMember_ = nil
        end
    else
        FamilyPage._CloseModal()
    end
    if onStateChanged_ then onStateChanged_() end
end

--- 检查免广告卡是否可用于本次重随
function FamilyPage._CanUseAdFreeCard()
    if not stateRef_ then return false end
    if not stateRef_.ad_free_card_active then return false end
    local cfg = Balance.AD_FREE_CARD
    local used = stateRef_.ad_free_reroll_used or 0
    return used < cfg.free_rerolls_per_turn
end

--- 免广告重随（使用免广告卡配额）
function FamilyPage._DoFreeReroll(member)
    if not stateRef_ then return end
    if (member.reroll_available or 0) <= 0 then
        UI.Toast.Show("该成员没有重随机会", { variant = "warning", duration = 1.5 })
        return
    end
    if not FamilyPage._CanUseAdFreeCard() then
        UI.Toast.Show("本回合免广告次数已用完", { variant = "warning", duration = 1.5 })
        return
    end
    stateRef_.ad_free_reroll_used = (stateRef_.ad_free_reroll_used or 0) + 1
    FamilyPage._ApplyReroll(member)
end

--- 看广告重随属性
function FamilyPage._DoReroll(member)
    if not stateRef_ then return end
    if (member.reroll_available or 0) <= 0 then
        UI.Toast.Show("该成员没有重随机会", { variant = "warning", duration = 1.5 })
        return
    end

    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        sdk:ShowRewardVideoAd(function(result)
            if not result.success then
                if result.msg == "embed manual close" then
                    UI.Toast.Show("需完整观看广告才能获得奖励",
                        { variant = "warning", duration = 1.5 })
                else
                    UI.Toast.Show("广告播放失败: " .. (result.msg or "未知错误"),
                        { variant = "error", duration = 1.5 })
                end
                return
            end

            -- 回调中二次检查，防止广告播放期间状态变化
            if (member.reroll_available or 0) <= 0 then
                UI.Toast.Show("重随次数已用完", { variant = "warning", duration = 1.5 })
                return
            end

            local ok2, err2 = pcall(function()
                FamilyPage._ApplyReroll(member)
            end)
            if not ok2 then
                print("[看广告重随] 回调异常: " .. tostring(err2))
            end
        end)
    end)
    if not ok then
        print("[看广告重随] SDK 调用异常: " .. tostring(err))
        UI.Toast.Show("广告服务暂不可用", { variant = "error", duration = 1.5 })
    end
end



--- 关闭当前弹窗
function FamilyPage._CloseModal()
    if rerollModal_ then
        rerollModal_:Close()
        rerollModal_ = nil
        rerollMember_ = nil
    end
    if currentModal_ then
        currentModal_:Close()
        currentModal_ = nil
    end
end

-- ============================================================================
-- 大学进修弹窗
-- ============================================================================

--- 打开大学弹窗：选择学位 → 选择成员 → 确认入学
function FamilyPage._ShowUniversityModal(state)
    FamilyPage._CloseModal()
    if not state then return end

    local baseCost = Balance.FAMILY.university_cost or 300
    local cost = math.floor(baseCost * GameState.GetInflationFactor(state))
    local duration = Balance.FAMILY.university_duration or 4
    local maxDeg = Balance.FAMILY.university_max_degrees or 2

    -- 当前在学人员
    local studyingCount = state.family.university and #state.family.university or 0

    -- 学位网格
    local degreeCards = {}
    for _, deg in ipairs(FamiliesData.DEGREES) do
        table.insert(degreeCards, UI.Panel {
            width = "48%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_badge,
            borderWidth = 1,
            borderColor = C.border_card,
            flexDirection = "column",
            gap = 4,
            children = {
                UI.Label {
                    text = deg.icon .. " " .. deg.name,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = deg.effect_desc,
                    fontSize = F.label,
                    fontColor = C.accent_green,
                },
                UI.Label {
                    text = deg.desc,
                    fontSize = F.label,
                    fontColor = C.text_muted,
                    whiteSpace = "normal",
                    lineHeight = 1.3,
                },
                UI.Button {
                    text = "选择此学位",
                    fontSize = F.label,
                    variant = "outlined",
                    size = "sm",
                    width = "100%",
                    onClick = Config.ClickGuard(function()
                        FamilyPage._ShowUniversityMemberPicker(state, deg)
                    end),
                },
            },
        })
    end

    -- 当前在学列表
    local studyingItems = {}
    if studyingCount > 0 then
        table.insert(studyingItems, UI.Divider { color = C.divider })
        table.insert(studyingItems, UI.Label {
            text = "当前在学",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        })
        for _, u in ipairs(state.family.university or {}) do
            local mem = nil
            for _, m in ipairs(state.family.members) do
                if m.id == u.member_id then mem = m; break end
            end
            local dDef = FamiliesData.GetDegreeDef(u.degree_id)
            local label = (mem and mem.name or "?") .. " — "
                .. (dDef and (dDef.icon .. " " .. dDef.name) or "?")
                .. string.format("（%d/%d季）", u.progress or 0, u.total or 4)
            table.insert(studyingItems, UI.Label {
                text = label,
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            })
        end
    end

    -- 组装所有 children（避免 nil 空洞和 table.unpack 陷阱）
    local scrollChildren = {
        -- 信息区
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 12,
            children = {
                FamilyPage._StatItem("费用", string.format("💰%d", cost)),
                FamilyPage._StatItem("学制", string.format("%d季", duration)),
                FamilyPage._StatItem("在学", tostring(studyingCount) .. "人"),
                FamilyPage._StatItem("上限", string.format("%d学位/人", maxDeg)),
            },
        },
        UI.Divider { color = C.divider },
        UI.Label {
            text = "选择一个学位方向",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        },
        -- 学位卡片网格
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 8,
            justifyContent = "space-between",
            children = degreeCards,
        },
    }
    for _, item in ipairs(studyingItems) do
        table.insert(scrollChildren, item)
    end

    local content = UI.ScrollView {
        width = "100%",
        maxHeight = 480,
        flexShrink = 1,
        scrollY = true,
        bounces = false,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 12,
                padding = S.card_padding,
                children = scrollChildren,
            },
        },
    }

    currentModal_ = UI.Modal {
        title = "🎓 萨拉热窝大学",
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            Config.ConsumeTap()
            currentModal_ = nil
            self:Destroy()
        end,
    }
    currentModal_:AddContent(content)
    if uiRoot_ then
        uiRoot_:AddChild(currentModal_)
    end
    currentModal_:Open()
end

--- 大学弹窗第二步：选择送哪个成员去进修
function FamilyPage._ShowUniversityMemberPicker(state, degree)
    FamilyPage._CloseModal()

    local baseCost = Balance.FAMILY.university_cost or 300
    local cost = math.floor(baseCost * GameState.GetInflationFactor(state))
    local maxDeg = Balance.FAMILY.university_max_degrees or 2

    -- 筛选可用成员：活跃、未在进修、学位未满、未拥有此学位
    local eligible = {}
    for _, m in ipairs(state.family.members) do
        if m.status == "active" then
            local studying = FamilyPage._IsStudying(state, m.id)
            local degCount = m.degrees and #m.degrees or 0
            local hasDeg = false
            if m.degrees then
                for _, d in ipairs(m.degrees) do
                    if d == degree.id then hasDeg = true; break end
                end
            end
            if not studying and degCount < maxDeg and not hasDeg then
                table.insert(eligible, m)
            end
        end
    end

    local rows = {}
    if #eligible == 0 then
        table.insert(rows, UI.Label {
            text = "没有符合条件的成员",
            fontSize = F.body,
            fontColor = C.text_muted,
            paddingVertical = 16,
            textAlign = "center",
            width = "100%",
        })
    else
        for _, m in ipairs(eligible) do
            local posName = nil
            if m.position then
                for _, p in ipairs(Config.POSITIONS) do
                    if p.id == m.position then posName = p.name; break end
                end
            end
            table.insert(rows, UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                paddingVertical = 6,
                paddingHorizontal = 4,
                borderRadius = S.radius_badge,
                backgroundColor = C.paper_dark,
                children = {
                    m.portraitImage and UI.Panel {
                        width = 40,
                        height = 64,
                        borderRadius = S.radius_badge,
                        backgroundImage = m.portraitImage,
                        backgroundFit = "cover",
                        borderWidth = 1,
                        borderColor = C.border_card,
                        flexShrink = 0,
                    } or UI.Avatar {
                        name = m.name,
                        initials = m.portrait,
                        size = 28,
                        shape = "rounded",
                        backgroundColor = C.paper_mid,
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
                                        text = m.name,
                                        fontSize = F.body,
                                        fontWeight = "bold",
                                        fontColor = C.text_primary,
                                    },
                                    FamilyPage._TraitChip(m),
                                    FamilyPage._FlawChip(m),
                                },
                            },
                            UI.Panel {
                                flexDirection = "row",
                                gap = 4,
                                flexWrap = "wrap",
                                children = {
                                    posName and UI.Label {
                                        text = "在岗：" .. posName .. "（将离岗）",
                                        fontSize = F.label,
                                        fontColor = C.accent_amber,
                                    } or nil,
                                    (m.degrees and #m.degrees > 0) and UI.Label {
                                        text = "学位：" .. #m.degrees .. "/" .. maxDeg,
                                        fontSize = F.label,
                                        fontColor = C.text_muted,
                                    } or nil,
                                },
                            },
                        },
                    },
                    UI.Button {
                        text = "送修",
                        fontSize = F.label,
                        variant = "primary",
                        size = "sm",
                        disabled = state.cash < cost,
                        onClick = Config.ClickGuard(function()
                            local ok, msg = GameState.StartUniversity(state, m.id, degree.id)
                            UI.Toast.Show(msg, { variant = ok and "success" or "warning", duration = 2.0 })
                            FamilyPage._CloseModal()
                            if ok and onStateChanged_ then onStateChanged_() end
                        end),
                    },
                },
            })
        end
    end

    -- 组装 children（避免 nil 空洞和 table.unpack 陷阱）
    local pickerChildren = {
        UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            children = {
                UI.Chip {
                    label = degree.icon .. " " .. degree.name,
                    color = "primary",
                    variant = "soft",
                    size = "md",
                },
                UI.Label {
                    text = degree.effect_desc,
                    fontSize = F.body,
                    fontColor = C.accent_green,
                },
            },
        },
    }
    if state.cash < cost then
        table.insert(pickerChildren, UI.Label {
            text = string.format("现金不足（需要 💰%d，当前 💰%d）", cost, math.floor(state.cash)),
            fontSize = F.body_minor,
            fontColor = C.accent_red,
        })
    end
    table.insert(pickerChildren, UI.Divider { color = C.divider })
    table.insert(pickerChildren, UI.Label {
        text = "选择成员",
        fontSize = F.subtitle,
        fontWeight = "bold",
        fontColor = C.text_secondary,
    })
    for _, row in ipairs(rows) do
        table.insert(pickerChildren, row)
    end

    local content = UI.ScrollView {
        width = "100%",
        maxHeight = 480,
        flexShrink = 1,
        scrollY = true,
        bounces = false,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                padding = S.card_padding,
                children = pickerChildren,
            },
        },
    }

    currentModal_ = UI.Modal {
        title = "📖 选择进修成员",
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            Config.ConsumeTap()
            currentModal_ = nil
            self:Destroy()
        end,
    }
    currentModal_:AddContent(content)
    if uiRoot_ then
        uiRoot_:AddChild(currentModal_)
    end
    currentModal_:Open()
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- ●○ 点状评分（完整版，10个点）
function FamilyPage._DotRating(val)
    local filled = math.min(math.max(math.floor(val), 0), 10)
    local empty = 10 - filled
    return string.rep("●", filled) .. string.rep("○", empty)
end

--- ●○ 点状评分（紧凑版，5个点，每2点一个实心）
function FamilyPage._DotRatingShort(val)
    local filled = math.min(math.max(math.floor(val / 2), 0), 5)
    local empty = 5 - filled
    return string.rep("●", filled) .. string.rep("○", empty)
end

return FamilyPage
