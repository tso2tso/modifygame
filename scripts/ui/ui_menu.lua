-- ============================================================================
-- 菜单页 UI：存档管理、新游戏、游戏统计、版本信息
-- 设计规范：sarajevo_dynasty_ui_spec §4.8 右侧 Drawer 托管
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local SaveLoad = require("utils.save_load")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local MenuPage = {}

---@type table
local stateRef_ = nil
---@type function|nil
local onStateChanged_ = nil
---@type function|nil
local onNewGame_ = nil

--- 创建菜单页完整内容
---@param state table
---@param callbacks table { onStateChanged, onNewGame }
---@return table widget
function MenuPage.Create(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged
    onNewGame_ = callbacks and callbacks.onNewGame
    return MenuPage._BuildContent(state)
end

function MenuPage._BuildContent(state)
    local hasSave = SaveLoad.HasSave()
    local slots = SaveLoad.ListSlots()

    return UI.Panel {
        id = "menuContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = {
            -- 游戏标题卡片
            MenuPage._CreateTitleCard(state),

            -- 存档操作卡片
            MenuPage._CreateSaveCard(state, hasSave),

            -- 存档列表卡片
            MenuPage._CreateSlotsCard(state, slots),

            -- 游戏统计
            MenuPage._CreateStatsCard(state),

            -- 版本信息
            MenuPage._CreateAboutCard(),
        },
    }
end

--- 游戏标题卡片
function MenuPage._CreateTitleCard(state)
    local turnText = GameState.GetTurnText(state)
    local ending = GameState.GetEndingInfo(state)
    local statusText = ending and (ending.resultLabel .. "：" .. ending.title) or ("当前进度：" .. turnText)
    local statusColor = ending and (ending.variant == "failure" and C.accent_red or C.accent_gold)
        or C.text_secondary

    return UI.Panel {
        width = "100%",
        padding = S.card_padding + 4,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_gold,
        flexDirection = "column",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                text = "⚜️",
                fontSize = 32,
                textAlign = "center",
            },
            UI.Label {
                text = Config.TITLE,
                fontSize = F.card_title,
                fontWeight = "bold",
                fontColor = C.accent_gold,
                textAlign = "center",
            },
            UI.Label {
                text = statusText,
                fontSize = F.body_minor,
                fontColor = statusColor,
                textAlign = "center",
            },
        },
    }
end

--- 存档操作卡片
function MenuPage._CreateSaveCard(state, hasSave)
    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Label {
                text = "存档管理",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Divider { color = C.divider },
            -- 快速存档
            UI.Button {
                text = "快速存档",
                width = "100%",
                height = 36,
                fontSize = F.body,
                variant = "primary",
                backgroundColor = C.accent_gold,
                fontColor = C.bg_base,
                borderRadius = S.radius_btn,
                onClick = function(self)
                    MenuPage._OnQuickSave()
                end,
            },
            -- 快速读档
            UI.Button {
                text = "快速读档",
                width = "100%",
                height = 36,
                fontSize = F.body,
                variant = "outlined",
                disabled = not hasSave,
                borderRadius = S.radius_btn,
                onClick = function(self)
                    MenuPage._OnQuickLoad()
                end,
            },
            UI.Divider { color = C.divider },
            -- 新游戏
            UI.Button {
                text = "开始新游戏",
                width = "100%",
                height = 36,
                fontSize = F.body,
                variant = "outlined",
                fontColor = C.accent_red,
                borderColor = C.accent_red,
                borderRadius = S.radius_btn,
                onClick = function(self)
                    MenuPage._OnNewGame()
                end,
            },
            UI.Label {
                text = "新游戏将覆盖当前进度（自动存档会保留）",
                fontSize = F.label,
                fontColor = C.text_muted,
                textAlign = "center",
                whiteSpace = "normal",
            },
        },
    }
end

--- 存档列表卡片
function MenuPage._CreateSlotsCard(state, slots)
    -- 避免 table.unpack 陷阱，用 table.insert 构建 children
    local slotChildren = {
        UI.Label {
            text = "存档列表",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_primary,
        },
        UI.Divider { color = C.divider },
    }

    if #slots == 0 then
        table.insert(slotChildren, UI.Label {
            text = "暂无存档",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
            textAlign = "center",
        })
    else
        for _, slot in ipairs(slots) do
            table.insert(slotChildren, UI.Panel {
                width = "100%",
                padding = 8,
                backgroundColor = C.bg_elevated,
                borderRadius = S.radius_card,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = slot,
                        fontSize = F.body,
                        fontColor = C.text_primary,
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    UI.Button {
                        text = "读取",
                        fontSize = F.label,
                        height = 26,
                        paddingHorizontal = 10,
                        variant = "primary",
                        borderRadius = S.radius_btn,
                        onClick = (function(slotName)
                            return function(self)
                                MenuPage._OnLoadSlot(slotName)
                            end
                        end)(slot),
                    },
                    UI.Button {
                        text = "删除",
                        fontSize = F.label,
                        height = 26,
                        paddingHorizontal = 10,
                        variant = "outlined",
                        fontColor = C.accent_red,
                        borderColor = C.accent_red,
                        borderRadius = S.radius_btn,
                        onClick = (function(slotName)
                            return function(self)
                                MenuPage._OnDeleteSlot(slotName)
                            end
                        end)(slot),
                    },
                },
            })
        end
    end

    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 6,
        children = slotChildren,
    }
