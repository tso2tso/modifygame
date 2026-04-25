-- ============================================================================
-- 快速操作弹窗集合：科技 / 情报 / 外交 / 资产交易
-- 每个弹窗呈现对应模块的可用操作，玩家点击执行
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local Tech = require("systems.tech")
local TechData = require("data.tech_data")
local Combat = require("systems.combat")
local RegionsData = require("data.regions_data")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local ActionModals = {}

local currentModal_ = nil
local onStateChanged_ = nil
local stateRef_ = nil
---@type table|nil UI 根节点引用
local uiRoot_ = nil

--- 设置回调
function ActionModals.SetCallbacks(state, onChanged)
    stateRef_ = state
    onStateChanged_ = onChanged
end

--- 设置 UI 根节点（Modal 必须 AddChild 到 UI 树才能渲染）
function ActionModals.SetRoot(root)
    uiRoot_ = root
end

local function closeModal()
    if currentModal_ then
        currentModal_:Close()
        -- onClose 回调负责 Destroy 和置 nil
    end
end

local function notifyChanged()
    if onStateChanged_ then onStateChanged_() end
end

-- ============================================================================
-- 通用工具
-- ============================================================================
local function listItem(children)
    return UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_card,
        borderWidth = 1, borderColor = C.border_card,
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = children,
    }
end

