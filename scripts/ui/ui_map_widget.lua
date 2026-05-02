-- ============================================================================
-- 欧洲地图控件 v4 — Civ6 式六边形网格渲染
-- 使用 MapTilesData 的 even-q flat-top hex 坐标
-- 坐标系：X=0..1 (15°W→45°E), Y=0..1 (71°N→34°N, 北在上)
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local Config = require("config")
local MapTilesData = require("data.map_tiles_data")

local C = Config.COLORS
local PI = math.pi

-- ============================================================================
-- 常量
-- ============================================================================

local MIN_ZOOM    = 1.0
local MAX_ZOOM    = 6.0
local ZOOM_STEP   = 1.30
local DRAG_THRESH = 5
local BOSNIA_CX   = 0.510
local BOSNIA_CY   = 0.730
local BOSNIA_ZOOM  = 5.0
local BTN_SIZE    = 30
local BTN_GAP     = 5
local BTN_MARGIN  = 8
local LAYER_BAR_H = 28
local LAYER_PILL_H = 22
local LAYER_PILL_GAP = 3
local LAYER_BAR_PAD = 6

-- ============================================================================
-- §8.5 图层定义（Civ6 式分层叠加）
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
-- §8.5 势力颜色
-- ============================================================================

local FACTION_COLORS = {
    player         = { 41, 128, 185 },
    local_clan     = { 139, 69,  19 },
    foreign_capital = { 39, 174,  96 },
    armed_group    = { 44,  62,  80 },
    neutral        = { 110, 110, 110 },
    contested      = { 170, 118,  48 },
}

-- ============================================================================
-- 大国主权着色
-- ============================================================================

local SOVEREIGN_COLORS = {
    austria_hungary = { 160, 130,  80 },
    germany         = { 100, 100,  85 },
    russia          = { 130, 110,  85 },
    britain         = { 120,  90, 100 },
    france          = {  80,  95, 140 },
    ottoman         = { 165, 140,  75 },
    italy           = {  95, 130,  85 },
    serbia          = { 170,  75,  75 },
    nazi_germany    = { 140,  55,  55 },
    soviet_union    = { 175,  60,  50 },
    yugoslavia      = {  70, 105, 145 },
    turkey          = { 155, 130,  70 },
    tito_yugoslavia = {  85, 115, 140 },
}

-- ============================================================================
-- 国家默认颜色（hex 填充底色）
-- ============================================================================

local COUNTRY_COLORS = {
    bosnia          = {  60,  90, 130 },
    scandinavia     = {  80, 100, 120 },
    finland         = {  90, 110, 130 },
    russia          = { 130, 110,  85 },
    britain         = { 120,  90, 100 },
    france          = {  80,  95, 140 },
    iberia          = { 120,  90,  60 },
    germany         = {  95,  92,  78 },
    italy           = {  95, 130,  85 },
    austria_hungary = { 160, 130,  80 },
    serbia          = { 170,  75,  75 },
    montenegro      = {  70,  92, 122 },
    romania         = { 105,  98,  62 },
    ottoman         = { 165, 140,  75 },
    greece          = {  62,  92, 122 },
    bulgaria        = {  92, 102,  72 },
    lowlands        = {  88,  95,  80 },
    denmark         = { 100,  88,  90 },
    switzerland     = { 110, 100, 100 },
}

-- ============================================================================
-- 地形色调微调（叠加在国家颜色上）
-- ============================================================================

local TERRAIN_TINT = {
    plains   = {  0,  0,  0 },
    hills    = { -8, -5,  5 },
    mountain = { -15, -10, 10 },
    forest   = { -10,  8, -5 },
    coast    = {  5,  8, 20 },
    urban    = { 10,  5, -5 },
    steppe   = {  5, -3, -8 },
}

-- ============================================================================
-- §8.5 节点类型定义
-- ============================================================================

local NODE_TYPES = {
    mine       = { icon = "⛏️",  label = "矿山区" },
    industrial = { icon = "🏭",  label = "工业城" },
    capital    = { icon = "🏛️",  label = "首都" },
    port       = { icon = "⚓",  label = "港口" },
    border     = { icon = "🛡️",  label = "边境" },
    cultural   = { icon = "🎭",  label = "文化" },
    strategic  = { icon = "⚔",   label = "山口" },
}

-- ============================================================================
-- §3.1 时代地图主题
-- ============================================================================

