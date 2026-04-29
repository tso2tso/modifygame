-- ============================================================================
-- 家族页 UI：成员卡片、属性展示、岗位分配
-- 设计规范：sarajevo_dynasty_ui_spec §6.2
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local FamiliesData = require("data.families_data")
local Balance = require("data.balance")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local FamilyPage = {}

---@type table 游戏状态引用
local stateRef_ = nil
---@type function|nil 状态变化回调
local onStateChanged_ = nil

-- 属性条颜色映射（使用更克制的工业时代配色）
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

--- 创建家族页完整内容
---@param state table
---@param callbacks table { onStateChanged = function }
---@return table widget
function FamilyPage.Create(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged

    return FamilyPage._BuildContent(state)
end

--- 构建页面内容
function FamilyPage._BuildContent(state)
    local children = {}

    -- 家族概况卡片
    table.insert(children, FamilyPage._CreateSummaryCard(state))

    -- 成员卡片
    for _, member in ipairs(state.family.members) do
        table.insert(children, FamilyPage._CreateMemberCard(state, member))
    end

    return UI.Panel {
        id = "familyContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = children,
    }
end

--- 家族概况卡片（§6.2 家主卡样式 — 金色边框）
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
                gap = 16,
                children = {
                    FamilyPage._StatItem("成员", string.format("%d/%d", activeCount, Balance.FAMILY.max_members)),
                    FamilyPage._StatItem("在岗", string.format("%d/%d", assignedCount, #Config.POSITIONS)),
                    FamilyPage._StatItem("空缺", tostring(#Config.POSITIONS - assignedCount)),
                },
            },
            -- 提示
            UI.Label {
                text = "分配家族成员到岗位可获得对应方向的经营加成",
                fontSize = F.body_minor,
                fontColor = C.text_muted,
                whiteSpace = "normal",
                lineHeight = 1.4,
            },
        },
    }
end

--- 统计项小组件
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

--- 生成 ●○ 点状评分字符串（§6.2 评分用 1-10 数字 + 小点状图）
---@param val number 0-10
---@return string
local function dotRating(val)
    local filled = math.min(math.max(math.floor(val), 0), 10)
    local empty = 10 - filled
    return string.rep("●", filled) .. string.rep("○", empty)
end

--- 创建单个成员卡片（§6.2 成员列表样式）
function FamilyPage._CreateMemberCard(state, member)
    local isDisabled = (member.status == "disabled")
    local isHead = (member.id == "patriarch")  -- 家主卡金色边框

    -- 构建岗位下拉选项
    local posOptions = { { value = "__none__", label = "未分配" } }
    for _, pos in ipairs(Config.POSITIONS) do
        local occupied = false
        local occupant = ""
        for _, m in ipairs(state.family.members) do
            if m.position == pos.id and m.id ~= member.id and m.status == "active" then
                occupied = true
                occupant = m.name
                break
            end
        end
        local label = pos.name
        if occupied then
            label = pos.name .. " (" .. occupant .. ")"
        end
        table.insert(posOptions, {
            value = pos.id,
            label = label,
            disabled = occupied,
        })
    end

    local currentPos = member.position or "__none__"

    -- 岗位适配信息
    local fitInfo = FamilyPage._GetCurrentFitInfo(member)

    -- 状态标签
    local statusChips = {}
    if isDisabled then
        table.insert(statusChips, UI.Chip {
            label = "失能 " .. member.disabled_turns .. "回合",
            color = "error",
            variant = "soft",
            size = "sm",
        })
    elseif member.position then
        table.insert(statusChips, UI.Chip {
            label = fitInfo.label,
            color = fitInfo.chipColor,
            variant = "soft",
            size = "sm",
        })
    else
        table.insert(statusChips, UI.Chip {
            label = "待命",
            color = "default",
            variant = "outlined",
            size = "sm",
        })
    end

    -- 成员卡片边框色：家主金色，失能红色，普通用 border_card
    local cardBorder = C.border_card
    if isHead then
        cardBorder = C.border_gold
    elseif isDisabled then
        cardBorder = C.danger
    end

    -- 职务角色徽章（§6.2 职务标注 11px 徽章）
    local positionBadge = nil
    if member.position then
        local posName = member.position
        for _, p in ipairs(Config.POSITIONS) do
            if p.id == member.position then posName = p.name; break end
        end
        positionBadge = UI.Panel {
            paddingHorizontal = 6,
            paddingVertical = 2,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_badge,
            borderWidth = 1,
            borderColor = C.border_card,
            children = {
                UI.Label {
                    text = posName,
                    fontSize = F.label,
                    fontColor = C.accent_gold,
                },
            },
        }
    end

    return UI.Panel {
        id = "memberCard_" .. member.id,
        width = "100%",
        backgroundColor = isDisabled and C.bg_elevated or C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = cardBorder,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 头部：头像 + 名字 + 头衔 + 状态
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    -- 头像（§6.2 头像 32px）
                    UI.Avatar {
                        name = member.name,
                        initials = member.portrait,
                        size = 32,
                        shape = "rounded",
                        backgroundColor = isDisabled and C.bg_surface or C.paper_mid,
                        showBorder = true,
                        borderColor = isHead and C.accent_gold or C.border_card,
                    },
                    -- 名字 + 头衔 + 职务徽章
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
                                        fontSize = F.subtitle,
                                        fontWeight = "bold",
                                        fontColor = isDisabled and C.text_muted or C.text_primary,
                                    },
                                    positionBadge,
                                },
                            },
                            UI.Label {
                                text = member.title,
                                fontSize = F.body_minor,
                                fontColor = C.text_secondary,
                            },
                        },
                    },
                    -- 状态标签
                    UI.Panel {
                        flexDirection = "row",
                        gap = 4,
                        children = statusChips,
                    },
                },
            },

            -- 属性评分（§6.2 ●○ 点状图 + 数值）
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = 8,
                flexDirection = "column",
                gap = 4,
                children = FamilyPage._CreateAttrDots(member),
            },

            UI.Divider { color = C.divider },

            -- 岗位分配区域
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = "岗位",
                        fontSize = F.body,
                        fontColor = C.text_secondary,
                        width = 32,
                    },
                    UI.Dropdown {
                        id = "posDropdown_" .. member.id,
                        options = posOptions,
                        value = currentPos,
                        disabled = isDisabled,
                        flexGrow = 1,
                        maxVisibleItems = 5,
                        itemHeight = 36,
                        onChange = function(self, value, option)
                            FamilyPage._OnPositionChanged(member.id, value)
                        end,
                    },
                },
            },

            -- 简介
            UI.Panel {
                width = "100%",
                paddingHorizontal = S.card_padding,
                paddingBottom = S.card_padding,
                children = {
                    UI.Label {
                        text = member.bio,
                        fontSize = F.body_minor,
                        fontColor = C.text_muted,
                        whiteSpace = "normal",
                        lineHeight = 1.4,
                    },
                },
            },
        },
    }
