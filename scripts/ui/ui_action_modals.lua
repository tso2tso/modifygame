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

local AudioManager = require("systems.audio_manager")

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
        AudioManager.PlayUI("ui_modal_close")
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
        onPointerUp = Config.TapGuard(function(self)
            if not disabled then onClick() end
        end),
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
-- 科技研发弹窗（文明6风格科技树 — 30 科技扩展版）
-- ============================================================================

--- 效果 kind → 可读描述映射
local EFFECT_LABELS = {
    mine_output_base  = function(v) return string.format("矿山基础产出 +%d", v) end,
    mine_output_mult  = function(v) return string.format("矿山产出 +%d%%", math.floor(v * 100)) end,
    security_bonus    = function(v) return string.format("矿区安全 +%d", v) end,
    accident_reduction= function(v) return string.format("事故概率 %d%%", math.floor(v * 100)) end,
    worker_efficiency = function(v) return string.format("工人效率 +%d%%", math.floor(v * 100)) end,
    tax_reduction     = function(v) return string.format("税率 %d%%", math.floor(v * 100)) end,
    ap_bonus          = function(v) return string.format("行动点上限 +%d", v) end,
    equipment_up      = function(v) return string.format("装备等级 +%d", v) end,
    supply_reduction  = function(v) return string.format("补给消耗 %d", v) end,
    finance_network   = function() return "补给成本 -20%，被动收入 +80" end,
    stock_boost_all   = function(v) return string.format("股票收益率 +%d%%", math.floor(v * 100)) end,
    influence_gain    = function(v) return string.format("每季影响力 +%d", v) end,
    morale_bonus      = function(v) return string.format("士气 +%d", v) end,
    guard_power_bonus = function(v) return string.format("护卫战力 +%d%%", math.floor(v * 100)) end,
    research_speed    = function(v) return string.format("研发速度 +%d%%", math.floor(v * 100)) end,
    trade_income      = function(v) return string.format("每季贸易收入 +%d", v) end,
    gold_price_bonus  = function(v) return string.format("黄金售价 +%d%%", math.floor(v * 100)) end,
    hire_cost_reduction = function(v) return string.format("雇佣成本 %d%%", math.floor(v * 100)) end,
    mine_slots          = function(v) return string.format("矿山槽位 +%d", v) end,
    prospect_success    = function(v) return string.format("探矿成功率 +%d%%", math.floor(v * 100)) end,
}

--- 解析管道式 requires，返回第一个前置id（用于深度计算）
---@param requires string|nil
---@return string|nil
local function getFirstRequire(requires)
    if not requires then return nil end
    -- "a|b" → 取第一个
    local first = requires:match("^([^|]+)")
    return first
end

--- 解析管道式 requires，返回所有前置id列表
---@param requires string|nil
---@return string[]
local function getAllRequires(requires)
    if not requires then return {} end
    local list = {}
    for part in requires:gmatch("[^|]+") do
        table.insert(list, part)
    end
    return list
end

--- 检查前置科技是否满足（支持 "a|b" 管道语法）
---@param requires string|nil
---@param researched table
---@return boolean
local function checkReqMet(requires, researched)
    if not requires then return true end
    if requires:find("|") then
        for part in requires:gmatch("[^|]+") do
            if researched[part] then return true end
        end
        return false
    end
    return researched[requires] == true
end

