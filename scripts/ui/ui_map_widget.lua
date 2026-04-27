-- ============================================================================
-- 欧洲地图控件 v3 — 严格遵循 sarajevo_dynasty_ui_spec v1.1 §8.5
-- Civ6 式图层叠加 + 类型化节点 + 势力配色 + 时代主题
-- 坐标系：X=0..1 (15°W→45°E), Y=0..1 (71°N→34°N, 北在上)
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Config = require("config")

local C = Config.COLORS
local PI = math.pi

-- ============================================================================
-- 常量
-- ============================================================================

local MIN_ZOOM    = 1.0
local MAX_ZOOM    = 6.0         -- §8.5: 最大 4× (放宽到 6 以保证波黑细节)
local ZOOM_STEP   = 1.30
local DRAG_THRESH = 5
local BOSNIA_CX   = 0.510
local BOSNIA_CY   = 0.730
local BOSNIA_ZOOM  = 5.0
local BTN_SIZE    = 30
local BTN_GAP     = 5
local BTN_MARGIN  = 8
local LAYER_BAR_H = 28         -- 图层选择器高度
local LAYER_PILL_H = 22        -- 图层胶囊高度
local LAYER_PILL_GAP = 3
local LAYER_BAR_PAD = 6

-- ============================================================================
-- §8.5 图层定义（Civ6 式分层叠加）
-- 控制层始终开启(always_on)，其余最多同时激活 2 个
-- ============================================================================

local LAYERS = {
    { id = "control",  label = "控制", color = { 41, 128, 185 }, always_on = true },
    { id = "resource", label = "资源", color = { 212, 175,  55 } },
    { id = "security", label = "安全", color = { 192,  57,  43 } },
    { id = "trade",    label = "贸易", color = {  46, 204, 113 }, locked = true },
    { id = "politics", label = "政治", color = { 142,  68, 173 }, locked = true },
    { id = "military", label = "军事", color = {  44,  62,  80 }, locked = true },
    { id = "culture",  label = "文化", color = { 243, 156,  18 }, locked = true },
    { id = "intel",    label = "情报", color = { 149, 165, 166 }, locked = true },
}

-- ============================================================================
-- §8.5 势力颜色（节点控制状态着色）
-- ============================================================================

local FACTION_COLORS = {
    player         = { 41, 128, 185 },  -- #2980B9 蓝
    local_clan     = { 139, 69,  19 },  -- #8B4513 棕红
    foreign_capital = { 39, 174,  96 },  -- #27AE60 资本绿
    armed_group    = { 44,  62,  80 },  -- #2C3E50 钢铁灰
    neutral        = { 110, 110, 110 },  -- 中立灰
    contested      = { 170, 118,  48 },  -- 争议琥珀
}

-- ============================================================================
-- §8.5 节点类型定义
-- ============================================================================

local NODE_TYPES = {
    mine       = { shape = "hex_pointy", size = 10, label = "矿山区" },
    industrial = { shape = "hex_flat",   size = 12, label = "工业城" },
    capital    = { shape = "star_hex",   size = 14, label = "首都" },
    port       = { shape = "hex_flat",   size = 11, label = "港口" },
    border     = { shape = "diamond",    size =  8, label = "边境" },
    cultural   = { shape = "circle",     size = 10, label = "文化" },
    strategic  = { shape = "triangle",   size =  8, label = "山口" },
}

-- ============================================================================
-- §3.1 时代地图主题（底图风格随时代变化）
-- ============================================================================

local ERA_MAP_THEMES = {
    [1] = { bg = { 45, 38, 28 }, grid = { 80, 68, 50, 20 }, polyA = 42, labelA = 125 },  -- 羊皮纸
    [2] = { bg = { 38, 30, 25 }, grid = { 70, 50, 40, 20 }, polyA = 38, labelA = 115 },  -- 旧报纸
    [3] = { bg = { 28, 35, 49 }, grid = { 50, 60, 80, 20 }, polyA = 45, labelA = 135 },  -- 深蓝钢
    [4] = { bg = { 40, 40, 40 }, grid = { 60, 60, 60, 18 }, polyA = 35, labelA = 95 },   -- 混凝土灰
    [5] = { bg = { 27, 40, 55 }, grid = { 40, 55, 75, 20 }, polyA = 42, labelA = 125 },  -- 冷战蓝
}

-- ============================================================================
-- 资源图标映射
-- ============================================================================

local RESOURCE_ICONS = {
    gold_reserve   = "Au",
    silver_reserve = "Ag",
    coal_reserve   = "C",
    steel_capacity = "Fe",
}

local RESOURCE_ORDER = { "gold_reserve", "silver_reserve", "coal_reserve", "steel_capacity" }

-- ============================================================================
-- 欧洲国家/势力多边形（背景，不可交互）
-- ============================================================================

