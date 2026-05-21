-- ============================================================================
-- 结算弹窗 UI：胜利/失败后的对局总结
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local AudioManager = require("systems.audio_manager")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local EndingModal = {}

---@type table|nil 当前 Modal 实例
local modal_ = nil
---@type table|nil UI 根节点引用
local uiRoot_ = nil
---@type function|nil 新游戏回调
local onNewGame_ = nil
---@type function|nil 新游戏请求回调（先展示 Loading，再创建状态）
local onNewGameRequested_ = nil
---@type function|nil 状态变化回调
local onStateChanged_ = nil

--- 设置 UI 根节点
---@param root table
function EndingModal.SetRoot(root)
    uiRoot_ = root
end

--- 设置外部回调
---@param callbacks table|nil
function EndingModal.SetCallbacks(callbacks)
    onNewGame_ = callbacks and callbacks.onNewGame
    onNewGameRequested_ = callbacks and callbacks.onNewGameRequested
    onStateChanged_ = callbacks and callbacks.onStateChanged
end

local function VictoryTypeName(victoryType)
    if victoryType == "economic" then
        return "经济胜利"
    elseif victoryType == "military" then
        return "军事胜利"
    elseif victoryType == "dominance" then
        return "统治胜利"
    end
    return "胜利"
end

--- 显示结算弹窗
---@param state table
function EndingModal.Show(state)
    local ending = GameState.GetEndingInfo(state)
    if not ending then return end

    EndingModal.Close()

    -- 播放结算 BGM
    if ending.variant == "success" then
        AudioManager.PlayBGM("bgm_victory")
    else
        AudioManager.PlayBGM("bgm_defeat")
    end

    modal_ = UI.Modal {
        title = ending.icon .. " " .. ending.title,
        size = "fullscreen",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = true,
    }

    modal_:AddContent(EndingModal._CreateContent(state, ending))

    if uiRoot_ then
        uiRoot_:AddChild(modal_)
    end
    modal_:Open()
end

function EndingModal.ShowVictoryPrompt(state)
    local prompt = state and state.victory and state.victory.prompt_pending
    if not prompt then return end

    EndingModal.Close()

    local standing = GameState.GetVictoryStanding(state)
    local victoryName = VictoryTypeName(prompt.type)
    modal_ = UI.Modal {
        title = "可宣布" .. victoryName,
        size = "md",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
    }

    modal_:AddContent(UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 10,
        children = {
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = C.accent_gold,
                flexDirection = "column",
                gap = 6,
                children = {
                    UI.Label {
                        text = victoryName,
                        fontSize = F.super_title,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = string.format("你已领先最强 AI %d 点（目标领先 %d）。可以宣布胜利，也可以继续经营到 1955 年终局。",
                            prompt.lead or 0, prompt.margin or 0),
                        fontSize = F.body,
                        fontColor = C.text_secondary,
                        textAlign = "center",
                        whiteSpace = "normal",
                        lineHeight = 1.4,
                    },
                    UI.Divider { color = C.divider },
                    EndingModal._ProgressRow({
                        label = "经济领先",
                        value = standing.lead.economic,
                        threshold = ((Balance.VICTORY.relative.lead_margin or {}).economic) or 200,
                    }, C.accent_gold),
                    EndingModal._ProgressRow({
                        label = "军事领先",
                        value = standing.lead.military,
                        threshold = ((Balance.VICTORY.relative.lead_margin or {}).military) or 250,
                    }, C.accent_red),
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 8,
                children = {
                    EndingModal._Button("暂不宣布", C.bg_elevated, C.text_primary, function()
                        GameState.DismissVictoryPrompt(state)
                        EndingModal.Close()
                        if onStateChanged_ then onStateChanged_() end
                    end),
                    EndingModal._Button("宣布胜利并继续", C.accent_gold, { 30, 25, 15, 255 }, function()
                        GameState.ClaimVictory(state, prompt.type)
                        EndingModal.Close()
                        UI.Toast.Show(victoryName .. "已记录，游戏继续", { variant = "success", duration = 2.5 })
                        if onStateChanged_ then onStateChanged_() end
                    end),
                },
            },
        },
    })

    if uiRoot_ then
        uiRoot_:AddChild(modal_)
    end
    modal_:Open()
end