local ERA_MAP_THEMES = {
    [1] = { bg = { 45, 38, 28 }, grid = { 80, 68, 50, 20 }, hexAlpha = 42, labelA = 125 },
    [2] = { bg = { 38, 30, 25 }, grid = { 70, 50, 40, 20 }, hexAlpha = 38, labelA = 115 },
    [3] = { bg = { 28, 35, 49 }, grid = { 50, 60, 80, 20 }, hexAlpha = 45, labelA = 135 },
    [4] = { bg = { 40, 40, 40 }, grid = { 60, 60, 60, 18 }, hexAlpha = 35, labelA = 95 },
    [5] = { bg = { 27, 40, 55 }, grid = { 40, 55, 75, 20 }, hexAlpha = 42, labelA = 125 },
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
    self.mapTiles_        = MapTilesData.CreateInitialTiles()
    self.onRegionSelect_  = props.onRegionSelect

    -- 图层状态
    self.activeLayers_ = { control = true }

    -- 时代
    self.eraId_ = 1

    -- 大国博弈
    self.europeState_ = nil
    self.frontLineData_ = nil

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

    -- tile 坐标索引缓存
    self.tileByCoord_ = nil

    Widget.Init(self, props)
end

-- ============================================================================
-- 公开 API
-- ============================================================================

function MapWidget:SetRegions(regions) self.regions_ = regions or {} end
function MapWidget:SetMapTiles(tiles)
    self.mapTiles_ = tiles or MapTilesData.CreateInitialTiles()
    MapTilesData.RebuildNeighbors(self.mapTiles_)
    self:_RebuildCoordIndex()
end
function MapWidget:SetSelected(id) self.selectedNodeId_ = id end
function MapWidget:GetSelected() return self.selectedNodeId_ end
function MapWidget:SetEra(eraId) self.eraId_ = eraId or 1 end
function MapWidget:SetEuropeState(europeData) self.europeState_ = europeData end
function MapWidget:SetFrontLineData(data) self.frontLineData_ = data end

--- 根据游戏状态动态解锁地图图层
function MapWidget:UpdateUnlocks(state)
    if not state then return end
    for _, layer in ipairs(LAYERS) do
        if layer.locked then
            local shouldUnlock = false
            if layer.id == "trade" then
                shouldUnlock = state.mines and #state.mines >= 3
            elseif layer.id == "military" then
                shouldUnlock = state.military and state.military.guards >= 10
            elseif layer.id == "intel" then
                shouldUnlock = state.flags and state.flags.intel_unlocked
            end
            if shouldUnlock then
                layer.locked = false
            end
        end
    end
end

function MapWidget:ToggleLayer(layerId)
    if layerId == "control" then return end
    local layerDef = nil
    for _, l in ipairs(LAYERS) do
        if l.id == layerId then layerDef = l; break end
    end
    if not layerDef or layerDef.locked then return end
    if self.activeLayers_[layerId] then
        self.activeLayers_[layerId] = nil
    else
        local count = 0
        for k, _ in pairs(self.activeLayers_) do
            if k ~= "control" then count = count + 1 end
        end
        if count >= 2 then return end
        self.activeLayers_[layerId] = true
    end
end

-- ============================================================================
-- 坐标变换
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
-- Hex 渲染工具
-- ============================================================================

--- 在屏幕坐标绘制一个 hex 路径（不调用 fill/stroke）
function MapWidget:_BeginHexPath(nvg, q, r, mx, my, mw, mh)
    local corners = MapTilesData.GetHexCorners(q, r)
    nvgBeginPath(nvg)
    for i = 1, 12, 2 do
        local sx, sy = self:_W2S(corners[i], corners[i + 1], mx, my, mw, mh)
        if i == 1 then
            nvgMoveTo(nvg, sx, sy)
        else
            nvgLineTo(nvg, sx, sy)
        end
    end
    nvgClosePath(nvg)
end

--- 坐标索引缓存
function MapWidget:_RebuildCoordIndex()
    self.tileByCoord_ = {}
    for _, t in ipairs(self.mapTiles_ or {}) do
        self.tileByCoord_[(t.q or 0) .. "," .. (t.r or 0)] = t
    end
end

function MapWidget:_GetTileAtCoord(q, r)
    if not self.tileByCoord_ then self:_RebuildCoordIndex() end
    return self.tileByCoord_[q .. "," .. r]
end

-- ============================================================================
-- 势力颜色工具
-- ============================================================================

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
    return "contested"
end

function MapWidget:_GetFactionColor(factionId)
    return FACTION_COLORS[factionId] or FACTION_COLORS.neutral
end

-- ============================================================================
-- Hex 填充色计算
-- ============================================================================

--- 获取 tile 的基础国家颜色（考虑时代主题和地形微调）
function MapWidget:_GetHexBaseColor(tile, theme)
    local cc = COUNTRY_COLORS[tile.country_id] or { 90, 85, 75 }
    local tint = TERRAIN_TINT[tile.terrain] or { 0, 0, 0 }
    local r = math.max(0, math.min(255, cc[1] + tint[1]))
    local g = math.max(0, math.min(255, cc[2] + tint[2]))
    local b = math.max(0, math.min(255, cc[3] + tint[3]))
    return r, g, b
end

--- 获取 tile 在控制层的颜色
function MapWidget:_GetHexControlColor(tile, isSelected, isHovered)
    -- 波黑 tile 有 region_id 的：用势力着色
    if tile.region_id then
        local rd = self:_FindRegionData(tile.region_id)
        local faction = self:_GetDominantFaction(rd)
        local fc = self:_GetFactionColor(faction)
        local a = isSelected and 200 or (isHovered and 170 or 130)
        return fc[1], fc[2], fc[3], a
    end
    -- 波黑 tile 无 region_id：用 controller
    if tile.country_id == "bosnia" then
        local fc = FACTION_COLORS[tile.controller] or FACTION_COLORS.contested
        local a = isSelected and 180 or (isHovered and 150 or 110)
        return fc[1], fc[2], fc[3], a
    end
    -- 外国 tile：用主权着色（如被占领）
    local sc = SOVEREIGN_COLORS[tile.controller] or COUNTRY_COLORS[tile.country_id]
    if not sc then sc = { 90, 85, 75 } end
    local a = isSelected and 160 or (isHovered and 130 or 80)
    return sc[1], sc[2], sc[3], a
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
            self:_ZoomAt(self.lastPtrX_, self.lastPtrY_, wheel > 0 and ZOOM_STEP or (1 / ZOOM_STEP), mx, my, mw, mh)
        end
    end

    -- ① 底板
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, 6)
    nvgFillColor(nvg, nvgRGBA(theme.bg[1], theme.bg[2], theme.bg[3], 255))
    nvgFill(nvg)

    -- 裁剪地图区域
    nvgSave(nvg)
    nvgScissor(nvg, mx, my, mw, mh)

    -- ② Hex 底色填充（国家颜色 + 地形微调）
    self:_DrawHexFills(nvg, mx, my, mw, mh, theme)

    -- ③ 控制层叠加色
    if self.activeLayers_.control then
        self:_DrawControlLayer(nvg, mx, my, mw, mh)
    end

    -- ④ 安全图层
    if self.activeLayers_.security then
        self:_DrawSecurityLayer(nvg, mx, my, mw, mh)
    end

    if self.activeLayers_.trade then
        self:_DrawTradeLayer(nvg, mx, my, mw, mh)
    end
    if self.activeLayers_.military then
        self:_DrawMilitaryLayer(nvg, mx, my, mw, mh)
    end
    if self.activeLayers_.intel then
        self:_DrawIntelLayer(nvg, mx, my, mw, mh)
    end

    -- ⑤ Hex 网格线 + 国家边界
    self:_DrawHexGrid(nvg, mx, my, mw, mh, theme)
    self:_DrawCountryBorders(nvg, mx, my, mw, mh)

    -- ⑥ 前线指示器
    self:_DrawFrontLines(nvg, mx, my, mw, mh)

    -- ⑦ 国家标签
    self:_DrawCountryLabels(nvg, mx, my, mw, mh, theme)

    -- ⑧ 资源图层
    if self.activeLayers_.resource then
        self:_DrawResourceLayer(nvg, mx, my, mw, mh)
    end

    -- ⑨ 节点图标 & 标签
    self:_DrawNodeIcons(nvg, mx, my, mw, mh)

    nvgRestore(nvg)  -- 恢复裁剪

    -- 边框
    local era = Config.GetEraByYear and Config.GetEraByYear(1904 + (self.eraId_ - 1) * 15) or nil
    local borderC = era and era.border or C.border_gold
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, 6)
    nvgStrokeColor(nvg, nvgRGBA(borderC[1], borderC[2], borderC[3], 140))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)

    -- ⑩ 图层选择器
    self:_DrawLayerSelector(nvg, l.x, l.y, l.w)

    -- ⑪ HUD 控件
    self:_DrawControls(nvg, l.x, l.y + LAYER_BAR_H, l.w, l.h - LAYER_BAR_H)