local EUROPE_REGIONS = {
    { id="scandinavia",    label="瑞典-挪威", color={80,100,120}, poly={0.30,0.02, 0.42,0.04, 0.47,0.15, 0.42,0.28, 0.36,0.38, 0.30,0.40, 0.27,0.34, 0.24,0.20, 0.28,0.08}, labelPos={0.35,0.20} },
    { id="finland",        label="芬兰",     color={90,110,130}, poly={0.47,0.04, 0.58,0.04, 0.56,0.18, 0.50,0.28, 0.47,0.28, 0.47,0.15}, labelPos={0.51,0.15} },
    { id="russia",         label="俄罗斯帝国", color={100,85,70}, poly={0.58,0.04, 0.98,0.04, 0.98,0.72, 0.78,0.68, 0.66,0.58, 0.56,0.48, 0.53,0.38, 0.50,0.28, 0.56,0.18}, labelPos={0.80,0.35} },
    { id="britain",        label="大英帝国",   color={90,70,80},  poly={0.17,0.33, 0.22,0.34, 0.23,0.42, 0.21,0.50, 0.17,0.52, 0.14,0.47, 0.14,0.40, 0.15,0.35}, labelPos={0.18,0.43} },
    { id="france",         label="法兰西",     color={70,80,110}, poly={0.20,0.50, 0.28,0.48, 0.33,0.52, 0.33,0.60, 0.30,0.68, 0.22,0.72, 0.15,0.68, 0.13,0.58, 0.15,0.52}, labelPos={0.23,0.60} },
    { id="iberia",         label="西班牙",     color={120,90,60}, poly={0.13,0.68, 0.22,0.68, 0.22,0.72, 0.22,0.80, 0.18,0.88, 0.08,0.86, 0.05,0.78, 0.07,0.70}, labelPos={0.14,0.78} },
    { id="germany",        label="德意志帝国", color={95,92,78},  poly={0.30,0.40, 0.36,0.38, 0.45,0.38, 0.53,0.38, 0.56,0.48, 0.48,0.55, 0.42,0.57, 0.33,0.52, 0.28,0.48}, labelPos={0.42,0.46} },
    { id="italy",          label="意大利",     color={80,105,72}, poly={0.30,0.63, 0.33,0.60, 0.38,0.62, 0.42,0.68, 0.40,0.76, 0.38,0.82, 0.35,0.86, 0.30,0.80, 0.28,0.72, 0.28,0.67}, labelPos={0.35,0.74} },
    { id="austria_hungary",label="奥匈帝国",   color={125,105,82}, poly={0.42,0.57, 0.48,0.55, 0.56,0.56, 0.58,0.60, 0.56,0.66, 0.52,0.70, 0.47,0.69, 0.42,0.68, 0.38,0.62}, labelPos={0.48,0.61} },
    { id="serbia",         label="塞尔维亚",   color={140,62,62}, poly={0.56,0.66, 0.58,0.60, 0.62,0.62, 0.63,0.70, 0.58,0.74, 0.54,0.74, 0.52,0.70}, labelPos={0.57,0.68} },
    { id="montenegro",     label="黑山",       color={70,92,122}, poly={0.47,0.74, 0.50,0.74, 0.54,0.74, 0.52,0.78, 0.48,0.80, 0.45,0.78}, labelPos={0.49,0.77} },
    { id="romania",        label="罗马尼亚",   color={105,98,62}, poly={0.58,0.58, 0.66,0.56, 0.70,0.60, 0.70,0.67, 0.63,0.70, 0.62,0.62}, labelPos={0.64,0.63} },
    { id="ottoman",        label="奥斯曼帝国", color={132,112,62}, poly={0.54,0.78, 0.58,0.74, 0.63,0.74, 0.70,0.70, 0.78,0.68, 0.83,0.76, 0.83,0.86, 0.72,0.88, 0.60,0.86, 0.52,0.82}, labelPos={0.70,0.80} },
    { id="greece",         label="希腊",       color={62,92,122}, poly={0.52,0.78, 0.54,0.78, 0.58,0.80, 0.56,0.88, 0.52,0.90, 0.48,0.86, 0.48,0.82}, labelPos={0.52,0.84} },
    { id="bulgaria",       label="保加利亚",   color={92,102,72}, poly={0.63,0.70, 0.70,0.67, 0.73,0.70, 0.72,0.76, 0.68,0.76, 0.63,0.74}, labelPos={0.67,0.72} },
    { id="lowlands",       label="低地国家",   color={88,95,80},  poly={0.24,0.42, 0.28,0.40, 0.30,0.40, 0.28,0.48, 0.24,0.50, 0.22,0.48}, labelPos={0.26,0.45} },
    { id="denmark",        label="丹麦",       color={100,88,90}, poly={0.30,0.34, 0.34,0.33, 0.36,0.38, 0.34,0.42, 0.30,0.40}, labelPos={0.33,0.37} },
    { id="switzerland",    label="瑞士",       color={110,100,100}, poly={0.30,0.60, 0.33,0.58, 0.36,0.60, 0.35,0.63, 0.30,0.63}, labelPos={0.33,0.61} },
}

-- ============================================================================
-- 波黑游戏节点（可交互）— §8.5 节点系统
-- ============================================================================

local GAME_NODES = {
    {
        id = "mine_district", label = "巴科维奇矿区", icon = "⛏️",
        nodeType = "mine",
        poly = { 0.470,0.710, 0.486,0.698, 0.502,0.705, 0.504,0.722, 0.496,0.736, 0.480,0.732, 0.468,0.722 },
        pos = { 0.486, 0.718 },
    },
    {
        id = "industrial_town", label = "泽尼察工业区", icon = "🏭",
        nodeType = "industrial",
        poly = { 0.496,0.736, 0.504,0.722, 0.518,0.718, 0.524,0.732, 0.520,0.746, 0.510,0.752, 0.498,0.746 },
        pos = { 0.510, 0.736 },
    },
    {
        id = "capital_city", label = "萨拉热窝", icon = "🏛️",
        nodeType = "capital",
        poly = { 0.518,0.718, 0.530,0.710, 0.542,0.714, 0.548,0.728, 0.540,0.744, 0.528,0.748, 0.520,0.746, 0.524,0.732 },
        pos = { 0.533, 0.730 },
    },
}

-- ============================================================================
-- MapWidget 类
-- ============================================================================

---@class MapWidget : Widget
local MapWidget = Widget:Extend("MapWidget")

