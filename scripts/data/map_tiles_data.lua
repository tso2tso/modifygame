-- ============================================================================
-- 宏观六边形地图模块数据 v2 — Civ6 风格 Hex 网格
-- 说明：
-- - 使用偏移坐标（even-q flat-top）六边形网格
-- - ~95 个 Hex 覆盖全欧洲 18 个国家
-- - 波黑 8 个 tile 中 3 个关联现有 region（经济结算层）
-- - 其余国家 tile 为背景/外交层（不参与经济结算）
-- ============================================================================

local MapTilesData = {}

-- ============================================================================
-- Hex 网格常量（flat-top 六边形）
-- ============================================================================

MapTilesData.HEX_SIZE    = 0.034                          -- hex 半径（世界坐标）
MapTilesData.ORIGIN_X    = 0.12                            -- 网格原点 X
MapTilesData.ORIGIN_Y    = 0.08                            -- 网格原点 Y
MapTilesData.COL_SPACING = MapTilesData.HEX_SIZE * 1.5     -- 列间距 ≈ 0.051
MapTilesData.ROW_SPACING = MapTilesData.HEX_SIZE * math.sqrt(3) -- 行间距 ≈ 0.0589

--- 获取 hex 中心的世界坐标
---@param q number 列（偏移坐标）
---@param r number 行（偏移坐标）
---@return number x, number y
function MapTilesData.GetHexCenter(q, r)
    local x = MapTilesData.ORIGIN_X + MapTilesData.COL_SPACING * q
    local y = MapTilesData.ORIGIN_Y + MapTilesData.ROW_SPACING * (r + 0.5 * (q % 2))
    return x, y
end

