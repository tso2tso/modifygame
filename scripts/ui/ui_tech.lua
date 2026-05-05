-- ============================================================================
-- 科技研发 UI 模块（一级 Tab 分类 + 二级线性科技树）
-- 从 ui_action_modals.lua 拆出，提高可维护性
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local Tech = require("systems.tech")
local TechData = require("data.tech_data")
local AudioManager = require("systems.audio_manager")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local UITech = {}

-- ============================================================================
-- 效果标签映射
-- ============================================================================

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
    unlock_local_coal_mine = function() return "解锁本地煤矿开发" end,
    prospect_success    = function(v) return string.format("探矿成功率 +%d%%", math.floor(v * 100)) end,
    plunder_loot_mult   = function(v) return string.format("掠夺收益 +%d%%", math.floor(v * 100)) end,
    rep_recovery_bonus  = function(v) return string.format("声誉恢复 +%d/季", v) end,
    plunder_cooldown_reduction = function(v) return string.format("掠夺冷却 -%d 季", v) end,
}

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 解析 requires 为扁平的 id 列表（用于依赖连线等场景）
local function getAllRequires(requires)
    if not requires then return {} end
    local list = {}
    -- 先按逗号拆 AND，再按管道拆 OR，收集所有 id
    for andPart in requires:gmatch("[^,]+") do
        for orPart in andPart:gmatch("[^|]+") do
            table.insert(list, orPart)
        end
    end
    return list
end

--- 检查前置科技是否满足（镜像 tech.lua checkRequires 逻辑）
local function checkReqMet(requires, researched)
    if not requires then return true end
    -- AND: "a,b" → 每个子项都要满足
    if requires:find(",") then
        for andPart in requires:gmatch("[^,]+") do
            local subOk = false
            if andPart:find("|") then
                for orPart in andPart:gmatch("[^|]+") do
                    if researched[orPart] then subOk = true; break end
                end
            else
                subOk = researched[andPart] == true
            end
            if not subOk then return false end
        end
        return true
    end
    -- OR: "a|b" → 任一满足
    if requires:find("|") then
        for part in requires:gmatch("[^|]+") do
            if researched[part] then return true end
        end
        return false
    end
    return researched[requires] == true
end

-- ============================================================================
-- 科技线定义（一级目录）
-- ============================================================================

local TECH_LANES = {
    {
        id = "a",
        title = "采矿",
        icon = "⛏️",
        desc = "产出 / 安全 / 工人效率",
        accentColor = { 218, 165, 32, 255 },  -- 金色
    },
    {
        id = "b",
        title = "经济",
        icon = "💰",
        desc = "税率 / 贸易 / 金融",
        accentColor = { 75, 175, 95, 255 },   -- 绿色
    },
    {
        id = "c",
        title = "军事",
        icon = "⚔️",
        desc = "装备 / 补给 / 战力",
        accentColor = { 200, 80, 80, 255 },   -- 红色
    },
    {
        id = "d",
        title = "文化",
        icon = "📜",
        desc = "影响力 / 士气 / 研发",
        accentColor = { 120, 140, 220, 255 },  -- 蓝色
    },
}

-- ============================================================================
-- 科技状态计算
-- ============================================================================