--- 构建科技树节点数据
local function buildTechTreeNodes(state)
    local allTechs = TechData.GetAll()
    local researched = (state.tech and state.tech.researched) or {}
    local inProgress = state.tech and state.tech.in_progress

    -- 计算每个科技的深度（列号），支持管道式 requires
    local depthMap = {}
    local function getDepth(techId)
        if depthMap[techId] then return depthMap[techId] end
        local t = TechData.GetById(techId)
        if not t or not t.requires then
            depthMap[techId] = 0
            return 0
        end
        -- 管道式: 取所有前置中最大深度 + 1
        local parents = getAllRequires(t.requires)
        local maxD = 0
        for _, pid in ipairs(parents) do
            maxD = math.max(maxD, getDepth(pid))
        end
        depthMap[techId] = maxD + 1
        return depthMap[techId]
    end
    for _, t in ipairs(allTechs) do
        getDepth(t.id)
    end

    -- 布局参数
    local nodeSize = 80
    local colGap = 220
    local rowGap = 110
    local paddingX = 50
    local paddingY = 30

    -- 按深度分组排列
    local colBuckets = {}
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
        local offsetY = (maxRows - colCount) * rowGap * 0.5
        for row, t in ipairs(bucket) do
            local isResearched = researched[t.id] == true
            local isInProgress = inProgress and inProgress.id == t.id
            local isExcluded = t.excludes and researched[t.excludes] == true

            local displayName = t.icon .. " " .. t.name
            if isInProgress then
                displayName = "⏳ " .. t.name
            elseif isExcluded then
                displayName = "🚫 " .. t.name
            end

            -- parentId: 取第一个前置用于连线
            local parentId = getFirstRequire(t.requires)

            table.insert(nodes, {
                id = t.id,
                name = displayName,
                icon = t.icon or "🔬",
                x = paddingX + d * colGap,
                y = paddingY + offsetY + (row - 1) * rowGap,
                parentId = parentId,
                unlocked = isResearched,
                techData = t,
                inProgress = isInProgress,
                excluded = isExcluded,
            })
        end
    end

    return nodes, nodeSize
end

