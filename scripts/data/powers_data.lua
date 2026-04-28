-- ============================================================================
-- 大国数据（大国博弈系统 Phase 2）
-- 大国定义、历史基准线（每年 military/economy/war_fatigue）、征服目标、阵营
-- ============================================================================

local PowersData = {}

-- ============================================================================
-- 漂移常量
-- ============================================================================
PowersData.DRIFT_RATE = 0.10  -- 每季缩小差距 10%

-- ============================================================================
-- 大国定义模板
-- active_years: {start, end} 活跃年份范围
-- initial: 初始三围 {mil, eco, fat}
-- faction_by_era: 各章阵营标签
-- war_goals_by_era: 各章征服目标队列（按优先级排序）
-- local_proxy: 在萨拉热窝的代理势力 id
-- successor: 消亡后的继承国 {year, new_id, new_label}
-- ============================================================================
local POWERS = {
    -- ── 奥匈帝国 ──
    {
        id = "austria_hungary",
        label = "奥匈帝国",
        active_years = { 1904, 1918 },
        initial = { military = 60, economy = 65, war_fatigue = 0 },
        faction_by_era = {
            [1] = "central_powers",
            [2] = "central_powers",
        },
        war_goals_by_era = {
            [2] = { "serbia", "montenegro", "romania" },
        },
        local_proxy = "local_clan",
        successor = { year = 1919, new_id = "yugoslavia", new_label = "南斯拉夫王国" },
    },

    -- ── 德意志帝国 ──
    {
        id = "germany",
        label = "德意志帝国",
        active_years = { 1904, 1918 },
        initial = { military = 70, economy = 80, war_fatigue = 0 },
        faction_by_era = {
            [1] = "central_powers",
            [2] = "central_powers",
        },
        war_goals_by_era = {
            [2] = { "lowlands", "france", "russia" },
        },
        local_proxy = nil,
        successor = { year = 1919, new_id = "weimar_germany", new_label = "魏玛共和国" },
    },

    -- ── 俄罗斯帝国 ──
    {
        id = "russia",
        label = "俄罗斯帝国",
        active_years = { 1904, 1917 },
        initial = { military = 65, economy = 50, war_fatigue = 0 },
        faction_by_era = {
            [1] = "entente",
            [2] = "entente",
        },
        war_goals_by_era = {
            [2] = { "austria_hungary", "ottoman" },
        },
        local_proxy = nil,
        successor = { year = 1918, new_id = "soviet_union", new_label = "苏联" },
    },

    -- ── 奥斯曼帝国 ──
    {
        id = "ottoman",
        label = "奥斯曼帝国",
        active_years = { 1904, 1918 },
        initial = { military = 45, economy = 35, war_fatigue = 0 },
        faction_by_era = {
            [1] = "neutral",
            [2] = "central_powers",
        },
        war_goals_by_era = {
            [2] = { "greece" },
        },
        local_proxy = nil,
        successor = { year = 1919, new_id = "turkey", new_label = "土耳其" },
    },

    -- ── 大英帝国 ──
    {
        id = "britain",
        label = "大英帝国",
        active_years = { 1904, 1955 },
        initial = { military = 75, economy = 90, war_fatigue = 0 },
        faction_by_era = {
            [1] = "entente",
            [2] = "entente",
            [3] = "western",
            [4] = "allies",
            [5] = "western",
        },
        war_goals_by_era = {},  -- 防守方，无主动征服
        local_proxy = nil,
    },

    -- ── 法兰西 ──
    {
        id = "france",
        label = "法兰西",
        active_years = { 1904, 1955 },
        initial = { military = 65, economy = 75, war_fatigue = 0 },
        faction_by_era = {
            [1] = "entente",
            [2] = "entente",
            [3] = "western",
            [4] = "allies",
            [5] = "western",
        },
        war_goals_by_era = {},
        local_proxy = nil,
    },

    -- ── 意大利 ──
    {
        id = "italy",
        label = "意大利",
        active_years = { 1904, 1955 },
        initial = { military = 50, economy = 55, war_fatigue = 0 },
        faction_by_era = {
            [1] = "neutral",
            [2] = "entente",      -- 1915年加入协约国
            [3] = "neutral",
            [4] = "axis",         -- 轴心国（至1943）
            [5] = "western",
        },
        war_goals_by_era = {
            [4] = { "greece" },
        },
        local_proxy = nil,
    },

    -- ── 塞尔维亚 / 南斯拉夫 ──
    {
        id = "serbia",
        label = "塞尔维亚",
        active_years = { 1904, 1918 },
        initial = { military = 55, economy = 30, war_fatigue = 0 },
        faction_by_era = {
            [1] = "entente",
            [2] = "entente",
        },
        war_goals_by_era = {},
        local_proxy = "foreign_capital",
        successor = { year = 1919, new_id = "yugoslavia", new_label = "南斯拉夫王国" },
    },

    -- ── 纳粹德国（1933 登场）──
    {
        id = "nazi_germany",
        label = "纳粹德国",
        active_years = { 1933, 1945 },
        initial = { military = 50, economy = 55, war_fatigue = 0 },
        faction_by_era = {
            [3] = "axis",
            [4] = "axis",
        },
        war_goals_by_era = {
            [3] = {},  -- 和平扩张（外交手段）
            [4] = { "denmark", "lowlands", "france", "yugoslavia", "greece", "russia" },
        },
        local_proxy = "foreign_capital",
    },

    -- ── 南斯拉夫王国（1919 登场）──
    {
        id = "yugoslavia",
        label = "南斯拉夫王国",
        active_years = { 1919, 1941 },
        initial = { military = 40, economy = 35, war_fatigue = 0 },
        faction_by_era = {
            [3] = "neutral",
            [4] = "allies",
        },
        war_goals_by_era = {},
        local_proxy = "local_clan",
    },

    -- ── 苏联（1918 登场）──
    {
        id = "soviet_union",
        label = "苏联",
        active_years = { 1918, 1955 },
        initial = { military = 30, economy = 25, war_fatigue = 20 },
        faction_by_era = {
            [2] = "neutral",    -- 退出一战
            [3] = "comintern",
            [4] = "allies",
            [5] = "comintern",
        },
        war_goals_by_era = {
            [4] = { "romania", "bulgaria", "germany" },  -- 反攻
        },
        local_proxy = nil,
    },

    -- ── 铁托南斯拉夫（1944 登场）──
    {
        id = "tito_yugoslavia",
        label = "铁托南斯拉夫",
        active_years = { 1944, 1955 },
        initial = { military = 45, economy = 25, war_fatigue = 30 },
        faction_by_era = {
            [4] = "allies",
            [5] = "non_aligned",
        },
        war_goals_by_era = {},
        local_proxy = "local_clan",
    },

    -- ── 魏玛共和国/战后德国 ──
    {
        id = "weimar_germany",
        label = "魏玛共和国",
        active_years = { 1919, 1932 },
        initial = { military = 20, economy = 30, war_fatigue = 60 },
        faction_by_era = {
            [3] = "neutral",
        },
        war_goals_by_era = {},
        local_proxy = nil,
        successor = { year = 1933, new_id = "nazi_germany", new_label = "纳粹德国" },
    },

    -- ── 土耳其 ──
    {
        id = "turkey",
        label = "土耳其",
        active_years = { 1919, 1955 },
        initial = { military = 35, economy = 30, war_fatigue = 40 },
        faction_by_era = {
            [3] = "neutral",
            [4] = "neutral",
            [5] = "western",
        },
        war_goals_by_era = {},
        local_proxy = nil,
    },
}