local function getTechState(state, tech)
    local researched = state.tech and state.tech.researched or {}
    local inProgress = state.tech and state.tech.in_progress
    local reqMet = checkReqMet(tech.requires, researched)
    local isExcluded = tech.excludes and researched[tech.excludes] == true
    local isDone = researched[tech.id] == true
    local isProgress = inProgress and inProgress.id == tech.id
    local hasOtherProgress = inProgress and inProgress.id ~= tech.id
    local inflatedCost = math.floor(tech.cost * GameState.GetInflationFactor(state))
    -- 科技顾问满配：研发费用降低 20%（与 Tech.Start 保持一致）
    local hasAdvisorDiscount = GameState.HasExcellentPosition(state, "tech_advisor")
    if hasAdvisorDiscount then
        inflatedCost = math.floor(inflatedCost * 0.8)
    end
    local canAfford = state.cash >= inflatedCost
    local hasAP = (state.ap.current + (state.ap.temp or 0)) >= Balance.TECH.base_research_ap
    local canStart = (not isDone) and (not isProgress) and (not isExcluded)
        and reqMet and canAfford and hasAP and not hasOtherProgress

    local label = "🔒 未解锁"
    local color = { 100, 100, 120, 255 }
    local statusKey = "locked"
    if isDone then
        label = "✓ 已研发"
        color = C.accent_green
        statusKey = "done"
    elseif isExcluded then
        label = "🚫 已排除"
        color = C.accent_red
        statusKey = "excluded"
    elseif isProgress then
        label = string.format("⏳ %d/%d 季", inProgress.progress, inProgress.total)
        color = C.accent_blue
        statusKey = "progress"
    elseif canStart then
        label = "🔓 可研发"
        color = C.accent_gold
        statusKey = "available"
    elseif reqMet then
        label = hasOtherProgress and "⏸ 等待" or "💲 资源不足"
        color = C.text_muted
        statusKey = "waiting"
    end

    return {
        label = label,
        color = color,
        statusKey = statusKey,
        reqMet = reqMet,
        isExcluded = isExcluded,
        isDone = isDone,
        isProgress = isProgress,
        hasOtherProgress = hasOtherProgress,
        canAfford = canAfford,
        hasAP = hasAP,
        canStart = canStart,
        inflatedCost = inflatedCost,
        hasAdvisorDiscount = hasAdvisorDiscount,
    }
end

--- 获取一条线的科技列表（保留数据定义顺序）
local function getLaneTechs(laneId)
    local result = {}
    for _, tech in ipairs(TechData.GetAll()) do
        if string.sub(tech.id, 1, 1) == laneId then
            table.insert(result, tech)
        end
    end
    return result
end

--- 统计一条线的研发进度
local function getLaneProgress(state, laneId)
    local techs = getLaneTechs(laneId)
    local total = #techs
    local done = 0
    local researched = state.tech and state.tech.researched or {}
    for _, tech in ipairs(techs) do
        if researched[tech.id] then done = done + 1 end
    end
    return done, total
end

-- ============================================================================
-- 模块级状态
-- ============================================================================

local currentModal_ = nil
local onStateChanged_ = nil
local stateRef_ = nil
---@type table|nil
local uiRoot_ = nil
local activeLaneId_ = "a"         -- 当前选中的一级 Tab
local expandedTechId_ = nil       -- 当前展开详情的科技 id
local tabBarRef_ = nil            -- Tab 栏容器引用
local treeContainerRef_ = nil     -- 科技树内容容器引用

-- ============================================================================
-- UI 组件：Tab 按钮
-- ============================================================================