function MapWidget:Init(props)
    props = props or {}
    props.width = props.width or "100%"
    props.height = props.height or 420

    -- 缩放/平移状态
    self.zoom_ = BOSNIA_ZOOM
    self.camX_ = BOSNIA_CX
    self.camY_ = BOSNIA_CY

    -- 交互状态
    self.selectedNodeId_  = nil
    self.hoveredNodeId_   = nil
    self.regions_         = {}
    self.onRegionSelect_  = props.onRegionSelect

    -- 图层状态：control 始终开启
    self.activeLayers_ = { control = true }

    -- 时代（影响底图风格）
    self.eraId_ = 1

    -- 拖拽状态
    self.pressing_      = false
    self.dragMoved_     = false
    self.dragStartSX_   = 0
    self.dragStartSY_   = 0
    self.dragStartCamX_ = 0
    self.dragStartCamY_ = 0

    -- 指针
    self.lastPtrX_  = 0
    self.lastPtrY_  = 0
    self.ptrInside_ = false
    self.showLegend_ = false

    Widget.Init(self, props)
end

-- ============================================================================
-- 公开 API
-- ============================================================================

function MapWidget:SetRegions(regions) self.regions_ = regions or {} end
function MapWidget:SetSelected(id) self.selectedNodeId_ = id end
function MapWidget:GetSelected() return self.selectedNodeId_ end
function MapWidget:SetEra(eraId) self.eraId_ = eraId or 1 end

--- 根据游戏状态动态解锁地图图层
---@param state table 游戏状态
function MapWidget:UpdateUnlocks(state)
    if not state then return end
    for _, layer in ipairs(LAYERS) do
        if layer.locked then
            local shouldUnlock = false
            if layer.id == "trade" then
                -- 贸易层：拥有 ≥ 3 矿山（商业网络建立）
                shouldUnlock = state.mines and #state.mines >= 3
            elseif layer.id == "military" then
                -- 军事层：护卫 ≥ 10（军事力量成型）
                shouldUnlock = state.military and state.military.guards >= 10
            elseif layer.id == "intel" then
                -- 情报层：执行过任何情报行动
                shouldUnlock = state.flags and state.flags.intel_unlocked
            end
            if shouldUnlock then
                layer.locked = false
            end
        end
    end
end

function MapWidget:ToggleLayer(layerId)
    -- control 不可关闭
    if layerId == "control" then return end
    -- 查找 layer 定义
    local layerDef = nil
    for _, l in ipairs(LAYERS) do
        if l.id == layerId then layerDef = l; break end
    end
    if not layerDef or layerDef.locked then return end

    if self.activeLayers_[layerId] then
        self.activeLayers_[layerId] = nil
    else
        -- 最多同时激活 2 个额外图层
        local count = 0
        for k, _ in pairs(self.activeLayers_) do
            if k ~= "control" then count = count + 1 end
        end
        if count >= 2 then return end -- 已满
        self.activeLayers_[layerId] = true
    end
end

-- ============================================================================
-- 坐标变换（保持不变）
-- ============================================================================

function MapWidget:_W2S(wx, wy, mx, my, mw, mh)
    return mx + (wx - self.camX_) * self.zoom_ * mw + mw * 0.5,
           my + (wy - self.camY_) * self.zoom_ * mh + mh * 0.5
end

function MapWidget:_S2W(sx, sy, mx, my, mw, mh)
    return (sx - mx - mw * 0.5) / (self.zoom_ * mw) + self.camX_,
           (sy - my - mh * 0.5) / (self.zoom_ * mh) + self.camY_
end

function MapWidget:_ZoomAt(sx, sy, factor, mx, my, mw, mh)
    local wx, wy = self:_S2W(sx, sy, mx, my, mw, mh)
    local oldZoom = self.zoom_
    self.zoom_ = math.max(MIN_ZOOM, math.min(MAX_ZOOM, self.zoom_ * factor))
    self.camX_ = wx - (wx - self.camX_) * oldZoom / self.zoom_
    self.camY_ = wy - (wy - self.camY_) * oldZoom / self.zoom_
    self:_ClampCam()
end

function MapWidget:_ClampCam()
    local halfW = 0.5 / self.zoom_
    local halfH = 0.5 / self.zoom_
    self.camX_ = math.max(halfW, math.min(1.0 - halfW, self.camX_))
    self.camY_ = math.max(halfH, math.min(1.0 - halfH, self.camY_))
end

function MapWidget:_MapArea()
    local l = self:GetAbsoluteLayout()
    local pad = 2
    return l.x + pad, l.y + LAYER_BAR_H + pad, l.w - pad * 2, l.h - LAYER_BAR_H - pad * 2
end

function MapWidget:_MapAreaHit()
    local l = self:GetAbsoluteLayoutForHitTest()
    local pad = 2
    return l.x + pad, l.y + LAYER_BAR_H + pad, l.w - pad * 2, l.h - LAYER_BAR_H - pad * 2
end

-- ============================================================================
-- 节点形状绘制
-- ============================================================================

--- 尖顶六边形（矿山区）
function MapWidget:_ShapeHexPointy(nvg, cx, cy, r)
    nvgBeginPath(nvg)
    for i = 0, 5 do
        local angle = PI / 180 * (60 * i - 30)
        local x = cx + r * math.cos(angle)
        local y = cy + r * math.sin(angle)
        if i == 0 then nvgMoveTo(nvg, x, y) else nvgLineTo(nvg, x, y) end
    end
    nvgClosePath(nvg)
end

--- 平顶六边形（工业城）
function MapWidget:_ShapeHexFlat(nvg, cx, cy, r)
    nvgBeginPath(nvg)
    for i = 0, 5 do
        local angle = PI / 180 * (60 * i)
        local x = cx + r * math.cos(angle)
        local y = cy + r * math.sin(angle)
        if i == 0 then nvgMoveTo(nvg, x, y) else nvgLineTo(nvg, x, y) end
    end
    nvgClosePath(nvg)
end

