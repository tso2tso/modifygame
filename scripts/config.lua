-- ============================================================================
-- 《百年萨拉热窝：黄金家族》- 全局配置
-- 严格遵循 sarajevo_dynasty_ui_spec.md v1.0
-- 设计语言：工业帝国主义时代的家族账簿
-- ============================================================================

local Config = {}

-- 游戏信息
Config.TITLE = "百年萨拉热窝：黄金家族"
Config.VERSION = "0.3.0"

-- ============================================================================
-- 7 章时代主题（对应 docs/sarajevo-hybrid-ui.html 的 era tokens）
-- 设计原则：只覆盖 era_accent / era_border / era_overlay / era_label
--           底色系统 bg_* / paper_* / text_* 全程不变
-- ============================================================================
Config.ERAS = {
    {
        id = 1, start_year = 1904, end_year = 1913,
        label  = "第一章 铜版帝国",
        accent = { 200, 169, 110, 255 },  -- #C8A96E 旧金
        border = { 139,  69,  19, 255 },  -- #8B4513 赭石
        overlay = { 200, 169, 110, 20 },  -- 8% 金色微光
        war_stripe = false,
        glitch = false,
    },
    {
        id = 2, start_year = 1914, end_year = 1918,
        label  = "第二章 战报红章",
        accent = { 230, 115,  50, 255 },  -- #E67332 战火橙红（与跌色 #C0392B 区分）
        border = { 160,  50,  20, 255 },  -- #A03214 铁锈
        overlay = { 160,  50,  20, 46 },  -- 18% 铁锈
        war_stripe = true,
        glitch = false,
    },
    {
        id = 3, start_year = 1919, end_year = 1940,
        label  = "第三章 黑金工业",
        accent = { 212, 175,  55, 255 },  -- #D4AF37 纯金
        border = {  74, 124,  89, 255 },  -- #4A7C59 钢绿
        overlay = {  28,  35,  49, 77 },  -- 30% 深蓝钢
        war_stripe = false,
        glitch = false,
    },
    {
        id = 4, start_year = 1941, end_year = 1945,
        label  = "第四章 战时灰幕",
        accent = { 165,  75,  75, 255 },  -- #A54B4B 灰烬红（与 accent_red #C0392B 区分）
        border = {  74,  74,  74, 255 },  -- #4A4A4A 铅灰
        overlay = {  45,  45,  45, 102 }, -- 40% 战灰
        war_stripe = true,
        glitch = false,
    },
    {
        id = 5, start_year = 1946, end_year = 1991,
        label  = "第五章 制度蓝红",
        accent = {  46, 125,  50, 255 },  -- #2E7D32 计划绿
        border = {  27,  58, 107, 255 },  -- #1B3A6B 政治蓝
        overlay = {  27,  58, 107, 64 },  -- 25% 政治蓝
        war_stripe = false,
        glitch = false,
    },
    {
        id = 6, start_year = 1992, end_year = 1995,
        label  = "第六章 围城信号",
        accent = { 255, 102,   0, 255 },  -- #FF6600 火光橙
        border = {  61,  61,  61, 255 },  -- #3D3D3D 烟灰
        overlay = { 255, 102,   0, 26 },  -- 10% 橙色微光
        war_stripe = true,
        glitch = true,                    -- 信号抖动效果
    },
    {
        id = 7, start_year = 1996, end_year = 2014,
        label  = "第七章 玻璃金融",
        accent = {   0, 137, 123, 255 },  -- #00897B 科技青
        border = {  28,  53,  87, 255 },  -- #1C3557 深海蓝
        overlay = {  28,  53,  87, 51 },  -- 20% 深海蓝
        war_stripe = false,
        glitch = false,
    },
}

