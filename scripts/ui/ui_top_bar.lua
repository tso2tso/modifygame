-- ============================================================================
-- 顶栏 UI（sarajevo_dynasty_ui_spec §4.1 + §4.2）
-- Row1: 年份+Q季+季节 | 日期 | 竖线分隔资源4格 | 设置齿轮    72px
-- Row2: AP图标+已用/总量+副文字 | 圆点进度条 | [+]按钮 | 安全等级胶囊  52px
-- 严格遵循设计图参考
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local RegionsData = require("data.regions_data")
local Balance = require("data.balance")
local GameState = require("game_state")

local C = Config.COLORS
local S = Config.SIZE
local F = Config.FONT

local TopBar = {}

---@type function|nil
local onSettings_ = nil
---@type function|nil 状态变化回调（AP 购买后通知 UIManager 重建）
local onStateChanged_ = nil
---@type table 游戏状态引用（用于 + 按钮）
local stateRef_ = nil

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 创建顶栏（双行）
---@param state table
---@param callbacks table|nil { onSettings = function }
---@return table widget
function TopBar.Create(state, callbacks)
    onSettings_ = callbacks and callbacks.onSettings
    onStateChanged_ = callbacks and callbacks.onStateChanged
    stateRef_ = state

    local era = Config.GetEraByYear(state.year)
    -- 顶栏底线颜色 = era_accent 的 30% 透明（对应 HTML 中 --era-border 的视觉层级）
    local borderBottom = { era.accent[1], era.accent[2], era.accent[3], 80 }

    local children = {
        TopBar._CreateInfoRow(state, era),
        TopBar._CreateAPRow(state, era),
    }

    -- 战争时代（2/4/6章）叠加红色斜纹
    if era.war_stripe then
        table.insert(children, 1, UI.Panel {
            id = "warStripe",
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 139, 0, 0, 20 },  -- 8% 暗红
            pointerEvents = "none",
        })
    end

    return UI.Panel {
        id = "topBarRoot",
        width = "100%",
        flexDirection = "column",
        backgroundColor = C.bg_base,
        borderBottomWidth = 1,
        borderBottomColor = borderBottom,
        children = children,
    }
end

