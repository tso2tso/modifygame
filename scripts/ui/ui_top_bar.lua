-- ============================================================================
-- 顶栏 UI（sarajevo_dynasty_ui_spec §4.1 + §4.2）
-- Row1: 年份+Q季+季节 | 日期 | 竖线分隔资源4格 | 设置齿轮    72px
-- Row2: AP图标+已用/总量+副文字 | 圆点进度条 | [+]按钮 | 安全等级胶囊  52px
-- 严格遵循设计图参考
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local RegionsData = require("data.regions_data")

local C = Config.COLORS
local S = Config.SIZE
local F = Config.FONT

local TopBar = {}

---@type function|nil
local onSettings_ = nil

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 创建顶栏（双行）
---@param state table
---@param callbacks table|nil { onSettings = function }
---@return table widget
function TopBar.Create(state, callbacks)
    onSettings_ = callbacks and callbacks.onSettings

    return UI.Panel {
        id = "topBarRoot",
        width = "100%",
        flexDirection = "column",
        backgroundColor = C.bg_base,
        borderBottomWidth = 1,
        borderBottomColor = { C.paper_light[1], C.paper_light[2], C.paper_light[3], 128 },
        children = {
            TopBar._CreateInfoRow(state),
            TopBar._CreateAPRow(state),
        },
    }
end