local function actionBtn(label, bg, onClick, disabled)
    return UI.Panel {
        width = 86, height = 32,
        borderRadius = S.radius_btn,
        backgroundColor = disabled and C.paper_mid or bg,
        justifyContent = "center", alignItems = "center",
        pointerEvents = disabled and "none" or "auto",
        opacity = disabled and 0.55 or 1.0,
        onPointerUp = function(self)
            if not disabled then onClick() end
        end,
        children = {
            UI.Label {
                text = label,
                fontSize = F.body_minor,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 科技研发弹窗（文明6风格科技树）
-- ============================================================================

--- 构建科技树节点数据
local function buildTechTreeNodes(state)
    local allTechs = TechData.GetAll()
    local researched = (state.tech and state.tech.researched) or {}
    local inProgress = state.tech and state.tech.in_progress

    -- 计算每个科技的深度（列号）
    local depthMap = {}
    local function getDepth(techId)
        if depthMap[techId] then return depthMap[techId] end
        local t = TechData.GetById(techId)
        if not t or not t.requires then
            depthMap[techId] = 0
            return 0
        end
        depthMap[techId] = getDepth(t.requires) + 1
        return depthMap[techId]
    end
    for _, t in ipairs(allTechs) do
        getDepth(t.id)
    end

    -- 布局参数
    local nodeSize = 80
    local colGap = 200   -- 列间距（加大避免文字重叠）
    local rowGap = 110   -- 行间距
    local paddingX = 50
    local paddingY = 30

    -- 按深度分组排列
    local colBuckets = {}  -- depth -> { tech, ... }
    for _, t in ipairs(allTechs) do
        local d = depthMap[t.id] or 0
        colBuckets[d] = colBuckets[d] or {}
        table.insert(colBuckets[d], t)
    end

    -- 分配坐标：每列内垂直居中对齐
    local maxRows = 0
    for _, bucket in pairs(colBuckets) do
        maxRows = math.max(maxRows, #bucket)
    end

    local nodes = {}
    for d, bucket in pairs(colBuckets) do
        local colCount = #bucket
        -- 垂直居中偏移
        local offsetY = (maxRows - colCount) * rowGap * 0.5
        for row, t in ipairs(bucket) do
            local isResearched = researched[t.id] == true
            local isInProgress = inProgress and inProgress.id == t.id

            -- 节点显示名称：包含状态标记
            local displayName = t.icon .. " " .. t.name
            if isInProgress then
                displayName = "⏳ " .. t.name
            end

            table.insert(nodes, {
                id = t.id,
                name = displayName,
                icon = t.icon or "🔬",
                x = paddingX + d * colGap,
                y = paddingY + offsetY + (row - 1) * rowGap,
                parentId = t.requires or nil,
                unlocked = isResearched,
                -- 扩展信息
                techData = t,
                inProgress = isInProgress,
            })
        end
    end

    return nodes, nodeSize
end

function ActionModals.ShowTechnology(state, accent)
    closeModal()

    local rows = {}

    -- 研发中进度条
    if state.tech and state.tech.in_progress then
        local ip = state.tech.in_progress
        local t = TechData.GetById(ip.id)
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 2,
            borderLeftColor = accent,
            flexDirection = "column",
            gap = 4,
            children = {
                UI.Label {
                    text = "⏳ 研发中：" .. (t and t.name or ip.id),
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = accent,
                },
                UI.ProgressBar {
                    value = ip.progress / math.max(1, ip.total),
                    width = "100%", height = 6,
                    borderRadius = 3,
                    trackColor = C.bg_surface,
                    fillColor = accent,
                },
                UI.Label {
                    text = string.format("进度 %d / %d 季", ip.progress, ip.total),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
            },
        })
    end

    -- 科技树
    local treeNodes, nodeSize = buildTechTreeNodes(state)
    local hasInProgress = state.tech and state.tech.in_progress

    -- 颜色定义
    local COL_DONE       = { 75, 175, 95, 255 }
    local COL_LOCKED     = { 70, 68, 80, 255 }
    local COL_AVAILABLE  = { 235, 190, 55, 255 }
    local COL_PROGRESS   = { 90, 155, 225, 255 }

    ---@type SkillTree
    local skillTree = UI.SkillTree {
        width = "100%",
        height = 520,
        nodes = treeNodes,
        nodeSize = nodeSize,
        nodeShape = "rounded",
        lineWidth = 3,
        minZoom = 0.5,
        maxZoom = 2.0,
        colors = {
            unlocked    = COL_DONE,
            locked      = COL_LOCKED,
            unlockable  = COL_AVAILABLE,
            line_unlocked = { COL_DONE[1], COL_DONE[2], COL_DONE[3], 200 },
            line_locked   = { 40, 40, 50, 150 },
            background  = { 18, 18, 24, 255 },
            node_border = { 180, 180, 190, 100 },
            text        = { 240, 240, 240, 255 },
        },
        -- 拦截自动解锁：仅用于展示，不允许 SkillTree 自行切换状态
        onNodeUnlock = function(node)
            -- 强制撤销 SkillTree 的自动解锁
            node.unlocked = (state.tech.researched[node.id] == true)
        end,
        onNodeClick = function(node)
            local t = node.techData
            if not t then return end

            -- 已研发
            if state.tech.researched[t.id] then
                UI.Toast.Show("✓ " .. t.name .. " — " .. t.desc,
                    { duration = 2.0 })
                return
            end

            -- 研发中
            if hasInProgress and hasInProgress.id == t.id then
                UI.Toast.Show(string.format("⏳ %s 研发中（%d/%d 季）",
                    t.name, hasInProgress.progress, hasInProgress.total),
                    { duration = 1.8 })
                return
            end

            -- 已有其他科技在研发
            if hasInProgress then
                local ipTech = TechData.GetById(hasInProgress.id)
                UI.Toast.Show("正在研发：" .. (ipTech and ipTech.name or ""),
                    { variant = "warning", duration = 1.5 })
                return
            end

            -- 检查前置
            if t.requires and not state.tech.researched[t.requires] then
                local req = TechData.GetById(t.requires)
                UI.Toast.Show("需要先研发：" .. (req and req.name or t.requires),
                    { variant = "warning", duration = 1.5 })
                return
            end

            -- 尝试研发
            local ok, msg = Tech.Start(state, t.id)
            UI.Toast.Show(msg, {
                variant = ok and "success" or "error", duration = 1.5,
            })
            if ok then
                closeModal()
                notifyChanged()
            end
        end,
    }

    table.insert(rows, skillTree)

    -- 图例
    table.insert(rows, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 16,
        marginTop = 4,
        children = {
            ActionModals._TechLegendItem(COL_DONE, "已研发"),
            ActionModals._TechLegendItem(COL_AVAILABLE, "可研发"),
            ActionModals._TechLegendItem(COL_LOCKED, "未解锁"),
            ActionModals._TechLegendItem(COL_PROGRESS, "研发中"),
        },
    })

    -- 提示
    table.insert(rows, UI.Label {
        text = "点击可研发节点启动研发 · 每次消耗 " .. Balance.TECH.base_research_ap .. " AP · 拖拽平移 · 缩放查看",
        fontSize = F.label,
        fontColor = C.text_muted,
        textAlign = "center",
        width = "100%",
    })

    ActionModals._ShowList("🔬 科技树", rows)
end

--- 科技树图例项
function ActionModals._TechLegendItem(color, label)
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Panel {
                width = 12, height = 12,
                borderRadius = 3,
                backgroundColor = color,
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
            },
        },
    }
