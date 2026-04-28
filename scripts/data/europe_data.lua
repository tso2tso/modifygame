-- ============================================================================
-- 欧洲国家数据（大国博弈系统 Phase 1）
-- 17 个欧洲国家/地区的领土状态、主权归属、邻接关系
-- ============================================================================

local EuropeData = {}

-- ============================================================================
-- 国家定义
-- ============================================================================

--- 完整国家列表（与 ui_map_widget.lua EUROPE_REGIONS 的 id 一一对应）
local COUNTRIES = {
    -- ── 大国 ──
    {
        id = "britain",
        label = "大英帝国",
        tier = "major",            -- major=大国 | minor=小国 | neutral=中立
        original = "britain",
        sovereign = "britain",
        stability = 85,
        resistance = 0,
        adjacency = { "france", "lowlands", "scandinavia" },
    },
    {
        id = "france",
        label = "法兰西",
        tier = "major",
        original = "france",
        sovereign = "france",
        stability = 75,
        resistance = 0,
        adjacency = { "britain", "germany", "lowlands", "switzerland", "italy", "iberia" },
    },
    {
        id = "germany",
        label = "德意志帝国",
        tier = "major",
        original = "germany",
        sovereign = "germany",
        stability = 80,
        resistance = 0,
        adjacency = { "france", "lowlands", "denmark", "austria_hungary", "russia", "switzerland" },
    },
    {
        id = "russia",
        label = "俄罗斯帝国",
        tier = "major",
        original = "russia",
        sovereign = "russia",
        stability = 60,
        resistance = 0,
        adjacency = { "finland", "scandinavia", "germany", "austria_hungary", "romania", "ottoman" },
    },
    {
        id = "austria_hungary",
        label = "奥匈帝国",
        tier = "major",
        original = "austria_hungary",
        sovereign = "austria_hungary",
        stability = 55,
        resistance = 0,
        adjacency = { "germany", "italy", "serbia", "romania", "russia", "switzerland", "montenegro" },
    },
    {
        id = "ottoman",
        label = "奥斯曼帝国",
        tier = "major",
        original = "ottoman",
        sovereign = "ottoman",
        stability = 45,
        resistance = 0,
        adjacency = { "greece", "bulgaria", "romania", "russia" },
    },

    -- ── 中等国家 ──
    {
        id = "italy",
        label = "意大利",
        tier = "medium",
        original = "italy",
        sovereign = "italy",
        stability = 65,
        resistance = 0,
        adjacency = { "france", "switzerland", "austria_hungary" },
    },

    -- ── 小国 ──
    {
        id = "serbia",
        label = "塞尔维亚",
        tier = "minor",
        original = "serbia",
        sovereign = "serbia",
        stability = 70,
        resistance = 0,
        adjacency = { "austria_hungary", "montenegro", "bulgaria", "romania", "ottoman" },
    },
    {
        id = "romania",
        label = "罗马尼亚",
        tier = "minor",
        original = "romania",
        sovereign = "romania",
        stability = 55,
        resistance = 0,
        adjacency = { "austria_hungary", "serbia", "bulgaria", "russia", "ottoman" },
    },
    {
        id = "bulgaria",
        label = "保加利亚",
        tier = "minor",
        original = "bulgaria",
        sovereign = "bulgaria",
        stability = 60,
        resistance = 0,
        adjacency = { "serbia", "romania", "ottoman", "greece" },
    },
    {
        id = "greece",
        label = "希腊",
        tier = "minor",
        original = "greece",
        sovereign = "greece",
        stability = 55,
        resistance = 0,
        adjacency = { "ottoman", "bulgaria" },
    },
    {
        id = "montenegro",
        label = "黑山",
        tier = "minor",
        original = "montenegro",
        sovereign = "montenegro",
        stability = 65,
        resistance = 0,
        adjacency = { "austria_hungary", "serbia" },
    },
    {
        id = "lowlands",
        label = "低地国家",
        tier = "minor",
        original = "lowlands",
        sovereign = "lowlands",
        stability = 70,
        resistance = 0,
        adjacency = { "britain", "france", "germany" },
    },
    {
        id = "denmark",
        label = "丹麦",
        tier = "minor",
        original = "denmark",
        sovereign = "denmark",
        stability = 75,
        resistance = 0,
        adjacency = { "germany", "scandinavia" },
    },

    -- ── 中立国 ──
    {
        id = "scandinavia",
        label = "瑞典-挪威",
        tier = "neutral",
        original = "scandinavia",
        sovereign = "scandinavia",
        stability = 85,
        resistance = 0,
        adjacency = { "denmark", "finland", "russia", "britain" },
    },
    {
        id = "finland",
        label = "芬兰",
        tier = "minor",
        original = "finland",
        sovereign = "russia",     -- 1907年：俄罗斯自治大公国
        stability = 60,
        resistance = 30,          -- 对俄罗斯统治有一定不满
        adjacency = { "scandinavia", "russia" },
    },
    {
        id = "switzerland",
        label = "瑞士",
        tier = "neutral",
        original = "switzerland",
        sovereign = "switzerland",
        stability = 95,
        resistance = 0,
        adjacency = { "france", "germany", "austria_hungary", "italy" },
    },
    {
        id = "iberia",
        label = "西班牙",
        tier = "neutral",
        original = "iberia",
        sovereign = "iberia",
        stability = 55,
        resistance = 0,
        adjacency = { "france" },
    },
}

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 创建欧洲初始状态（深拷贝，每局游戏独立）
---@return table<string, table> europeState  以国家 id 为 key 的字典
function EuropeData.CreateInitial()
    local result = {}
    for _, country in ipairs(COUNTRIES) do
        local c = {}
        for k, v in pairs(country) do
            if type(v) == "table" then
                local t = {}
                for i, item in ipairs(v) do t[i] = item end
                c[k] = t
            else
                c[k] = v
            end
        end
        result[c.id] = c
    end
    return result
end

--- 检查两国是否邻接
---@param europeState table
---@param countryA string
---@param countryB string
---@return boolean
function EuropeData.AreAdjacent(europeState, countryA, countryB)
    local a = europeState[countryA]
    if not a or not a.adjacency then return false end
    for _, adj in ipairs(a.adjacency) do
        if adj == countryB then return true end
    end
    return false
end

--- 获取某个大国当前控制的所有国家 id 列表
---@param europeState table
---@param sovereignId string
---@return table idList
function EuropeData.GetControlledBy(europeState, sovereignId)
    local result = {}
    for id, c in pairs(europeState) do
        if c.sovereign == sovereignId then
            table.insert(result, id)
        end
    end
    return result
end

--- 变更主权
---@param europeState table
---@param countryId string
---@param newSovereign string
function EuropeData.ChangeSovereignty(europeState, countryId, newSovereign)
    local c = europeState[countryId]
    if not c then return end
    local oldSovereign = c.sovereign
    c.sovereign = newSovereign
    -- 被占领时：抵抗值设为原 stability
    if newSovereign ~= c.original then
        c.resistance = math.max(c.resistance, c.stability * 0.7)
    else
        c.resistance = 0  -- 解放后重置
    end
end

--- 判断某国是否处于被占领状态
---@param europeState table
---@param countryId string
---@return boolean
function EuropeData.IsOccupied(europeState, countryId)
    local c = europeState[countryId]
    if not c then return false end
    return c.sovereign ~= c.original
end

--- 获取所有国家 id 列表
---@return table idList
function EuropeData.GetAllIds()
    local ids = {}
    for _, country in ipairs(COUNTRIES) do
        table.insert(ids, country.id)
    end
    return ids
end

return EuropeData