local function createTabButton(lane, isActive, onSelect)
    local done, total = getLaneProgress(stateRef_, lane.id)
    local progress = total > 0 and (done / total) or 0
    local bgColor = isActive
        and { lane.accentColor[1], lane.accentColor[2], lane.accentColor[3], 60 }
        or C.bg_elevated
    local borderColor = isActive and lane.accentColor or { 60, 60, 70, 255 }

    return UI.Panel {
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        minWidth = 70,
        padding = 6,
        backgroundColor = bgColor,
        borderRadius = S.radius_card,
        borderWidth = isActive and 1.5 or 1,
        borderColor = borderColor,
        flexDirection = "column",
        alignItems = "center",
        gap = 2,
        pointerEvents = "auto",
        onPointerUp = Config.TapGuard(function()
            AudioManager.PlayUI("ui_click")
            onSelect(lane.id)
        end),
        children = {
            UI.Label {
                text = lane.icon .. " " .. lane.title,
                fontSize = isActive and F.body or F.body_minor,
                fontWeight = isActive and "bold" or "medium",
                fontColor = isActive and lane.accentColor or C.text_secondary,
                pointerEvents = "none",
            },
            -- 进度条
            UI.Panel {
                width = "90%",
                height = 3,
                borderRadius = 2,
                backgroundColor = { 50, 50, 60, 255 },
                children = {
                    UI.Panel {
                        width = string.format("%d%%", math.floor(progress * 100)),
                        height = "100%",
                        borderRadius = 2,
                        backgroundColor = lane.accentColor,
                    },
                },
            },
            UI.Label {
                text = string.format("%d/%d", done, total),
                fontSize = 10,
                fontColor = C.text_muted,
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- UI 组件：科技节点（二级目录中的一个节点）
-- 改动2: 折叠态改为单行紧凑布局，减少 padding
-- ============================================================================

local function createTechNode(state, tech, laneAccent, isExpanded, onExpand, onStartResearch)
    local st = getTechState(state, tech)

    -- 节点左边的状态指示条颜色
    local indicatorColor = st.isDone and C.accent_green
        or st.isProgress and C.accent_blue
        or st.canStart and C.accent_gold
        or st.isExcluded and C.accent_red
        or { 60, 60, 70, 255 }

    -- 节点背景
    local nodeBg = isExpanded
        and { laneAccent[1], laneAccent[2], laneAccent[3], 35 }
        or C.paper_dark

    -- 构建效果列表（仅展开时显示）
    local expandedContent = {}
    if isExpanded then
        -- effect_desc 简要效果说明（仅展开时显示）
        if tech.effect_desc and tech.effect_desc ~= "" then
            table.insert(expandedContent, UI.Label {
                text = tech.effect_desc,
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
                pointerEvents = "none",
            })
        end

        -- 描述
        table.insert(expandedContent, UI.Label {
            text = tech.desc,
            fontSize = F.body_minor,
            fontColor = C.text_secondary,
            whiteSpace = "normal",
            width = "100%",
        })

        -- 分割线
        table.insert(expandedContent, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = C.divider,
            marginTop = 2, marginBottom = 2,
        })

        -- 效果
        for _, eff in ipairs(tech.effects or {}) do
            local formatter = EFFECT_LABELS[eff.kind]
            local label = formatter and formatter(eff.value)
                or (eff.kind .. " " .. tostring(eff.value or ""))
            table.insert(expandedContent, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 5,
                children = {
                    UI.Panel {
                        width = 5, height = 5,
                        borderRadius = 3,
                        backgroundColor = laneAccent,
                    },
                    UI.Label {
                        text = label,
                        fontSize = F.body_minor,
                        fontColor = C.text_primary,
                    },
                },
            })
        end

        -- 费用行
        table.insert(expandedContent, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = C.divider,
            marginTop = 2, marginBottom = 2,
        })
        table.insert(expandedContent, UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 10,
            children = {
                UI.Label {
                    text = st.hasAdvisorDiscount
                        and string.format("💰 %d 克朗（顾问-20%%）", st.inflatedCost)
                        or  string.format("💰 %d 克朗", st.inflatedCost),
                    fontSize = F.label,
                    fontColor = st.canAfford and C.text_primary or C.accent_red,
                },
                UI.Label {
                    text = string.format("🕐 %d 季", tech.turns),
                    fontSize = F.label,
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = string.format("⚡ AP %d", Balance.TECH.base_research_ap),
                    fontSize = F.label,
                    fontColor = st.hasAP and C.text_primary or C.accent_red,
                },
            },
        })

        -- 前置科技（支持 AND/OR 显示）
        if tech.requires then
            local displayStr
            if tech.requires:find(",") then
                -- AND 语法："a1|a2,b1" → "(科技A1 或 科技A2) 且 科技B1"
                local andGroups = {}
                for andPart in tech.requires:gmatch("[^,]+") do
                    if andPart:find("|") then
                        local orParts = {}
                        for orId in andPart:gmatch("[^|]+") do
                            local req = TechData.GetById(orId)
                            if req then
                                local reqDone = state.tech and state.tech.researched
                                    and state.tech.researched[req.id]
                                table.insert(orParts, req.name .. (reqDone and " ✓" or " ✗"))
                            end
                        end
                        table.insert(andGroups, "(" .. table.concat(orParts, " 或 ") .. ")")
                    else
                        local req = TechData.GetById(andPart)
                        if req then
                            local reqDone = state.tech and state.tech.researched
                                and state.tech.researched[req.id]
                            table.insert(andGroups, req.name .. (reqDone and " ✓" or " ✗"))
                        end
                    end
                end
                displayStr = table.concat(andGroups, " 且 ")
            else
                local parts = getAllRequires(tech.requires)
                local reqParts = {}
                for _, pid in ipairs(parts) do
                    local req = TechData.GetById(pid)
                    if req then
                        local reqDone = state.tech and state.tech.researched
                            and state.tech.researched[req.id]
                        table.insert(reqParts, req.name .. (reqDone and " ✓" or " ✗"))
                    end
                end
                local hasPipe = #parts > 1
                displayStr = table.concat(reqParts, hasPipe and " 或 " or " → ")
            end
            table.insert(expandedContent, UI.Label {
                text = "前置：" .. displayStr,
                fontSize = F.label,
                fontColor = C.text_secondary,
            })
        end

        -- 互斥提示
        if tech.excludes then
            local exTech = TechData.GetById(tech.excludes)
            local exName = exTech and (exTech.icon .. " " .. exTech.name) or tech.excludes
            local exDone = state.tech and state.tech.researched
                and state.tech.researched[tech.excludes]
            table.insert(expandedContent, UI.Label {
                text = "⚠ 互斥：" .. exName .. (exDone and " (已选)" or ""),
                fontSize = F.label,
                fontColor = exDone and C.accent_red or { 200, 170, 80, 255 },
            })
        end

        -- 研发按钮
        if not st.isDone and not st.isExcluded then
            local btnLabel = st.isProgress and "研发进行中"
                or (not st.reqMet) and "需要前置科技"
                or st.hasOtherProgress and "已有研发项目"
                or (not st.canAfford) and "资金不足"
                or (not st.hasAP) and "行动点不足"
                or "开始研发"
            table.insert(expandedContent, UI.Panel {
                width = "100%",
                height = 34,
                marginTop = 4,
                borderRadius = S.radius_btn,
                backgroundColor = st.canStart and laneAccent or C.paper_mid,
                justifyContent = "center",
                alignItems = "center",
                opacity = st.canStart and 1.0 or 0.5,
                pointerEvents = st.canStart and "auto" or "none",
                onPointerUp = Config.TapGuard(function()
                    if st.canStart then onStartResearch(tech.id) end
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
    end

    -- 节点主体：折叠态为紧凑单行，展开态保留详情
    local nodeChildren = {
        -- 标题行（始终可见）—— 紧凑单行：icon + 名称 | 状态标签
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            pointerEvents = "none",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = tech.icon,
                            fontSize = isExpanded and F.subtitle or F.body,
                            pointerEvents = "none",
                        },
                        UI.Label {
                            text = tech.name,
                            fontSize = F.body,
                            fontWeight = (st.canStart or isExpanded) and "bold" or "medium",
                            fontColor = (st.reqMet or st.isDone) and C.text_primary or C.text_muted,
                            flexShrink = 1,
                            pointerEvents = "none",
                        },
                    },
                },
                -- 状态标签
                UI.Panel {
                    paddingHorizontal = 6,
                    paddingVertical = 2,
                    borderRadius = S.radius_badge,
                    backgroundColor = { st.color[1], st.color[2], st.color[3], 40 },
                    children = {
                        UI.Label {
                            text = st.label,
                            fontSize = F.label,
                            fontWeight = "bold",
                            fontColor = st.color,
                            pointerEvents = "none",
                        },
                    },
                },
            },
        },
    }

    -- 展开内容
    if isExpanded and #expandedContent > 0 then
        table.insert(nodeChildren, UI.Panel {
            width = "100%",
            flexDirection = "column",
            gap = 5,
            marginTop = 6,
            paddingTop = 6,
            borderTopWidth = 1,
            borderTopColor = C.divider,
            children = expandedContent,
        })
    end

    return UI.Panel {
        width = "100%",
        paddingVertical = isExpanded and 8 or 6,
        paddingHorizontal = isExpanded and 10 or 8,
        backgroundColor = nodeBg,
        borderRadius = S.radius_card,
        borderLeftWidth = 3,
        borderLeftColor = indicatorColor,
        borderWidth = isExpanded and 1 or 0,
        borderColor = isExpanded and laneAccent or nil,
        flexDirection = "column",
        pointerEvents = "auto",
        onPointerUp = Config.TapGuard(function()
            AudioManager.PlayUI("ui_click")
            onExpand(tech.id)
        end),
        children = nodeChildren,
    }
