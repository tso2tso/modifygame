-- ============================================================================
-- 市场页（深度页）— sarajevo_dynasty_ui_spec §6.4
-- 股票/债券/商品 市场概览
-- 接入 GBM 动态股价 + 买卖交互 + 微型走势图
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local Balance = require("data.balance")
local GameState = require("game_state")
local StockEngine = require("systems.stock_engine")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local MarketPage = {}

---@type table 游戏状态引用
local stateRef_ = nil
---@type function|nil 状态变化回调
local onStateChanged_ = nil
---@type table|nil 当前打开的交易弹窗
local tradeModal_ = nil

-- ============================================================================
-- 板块标签（中文）
-- ============================================================================
local SECTOR_NAMES = {
    mining     = "矿业",
    transport  = "运输",
    military   = "军工",
    finance    = "金融",
    trade      = "贸易",
}

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
    local era = Config.GetEraByYear(state.year)
    local accent = era.accent

    local inflation = state.inflation_factor or 1.0
    local goldPriceNow = math.floor(Balance.MINE.gold_price * inflation)
    local silverPriceNow = math.floor(Balance.MINE.silver_price * inflation)

    -- 持仓信息
    local portfolioVal, portfolioCost = StockEngine.PortfolioValue(state)
    local pnl = portfolioVal - portfolioCost
    local pnlColor = pnl >= 0 and C.accent_green or C.accent_red

    -- 构建股票行
    local stockRows = {}
    for i, stock in ipairs(state.stocks or {}) do
        table.insert(stockRows, MarketPage._StockRow(state, stock, i, accent))
    end

    return UI.Panel {
        id = "marketContent",
        width = "100%",
        flexDirection = "column",
        gap = S.section_gap,
        children = {
            -- 标签页
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 0,
                borderBottomWidth = 1,
                borderBottomColor = C.paper_mid,
                children = {
                    MarketPage._TabUnderline("股票", true, accent),
                    MarketPage._TabUnderline("贷款", false, accent),
                    MarketPage._TabUnderline("商品", false, accent),
                },
            },

            -- 商品价格行：金价 + 银价 + 通胀
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
                    MarketPage._PriceCol("🟡 金价", goldPriceNow .. "/单位", accent),
                    MarketPage._PriceCol("⚪ 银价", silverPriceNow .. "/单位", C.paper_light),
                    MarketPage._PriceCol("📊 通胀", string.format("×%.2f", inflation),
                        inflation > 1.3 and C.accent_red or C.text_primary),
                },
            },

            -- 持仓汇总卡
            MarketPage._PortfolioCard(state, portfolioVal, pnl, pnlColor, accent),

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

            -- 贷款入口 + 新建贷款按钮
            MarketPage._LoanCard(state, accent),
        },
    }
end

-- ============================================================================
-- 持仓汇总卡
-- ============================================================================
function MarketPage._PortfolioCard(state, val, pnl, pnlColor, accent)
    local holdingsList = {}
    local cnt = 0
    if state.portfolio and state.portfolio.holdings then
        for stockId, h in pairs(state.portfolio.holdings) do
            cnt = cnt + 1
            local stock = StockEngine.Find(state, stockId)
            if stock then
                table.insert(holdingsList, UI.Label {
                    text = string.format("· %s ×%d 市值 %.0f 成本 %.1f",
                        stock.name, h.shares, stock.price * h.shares, h.avg_cost),
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                })
            end
        end
    end
    if cnt == 0 then
        table.insert(holdingsList, UI.Label {
            text = "暂无持仓",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
        })
    end

    local children = {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = "我的持仓",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = string.format("市值 %.0f  盈亏 %+.0f",
                        val, pnl),
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = pnlColor,
                },
            },
        },
    }
    for _, w in ipairs(holdingsList) do table.insert(children, w) end

    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_card,
        borderLeftWidth = 2,
        borderLeftColor = accent,
        flexDirection = "column",
        gap = 3,
        children = children,
    }