--- 星形六边形（首都/省会）— 外环六角 + 内环六角形成星芒
function MapWidget:_ShapeStarHex(nvg, cx, cy, r)
    local rInner = r * 0.65
    nvgBeginPath(nvg)
    for i = 0, 11 do
        local angle = PI / 180 * (30 * i - 15)
        local rad = (i % 2 == 0) and r or rInner
        local x = cx + rad * math.cos(angle)
        local y = cy + rad * math.sin(angle)
        if i == 0 then nvgMoveTo(nvg, x, y) else nvgLineTo(nvg, x, y) end
    end
    nvgClosePath(nvg)
end

--- 菱形（边境通道）
function MapWidget:_ShapeDiamond(nvg, cx, cy, r)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy - r)
    nvgLineTo(nvg, cx + r * 0.7, cy)
    nvgLineTo(nvg, cx, cy + r)
    nvgLineTo(nvg, cx - r * 0.7, cy)
    nvgClosePath(nvg)
end

--- 三角形（战略山口）
function MapWidget:_ShapeTriangle(nvg, cx, cy, r)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy - r)
    nvgLineTo(nvg, cx + r * 0.866, cy + r * 0.5)
    nvgLineTo(nvg, cx - r * 0.866, cy + r * 0.5)
    nvgClosePath(nvg)
end

--- 绘制节点形状（根据类型派发）
function MapWidget:_DrawNodeShape(nvg, cx, cy, r, nodeType)
    local t = NODE_TYPES[nodeType] or NODE_TYPES.mine
    local shape = t.shape
    if shape == "hex_pointy" then self:_ShapeHexPointy(nvg, cx, cy, r)
    elseif shape == "hex_flat" then self:_ShapeHexFlat(nvg, cx, cy, r)
    elseif shape == "star_hex" then self:_ShapeStarHex(nvg, cx, cy, r)
    elseif shape == "diamond" then self:_ShapeDiamond(nvg, cx, cy, r)
    elseif shape == "triangle" then self:_ShapeTriangle(nvg, cx, cy, r)
    else
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, r)
    end
end

-- ============================================================================
-- 势力颜色工具
-- ============================================================================

--- 获取区域的主导控制方
function MapWidget:_GetDominantFaction(regionData)
    if not regionData then return "neutral" end
    local playerCtrl = regionData.control or 0
    if playerCtrl >= 50 then return "player" end

    local maxAI, maxAIId = 0, nil
    if regionData.ai_presence then
        for aiId, presence in pairs(regionData.ai_presence) do
            if presence > maxAI then maxAI = presence; maxAIId = aiId end
        end
    end
    if maxAIId and maxAI >= 40 then return maxAIId end

    -- 争议状态：没有单一势力主导
    return "contested"
end

--- 获取势力填充颜色
function MapWidget:_GetFactionColor(factionId)
    return FACTION_COLORS[factionId] or FACTION_COLORS.neutral
end

--- 获取控制层的区域填充色
function MapWidget:_GetControlFill(regionData, isSelected, isHovered)
    local faction = self:_GetDominantFaction(regionData)
    local fc = self:_GetFactionColor(faction)
    local a = isSelected and 180 or (isHovered and 150 or 110)
    local boost = (isSelected or isHovered) and 20 or 0
    return { math.min(255, fc[1] + boost), math.min(255, fc[2] + boost), math.min(255, fc[3] + boost), a }
end

--- 获取节点填充色（更饱和）
function MapWidget:_GetNodeFill(regionData, isSelected, isHovered)
    local faction = self:_GetDominantFaction(regionData)
    local fc = self:_GetFactionColor(faction)
    local a = isSelected and 245 or (isHovered and 220 or 200)
    return { fc[1], fc[2], fc[3], a }
end

-- ============================================================================
-- 主渲染
-- ============================================================================

function MapWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local mx, my, mw, mh = self:_MapArea()
    local theme = ERA_MAP_THEMES[self.eraId_] or ERA_MAP_THEMES[1]

    -- 鼠标滚轮
    if self.ptrInside_ then
        local wheel = input:GetMouseMoveWheel()
        if wheel ~= 0 then
            self:_ZoomAt(self.lastPtrX_, self.lastPtrY_, wheel > 0 and ZOOM_STEP or (1/ZOOM_STEP), mx, my, mw, mh)
        end
    end

    -- ① 底板（时代主题色）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, 6)
    nvgFillColor(nvg, nvgRGBA(theme.bg[1], theme.bg[2], theme.bg[3], 255))
    nvgFill(nvg)

    -- 裁剪地图区域（不含图层选择器）
    nvgSave(nvg)
    nvgScissor(nvg, mx, my, mw, mh)

    -- ② 经纬网格
    self:_DrawGrid(nvg, mx, my, mw, mh, theme)

    -- ③ 欧洲背景多边形
    for _, er in ipairs(EUROPE_REGIONS) do
        local c = er.color
        self:_DrawPoly(nvg, er.poly, {c[1], c[2], c[3], theme.polyA}, {85,75,60,40}, 0.6, mx, my, mw, mh)
    end

    -- ④ 控制层：游戏区域多边形按势力着色
    if self.activeLayers_.control then
        for _, gn in ipairs(GAME_NODES) do
            local rd = self:_FindRegionData(gn.id)
            local isSel = (self.selectedNodeId_ == gn.id)
            local isHov = (self.hoveredNodeId_ == gn.id)
            local fc = self:_GetControlFill(rd, isSel, isHov)
            local era = Config.GetEraByYear and Config.GetEraByYear(1904 + (self.eraId_ - 1) * 15) or nil
            local bc = isSel and C.accent_gold or C.paper_light
            local ba = isSel and 255 or (isHov and 200 or 120)
            local bw = isSel and 2.5 or (isHov and 1.8 or 1.0)
            self:_DrawPoly(nvg, gn.poly, fc, {bc[1], bc[2], bc[3], ba}, bw, mx, my, mw, mh)
        end
    end

    -- ⑤ 安全图层：热力色覆盖
    if self.activeLayers_.security then
        self:_DrawSecurityLayer(nvg, mx, my, mw, mh)
    end

    -- ⑥ 欧洲标签
    for _, er in ipairs(EUROPE_REGIONS) do
        self:_DrawContextLabel(nvg, er, mx, my, mw, mh, theme)
    end

    -- ⑦ 资源图层：在节点旁显示资源图标
    if self.activeLayers_.resource then
        self:_DrawResourceLayer(nvg, mx, my, mw, mh)
    end

    -- ⑧ 游戏节点（类型化形状）
    for _, gn in ipairs(GAME_NODES) do
        self:_DrawGameNode(nvg, gn, mx, my, mw, mh)
    end

    nvgRestore(nvg)  -- 恢复裁剪

    -- 边框（时代主题）
    local era = Config.GetEraByYear and Config.GetEraByYear(1904 + (self.eraId_ - 1) * 15) or nil
    local borderC = era and era.border or C.border_gold
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, 6)
    nvgStrokeColor(nvg, nvgRGBA(borderC[1], borderC[2], borderC[3], 140))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    -- ⑨ 图层选择器（顶部浮条）
    self:_DrawLayerSelector(nvg, l.x, l.y, l.w)

    -- ⑩ 缩放控件（右侧）
    self:_DrawControls(nvg, l.x, l.y + LAYER_BAR_H, l.w, l.h - LAYER_BAR_H)