end

-- ============================================================================
-- Hex 底色填充
-- ============================================================================

function MapWidget:_DrawHexFills(nvg, mx, my, mw, mh, theme)
    local alpha = theme.hexAlpha or 42
    for _, tile in ipairs(self.mapTiles_) do
        local r, g, b = self:_GetHexBaseColor(tile, theme)
        local isSel = (self.selectedNodeId_ == tile.id)
        local isHov = (self.hoveredNodeId_ == tile.id)
        -- 主权覆盖：如果 europeState 中被占领，使用占领方颜色
        if self.europeState_ and tile.country_id ~= "bosnia" then
            local cs = self.europeState_[tile.country_id]
            if cs then
                local sc = SOVEREIGN_COLORS[cs.sovereign]
                if sc then
                    r, g, b = sc[1], sc[2], sc[3]
                end
                if cs.sovereign ~= cs.original then
                    alpha = math.min(255, (theme.hexAlpha or 42) + 40)
                end
            end
        end
        local a = isSel and math.min(255, alpha + 60) or (isHov and math.min(255, alpha + 30) or alpha)
        self:_BeginHexPath(nvg, tile.q, tile.r, mx, my, mw, mh)
        nvgFillColor(nvg, nvgRGBA(r, g, b, a))
        nvgFill(nvg)
    end
