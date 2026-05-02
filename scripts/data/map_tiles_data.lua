-- ============================================================================
-- 宏观六边形地图模块数据
-- 说明：
-- - 这是显示与占领感知层，不替代现有 state.regions 经济结算。
-- - 本地 tile 通过 region_id 聚合回 region.control / region.ai_presence。
-- ============================================================================

local MapTilesData = {}

local function copyTile(t)
    local c = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            local sub = {}
            for kk, vv in pairs(v) do sub[kk] = vv end
            c[k] = sub
        else
            c[k] = v
        end
    end
    return c
end

MapTilesData.TEMPLATES = {
    -- 波黑核心：与现有三个 region 关联
    { id = "tile_sarajevo", label = "萨拉热窝", country_id = "bosnia", region_id = "capital_city", type = "capital", q = 0, r = 0, weight = 2, controller = "foreign_capital" },
    { id = "tile_bakovici", label = "巴科维奇矿区", country_id = "bosnia", region_id = "mine_district", type = "mine", q = -1, r = 1, weight = 2, controller = "player" },
    { id = "tile_zenica", label = "泽尼察工业区", country_id = "bosnia", region_id = "industrial_town", type = "industrial", q = 0, r = 1, weight = 2, controller = "local_clan" },
    { id = "tile_bosnia_rail", label = "波黑铁路节点", country_id = "bosnia", region_id = "industrial_town", type = "rail", q = 1, r = 0, weight = 1, controller = "foreign_capital" },
    { id = "tile_bosnia_border", label = "德里纳边境", country_id = "bosnia", region_id = "capital_city", type = "border", q = 1, r = -1, weight = 1, controller = "contested" },

    -- 邻近与欧洲关键模块
    { id = "tile_vienna", label = "维也纳", country_id = "austria_hungary", type = "capital", q = -2, r = -1, weight = 2, controller = "austria_hungary" },
    { id = "tile_austrian_industry", label = "奥地利工业区", country_id = "austria_hungary", type = "industrial", q = -2, r = 0, weight = 1, controller = "austria_hungary" },
    { id = "tile_belgrade", label = "贝尔格莱德", country_id = "serbia", type = "capital", q = 2, r = -1, weight = 2, controller = "serbia" },
    { id = "tile_serbia_border", label = "塞尔维亚边境", country_id = "serbia", type = "border", q = 2, r = 0, weight = 1, controller = "serbia" },
    { id = "tile_berlin", label = "柏林", country_id = "germany", type = "capital", q = -3, r = -2, weight = 2, controller = "germany" },
    { id = "tile_ruhr", label = "鲁尔工业区", country_id = "germany", type = "industrial", q = -4, r = -1, weight = 1, controller = "germany" },
    { id = "tile_paris", label = "巴黎", country_id = "france", type = "capital", q = -5, r = 0, weight = 2, controller = "france" },
    { id = "tile_london", label = "伦敦", country_id = "britain", type = "capital", q = -6, r = -1, weight = 2, controller = "britain" },
    { id = "tile_rome", label = "罗马", country_id = "italy", type = "capital", q = -2, r = 2, weight = 2, controller = "italy" },
    { id = "tile_istanbul", label = "君士坦丁堡", country_id = "ottoman", type = "port", q = 3, r = 1, weight = 2, controller = "ottoman" },
    { id = "tile_moscow", label = "莫斯科", country_id = "russia", type = "capital", q = 4, r = -3, weight = 2, controller = "russia" },
    { id = "tile_adriatic_port", label = "亚得里亚港口", country_id = "adriatic", type = "port", q = -1, r = 3, weight = 1, controller = "contested" },
    { id = "tile_balkan_pass", label = "巴尔干山口", country_id = "balkans", type = "strategic", q = 2, r = 1, weight = 1, controller = "contested" },
}

function MapTilesData.CreateInitialTiles()
    local tiles = {}
    for _, t in ipairs(MapTilesData.TEMPLATES) do
        table.insert(tiles, copyTile(t))
    end
    MapTilesData.RebuildNeighbors(tiles)
    return tiles
end

function MapTilesData.RebuildNeighbors(tiles)
    local byCoord = {}
    for _, t in ipairs(tiles or {}) do
        byCoord[(t.q or 0) .. "," .. (t.r or 0)] = t
        t.neighbors = {}
    end
    local dirs = {
        { 1, 0 }, { 1, -1 }, { 0, -1 },
        { -1, 0 }, { -1, 1 }, { 0, 1 },
    }
    for _, t in ipairs(tiles or {}) do
        for _, d in ipairs(dirs) do
            local n = byCoord[((t.q or 0) + d[1]) .. "," .. ((t.r or 0) + d[2])]
            if n then table.insert(t.neighbors, n.id) end
        end
    end
end

function MapTilesData.EnsureState(state)
    if not state.map_tiles or #state.map_tiles == 0 then
        state.map_tiles = MapTilesData.CreateInitialTiles()
        return true
    end
    MapTilesData.RebuildNeighbors(state.map_tiles)
    for _, t in ipairs(state.map_tiles) do
        t.weight = t.weight or 1
        t.controller = t.controller or "contested"
    end
    return false
end

function MapTilesData.GetTile(state, tileId)
    for _, t in ipairs((state and state.map_tiles) or {}) do
        if t.id == tileId then return t end
    end
    return nil
end

local function controllerToPresence(controller)
    if controller == "local_clan" or controller == "foreign_capital" then
        return controller
    end
    return nil
end

function MapTilesData.SyncRegionsFromTiles(state)
    local accum = {}
    for _, tile in ipairs(state.map_tiles or {}) do
        if tile.region_id then
            local a = accum[tile.region_id] or {
                weight = 0,
                player = 0,
                ai = {},
            }
            local w = tile.weight or 1
            a.weight = a.weight + w
            if tile.controller == "player" then
                a.player = a.player + w
            else
                local aiId = controllerToPresence(tile.controller)
                if aiId then
                    a.ai[aiId] = (a.ai[aiId] or 0) + w
                end
            end
            accum[tile.region_id] = a
        end
    end

    for _, region in ipairs(state.regions or {}) do
        local a = accum[region.id]
        if a and a.weight > 0 then
            region.control = math.floor(a.player / a.weight * 100 + 0.5)
            region.ai_presence = region.ai_presence or {}
            for aiId, _ in pairs(region.ai_presence) do
                region.ai_presence[aiId] = math.floor(((a.ai[aiId] or 0) / a.weight) * 100 + 0.5)
            end
        end
    end
end

local function dominantFromRegion(region)
    if not region then return "contested" end
    if (region.control or 0) >= 50 then return "player" end
    local maxId, maxVal = nil, 0
    for aiId, v in pairs(region.ai_presence or {}) do
        if v > maxVal then
            maxId, maxVal = aiId, v
        end
    end
    if maxId and maxVal >= 40 then return maxId end
    return "contested"
end

function MapTilesData.SyncTilesFromRegions(state)
    if not state.map_tiles then return end
    local byRegion = {}
    for _, r in ipairs(state.regions or {}) do
        byRegion[r.id] = r
    end
    for _, tile in ipairs(state.map_tiles) do
        if tile.region_id and byRegion[tile.region_id] then
            tile.controller = dominantFromRegion(byRegion[tile.region_id])
        end
    end
end

return MapTilesData