end

-- ============================================================================
-- 子渲染函数
-- ============================================================================

function MapWidget:_DrawGrid(nvg, mx, my, mw, mh, theme)
    local g = theme.grid
    nvgStrokeColor(nvg, nvgRGBA(g[1], g[2], g[3], g[4]))
    nvgStrokeWidth(nvg, 0.5)
    for wx = 0, 1, 0.1 do
        local sx1, sy1 = self:_W2S(wx, 0, mx, my, mw, mh)
        local sx2, sy2 = self:_W2S(wx, 1, mx, my, mw, mh)
        nvgBeginPath(nvg); nvgMoveTo(nvg, sx1, sy1); nvgLineTo(nvg, sx2, sy2); nvgStroke(nvg)
    end
    for wy = 0, 1, 0.1 do
        local sx1, sy1 = self:_W2S(0, wy, mx, my, mw, mh)
        local sx2, sy2 = self:_W2S(1, wy, mx, my, mw, mh)
        nvgBeginPath(nvg); nvgMoveTo(nvg, sx1, sy1); nvgLineTo(nvg, sx2, sy2); nvgStroke(nvg)
    end
end

function MapWidget:_DrawPoly(nvg, poly, fillColor, strokeColor, strokeW, mx, my, mw, mh)
    if #poly < 6 then return end
    local sx, sy = self:_W2S(poly[1], poly[2], mx, my, mw, mh)
    nvgBeginPath(nvg); nvgMoveTo(nvg, sx, sy)
    for i = 3, #poly, 2 do
        sx, sy = self:_W2S(poly[i], poly[i+1], mx, my, mw, mh)
        nvgLineTo(nvg, sx, sy)
    end
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4]))
    nvgFill(nvg)
    if strokeColor then
        nvgStrokeColor(nvg, nvgRGBA(strokeColor[1], strokeColor[2], strokeColor[3], strokeColor[4]))
        nvgStrokeWidth(nvg, strokeW or 1)
        nvgStroke(nvg)
    end
end

function MapWidget:_DrawContextLabel(nvg, er, mx, my, mw, mh, theme)
    local lp = er.labelPos
    local sx, sy = self:_W2S(lp[1], lp[2], mx, my, mw, mh)
    local fontSize = math.max(8, math.min(16, 8 + self.zoom_ * 1.2))
    local alpha = self.zoom_ <= 3 and theme.labelA or math.max(30, theme.labelA - (self.zoom_ - 3) * 18)
    nvgFontFace(nvg, "sans"); nvgFontSize(nvg, fontSize)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(160, 148, 125, math.floor(alpha)))
    nvgText(nvg, sx, sy, er.label)
end

--- 安全图层 — 区域热力色覆盖
function MapWidget:_DrawSecurityLayer(nvg, mx, my, mw, mh)
    for _, gn in ipairs(GAME_NODES) do
        local rd = self:_FindRegionData(gn.id)
        if rd then
            local sec = rd.security or 3
            -- 1=红, 2=橙, 3=黄, 4=浅绿, 5=绿
            local r, g, b
            if sec <= 1 then     r, g, b = 200, 40, 40
            elseif sec <= 2 then r, g, b = 200, 120, 40
            elseif sec <= 3 then r, g, b = 200, 180, 60
            elseif sec <= 4 then r, g, b = 80, 160, 80
            else                 r, g, b = 40, 140, 60 end
            self:_DrawPoly(nvg, gn.poly, {r, g, b, 50}, nil, 0, mx, my, mw, mh)
        end
    end
end

--- 资源图层 — 在节点旁显示资源标签
function MapWidget:_DrawResourceLayer(nvg, mx, my, mw, mh)
    for _, gn in ipairs(GAME_NODES) do
        local rd = self:_FindRegionData(gn.id)
        if rd and rd.resources then
            local sx, sy = self:_W2S(gn.pos[1], gn.pos[2], mx, my, mw, mh)
            local offsetX = 0
            local iconSize = math.max(8, math.min(12, 6 + self.zoom_ * 1.0))
            nvgFontFace(nvg, "sans"); nvgFontSize(nvg, iconSize)
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            for _, resKey in ipairs(RESOURCE_ORDER) do
                local resVal = rd.resources[resKey] or 0
                if resVal > 0 and RESOURCE_ICONS[resKey] then
                    local tag = RESOURCE_ICONS[resKey]
                    -- 背景胶囊
                    local tw = iconSize * #tag * 0.6 + 6
                    local tx = sx + 14 + offsetX
                    local ty = sy - 14
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, tx - 3, ty - iconSize * 0.5 - 1, tw, iconSize + 2, 3)
                    nvgFillColor(nvg, nvgRGBA(30, 28, 22, 180))
                    nvgFill(nvg)
                    -- 文字
                    nvgFillColor(nvg, nvgRGBA(212, 175, 55, 220))
                    nvgText(nvg, tx, ty, tag)
                    offsetX = offsetX + tw + 2
                end
            end
        end
    end