local detailModal_ = nil
--- 模块级引用：科技树 detail 容器和滚动内容面板
local techDetailContainer_ = nil
local techScrollContent_ = nil
local techSelectedId_ = nil
--- 显示科技详情弹窗
---@param state table
---@param tech table 科技数据
---@param accent table 强调色
local function showTechDetail(state, tech, accent)
    if detailModal_ then
        local dm = detailModal_
        detailModal_ = nil
        dm:Close()  -- onClose 回调会调用 Destroy()
    end

    local researched = (state.tech and state.tech.researched) or {}
    local isResearched = researched[tech.id] == true
    local inProgress = state.tech and state.tech.in_progress
    local isInProgress = inProgress and inProgress.id == tech.id
    local hasOtherInProgress = inProgress and inProgress.id ~= tech.id
    local reqMet = checkReqMet(tech.requires, researched)
    local isExcluded = tech.excludes and researched[tech.excludes] == true
    local inflatedCost = math.floor(tech.cost * GameState.GetInflationFactor(state))
    local canAfford = state.cash >= inflatedCost
    local hasAP = (state.ap.current + (state.ap.temp or 0)) >= Balance.TECH.base_research_ap

    -- 状态标签
    local statusText, statusColor
    if isResearched then
        statusText = "✓ 已研发"
        statusColor = { 75, 175, 95, 255 }
    elseif isExcluded then
        local exTech = TechData.GetById(tech.excludes)
        statusText = "🚫 已被排除（" .. (exTech and exTech.name or "?") .. "）"
        statusColor = { 160, 80, 80, 255 }
    elseif isInProgress then
        statusText = string.format("⏳ 研发中 %d/%d 季", inProgress.progress, inProgress.total)
        statusColor = { 90, 155, 225, 255 }
    elseif not reqMet then
        statusText = "🔒 未解锁"
        statusColor = { 120, 120, 140, 255 }
    elseif hasOtherInProgress then
        statusText = "⏸ 等待中"
        statusColor = { 168, 152, 128, 255 }
    else
        statusText = "🔓 可研发"
        statusColor = { 235, 190, 55, 255 }
    end

    -- 构建效果列表
    local effectRows = {}
    for _, eff in ipairs(tech.effects or {}) do
        local formatter = EFFECT_LABELS[eff.kind]
        local label = formatter and formatter(eff.value) or (eff.kind .. " " .. tostring(eff.value or ""))
        table.insert(effectRows, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Panel {
                    width = 6, height = 6,
                    borderRadius = 3,
                    backgroundColor = accent,
                },
                UI.Label {
                    text = label,
                    fontSize = F.body,
                    fontColor = C.text_primary,
                },
            },
        })
    end

    -- 前置科技信息（支持管道式）
    local reqText = "无"
    if tech.requires then
        local parts = getAllRequires(tech.requires)
        local reqParts = {}
        for _, pid in ipairs(parts) do
            local req = TechData.GetById(pid)
            if req then
                local reqDone = researched[req.id] == true
                table.insert(reqParts, req.icon .. " " .. req.name .. (reqDone and " ✓" or " ✗"))
            end
        end
        reqText = table.concat(reqParts, " 或 ")
    end

    -- 内容面板
    local contentChildren = {
        -- 标题行：图标 + 名称 + 时代标签
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = tech.icon .. " " .. tech.name,
                    fontSize = F.card_title,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Panel {
                    paddingLeft = 8, paddingRight = 8,
                    paddingTop = 2, paddingBottom = 2,
                    borderRadius = 4,
                    backgroundColor = C.paper_mid,
                    children = {
                        UI.Label {
                            text = tech.era_hint or "",
                            fontSize = F.label,
                            fontColor = C.text_secondary,
                        },
                    },
                },
            },
        },
        -- 状态
        UI.Label {
            text = statusText,
            fontSize = F.body,
            fontWeight = "bold",
            fontColor = statusColor,
        },
        -- 分割线
        UI.Panel {
            width = "100%", height = 1,
            backgroundColor = C.paper_light,
            marginTop = 2, marginBottom = 2,
        },
        -- 描述
        UI.Label {
            text = tech.desc,
            fontSize = F.body,
            fontColor = C.text_secondary,
            whiteSpace = "normal",
            width = "100%",
        },
        -- 效果标题
        UI.Label {
            text = "效果：",
            fontSize = F.body,
            fontWeight = "bold",
            fontColor = accent,
            marginTop = 4,
        },
    }

    -- 添加效果列表
    for _, row in ipairs(effectRows) do
        table.insert(contentChildren, row)
    end

    -- 分割线
    table.insert(contentChildren, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = C.paper_light,
        marginTop = 4, marginBottom = 4,
    })

    -- 费用/时间/前置
    table.insert(contentChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 12,
        children = {
            UI.Label {
                text = string.format("费用 %d 克朗", inflatedCost),
                fontSize = F.body_minor,
                fontColor = canAfford and C.text_primary or C.accent_red,
            },
            UI.Label {
                text = string.format("研发 %d 季", tech.turns),
                fontSize = F.body_minor,
                fontColor = C.text_primary,
            },
            UI.Label {
                text = string.format("AP %d", Balance.TECH.base_research_ap),
                fontSize = F.body_minor,
                fontColor = hasAP and C.text_primary or C.accent_red,
            },
        },
    })
    table.insert(contentChildren, UI.Label {
        text = "前置：" .. reqText,
        fontSize = F.body_minor,
        fontColor = C.text_secondary,
    })

    -- 互斥提示
    if tech.excludes then
        local exTech = TechData.GetById(tech.excludes)
        local exName = exTech and (exTech.icon .. " " .. exTech.name) or tech.excludes
        local exDone = researched[tech.excludes] == true
        table.insert(contentChildren, UI.Label {
            text = "互斥：" .. exName .. (exDone and " (已研发)" or ""),
            fontSize = F.body_minor,
            fontColor = exDone and C.accent_red or C.text_secondary,
        })
    end

    -- 研发按钮（仅在可研发时显示）
    if not isResearched and not isInProgress and not isExcluded then
        local canStart = reqMet and canAfford and hasAP and not hasOtherInProgress
        local btnLabel = not reqMet and "需要前置科技"
            or hasOtherInProgress and "正在研发其他科技"
            or not canAfford and "资金不足"
            or not hasAP and "行动点不足"
            or "开始研发"
        table.insert(contentChildren, UI.Panel {
            width = "100%",
            marginTop = 6,
            height = 36,
            borderRadius = S.radius_btn,
            backgroundColor = canStart and accent or C.paper_mid,
            justifyContent = "center",
            alignItems = "center",
            opacity = canStart and 1.0 or 0.55,
            pointerEvents = canStart and "auto" or "none",
            onPointerUp = Config.TapGuard(function()
                if not canStart then return end
                local ok, msg = Tech.Start(state, tech.id)
                UI.Toast.Show(msg, {
                    variant = ok and "success" or "error", duration = 1.5,
                })
                if ok then
                    local dm = detailModal_
                    detailModal_ = nil
                    if dm then
                        dm:Close()  -- onClose 回调会调用 Destroy()
                    end
                    closeModal()
                    notifyChanged()
                end
            end),
            children = {
                UI.Label {
                    text = btnLabel,
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = { 255, 255, 255, 255 },
                    pointerEvents = "none",
                },
            },
        })
    end

    detailModal_ = UI.Modal {
        title = "科技详情",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            if detailModal_ == self then
                detailModal_ = nil
            end
            self:Destroy()
        end,
    }
    local content = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 6,
        padding = 4,
        children = contentChildren,
    }
    detailModal_:AddContent(content)
    if uiRoot_ then
        uiRoot_:AddChild(detailModal_)
    end
    detailModal_:Open()