end

-- ============================================================================
-- 金价 / 银价 / 通胀列
-- ============================================================================
function MarketPage._PriceCol(label, value, color)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        alignItems = "center",
        children = {
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
            },
            UI.Label {
                text = value,
                fontSize = F.card_title,
                fontWeight = "bold",
                fontColor = color or C.text_primary,
            },
        },
    }
end

-- ============================================================================
-- 股票行（可点击打开交易弹窗）
-- ============================================================================
function MarketPage._StockRow(state, stock, index, accent)
    local isOdd = (index % 2 == 1)
    local bgColor = isOdd and C.bg_surface or C.bg_elevated
    local up = (stock.change_pct or 0) >= 0
    local arrow = up and "▲" or "▼"
    local changeColor = up and C.accent_green or C.accent_red

    local sectorLabel = SECTOR_NAMES[stock.sector] or stock.sector or ""

    -- 持仓标记
    local holding = state.portfolio and state.portfolio.holdings
        and state.portfolio.holdings[stock.id]
    local holdingText = holding and string.format(" 持%d", holding.shares) or ""

    return UI.Panel {
        width = "100%",
        paddingVertical = 10,
        paddingHorizontal = S.card_padding,
        backgroundColor = bgColor,
        flexDirection = "row",
        alignItems = "center",
        pointerEvents = "auto",
        onPointerUp = function(self)
            MarketPage._OpenTradeModal(state, stock, accent)
        end,
        children = {
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                flexDirection = "column",
                gap = 2,
                children = {
                    UI.Label {
                        text = stock.name .. holdingText,
                        fontSize = F.subtitle,
                        fontColor = holding and accent or C.text_primary,
                        pointerEvents = "none",
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = sectorLabel,
                                fontSize = F.label,
                                fontColor = C.text_muted,
                                pointerEvents = "none",
                            },
                            -- 迷你走势条（最近 8 点）
                            MarketPage._Sparkline(stock, changeColor),
                        },
                    },
                },
            },
            UI.Label {
                text = string.format("¥%.2f", stock.price),
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
                marginRight = 12,
                pointerEvents = "none",
            },
            UI.Label {
                text = string.format("%s %+.1f%%", arrow, stock.change_pct or 0),
                fontSize = F.body,
                fontColor = changeColor,
                minWidth = 72,
                textAlign = "right",
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 迷你走势条：用高度不同的小矩形模拟 sparkline
-- ============================================================================
function MarketPage._Sparkline(stock, color)
    local hist = stock.history or {}
    if #hist < 2 then
        return UI.Panel { width = 0, height = 0, pointerEvents = "none" }
    end
    -- 归一化到 0-1
    local lo, hi = math.huge, -math.huge
    for _, p in ipairs(hist) do
        if p < lo then lo = p end
        if p > hi then hi = p end
    end
    local range = math.max(0.001, hi - lo)

    local bars = {}
    local showCount = math.min(8, #hist)
    local start = #hist - showCount + 1
    for i = start, #hist do
        local v = hist[i]
        local pct = (v - lo) / range
        local h = 2 + math.floor(pct * 10)  -- 2-12 px
        table.insert(bars, UI.Panel {
            width = 2, height = h,
            backgroundColor = color,
            pointerEvents = "none",
        })
    end

    return UI.Panel {
        flexDirection = "row",
        alignItems = "flex-end",
        gap = 1,
        height = 12,
        pointerEvents = "none",
        children = bars,
    }
end

-- ============================================================================
-- 标签页下划线
-- ============================================================================
function MarketPage._TabUnderline(label, active, accent)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        paddingVertical = 10,
        justifyContent = "center", alignItems = "center",
        borderBottomWidth = active and 2 or 0,
        borderBottomColor = accent,
        pointerEvents = "auto",
        children = {
            UI.Label {
                text = label,
                fontSize = F.body,
                fontWeight = active and "bold" or "normal",
                fontColor = active and accent or C.text_muted,
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 交易弹窗（买入/卖出）
-- ============================================================================
function MarketPage._OpenTradeModal(state, stock, accent)
    if tradeModal_ then
        tradeModal_:Close()
        tradeModal_ = nil
    end

    -- 内部数量状态（闭包）
    local qty = 10
    local qtyLabel

    local function refreshQty()
        if qtyLabel then qtyLabel:SetText(tostring(qty)) end
    end

    local function adjustQty(delta)
        qty = math.max(1, qty + delta)
        refreshQty()
    end

    local holding = state.portfolio and state.portfolio.holdings
        and state.portfolio.holdings[stock.id]
    local holdingShares = (holding and holding.shares) or 0

    qtyLabel = UI.Label {
        text = tostring(qty),
        fontSize = F.card_title,
        fontWeight = "bold",
        fontColor = C.text_primary,
        minWidth = 60,
        textAlign = "center",
    }

    tradeModal_ = UI.Modal {
        isOpen = true,
        title = stock.name,
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
    }

    local up = (stock.change_pct or 0) >= 0
    local changeColor = up and C.accent_green or C.accent_red

    local content = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 10,
        children = {
            -- 价格/涨跌
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = string.format("现价 ¥%.2f", stock.price),
                        fontSize = F.card_title,
                        fontWeight = "bold",
                        fontColor = accent,
                    },
                    UI.Label {
                        text = string.format("%s %+.2f%%",
                            up and "▲" or "▼", stock.change_pct or 0),
                        fontSize = F.body,
                        fontColor = changeColor,
                    },
                },
            },
            -- 基本面
            UI.Label {
                text = string.format("板块：%s  |  长期漂移 μ=%+.3f  波动 σ=%.2f",
                    SECTOR_NAMES[stock.sector] or "",
                    stock.mu or 0, stock.sigma or 0),
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            },
            -- 持仓
            UI.Label {
                text = string.format("当前持仓：%d 股  均价 %.2f",
                    holdingShares,
                    (holding and holding.avg_cost) or 0),
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            },
            UI.Divider { color = C.divider },
            -- 数量选择器
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 8,
                children = {
                    MarketPage._QtyBtn("-10", function() adjustQty(-10) end),
                    MarketPage._QtyBtn("-1",  function() adjustQty(-1) end),
                    qtyLabel,
                    MarketPage._QtyBtn("+1",  function() adjustQty(1) end),
                    MarketPage._QtyBtn("+10", function() adjustQty(10) end),
                },
            },
            -- 买入 / 卖出
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = {
                    MarketPage._ActionBtn("💰 买入", C.accent_green, function()
                        MarketPage._OnBuy(state, stock.id, qty)
                    end),
                    MarketPage._ActionBtn("📤 卖出", C.accent_red, function()
                        MarketPage._OnSell(state, stock.id, qty)
                    end),
                },
            },
            -- 全仓快捷
            holdingShares > 0 and UI.Panel {
                flexDirection = "row",
                children = {
                    MarketPage._ActionBtn("全部卖出 (×" .. holdingShares .. ")",
                        C.accent_amber, function()
                            MarketPage._OnSell(state, stock.id, holdingShares)
                        end),
                },
            } or UI.Panel { width = 0, height = 0 },
        },
    }
    tradeModal_:AddContent(content)
    tradeModal_:Open()