end

--- 绘制游戏节点（§8.5 节点类型视觉）
function MapWidget:_DrawGameNode(nvg, gn, mx, my, mw, mh)
    local rd = self:_FindRegionData(gn.id)
    local isSel = (self.selectedNodeId_ == gn.id)
    local isHov = (self.hoveredNodeId_ == gn.id)
    local sx, sy = self:_W2S(gn.pos[1], gn.pos[2], mx, my, mw, mh)

    local nt = NODE_TYPES[gn.nodeType] or NODE_TYPES.mine
    local baseR = nt.size
    local r = math.max(6, baseR * (0.6 + self.zoom_ * 0.15))
    local nfill = self:_GetNodeFill(rd, isSel, isHov)

    if self.zoom_ < 2.5 then
        local dotR = isSel and 7 or (isHov and 6 or math.max(4, self.zoom_ * 2.2))
        nvgBeginPath(nvg)
        nvgCircle(nvg, sx, sy, dotR + (isSel and 3 or 0))
        nvgFillColor(nvg, nvgRGBA(20, 18, 14, isSel and 180 or 120))
        nvgFill(nvg)
        nvgBeginPath(nvg)
        nvgCircle(nvg, sx, sy, dotR)
        nvgFillColor(nvg, nvgRGBA(nfill[1], nfill[2], nfill[3], isHov and 245 or 220))
        nvgFill(nvg)
        if isSel or isHov then
            nvgStrokeColor(nvg, nvgRGBA(C.accent_gold[1], C.accent_gold[2], C.accent_gold[3], 220))
            nvgStrokeWidth(nvg, 1.4)
            nvgStroke(nvg)
        end
        return
    end

    -- 选中/悬停光环
    if isSel or isHov then
        self:_DrawNodeShape(nvg, sx, sy, r + 4)
        nvgFillColor(nvg, nvgRGBA(201, 168, 76, isSel and 80 or 50))
        nvgFill(nvg)
    end

    -- 节点形状
    self:_DrawNodeShape(nvg, sx, sy, r, gn.nodeType)
    nvgFillColor(nvg, nvgRGBA(nfill[1], nfill[2], nfill[3], nfill[4]))
    nvgFill(nvg)

    -- 节点边框
    local borderC = isSel and C.accent_gold or { 200, 190, 170 }
    nvgStrokeColor(nvg, nvgRGBA(borderC[1], borderC[2], borderC[3], isSel and 255 or 180))
    nvgStrokeWidth(nvg, isSel and 2.0 or 1.2)
    nvgStroke(nvg)

    -- 节点内图标（缩放 >= 2.5 时显示）
    if self.zoom_ >= 2.5 then
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, math.min(r * 1.0, 18))
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 230))
        nvgText(nvg, sx, sy, gn.icon)
    end

    -- 节点状态叠加图标（右上角 12pt）
    if rd then
        local statusIcon = nil
        if rd.security and rd.security <= 2 then statusIcon = "⚠" end
        if rd.control and rd.control >= 60 then statusIcon = "⭐" end
        if statusIcon and self.zoom_ >= 2.0 then
            nvgFontSize(nvg, 10)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 220, 80, 230))
            nvgText(nvg, sx + r + 2, sy - r, statusIcon)
        end
    end

    -- 节点标签（缩放 >= 3.0 时显示）
    if self.zoom_ >= 3.0 then
        local nameSize = math.min(13, 7 + self.zoom_ * 0.8)
        nvgFontFace(nvg, "sans"); nvgFontSize(nvg, nameSize)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(nvg, nvgRGBA(240, 230, 208, isSel and 255 or 190))
        nvgText(nvg, sx, sy + r + 3, gn.label)

        -- 控制比例（缩放 >= 4.0）
        if rd and self.zoom_ >= 4.0 then
            local ctrl = rd.control or 0
            local ctrlC = ctrl >= 60 and C.accent_green or (ctrl >= 30 and C.accent_amber or C.accent_red)
            nvgFontSize(nvg, math.min(11, 6 + self.zoom_ * 0.6))
            nvgFillColor(nvg, nvgRGBA(ctrlC[1], ctrlC[2], ctrlC[3], 210))
            nvgText(nvg, sx, sy + r + 3 + nameSize + 2, ctrl .. "%")
        end
    end
end

-- ============================================================================
-- 图层选择器（§8.5 顶部悬浮条）
-- ============================================================================