end

--- 游戏统计卡片
function MenuPage._CreateStatsCard(state)
    local totalTurns = state.turn_count
    local totalIncome = state.total_income or 0
    local totalExpense = state.total_expense or 0
    local members = #state.family.members
    local logCount = #state.history_log

    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Label {
                text = "游戏统计",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Divider { color = C.divider },
            MenuPage._InfoRow("已度过回合", tostring(totalTurns)),
            MenuPage._InfoRow("累计收入", string.format("%d", totalIncome)),
            MenuPage._InfoRow("累计支出", string.format("%d", totalExpense)),
            MenuPage._InfoRow("净利润", string.format("%d", totalIncome - totalExpense)),
            MenuPage._InfoRow("家族成员", tostring(members) .. " 人"),
            MenuPage._InfoRow("事件记录", tostring(logCount) .. " 条"),
            MenuPage._InfoRow("经济胜利进度", string.format("%d%%", state.victory.economic)),
            MenuPage._InfoRow("军事胜利进度", string.format("%d%%", state.victory.military)),
        },
    }
end

--- 版本信息
function MenuPage._CreateAboutCard()
    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Label {
                text = Config.TITLE,
                fontSize = F.body_minor,
                fontColor = C.text_muted,
                textAlign = "center",
            },
            UI.Label {
                text = "版本 " .. Config.VERSION .. " | MVP 竖版纵切片",
                fontSize = F.label,
                fontColor = C.text_muted,
                textAlign = "center",
            },
            UI.Label {
                text = "1904-1918 巴尔干半岛·波斯尼亚",
                fontSize = F.label,
                fontColor = C.text_muted,
                textAlign = "center",
            },
        },
    }
end

--- 信息行
function MenuPage._InfoRow(label, value)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label { text = label, fontSize = F.body_minor, fontColor = C.text_secondary },
            UI.Label { text = value, fontSize = F.body_minor, fontWeight = "bold", fontColor = C.text_primary },
        },
    }
end

-- ============================================================================
-- 操作回调
-- ============================================================================

--- 快速存档
function MenuPage._OnQuickSave()
    if not stateRef_ then return end
    local ok = SaveLoad.Save(stateRef_)
    if ok then
        UI.Toast.Show("存档成功", { variant = "success", duration = 1.5 })
    else
        UI.Toast.Show("存档失败", { variant = "error", duration = 1.5 })
    end
    if onStateChanged_ then onStateChanged_() end
end

--- 快速读档
function MenuPage._OnQuickLoad()
    local loaded = SaveLoad.Load()
    if loaded then
        loaded.ap.max = GameState.CalcMaxAP(loaded)
        loaded.ap.current = math.min(loaded.ap.current, loaded.ap.max)

        UI.Toast.Show("读档成功：" .. GameState.GetTurnText(loaded), { variant = "success", duration = 1.5 })
        if onNewGame_ then
            onNewGame_(loaded)
        end
    else
        UI.Toast.Show("读档失败", { variant = "error", duration = 1.5 })
    end
end

--- 读取指定存档
function MenuPage._OnLoadSlot(slotName)
    local loaded = SaveLoad.Load(slotName)
    if loaded then
        loaded.ap.max = GameState.CalcMaxAP(loaded)
        loaded.ap.current = math.min(loaded.ap.current, loaded.ap.max)

        UI.Toast.Show("读档成功：" .. slotName, { variant = "success", duration = 1.5 })
        if onNewGame_ then
            onNewGame_(loaded)
        end
    else
        UI.Toast.Show("读档失败：" .. slotName, { variant = "error", duration = 1.5 })
    end
end

--- 删除指定存档
function MenuPage._OnDeleteSlot(slotName)
    local ok = SaveLoad.Delete(slotName)
    if ok then
        UI.Toast.Show("已删除：" .. slotName, { variant = "warning", duration = 1.5 })
    else
        UI.Toast.Show("删除失败", { variant = "error", duration = 1.5 })
    end
    if onStateChanged_ then onStateChanged_() end
end

--- 新游戏
function MenuPage._OnNewGame()
    local newState = GameState.CreateNew()
    newState.ap.max = GameState.CalcMaxAP(newState)
    newState.ap.current = newState.ap.max
    GameState.AddLog(newState, "科瓦奇家族在巴科维奇矿区开始了创业之路。")
    UI.Toast.Show("新的百年传奇开始了！", { variant = "info", duration = 2 })
    if onNewGame_ then
        onNewGame_(newState)
    end
end

function MenuPage.Refresh(root, state)
    stateRef_ = state
end

return MenuPage