end

function MarketPage._QtyBtn(label, onClick)
    return UI.Panel {
        width = 42, height = 32,
        borderRadius = S.radius_btn,
        backgroundColor = C.bg_elevated,
        borderWidth = 1, borderColor = C.paper_light,
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onPointerUp = function(self) onClick() end,
        children = {
            UI.Label {
                text = label,
                fontSize = F.body,
                fontColor = C.text_primary,
                pointerEvents = "none",
            },
        },
    }
end

function MarketPage._ActionBtn(label, bg, onClick)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        height = 40,
        borderRadius = S.radius_btn,
        backgroundColor = bg,
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onPointerUp = function(self) onClick() end,
        children = {
            UI.Label {
                text = label,
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
                pointerEvents = "none",
            },
        },
    }
end

function MarketPage._OnBuy(state, stockId, qty)
    local ok, msg = StockEngine.Buy(state, stockId, qty)
    if ok then
        GameState.AddLog(state, "[股市] " .. msg)
        UI.Toast.Show(msg, { variant = "success", duration = 1.5 })
        if tradeModal_ then tradeModal_:Close(); tradeModal_ = nil end
        if onStateChanged_ then onStateChanged_() end
    else
        UI.Toast.Show(msg or "买入失败", { variant = "error", duration = 1.5 })
    end