end

local TECH_LANES = {
    { id = "a", title = "A · 采矿", desc = "产出 / 安全 / 工人效率" },
    { id = "b", title = "B · 经济", desc = "税率 / 贸易 / 金融 AP" },
    { id = "c", title = "C · 军事", desc = "装备 / 补给 / 战力" },
    { id = "d", title = "D · 文化", desc = "影响力 / 士气 / 研发速度" },
}

local function getTechState(state, tech)
    local researched = state.tech and state.tech.researched or {}
    local inProgress = state.tech and state.tech.in_progress
    local reqMet = checkReqMet(tech.requires, researched)
    local isExcluded = tech.excludes and researched[tech.excludes] == true
    local isDone = researched[tech.id] == true
    local isProgress = inProgress and inProgress.id == tech.id
    local hasOtherProgress = inProgress and inProgress.id ~= tech.id
    local inflatedCost = math.floor(tech.cost * GameState.GetInflationFactor(state))
    local canAfford = state.cash >= inflatedCost
    local hasAP = (state.ap.current + (state.ap.temp or 0)) >= Balance.TECH.base_research_ap
    local canStart = (not isDone) and (not isProgress) and (not isExcluded)
        and reqMet and canAfford and hasAP and not hasOtherProgress

    local label = "未解锁"
    local color = C.paper_mid
    if isDone then
        label = "已研发"
        color = C.accent_green
    elseif isExcluded then
        label = "已排除"
        color = C.accent_red
    elseif isProgress then
        label = "研发中"
        color = C.accent_blue
    elseif canStart then
        label = "可研发"
        color = C.accent_gold
    elseif reqMet then
        label = hasOtherProgress and "等待" or "资源不足"
        color = C.text_muted
    end

    return {
        label = label,
        color = color,
        reqMet = reqMet,
        isExcluded = isExcluded,
        isDone = isDone,
        isProgress = isProgress,
        hasOtherProgress = hasOtherProgress,
        canAfford = canAfford,
        hasAP = hasAP,
        canStart = canStart,
        inflatedCost = inflatedCost,
    }
end

local function findDefaultTechId(state)
    local inProgress = state.tech and state.tech.in_progress
    if inProgress then return inProgress.id end
    for _, tech in ipairs(TechData.GetAll()) do
        if getTechState(state, tech).canStart then return tech.id end
    end
    local allTechs = TechData.GetAll()
    return allTechs[1] and allTechs[1].id or nil
end

local function createInlineDivider()
    return UI.Panel {
        width = "100%",
        height = 1,
        backgroundColor = C.divider,
    }
end

local function createTechStatusBar(state, accent)
    local inProgress = state.tech and state.tech.in_progress
    local tech = inProgress and TechData.GetById(inProgress.id) or nil

    if not inProgress or not tech then
        return UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = C.border_card,
            flexDirection = "column",
            gap = 4,
            children = {
                UI.Label {
                    text = "当前无研发项目",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = "选择一个可研发科技开始推进。建议优先完成每条线的前置节点。",
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                    whiteSpace = "normal",
                },
            },
        }
    end

    local progress = inProgress.progress / math.max(1, inProgress.total)
    return UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderLeftWidth = 3,
        borderLeftColor = accent,
        flexDirection = "column",
        gap = 6,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "研发中：" .. tech.name,
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = accent,
                    },
                    UI.Label {
                        text = string.format("%d/%d 季", inProgress.progress, inProgress.total),
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                    },
                },
            },
            UI.ProgressBar {
                value = progress,
                width = "100%",
                height = 7,
                borderRadius = 4,
                trackColor = C.bg_surface,
                fillColor = accent,
            },
        },
    }
end