-- ============================================================================
-- 历史基准线
-- 格式: BASELINES[power_id][year] = { military, economy, war_fatigue }
-- 未列出的年份由前后最近年份线性插值
-- ============================================================================
local BASELINES = {
    -- ── 奥匈帝国 ──
    austria_hungary = {
        [1904] = { 60, 65,  0 },
        [1910] = { 65, 68,  0 },
        [1913] = { 70, 65,  5 },
        [1914] = { 75, 60, 10 },
        [1916] = { 65, 45, 35 },
        [1917] = { 45, 30, 55 },
        [1918] = { 15, 15, 85 },  -- 崩溃
    },

    -- ── 德意志帝国 ──
    germany = {
        [1904] = { 65, 80,  0 },
        [1910] = { 70, 85,  0 },
        [1913] = { 80, 82,  3 },
        [1914] = { 90, 78, 10 },
        [1916] = { 85, 60, 30 },
        [1917] = { 75, 45, 50 },
        [1918] = { 30, 25, 80 },  -- 投降
    },

    -- ── 俄罗斯帝国 ──
    russia = {
        [1904] = { 65, 50,  0 },
        [1910] = { 60, 55,  0 },
        [1913] = { 65, 52,  5 },
        [1914] = { 70, 48, 10 },
        [1916] = { 55, 35, 40 },
        [1917] = { 25, 20, 75 },  -- 革命
    },

    -- ── 奥斯曼帝国 ──
    ottoman = {
        [1904] = { 45, 35,  0 },
        [1910] = { 40, 32,  5 },
        [1914] = { 50, 30, 10 },
        [1916] = { 40, 22, 40 },
        [1918] = { 15, 10, 70 },
    },

    -- ── 大英帝国 ──
    britain = {
        [1904] = { 75, 90,  0 },
        [1910] = { 78, 88,  0 },
        [1914] = { 80, 85,  5 },
        [1916] = { 82, 75, 20 },
        [1918] = { 70, 65, 40 },
        [1920] = { 55, 70, 15 },
        [1930] = { 45, 65,  5 },
        [1938] = { 55, 60,  0 },
        [1940] = { 70, 55, 10 },
        [1943] = { 75, 60, 25 },
        [1945] = { 65, 55, 35 },
        [1948] = { 50, 55, 10 },
        [1955] = { 45, 50,  5 },
    },

    -- ── 法兰西 ──
    france = {
        [1904] = { 65, 75,  0 },
        [1910] = { 68, 72,  0 },
        [1914] = { 75, 68,  5 },
        [1916] = { 70, 55, 30 },
        [1918] = { 55, 50, 45 },
        [1920] = { 45, 55, 15 },
        [1930] = { 40, 60,  5 },
        [1938] = { 50, 55,  0 },
        [1940] = { 35, 30, 50 },  -- 沦陷
        [1944] = { 30, 25, 35 },  -- 解放中
        [1945] = { 40, 35, 20 },
        [1950] = { 45, 50,  5 },
        [1955] = { 45, 55,  5 },
    },

    -- ── 意大利 ──
    italy = {
        [1904] = { 50, 55,  0 },
        [1910] = { 48, 55,  0 },
        [1915] = { 55, 50,  5 },
        [1917] = { 45, 40, 30 },
        [1918] = { 40, 38, 40 },
        [1920] = { 35, 45, 10 },
        [1930] = { 45, 50,  5 },
        [1938] = { 55, 48,  0 },
        [1940] = { 50, 42, 10 },
        [1942] = { 40, 32, 35 },
        [1943] = { 20, 25, 60 },  -- 投降
        [1945] = { 25, 25, 30 },
        [1950] = { 30, 45,  5 },
        [1955] = { 30, 50,  5 },
    },

    -- ── 塞尔维亚 ──
    serbia = {
        [1904] = { 55, 30,  0 },
        [1910] = { 58, 32,  0 },
        [1914] = { 65, 28,  5 },
        [1915] = { 55, 20, 25 },
        [1916] = { 30, 12, 50 },  -- 陷落
        [1918] = { 20, 10, 60 },
    },

    -- ── 纳粹德国 ──
    nazi_germany = {
        [1933] = { 50, 55,  0 },
        [1936] = { 70, 65,  0 },
        [1938] = { 80, 70,  0 },
        [1939] = { 90, 75,  5 },
        [1940] = { 92, 72, 10 },
        [1941] = { 90, 68, 15 },
        [1942] = { 85, 60, 25 },
        [1943] = { 70, 50, 45 },  -- 斯大林格勒
        [1944] = { 55, 35, 60 },
        [1945] = {  5,  5, 95 },  -- 投降
    },

    -- ── 南斯拉夫王国 ──
    yugoslavia = {
        [1919] = { 40, 35,  0 },
        [1925] = { 38, 40,  0 },
        [1930] = { 35, 42,  0 },
        [1935] = { 38, 40,  0 },
        [1940] = { 40, 38,  5 },
        [1941] = { 25, 20, 40 },  -- 被入侵
    },

    -- ── 苏联 ──
    soviet_union = {
        [1918] = { 30, 25, 20 },
        [1920] = { 40, 20, 15 },
        [1925] = { 50, 30,  5 },
        [1930] = { 55, 40,  0 },
        [1935] = { 65, 50,  0 },
        [1939] = { 70, 55,  0 },
        [1941] = { 65, 50, 15 },  -- 巴巴罗萨
        [1942] = { 70, 52, 25 },
        [1943] = { 80, 55, 20 },  -- 反攻
        [1944] = { 85, 58, 25 },
        [1945] = { 90, 55, 30 },
        [1948] = { 80, 55, 10 },
        [1955] = { 75, 60,  5 },
    },

    -- ── 铁托南斯拉夫 ──
    tito_yugoslavia = {
        [1944] = { 45, 25, 30 },
        [1945] = { 50, 30, 15 },
        [1948] = { 45, 35,  5 },
        [1950] = { 40, 40,  0 },
        [1955] = { 40, 45,  0 },
    },

    -- ── 魏玛共和国 ──
    weimar_germany = {
        [1919] = { 20, 30, 60 },
        [1922] = { 22, 25, 40 },  -- 超级通胀
        [1925] = { 25, 35, 20 },
        [1929] = { 30, 40, 10 },  -- 大萧条前
        [1931] = { 28, 28, 15 },  -- 大萧条
        [1932] = { 30, 30, 10 },
    },

    -- ── 土耳其 ──
    turkey = {
        [1919] = { 35, 30, 40 },
        [1923] = { 40, 32, 15 },  -- 共和国成立
        [1930] = { 38, 38,  5 },
        [1938] = { 35, 40,  0 },
        [1945] = { 35, 38,  0 },
        [1950] = { 38, 42,  0 },
        [1955] = { 40, 45,  0 },
    },
}

