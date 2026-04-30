-- ============================================================================
-- 菜单页 UI：存档管理、新游戏、游戏统计、版本信息
-- 设计规范：sarajevo_dynasty_ui_spec §4.8 右侧 Drawer 托管
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local SaveLoad = require("utils.save_load")
local Balance = require("data.balance")

local AudioManager = require("systems.audio_manager")

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
---@type table|nil 存档操作卡片引用（用于局部刷新）
local saveCardRef_ = nil

--- 创建菜单页完整内容
---@param state table
---@param callbacks table { onStateChanged, onNewGame }
---@return table widget
function MenuPage.Create(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged
    onNewGame_ = callbacks and callbacks.onNewGame
    saveCardRef_ = nil
    return MenuPage._BuildContent(state)
end

function MenuPage._BuildContent(state)
    local hasSave = SaveLoad.HasSave()

    saveCardRef_ = MenuPage._CreateSaveCard(state, hasSave)

    return UI.Panel {
        id = "menuContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = {
            -- 游戏标题卡片
            MenuPage._CreateTitleCard(state),

            -- 音量设置卡片
            MenuPage._CreateAudioCard(),

            -- 存档操作卡片（含双槽位读档）
            saveCardRef_,

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

--- 音量设置卡片
function MenuPage._CreateAudioCard()
    local function volumeRow(label, category)
        local val = math.floor(AudioManager.GetVolume(category) * 100)
        local valLabel = nil
        valLabel = UI.Label {
            id = "vol_" .. category,
            text = val .. "%",
            fontSize = F.label,
            fontColor = C.text_muted,
            width = 36,
            textAlign = "right",
        }
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = label,
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                    width = 40,
                },
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = {
                        UI.Slider {
                            value = val,
                            min = 0,
                            max = 100,
                            step = 5,
                            width = "100%",
                            trackColor = C.paper_mid,
                            fillColor = C.accent_gold,
                            onChange = (function(cat, lbl)
                                return function(self, v)
                                    AudioManager.SetVolume(cat, v / 100)
                                    if lbl then lbl:SetText(math.floor(v) .. "%") end
                                end
                            end)(category, valLabel),
                        },
                    },
                },
                valLabel,
            },
        }
    end

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
                text = "🔊 音量设置",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Divider { color = C.divider },
            volumeRow("音乐", "music"),
            volumeRow("音效", "effect"),
            volumeRow("界面", "ui"),
        },
    }
end

--- 格式化存档时间戳为可读文本
function MenuPage._FormatTimestamp(ts)
    if not ts or ts == 0 then return "未知时间" end
    local d = os.date("*t", ts)
    if not d then return "未知时间" end
    return string.format("%d/%02d/%02d %02d:%02d", d.year, d.month, d.day, d.hour, d.min)
end

--- 创建存档槽位信息行（用于展示 auto/manual 槽位状态）
function MenuPage._CreateSlotInfoRow(label, info, onLoad)
    if not info then
        return UI.Panel {
            width = "100%",
            padding = 8,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_card,
            flexDirection = "row",
            alignItems = "center",
            children = {
                UI.Label {
                    text = label,
                    fontSize = F.body_minor,
                    fontWeight = "bold",
                    fontColor = C.text_muted,
                    width = 70,
                },
                UI.Label {
                    text = "空",
                    fontSize = F.body_minor,
                    fontColor = C.text_muted,
                    flexGrow = 1,
                },
            },
        }
    end

    local timeStr = MenuPage._FormatTimestamp(info.timestamp)
    local turnStr = string.format("%d年Q%d  第%d回合", info.year, info.quarter, info.turn_count)
    local cashStr = string.format("💰%d  🥇%d", info.cash, info.gold)

    return UI.Panel {
        width = "100%",
        padding = 8,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_card,
        flexDirection = "column",
        gap = 4,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = label,
                        fontSize = F.body_minor,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                        width = 70,
                    },
                    UI.Label {
                        text = turnStr,
                        fontSize = F.body_minor,
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
                        onClick = onLoad,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = cashStr,
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                    },
                    UI.Label {
                        text = timeStr,
                        fontSize = F.label,
                        fontColor = C.text_muted,
                    },
                },
            },
        },
    }