--- 根据年份获取对应时代定义
---@param year number
---@return table era
function Config.GetEraByYear(year)
    for _, era in ipairs(Config.ERAS) do
        if year >= era.start_year and year <= era.end_year then
            return era
        end
    end
    -- 越界兜底：取最近一章
    if year < Config.ERAS[1].start_year then return Config.ERAS[1] end
    return Config.ERAS[#Config.ERAS]
end

--- 获取当前时代的 accent 色（常用快捷）
---@param state table
---@return table rgba
function Config.GetEraAccent(state)
    if not state or not state.year then
        return { 201, 168, 76, 255 }  -- 默认金色
    end
    return Config.GetEraByYear(state.year).accent
end

-- ============================================================================
-- 色彩系统（sarajevo_dynasty_ui_spec §2）
-- ============================================================================
Config.COLORS = {
    -- 背景层
    bg_base       = { 26, 24, 20, 255 },       -- #1A1814 深煤炭棕黑（主背景）
    bg_surface    = { 36, 32, 24, 255 },        -- #242018 略浅的卡片底层
    bg_elevated   = { 46, 41, 32, 255 },        -- #2E2920 悬浮卡片/弹出面板

    -- 纸张层（内容卡片）
    paper_dark    = { 61, 52, 38, 255 },        -- #3D3426 深羊皮纸（卡片背景主色）
    paper_mid     = { 74, 62, 46, 255 },        -- #4A3E2E 中羊皮纸（内嵌区域）
    paper_light   = { 200, 184, 154, 255 },     -- #C8B89A 浅羊皮纸（边框/分隔线/次要文字）
    paper_cream   = { 232, 217, 192, 255 },     -- #E8D9C0 奶油白

    -- 文字层
    text_primary  = { 240, 230, 208, 255 },     -- #F0E6D0 主文本（近白奶油色）
    text_secondary= { 168, 152, 128, 255 },     -- #A89880 次要文本（灰棕色）
    text_muted    = { 107, 94, 78, 255 },       -- #6B5E4E 低优先级文本/占位符
    text_label    = { 200, 184, 154, 255 },     -- #C8B89A 标签/说明文字

    -- 强调色
    accent_gold   = { 201, 168, 76, 255 },      -- #C9A84C 金色（货币/高价值信息/高亮边框）
    accent_red    = { 192, 57, 43, 255 },        -- #C0392B 警戒红
    accent_amber  = { 212, 129, 10, 255 },       -- #D4810A 琥珀橙
    accent_green  = { 74, 124, 89, 255 },        -- #4A7C59 暗绿
    accent_blue   = { 58, 107, 138, 255 },       -- #3A6B8A 钢蓝

    -- 功能色别名
    danger        = { 192, 57, 43, 255 },        -- = accent_red
    warning       = { 212, 129, 10, 255 },       -- = accent_amber
    success       = { 74, 124, 89, 255 },        -- = accent_green
    info          = { 58, 107, 138, 255 },       -- = accent_blue
    neutral       = { 107, 94, 78, 255 },        -- = text_muted

    -- 边框/分隔线
    border_card   = { 200, 184, 154, 100 },     -- paper_light 40% opacity
    border_gold   = { 201, 168, 76, 130 },      -- accent_gold 50% opacity
    divider       = { 74, 62, 46, 200 },        -- paper_mid

    -- AP 圆点
    ap_filled     = { 201, 168, 76, 255 },      -- accent_gold 实心
    ap_empty      = { 200, 184, 154, 255 },     -- paper_light 空心

    -- Tab
    tab_active    = { 201, 168, 76, 255 },      -- accent_gold
    tab_inactive  = { 107, 94, 78, 255 },       -- text_muted
}

-- 快捷别名
local C = Config.COLORS
C.gold = C.accent_gold       -- 货币/高亮常用别名
C.text_gold = C.accent_gold  -- 金色文字别名

-- ============================================================================
-- 字号规范（sarajevo_dynasty_ui_spec §3.2）
-- ============================================================================
Config.FONT = {
    super_title  = 28,   -- 弹出面板大标题
    page_title   = 22,   -- 顶栏年份/季节
    card_title   = 18,   -- 矿场名称、系统名
    subtitle     = 15,   -- 分组标签
    body         = 13,   -- 事件描述正文
    body_minor   = 12,   -- 说明文字、括号内容
    label        = 11,   -- 状态徽章、小标签
    data_large   = 32,   -- 关键KPI数字
    data_mid     = 20,   -- 次要数据（百分比/小计）
    data_small   = 16,   -- 概览数值
}

-- ============================================================================
-- 尺寸常量（sarajevo_dynasty_ui_spec §4 + §8）
-- ============================================================================
Config.SIZE = {
    -- 主要区域高度
    top_bar_height    = 72,   -- §4.1 TopBar
    ap_bar_height     = 52,   -- §4.2 AP Bar
    bottom_nav_height = 64,   -- §4.7 Bottom Navigation
    sub_header_height = 56,   -- §6.1 深度页 Sub-Header
    season_bar_height = 64,   -- §4.6 Season Overview Bar

    -- 间距
    page_padding      = 16,   -- §8.1 全局水平内边距
    card_padding      = 16,   -- §4.3 内边距
    card_gap          = 12,   -- §4.3 卡片间距
    section_gap       = 16,   -- 区块间距

    -- 圆角（§1.3 禁止 > 8px 大卡片圆角）
    radius_card       = 6,    -- 卡片圆角
    radius_btn        = 4,    -- 按钮圆角
    radius_badge      = 3,    -- 徽章圆角
    radius_drawer     = 8,    -- Drawer 圆角

    -- 图标
    icon_size         = 24,   -- §4.7 图标尺寸
    icon_resource     = 16,   -- §4.1 资源图标

    -- AP 圆点
    ap_dot_size       = 10,   -- §4.2
    ap_dot_gap        = 8,    -- §4.2

    -- 快速操作
    quick_action_size = 80,   -- §4.5 约 80×80

    -- 事件卡图片
    event_img_size    = 64,   -- §4.3

    -- 焦点卡片
    focus_img_height  = 120,  -- §4.4

    -- 按钮
    btn_height        = 40,   -- §4.4 操作按钮高度
    btn_small_height  = 32,   -- §4.3 处理按钮

    -- Drawer
    drawer_width_pct  = 58,   -- §4.8 右侧 Drawer 约 58% 屏宽

    -- 兼容旧名称（供深度页过渡期引用）
    font_title    = 18,
    font_large    = 15,
    font_body     = 13,
    font_small    = 12,
    font_tiny     = 11,
    font_number   = 16,
    font_h1       = 22,
    font_h2       = 18,
    font_caption  = 12,
    spacing_xs    = 4,
    spacing_sm    = 8,
    spacing_md    = 12,
    spacing_lg    = 16,
    spacing_xl    = 24,
    spacing_xxl   = 32,
    card_radius   = 6,
    btn_radius    = 4,
    icon_sz       = 24,
}

-- ============================================================================
-- 进度条颜色规则（§4.4）
-- ============================================================================
function Config.GetUtilColor(pct)
    if pct >= 80 then return C.accent_green end
    if pct >= 50 then return C.accent_amber end
    return C.accent_red
end

-- ============================================================================
-- 数字千分位格式化（§3.3 货币金额始终右对齐，使用等宽数字）
-- ============================================================================
---@param n number
---@return string
function Config.FormatNumber(n)
    local s = tostring(math.floor(math.abs(n)))
    local parts = {}
    while #s > 3 do
        table.insert(parts, 1, s:sub(-3))
        s = s:sub(1, -4)
    end
    table.insert(parts, 1, s)
    local result = table.concat(parts, ",")
    if n < 0 then result = "-" .. result end
    return result
end

--- 季度对应月日文本（设计图顶栏显示 XmonthYday 格式）
Config.QUARTER_DATES = {
    "4月15日",   -- Q1 春
    "7月15日",   -- Q2 夏
    "10月15日",  -- Q3 秋
    "1月15日",   -- Q4 冬
}

-- ============================================================================
-- 游戏平衡数值
-- ============================================================================
Config.BALANCE = {
    start_year     = 1904,
    start_quarter  = 1,
    end_year       = 2014,
    end_quarter    = 4,
    base_ap        = 6,
    max_ap_bonus   = 4,
    start_cash     = 1000,
    start_gold     = 5,
    gold_price     = 50,
    worker_wage    = 8,
    guard_wage     = 12,
    mine_base_output = 2,
    victory_threshold = 100,
}

-- ============================================================================
-- Tab 定义（§4.7 底部导航 — 5 个 Tab）
-- ============================================================================
Config.TABS = {
    { id = "family",   label = "家族", icon = "👥" },
    { id = "industry", label = "产业", icon = "⛏️" },
    { id = "market",   label = "市场", icon = "📈" },
    { id = "military", label = "武装", icon = "🛡️" },
    { id = "world",    label = "世界", icon = "🌍" },
}

-- ============================================================================
-- 快速操作定义（§4.5 — 6 项，3列×2行）
-- ============================================================================
-- ap_cost 为"典型"消耗（仅展示用；不同操作实际消耗见 data/balance.lua）
Config.QUICK_ACTIONS = {
    { id = "personnel",   label = "人事管理", icon = "👥", ap_cost = 0 },
    { id = "finance",     label = "金融操作", icon = "📈", ap_cost = 0 },
    { id = "technology",  label = "科技研发", icon = "🔬", ap_cost = 2 },
    { id = "intelligence",label = "情报行动", icon = "👁️", ap_cost = 1 },
    { id = "diplomacy",   label = "政治外交", icon = "🤝", ap_cost = 1 },
    { id = "trade",       label = "资产交易", icon = "🏭", ap_cost = 2 },
}

-- ============================================================================
-- 岗位定义
-- ============================================================================
Config.POSITIONS = {
    { id = "mine_director",   name = "矿业总监", attr1 = "management", attr2 = "knowledge" },
    { id = "military_chief",  name = "军务主管", attr1 = "strategy",   attr2 = "ambition" },
    { id = "finance_director",name = "财务总监", attr1 = "management", attr2 = "strategy" },
    { id = "culture_advisor", name = "文化顾问", attr1 = "charisma",   attr2 = "knowledge" },
    { id = "tech_advisor",    name = "科技顾问", attr1 = "knowledge",  attr2 = "ambition" },
    { id = "diplomat",        name = "外交总监", attr1 = "charisma",   attr2 = "strategy" },
}

-- 属性中文名
Config.ATTR_NAMES = {
    management = "管理",
    strategy   = "谋略",
    charisma   = "魅力",
    knowledge  = "学识",
    ambition   = "野心",
}

-- ============================================================================
-- 季度中文
-- ============================================================================
Config.QUARTER_NAMES = { "春", "夏", "秋", "冬" }

return Config
