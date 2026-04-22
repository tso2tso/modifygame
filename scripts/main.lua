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

    -- 2. 尝试读取存档，否则新建游戏
    local loaded = SaveLoad.Load()
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

    -- 5. 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    -- 6. 检查开局事件（新游戏首回合）
    if not loaded then
        local startEvents = Events.CheckEvents(state_)
        if #startEvents > 0 then
            Events.Enqueue(state_, startEvents)
            ProcessNextEvent()
        end
    end

    print("=== 初始化完成 ===")
end

function Stop()
    if state_ then
        SaveLoad.Save(state_)
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

    -- 重建 UI
    UIManager.Create(state_, {
        onEndTurn = HandleEndTurn,
        onNewGame = HandleNewGame,
        onProcessEvent = HandleProcessEvent,
    })
    UIManager.BackToDashboard()

    -- 新游戏检查开局事件
    if state_.turn_count == 0 then
        local startEvents = Events.CheckEvents(state_)
        if #startEvents > 0 then
            Events.Enqueue(state_, startEvents)
            ProcessNextEvent()
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
    end)
end

-- ============================================================================
-- 回合处理
-- ============================================================================

--- 结束回合（调用回合引擎）
function HandleEndTurn()
    -- 防止事件弹窗期间重复点击
    if EventModal.IsShowing() then return end

    -- 检查游戏结束
    if GameState.IsGameOver(state_) then
        local vType = GameState.GetVictoryType(state_)
        local msg = "百年家族史已书写完毕！"
        if vType == "economic" then
            msg = "经济胜利！黄金帝国已建成！"
        elseif vType == "military" then
            msg = "军事胜利！钢铁执政者崛起！"
        end
        print("[结局] " .. msg)
        UI.Toast.Show(msg, { variant = "info", duration = 4 })
        return
    end

    -- 执行回合引擎（会将事件入队）
    local report = TurnEngine.EndTurn(state_)
    pendingReport_ = report

    -- 输出日志
    print(string.format("[%s] %s", GameState.GetTurnText(state_),
        TurnEngine.FormatReportSummary(report)))

    -- 检查事件队列，有事件则弹窗
    if Events.HasPendingEvents(state_) then
        ProcessNextEvent()
    else
        FinalizeEndTurn()
    end
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
    end)
end

--- 回合最终完成（事件全部处理后）
function FinalizeEndTurn()
    local report = pendingReport_
    pendingReport_ = nil

    if not report then return end

    -- 自动存档
    SaveLoad.Save(state_)

    -- 刷新 UI
    UIManager.RefreshAll(state_)

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
    -- 回合制，无需每帧逻辑
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