function MapWidget:_DrawLayerSelector(nvg, wx, wy, ww)
    -- 半透明背景条
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, wx + 1, wy + 1, ww - 2, LAYER_BAR_H, 5)
    nvgFillColor(nvg, nvgRGBA(25, 23, 18, 210))
    nvgFill(nvg)

    -- 绘制各图层胶囊按钮
    local px = wx + LAYER_BAR_PAD
    local py = wy + (LAYER_BAR_H - LAYER_PILL_H) * 0.5
    nvgFontFace(nvg, "sans")

    for _, layer in ipairs(LAYERS) do
        local isActive = self.activeLayers_[layer.id] or false
        local isLocked = layer.locked or false
        local pillW = 38

        -- 胶囊背景
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, px, py, pillW, LAYER_PILL_H, 4)
        if isActive then
            nvgFillColor(nvg, nvgRGBA(layer.color[1], layer.color[2], layer.color[3], 200))
        elseif isLocked then
            nvgFillColor(nvg, nvgRGBA(50, 46, 38, 120))
        else
            nvgFillColor(nvg, nvgRGBA(50, 46, 38, 180))
        end
        nvgFill(nvg)

        -- 色块指示器 (4x4)
        if not isActive then
            nvgBeginPath(nvg)
            nvgRect(nvg, px + 4, py + (LAYER_PILL_H - 4) * 0.5, 4, 4)
            nvgFillColor(nvg, nvgRGBA(layer.color[1], layer.color[2], layer.color[3], isLocked and 60 or 180))
            nvgFill(nvg)
        end

        -- 文字
        nvgFontSize(nvg, 10)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
        elseif isLocked then
            nvgFillColor(nvg, nvgRGBA(90, 82, 70, 160))
        else
            nvgFillColor(nvg, nvgRGBA(168, 152, 128, 200))
        end
        nvgText(nvg, px + pillW * 0.5, py + LAYER_PILL_H * 0.5, layer.label)

        px = px + pillW + LAYER_PILL_GAP
    end
end

-- ============================================================================
-- 地图 HUD 控件
-- ============================================================================

function MapWidget:_DrawControls(nvg, wx, wy, ww, wh)
    local bx = wx + ww - BTN_MARGIN - BTN_SIZE
    local by = wy + BTN_MARGIN

    -- 缩放倍率
    nvgFontFace(nvg, "sans"); nvgFontSize(nvg, 9)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(200, 185, 155, 140))
    nvgText(nvg, bx + BTN_SIZE * 0.5, by - 2, string.format("%.1fx", self.zoom_))

    self:_DrawBtn(nvg, bx, by, "+")
    self:_DrawBtn(nvg, bx, by + BTN_SIZE + BTN_GAP, "−")
    self:_DrawBtn(nvg, bx, by + (BTN_SIZE + BTN_GAP) * 2, "🌍")
    self:_DrawBtn(nvg, bx, by + (BTN_SIZE + BTN_GAP) * 3, "◎")

    -- 图例按钮（右下角）
    local legendY = wy + wh - BTN_MARGIN - BTN_SIZE
    self:_DrawBtn(nvg, bx, legendY, "?")

    if self.showLegend_ then
        self:_DrawLegendPanel(nvg, wx + ww - 178, legendY - 132)
    end

    -- 势力图例（左下角微型）
    if self.activeLayers_.control then
        local lx = wx + BTN_MARGIN
        local ly = wy + wh - BTN_MARGIN - 50
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, lx, ly, 62, 50, 4)
        nvgFillColor(nvg, nvgRGBA(25, 23, 18, 190))
        nvgFill(nvg)
        nvgFontFace(nvg, "sans"); nvgFontSize(nvg, 8)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local legendItems = {
            { "玩家", FACTION_COLORS.player },
            { "家族", FACTION_COLORS.local_clan },
            { "外资", FACTION_COLORS.foreign_capital },
            { "争议", FACTION_COLORS.contested },
        }
        for i, item in ipairs(legendItems) do
            local iy = ly + 5 + (i - 1) * 11
            nvgBeginPath(nvg)
            nvgRect(nvg, lx + 4, iy, 6, 6)
            nvgFillColor(nvg, nvgRGBA(item[2][1], item[2][2], item[2][3], 220))
            nvgFill(nvg)
            nvgFillColor(nvg, nvgRGBA(180, 170, 150, 200))
            nvgText(nvg, lx + 14, iy + 3, item[1])
        end
    end
end

function MapWidget:_DrawLegendPanel(nvg, x, y)
    local w, h = 168, 122
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, 5)
    nvgFillColor(nvg, nvgRGBA(25, 23, 18, 235))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(C.accent_gold[1], C.accent_gold[2], C.accent_gold[3], 120))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFontSize(nvg, 10)
    nvgFillColor(nvg, nvgRGBA(240, 230, 208, 230))
    nvgText(nvg, x + 10, y + 14, "地图图例")

    local rows = {
        { "控制色：玩家/家族/外资/争议", C.accent_gold },
        { "安全层：红低、绿高", C.accent_red },
        { "资源：Au 金 / Ag 银 / C 煤 / Fe 钢", C.accent_amber },
        { "◎ 聚焦波黑，地球显示全欧", C.accent_blue },
    }
    nvgFontSize(nvg, 8)
    for i, row in ipairs(rows) do
        local iy = y + 34 + (i - 1) * 20
        nvgBeginPath(nvg)
        nvgCircle(nvg, x + 12, iy, 3)
        nvgFillColor(nvg, nvgRGBA(row[2][1], row[2][2], row[2][3], 220))
        nvgFill(nvg)
        nvgFillColor(nvg, nvgRGBA(190, 176, 148, 220))
        nvgText(nvg, x + 22, iy, row[1])
    end
end

function MapWidget:_DrawBtn(nvg, x, y, label)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, BTN_SIZE, BTN_SIZE, 4)
    nvgFillColor(nvg, nvgRGBA(40, 36, 28, 200))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(C.accent_gold[1], C.accent_gold[2], C.accent_gold[3], 100))
    nvgStrokeWidth(nvg, 1); nvgStroke(nvg)
    nvgFontFace(nvg, "sans"); nvgFontSize(nvg, 14)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(220, 210, 190, 210))
    nvgText(nvg, x + BTN_SIZE * 0.5, y + BTN_SIZE * 0.5, label)
end

-- ============================================================================
-- 数据工具
-- ============================================================================

