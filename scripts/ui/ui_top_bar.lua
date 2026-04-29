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
---@type function|nil
local onHome_ = nil
---@type function|nil 状态变化回调（重操作：结束回合等触发页面重建）
local onStateChanged_ = nil
---@type function|nil 轻量刷新回调（仅 TopBar，AP 购买等高频操作）
local onTopBarRefresh_ = nil
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
    onHome_ = callbacks and callbacks.onHome
    onStateChanged_ = callbacks and callbacks.onStateChanged
    onTopBarRefresh_ = callbacks and callbacks.onTopBarRefresh
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
        paddingTop = 3,
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
    -- 年份+季节（主标题行）: 1904年 春
    local seasonChar = ({ "春", "夏", "秋", "冬" })[state.quarter] or "春"
    local yearText = string.format("%d年 %s", state.year, seasonChar)
    -- 日期+时代（副文字行）
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
            -- §4.1 左侧核心资源组
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "flex-start",
                gap = 4,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        backgroundColor = C.bg_inset,
                        borderRadius = S.radius_card,
                        borderWidth = 1,
                        borderColor = C.border_soft,
                        paddingHorizontal = 4,
                        paddingVertical = 4,
                        gap = 2,
                        flexShrink = 1,
                        children = {
                            TopBar._ResourceCell("cashCell", "💰",
                                Config.FormatNumber(state.cash), era.accent, "现金"),
                            UI.Panel {
                                id = "luckyAdBtn",
                                width = 24, height = 24,
                                borderRadius = 12,
                                backgroundColor = { era.accent[1], era.accent[2], era.accent[3], 36 },
                                borderWidth = 1,
                                borderColor = { era.accent[1], era.accent[2], era.accent[3], 120 },
                                justifyContent = "center",
                                alignItems = "center",
                                pointerEvents = "auto",
                                onPointerUp = Config.TapGuard(function(self)
                                    TopBar._OnWatchAd()
                                end),
                                children = {
                                    UI.Label {
                                        text = "🎰",
                                        fontSize = 13,
                                        textAlign = "center",
                                        pointerEvents = "none",
                                    },
                                },
                            },
                            TopBar._ResourceCell("goldCell", "●",
                                tostring(state.gold), C.text_primary, "黄金"),
                            TopBar._ResourceCell("prodCell", "⛏",
                                tostring(production), C.text_primary, "产能"),
                            TopBar._ResourceCell("repCell", "★",
                                tostring(reputation), C.text_primary, "声望"),
                        },
                    },
                    (function()
                        local totalAssets = GameState.CalcTotalAssets(state)
                        local totalDebt = GameState.CalcTotalDebt(state)
                        local netWorth = totalAssets - totalDebt
                        local nwColor = netWorth < 0 and C.accent_red or C.accent_green
                        return TopBar._ResourceCell("netWorthCell", "🏦",
                            Config.FormatNumber(netWorth), nwColor, "净资产", true)
                    end)(),
                },
            },

            -- 年份 + 日期/时代（右侧时间信息区）
            UI.Panel {
                flexDirection = "column",
                flexShrink = 0,
                alignItems = "flex-end",
                gap = 2,
                children = {
                    UI.Label {
                        id = "yearLabel",
                        text = yearText,
                        fontSize = F.page_title,
                        fontWeight = "bold",
                        fontColor = era.accent,
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label {
                                id = "dateLabel",
                                text = dateText,
                                fontSize = F.body_minor,
                                fontColor = C.text_secondary,
                            },
                            UI.Label {
                                id = "eraLabel",
                                text = era.label,
                                fontSize = 10,
                                fontColor = { era.accent[1], era.accent[2], era.accent[3], 180 },
                            },
                        },
                    },
                },
            },
        },
    }
end