-- ============================================================================
-- 历史征服事件时间线
-- 格式: { year, quarter, attacker, target, action }
-- action: "conquer" = 征服, "liberate" = 解放, "annex" = 和平吞并
-- ============================================================================
PowersData.CONQUEST_TIMELINE = {
    -- ── 第一章 Ch1: 和平期 ──
    -- 无征服事件

    -- ── 第二章 Ch2: 一战 ──
    { year = 1914, quarter = 4, attacker = "germany",         target = "lowlands",    action = "conquer" },
    { year = 1915, quarter = 2, attacker = "austria_hungary",  target = "montenegro",  action = "conquer" },
    { year = 1916, quarter = 1, attacker = "austria_hungary",  target = "serbia",      action = "conquer" },
    { year = 1916, quarter = 3, attacker = "austria_hungary",  target = "romania",     action = "conquer" },
    { year = 1917, quarter = 3, attacker = "finland",          target = "finland",     action = "liberate" },  -- 芬兰独立
    { year = 1918, quarter = 3, attacker = "entente",          target = "lowlands",    action = "liberate" },
    { year = 1918, quarter = 3, attacker = "entente",          target = "serbia",      action = "liberate" },
    { year = 1918, quarter = 3, attacker = "entente",          target = "montenegro",  action = "liberate" },
    { year = 1918, quarter = 4, attacker = "entente",          target = "romania",     action = "liberate" },

    -- ── 第三章 Ch3: 和平扩张 ──
    { year = 1938, quarter = 1, attacker = "nazi_germany",     target = "austria_hungary", action = "annex" },  -- 德奥合并

    -- ── 第四章 Ch4: 二战 ──
    { year = 1940, quarter = 1, attacker = "nazi_germany",     target = "denmark",     action = "conquer" },
    { year = 1940, quarter = 1, attacker = "nazi_germany",     target = "lowlands",    action = "conquer" },
    { year = 1940, quarter = 3, attacker = "nazi_germany",     target = "france",      action = "conquer" },
    { year = 1941, quarter = 2, attacker = "nazi_germany",     target = "yugoslavia",  action = "conquer" },  -- 南斯拉夫陷落
    { year = 1941, quarter = 3, attacker = "nazi_germany",     target = "greece",      action = "conquer" },
    { year = 1941, quarter = 3, attacker = "nazi_germany",     target = "serbia",      action = "conquer" },  -- 占领继承国领土
    { year = 1941, quarter = 3, attacker = "nazi_germany",     target = "montenegro",  action = "conquer" },
    { year = 1943, quarter = 3, attacker = "allies",           target = "italy",       action = "liberate" },  -- 意大利投降
    { year = 1944, quarter = 2, attacker = "allies",           target = "france",      action = "liberate" },  -- 诺曼底
    { year = 1944, quarter = 3, attacker = "soviet_union",     target = "romania",     action = "liberate" },
    { year = 1944, quarter = 3, attacker = "soviet_union",     target = "bulgaria",    action = "liberate" },
    { year = 1944, quarter = 4, attacker = "tito_yugoslavia",  target = "yugoslavia",  action = "liberate" },  -- 游击队解放
    { year = 1944, quarter = 4, attacker = "tito_yugoslavia",  target = "serbia",      action = "liberate" },
    { year = 1944, quarter = 4, attacker = "tito_yugoslavia",  target = "montenegro",  action = "liberate" },
    { year = 1945, quarter = 1, attacker = "allies",           target = "greece",      action = "liberate" },
    { year = 1945, quarter = 1, attacker = "allies",           target = "lowlands",    action = "liberate" },
    { year = 1945, quarter = 1, attacker = "allies",           target = "denmark",     action = "liberate" },
    { year = 1945, quarter = 2, attacker = "allies",           target = "nazi_germany",action = "liberate" },  -- 德国投降
}