local function createTechNodeButton(state, accent, tech)
    local st = getTechState(state, tech)
    local borderColor = st.canStart and C.accent_gold or C.border_card
    local bg = st.isDone and { C.accent_green[1], C.accent_green[2], C.accent_green[3], 50 }
        or st.isProgress and { C.accent_blue[1], C.accent_blue[2], C.accent_blue[3], 50 }
        or st.canStart and { C.accent_gold[1], C.accent_gold[2], C.accent_gold[3], 42 }
        or C.bg_elevated

    return UI.Panel {
        width = 128,
        minHeight = 68,
        padding = 8,
        backgroundColor = bg,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = borderColor,
        flexDirection = "column",
        justifyContent = "space-between",
        gap = 4,
        pointerEvents = "auto",
        onPointerUp = Config.TapGuard(function()
            ActionModals._UpdateTechDetail(state, accent, tech.id)
        end),
        children = {
            UI.Label {
                text = tech.icon .. " " .. tech.name,
                fontSize = F.body_minor,
                fontWeight = st.canStart and "bold" or "medium",
                fontColor = st.reqMet and C.text_primary or C.text_muted,
                whiteSpace = "normal",
                pointerEvents = "none",
            },
            UI.Label {
                text = st.label,
                fontSize = F.label,
                fontColor = st.color,
                pointerEvents = "none",
            },
        },
    }
end

local function createTechLane(state, accent, lane)
    local nodes = {}
    for _, tech in ipairs(TechData.GetAll()) do
        if string.sub(tech.id, 1, 1) == lane.id then
            table.insert(nodes, createTechNodeButton(state, accent, tech))
        end
    end

    return UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = lane.title,
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = lane.desc,
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 8,
                children = nodes,
            },
        },
    }
end

local function createTechDetailPanel(state, accent, techId)
    local tech = techId and TechData.GetById(techId) or nil
    if not tech then
        return UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            children = {
                UI.Label {
                    text = "选择一个科技查看详情",
                    fontSize = F.body,
                    fontColor = C.text_secondary,
                },
            },
        }
    end

    local st = getTechState(state, tech)
    local effectRows = {}
    for _, eff in ipairs(tech.effects or {}) do
        local formatter = EFFECT_LABELS[eff.kind]
        local label = formatter and formatter(eff.value) or (eff.kind .. " " .. tostring(eff.value or ""))
        table.insert(effectRows, UI.Label {
            text = "• " .. label,
            fontSize = F.body_minor,
            fontColor = C.text_primary,
            whiteSpace = "normal",
        })
    end

    local reqText = "无"
    if tech.requires then
        local parts = getAllRequires(tech.requires)
        local reqParts = {}
        for _, pid in ipairs(parts) do
            local req = TechData.GetById(pid)
            if req then
                local reqDone = state.tech and state.tech.researched and state.tech.researched[req.id]
                table.insert(reqParts, req.name .. (reqDone and " ✓" or " ✗"))
            end
        end
        reqText = table.concat(reqParts, " / ")
    end

    local btnLabel = st.isDone and "已完成"
        or st.isExcluded and "互斥已排除"
        or st.isProgress and "研发进行中"
        or (not st.reqMet) and "需要前置科技"
        or st.hasOtherProgress and "已有研发项目"
        or (not st.canAfford) and "资金不足"
        or (not st.hasAP) and "行动点不足"
        or "开始研发"

    local children = {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = tech.icon .. " " .. tech.name,
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = st.label,
                    fontSize = F.label,
                    fontWeight = "bold",
                    fontColor = st.color,
                },
            },
        },
        UI.Label {
            text = tech.desc,
            fontSize = F.body_minor,
            fontColor = C.text_secondary,
            whiteSpace = "normal",
        },
        createInlineDivider(),
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 12,
            children = {
                UI.Label {
                    text = "费用 " .. st.inflatedCost,
                    fontSize = F.body_minor,
                    fontColor = st.canAfford and C.text_primary or C.accent_red,
                },
                UI.Label {
                    text = "周期 " .. tech.turns .. " 季",
                    fontSize = F.body_minor,
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = "AP " .. Balance.TECH.base_research_ap,
                    fontSize = F.body_minor,
                    fontColor = st.hasAP and C.text_primary or C.accent_red,
                },
                UI.Label {
                    text = "前置 " .. reqText,
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                },
            },
        },
        UI.Label {
            text = "效果",
            fontSize = F.body_minor,
            fontWeight = "bold",
            fontColor = accent,
        },
    }
    for _, row in ipairs(effectRows) do
        table.insert(children, row)
    end
    table.insert(children, UI.Panel {
        width = "100%",
        height = 34,
        marginTop = 4,
        borderRadius = S.radius_btn,
        backgroundColor = st.canStart and accent or C.paper_mid,
        justifyContent = "center",
        alignItems = "center",
        opacity = st.canStart and 1.0 or 0.55,
        pointerEvents = st.canStart and "auto" or "none",
        onPointerUp = Config.TapGuard(function()
            if not st.canStart then return end
            local ok, msg = Tech.Start(state, tech.id)
            UI.Toast.Show(msg, {
                variant = ok and "success" or "error",
                duration = 1.5,
            })
            if ok then
                closeModal()
                notifyChanged()
            end
        end),
        children = {
            UI.Label {
                text = btnLabel,
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
                pointerEvents = "none",
            },
        },
    })

    return UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = accent,
        flexDirection = "column",
        gap = 8,
        children = children,
    }