end

--- 存档操作卡片内部子元素列表
function MenuPage._CreateSaveCardInner(state, hasSave)
    local autoInfo = SaveLoad.GetSlotInfo(SaveLoad.SLOT_AUTO)
    local manualInfo = SaveLoad.GetSlotInfo(SaveLoad.SLOT_MANUAL)
    -- 兼容旧版 autosave
    if not autoInfo then
        autoInfo = SaveLoad.GetSlotInfo()
    end

    return {
        UI.Label {
            text = "存档管理",
            fontSize = F.subtitle,
            fontWeight = "bold",
            fontColor = C.text_primary,
        },
        UI.Divider { color = C.divider },
        -- 快速存档（存到 manual 槽）
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
        UI.Divider { color = C.divider },
        -- 双槽位读档
        UI.Label {
            text = "选择存档读取",
            fontSize = F.body_minor,
            fontWeight = "bold",
            fontColor = C.text_secondary,
        },
        MenuPage._CreateSlotInfoRow("自动存档", autoInfo, function(self)
            MenuPage._OnLoadSlot(autoInfo and SaveLoad.SLOT_AUTO or nil)
        end),
        MenuPage._CreateSlotInfoRow("手动存档", manualInfo, function(self)
            if manualInfo then
                MenuPage._OnLoadSlot(SaveLoad.SLOT_MANUAL)
            else
                UI.Toast.Show("暂无手动存档", { variant = "warning", duration = 1.5 })
            end
        end),
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
            text = "新游戏将覆盖当前进度",
            fontSize = F.label,
            fontColor = C.text_muted,
            textAlign = "center",
            whiteSpace = "normal",
        },
    }
end

--- 存档操作卡片（容器 + 内容）
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
        children = MenuPage._CreateSaveCardInner(state, hasSave),
    }
end

--- 游戏统计卡片
function MenuPage._CreateStatsCard(state)
    local totalTurns = state.turn_count
    local totalIncome = state.total_income or 0
    local totalExpense = state.total_expense or 0
    local members = #state.family.members
    local logCount = #state.history_log
    local standing = GameState.GetVictoryStanding(state)
    local ecoTarget = (standing.best_ai.economic.score or 0)
        + (((Balance.VICTORY.relative.lead_margin or {}).economic) or 200)
    local milTarget = (standing.best_ai.military.score or 0)
        + (((Balance.VICTORY.relative.lead_margin or {}).military) or 250)

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
            MenuPage._InfoRow("经济领先", string.format("%d / %d", state.victory.economic, ecoTarget)),
            MenuPage._InfoRow("军事领先", string.format("%d / %d", state.victory.military, milTarget)),
            MenuPage._InfoRow("胜利声明", state.victory.claimed and "已宣布" or "未宣布"),
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

--- 快速存档（存到 manual 槽）
function MenuPage._OnQuickSave()
    if not stateRef_ then return end
    local ok = SaveLoad.Save(stateRef_, SaveLoad.SLOT_MANUAL)
    if ok then
        UI.Toast.Show("手动存档成功", { variant = "success", duration = 1.5 })
    else
        UI.Toast.Show("存档失败", { variant = "error", duration = 1.5 })
    end
    if onStateChanged_ then onStateChanged_() end
    -- 局部刷新存档卡片（不重建 Modal）
    MenuPage._RefreshSaveCards()
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

--- 局部刷新存档相关卡片（不重建整个 Modal）
function MenuPage._RefreshSaveCards()
    if not stateRef_ then return end
    local hasSave = SaveLoad.HasSave()

    -- 替换存档操作卡片内容（含双槽位读档）
    if saveCardRef_ then
        saveCardRef_:ClearChildren()
        for _, child in ipairs(MenuPage._CreateSaveCardInner(stateRef_, hasSave)) do
            saveCardRef_:AddChild(child)
        end
    end
end

function MenuPage.Refresh(root, state)
    stateRef_ = state
end

return MenuPage