end

-- ============================================================================
-- 控制层叠加
-- ============================================================================

function MapWidget:_DrawControlLayer(nvg, mx, my, mw, mh)
    for _, tile in ipairs(self.mapTiles_) do
        local isSel = (self.selectedNodeId_ == tile.id)
        local isHov = (self.hoveredNodeId_ == tile.id)
        local r, g, b, a = self:_GetHexControlColor(tile, isSel, isHov)
        self:_BeginHexPath(nvg, tile.q, tile.r, mx, my, mw, mh)
        nvgFillColor(nvg, nvgRGBA(r, g, b, a))
        nvgFill(nvg)
    end
end

-- ============================================================================
-- 安全图层
-- ============================================================================

function MapWidget:_DrawSecurityLayer(nvg, mx, my, mw, mh)
    for _, tile in ipairs(self.mapTiles_) do
        local rd = self:_FindRegionData(tile.region_id)
        if rd then
            local sec = rd.security or 3
            local r, g, b
            if sec <= 1 then     r, g, b = 200, 40, 40
            elseif sec <= 2 then r, g, b = 200, 120, 40
            elseif sec <= 3 then r, g, b = 200, 180, 60
            elseif sec <= 4 then r, g, b = 80, 160, 80
            else                 r, g, b = 40, 140, 60 end
            self:_BeginHexPath(nvg, tile.q, tile.r, mx, my, mw, mh)
            nvgFillColor(nvg, nvgRGBA(r, g, b, 50))
            nvgFill(nvg)
        end
    end
end

function MapWidget:_DrawTileOverlay(nvg, tile, rgba, mx, my, mw, mh)
    self:_BeginHexPath(nvg, tile.q, tile.r, mx, my, mw, mh)
    nvgFillColor(nvg, nvgRGBA(rgba[1], rgba[2], rgba[3], rgba[4]))
    nvgFill(nvg)
end

function MapWidget:_DrawTradeLayer(nvg, mx, my, mw, mh)
    for _, tile in ipairs(self.mapTiles_) do
        if tile.type == "port" or tile.type == "industrial" or tile.type == "mine" then
            self:_DrawTileOverlay(nvg, tile, { 46, 204, 113, tile.type == "port" and 70 or 42 }, mx, my, mw, mh)
        end
    end
end

function MapWidget:_DrawMilitaryLayer(nvg, mx, my, mw, mh)
    for _, tile in ipairs(self.mapTiles_) do
        if tile.type == "border" or tile.type == "strategic" or tile.controller == "local_clan" then
            self:_DrawTileOverlay(nvg, tile, { 44, 62, 80, 70 }, mx, my, mw, mh)
        end
    end
end

function MapWidget:_DrawIntelLayer(nvg, mx, my, mw, mh)
    for _, tile in ipairs(self.mapTiles_) do
        if tile.controller == "foreign_capital" or tile.controller == "local_clan" or tile.controller == "contested" then
            self:_DrawTileOverlay(nvg, tile, { 149, 165, 166, tile.controller == "contested" and 45 or 65 }, mx, my, mw, mh)
        end
    end
end

-- ============================================================================
-- Hex 网格线
-- ============================================================================

function MapWidget:_DrawHexGrid(nvg, mx, my, mw, mh, theme)
    local g = theme.grid
    nvgStrokeColor(nvg, nvgRGBA(g[1], g[2], g[3], g[4]))
    nvgStrokeWidth(nvg, 0.5)
    for _, tile in ipairs(self.mapTiles_) do
        self:_BeginHexPath(nvg, tile.q, tile.r, mx, my, mw, mh)
        nvgStroke(nvg)
    end
end