end

-- ============================================================================
-- 情报行动弹窗
-- ============================================================================
function ActionModals.ShowIntelligence(state, accent)
    closeModal()

    local rows = {}
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction  -- 闭包捕获
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 2,
            borderLeftColor = accent,
            flexDirection = "column",
            gap = 6,
            children = {
                UI.Label {
                    text = (faction.icon or "") .. " " .. faction.name,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                -- 已知情报（侦察后显示）
                faction.scouted and UI.Label {
                    text = string.format("情报：现金 %d  势力 %d  态度 %d",
                        faction.cash, faction.power, faction.attitude),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                } or UI.Label {
                    text = "情报：未知（先侦察）",
                    fontSize = F.label,
                    fontColor = C.text_muted,
                },
                -- 3 个行动按钮
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    children = {
                        actionBtn("侦察",
                            C.accent_blue,
                            function() ActionModals._IntelScout(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.INTEL.scout)),
                        actionBtn("渗透",
                            C.accent_amber,
                            function() ActionModals._IntelInfiltrate(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.INTEL.infiltrate, Balance.INFLUENCE.cost_infiltrate)),
                        actionBtn("收买",
                            C.accent_green,
                            function() ActionModals._IntelBribe(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.INTEL.bribe, Balance.INFLUENCE.cost_bribe)),
                    },
                },
            },
        })
    end

    ActionModals._ShowList("👁️ 情报行动", rows)
end

--- 检查是否负担得起（AP + 现金 + 可选 influence）
---@param state table
---@param cfg table { ap, cash }
---@param influenceCost number|nil 额外的影响力消耗（可选）
function ActionModals._CanAfford(state, cfg, influenceCost)
    if state.cash < (cfg.cash or 0) then return false end
    if (state.ap.current + (state.ap.temp or 0)) < (cfg.ap or 0) then return false end
    if influenceCost and influenceCost > 0 then
        local totalInfluence = GameState.CalcTotalInfluence(state)
        if totalInfluence < influenceCost then return false end
    end
    return true
end

--- 原子扣费：同时扣 AP、现金、可选 influence
---@param state table
---@param cfg table
---@param influenceCost number|nil
function ActionModals._Spend(state, cfg, influenceCost)
    if not ActionModals._CanAfford(state, cfg, influenceCost) then return false end
    local apOk = GameState.SpendAP(state, cfg.ap or 0)
    if not apOk then return false end
    state.cash = state.cash - (cfg.cash or 0)
    -- 扣除 influence：按比例从各地区扣减
    if influenceCost and influenceCost > 0 then
        local totalInf = GameState.CalcTotalInfluence(state)
        if totalInf > 0 then
            for _, r in ipairs(state.regions) do
                local ratio = (r.influence or 0) / totalInf
                local loss = math.floor(influenceCost * ratio + 0.5)
                r.influence = math.max(0, (r.influence or 0) - loss)
            end
        end
    end
    return true
end