-- ============================================================================
-- Row 1: 年份+季节+日期 | 资源4格（竖线分隔） | 设置齿轮   (72px)
-- 设计图参考：左侧 "1904年 Q2 春季" + 副文字 "4月15日"
-- 中部：4组资源 💰现金 🟡黄金(吨) ⛏产能 ⭐声望
-- 右侧：⚙ 设置
-- ============================================================================
function TopBar._CreateInfoRow(state)
    -- 设计图格式："1904年 Q{n} {季}季"
    local yearText = string.format("%d年 Q%d %s季",
        state.year, state.quarter, Config.QUARTER_NAMES[state.quarter])
    -- 日期副文字
    local dateText = Config.QUARTER_DATES[state.quarter] or ""

    -- 产能（当季矿产）
    local production = 0
    for _, mine in ipairs(state.mines) do
        if mine.active then
            production = production + (mine.level * 30 + state.workers.hired * 2)
        end
    end

    -- 声望
    local reputation = 0
    if state.regions and #state.regions > 0 then
        reputation = state.regions[1].influence or 0
    end

    return UI.Panel {
        id = "topInfoRow",
        width = "100%",
        height = S.top_bar_height,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = S.page_padding,
        children = {
            -- 年份 + 季节（§4.1 左侧：时间信息区，22px 大字 + 12px 副文字）
            UI.Panel {
                flexDirection = "column",
                flexShrink = 0,
                children = {
                    UI.Label {
                        id = "yearLabel",
                        text = yearText,
                        fontSize = F.page_title,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        id = "dateLabel",
                        text = dateText,
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                    },
                },
            },

            -- 弹性间隔
            UI.Panel { flexGrow = 1 },

            -- §4.1 中部核心资源4格（图标+数字+标签，竖线分隔）
            -- 💰现金 / 🟡黄金(吨) / ⛏产能 / ⭐声望
            TopBar._ResourceCell("cashCell", "💰",
                Config.FormatNumber(state.cash), C.accent_gold, "现金"),
            TopBar._VerticalDivider(),
            TopBar._ResourceCell("goldCell", "🟡",
                tostring(state.gold), C.text_primary, "黄金(吨)"),
            TopBar._VerticalDivider(),
            TopBar._ResourceCell("prodCell", "⛏️",
                tostring(production), C.text_primary, "产能"),
            TopBar._VerticalDivider(),
            TopBar._ResourceCell("repCell", "⭐",
                tostring(reputation), C.text_primary, "声望"),

            -- §4.1 右侧：⚙设置图标 24px + "设置"标签
            UI.Panel {
                width = 40,
                marginLeft = S.spacing_sm,
                justifyContent = "center",
                alignItems = "center",
                gap = 1,
                pointerEvents = "auto",
                onPointerUp = function(self)
                    if onSettings_ then onSettings_() end
                end,
                children = {
                    UI.Label {
                        text = "⚙️",
                        fontSize = S.icon_size,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "设置",
                        fontSize = 9,
                        fontColor = C.text_muted,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

--- §4.1 资源格：图标16px + 数值16px bold + 标签11px text_secondary
function TopBar._ResourceCell(id, icon, valueText, valueColor, label)
    return UI.Panel {
        id = id,
        flexDirection = "column",
        alignItems = "center",
        gap = 1,
        paddingHorizontal = 6,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 3,
                children = {
                    UI.Label {
                        text = icon,
                        fontSize = S.icon_resource,
                    },
                    UI.Label {
                        id = id .. "_val",
                        text = valueText,
                        fontSize = F.data_small,
                        fontWeight = "bold",
                        fontColor = valueColor or C.text_primary,
                    },
                },
            },
            label and UI.Label {
                text = label,
                fontSize = 9,
                fontColor = C.text_muted,
            } or nil,
        },
    }
end

--- 竖线分隔符（1px paper_mid）
function TopBar._VerticalDivider()
    return UI.Panel {
        width = 1,
        height = 24,
        backgroundColor = C.paper_mid,
    }
end

-- ============================================================================
-- Row 2: AP信息 | 圆点进度条 | [+]按钮 | 安全等级   (52px)
-- 设计图参考：
--   左侧 "AP" 标签 + "4 / 6" 大字 + ●●●●○○ 圆点 + [+] 按钮
--   右侧 "安全等级" + 🛡低/中/高 胶囊
-- ============================================================================
function TopBar._CreateAPRow(state)
    local apCurrent = state.ap.current
    local apMax = state.ap.max

    -- AP 圆点（§4.2 已用实心 ● accent_gold，未用空心 ○ paper_light）
    local dots = {}
    for i = 1, apMax do
        local isFilled = (i <= apCurrent)
        table.insert(dots, UI.Panel {
            width = S.ap_dot_size,
            height = S.ap_dot_size,
            borderRadius = S.ap_dot_size / 2,
            backgroundColor = isFilled and C.ap_filled or { 0, 0, 0, 0 },
            borderWidth = isFilled and 0 or 1,
            borderColor = C.ap_empty,
        })
    end

    -- 安全等级
    local security = 0
    for _, r in ipairs(state.regions) do
        if r.id == "mine_district" then
            security = r.security
            break
        end
    end
    local secText = RegionsData.GetSecurityText(security)
    local secBg, secFontColor
    if security <= 2 then
        secBg = C.accent_red
        secFontColor = { 255, 255, 255, 255 }
    elseif security >= 4 then
        secBg = C.accent_green
        secFontColor = { 255, 255, 255, 255 }
    else
        secBg = C.accent_amber
        secFontColor = { 255, 255, 255, 255 }
    end

    return UI.Panel {
        id = "apRow",
        width = "100%",
        height = S.ap_bar_height,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = S.page_padding,
        backgroundColor = C.bg_surface,
        children = {
            -- 设计图左侧：AP 圆形标签 + 数字
            UI.Panel {
                width = 32, height = 32,
                borderRadius = 16,
                backgroundColor = C.paper_dark,
                borderWidth = 1,
                borderColor = C.accent_gold,
                justifyContent = "center",
                alignItems = "center",
                marginRight = 6,
                children = {
                    UI.Label {
                        text = "AP",
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                },
            },

            -- AP 文字：已用/总量 + 副标题
            UI.Panel {
                flexDirection = "column",
                flexShrink = 0,
                marginRight = S.spacing_sm,
                children = {
                    UI.Label {
                        id = "apCountLabel",
                        text = string.format("%d / %d", apCurrent, apMax),
                        fontSize = F.card_title,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = "本季可用行动点",
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                    },
                },
            },

            -- 中部：圆点进度条
            UI.Panel {
                id = "apDots",
                flexDirection = "row",
                alignItems = "center",
                gap = S.ap_dot_gap,
                flexGrow = 1,
                children = dots,
            },

            -- [+] 按钮（§4.2 获取额外AP，32x32，圆角4px，accent_gold边框）
            UI.Panel {
                width = 32, height = 32,
                borderRadius = S.radius_btn,
                backgroundColor = C.paper_dark,
                borderWidth = 1,
                borderColor = C.accent_gold,
                justifyContent = "center",
                alignItems = "center",
                marginHorizontal = S.spacing_sm,
                pointerEvents = "auto",
                onPointerUp = function(self)
                    UI.Toast.Show("额外AP功能开发中", { variant = "info", duration = 1.0 })
                end,
                children = {
                    UI.Label {
                        text = "+",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                },
            },

            -- §4.2 安全等级胶囊："安全等级" 文字 + 🛡 + 等级
            UI.Panel {
                flexDirection = "column",
                alignItems = "flex-end",
                gap = 1,
                children = {
                    UI.Label {
                        text = "安全等级",
                        fontSize = 9,
                        fontColor = C.text_muted,
                    },
                    UI.Panel {
                        id = "securityBadge",
                        paddingHorizontal = 8,
                        paddingVertical = 3,
                        borderRadius = S.radius_btn,
                        backgroundColor = secBg,
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        children = {
                            UI.Label {
                                text = "🛡️ " .. secText,
                                fontSize = F.label,
                                fontColor = secFontColor,
                                pointerEvents = "none",
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 刷新
-- ============================================================================
function TopBar.Refresh(root, state)
    local yearLabel = root:FindById("yearLabel")
    if yearLabel then
        yearLabel:SetText(string.format("%d年 Q%d %s季",
            state.year, state.quarter, Config.QUARTER_NAMES[state.quarter]))
    end

    local dateLabel = root:FindById("dateLabel")
    if dateLabel then
        dateLabel:SetText(Config.QUARTER_DATES[state.quarter] or "")
    end

    local cashVal = root:FindById("cashCell_val")
    if cashVal then cashVal:SetText(Config.FormatNumber(state.cash)) end

    local goldVal = root:FindById("goldCell_val")
    if goldVal then goldVal:SetText(tostring(state.gold)) end

    local production = 0
    for _, mine in ipairs(state.mines) do
        if mine.active then
            production = production + (mine.level * 30 + state.workers.hired * 2)
        end
    end
    local prodVal = root:FindById("prodCell_val")
    if prodVal then prodVal:SetText(tostring(production)) end

    local reputation = 0
    if state.regions and #state.regions > 0 then
        reputation = state.regions[1].influence or 0
    end
    local repVal = root:FindById("repCell_val")
    if repVal then repVal:SetText(tostring(reputation)) end

    local apLabel = root:FindById("apCountLabel")
    if apLabel then
        apLabel:SetText(string.format("%d / %d", state.ap.current, state.ap.max))
    end
end

return TopBar