-- ============================================================================
-- 国家边界（不同 country_id 之间画粗线）
-- ============================================================================

function MapWidget:_DrawCountryBorders(nvg, mx, my, mw, mh)
    -- even-q flat-top 各边对应的邻居方向
    local evenDirs = { {1, -1}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {-1, 0} }
    local oddDirs  = { {1, 0}, {1, 1}, {0, -1}, {0, 1}, {-1, 0}, {-1, 1} }

    nvgStrokeWidth(nvg, 1.8)

    for _, tile in ipairs(self.mapTiles_) do
        local q, r = tile.q, tile.r
        local corners = MapTilesData.GetHexCorners(q, r)
        local dirs = (q % 2 == 0) and evenDirs or oddDirs

        for edgeIdx = 1, 6 do
            local d = dirs[edgeIdx]
            local nq, nr = q + d[1], r + d[2]
            local neighbor = self:_GetTileAtCoord(nq, nr)

            -- 画国界边：邻居不存在（外边界）或国家不同
            local isBorder = (not neighbor) or (neighbor.country_id ~= tile.country_id)
            if isBorder then
                -- flat-top hex: 边 i 连接顶点 i 和 i+1
                local i1 = edgeIdx
                local i2 = (edgeIdx % 6) + 1
                local wx1, wy1 = corners[(i1 - 1) * 2 + 1], corners[(i1 - 1) * 2 + 2]
                local wx2, wy2 = corners[(i2 - 1) * 2 + 1], corners[(i2 - 1) * 2 + 2]
                local sx1, sy1 = self:_W2S(wx1, wy1, mx, my, mw, mh)
                local sx2, sy2 = self:_W2S(wx2, wy2, mx, my, mw, mh)

                -- 波黑边界用金色
                local isBosniaBorder = (tile.country_id == "bosnia") or (neighbor and neighbor.country_id == "bosnia")
                if isBosniaBorder then
                    nvgStrokeColor(nvg, nvgRGBA(201, 168, 76, 200))
                else
                    nvgStrokeColor(nvg, nvgRGBA(120, 110, 90, 150))
                end

                nvgBeginPath(nvg)
                nvgMoveTo(nvg, sx1, sy1)
                nvgLineTo(nvg, sx2, sy2)
                nvgStroke(nvg)
            end
        end
    end
end

-- ============================================================================
-- 国家标签（基于 hex 中心聚合计算标签位置）
-- ============================================================================

function MapWidget:_DrawCountryLabels(nvg, mx, my, mw, mh, theme)
    -- 先计算每个国家的所有 tile 中心的平均位置
    local countryInfo = {}
    for _, tile in ipairs(self.mapTiles_) do
        local cid = tile.country_id
        if not countryInfo[cid] then
            countryInfo[cid] = { sumX = 0, sumY = 0, count = 0, label = nil }
        end
        local cx, cy = MapTilesData.GetHexCenter(tile.q, tile.r)
        countryInfo[cid].sumX = countryInfo[cid].sumX + cx
        countryInfo[cid].sumY = countryInfo[cid].sumY + cy
        countryInfo[cid].count = countryInfo[cid].count + 1
    end

    -- 国家显示名称
    local COUNTRY_LABELS = {
        bosnia = "波斯尼亚", scandinavia = "瑞典-挪威", finland = "芬兰",
        russia = "俄罗斯帝国", britain = "大英帝国", france = "法兰西",
        iberia = "西班牙", germany = "德意志帝国", italy = "意大利",
        austria_hungary = "奥匈帝国", serbia = "塞尔维亚", montenegro = "黑山",
        romania = "罗马尼亚", ottoman = "奥斯曼帝国", greece = "希腊",
        bulgaria = "保加利亚", lowlands = "低地国家", denmark = "丹麦",
        switzerland = "瑞士",
    }

    local fontSize = math.max(8, math.min(16, 8 + self.zoom_ * 1.2))
    local alpha = self.zoom_ <= 3 and theme.labelA or math.max(30, theme.labelA - (self.zoom_ - 3) * 18)

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, fontSize)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for cid, info in pairs(countryInfo) do
        local avgX = info.sumX / info.count
        local avgY = info.sumY / info.count
        local sx, sy = self:_W2S(avgX, avgY, mx, my, mw, mh)
        local label = COUNTRY_LABELS[cid] or cid

        -- 占领指示器
        local occupierTag = nil
        if self.europeState_ and cid ~= "bosnia" and self.zoom_ >= 1.8 then
            local cs = self.europeState_[cid]
            if cs and cs.sovereign ~= cs.original then
                occupierTag = cs.sovereign
            end
        end

        -- 国名文字阴影
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.5)))
        nvgText(nvg, sx + 1, sy + 1, label)
        -- 国名文字
        nvgFillColor(nvg, nvgRGBA(190, 178, 155, math.floor(alpha)))
        nvgText(nvg, sx, sy, label)

        -- 占领指示
        if occupierTag then
            local tagSize = math.max(7, math.min(11, 6 + self.zoom_ * 0.8))
            nvgFontSize(nvg, tagSize)
            nvgFillColor(nvg, nvgRGBA(200, 70, 60, 200))
            nvgText(nvg, sx, sy + fontSize * 0.7, "占" .. (COUNTRY_LABELS[occupierTag] or occupierTag))
            nvgFontSize(nvg, fontSize)
        end
    end