end

-- ============================================================================
-- UI 组件：分叉组（两个互斥选项的可视化容器）
-- 改动3: 紧凑分叉组 —— 薄分隔条替代 VS 圆形
-- ============================================================================

local function createForkGroup(state, techA, techB, accent, expandedId, onExpand, onStartResearch)
    local stA = getTechState(state, techA)
    local stB = getTechState(state, techB)
    local forkColor = { 200, 170, 80, 255 }

    -- 确定分叉状态 → 头部文案
    local headerText = "⚠ 二选一 · 不可更改"
    local headerTextColor = forkColor
    local resolved = stA.isDone or stB.isDone
    if stA.isDone then
        headerText = "✓ 已选：" .. techA.icon .. " " .. techA.name
        headerTextColor = C.accent_green
    elseif stB.isDone then
        headerText = "✓ 已选：" .. techB.icon .. " " .. techB.name
        headerTextColor = C.accent_green
    end

    -- 复用 createTechNode 渲染每个选项
    local nodeA = createTechNode(state, techA, accent, expandedId == techA.id, onExpand, onStartResearch)
    local nodeB = createTechNode(state, techB, accent, expandedId == techB.id, onExpand, onStartResearch)

    -- 已排除选项降低不透明度
    local wrapA = stA.isExcluded
        and UI.Panel { width = "100%", opacity = 0.45, children = { nodeA } }
        or nodeA
    local wrapB = stB.isExcluded
        and UI.Panel { width = "100%", opacity = 0.45, children = { nodeB } }
        or nodeB

    local borderCol = resolved and C.accent_green or forkColor
    local headerBg  = resolved
        and { C.accent_green[1], C.accent_green[2], C.accent_green[3], 30 }
        or  { forkColor[1], forkColor[2], forkColor[3], 30 }

    -- 路线标签生成器（紧凑版）
    local function routeBadge(letter, st)
        local badgeBg = st.isDone and C.accent_green
            or st.isExcluded and C.accent_red
            or accent
        local hint = st.isDone and "已选" or (st.isExcluded and "已排除" or "")
        local hintColor = st.isDone and C.accent_green or C.accent_red
        local badgeChildren = {
            UI.Panel {
                paddingHorizontal = 5, paddingVertical = 1,
                borderRadius = S.radius_badge,
                backgroundColor = badgeBg,
                children = {
                    UI.Label {
                        text = letter,
                        fontSize = 10, fontWeight = "bold",
                        fontColor = { 255, 255, 255, 255 },
                        pointerEvents = "none",
                    },
                },
            },
        }
        if hint ~= "" then
            table.insert(badgeChildren, UI.Label {
                text = hint,
                fontSize = F.label,
                fontColor = hintColor,
                pointerEvents = "none",
            })
        end
        return UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 2,
            children = badgeChildren,
        }
    end

    return UI.Panel {
        width = "100%",
        borderWidth = 1,
        borderColor = borderCol,
        borderRadius = S.radius_card + 2,
        backgroundColor = { forkColor[1], forkColor[2], forkColor[3], 10 },
        flexDirection = "column",
        children = {
            -- ── 头部横幅（紧凑） ──
            UI.Panel {
                width = "100%",
                paddingVertical = 3, paddingHorizontal = 8,
                backgroundColor = headerBg,
                flexDirection = "row",
                alignItems = "center", justifyContent = "center",
                children = {
                    UI.Label {
                        text = headerText,
                        fontSize = F.label, fontWeight = "bold",
                        fontColor = headerTextColor,
                        pointerEvents = "none",
                    },
                },
            },
            -- ── 选项主体 ──
            UI.Panel {
                width = "100%",
                padding = 5,
                flexDirection = "column",
                gap = 0,
                children = {
                    routeBadge("A", stA),
                    wrapA,
                    -- 薄分隔条替代 VS 圆形
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center", gap = 6,
                        paddingVertical = 3,
                        children = {
                            UI.Panel { flexGrow = 1, height = 1,
                                backgroundColor = { forkColor[1], forkColor[2], forkColor[3], 50 } },
                            UI.Label {
                                text = "或",
                                fontSize = 10, fontWeight = "bold",
                                fontColor = { forkColor[1], forkColor[2], forkColor[3], 180 },
                                pointerEvents = "none",
                            },
                            UI.Panel { flexGrow = 1, height = 1,
                                backgroundColor = { forkColor[1], forkColor[2], forkColor[3], 50 } },
                        },
                    },
                    routeBadge("B", stB),
                    wrapB,
                },
            },
        },
    }