function ActionModals._IntelScout(state, faction)
    local cfg = Balance.INTEL.scout
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.scouted = true
    GameState.AddLog(state, string.format("[情报] 侦察 %s：现金 %d，势力 %d",
        faction.name, faction.cash, faction.power))
    UI.Toast.Show("侦察完成，情报已更新", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._IntelInfiltrate(state, faction)
    local cfg = Balance.INTEL.infiltrate
    local infCost = Balance.INFLUENCE.cost_infiltrate
    if not ActionModals._CanAfford(state, cfg, infCost) then
        UI.Toast.Show("资源不足（需影响力≥" .. infCost .. "）", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg, infCost)
    faction.growth_mod = cfg.growth_debuff
    faction.growth_mod_remaining = cfg.duration
    GameState.AddLog(state, string.format("[情报] 渗透 %s，%d 季内增长 %.0f%%",
        faction.name, cfg.duration, cfg.growth_debuff * 100))
    UI.Toast.Show("渗透成功", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._IntelBribe(state, faction)
    local cfg = Balance.INTEL.bribe
    local infCost = Balance.INFLUENCE.cost_bribe
    if not ActionModals._CanAfford(state, cfg, infCost) then
        UI.Toast.Show("资源不足（需影响力≥" .. infCost .. "）", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg, infCost)
    faction.attitude = math.min(100, faction.attitude + cfg.attitude_gain)
    GameState.AddLog(state, string.format("[情报] 收买 %s，态度 +%d → %d",
        faction.name, cfg.attitude_gain, faction.attitude))
    UI.Toast.Show("收买完成", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 外交弹窗
-- ============================================================================
function ActionModals.ShowDiplomacy(state, accent)
    closeModal()

    local rows = {}
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction
        local pactText = (faction.pact_remaining and faction.pact_remaining > 0)
            and string.format("  🤝协议剩 %d 季", faction.pact_remaining) or ""
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 2,
            borderLeftColor = accent,
            flexDirection = "column",
            gap = 6,
            children = {
                UI.Label {
                    text = (faction.icon or "") .. " " .. faction.name
                        .. "  态度 " .. faction.attitude .. pactText,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    children = {
                        actionBtn("送礼",
                            C.accent_green,
                            function() ActionModals._DiploGift(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.gift)),
                        actionBtn("协议",
                            C.accent_blue,
                            function() ActionModals._DiploTreaty(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.treaty, Balance.INFLUENCE.cost_treaty)),
                        actionBtn("敌对",
                            C.accent_red,
                            function() ActionModals._DiploHostile(state, factionLocal) end,
                            not ActionModals._CanAfford(state, Balance.DIPLOMACY.hostile)),
                    },
                },
            },
        })
    end

    ActionModals._ShowList("🤝 政治外交", rows)
end

function ActionModals._DiploGift(state, faction)
    local cfg = Balance.DIPLOMACY.gift
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.attitude = math.min(100, faction.attitude + cfg.attitude)
    GameState.AddLog(state, string.format("[外交] 向 %s 送礼，态度 +%d",
        faction.name, cfg.attitude))
    UI.Toast.Show("礼物已送达", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._DiploTreaty(state, faction)
    local cfg = Balance.DIPLOMACY.treaty
    local infCost = Balance.INFLUENCE.cost_treaty
    if faction.attitude < cfg.attitude_req then
        UI.Toast.Show(string.format("需要态度 ≥ %d 才能签订协议", cfg.attitude_req),
            { variant = "warning", duration = 1.5 })
        return
    end
    if not ActionModals._CanAfford(state, cfg, infCost) then
        UI.Toast.Show("资源不足（需影响力≥" .. infCost .. "）", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg, infCost)
    faction.attitude = math.min(100, faction.attitude + cfg.attitude)
    faction.pact_remaining = cfg.pact_turns
    GameState.AddLog(state, string.format("[外交] 与 %s 签订协议，%d 季互不侵犯",
        faction.name, cfg.pact_turns))
    UI.Toast.Show("协议已签订", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._DiploHostile(state, faction)
    local cfg = Balance.DIPLOMACY.hostile
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.attitude = math.max(-100, faction.attitude + cfg.attitude)
    faction.pact_remaining = 0
    GameState.AddLog(state, string.format("[外交] 与 %s 断交，态度 %d",
        faction.name, faction.attitude))
    UI.Toast.Show("已宣布敌对", { variant = "warning", duration = 1.5 })
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 资产交易弹窗
-- ============================================================================
function ActionModals.ShowTrade(state, accent)
    closeModal()

    local rows = {}

    -- 开发新矿
    local maxMines = Balance.TRADE.new_mine.max_mines or 8
    local minesFull = #state.mines >= maxMines
    table.insert(rows, ActionModals._TradeOption(
        "⛏️ 开发新矿区",
        string.format("投入 %d 克朗 / %d AP 建立一座新矿（%d/%d）",
            Balance.TRADE.new_mine.cash, Balance.TRADE.new_mine.ap,
            #state.mines, maxMines),
        accent,
        function() ActionModals._TradeNewMine(state) end,
        minesFull or not ActionModals._CanAfford(state, Balance.TRADE.new_mine)
    ))

    -- 出售矿山
    for _, mine in ipairs(state.mines) do
        if mine.active and #state.mines > 1 then
            local mineLocal = mine
            local salePrice = mine.level * Balance.TRADE.sell_mine.cash_per_level
            table.insert(rows, ActionModals._TradeOption(
                "💸 出售 " .. mine.name,
                string.format("得现金 %d 克朗（Lv.%d）",
                    salePrice, mine.level),
                accent,
                function() ActionModals._TradeSellMine(state, mineLocal, salePrice) end,
                false
            ))
        end
    end

    -- 对 AI 发起资本攻击
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction
        table.insert(rows, ActionModals._TradeOption(
            "⚔ 资本攻击：" .. faction.name,
            string.format("花 %d 克朗削弱 AI 资金 %d / 势力 -%d",
                Balance.TRADE.raid_ai.cash,
                Balance.TRADE.raid_ai.ai_cash_loss,
                Balance.TRADE.raid_ai.power_loss),
            accent,
            function() ActionModals._TradeRaid(state, factionLocal) end,
            not ActionModals._CanAfford(state, Balance.TRADE.raid_ai)
        ))
    end

    ActionModals._ShowList("🏭 资产交易", rows)
end

function ActionModals._TradeOption(title, desc, accent, onClick, disabled)
    return UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderLeftWidth = 2,
        borderLeftColor = accent,
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                flexDirection = "column",
                gap = 2,
                children = {
                    UI.Label {
                        text = title,
                        fontSize = F.body,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = desc,
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                        whiteSpace = "normal",
                    },
                },
            },
            actionBtn("执行", accent, onClick, disabled),
        },
    }
end

function ActionModals._TradeNewMine(state)
    local cfg = Balance.TRADE.new_mine
    -- 检查矿山数量上限
    local maxMines = cfg.max_mines or 8
    if #state.mines >= maxMines then
        UI.Toast.Show(string.format("矿山已达上限（%d/%d）", #state.mines, maxMines),
            { variant = "warning", duration = 1.5 })
        return
    end
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    local id = "mine_" .. tostring(state.turn_count) .. "_" .. tostring(math.random(1000, 9999))
    -- 扩展矿区资源
    local region = state.regions[1]  -- 放在主矿区上
    for _, r in ipairs(state.regions) do
        if r.id == "mine_district" then region = r; break end
    end
    if region and region.resources then
        region.resources.gold_reserve = (region.resources.gold_reserve or 0) + cfg.base_reserve
    end
    table.insert(state.mines, {
        id = id,
        name = "新矿井 #" .. (#state.mines + 1),
        region_id = region and region.id or "mine_district",
        level = 1,
        output_bonus = 0,
        active = true,
    })
    GameState.AddLog(state, string.format("[交易] 新矿开发完成，储量 +%d", cfg.base_reserve))
    UI.Toast.Show("新矿已建成", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._TradeSellMine(state, mine, price)
    if not GameState.SpendAP(state, Balance.TRADE.sell_mine.ap) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.2 })
        return
    end
    state.cash = state.cash + price
    -- 从矿山数组移除
    local kept = {}
    for _, m in ipairs(state.mines) do
        if m ~= mine then table.insert(kept, m) end
    end
    state.mines = kept
    GameState.AddLog(state, string.format("[交易] 出售 %s，得 %d 克朗", mine.name, price))
    UI.Toast.Show("已出售 " .. mine.name, { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

function ActionModals._TradeRaid(state, faction)
    local cfg = Balance.TRADE.raid_ai
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    faction.cash = math.max(0, faction.cash - cfg.ai_cash_loss)
    faction.power = math.max(0, faction.power - cfg.power_loss)
    faction.attitude = math.max(-100, faction.attitude - 15)
    GameState.AddLog(state, string.format("[交易] 对 %s 发动资本攻击：现金 -%d 势力 -%d",
        faction.name, cfg.ai_cash_loss, cfg.power_loss))
    UI.Toast.Show("资本攻击成功", { variant = "success", duration = 1.5 })
    closeModal()
    notifyChanged()
end

-- ============================================================================
-- 通用列表弹窗
-- ============================================================================
function ActionModals._ShowList(title, rows)
    currentModal_ = UI.Modal {
        title = title,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            currentModal_ = nil
            self:Destroy()
        end,
    }
    local content = UI.ScrollView {
        width = "100%",
        maxHeight = 480,
        flexShrink = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                children = rows,
            },
        },
    }
    currentModal_:AddContent(content)
    -- Modal 必须加入 UI 树才能渲染
    if uiRoot_ then
        uiRoot_:AddChild(currentModal_)
    end
    currentModal_:Open()
end

return ActionModals