end

-- ============================================================================
-- 前线指示器
-- ============================================================================

function MapWidget:_DrawFrontLines(nvg, mx, my, mw, mh)
    if not self.frontLineData_ or #self.frontLineData_ == 0 then return end

    -- 构建国家中心位置查找表（基于 hex 平均位置）
    local posLookup = {}
    for _, tile in ipairs(self.mapTiles_) do
        local cid = tile.country_id
        if not posLookup[cid] then posLookup[cid] = { sumX = 0, sumY = 0, n = 0 } end
        local cx, cy = MapTilesData.GetHexCenter(tile.q, tile.r)
        posLookup[cid].sumX = posLookup[cid].sumX + cx
        posLookup[cid].sumY = posLookup[cid].sumY + cy
        posLookup[cid].n = posLookup[cid].n + 1
    end

    local t = os.clock()

    for _, fl in ipairs(self.frontLineData_) do
        local fromInfo = posLookup[fl.from_id]
        local toInfo = posLookup[fl.to_id]
        if fromInfo and toInfo and fromInfo.n > 0 and toInfo.n > 0 then
            local fromX = fromInfo.sumX / fromInfo.n
            local fromY = fromInfo.sumY / fromInfo.n
            local toX = toInfo.sumX / toInfo.n
            local toY = toInfo.sumY / toInfo.n

            local sx1, sy1 = self:_W2S(fromX, fromY, mx, my, mw, mh)
            local sx2, sy2 = self:_W2S(toX, toY, mx, my, mw, mh)

            local c = SOVEREIGN_COLORS[fl.from_id] or {200, 60, 50}
            local pulse = 0.55 + 0.45 * math.sin(t * 2.5 + (fl._phase or 0))
            local alpha = math.floor(180 * pulse)

            local dx = sx2 - sx1
            local dy = sy2 - sy1
            local len = math.sqrt(dx * dx + dy * dy)
            if len < 5 then goto continue end

            local ux, uy = dx / len, dy / len
            local shrink = math.min(len * 0.18, 16)
            local ax1 = sx1 + ux * shrink
            local ay1 = sy1 + uy * shrink
            local ax2 = sx2 - ux * shrink
            local ay2 = sy2 - uy * shrink

            -- 虚线
            local segLen = math.max(4, 6 + self.zoom_ * 0.5)
            local gapLen = math.max(3, 4 + self.zoom_ * 0.3)
            local lineDx = ax2 - ax1
            local lineDy = ay2 - ay1
            local lineLen = math.sqrt(lineDx * lineDx + lineDy * lineDy)
            local lux = lineDx / math.max(1, lineLen)
            local luy = lineDy / math.max(1, lineLen)
            local lineW = math.max(1.2, math.min(2.5, 1.0 + self.zoom_ * 0.25))

            nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
            nvgStrokeWidth(nvg, lineW)

            local pos = 0
            while pos < lineLen do
                local segEnd = math.min(pos + segLen, lineLen)
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, ax1 + lux * pos, ay1 + luy * pos)
                nvgLineTo(nvg, ax1 + lux * segEnd, ay1 + luy * segEnd)
                nvgStroke(nvg)
                pos = segEnd + gapLen
            end

            -- 箭头
            local arrowLen = math.max(5, math.min(10, lineLen * 0.12))
            local ahx = ax2 - ux * arrowLen
            local ahy = ay2 - uy * arrowLen
            local perpX, perpY = -uy * arrowLen * 0.45, ux * arrowLen * 0.45

            nvgBeginPath(nvg)
            nvgMoveTo(nvg, ax2, ay2)
            nvgLineTo(nvg, ahx + perpX, ahy + perpY)
            nvgLineTo(nvg, ahx - perpX, ahy - perpY)
            nvgClosePath(nvg)
            nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
            nvgFill(nvg)

            -- 中点 ⚔ 图标
            if self.zoom_ >= 1.5 then
                local midX = (ax1 + ax2) * 0.5
                local midY = (ay1 + ay2) * 0.5
                local iconSize = math.max(8, math.min(14, 7 + self.zoom_ * 1.0))
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, iconSize)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.min(255, alpha + 40)))
                nvgText(nvg, midX, midY, "⚔")
            end

            ::continue::
        end
    end