end

function MarketPage._OnSell(state, stockId, qty)
    local ok, msg = StockEngine.Sell(state, stockId, qty)
    if ok then
        GameState.AddLog(state, "[股市] " .. msg)
        UI.Toast.Show(msg, { variant = "success", duration = 1.5 })
        if tradeModal_ then tradeModal_:Close(); tradeModal_ = nil end
        if onStateChanged_ then onStateChanged_() end
    else
        UI.Toast.Show(msg or "卖出失败", { variant = "error", duration = 1.5 })
    end
end

-- ============================================================================
-- 贷款卡
-- ============================================================================
function MarketPage._LoanCard(state, accent)
    state.loans = state.loans or {}
    local loanRows = {
        UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "贷款",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = string.format("当前 %d 笔", #state.loans),
                    fontSize = F.body_minor,
                    fontColor = C.text_muted,
                },
            },
        },
    }

    if #state.loans > 0 then
        for _, loan in ipairs(state.loans) do
            table.insert(loanRows, UI.Label {
                text = string.format("· 本金 %d  利率 %.1f%%  剩 %d 季",
                    loan.principal,
                    (loan.interest or 0) * 100,
                    loan.remaining_turns or 0),
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            })
        end
    else
        table.insert(loanRows, UI.Label {
            text = "暂无贷款",
            fontSize = F.body_minor,
            fontColor = C.text_muted,
        })
    end

    -- 申请贷款按钮
    local optionBtns = {}
    for _, opt in ipairs(Balance.LOAN.options) do
        table.insert(optionBtns, MarketPage._QtyBtn(
            string.format("借 %d", opt.amount),
            function()
                MarketPage._OnTakeLoan(state, opt)
            end))
    end
    table.insert(loanRows, UI.Panel {
        flexDirection = "row",
        gap = 6,
        marginTop = 4,
        children = optionBtns,
    })

    return UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderLeftWidth = 2,
        borderLeftColor = accent,
        flexDirection = "column",
        gap = 4,
        children = loanRows,
    }
end

function MarketPage._OnTakeLoan(state, opt)
    state.loans = state.loans or {}
    if #state.loans >= Balance.LOAN.max_active then
        UI.Toast.Show("贷款数量已达上限（" .. Balance.LOAN.max_active .. "）",
            { variant = "warning", duration = 1.5 })
        return
    end
    state.cash = state.cash + opt.amount
    table.insert(state.loans, {
        principal       = opt.amount,
        interest        = opt.interest,
        remaining_turns = opt.duration,
        total_paid      = 0,
    })
    GameState.AddLog(state, string.format("[贷款] 借入 %d，%d 季后到期，季利率 %.1f%%",
        opt.amount, opt.duration, opt.interest * 100))
    UI.Toast.Show(string.format("借入 %d 克朗", opt.amount),
        { variant = "success", duration = 1.5 })
    if onStateChanged_ then onStateChanged_() end
end

function MarketPage.Refresh(root, state)
    stateRef_ = state
end

return MarketPage