-- ============================================================================
-- 大国消亡/继承事件
-- 格式: { year, quarter, old_id, changes }
-- changes: 需要对 europe 和 powers 状态执行的操作列表
-- ============================================================================
PowersData.SUCCESSION_EVENTS = {
    -- 俄罗斯 → 苏联 (1917 Q3 革命后)
    {
        year = 1918, quarter = 1,
        old_id = "russia",
        new_id = "soviet_union",
        -- 保留俄罗斯领土（除芬兰外），主权标记更新为 soviet_union
        rename_sovereign = true,
    },
    -- 奥匈帝国 → 南斯拉夫王国 (1918 Q4 崩溃)
    {
        year = 1919, quarter = 1,
        old_id = "austria_hungary",
        new_id = "yugoslavia",
        -- 奥匈本土恢复自治，塞尔维亚区域由南斯拉夫继承
        restore_original = true,  -- 原奥匈领土恢复原主权
    },
    -- 奥斯曼 → 土耳其
    {
        year = 1919, quarter = 1,
        old_id = "ottoman",
        new_id = "turkey",
        rename_sovereign = true,
    },
    -- 塞尔维亚 → 并入南斯拉夫
    {
        year = 1919, quarter = 1,
        old_id = "serbia",
        new_id = "yugoslavia",
        absorb = true,  -- 塞尔维亚被并入南斯拉夫
    },
    -- 魏玛共和国 → 纳粹德国
    {
        year = 1933, quarter = 1,
        old_id = "weimar_germany",
        new_id = "nazi_germany",
        rename_sovereign = true,
    },
    -- 南斯拉夫王国灭亡（被纳粹征服后）
    {
        year = 1941, quarter = 2,
        old_id = "yugoslavia",
        new_id = nil,  -- 不产生继承国，领土被瓜分
        dissolve = true,
    },
    -- 铁托南斯拉夫继承
    {
        year = 1944, quarter = 4,
        old_id = nil,
        new_id = "tito_yugoslavia",
        create_fresh = true,  -- 直接创建新大国
    },
}

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 获取所有大国定义
---@return table[] powers
function PowersData.GetAllPowers()
    return POWERS