function MapWidget:_FindRegionData(regionId)
    for _, r in ipairs(self.regions_) do
        if r.id == regionId then return r end
    end
    return nil
end

-- ============================================================================
-- 交互事件
-- ============================================================================

function MapWidget:OnPointerDown(event)
    if not event:IsPrimaryAction() then return end
    local l = self:GetAbsoluteLayoutForHitTest()
    local px, py = event.x, event.y
    local mx, my, mw, mh = self:_MapAreaHit()

    -- 1. 图层选择器点击
    if py >= l.y and py <= l.y + LAYER_BAR_H then
        local pillX = l.x + LAYER_BAR_PAD
        local pillW = 38
        for _, layer in ipairs(LAYERS) do
            if px >= pillX and px <= pillX + pillW then
                self:ToggleLayer(layer.id)
                event:StopPropagation()
                return
            end
            pillX = pillX + pillW + LAYER_PILL_GAP
        end
        event:StopPropagation()
        return
    end

    -- 2. 缩放按钮
    local bx = l.x + l.w - BTN_MARGIN - BTN_SIZE
    local by = l.y + LAYER_BAR_H + BTN_MARGIN

    if self:_HitRect(px, py, bx, by, BTN_SIZE, BTN_SIZE) then
        self:_ZoomAt(l.x + l.w * 0.5, l.y + l.h * 0.5, ZOOM_STEP, mx, my, mw, mh)
        event:StopPropagation(); return
    end
    by = by + BTN_SIZE + BTN_GAP
    if self:_HitRect(px, py, bx, by, BTN_SIZE, BTN_SIZE) then
        self:_ZoomAt(l.x + l.w * 0.5, l.y + l.h * 0.5, 1/ZOOM_STEP, mx, my, mw, mh)
        event:StopPropagation(); return
    end
    by = by + BTN_SIZE + BTN_GAP
    if self:_HitRect(px, py, bx, by, BTN_SIZE, BTN_SIZE) then
        self.zoom_ = MIN_ZOOM; self.camX_ = 0.5; self.camY_ = 0.5
        event:StopPropagation(); return
    end
    by = by + BTN_SIZE + BTN_GAP
    if self:_HitRect(px, py, bx, by, BTN_SIZE, BTN_SIZE) then
        self.zoom_ = BOSNIA_ZOOM; self.camX_ = BOSNIA_CX; self.camY_ = BOSNIA_CY
        self:_ClampCam(); event:StopPropagation(); return
    end

    -- 图例按钮
    local legendY = l.y + LAYER_BAR_H + (l.h - LAYER_BAR_H) - BTN_MARGIN - BTN_SIZE
    if self:_HitRect(px, py, bx, legendY, BTN_SIZE, BTN_SIZE) then
        self.showLegend_ = not self.showLegend_
        event:StopPropagation(); return
    end

    -- 3. 拖拽准备
    self.pressing_ = true
    self.dragMoved_ = false
    self.dragStartSX_ = px; self.dragStartSY_ = py
    self.dragStartCamX_ = self.camX_; self.dragStartCamY_ = self.camY_

    if self.zoom_ > 1.05 then event:StopPropagation() end
end

function MapWidget:OnPointerMove(event)
    local px, py = event.x, event.y
    self.lastPtrX_ = px; self.lastPtrY_ = py

    if self.pressing_ then
        local dx = px - self.dragStartSX_
        local dy = py - self.dragStartSY_
        if not self.dragMoved_ and math.abs(dx) + math.abs(dy) > DRAG_THRESH then
            self.dragMoved_ = true
        end
        if self.dragMoved_ and self.zoom_ > 1.05 then
            local mx, my, mw, mh = self:_MapAreaHit()
            self.camX_ = self.dragStartCamX_ - dx / (self.zoom_ * mw)
            self.camY_ = self.dragStartCamY_ - dy / (self.zoom_ * mh)
            self:_ClampCam()
            event:StopPropagation()
        end
    else
        -- 悬停检测（节点）
        local mx, my, mw, mh = self:_MapAreaHit()
        self.hoveredNodeId_ = nil
        for i = #GAME_NODES, 1, -1 do
            if self:_HitPoly(px, py, GAME_NODES[i].poly, mx, my, mw, mh) then
                self.hoveredNodeId_ = GAME_NODES[i].id
                break
            end
        end
    end
end

function MapWidget:OnPointerUp(event)
    if not self.pressing_ then return end
    self.pressing_ = false

    if not self.dragMoved_ then
        local px, py = event.x, event.y
        local mx, my, mw, mh = self:_MapAreaHit()
        for i = #GAME_NODES, 1, -1 do
            if self:_HitPoly(px, py, GAME_NODES[i].poly, mx, my, mw, mh) then
                self.selectedNodeId_ = GAME_NODES[i].id
                if self.onRegionSelect_ then
                    self.onRegionSelect_(GAME_NODES[i].id)
                end
                event:StopPropagation()
                return
            end
        end
    end
end

function MapWidget:OnPointerEnter(event) self.ptrInside_ = true end
function MapWidget:OnPointerLeave(event)
    self.ptrInside_ = false; self.hoveredNodeId_ = nil
    if self.pressing_ then self.pressing_ = false; self.dragMoved_ = false end
end

-- ============================================================================
-- 碰撞检测
-- ============================================================================

function MapWidget:_HitRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

function MapWidget:_HitPoly(px, py, poly, mx, my, mw, mh)
    local n = #poly / 2
    if n < 3 then return false end
    local inside = false
    local j = n
    for i = 1, n do
        local xi, yi = self:_W2S(poly[(i-1)*2+1], poly[(i-1)*2+2], mx, my, mw, mh)
        local xj, yj = self:_W2S(poly[(j-1)*2+1], poly[(j-1)*2+2], mx, my, mw, mh)
        if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

return MapWidget
