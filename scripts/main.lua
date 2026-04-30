-- ============================================================================
-- 《百年萨拉热窝：黄金家族》- 主入口
-- 竖屏手机历史架空经营模拟游戏
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local UIManager = require("ui.ui_manager")
local SaveLoad = require("utils.save_load")
local TurnEngine = require("systems.turn_engine")
local Events = require("systems.events")
local EventModal = require("ui.ui_event_modal")
local Balance = require("data.balance")
local AudioManager = require("systems.audio_manager")
local Tutorial = require("ui.ui_tutorial")

-- ============================================================================
-- 全局变量
-- ============================================================================

---@type table 游戏状态
local state_ = nil
---@type TurnReport|nil 当前回合报告（等待事件处理完毕）
local pendingReport_ = nil

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = Config.TITLE
    print("=== " .. Config.TITLE .. " v" .. Config.VERSION .. " ===")

    -- 1. 初始化 UI 系统
    UIManager.InitUI()

    -- 1.1 移动端去重：抑制引擎模拟的鼠标事件，避免 Widget 内置 OnClick 双触发
    --     在移动端，引擎对同一次触摸同时发送 Touch* 和 Mouse* 事件，
    --     UI 框架两组都订阅，导致 Dropdown 等组件的 OnClick 被调用两次（开→关）。
    --     此处将 UI 的鼠标处理函数替换为空操作，只保留触摸路径。
    local plat = GetPlatform and GetPlatform() or ""
    if plat == "Android" or plat == "iOS" then
        local noop = function() end
        UI.HandleMouseDown = noop
        UI.HandleMouseUp   = noop
        UI.HandleMouseMove = noop
        print("[Touch] 移动端：已抑制模拟鼠标事件，使用纯触摸路径")
    else
        print("[Input] 桌面/Web端：使用鼠标事件路径")
    end

    -- 1.5 初始化音频系统
    local audioScene = Scene()
    AudioManager.Init(audioScene)

    -- 包裹 TapGuard：所有按钮点击自动播放 UI 音效
    local _origTapGuard = Config.TapGuard
    Config.TapGuard = function(fn)
        return _origTapGuard(function(self)
            AudioManager.PlayUI("ui_button_click")
            fn(self)
        end)
    end

    -- 包裹 Toast.Show：根据 variant 自动播放对应提示音
    local _origToastShow = UI.Toast.Show
    UI.Toast.Show = function(msg, opts)
        local variant = opts and opts.variant or "info"
        if variant == "error" then
            AudioManager.PlayUI("ui_toast_error")
        elseif variant == "warning" then
            AudioManager.PlayUI("ui_toast_warning")
        else
            AudioManager.PlayUI("ui_toast_info")
        end
        _origToastShow(msg, opts)
    end

    -- 2. 尝试读取存档（优先 auto 槽，兼容旧 autosave）
    local loaded = SaveLoad.Load(SaveLoad.SLOT_AUTO)
        or SaveLoad.Load()  -- 兼容旧版 autosave.json
    if loaded then
        state_ = loaded
        print(string.format("读档成功：%s，现金 %d，黄金 %d",
            GameState.GetTurnText(state_), state_.cash, state_.gold))
    else
        state_ = GameState.CreateNew()
        print(string.format("新游戏：%s，现金 %d，黄金 %d",
            GameState.GetTurnText(state_), state_.cash, state_.gold))
        GameState.AddLog(state_, "科瓦奇家族在巴科维奇矿区开始了创业之路。")
    end

    -- 2.5 恢复音量设置并启动 BGM
    if state_.audio_settings then
        AudioManager.LoadSettings(state_.audio_settings)
    end
    AudioManager.UpdateBGM(state_)

    -- 打印初始信息
    print(string.format("家族成员 %d 人：", #state_.family.members))
    for i, m in ipairs(state_.family.members) do
        print(string.format("  %d. %s (%s) - 管理:%d 谋略:%d 魅力:%d 学识:%d 野心:%d",
            i, m.name, m.title,
            m.attrs.management, m.attrs.strategy, m.attrs.charisma,
            m.attrs.knowledge, m.attrs.ambition))
    end

    print(string.format("地区 %d | AI %d | 矿山 %d",
        #state_.regions, #state_.ai_factions, #state_.mines))

    -- 3. 更新 AP 上限
    state_.ap.max = GameState.CalcMaxAP(state_)
    state_.ap.current = math.min(state_.ap.current, state_.ap.max)

    -- 4. 创建 UI
    UIManager.Create(state_, {
        onEndTurn = HandleEndTurn,
        onNewGame = HandleNewGame,
        onProcessEvent = HandleProcessEvent,
    })
    -- EventModal / Tutorial 也需要 UI 根节点来显示弹窗
    EventModal.SetRoot(UIManager.GetRoot())
    Tutorial.SetRoot(UIManager.GetRoot())

    if GameState.IsGameOver(state_) then
        UIManager.ShowEnding(state_)
    elseif state_.victory and state_.victory.prompt_pending then
        UIManager.ShowVictoryPrompt(state_)
    end

    -- 5. 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    -- 5.0 切后台自动存档（移动端最可靠的保存时机）
    SubscribeToEvent("AppMinimized", function()
        if state_ then
            state_.audio_settings = AudioManager.GetSettings()
            SaveLoad.Save(state_, SaveLoad.SLOT_AUTO)
            print("[AppMinimized] 切后台，已自动存档到 auto 槽")
        end
    end)

    -- 5.1 全局触控按下位置跟踪（供 Config.TapGuard 滑动/点击区分）
    SubscribeToEvent("MouseButtonDown", function()
        Config.TapDown()
    end)
    SubscribeToEvent("TouchBegin", function()
        Config.TapDown()
    end)

    -- 6. 新游戏：先展示新手引导，引导结束后再检查开局事件
    if not loaded then
        if not state_.tutorial_done then
            Tutorial.Start(function()
                state_.tutorial_done = true
                -- 引导结束后检查开局事件
                local startEvents = Events.CheckEvents(state_)
                if #startEvents > 0 then
                    Events.Enqueue(state_, startEvents)
                    UIManager.RefreshAll(state_)
                end
                SaveLoad.Save(state_, SaveLoad.SLOT_AUTO)
            end)
        else
            local startEvents = Events.CheckEvents(state_)
            if #startEvents > 0 then
                Events.Enqueue(state_, startEvents)
                UIManager.RefreshAll(state_)
            end
        end
    end

    print("=== 初始化完成 ===")
end

function Stop()
    if state_ then
        state_.audio_settings = AudioManager.GetSettings()
        SaveLoad.Save(state_, SaveLoad.SLOT_AUTO)
    end
    UI.Shutdown()
    print("=== 游戏退出 ===")
end

-- ============================================================================
-- 新游戏/读档处理
-- ============================================================================

--- 新游戏或读档回调（从菜单页触发）
---@param newState table 新的游戏状态
function HandleNewGame(newState)
    state_ = newState
    pendingReport_ = nil
    print(string.format("[新游戏/读档] %s，现金 %d，黄金 %d",
        GameState.GetTurnText(state_), state_.cash, state_.gold))

    -- 重置 BGM
    AudioManager.UpdateBGM(state_)

    -- 重建 UI
    UIManager.Create(state_, {
        onEndTurn = HandleEndTurn,
        onNewGame = HandleNewGame,
        onProcessEvent = HandleProcessEvent,
    })
    EventModal.SetRoot(UIManager.GetRoot())
    Tutorial.SetRoot(UIManager.GetRoot())
    UIManager.BackToDashboard()
    if GameState.IsGameOver(state_) then
        UIManager.ShowEnding(state_)
    elseif state_.victory and state_.victory.prompt_pending then
        UIManager.ShowVictoryPrompt(state_)
    end

    -- 新游戏：先展示引导，引导结束后再检查开局事件
    if state_.turn_count == 0 and not state_.tutorial_done then
        Tutorial.Start(function()
            state_.tutorial_done = true
            local startEvents = Events.CheckEvents(state_)
            if #startEvents > 0 then
                Events.Enqueue(state_, startEvents)
                UIManager.RefreshAll(state_)
            end
            SaveLoad.Save(state_, SaveLoad.SLOT_AUTO)
        end)
    elseif state_.turn_count == 0 then
        local startEvents = Events.CheckEvents(state_)
        if #startEvents > 0 then
            Events.Enqueue(state_, startEvents)
            UIManager.RefreshAll(state_)
        end
    end
end

-- ============================================================================
-- 事件处理（仪表盘事件卡点击"处理"按钮）
-- ============================================================================

--- 从仪表盘处理指定事件
---@param eventIndex number 事件在队列中的索引
function HandleProcessEvent(eventIndex)
    if not state_ or not state_.event_queue then return end
    if eventIndex < 1 or eventIndex > #state_.event_queue then return end

    -- 取出该事件（从队列中移除）
    local event = table.remove(state_.event_queue, eventIndex)
    if not event then return end

    print(string.format("[事件处理] %s - %s", event.icon or "", event.title))

    EventModal.Show(event, function(optionIndex)
        Events.ApplyOption(state_, event, optionIndex)
        print(string.format("[事件选择] %s → 选项 %d", event.title, optionIndex))
        UIManager.RefreshAll(state_)
    end, state_)
end

-- ============================================================================
-- 回合处理
-- ============================================================================

--- 结束回合（调用回合引擎）
function HandleEndTurn()
    -- 防止事件弹窗期间重复点击
    if EventModal.IsShowing() then
        return
    end

    -- 播放回合结束音效
    AudioManager.PlayEffect("turn_end")

    -- 清空上一轮动态通知
    if state_ then
        state_.turn_messages = {}
    end

    -- 检查游戏结束（上一回合已结束但未结算的情况，如读档后）
    if GameState.IsGameOver(state_) then
        print("[HandleEndTurn] 游戏已结束（早期检查）: bankrupt=" .. tostring(state_.bankrupt))
        -- 同样尝试破产救济
        if TryBankruptcyRescue(state_) then
            return
        end
        local ending = GameState.GetEndingInfo(state_)
        local msg = ending and ending.title or "百年家族史已书写完毕！"
        local variant = "info"
        if ending and ending.variant == "failure" then
            variant = "error"
        elseif ending and ending.variant == "success" then
            variant = "success"
        end
        print("[结局] " .. msg)
        UI.Toast.Show(msg, { variant = variant, duration = 3 })
        UIManager.ShowEnding(state_)
        return
    end

    -- 执行回合引擎（会将事件入队）
    local report = TurnEngine.EndTurn(state_)
    pendingReport_ = report

    -- 输出日志
    print(string.format("[%s] %s", GameState.GetTurnText(state_),
        TurnEngine.FormatReportSummary(report)))

    -- 事件留在队列中，交由仪表盘「当前事件」展示
    -- 玩家在仪表盘点击"处理"按钮来逐个处理
    FinalizeEndTurn()
end

--- 处理下一个待处理事件
function ProcessNextEvent()
    local event = Events.Dequeue(state_)
    if not event then
        FinalizeEndTurn()
        return
    end

    print(string.format("[事件] %s - %s", event.icon or "", event.title))

    EventModal.Show(event, function(optionIndex)
        -- 玩家做出选择，应用效果
        Events.ApplyOption(state_, event, optionIndex)
        print(string.format("[事件选择] %s → 选项 %d", event.title, optionIndex))

        -- 刷新 UI（效果可能改变资源）
        UIManager.RefreshAll(state_)

        -- 检查是否还有更多事件
        if Events.HasPendingEvents(state_) then
            ProcessNextEvent()
        else
            FinalizeEndTurn()
        end
    end, state_)
end

-- ============================================================================
-- 破产免死：统一入口，两处 IsGameOver 检查共用
-- 返回 true 表示弹窗已展示（调用方应 return 等待玩家选择）
-- 返回 false 表示不符合条件或弹窗失败，调用方继续正常结算
-- ============================================================================
function TryBankruptcyRescue(state)
    if not state.bankrupt then
        print("[破产免死] 跳过：非破产状态")
        return false
    end
    local rescue = Balance.BANKRUPTCY_RESCUE
    if not rescue then
        print("[破产免死] 跳过：Balance.BANKRUPTCY_RESCUE 未定义")
        return false
    end
    local used = state.bankrupt_ad_used or 0
    if used >= rescue.max_uses_per_game then
        print("[破产免死] 跳过：已用完次数 used=" .. used .. " max=" .. rescue.max_uses_per_game)
        return false
    end
    print("[破产免死] 条件满足，尝试创建弹窗...")
    local ok, err = pcall(function()
        AudioManager.PlayEffect("danger_warning")
        ShowBankruptcyRescueModal(state)
    end)
    if ok then
        print("[破产免死] 弹窗创建成功")
        return true
    end
    print("[破产免死] 弹窗创建失败，回退正常结算: " .. tostring(err))
    return false
end

-- ============================================================================
-- 破产免死弹窗：看广告获得紧急救济金，每局限一次
-- ============================================================================
function ShowBankruptcyRescueModal(state)
    local rescue = Balance.BANKRUPTCY_RESCUE
    local inflation = GameState.GetInflationFactor(state)
    local rescueCash = math.floor(rescue.rescue_cash_base * inflation)
    print("[破产免死] 弹窗创建: 救济金=" .. rescueCash .. " 通胀=" .. inflation)

    local modal = UI.Modal {
        title = "💀 家族濒临破产",
        size = "md",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
    }

    local content = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 12,
        padding = 4,
        children = {
            UI.Label {
                text = "债台高筑，家族即将走向毁灭……\n但命运给了你最后一次机会！",
                fontSize = Config.FONT.body,
                fontColor = Config.COLORS.text_primary,
                whiteSpace = "normal",
                lineHeight = 1.6,
            },
            UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = {45, 60, 45, 255},
                borderRadius = Config.SIZE.radius_card,
                borderWidth = 1,
                borderColor = {80, 140, 80, 180},
                flexDirection = "column",
                gap = 4,
                children = {
                    UI.Label {
                        text = "观看广告获得紧急救济",
                        fontSize = Config.FONT.body,
                        fontWeight = "bold",
                        fontColor = {180, 230, 160, 255},
                    },
                    UI.Label {
                        text = string.format("注入 %s 克朗紧急资金，清除破产状态", Config.FormatNumber(rescueCash)),
                        fontSize = Config.FONT.body_minor,
                        fontColor = Config.COLORS.text_secondary,
                        whiteSpace = "normal",
                    },
                    UI.Label {
                        text = "每局仅限一次机会",
                        fontSize = Config.FONT.label,
                        fontColor = {200, 170, 100, 255},
                    },
                },
            },
            -- 按钮区
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                children = {
                    UI.Button {
                        text = "观看广告，绝处逢生",
                        variant = "primary",
                        width = "100%",
                        onClick = function(self)
                            modal:Close()
                            modal:Destroy()
                            ---@diagnostic disable-next-line: undefined-global
                            sdk:ShowRewardVideoAd(function(result)
                                if not result.success then
                                    if result.msg == "embed manual close" then
                                        UI.Toast.Show("需完整观看广告才能获得救济",
                                            { variant = "warning", duration = 1.5 })
                                    else
                                        UI.Toast.Show("广告播放失败: " .. (result.msg or "未知错误"),
                                            { variant = "error", duration = 1.5 })
                                    end
                                    ProceedBankruptcy(state)
                                    return
                                end
                                ApplyBankruptcyRescue(state, rescueCash)
                            end)
                        end,
                    },
                    UI.Button {
                        text = "放弃挣扎，接受命运",
                        variant = "ghost",
                        width = "100%",
                        onClick = function(self)
                            modal:Close()
                            modal:Destroy()
                            ProceedBankruptcy(state)
                        end,
                    },
                },
            },
        },
    }

    modal:AddContent(content)
    local root = UIManager.GetRoot()
    if root then
        root:AddChild(modal)
    end
    modal:Open()
end

--- 破产免死广告成功：清除破产、注入资金、重置计数器
function ApplyBankruptcyRescue(state, rescueCash)
    -- 清除破产标记
    state.bankrupt = false

    -- 注入紧急资金
    state.cash = state.cash + rescueCash
    state.total_income = (state.total_income or 0) + rescueCash

    -- 重置违约/负净资产计数
    local rescue = Balance.BANKRUPTCY_RESCUE
    if rescue.clear_defaults then
        state.loan_consecutive_defaults = 0
    end
    if rescue.clear_neg_nw then
        state.negative_net_worth_turns = 0
    end

    -- 标记已使用
    state.bankrupt_ad_used = (state.bankrupt_ad_used or 0) + 1

    -- 日志
    GameState.AddLog(state, string.format(
        "🆘 破产免死：观看广告获得 %s 克朗紧急救济金，家族转危为安",
        Config.FormatNumber(rescueCash)))

    -- 存档（关键事件存到 auto 槽）
    SaveLoad.Save(state, SaveLoad.SLOT_AUTO)

    -- 提示
    UI.Toast.Show(string.format("🆘 紧急救济！\n+%s 克朗，家族暂时脱离破产危机",
        Config.FormatNumber(rescueCash)),
        { variant = "success", duration = 3 })
    AudioManager.PlayEffect("event_trigger")

    -- 刷新 UI
    UIManager.RefreshAll(state)
    print("[破产免死] 广告成功，注入 " .. Config.FormatNumber(rescueCash) .. " 克朗")
end

--- 玩家拒绝看广告或广告失败 → 正常破产流程
function ProceedBankruptcy(state)
    local ending = GameState.GetEndingInfo(state)
    if ending then
        AudioManager.PlayEffect("game_defeat")
        UI.Toast.Show(ending.title, { variant = "error", duration = 3 })
    end
    AudioManager.StopBGM()
    UIManager.ShowEnding(state)
end

--- 回合最终完成（事件全部处理后）
function FinalizeEndTurn()
    local report = pendingReport_
    pendingReport_ = nil

    if not report then return end

    -- 更新 BGM（跨时代切换）
    AudioManager.UpdateBGM(state_)

    -- 收集本季动态通知（战斗结果、AI行动、警告）
    state_.turn_messages = {}
    for _, msg in ipairs(report.ai_changes or {}) do
        local mtype = "ai_move"
        if msg:find("⚔") then mtype = "combat_win"
        elseif msg:find("💥") then mtype = "combat_lose"
        end
        table.insert(state_.turn_messages, { text = msg, type = mtype })
    end
    for _, w in ipairs(report.warnings or {}) do
        table.insert(state_.turn_messages, { text = w, type = "warning" })
    end

    -- 刷新 UI
    UIManager.RefreshAll(state_)

    -- 回合推进后立即展示胜利/失败结算，避免只在下一次点击时提示。
    if GameState.IsGameOver(state_) then
        print("[FinalizeEndTurn] 游戏结束检测: bankrupt=" .. tostring(state_.bankrupt)
            .. " year=" .. tostring(state_.year) .. " turn=" .. tostring(state_.turn))
        -- ==================================================================
        -- 破产免死广告：在展示结局前，给一次看广告续命的机会
        -- ==================================================================
        if TryBankruptcyRescue(state_) then
            return  -- 弹窗已展示，等待玩家选择
        end

        local ending = GameState.GetEndingInfo(state_)
        if ending then
            local variant = ending.variant == "failure" and "error" or "success"
            if variant == "error" then
                AudioManager.PlayEffect("game_defeat")
            else
                AudioManager.PlayEffect("game_victory")
            end
            UI.Toast.Show(ending.title, { variant = variant, duration = 3 })
        end
        AudioManager.StopBGM()
        UIManager.ShowEnding(state_)
        return
    end

    if state_.victory and state_.victory.prompt_pending then
        UIManager.ShowVictoryPrompt(state_)
        return
    end

    -- 强制清算醒目提示（变卖黄金/矿山降级）
    -- Toast 固定 320×56 单行，精简文案避免右侧截断
    if report.forced_liquidation and #report.forced_liquidation > 0 then
        for _, msg in ipairs(report.forced_liquidation) do
            local short = msg
                :gsub("^强制清算：变卖 (%d+) 单位黄金（回收 (%d+) 克朗）",
                      "清算：卖出%1黄金 回收%2")
                :gsub("^强制清算：矿山%[(.-)%]降级 (%d+) 级（回收 (%d+) 克朗），当前等级 (%d+)",
                      "清算：%1降%2级(Lv%4) 回收%3")
                :gsub("^强制清算：", "清算：")
            UI.Toast.Show(short, { variant = "error", duration = 5 })
        end
    end

    -- 贷款违约醒目警告（独立 Toast，确保用户注意到）
    local defaults = state_.loan_consecutive_defaults or 0
    if defaults >= 1 then
        local bkDefaults = (Balance.LOAN.bankruptcy or {}).consecutive_defaults or 4
        local remaining = bkDefaults - defaults
        if remaining > 0 then
            UI.Toast.Show(
                string.format("⚠ 贷款违约！已连续 %d 季，再违约 %d 季将破产！", defaults, remaining),
                { variant = "error", duration = 4 })
        end
    end

    -- 净资产为负时醒目警告
    local totalAssets = GameState.CalcTotalAssets(state_)
    local totalDebt = GameState.CalcTotalDebt(state_)
    local netWorth = totalAssets - totalDebt
    if netWorth < 0 then
        local negTurns = state_.negative_net_worth_turns or 0
        local bkNegTurns = (Balance.LOAN.bankruptcy or {}).negative_net_worth_turns or 4
        local remaining = bkNegTurns - negTurns
        if remaining > 0 then
            UI.Toast.Show(
                string.format("净资产为负（%s）！已持续 %d 季，再持续 %d 季将破产！",
                    Config.FormatNumber(netWorth), negTurns, remaining),
                { variant = "error", duration = 4 })
        end
    end

    -- 收支音效
    if report.economy.net >= 0 then
        AudioManager.PlayEffect("coin_income")
    else
        AudioManager.PlayEffect("coin_expense")
    end

    -- Toast 提示
    local toastMsg = string.format("%s - 净利 %d",
        GameState.GetTurnText(state_), report.economy.net)
    local variant = report.economy.net >= 0 and "success" or "warning"
    if report.economy.bankrupt then
        variant = "error"
        toastMsg = GameState.GetTurnText(state_) .. " - 财政危机！"
    end

    -- 如果有事件触发，附加提示
    if #report.events_triggered > 0 then
        toastMsg = toastMsg .. " | 事件: " .. table.concat(report.events_triggered, ", ")
    end

    UI.Toast.Show(toastMsg, { variant = variant, duration = 2.5 })
end

-- ============================================================================
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = 0
    if eventData and eventData["TimeStep"] then
        dt = eventData["TimeStep"]:GetFloat()
    end
    -- 延迟页面刷新：在 onClick 回调栈外执行 ClearChildren+rebuild，防止按钮闪烁
    UIManager.FlushPendingRefresh()
    Tutorial.Update(dt)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_ESCAPE then
        -- ESC 键：如果在深度页则返回仪表盘
        if UIManager.GetActiveView() ~= "dashboard" then
            UIManager.BackToDashboard()
        end
    end
end