--- 获取 hex 六个顶点（flat-top，用于渲染）
---@param q number
---@param r number
---@return number[] corners {x1,y1, x2,y2, ..., x6,y6}
function MapTilesData.GetHexCorners(q, r)
    local cx, cy = MapTilesData.GetHexCenter(q, r)
    local s = MapTilesData.HEX_SIZE
    local corners = {}
    for i = 0, 5 do
        local angle = math.pi / 3 * i  -- flat-top: 0°, 60°, 120°, 180°, 240°, 300°
        corners[#corners + 1] = cx + s * math.cos(angle)
        corners[#corners + 1] = cy + s * math.sin(angle)
    end
    return corners
end

--- 判断世界坐标点是否在某 hex 内
---@param wx number 世界坐标 X
---@param wy number 世界坐标 Y
---@param q number
---@param r number
---@return boolean
function MapTilesData.HitHex(wx, wy, q, r)
    local cx, cy = MapTilesData.GetHexCenter(q, r)
    local dx = math.abs(wx - cx)
    local dy = math.abs(wy - cy)
    local s = MapTilesData.HEX_SIZE
    -- 快速排除
    if dx > s or dy > s * 0.866 then return false end
    -- 精确判断（flat-top hex）
    return (s * 0.866 - dy) * s >= (dx - s * 0.5) * s * 1.732
end

-- ============================================================================
-- 深拷贝工具
-- ============================================================================

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

-- ============================================================================
-- Hex Tile 模板（~95 个 tile）
-- 坐标系：even-q flat-top offset grid
-- q = 列（东→大），r = 行（南→大）
-- 地理映射：col 0 ≈ 西欧边缘, col 14 ≈ 东欧/俄罗斯
--           row 1 ≈ 北欧, row 13 ≈ 地中海
-- ============================================================================

MapTilesData.TEMPLATES = {

    -- ═══════════════════════════════════════════════════════════
    -- 波黑 Bosnia (8 tiles) — 核心可玩区域，3 个关联 region
    -- ═══════════════════════════════════════════════════════════
    { id = "bos_sarajevo",  label = "萨拉热窝",     country_id = "bosnia", region_id = "capital_city",    type = "capital",    q = 8,  r = 10, weight = 2, controller = "foreign_capital", terrain = "urban" },
    { id = "bos_mine",      label = "巴科维奇矿区", country_id = "bosnia", region_id = "mine_district",   type = "mine",       q = 7,  r = 11, weight = 2, controller = "player",          terrain = "mountain" },
    { id = "bos_zenica",    label = "泽尼察工业区", country_id = "bosnia", region_id = "industrial_town", type = "industrial", q = 8,  r = 11, weight = 2, controller = "local_clan",      terrain = "hills" },
    { id = "bos_banja",     label = "巴尼亚卢卡",   country_id = "bosnia", region_id = "capital_city",    type = "cultural",   q = 7,  r = 10, weight = 1, controller = "contested",       terrain = "plains" },
    { id = "bos_drina",     label = "德里纳边境",   country_id = "bosnia", region_id = "capital_city",    type = "border",     q = 9,  r = 10, weight = 1, controller = "contested",       terrain = "hills" },
    { id = "bos_east",      label = "东波黑",       country_id = "bosnia", region_id = "capital_city",    type = "border",     q = 9,  r = 11, weight = 1, controller = "contested",       terrain = "forest" },
    { id = "bos_herceg_n",  label = "黑塞哥维那北", country_id = "bosnia", region_id = "industrial_town", type = "strategic",  q = 8,  r = 12, weight = 1, controller = "contested",       terrain = "mountain" },
    { id = "bos_herceg_w",  label = "黑塞哥维那西", country_id = "bosnia", region_id = "industrial_town", type = "port",       q = 7,  r = 12, weight = 1, controller = "contested",       terrain = "coast" },

    -- ═══════════════════════════════════════════════════════════
    -- 奥匈帝国 Austria-Hungary (9 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "ah_vienna",     label = "维也纳",       country_id = "austria_hungary", type = "capital",    q = 6,  r = 8,  weight = 2, controller = "austria_hungary", terrain = "urban" },
    { id = "ah_budapest",   label = "布达佩斯",     country_id = "austria_hungary", type = "capital",    q = 8,  r = 8,  weight = 2, controller = "austria_hungary", terrain = "urban" },
    { id = "ah_prague",     label = "布拉格",       country_id = "austria_hungary", type = "industrial", q = 6,  r = 7,  weight = 1, controller = "austria_hungary", terrain = "hills" },
    { id = "ah_tyrol",      label = "蒂罗尔",       country_id = "austria_hungary", type = "strategic",  q = 5,  r = 8,  weight = 1, controller = "austria_hungary", terrain = "mountain" },
    { id = "ah_slavonia",   label = "斯拉沃尼亚",   country_id = "austria_hungary", type = "border",     q = 7,  r = 9,  weight = 1, controller = "austria_hungary", terrain = "plains" },
    { id = "ah_croatia",    label = "克罗地亚",     country_id = "austria_hungary", type = "port",       q = 6,  r = 9,  weight = 1, controller = "austria_hungary", terrain = "coast" },
    { id = "ah_galicia",    label = "加利西亚",     country_id = "austria_hungary", type = "mine",       q = 9,  r = 8,  weight = 1, controller = "austria_hungary", terrain = "plains" },
    { id = "ah_transylv",   label = "特兰西瓦尼亚", country_id = "austria_hungary", type = "mine",       q = 9,  r = 7,  weight = 1, controller = "austria_hungary", terrain = "mountain" },
    { id = "ah_pannonia",   label = "潘诺尼亚",     country_id = "austria_hungary", type = "strategic",  q = 8,  r = 9,  weight = 1, controller = "austria_hungary", terrain = "plains" },

    -- ═══════════════════════════════════════════════════════════
    -- 德意志帝国 Germany (9 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "de_berlin",     label = "柏林",         country_id = "germany", type = "capital",    q = 6,  r = 5,  weight = 2, controller = "germany", terrain = "urban" },
    { id = "de_ruhr",       label = "鲁尔工业区",   country_id = "germany", type = "industrial", q = 5,  r = 6,  weight = 2, controller = "germany", terrain = "urban" },
    { id = "de_hamburg",    label = "汉堡",         country_id = "germany", type = "port",       q = 5,  r = 5,  weight = 1, controller = "germany", terrain = "coast" },
    { id = "de_bavaria",    label = "巴伐利亚",     country_id = "germany", type = "cultural",   q = 6,  r = 6,  weight = 1, controller = "germany", terrain = "hills" },
    { id = "de_saxony",     label = "萨克森",       country_id = "germany", type = "industrial", q = 7,  r = 5,  weight = 1, controller = "germany", terrain = "plains" },
    { id = "de_rhineland",  label = "莱茵兰",       country_id = "germany", type = "cultural",   q = 4,  r = 6,  weight = 1, controller = "germany", terrain = "plains" },
    { id = "de_silesia",    label = "西里西亚",     country_id = "germany", type = "mine",       q = 8,  r = 5,  weight = 1, controller = "germany", terrain = "hills" },
    { id = "de_pomerania",  label = "波美拉尼亚",   country_id = "germany", type = "strategic",  q = 7,  r = 4,  weight = 1, controller = "germany", terrain = "coast" },
    { id = "de_alsace",     label = "阿尔萨斯",     country_id = "germany", type = "border",     q = 5,  r = 7,  weight = 1, controller = "germany", terrain = "hills" },

    -- ═══════════════════════════════════════════════════════════
    -- 法兰西 France (9 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "fr_paris",      label = "巴黎",         country_id = "france", type = "capital",    q = 2,  r = 8,  weight = 2, controller = "france", terrain = "urban" },
    { id = "fr_lyon",       label = "里昂",         country_id = "france", type = "industrial", q = 3,  r = 9,  weight = 1, controller = "france", terrain = "hills" },
    { id = "fr_marseille",  label = "马赛",         country_id = "france", type = "port",       q = 3,  r = 10, weight = 1, controller = "france", terrain = "coast" },
    { id = "fr_normandy",   label = "诺曼底",       country_id = "france", type = "strategic",  q = 2,  r = 7,  weight = 1, controller = "france", terrain = "coast" },
    { id = "fr_bordeaux",   label = "波尔多",       country_id = "france", type = "port",       q = 1,  r = 10, weight = 1, controller = "france", terrain = "coast" },
    { id = "fr_lorraine",   label = "洛林",         country_id = "france", type = "border",     q = 3,  r = 8,  weight = 1, controller = "france", terrain = "plains" },
    { id = "fr_brittany",   label = "布列塔尼",     country_id = "france", type = "port",       q = 1,  r = 9,  weight = 1, controller = "france", terrain = "coast" },
    { id = "fr_picardy",    label = "皮卡第",       country_id = "france", type = "strategic",  q = 3,  r = 7,  weight = 1, controller = "france", terrain = "plains" },
    { id = "fr_provence",   label = "普罗旺斯",     country_id = "france", type = "cultural",   q = 2,  r = 10, weight = 1, controller = "france", terrain = "hills" },

    -- ═══════════════════════════════════════════════════════════
    -- 俄罗斯帝国 Russia (12 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "ru_moscow",     label = "莫斯科",       country_id = "russia", type = "capital",    q = 13, r = 4,  weight = 2, controller = "russia", terrain = "urban" },
    { id = "ru_stpetersbg", label = "圣彼得堡",     country_id = "russia", type = "port",       q = 10, r = 2,  weight = 2, controller = "russia", terrain = "urban" },
    { id = "ru_warsaw",     label = "华沙",         country_id = "russia", type = "industrial", q = 9,  r = 5,  weight = 1, controller = "russia", terrain = "plains" },
    { id = "ru_kiev",       label = "基辅",         country_id = "russia", type = "industrial", q = 12, r = 6,  weight = 1, controller = "russia", terrain = "plains" },
    { id = "ru_minsk",      label = "明斯克",       country_id = "russia", type = "strategic",  q = 10, r = 4,  weight = 1, controller = "russia", terrain = "forest" },
    { id = "ru_baltics",    label = "波罗的海",     country_id = "russia", type = "port",       q = 9,  r = 3,  weight = 1, controller = "russia", terrain = "coast" },
    { id = "ru_finland_bdr",label = "芬兰边区",     country_id = "russia", type = "border",     q = 9,  r = 2,  weight = 1, controller = "russia", terrain = "forest" },
    { id = "ru_odessa",     label = "敖德萨",       country_id = "russia", type = "port",       q = 12, r = 7,  weight = 1, controller = "russia", terrain = "coast" },
    { id = "ru_caucasus",   label = "高加索",       country_id = "russia", type = "mine",       q = 14, r = 6,  weight = 1, controller = "russia", terrain = "mountain" },
    { id = "ru_volga",      label = "伏尔加",       country_id = "russia", type = "mine",       q = 14, r = 4,  weight = 1, controller = "russia", terrain = "steppe" },
    { id = "ru_smolensk",   label = "斯摩棱斯克",   country_id = "russia", type = "strategic",  q = 11, r = 4,  weight = 1, controller = "russia", terrain = "forest" },
    { id = "ru_urals",      label = "乌拉尔",       country_id = "russia", type = "mine",       q = 14, r = 3,  weight = 1, controller = "russia", terrain = "mountain" },

    -- ═══════════════════════════════════════════════════════════
    -- 大英帝国 Britain (4 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "br_london",     label = "伦敦",         country_id = "britain", type = "capital",    q = 2,  r = 6,  weight = 2, controller = "britain", terrain = "urban" },
    { id = "br_manchester", label = "曼彻斯特",     country_id = "britain", type = "industrial", q = 1,  r = 6,  weight = 1, controller = "britain", terrain = "urban" },
    { id = "br_scotland",   label = "苏格兰",       country_id = "britain", type = "mine",       q = 1,  r = 5,  weight = 1, controller = "britain", terrain = "hills" },
    { id = "br_wales",      label = "威尔士",       country_id = "britain", type = "mine",       q = 1,  r = 7,  weight = 1, controller = "britain", terrain = "hills" },

    -- ═══════════════════════════════════════════════════════════
    -- 意大利 Italy (6 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "it_rome",       label = "罗马",         country_id = "italy", type = "capital",    q = 4,  r = 11, weight = 2, controller = "italy", terrain = "urban" },
    { id = "it_milan",      label = "米兰",         country_id = "italy", type = "industrial", q = 4,  r = 10, weight = 1, controller = "italy", terrain = "plains" },
    { id = "it_venice",     label = "威尼斯",       country_id = "italy", type = "port",       q = 5,  r = 10, weight = 1, controller = "italy", terrain = "coast" },
    { id = "it_naples",     label = "那不勒斯",     country_id = "italy", type = "port",       q = 5,  r = 12, weight = 1, controller = "italy", terrain = "coast" },
    { id = "it_tuscany",    label = "托斯卡纳",     country_id = "italy", type = "cultural",   q = 5,  r = 11, weight = 1, controller = "italy", terrain = "hills" },
    { id = "it_sicily",     label = "西西里",       country_id = "italy", type = "port",       q = 5,  r = 13, weight = 1, controller = "italy", terrain = "coast" },

    -- ═══════════════════════════════════════════════════════════
    -- 塞尔维亚 Serbia (4 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "se_belgrade",   label = "贝尔格莱德",   country_id = "serbia", type = "capital",    q = 10, r = 10, weight = 2, controller = "serbia", terrain = "urban" },
    { id = "se_nis",        label = "尼什",         country_id = "serbia", type = "industrial", q = 10, r = 11, weight = 1, controller = "serbia", terrain = "hills" },
    { id = "se_vojvodina",  label = "伏伊伏丁那",   country_id = "serbia", type = "mine",       q = 9,  r = 9,  weight = 1, controller = "serbia", terrain = "plains" },
    { id = "se_kosovo",     label = "科索沃",       country_id = "serbia", type = "strategic",  q = 10, r = 12, weight = 1, controller = "serbia", terrain = "mountain" },

    -- ═══════════════════════════════════════════════════════════
    -- 罗马尼亚 Romania (5 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "ro_bucharest",  label = "布加勒斯特",   country_id = "romania", type = "capital",    q = 11, r = 9,  weight = 2, controller = "romania", terrain = "urban" },
    { id = "ro_wallachia",  label = "瓦拉几亚",     country_id = "romania", type = "mine",       q = 11, r = 8,  weight = 1, controller = "romania", terrain = "plains" },
    { id = "ro_moldova",    label = "摩尔达维亚",   country_id = "romania", type = "strategic",  q = 12, r = 8,  weight = 1, controller = "romania", terrain = "hills" },
    { id = "ro_transylv",   label = "罗马尼亚山区", country_id = "romania", type = "mine",       q = 10, r = 8,  weight = 1, controller = "romania", terrain = "mountain" },
    { id = "ro_dobruja",    label = "多布罗加",     country_id = "romania", type = "port",       q = 12, r = 9,  weight = 1, controller = "romania", terrain = "coast" },

    -- ═══════════════════════════════════════════════════════════
    -- 保加利亚 Bulgaria (3 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "bg_sofia",      label = "索菲亚",       country_id = "bulgaria", type = "capital",    q = 11, r = 11, weight = 2, controller = "bulgaria", terrain = "urban" },
    { id = "bg_plovdiv",    label = "普罗夫迪夫",   country_id = "bulgaria", type = "industrial", q = 11, r = 10, weight = 1, controller = "bulgaria", terrain = "hills" },
    { id = "bg_varna",      label = "瓦尔纳",       country_id = "bulgaria", type = "port",       q = 12, r = 10, weight = 1, controller = "bulgaria", terrain = "coast" },

    -- ═══════════════════════════════════════════════════════════
    -- 希腊 Greece (3 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "gr_athens",     label = "雅典",         country_id = "greece", type = "capital",    q = 9,  r = 13, weight = 2, controller = "greece", terrain = "urban" },
    { id = "gr_thessaly",   label = "色萨利",       country_id = "greece", type = "strategic",  q = 9,  r = 12, weight = 1, controller = "greece", terrain = "mountain" },
    { id = "gr_crete",      label = "克里特",       country_id = "greece", type = "port",       q = 10, r = 14, weight = 1, controller = "greece", terrain = "coast" },

    -- ═══════════════════════════════════════════════════════════
    -- 黑山 Montenegro (2 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "mt_cetinje",    label = "采蒂涅",       country_id = "montenegro", type = "capital",  q = 8,  r = 13, weight = 1, controller = "montenegro", terrain = "mountain" },
    { id = "mt_coast",      label = "黑山海岸",     country_id = "montenegro", type = "port",     q = 7,  r = 13, weight = 1, controller = "montenegro", terrain = "coast" },

    -- ═══════════════════════════════════════════════════════════
    -- 奥斯曼帝国 Ottoman (8 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "ot_istanbul",   label = "君士坦丁堡",   country_id = "ottoman", type = "capital",    q = 12, r = 11, weight = 2, controller = "ottoman", terrain = "urban" },
    { id = "ot_thrace",     label = "色雷斯",       country_id = "ottoman", type = "strategic",  q = 12, r = 12, weight = 1, controller = "ottoman", terrain = "plains" },
    { id = "ot_anatolia_w", label = "安纳托利亚西", country_id = "ottoman", type = "industrial", q = 13, r = 11, weight = 1, controller = "ottoman", terrain = "hills" },
    { id = "ot_anatolia_c", label = "安纳托利亚中", country_id = "ottoman", type = "strategic",  q = 14, r = 10, weight = 1, controller = "ottoman", terrain = "steppe" },
    { id = "ot_smyrna",     label = "士麦那",       country_id = "ottoman", type = "port",       q = 13, r = 12, weight = 1, controller = "ottoman", terrain = "coast" },
    { id = "ot_syria",      label = "叙利亚",       country_id = "ottoman", type = "strategic",  q = 14, r = 12, weight = 1, controller = "ottoman", terrain = "steppe" },
    { id = "ot_adrianople", label = "阿德里安堡",   country_id = "ottoman", type = "border",     q = 11, r = 12, weight = 1, controller = "ottoman", terrain = "plains" },
    { id = "ot_aegean",     label = "爱琴海岸",     country_id = "ottoman", type = "port",       q = 11, r = 13, weight = 1, controller = "ottoman", terrain = "coast" },

    -- ═══════════════════════════════════════════════════════════
    -- 低地国家 Lowlands (2 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "lo_amsterdam",  label = "阿姆斯特丹",   country_id = "lowlands", type = "capital",  q = 3,  r = 6,  weight = 1, controller = "lowlands", terrain = "coast" },
    { id = "lo_brussels",   label = "布鲁塞尔",     country_id = "lowlands", type = "industrial", q = 3,  r = 5,  weight = 1, controller = "lowlands", terrain = "plains" },

    -- ═══════════════════════════════════════════════════════════
    -- 丹麦 Denmark (2 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "dk_copenhagen", label = "哥本哈根",     country_id = "denmark", type = "capital",  q = 5,  r = 4,  weight = 1, controller = "denmark", terrain = "coast" },
    { id = "dk_jutland",    label = "日德兰",       country_id = "denmark", type = "port",     q = 4,  r = 4,  weight = 1, controller = "denmark", terrain = "coast" },

    -- ═══════════════════════════════════════════════════════════
    -- 瑞典-挪威 Scandinavia (3 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "sc_stockholm",  label = "斯德哥尔摩",   country_id = "scandinavia", type = "capital",  q = 6,  r = 2,  weight = 1, controller = "scandinavia", terrain = "coast" },
    { id = "sc_oslo",       label = "奥斯陆",       country_id = "scandinavia", type = "port",     q = 5,  r = 2,  weight = 1, controller = "scandinavia", terrain = "coast" },
    { id = "sc_norrland",   label = "北部山区",     country_id = "scandinavia", type = "mine",     q = 6,  r = 1,  weight = 1, controller = "scandinavia", terrain = "mountain" },

    -- ═══════════════════════════════════════════════════════════
    -- 芬兰 Finland (2 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "fi_helsinki",   label = "赫尔辛基",     country_id = "finland", type = "capital",  q = 8,  r = 2,  weight = 1, controller = "russia",  terrain = "coast" },
    { id = "fi_inland",     label = "芬兰内陆",     country_id = "finland", type = "mine",     q = 8,  r = 1,  weight = 1, controller = "russia",  terrain = "forest" },

    -- ═══════════════════════════════════════════════════════════
    -- 瑞士 Switzerland (2 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "sw_bern",       label = "伯尔尼",       country_id = "switzerland", type = "capital",    q = 4,  r = 8,  weight = 1, controller = "switzerland", terrain = "mountain" },
    { id = "sw_zurich",     label = "苏黎世",       country_id = "switzerland", type = "industrial", q = 4,  r = 9,  weight = 1, controller = "switzerland", terrain = "mountain" },

    -- ═══════════════════════════════════════════════════════════
    -- 西班牙 Spain/Iberia (3 tiles)
    -- ═══════════════════════════════════════════════════════════
    { id = "ib_madrid",     label = "马德里",       country_id = "iberia", type = "capital",  q = 0,  r = 12, weight = 1, controller = "iberia", terrain = "plains" },
    { id = "ib_barcelona",  label = "巴塞罗那",     country_id = "iberia", type = "port",     q = 1,  r = 11, weight = 1, controller = "iberia", terrain = "coast" },
    { id = "ib_lisbon",     label = "里斯本",       country_id = "iberia", type = "port",     q = 0,  r = 13, weight = 1, controller = "iberia", terrain = "coast" },
}

-- ============================================================================
-- 核心函数
-- ============================================================================

function MapTilesData.CreateInitialTiles()
    local tiles = {}
    for _, t in ipairs(MapTilesData.TEMPLATES) do
        table.insert(tiles, copyTile(t))
    end
    MapTilesData.RebuildNeighbors(tiles)
    return tiles
end

--- 重建邻居关系（even-q flat-top offset grid）
function MapTilesData.RebuildNeighbors(tiles)
    local byCoord = {}
    for _, t in ipairs(tiles or {}) do
        byCoord[(t.q or 0) .. "," .. (t.r or 0)] = t
        t.neighbors = {}
    end
    -- even-q flat-top 偏移坐标邻居方向
    local evenDirs = { {1, -1}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {-1, 0} }
    local oddDirs  = { {1, 0}, {1, 1}, {0, -1}, {0, 1}, {-1, 0}, {-1, 1} }
    for _, t in ipairs(tiles or {}) do
        local q = t.q or 0
        local dirs = (q % 2 == 0) and evenDirs or oddDirs
        for _, d in ipairs(dirs) do
            local nq = q + d[1]
            local nr = (t.r or 0) + d[2]
            local n = byCoord[nq .. "," .. nr]
            if n then table.insert(t.neighbors, n.id) end
        end
    end
end

function MapTilesData.EnsureState(state)
    if not state.map_tiles or #state.map_tiles == 0 then
        state.map_tiles = MapTilesData.CreateInitialTiles()
        return true
    end

    -- 模板升级兼容：保留同 ID 的运行时控制状态，移除旧版遗留 tile。
    local existingById = {}
    for _, t in ipairs(state.map_tiles) do
        existingById[t.id] = t
    end
    local upgraded = {}
    local changed = #state.map_tiles ~= #MapTilesData.TEMPLATES
    for _, tmpl in ipairs(MapTilesData.TEMPLATES) do
        local t = copyTile(tmpl)
        local old = existingById[tmpl.id]
        if old then
            t.controller = old.controller or t.controller
            t.owner = old.owner or t.owner
            t.exhausted = old.exhausted or t.exhausted
            t.manual_control = old.manual_control or t.manual_control
        else
            changed = true
        end
        table.insert(upgraded, t)
    end
    state.map_tiles = upgraded
    MapTilesData.RebuildNeighbors(state.map_tiles)
    return changed
end

function MapTilesData.GetTile(state, tileId)
    for _, t in ipairs((state and state.map_tiles) or {}) do
        if t.id == tileId then return t end
    end
    return nil
end

--- 获取指定国家的所有 tile
---@param state table
---@param countryId string
---@return table[]
function MapTilesData.GetTilesByCountry(state, countryId)
    local result = {}
    for _, t in ipairs((state and state.map_tiles) or {}) do
        if t.country_id == countryId then
            table.insert(result, t)
        end
    end
    return result
end

--- 获取所有不重复的 country_id
---@param tiles table[]|nil
---@return string[]
function MapTilesData.GetAllCountryIds(tiles)
    local seen = {}
    local result = {}
    for _, t in ipairs(tiles or {}) do
        if t.country_id and not seen[t.country_id] then
            seen[t.country_id] = true
            result[#result + 1] = t.country_id
        end
    end
    return result
end

--- 判断两个 tile 是否属于不同国家（用于边界判断）
---@param tileA table
---@param tileB table
---@return boolean
function MapTilesData.IsBorderEdge(tileA, tileB)
    if not tileA or not tileB then return true end
    return tileA.country_id ~= tileB.country_id
end

--- 查找指定坐标的 tile
---@param tiles table[]
---@param q number
---@param r number
---@return table|nil
function MapTilesData.GetTileByCoord(tiles, q, r)
    for _, t in ipairs(tiles or {}) do
        if t.q == q and t.r == r then return t end
    end
    return nil
end

-- ============================================================================
-- 同步函数（与 region 经济系统双向同步）
-- ============================================================================

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
        if tile.region_id and byRegion[tile.region_id] and not tile.manual_control then
            tile.controller = dominantFromRegion(byRegion[tile.region_id])
        end
    end
end

return MapTilesData
