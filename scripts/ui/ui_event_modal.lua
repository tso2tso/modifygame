-- ============================================================================
-- 事件弹窗 UI：显示事件内容，让玩家选择应对策略
-- 设计规范：sarajevo_dynasty_ui_spec §4.8 面板类型 3
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")

local AudioManager = require("systems.audio_manager")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local EventModal = {}

---@type table|nil 当前 Modal 实例
local modal_ = nil
---@type function|nil 选择回调 (optionIndex)
local onChoose_ = nil
---@type table|nil UI 根节点引用
local uiRoot_ = nil

--- 设置 UI 根节点（Modal 必须 AddChild 到 UI 树才能渲染）
function EventModal.SetRoot(root)
    uiRoot_ = root
end

--- 显示事件弹窗
---@param event table 事件数据
---@param onChoose function(optionIndex) 选择回调
---@param state table|nil 游戏状态（用于通胀系数修正显示）
function EventModal.Show(event, onChoose, state)
    onChoose_ = onChoose
    AudioManager.PlayEffect("event_trigger")

    -- 关闭已有弹窗
    if modal_ then
        modal_:Close()
        modal_ = nil
    end

    -- §4.8 面板类型 3：选项列表（单选）
    local optionWidgets = {}
    for i, option in ipairs(event.options) do
        -- 效果提示文本及颜色（§4.8 代价：绿色正面/红色负面/灰色中性）
        local effectHints, effectColor = EventModal._FormatEffects(option.effects or {}, state)

        -- 分支事件：选项可能因条件不满足而不可选
        local isAvailable = (option._available == nil) or (option._available == true)
        local bgColor = isAvailable and C.bg_elevated or {60, 55, 50, 255}
        local textColor = isAvailable and C.text_primary or {120, 110, 100, 255}
        local descColor = isAvailable and C.text_secondary or {100, 95, 88, 255}

        table.insert(optionWidgets, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = bgColor,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = isAvailable and C.border_card or {80, 75, 70, 180},
            flexDirection = "column",
            gap = 4,
            pointerEvents = "auto",
            opacity = isAvailable and 1.0 or 0.6,
            onPointerUp = (function(idx, avail)
                return Config.TapGuard(function(self)
                    if not avail then
                        UI.Toast.Show("条件不满足，无法选择此选项",
                            { variant = "warning", duration = 1.5 })
                        return
                    end
                    EventModal._OnChoose(idx)
                end)
            end)(i, isAvailable),
            children = {
                -- §4.8 主文字（13px）
                UI.Label {
                    text = string.format("%d. %s", i, option.text),
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = textColor,
                    whiteSpace = "normal",
                    lineHeight = 1.3,
                    pointerEvents = "none",
                },
                -- §4.8 副文字代价（12px --text-secondary）
                UI.Label {
                    text = option.desc or "",
                    fontSize = F.body_minor,
                    fontColor = descColor,
                    whiteSpace = "normal",
                    pointerEvents = "none",
                },
                -- 效果提示（代价颜色规则）
                UI.Label {
                    text = effectHints,
                    fontSize = F.label,
                    fontColor = effectColor,
                    whiteSpace = "normal",
                    lineHeight = 1.3,
                    pointerEvents = "none",
                },
            },
        })
    end

    -- 创建弹窗
    modal_ = UI.Modal {
        title = (event.icon or "") .. " " .. event.title,
        size = "md",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
    }

    -- 内容区
    local contentChildren = {}

    -- 事件插图（如有）
    if event.image then
        table.insert(contentChildren, UI.Panel {
            width = "100%",
            aspectRatio = 16 / 9,
            borderRadius = S.radius_card,
            overflow = "hidden",
            backgroundImage = event.image,
            backgroundFit = "cover",
            marginBottom = 4,
            flexShrink = 0,
            children = {
                -- 底部渐变遮罩
                UI.Panel {
                    position = "absolute",
                    left = 0, right = 0, bottom = 0, height = 50,
                    backgroundColor = { 0, 0, 0, 100 },
                },
            },
        })
    end

    -- 事件描述
    table.insert(contentChildren, UI.Label {
        text = event.desc,
        fontSize = F.body,
        fontColor = C.text_primary,
        whiteSpace = "normal",
        lineHeight = 1.6,
    })

    local contentPanel = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 12,
        padding = 4,
        children = {
            -- 插图 + 描述（已动态插入 contentChildren）
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                children = contentChildren,
            },
            -- 分隔线
            UI.Divider { color = C.divider },
            -- §4.8 副标题"选择你的应对方式"（12px --text-secondary）
            UI.Label {
                text = "选择你的应对方式：",
                fontSize = F.body_minor,
                fontWeight = "bold",
                fontColor = C.text_secondary,
            },
            -- 选项列表
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                children = optionWidgets,
            },
        },
    }

    -- 用 ScrollView 包裹内容，防止选项溢出不可选
    local scrollContent = UI.ScrollView {
        width = "100%",
        maxHeight = 480,
        flexShrink = 1,
        scrollY = true,
        bounces = false,
        children = { contentPanel },
    }
    modal_:AddContent(scrollContent)

    -- Modal 必须加入 UI 树才能渲染
    if uiRoot_ then
        uiRoot_:AddChild(modal_)
    end
    -- 打开
    modal_:Open()