end

-- ============================================================================
-- 构建一条线的科技树（二级目录）
-- 改动4: 移除箭头连接符，用 gap 自然间距
-- ============================================================================

local function buildLaneTree(state, laneId, accent, expandedId, onExpand, onStartResearch)
    local techs = getLaneTechs(laneId)
    local children = {}

    -- 按顺序排列科技，识别分叉点
    local i = 1
    while i <= #techs do
        local tech = techs[i]
        local nextTech = techs[i + 1]

        -- 检查是否是分叉对（当前和下一个互斥）
        if nextTech and tech.excludes == nextTech.id then
            table.insert(children, createForkGroup(
                state, tech, nextTech, accent, expandedId, onExpand, onStartResearch
            ))
            i = i + 2
        else
            table.insert(children, createTechNode(
                state, tech, accent, expandedId == tech.id, onExpand, onStartResearch
            ))
            i = i + 1
        end
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 3,
        children = children,
    }
end

-- ============================================================================
-- 构建当前研发状态条
-- ============================================================================

local function createResearchStatusBar(state, accent)
    local inProgress = state.tech and state.tech.in_progress
    local tech = inProgress and TechData.GetById(inProgress.id) or nil

    if not inProgress or not tech then
        return UI.Panel {
            width = "100%",
            paddingVertical = 6,
            paddingHorizontal = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = "当前无研发项目",
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = "选择下方科技开始研发",
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
            },
        }
    end

    local progress = inProgress.progress / math.max(1, inProgress.total)
    -- 找到对应 lane 的颜色
    local laneLetter = string.sub(inProgress.id, 1, 1)
    local laneAccent = accent
    for _, lane in ipairs(TECH_LANES) do
        if lane.id == laneLetter then
            laneAccent = lane.accentColor
            break
        end
    end

    return UI.Panel {
        width = "100%",
        paddingVertical = 6,
        paddingHorizontal = 10,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderLeftWidth = 3,
        borderLeftColor = laneAccent,
        flexDirection = "column",
        gap = 4,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "研发中：" .. tech.icon .. " " .. tech.name,
                        fontSize = F.body,
                        fontWeight = "bold",
                        fontColor = laneAccent,
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
                height = 5,
                borderRadius = 3,
                trackColor = C.bg_surface,
                fillColor = laneAccent,
            },
        },
    }