--- §4.1 资源格：图标16px + 数值16px bold + 标签11px text_secondary
function TopBar._ResourceCell(id, icon, valueText, valueColor, label, framed)
    return UI.Panel {
        id = id,
        flexDirection = "column",
        alignItems = "center",
        gap = 1,
        paddingHorizontal = framed and 6 or 4,
        paddingVertical = framed and 4 or 0,
        backgroundColor = framed and C.bg_inset or nil,
        borderRadius = framed and S.radius_card or nil,
        borderWidth = framed and 1 or 0,
        borderColor = framed and C.border_soft or nil,
        flexShrink = 0,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 2,
                children = {
                    UI.Label {
                        text = icon,
                        fontSize = framed and 13 or 12,
                        fontColor = valueColor or C.text_primary,
                    },
                    UI.Label {
                        id = id .. "_val",
                        text = valueText,
                        fontSize = framed and F.body_minor or F.label,
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
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                backgroundColor = C.bg_inset,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = C.border_soft,
                paddingHorizontal = 8,
                paddingVertical = 5,
                gap = 7,
                children = {
                    UI.Panel {
                        width = 28, height = 28,
                        borderRadius = 14,
                        backgroundColor = C.paper_dark,
                        borderWidth = 1,
                        borderColor = era.accent,
                        justifyContent = "center",
                        alignItems = "center",
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
                    UI.Panel {
                        flexDirection = "column",
                        children = {
                            UI.Label {
                                id = "apCountLabel",
                                text = string.format("%d / %d", totalAvail, apMax),
                                fontSize = F.card_title,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = "本季行动点",
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                        },
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
                marginLeft = 10,
                children = dots,
            },

            -- [+] 按钮（§4.2 获取额外AP，36x36触控友好，圆角4px，era_accent 边框）
            -- 功能：消耗 Balance.AP_PURCHASE.cost_per_ap 现金 +1 temp AP，本季最多 max_per_season 次
            UI.Panel {
                width = 36, height = 36,
                borderRadius = S.radius_btn,
                backgroundColor = C.paper_dark,
                borderWidth = 1,
                borderColor = era.accent,
                justifyContent = "center",
                alignItems = "center",
                marginRight = S.spacing_sm,
                pointerEvents = "auto",
                onPointerUp = Config.TapGuard(function(self)
                    TopBar._OnBuyAP()
                end),
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

            -- ⚙ 设置按钮（与 [+] 按钮同尺寸 36×36）
            UI.Panel {
                width = 36, height = 36,
                borderRadius = S.radius_btn,
                backgroundColor = C.paper_dark,
                borderWidth = 1,
                borderColor = era.accent,
                justifyContent = "center",
                alignItems = "center",
                marginRight = S.spacing_sm,
                pointerEvents = "auto",
                onPointerUp = Config.TapGuard(function(self)
                    if onSettings_ then onSettings_() end
                end),
                children = {
                    UI.Label {
                        text = "⚙",
                        fontSize = 17,
                        fontColor = era.accent,
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                },
            },

            -- 🏠 主页按钮（返回首页仪表盘，与设置按钮同尺寸 36×36）
            UI.Panel {
                width = 36, height = 36,
                borderRadius = S.radius_btn,
                backgroundColor = C.paper_dark,
                borderWidth = 1,
                borderColor = era.accent,
                justifyContent = "center",
                alignItems = "center",
                marginRight = S.spacing_sm,
                pointerEvents = "auto",
                onPointerUp = Config.TapGuard(function(self)
                    if onHome_ then onHome_() end
                end),
                children = {
                    UI.Label {
                        text = "🏠",
                        fontSize = 15,
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
                        fontSize = 10,
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
        local seasonChar = ({ "春", "夏", "秋", "冬" })[state.quarter] or "春"
        yearLabel:SetText(string.format("%d年 %s", state.year, seasonChar))
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

    -- 净资产刷新
    local totalAssets = GameState.CalcTotalAssets(state)
    local totalDebt = GameState.CalcTotalDebt(state)
    local netWorth = totalAssets - totalDebt
    local nwVal = root:FindById("netWorthCell_val")
    if nwVal then
        nwVal:SetText(Config.FormatNumber(netWorth))
        if nwVal.SetFontColor then
            nwVal:SetFontColor(netWorth < 0 and C.accent_red or C.accent_green)
        end
    end

    local apLabel = root:FindById("apCountLabel")
    local totalAvail = state.ap.current + (state.ap.temp or 0)
    if apLabel then
        apLabel:SetText(string.format("%d / %d", totalAvail, state.ap.max))
    end

    -- 刷新 AP 圆点（增量更新：复用已有圆点，避免 ClearChildren 闪烁）
    local apDots = root:FindById("apDots")
    if apDots then
        local apMax = state.ap.max
        local tempAP = state.ap.temp or 0
        local totalDots = apMax + tempAP

        local existing = apDots:GetChildren()
        local existCount = existing and #existing or 0

        -- 移除多余圆点（从末尾开始）
        while existCount > totalDots do
            existing[existCount]:Destroy()
            existCount = existCount - 1
        end

        -- 更新已有圆点 + 添加缺少的圆点
        for i = 1, totalDots do
            local isFilled = (i <= totalAvail)
            local isTemp = (i > apMax)
            local emptyBorder = { era.accent[1], era.accent[2], era.accent[3], 89 }
            local fillColor
            if isFilled then
                fillColor = isTemp
                    and { era.accent[1], era.accent[2], era.accent[3], 160 }
                    or era.accent
            else
                fillColor = { 0, 0, 0, 0 }
            end

            if i <= existCount then
                -- 复用已有圆点，只更新样式
                existing[i]:SetStyle({
                    backgroundColor = fillColor,
                    borderWidth = isFilled and 0 or 1,
                    borderColor = emptyBorder,
                })
            else
                -- 新增圆点
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
    if onTopBarRefresh_ then onTopBarRefresh_()
    elseif onStateChanged_ then onStateChanged_() end
end

-- ============================================================================
-- 看广告 → 幸运事件
-- ============================================================================
function TopBar._OnWatchAd()
    if not stateRef_ then return end
    local lucky = Balance.LUCKY_EVENT
    -- 本季次数限制
    local watched = stateRef_.lucky_ad_watched or 0
    if watched >= lucky.max_per_season then
        UI.Toast.Show("本季运气已用尽（最多 " .. lucky.max_per_season .. " 次）",
            { variant = "warning", duration = 1.5 })
        return
    end

    -- 调用 SDK 激励视频广告
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

        -- 广告成功，发放幸运奖励
        stateRef_.lucky_ad_watched = (stateRef_.lucky_ad_watched or 0) + 1
        local decay = stateRef_.lucky_ad_decay or 1.0

        -- 加权随机抽档
        local totalWeight = 0
        for _, tier in ipairs(lucky.tiers) do
            totalWeight = totalWeight + tier.weight * decay
        end
        local roll = math.random() * totalWeight
        local chosen = lucky.tiers[1]  -- 兜底
        local acc = 0
        for _, tier in ipairs(lucky.tiers) do
            acc = acc + tier.weight * decay
            if roll <= acc then
                chosen = tier
                break
            end
        end

        -- 通胀浮动金额；同一季度连续观看会按 lucky_ad_decay 衰减实际奖金
        local inflation = GameState.GetInflationFactor(stateRef_)
        local amount = math.floor(chosen.base * inflation * decay)

        -- 发放奖励
        stateRef_.cash = stateRef_.cash + amount
        stateRef_.total_income = (stateRef_.total_income or 0) + amount

        -- 衰减概率（下次更难抽到高额）
        stateRef_.lucky_ad_decay = math.max(lucky.decay_min,
            decay * lucky.decay_factor)

        -- 日志 & 提示
        GameState.AddLog(stateRef_, string.format(
            "🎰 %s：获得 %s 克朗", chosen.label, Config.FormatNumber(amount)))
        UI.Toast.Show(string.format("🎰 %s\n+%s 克朗！",
            chosen.label, Config.FormatNumber(amount)),
            { variant = "success", duration = 2.5 })

        -- 刷新 UI
        if onStateChanged_ then onStateChanged_() end
    end)
end

return TopBar