end

-- ============================================================================
-- 资源图层
-- ============================================================================

function MapWidget:_DrawResourceLayer(nvg, mx, my, mw, mh)
    for _, tile in ipairs(self.mapTiles_) do
        local rd = self:_FindRegionData(tile.region_id)
        if rd and rd.resources then
            local cx, cy = MapTilesData.GetHexCenter(tile.q, tile.r)
            local sx, sy = self:_W2S(cx, cy, mx, my, mw, mh)
            local offsetX = 0
            local iconSize = math.max(8, math.min(12, 6 + self.zoom_ * 1.0))
            nvgFontFace(nvg, "sans"); nvgFontSize(nvg, iconSize)
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            for _, resKey in ipairs(RESOURCE_ORDER) do
                local resVal = rd.resources[resKey] or 0
                if resVal > 0 and RESOURCE_ICONS[resKey] then
                    local tag = RESOURCE_ICONS[resKey]
                    local tw = iconSize * #tag * 0.6 + 6
                    local tx = sx + 14 + offsetX
                    local ty = sy - 14
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, tx - 3, ty - iconSize * 0.5 - 1, tw, iconSize + 2, 3)
                    nvgFillColor(nvg, nvgRGBA(30, 28, 22, 180))
                    nvgFill(nvg)
                    nvgFillColor(nvg, nvgRGBA(212, 175, 55, 220))
                    nvgText(nvg, tx, ty, tag)
                    offsetX = offsetX + tw + 2
                end
            end
        end
    end
end

-- ============================================================================
-- 节点图标 & 标签
-- ============================================================================

function MapWidget:_DrawNodeIcons(nvg, mx, my, mw, mh)
    for _, tile in ipairs(self.mapTiles_) do
        local cx, cy = MapTilesData.GetHexCenter(tile.q, tile.r)
        local sx, sy = self:_W2S(cx, cy, mx, my, mw, mh)
        local isSel = (self.selectedNodeId_ == tile.id)
        local isHov = (self.hoveredNodeId_ == tile.id)
        local rd = self:_FindRegionData(tile.region_id)

        local nt = NODE_TYPES[tile.type]
        local icon = (nt and nt.icon) or ""

        -- 选中/悬停高亮边框
        if isSel or isHov then
            self:_BeginHexPath(nvg, tile.q, tile.r, mx, my, mw, mh)
            nvgStrokeColor(nvg, nvgRGBA(201, 168, 76, isSel and 255 or 180))
            nvgStrokeWidth(nvg, isSel and 3.0 or 2.0)
            nvgStroke(nvg)
        end

        -- 缩放 < 2.5 时：只画小圆点
        if self.zoom_ < 2.5 then
            -- 波黑 tile 或有 region_id 的显示圆点
            if tile.country_id == "bosnia" or tile.region_id then
                local dotR = isSel and 5 or (isHov and 4 or 3)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, dotR)
                local fc = FACTION_COLORS[tile.controller] or FACTION_COLORS.neutral
                nvgFillColor(nvg, nvgRGBA(fc[1], fc[2], fc[3], 220))
                nvgFill(nvg)
                if isSel then
                    nvgStrokeColor(nvg, nvgRGBA(201, 168, 76, 220))
                    nvgStrokeWidth(nvg, 1.2)
                    nvgStroke(nvg)
                end
            end
            goto nextTile
        end

        -- 缩放 >= 2.5：显示节点图标
        if icon ~= "" then
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, math.max(10, math.min(18, 8 + self.zoom_ * 1.5)))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 230))
            nvgText(nvg, sx, sy, icon)
        end

        -- 状态叠加图标
        if rd then
            local statusIcon = nil
            if rd.security and rd.security <= 2 then statusIcon = "⚠" end
            if rd.control and rd.control >= 60 then statusIcon = "⭐" end
            if statusIcon and self.zoom_ >= 2.5 then
                nvgFontSize(nvg, 10)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(255, 220, 80, 230))
                local hexR = MapTilesData.HEX_SIZE * self.zoom_ * mw * 0.4
                nvgText(nvg, sx + hexR, sy - hexR, statusIcon)
            end
        end

        -- 缩放 >= 3.0：显示 tile 名称
        if self.zoom_ >= 3.0 then
            local nameSize = math.min(13, 7 + self.zoom_ * 0.8)
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, nameSize)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            -- 文字阴影
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 120))
            local hexScreenR = MapTilesData.HEX_SIZE * self.zoom_ * mw * 0.5
            nvgText(nvg, sx + 1, sy + hexScreenR + 2, tile.label)
            nvgFillColor(nvg, nvgRGBA(240, 230, 208, isSel and 255 or 190))
            nvgText(nvg, sx, sy + hexScreenR + 1, tile.label)

            -- 控制比例（缩放 >= 4.0，仅波黑）
            if rd and self.zoom_ >= 4.0 then
                local ctrl = rd.control or 0
                local ctrlC = ctrl >= 60 and C.accent_green or (ctrl >= 30 and C.accent_amber or C.accent_red)
                nvgFontSize(nvg, math.min(11, 6 + self.zoom_ * 0.6))
                nvgFillColor(nvg, nvgRGBA(ctrlC[1], ctrlC[2], ctrlC[3], 210))
                nvgText(nvg, sx, sy + hexScreenR + 1 + nameSize + 2, ctrl .. "%")
            end
        end

        ::nextTile::
    end