function EndingModal._CreateContent(state, ending)
    local accent = EndingModal._GetAccent(ending)

    local statRows = {}
    for i = 1, #ending.stats, 2 do
        table.insert(statRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            children = {
                EndingModal._StatCell(ending.stats[i].label, ending.stats[i].value),
                ending.stats[i + 1] and EndingModal._StatCell(ending.stats[i + 1].label,
                    ending.stats[i + 1].value) or UI.Panel { flexGrow = 1, flexBasis = 0 },
            },
        })
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 12,
        padding = 4,
        children = {
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = accent,
                flexDirection = "column",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = ending.resultLabel,
                        fontSize = F.body_minor,
                        fontWeight = "bold",
                        fontColor = accent,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = ending.title,
                        fontSize = F.super_title,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                    UI.Label {
                        text = ending.subtitle,
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = ending.description,
                        fontSize = F.body,
                        fontColor = C.text_primary,
                        textAlign = "center",
                        whiteSpace = "normal",
                        lineHeight = 1.5,
                    },
                },
            },

            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.bg_surface,
                borderRadius = S.radius_card,
                flexDirection = "column",
                gap = 8,
                children = {
                    UI.Label {
                        text = "胜利进度",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    EndingModal._ProgressRow(ending.progress.economic, C.accent_gold),
                    EndingModal._ProgressRow(ending.progress.military, C.accent_red),
                },
            },

            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.bg_surface,
                borderRadius = S.radius_card,
                flexDirection = "column",
                gap = 8,
                children = EndingModal._WithTitle("结算统计", statRows),
            },

            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 8,
                children = {
                    EndingModal._Button("留在结算", C.bg_elevated, C.text_primary, function()
                        EndingModal.Close()
                    end),
                    EndingModal._Button("开始新游戏", accent, { 30, 25, 15, 255 }, function()
                        EndingModal._StartNewGame()
                    end),
                },
            },
        },
    }
end

function EndingModal._WithTitle(title, children)
    local result = {
        UI.Label {
            text = title,
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_primary,
        },
    }
    for _, child in ipairs(children) do
        table.insert(result, child)
    end
    return result
end

function EndingModal._StatCell(label, value)
    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        minWidth = 0,
        padding = 8,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_btn,
        flexDirection = "column",
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = value,
                fontSize = F.data_small,
                fontWeight = "bold",
                fontColor = C.text_primary,
                textAlign = "center",
                flexShrink = 1,
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
                textAlign = "center",
                flexShrink = 1,
            },
        },
    }
end

function EndingModal._ProgressRow(progress, color)
    local value = progress.value or 0
    local threshold = math.max(1, progress.threshold or 1)
    local pct = math.max(0, math.min(100, math.floor(value / threshold * 100)))

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = progress.label,
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                    },
                    UI.Label {
                        text = string.format("%d / %d", value, threshold),
                        fontSize = F.body_minor,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                height = 8,
                backgroundColor = C.paper_mid,
                borderRadius = 4,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = pct .. "%",
                        height = 8,
                        backgroundColor = color,
                        borderRadius = 4,
                    },
                },
            },
        },
    }
end

function EndingModal._Button(text, bgColor, textColor, onClick)
    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        height = S.btn_height,
        backgroundColor = bgColor,
        borderRadius = S.radius_btn,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onPointerUp = Config.TapGuard(function(self)
            if onClick then onClick() end
        end),
        children = {
            UI.Label {
                text = text,
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = textColor,
                pointerEvents = "none",
            },
        },
    }
end

function EndingModal._GetAccent(ending)
    if ending.variant == "success" then
        return C.accent_gold
    elseif ending.variant == "failure" then
        return C.accent_red
    end
    return C.accent_blue
end

function EndingModal._StartNewGame()
    if not onNewGame_ and not onNewGameRequested_ then
        UI.Toast.Show("新游戏入口不可用", { variant = "error", duration = 1.5 })
        return
    end

    EndingModal.Close()
    if onNewGameRequested_ then
        onNewGameRequested_()
    else
        local newState = GameState.CreateNew()
        newState.ap.max = GameState.CalcMaxAP(newState)
        newState.ap.current = newState.ap.max
        GameState.AddLog(newState, "科瓦奇家族在巴科维奇矿区开始了创业之路。")
        onNewGame_(newState)
    end
end

-- 即时胜利立绘映射
local INSTANT_VICTORY_PORTRAITS = {
    world_domination   = "image/victory_world_domination.png",
    economic_dominance = "image/victory_economic_dominance.png",
}