end

--- 构建科技研发的滚动内容
local function buildTechContent(state, accent, selectedTechId)
    local rows = {}

    table.insert(rows, createTechStatusBar(state, accent))

    table.insert(rows, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 14,
        children = {
            ActionModals._TechLegendItem(C.accent_green, "已研发"),
            ActionModals._TechLegendItem(C.accent_gold, "可研发"),
            ActionModals._TechLegendItem(C.accent_blue, "研发中"),
            ActionModals._TechLegendItem(C.paper_mid, "未解锁"),
        },
    })

    for _, lane in ipairs(TECH_LANES) do
        table.insert(rows, createTechLane(state, accent, lane))
    end

    -- detail 面板放入一个容器，便于后续局部替换
    techDetailContainer_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        children = {
            createTechDetailPanel(state, accent, selectedTechId),
        },
    }
    table.insert(rows, techDetailContainer_)

    table.insert(rows, UI.Label {
        text = "点击科技节点查看详情，四条线独立，同时只能研发一项。",
        fontSize = F.label,
        fontColor = C.text_muted,
        textAlign = "center",
        width = "100%",
    })

    return UI.ScrollView {
        width = "100%",
        maxHeight = 480,
        flexShrink = 1,
        bounces = false,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                children = rows,
            },
        },
    }
end

--- 仅更新 detail 面板（不重建 ScrollView，保留滚动位置）
function ActionModals._UpdateTechDetail(state, accent, techId)
    techSelectedId_ = techId
    if techDetailContainer_ then
        techDetailContainer_:ClearChildren()
        techDetailContainer_:AddChild(createTechDetailPanel(state, accent, techId))
    end
end

function ActionModals.ShowTechnology(state, accent, selectedTechId)
    selectedTechId = selectedTechId or findDefaultTechId(state)
    techSelectedId_ = selectedTechId

    -- 如果科技弹窗已打开，只替换 detail 面板
    if currentModal_ and currentModal_._isTechModal then
        ActionModals._UpdateTechDetail(state, accent, selectedTechId)
        return
    end

    AudioManager.PlayUI("ui_modal_open")

    closeModal()
    techDetailContainer_ = nil

    currentModal_ = UI.Modal {
        title = "🔬 科技研发",
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            currentModal_ = nil
            techDetailContainer_ = nil
            techSelectedId_ = nil
            self:Destroy()
        end,
    }
    currentModal_._isTechModal = true

    currentModal_:AddContent(buildTechContent(state, accent, selectedTechId))

    if uiRoot_ then
        uiRoot_:AddChild(currentModal_)
    end
    currentModal_:Open()
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
    AudioManager.PlayUI("ui_modal_open")
    closeModal()

    local rows = {}
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction  -- 闭包捕获
        -- 瘫痪势力显示特殊卡片
        if faction.collapsed then
            table.insert(rows, UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = { 40, 40, 45, 255 },
                borderRadius = S.radius_card,
                borderLeftWidth = 2,
                borderLeftColor = { 100, 100, 100, 255 },
                flexDirection = "column",
                gap = 6,
                opacity = 0.7,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label {
                                text = "💀 " .. faction.name,
                                fontSize = F.body,
                                fontWeight = "bold",
                                fontColor = { 140, 140, 140, 255 },
                            },
                            UI.Panel {
                                paddingHorizontal = 5,
                                paddingVertical = 1,
                                backgroundColor = { 180, 50, 50, 50 },
                                borderRadius = S.radius_badge,
                                children = {
                                    UI.Label {
                                        text = "已瘫痪",
                                        fontSize = F.label,
                                        fontColor = C.accent_red,
                                    },
                                },
                            },
                        },
                    },
                    UI.Label {
                        text = "该势力已崩溃，无需情报行动",
                        fontSize = F.label,
                        fontColor = { 120, 120, 120, 255 },
                    },
                },
            })
        else
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
    end

    ActionModals._ShowList("👁️ 情报行动", rows)