end

--- 按 id 获取大国定义
---@param powerId string
---@return table|nil
function PowersData.GetPowerById(powerId)
    for _, p in ipairs(POWERS) do
        if p.id == powerId then return p end
    end
    return nil
end

--- 获取指定大国在指定年份的历史基准线 {mil, eco, fat}
--- 使用线性插值填充未定义年份
---@param powerId string
---@param year number
---@return table|nil {military, economy, war_fatigue}
function PowersData.GetBaseline(powerId, year)
    local bl = BASELINES[powerId]
    if not bl then return nil end

    -- 收集并排序已定义的年份
    local years = {}
    for y, _ in pairs(bl) do
        table.insert(years, y)
    end
    table.sort(years)

    if #years == 0 then return nil end

    -- 边界情况
    if year <= years[1] then
        local v = bl[years[1]]
        return { military = v[1], economy = v[2], war_fatigue = v[3] }
    end
    if year >= years[#years] then
        local v = bl[years[#years]]
        return { military = v[1], economy = v[2], war_fatigue = v[3] }
    end

    -- 线性插值
    for i = 1, #years - 1 do
        if year >= years[i] and year <= years[i + 1] then
            local y0, y1 = years[i], years[i + 1]
            local v0, v1 = bl[y0], bl[y1]
            local t = (year - y0) / (y1 - y0)
            return {
                military    = math.floor(v0[1] + (v1[1] - v0[1]) * t + 0.5),
                economy     = math.floor(v0[2] + (v1[2] - v0[2]) * t + 0.5),
                war_fatigue = math.floor(v0[3] + (v1[3] - v0[3]) * t + 0.5),
            }
        end
    end

    return nil
end

--- 获取指定年份+季度应发生的征服事件列表
---@param year number
---@param quarter number
---@return table[]
function PowersData.GetConquestEvents(year, quarter)
    local result = {}
    for _, ev in ipairs(PowersData.CONQUEST_TIMELINE) do
        if ev.year == year and ev.quarter == quarter then
            table.insert(result, ev)
        end
    end
    return result
end

--- 获取指定年份+季度应发生的继承事件列表
---@param year number
---@param quarter number
---@return table[]
function PowersData.GetSuccessionEvents(year, quarter)
    local result = {}
    for _, ev in ipairs(PowersData.SUCCESSION_EVENTS) do
        if ev.year == year and ev.quarter == quarter then
            table.insert(result, ev)
        end
    end
    return result
end

--- 获取某章（era_id）中该大国的阵营
---@param powerId string
---@param eraId number
---@return string faction
function PowersData.GetFaction(powerId, eraId)
    local p = PowersData.GetPowerById(powerId)
    if not p then return "neutral" end
    return p.faction_by_era[eraId] or "neutral"
end

--- 获取某章中该大国的征服目标队列
---@param powerId string
---@param eraId number
---@return table goals
function PowersData.GetWarGoals(powerId, eraId)
    local p = PowersData.GetPowerById(powerId)
    if not p or not p.war_goals_by_era then return {} end
    return p.war_goals_by_era[eraId] or {}
end

return PowersData