-- ============================================================================
-- Row 1: 年份+季节+日期 | 资源4格（竖线分隔） | 设置齿轮   (72px)
-- 设计图参考：左侧 "1904年 Q2 春季" + 副文字 "4月15日"
-- 中部：4组资源 💰现金 🟡黄金(吨) ⛏产能 ⭐声望
-- 右侧：⚙ 设置
-- ============================================================================
function TopBar._CreateInfoRow(state, era)
    era = era or Config.GetEraByYear(state.year)
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
            -- 接入时代 accent：年份文字使用 era.accent 传达年代感
            UI.Panel {
                flexDirection = "column",
                flexShrink = 0,
                children = {
                    UI.Label {
                        id = "yearLabel",
                        text = yearText,
                        fontSize = F.page_title,
                        fontWeight = "bold",
                        fontColor = era.accent,
                    },
                    UI.Label {
                        id = "dateLabel",
                        text = dateText,
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                    },
                    -- 时代标签（小字，显示当前章节名）
                    UI.Label {
                        id = "eraLabel",
                        text = era.label,
                        fontSize = 9,
                        fontColor = { era.accent[1], era.accent[2], era.accent[3], 180 },
                    },
                },
            },

            -- 弹性间隔
            UI.Panel { flexGrow = 1 },

            -- §4.1 中部核心资源4格（图标+数字+标签，竖线分隔）
            -- 💰现金 / 🟡黄金(吨) / ⛏产能 / ⭐声望
            TopBar._ResourceCell("cashCell", "💰",
                Config.FormatNumber(state.cash), era.accent, "现金"),
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
function TopBar._CreateAPRow(state, era)
    era = era or Config.GetEraByYear(state.year)
    local tempAP = state.ap.temp or 0
    local totalAvail = state.ap.current + tempAP
    local apMax = state.ap.max
    local totalDots = apMax + tempAP  -- 临时 AP 额外显示圆点

    -- AP 圆点：实心=剩余可用（era_accent），空心=已用
    -- 对应 HTML 中的 --era-accent 接入点之一
    local dots = {}
    for i = 1, totalDots do
        local isFilled = (i <= totalAvail)
        local isTemp = (i > apMax)  -- 超出 max 的属于临时 AP
        -- 空心描边：era_accent 35% 透明
        local emptyBorder = { era.accent[1], era.accent[2], era.accent[3], 89 }
        local fillColor
        if isFilled then
            fillColor = isTemp
                and { era.accent[1], era.accent[2], era.accent[3], 160 }  -- 临时 AP 半透明
                or era.accent
        else
            fillColor = { 0, 0, 0, 0 }
        end
        table.insert(dots, UI.Panel {
            width = S.ap_dot_size,
            height = S.ap_dot_size,
            borderRadius = S.ap_dot_size / 2,
            backgroundColor = fillColor,
            borderWidth = isFilled and 0 or 1,
            borderColor = emptyBorder,
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
            -- 设计图左侧：AP 圆形标签 + 数字（接入 era_accent）
            UI.Panel {
                width = 32, height = 32,
                borderRadius = 16,
                backgroundColor = C.paper_dark,
                borderWidth = 1,
                borderColor = era.accent,
                justifyContent = "center",
                alignItems = "center",
                marginRight = 6,
                children = {
                    UI.Label {
                        text = "AP",
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = era.accent,
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
                        text = string.format("%d / %d", totalAvail, apMax),
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

            -- [+] 按钮（§4.2 获取额外AP，32x32，圆角4px，era_accent 边框）
            -- 功能：消耗 Balance.AP_PURCHASE.cost_per_ap 现金 +1 temp AP，本季最多 max_per_season 次
            UI.Panel {
                width = 32, height = 32,
                borderRadius = S.radius_btn,
                backgroundColor = C.paper_dark,
                borderWidth = 1,
                borderColor = era.accent,
                justifyContent = "center",
                alignItems = "center",
                marginHorizontal = S.spacing_sm,
                pointerEvents = "auto",
                onPointerUp = function(self)
                    TopBar._OnBuyAP()
                end,
                children = {
                    UI.Label {
                        text = "+",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = era.accent,
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
    local era = Config.GetEraByYear(state.year)

    local yearLabel = root:FindById("yearLabel")
    if yearLabel then
        yearLabel:SetText(string.format("%d年 Q%d %s季",
            state.year, state.quarter, Config.QUARTER_NAMES[state.quarter]))
        if yearLabel.SetFontColor then yearLabel:SetFontColor(era.accent) end
    end

    local dateLabel = root:FindById("dateLabel")
    if dateLabel then
        dateLabel:SetText(Config.QUARTER_DATES[state.quarter] or "")
    end

    -- 时代标签刷新（跨章切换时自动更新）
    local eraLabel = root:FindById("eraLabel")
    if eraLabel then
        eraLabel:SetText(era.label)
        if eraLabel.SetFontColor then
            eraLabel:SetFontColor({ era.accent[1], era.accent[2], era.accent[3], 180 })
        end
    end

    local cashVal = root:FindById("cashCell_val")
    if cashVal then
        cashVal:SetText(Config.FormatNumber(state.cash))
        if cashVal.SetFontColor then cashVal:SetFontColor(era.accent) end
    end

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
    local totalAvail = state.ap.current + (state.ap.temp or 0)
    if apLabel then
        apLabel:SetText(string.format("%d / %d", totalAvail, state.ap.max))
    end

    -- 刷新 AP 圆点（含临时 AP）
    local apDots = root:FindById("apDots")
    if apDots then
        apDots:ClearChildren()
        local apMax = state.ap.max
        local tempAP = state.ap.temp or 0
        local totalDots = apMax + tempAP  -- 临时 AP 额外显示圆点
        for i = 1, totalDots do
            local isFilled = (i <= totalAvail)
            local isTemp = (i > apMax)  -- 超出 max 的属于临时 AP
            local emptyBorder = { era.accent[1], era.accent[2], era.accent[3], 89 }
            local fillColor
            if isFilled then
                fillColor = isTemp
                    and { era.accent[1], era.accent[2], era.accent[3], 160 }  -- 临时 AP 半透明
                    or era.accent
            else
                fillColor = { 0, 0, 0, 0 }
            end
            apDots:AddChild(UI.Panel {
                width = S.ap_dot_size,
                height = S.ap_dot_size,
                borderRadius = S.ap_dot_size / 2,
                backgroundColor = fillColor,
                borderWidth = isFilled and 0 or 1,
                borderColor = emptyBorder,
            })
        end
    end
end

-- ============================================================================
-- AP 购买处理
-- ============================================================================
function TopBar._OnBuyAP()
    if not stateRef_ then return end
    local cfg = Balance.AP_PURCHASE
    local used = stateRef_.ap.bonus_used or 0
    if used >= cfg.max_per_season then
        UI.Toast.Show("本季已达最大购买次数（" .. cfg.max_per_season .. "）",
            { variant = "warning", duration = 1.5 })
        return
    end
    if stateRef_.cash < cfg.cost_per_ap then
        UI.Toast.Show("资金不足（需要 " .. cfg.cost_per_ap .. " 克朗）",
            { variant = "error", duration = 1.5 })
        return
    end
    stateRef_.cash = stateRef_.cash - cfg.cost_per_ap
    stateRef_.ap.temp = (stateRef_.ap.temp or 0) + 1
    stateRef_.ap.bonus_used = used + 1
    GameState.AddLog(stateRef_, string.format("购买 1 AP（花费 %d）", cfg.cost_per_ap))
    UI.Toast.Show("+1 AP", { variant = "success", duration = 1.2 })
    if onStateChanged_ then onStateChanged_() end
end

return TopBar
