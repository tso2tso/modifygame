-- ============================================================================
-- 市场页（深度页）— sarajevo_dynasty_ui_spec §6.4
-- 股票/债券/商品 市场概览
-- 交替行背景 + ▲/▼ 涨跌箭头 + 下划线式标签
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local Balance = require("data.balance")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local MarketPage = {}

---@type table 游戏状态引用
local stateRef_ = nil
---@type function|nil 状态变化回调
local onStateChanged_ = nil

--- 创建市场页内容
---@param state table
---@param callbacks table { onStateChanged = function }
---@return table widget
function MarketPage.Create(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged
    return MarketPage._BuildContent(state)
end

function MarketPage._BuildContent(state)
    local goldPrice = Balance.MINE.gold_price

    -- 模拟市场数据
    local stockItems = {
        { name = "萨拉热窝矿业", price = "12.50", change = "+12.3%", up = true },
        { name = "帝国铁路公司", price = "8.30",  change = "-5.2%",  up = false },
        { name = "巴尔干行船",   price = "15.60", change = "+3.1%",  up = true },
        { name = "军需工业集团", price = "22.10", change = "+8.7%",  up = true },
        { name = "奥匈银行信托", price = "31.40", change = "-1.8%",  up = false },
        { name = "东方贸易商行", price = "9.75",  change = "+0.5%",  up = true },
    }

    -- 构建交替行背景的股票列表
    local stockRows = {}
    for i, item in ipairs(stockItems) do
        table.insert(stockRows, MarketPage._StockRow(item, i))
    end

    return UI.Panel {
        id = "marketContent",
        width = "100%",
        flexDirection = "column",
        gap = S.section_gap,
        children = {
            -- §6.4 标签页筛选（下划线式）
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 0,
                borderBottomWidth = 1,
                borderBottomColor = C.paper_mid,
                children = {
                    MarketPage._TabUnderline("股票", true),
                    MarketPage._TabUnderline("债券", false),
                    MarketPage._TabUnderline("商品", false),
                },
            },

            -- 金价信息行
            UI.Panel {
                width = "100%",
                paddingVertical = 10,
                paddingHorizontal = S.card_padding,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "当前金价",
                        fontSize = F.body,
                        fontColor = C.text_secondary,
                    },
                    UI.Label {
                        text = goldPrice .. " 克朗/单位",
                        fontSize = F.card_title,
                        fontWeight = "bold",
                        fontColor = C.accent_gold,
                    },
                },
            },

            -- 股票列表
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                borderRadius = S.radius_card,
                overflow = "hidden",
                borderWidth = 1,
                borderColor = C.border_card,
                children = stockRows,
            },

            -- 底部：我的持仓
            UI.Panel {
                width = "100%",
                height = 44,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderWidth = 1, borderColor = C.paper_light,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "auto",
                children = {
                    UI.Label {
                        text = "我的持仓 ›",
                        fontSize = F.body,
                        fontColor = C.accent_gold,
                        pointerEvents = "none",
                    },
                },
            },
        },
    }
end

--- §6.4 股票列表行
--- 交替背景：奇数行 bg_surface，偶数行 bg_elevated
--- 涨跌箭头：▲ accent_green / ▼ accent_red
function MarketPage._StockRow(item, index)
    local isOdd = (index % 2 == 1)
    local bgColor = isOdd and C.bg_surface or C.bg_elevated
    local arrow = item.up and "▲" or "▼"
    local changeColor = item.up and C.accent_green or C.accent_red

    return UI.Panel {
        width = "100%",
        paddingVertical = 10,
        paddingHorizontal = S.card_padding,
        backgroundColor = bgColor,
        flexDirection = "row",
        alignItems = "center",
        children = {
            -- 公司简称
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                children = {
                    UI.Label {
                        text = item.name,
                        fontSize = F.subtitle,
                        fontColor = C.text_primary,
                    },
                },
            },
            -- 现价
            UI.Label {
                text = "¥" .. item.price,
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
                marginRight = 12,
            },
            -- 涨跌幅
            UI.Label {
                text = arrow .. " " .. item.change,
                fontSize = F.body,
                fontColor = changeColor,
                minWidth = 72,
                textAlign = "right",
            },
        },
    }
end

--- §6.4 下划线式标签（Tab Underline）
function MarketPage._TabUnderline(label, active)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        paddingVertical = 10,
        justifyContent = "center", alignItems = "center",
        borderBottomWidth = active and 2 or 0,
        borderBottomColor = C.accent_gold,
        pointerEvents = "auto",
        children = {
            UI.Label {
                text = label,
                fontSize = F.body,
                fontWeight = active and "bold" or "normal",
                fontColor = active and C.accent_gold or C.text_muted,
                pointerEvents = "none",
            },
        },
    }
end

function MarketPage.Refresh(root, state)
    stateRef_ = state
end

return MarketPage