end

--- 创建 ●○ 点状属性评分列表（§6.2 三维度评分 ●○ 形式）
function FamilyPage._CreateAttrDots(member)
    local rows = {}
    for _, attrKey in ipairs(ATTR_ORDER) do
        local val = member.attrs[attrKey] or 0
        local attrName = Config.ATTR_NAMES[attrKey] or attrKey
        local color = ATTR_COLORS[attrKey] or C.text_primary

        table.insert(rows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                -- 属性名
                UI.Label {
                    text = attrName,
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                    width = 24,
                    textAlign = "right",
                },
                -- ●○ 点状评分
                UI.Label {
                    text = dotRating(val),
                    fontSize = 8,
                    fontColor = color,
                    flexGrow = 1,
                    letterSpacing = 1,
                },
                -- 数值
                UI.Label {
                    text = tostring(val),
                    fontSize = F.label,
                    fontWeight = "bold",
                    fontColor = color,
                    width = 16,
                    textAlign = "right",
                },
            },
        })
    end
    return rows
end

--- 获取当前岗位适配信息
function FamilyPage._GetCurrentFitInfo(member)
    if not member.position then
        return { label = "待命", chipColor = "default" }
    end

    local posConfig = nil
    for _, p in ipairs(Config.POSITIONS) do
        if p.id == member.position then posConfig = p; break end
    end
    if not posConfig then
        return { label = "待命", chipColor = "default" }
    end

    local rating, _ = FamiliesData.GetPositionFit(member, posConfig.attr1, posConfig.attr2)
    local chipColorMap = {
        excellent = "success",
        good      = "warning",
        poor      = "error",
    }
    return {
        label = posConfig.name .. " · " .. (FIT_LABELS[rating] or ""),
        chipColor = chipColorMap[rating] or "default",
    }
end

--- 岗位变更回调
function FamilyPage._OnPositionChanged(memberId, positionValue)
    if not stateRef_ then return end

    local posId = (positionValue == "__none__") and nil or positionValue
    local success = GameState.AssignPosition(stateRef_, memberId, posId)

    if success then
        stateRef_.ap.max = GameState.CalcMaxAP(stateRef_)
        stateRef_.ap.current = math.min(stateRef_.ap.current, stateRef_.ap.max)

        local memberName = memberId
        for _, m in ipairs(stateRef_.family.members) do
            if m.id == memberId then memberName = m.name; break end
        end

        if posId then
            local posName = posId
            for _, p in ipairs(Config.POSITIONS) do
                if p.id == posId then posName = p.name; break end
            end
            GameState.AddLog(stateRef_, memberName .. " 被任命为" .. posName)
            UI.Toast.Show(memberName .. " → " .. posName, { variant = "success", duration = 1.5 })
        else
            GameState.AddLog(stateRef_, memberName .. " 被解除岗位")
            UI.Toast.Show(memberName .. " 已解除岗位", { variant = "info", duration = 1.5 })
        end

        if onStateChanged_ then
            onStateChanged_()
        end
    end
end

--- 刷新家族页
---@param root table UI 根控件
---@param state table
function FamilyPage.Refresh(root, state)
    stateRef_ = state
    local content = root and root:FindById("familyContent")
    if not content then return false end

    local nextContent = FamilyPage._BuildContent(state)
    content:ClearChildren()
    for _, child in ipairs(nextContent:GetChildren()) do
        content:AddChild(child)
    end
    return true
end

return FamilyPage