end

-- ============================================================================
-- 主构建函数：组合 Tab + 科技树
-- 改动1: 将状态栏/图例/Tab移出ScrollView
-- 改动5: 增大ScrollView高度
-- ============================================================================

local function rebuildTreeContent(state, onChanged)
    if not treeContainerRef_ then return end
    treeContainerRef_:ClearChildren()

    local lane = nil
    for _, l in ipairs(TECH_LANES) do
        if l.id == activeLaneId_ then lane = l; break end
    end
    if not lane then return end

    local accent = lane.accentColor

    -- 线的描述头
    local done, total = getLaneProgress(state, lane.id)
    local header = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingHorizontal = 2,
        marginBottom = 2,
        children = {
            UI.Label {
                text = lane.icon .. " " .. lane.title .. "科技线",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = accent,
            },
            UI.Label {
                text = lane.desc .. string.format("  (%d/%d)", done, total),
                fontSize = F.label,
                fontColor = C.text_secondary,
            },
        },
    }

    -- 构建科技树
    local tree = buildLaneTree(state, lane.id, accent, expandedTechId_,
        function(techId)
            -- 点击展开/收起
            if expandedTechId_ == techId then
                expandedTechId_ = nil
            else
                expandedTechId_ = techId
            end
            rebuildTreeContent(state, onChanged)
        end,
        function(techId)
            -- 开始研发
            local ok, msg = Tech.Start(state, techId)
            UI.Toast.Show(msg, {
                variant = ok and "success" or "error",
                duration = 1.5,
            })
            if ok then
                expandedTechId_ = nil
                if currentModal_ then
                    currentModal_:Close()
                end
                if onChanged then onChanged() end
            end
        end
    )

    treeContainerRef_:AddChild(header)
    treeContainerRef_:AddChild(tree)
