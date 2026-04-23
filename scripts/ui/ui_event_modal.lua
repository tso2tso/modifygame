-- ============================================================================
-- 事件弹窗 UI：显示事件内容，让玩家选择应对策略
-- 设计规范：sarajevo_dynasty_ui_spec §4.8 面板类型 3
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")

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
function EventModal.Show(event, onChoose)
    onChoose_ = onChoose

    -- 关闭已有弹窗
    if modal_ then
        modal_:Close()
        modal_ = nil
    end

    -- §4.8 面板类型 3：选项列表（单选）
    local optionWidgets = {}
    for i, option in ipairs(event.options) do
        -- 效果提示文本及颜色（§4.8 代价：绿色正面/红色负面/灰色中性）
        local effectHints, effectColor = EventModal._FormatEffects(option.effects or {})

        table.insert(optionWidgets, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = C.border_card,
            flexDirection = "column",
            gap = 4,
            pointerEvents = "auto",
            onPointerUp = (function(idx)
                return function(self)
                    EventModal._OnChoose(idx)
                end
            end)(i),
            children = {
                -- §4.8 主文字（13px）
                UI.Label {
                    text = string.format("%d. %s", i, option.text),
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                    whiteSpace = "normal",
                    lineHeight = 1.3,
                    pointerEvents = "none",
                },
                -- §4.8 副文字代价（12px --text-secondary）
                UI.Label {
                    text = option.desc or "",
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
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
    local contentPanel = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 12,
        padding = 4,
        children = {
            -- 事件描述
            UI.Label {
                text = event.desc,
                fontSize = F.body,
                fontColor = C.text_primary,
                whiteSpace = "normal",
                lineHeight = 1.6,
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
    modal_:AddContent(contentPanel)

    -- Modal 必须加入 UI 树才能渲染
    if uiRoot_ then
        uiRoot_:AddChild(modal_)
    end
    -- 打开
    modal_:Open()
end

--- 格式化效果提示（§4.8 代价颜色：绿色正面/红色负面/灰色中性）
---@return string hints, table color
function EventModal._FormatEffects(effects)
    local hints = {}
    local hasPositive = false
    local hasNegative = false

    if effects.cash then
        local prefix = effects.cash >= 0 and "+" or ""
        table.insert(hints, string.format("💰 %s%d", prefix, effects.cash))
        if effects.cash > 0 then hasPositive = true end
        if effects.cash < 0 then hasNegative = true end
    end
    if effects.gold then
        local prefix = effects.gold >= 0 and "+" or ""
        table.insert(hints, string.format("🥇 %s%d", prefix, effects.gold))
        if effects.gold > 0 then hasPositive = true end
        if effects.gold < 0 then hasNegative = true end
    end
    if effects.workers_bonus then
        table.insert(hints, string.format("👷 +%d 工人", effects.workers_bonus))
        hasPositive = true
    end
    if effects.security_bonus then
        local prefix = effects.security_bonus >= 0 and "+" or ""
        table.insert(hints, string.format("🛡️ 治安 %s%d", prefix, effects.security_bonus))
        if effects.security_bonus > 0 then hasPositive = true end
        if effects.security_bonus < 0 then hasNegative = true end
    end

    -- 修正器提示
    if effects.modifiers then
        for _, mod in ipairs(effects.modifiers) do
            if mod.target == "mine_output" and mod.value ~= 0 then
                local prefix = mod.value > 0 and "+" or ""
                local dur = mod.duration > 0 and string.format(" (%d季)", mod.duration) or ""
                table.insert(hints, string.format("⛏️ 产出 %s%d%s", prefix, mod.value, dur))
                if mod.value > 0 then hasPositive = true else hasNegative = true end
            elseif mod.target == "worker_morale" and mod.value ~= 0 then
                local prefix = mod.value > 0 and "+" or ""
                table.insert(hints, string.format("💪 士气 %s%d", prefix, mod.value))
                if mod.value > 0 then hasPositive = true else hasNegative = true end
            end
        end
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