end

-- ============================================================================
-- 图层选择器
-- ============================================================================

function MapWidget:_DrawLayerSelector(nvg, wx, wy, ww)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, wx + 1, wy + 1, ww - 2, LAYER_BAR_H, 5)
    nvgFillColor(nvg, nvgRGBA(25, 23, 18, 210))
    nvgFill(nvg)

    local px = wx + LAYER_BAR_PAD
    local py = wy + (LAYER_BAR_H - LAYER_PILL_H) * 0.5
    nvgFontFace(nvg, "sans")

    for _, layer in ipairs(LAYERS) do
        local isActive = self.activeLayers_[layer.id] or false
        local isLocked = layer.locked or false
        local pillW = 38

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

        if not isActive then
            nvgBeginPath(nvg)
            nvgRect(nvg, px + 4, py + (LAYER_PILL_H - 4) * 0.5, 4, 4)
            nvgFillColor(nvg, nvgRGBA(layer.color[1], layer.color[2], layer.color[3], isLocked and 60 or 180))
            nvgFill(nvg)
        end

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
-- HUD 控件
-- ============================================================================

function MapWidget:_DrawControls(nvg, wx, wy, ww, wh)
    local bx = wx + ww - BTN_MARGIN - BTN_SIZE
    local by = wy + BTN_MARGIN

    nvgFontFace(nvg, "sans"); nvgFontSize(nvg, 9)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(200, 185, 155, 140))
    nvgText(nvg, bx + BTN_SIZE * 0.5, by - 2, string.format("%.1fx", self.zoom_))

    self:_DrawBtn(nvg, bx, by, "+")
    self:_DrawBtn(nvg, bx, by + BTN_SIZE + BTN_GAP, "−")
    self:_DrawBtn(nvg, bx, by + (BTN_SIZE + BTN_GAP) * 2, "🌍")
    self:_DrawBtn(nvg, bx, by + (BTN_SIZE + BTN_GAP) * 3, "◎")

    local legendY = wy + wh - BTN_MARGIN - BTN_SIZE
    self:_DrawBtn(nvg, bx, legendY, "?")

    if self.showLegend_ then
        self:_DrawLegendPanel(nvg, wx + ww - 178, legendY - 132)
    end

    -- 势力图例（左下角）
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
        { "◎ 聚焦波黑，🌍 显示全欧", C.accent_blue },
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
    if not regionId then return nil end
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
        self:_ZoomAt(l.x + l.w * 0.5, l.y + l.h * 0.5, 1 / ZOOM_STEP, mx, my, mw, mh)
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
        -- 悬停检测（hex 命中）
        local mx, my, mw, mh = self:_MapAreaHit()
        self.hoveredNodeId_ = nil
        local wx, wy = self:_S2W(px, py, mx, my, mw, mh)
        for i = #self.mapTiles_, 1, -1 do
            local tile = self.mapTiles_[i]
            if MapTilesData.HitHex(wx, wy, tile.q, tile.r) then
                self.hoveredNodeId_ = tile.id
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
        local wx, wy = self:_S2W(px, py, mx, my, mw, mh)
        for i = #self.mapTiles_, 1, -1 do
            local tile = self.mapTiles_[i]
            if MapTilesData.HitHex(wx, wy, tile.q, tile.r) then
                self.selectedNodeId_ = tile.id
                if self.onRegionSelect_ then
                    self.onRegionSelect_(tile.id)
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

return MapWidget