--- 即时胜利全屏庆祝弹窗（全面统治/经济碾压 达成时立刻弹出）
---@param state table
---@param instantVictory table  { type, label, desc }
function EndingModal.ShowInstantVictory(state, instantVictory)
    if not instantVictory then return end

    EndingModal.Close()

    -- 播放胜利 BGM
    AudioManager.PlayBGM("bgm_victory")

    -- 先记录胜利
    GameState.ClaimInstantVictory(state, instantVictory)

    -- 图标 & 立绘
    local icon = instantVictory.type == "world_domination" and "🌍" or "💎"
    local portrait = INSTANT_VICTORY_PORTRAITS[instantVictory.type]

    -- 统计数据
    local stats = EndingModal._BuildInstantVictoryStats(state, instantVictory)
    local statRows = {}
    for i = 1, #stats, 2 do
        table.insert(statRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            children = {
                EndingModal._StatCell(stats[i].label, stats[i].value),
                stats[i + 1] and EndingModal._StatCell(stats[i + 1].label, stats[i + 1].value)
                    or UI.Panel { flexGrow = 1, flexBasis = 0 },
            },
        })
    end

    modal_ = UI.Modal {
        title = icon .. " " .. instantVictory.label,
        size = "fullscreen",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
    }

    -- 立绘区
    local portraitPanel = nil
    if portrait then
        portraitPanel = UI.Panel {
            width = "100%",
            alignItems = "center",
            justifyContent = "center",
            children = {
                UI.Panel {
                    width = 380,
                    height = 380,
                    borderRadius = S.radius_card,
                    backgroundImage = portrait,
                    backgroundFit = "cover",
                    borderWidth = 2,
                    borderColor = C.accent_gold,
                    flexShrink = 0,
                },
            },
        }
    end

    -- 内容子元素
    local contentChildren = {}

    -- 1. 立绘
    if portraitPanel then
        table.insert(contentChildren, portraitPanel)
    end

    -- 2. 标题 + 描述卡片
    table.insert(contentChildren, UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 2,
        borderColor = C.accent_gold,
        flexDirection = "column",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                text = "即时胜利",
                fontSize = F.body_minor,
                fontWeight = "bold",
                fontColor = C.accent_gold,
                textAlign = "center",
            },
            UI.Label {
                text = icon .. " " .. instantVictory.label,
                fontSize = F.data_large,
                fontWeight = "bold",
                fontColor = C.text_primary,
                textAlign = "center",
            },
            UI.Divider { color = C.accent_gold },
            UI.Label {
                text = instantVictory.desc,
                fontSize = F.body,
                fontColor = C.text_secondary,
                textAlign = "center",
                whiteSpace = "normal",
                lineHeight = 1.5,
            },
        },
    })

    -- 3. 成就统计
    table.insert(contentChildren, UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_card,
        flexDirection = "column",
        gap = 8,
        children = EndingModal._WithTitle("成就统计", statRows),
    })

    -- 4. 按钮
    table.insert(contentChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 8,
        children = {
            EndingModal._Button("继续经营", C.bg_elevated, C.text_primary, function()
                EndingModal.Close()
                if onStateChanged_ then onStateChanged_() end
            end),
            EndingModal._Button("开始新游戏", C.accent_gold, { 30, 25, 15, 255 }, function()
                EndingModal._StartNewGame()
            end),
        },
    })

    modal_:AddContent(UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 12,
        padding = 4,
        children = contentChildren,
    })

    if uiRoot_ then
        uiRoot_:AddChild(modal_)
    end
    modal_:Open()
end

--- 构建即时胜利的统计数据
---@param state table
---@param instantVictory table
---@return table[] stats
function EndingModal._BuildInstantVictoryStats(state, instantVictory)
    local stats = {}

    -- 占领国家数
    local occupiedCount = 0
    if state.expeditions and state.expeditions.occupied_countries then
        occupiedCount = #state.expeditions.occupied_countries
    end

    -- 总控制度
    local totalControl = 0
    for _, region in pairs(state.regions or {}) do
        totalControl = totalControl + (region.control or 0)
    end

    -- 总资产
    local totalAssets = (state.cash or 0) + (state.gold or 0) * (Balance.GOLD.price_per_unit or 400)

    if instantVictory.type == "world_domination" then
        table.insert(stats, { label = "占领国家", value = tostring(occupiedCount) })
        table.insert(stats, { label = "总控制度", value = tostring(totalControl) })
        table.insert(stats, { label = "现金", value = string.format("%d 克朗", state.cash or 0) })
        table.insert(stats, { label = "黄金", value = string.format("%d 单位", state.gold or 0) })
        table.insert(stats, { label = "总资产", value = string.format("%d 克朗", totalAssets) })
        table.insert(stats, { label = "达成回合", value = string.format("第 %d 回合", state.turn or 0) })
    else -- economic_dominance
        table.insert(stats, { label = "现金", value = string.format("%d 克朗", state.cash or 0) })
        table.insert(stats, { label = "黄金", value = string.format("%d 单位", state.gold or 0) })
        table.insert(stats, { label = "总资产", value = string.format("%d 克朗", totalAssets) })
        table.insert(stats, { label = "总控制度", value = tostring(totalControl) })
        table.insert(stats, { label = "占领国家", value = tostring(occupiedCount) })
        table.insert(stats, { label = "达成回合", value = string.format("第 %d 回合", state.turn or 0) })
    end

    return stats
end

function EndingModal.Close()
    if modal_ then
        modal_:Close()
        modal_:Destroy()
        modal_ = nil
    end
end

function EndingModal.IsShowing()
    return modal_ ~= nil
end

return EndingModal