end

--- 检查是否负担得起（AP + 现金×通胀 + 可选 influence）
---@param state table
---@param cfg table { ap, cash }
---@param influenceCost number|nil 额外的影响力消耗（可选）
function ActionModals._CanAfford(state, cfg, influenceCost)
    local inflation = GameState.GetInflationFactor(state)
    if state.cash < math.floor((cfg.cash or 0) * inflation) then return false end
    if (state.ap.current + (state.ap.temp or 0)) < (cfg.ap or 0) then return false end
    if influenceCost and influenceCost > 0 then
        local totalInfluence = GameState.CalcTotalInfluence(state)
        if totalInfluence < influenceCost then return false end
    end
    return true
end

--- 原子扣费：同时扣 AP、现金×通胀、可选 influence
---@param state table
---@param cfg table
---@param influenceCost number|nil
function ActionModals._Spend(state, cfg, influenceCost)
    if not ActionModals._CanAfford(state, cfg, influenceCost) then return false end
    local apOk = GameState.SpendAP(state, cfg.ap or 0)
    if not apOk then return false end
    local inflation = GameState.GetInflationFactor(state)
    state.cash = state.cash - math.floor((cfg.cash or 0) * inflation)
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
    state.flags.intel_unlocked = true
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
    AudioManager.PlayUI("ui_modal_open")
    closeModal()

    local rows = {}
    for _, faction in ipairs(state.ai_factions) do
        local factionLocal = faction
        if faction.collapsed then
            table.insert(rows, UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = { 40, 40, 45, 255 },
                borderRadius = S.radius_card,
                borderLeftWidth = 2,
                borderLeftColor = { 100, 100, 100, 255 },
                flexDirection = "column",
                gap = 6,
                opacity = 0.7,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label { text = "💀 " .. faction.name, fontSize = F.body,
                                fontWeight = "bold", fontColor = { 140, 140, 140, 255 } },
                            UI.Panel { paddingHorizontal = 5, paddingVertical = 1,
                                backgroundColor = { 180, 50, 50, 50 }, borderRadius = S.radius_badge,
                                children = { UI.Label { text = "已瘫痪", fontSize = F.label,
                                    fontColor = C.accent_red } } },
                        },
                    },
                    UI.Label { text = "该势力已崩溃，无法进行外交", fontSize = F.label,
                        fontColor = { 120, 120, 120, 255 } },
                },
            })
        else
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
    AudioManager.PlayUI("ui_modal_open")
    closeModal()

    local rows = {}

    -- 开发新矿
    local maxMines = (Balance.TRADE.new_mine.max_mines or 4) + (state.mine_slots_bonus or 0)
    local minesFull = #state.mines >= maxMines
    local assetPriceFactor = GameState.GetAssetPriceFactor(state)
    local newMineCost = math.floor(Balance.TRADE.new_mine.cash * assetPriceFactor)
    table.insert(rows, ActionModals._TradeOption(
        "⛏️ 开发新矿区",
        string.format("投入 %d 克朗 / %d AP 建立一座新矿（%d/%d）",
            newMineCost, Balance.TRADE.new_mine.ap,
            #state.mines, maxMines),
        accent,
        function() ActionModals._TradeNewMine(state) end,
        minesFull or state.cash < newMineCost or (state.ap.current + (state.ap.temp or 0)) < Balance.TRADE.new_mine.ap
    ))

    -- 出售矿山
    for _, mine in ipairs(state.mines) do
        if mine.active and #state.mines > 1 then
            local mineLocal = mine
            local salePrice = math.floor(mine.level * Balance.TRADE.sell_mine.cash_per_level * assetPriceFactor)
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
    local inflationFactor = GameState.GetInflationFactor(state)
    for _, faction in ipairs(state.ai_factions) do
        -- 瘫痪势力：显示已瘫痪提示，跳过攻击选项
        if faction.collapsed then
            table.insert(rows, ActionModals._TradeOption(
                "💀 " .. faction.name .. "（已瘫痪）",
                "该势力已崩溃，无需进一步打击",
                { 100, 100, 100, 255 },
                function() end,
                true
            ))
        else
        local factionLocal = faction
        table.insert(rows, ActionModals._TradeOption(
            "⚔ 资本攻击：" .. faction.name,
            string.format("花 %d 克朗削弱 AI 资金 %d / 势力 -%d",
                math.floor(Balance.TRADE.raid_ai.cash * inflationFactor),
                Balance.TRADE.raid_ai.ai_cash_loss,
                Balance.TRADE.raid_ai.power_loss),
            accent,
            function() ActionModals._TradeRaid(state, factionLocal) end,
            not ActionModals._CanAfford(state, Balance.TRADE.raid_ai)
        ))
        local attackCfg = { ap = Balance.COMBAT.player_attack_ap, cash = Balance.COMBAT.player_attack_cash }
        table.insert(rows, ActionModals._TradeOption(
            "🛡 武装突袭：" .. faction.name,
            string.format("花 %d 克朗 / %d AP 发动一次军事打击，胜负会改变地区控制",
                math.floor(attackCfg.cash * inflationFactor), attackCfg.ap),
            C.accent_red,
            function() ActionModals._TradeMilitaryStrike(state, factionLocal) end,
            not ActionModals._CanAfford(state, attackCfg)
        ))
        end
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
    local cashCost = math.floor(cfg.cash * GameState.GetAssetPriceFactor(state))
    -- 检查矿山数量上限（基础 + 科技加成）
    local maxMines = (cfg.max_mines or 4) + (state.mine_slots_bonus or 0)
    if #state.mines >= maxMines then
        UI.Toast.Show(string.format("矿山已达上限（%d/%d）", #state.mines, maxMines),
            { variant = "warning", duration = 1.5 })
        return
    end
    if state.cash < cashCost or (state.ap.current + (state.ap.temp or 0)) < cfg.ap then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    if not GameState.SpendAP(state, cfg.ap) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.2 })
        return
    end
    state.cash = state.cash - cashCost
    local id = "mine_" .. tostring(state.turn_count) .. "_" .. tostring(math.random(1000, 9999))
    local region = state.regions[1]
    for _, r in ipairs(state.regions) do
        if r.id == "mine_district" then region = r; break end
    end
    -- 新矿使用独立储量，同时同步到 region
    local newReserve = cfg.base_reserve or 1500
    table.insert(state.mines, {
        id = id,
        name = "新矿井 #" .. (#state.mines + 1),
        region_id = region and region.id or "mine_district",
        level = 1,
        output_bonus = 0,
        active = true,
        reserve = newReserve,
    })
    -- 同步 region.gold_reserve（兼容显示）
    if region and region.resources then
        region.resources.gold_reserve = (region.resources.gold_reserve or 0) + newReserve
    end
    GameState.AddLog(state, string.format("[交易] 新矿开发完成，独立储量 %d", newReserve))
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

function ActionModals._TradeMilitaryStrike(state, faction)
    local cfg = { ap = Balance.COMBAT.player_attack_ap, cash = Balance.COMBAT.player_attack_cash }
    if not ActionModals._CanAfford(state, cfg) then
        UI.Toast.Show("资源不足", { variant = "error", duration = 1.2 })
        return
    end
    ActionModals._Spend(state, cfg)
    local ok, msg = Combat.PlayerAttack(state, faction.id)
    if ok then
        faction.attitude = math.max(-100, (faction.attitude or 0) - 20)
        UI.Toast.Show("突袭完成", { variant = "success", duration = 1.5 })
    else
        UI.Toast.Show(msg or "突袭失败", { variant = "error", duration = 1.5 })
    end
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
        bounces = false,
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