end

--- 格式化效果提示（§4.8 代价颜色：绿色正面/红色负面/灰色中性）
---@return string hints, table color
function EventModal._FormatEffects(effects, state)
    local hints = {}
    local hasPositive = false
    local hasNegative = false

    if effects.cash then
        local inflationFactor = (state and state.inflation_factor) or 1.0
        local displayCash = math.floor(effects.cash * inflationFactor)
        local prefix = displayCash >= 0 and "+" or ""
        table.insert(hints, string.format("💰 %s%d", prefix, displayCash))
        if displayCash > 0 then hasPositive = true end
        if displayCash < 0 then hasNegative = true end
    end
    if effects.gold then
        local prefix = effects.gold >= 0 and "+" or ""
        table.insert(hints, string.format("🥇 %s%d", prefix, effects.gold))
        if effects.gold > 0 then hasPositive = true end
        if effects.gold < 0 then hasNegative = true end
    end
    if effects.workers_bonus then
        local prefix = effects.workers_bonus >= 0 and "+" or ""
        table.insert(hints, string.format("👷 %s%d 工人", prefix, effects.workers_bonus))
        if effects.workers_bonus > 0 then hasPositive = true end
        if effects.workers_bonus < 0 then hasNegative = true end
    end
    if effects.security_bonus then
        local prefix = effects.security_bonus >= 0 and "+" or ""
        table.insert(hints, string.format("🛡️ 治安 %s%d", prefix, effects.security_bonus))
        if effects.security_bonus > 0 then hasPositive = true end
        if effects.security_bonus < 0 then hasNegative = true end
    end

    -- 直接效果：黄金储备
    if effects.gold_reserve and effects.gold_reserve ~= 0 then
        local prefix = effects.gold_reserve >= 0 and "+" or ""
        table.insert(hints, string.format("🪙 储备 %s%d", prefix, effects.gold_reserve))
        if effects.gold_reserve > 0 then hasPositive = true end
        if effects.gold_reserve < 0 then hasNegative = true end
    end
    -- 直接效果：通胀变化
    if effects.inflation_delta and effects.inflation_delta ~= 0 then
        local pct = math.floor(effects.inflation_delta * 100 + 0.5)
        local prefix = pct >= 0 and "+" or ""
        table.insert(hints, string.format("📊 通胀 %s%d%%", prefix, pct))
        if pct > 0 then hasNegative = true end
        if pct < 0 then hasPositive = true end
    end
    -- 直接效果：战争状态
    if effects.war_state ~= nil then
        if effects.war_state then
            table.insert(hints, "⚔️ 进入战争状态")
            hasNegative = true
        else
            table.insert(hints, "🕊️ 战争结束")
            hasPositive = true
        end
    end

    -- 修正器提示
    if effects.modifiers then
        --- 修正器显示映射
        local modDisplay = {
            mine_output_mult       = { icon = "⛏️", label = "产出",   pct = true },
            worker_morale          = { icon = "💪", label = "士气",   pct = false },
            tax_rate               = { icon = "📋", label = "税率",   pct = true, invert = true },
            transport_risk         = { icon = "🚚", label = "运输风险", pct = true, invert = true },
            shadow_income          = { icon = "🌑", label = "暗收入", pct = false },
            corruption_risk        = { icon = "💀", label = "腐败",   pct = false, invert = true },
            worker_cost_multiplier = { icon = "💸", label = "工资成本", pct = true, invert = true },
            military_industry_profit = { icon = "🏭", label = "军工利润", pct = true },
            civilian_consumption   = { icon = "🛒", label = "民用消费", pct = true },
            political_standing     = { icon = "🏛️", label = "政治",   pct = false },
            legitimacy             = { icon = "📜", label = "合法性", pct = false },
            public_support         = { icon = "👥", label = "民心",   pct = false },
            independence           = { icon = "🗽", label = "独立性", pct = false },
            foreign_control        = { icon = "🌐", label = "外资控制", pct = false, invert = true },
            local_relations        = { icon = "🤝", label = "地方关系", pct = false },
            total_assets           = { icon = "💎", label = "总资产", pct = false },
            foreign_assets         = { icon = "🌍", label = "海外资产", pct = false },
            tech_bonus             = { icon = "🔬", label = "科技",   pct = false },
            worker_wage            = { icon = "💰", label = "永久工资", pct = false },
            security               = { icon = "🛡️", label = "区域治安", pct = false },
            trade_income_mult      = { icon = "📦", label = "贸易收入", pct = true },
            local_reputation       = { icon = "📣", label = "本地声誉", pct = false },
            risk                   = { icon = "⚠️", label = "风险",   pct = false, invert = true },
            railway_blocked        = { icon = "🚂", label = "铁路封锁", pct = false, invert = true },
        }
        for _, mod in ipairs(effects.modifiers) do
            if mod.value ~= 0 then
                local info = modDisplay[mod.target]
                if info then
                    local dur = (mod.duration and mod.duration > 0) and string.format(" (%d季)", mod.duration) or ""
                    local display
                    if info.pct then
                        local pctVal = math.floor(mod.value * 100 + 0.5)
                        local prefix = pctVal >= 0 and "+" or ""
                        display = string.format("%s %s %s%d%%%s", info.icon, info.label, prefix, pctVal, dur)
                    else
                        local prefix = mod.value >= 0 and "+" or ""
                        display = string.format("%s %s %s%g%s", info.icon, info.label, prefix, mod.value, dur)
                    end
                    table.insert(hints, display)
                    -- 判断正负面：invert 的指标，数值越大越"负面"
                    if info.invert then
                        if mod.value > 0 then hasNegative = true else hasPositive = true end
                    else
                        if mod.value > 0 then hasPositive = true else hasNegative = true end
                    end
                end
            end
        end
    end

    -- 合作分数（分支事件）
    if effects.collaboration_score and effects.collaboration_score ~= 0 then
        local prefix = effects.collaboration_score > 0 and "+" or ""
        table.insert(hints, string.format("🤝 合作度 %s%d", prefix, effects.collaboration_score))
        if effects.collaboration_score > 0 then hasNegative = true end  -- 合作是"负面"（偏向占领方）
        if effects.collaboration_score < 0 then hasPositive = true end  -- 抵抗是"正面"
    end

    if #hints == 0 then
        return "无直接资源变化", C.text_muted
    end

    -- §4.8 代价颜色规则
    local color = C.text_muted  -- 中性灰色
    if hasPositive and not hasNegative then
        color = C.accent_green  -- 正面绿色
    elseif hasNegative and not hasPositive then
        color = C.accent_red    -- 负面红色
    elseif hasPositive and hasNegative then
        color = C.accent_amber  -- 混合琥珀
    end

    return table.concat(hints, "  "), color
end

--- 选择回调
function EventModal._OnChoose(optionIndex)
    AudioManager.PlayEffect("event_choose")
    if modal_ then
        modal_:Close()
        modal_:Destroy()
        modal_ = nil
    end
    if onChoose_ then
        onChoose_(optionIndex)
    end
end

--- 关闭弹窗（外部调用）
function EventModal.Close()
    if modal_ then
        modal_:Close()
        modal_:Destroy()
        modal_ = nil
    end
end

--- 是否正在显示
function EventModal.IsShowing()
    return modal_ ~= nil
end

return EventModal