end

local function rebuildTabBar(state, onChanged)
    if not tabBarRef_ then return end
    tabBarRef_:ClearChildren()

    for _, lane in ipairs(TECH_LANES) do
        local isActive = lane.id == activeLaneId_
        tabBarRef_:AddChild(createTabButton(lane, isActive, function(laneId)
            activeLaneId_ = laneId
            expandedTechId_ = nil  -- 切换 Tab 时清除展开
            rebuildTabBar(state, onChanged)
            rebuildTreeContent(state, onChanged)
        end))
    end
end

local function buildTechModalContent(state, accent, onChanged)
    -- 顶部：当前研发状态（固定在ScrollView外部）
    local statusBar = createResearchStatusBar(state, accent)

    -- 图例（紧凑单行，固定在ScrollView外部）
    local legend = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 10,
        children = {
            UITech._LegendItem(C.accent_green, "已研发"),
            UITech._LegendItem(C.accent_gold, "可研发"),
            UITech._LegendItem(C.accent_blue, "研发中"),
            UITech._LegendItem({ 100, 100, 120, 255 }, "未解锁"),
        },
    }

    -- Tab 栏（固定在ScrollView外部）
    tabBarRef_ = UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 5,
    }

    -- 科技树内容容器（放在ScrollView内部）
    treeContainerRef_ = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
    }

    -- 填充 Tab 和科技树
    rebuildTabBar(state, onChanged)
    rebuildTreeContent(state, onChanged)

    -- 组合：固定头部 + 可滚动科技树
    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 6,
        flexShrink = 1,
        children = {
            statusBar,
            legend,
            tabBarRef_,
            -- 科技树放在 ScrollView 中
            UI.ScrollView {
                width = "100%",
                maxHeight = 580,
                flexShrink = 1,
                bounces = false,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 4,
                        children = {
                            treeContainerRef_,
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 图例辅助
-- ============================================================================

function UITech._LegendItem(color, label)
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Panel {
                width = 8, height = 8,
                borderRadius = 4,
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
-- 公开接口
-- ============================================================================

--- 打开科技研发弹窗
---@param state table 游戏状态
---@param accent table 强调色
---@param uiRootNode table UI 根节点
---@param onChanged function 状态变化回调
function UITech.Show(state, accent, uiRootNode, onChanged)
    stateRef_ = state
    onStateChanged_ = onChanged
    uiRoot_ = uiRootNode

    -- 关闭已有的弹窗
    if currentModal_ then
        currentModal_:Close()
        currentModal_ = nil
    end

    AudioManager.PlayUI("ui_modal_open")

    -- 重置状态
    expandedTechId_ = nil
    tabBarRef_ = nil
    treeContainerRef_ = nil

    -- 自动选择包含正在研发项目的 Tab
    local inProgress = state.tech and state.tech.in_progress
    if inProgress then
        activeLaneId_ = string.sub(inProgress.id, 1, 1)
    end

    currentModal_ = UI.Modal {
        title = "🔬 科技研发",
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            Config.ConsumeTap()
            currentModal_ = nil
            tabBarRef_ = nil
            treeContainerRef_ = nil
            expandedTechId_ = nil
            self:Destroy()
        end,
    }

    currentModal_:AddContent(buildTechModalContent(state, accent, onChanged))

    if uiRootNode then
        uiRootNode:AddChild(currentModal_)
    end
    currentModal_:Open()
end

--- 关闭弹窗
function UITech.Close()
    if currentModal_ then
        currentModal_:Close()
        currentModal_ = nil
    end
end

--- 是否正在显示
function UITech.IsShowing()
    return currentModal_ ~= nil
end

return UITech
