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
---@type function|nil 轻量刷新回调（仅更新 TopBar，不重建页面）
local onLightRefresh_ = nil
---@type table|nil 当前打开的交易弹窗
local tradeModal_ = nil
---@type string 当前激活的标签页
local activeTab_ = "stocks"
---@type table|nil UI 根节点引用
local uiRoot_ = nil

--- 设置 UI 根节点（Modal 必须 AddChild 到 UI 树才能渲染）
function MarketPage.SetRoot(root)
    uiRoot_ = root
end

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
    onLightRefresh_ = callbacks and callbacks.onLightRefresh
    return MarketPage._BuildContent(state)
end

function MarketPage._BuildContent(state)
    local era = Config.GetEraByYear(state.year)
    local accent = era.accent

    -- 标签页定义
    local tabs = {
        { id = "stocks", label = "股票" },
        { id = "loans",  label = "贷款" },
        { id = "goods",  label = "商品" },
    }

    -- 标签行
    local tabWidgets = {}
    for _, tab in ipairs(tabs) do
        local isActive = (activeTab_ == tab.id)
        table.insert(tabWidgets, MarketPage._TabUnderline(
            tab.label, isActive, accent, tab.id))
    end

    -- 根据当前标签构建内容
    local tabContent
    if activeTab_ == "stocks" then
        tabContent = MarketPage._StocksTabContent(state, accent)
    elseif activeTab_ == "loans" then
        tabContent = MarketPage._LoansTabContent(state, accent)
    else
        tabContent = MarketPage._GoodsTabContent(state, accent)
    end

    return UI.Panel {
        id = "marketContent",
        width = "100%",
        flexDirection = "column",
        gap = S.section_gap,
        children = {
            -- 标签栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 0,
                borderBottomWidth = 1,
                borderBottomColor = C.paper_mid,
                children = tabWidgets,
            },
            -- 当前标签内容
            tabContent,
        },
    }
end

-- ============================================================================
-- 股票标签页内容
-- ============================================================================
function MarketPage._StocksTabContent(state, accent)
    local inflation = state.inflation_factor or 1.0
    local BG = Balance.GOLD
    local BM = Balance.MINE
    -- 金价公式与 economy.lua Settle 保持一致：超线性通胀 + 战时溢价 + 修正因子
    local goldPriceCalc = BM.gold_price * (inflation ^ BG.price_inflation_exponent)
    if state.flags and state.flags.at_war then
        goldPriceCalc = goldPriceCalc * (1 + BG.war_premium)
    end
    local priceModifier = GameState.GetModifierValue and GameState.GetModifierValue(state, "military_industry_profit") or 0
    if priceModifier > 0 then goldPriceCalc = goldPriceCalc * (1 + priceModifier * 0.5) end
    local goldPriceBonus = state.gold_price_bonus or 0
    if goldPriceBonus > 0 then goldPriceCalc = goldPriceCalc * (1 + goldPriceBonus) end
    local goldPriceMod = GameState.GetModifierValue and GameState.GetModifierValue(state, "gold_price_mod") or 0
    if goldPriceMod ~= 0 then goldPriceCalc = goldPriceCalc * (1 + goldPriceMod) end
    local goldPriceNow = math.floor(goldPriceCalc)
    local copperPriceMod = GameState.GetModifierValue and GameState.GetModifierValue(state, "copper_price_mod") or 0
    local copperPriceNow = math.max(1, math.floor(BM.copper_price * inflation * (1 + copperPriceMod)))
    local BC = Balance.COAL or {}
    local coalPriceMod = GameState.GetModifierValue and GameState.GetModifierValue(state, "coal_price_mod") or 0
    local coalPriceNow = BM.coal_price * inflation * (1 + coalPriceMod)
    if state.flags and state.flags.at_war then
        coalPriceNow = coalPriceNow * (1 + (BC.war_price_premium or 0.5))
    end
    coalPriceNow = math.max(1, math.floor(coalPriceNow))

    local portfolioVal, portfolioCost = StockEngine.PortfolioValue(state)
    local pnl = portfolioVal - portfolioCost
    local pnlColor = pnl >= 0 and C.accent_green or C.accent_red

    local stockRows = {}
    for i, stock in ipairs(state.stocks or {}) do
        table.insert(stockRows, MarketPage._StockRow(state, stock, i, accent))
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.section_gap,
        children = {
            -- 商品价格行
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
                    MarketPage._PriceCol("🟡 金价", goldPriceNow .. "/u", accent),
                    MarketPage._PriceCol("🟠 铜价", copperPriceNow .. "/u", C.paper_light),
                    MarketPage._PriceCol("⚫ 煤价", coalPriceNow .. "/u"
                        .. ((state.flags and state.flags.at_war) and " ⚔" or ""),
                        C.text_secondary),
                    MarketPage._PriceCol("📊 通胀", string.format("×%.2f", inflation),
                        inflation > 1.3 and C.accent_red or C.text_primary),
                },
            },
            -- 持仓汇总
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
        },
    }
end

-- ============================================================================
-- 贷款标签页内容
-- ============================================================================
function MarketPage._LoansTabContent(state, accent)
    local children = {}

    -- 贷款概览
    state.loans = state.loans or {}
    local totalDebt = GameState.CalcTotalDebt(state)
    local totalAssets = GameState.CalcTotalAssets(state)
    local leverage = GameState.CalcLeverage(state)
    local leveragePct = math.floor(leverage * 100)
    local maxLev = Balance.LOAN.max_leverage or 0.80
    local leverageColor = leverage >= maxLev and C.accent_red
        or (leverage >= maxLev * 0.6 and C.accent_amber or C.accent_green)

    table.insert(children, UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_card,
        flexDirection = "column",
        gap = 8,
        children = {
            -- 第一行：标题 + 贷款笔数
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "贷款总览",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = string.format("活跃 %d / %d 笔",
                            #state.loans, Balance.LOAN.max_active),
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                    },
                },
            },
            -- 第二行：资产/负债/杠杆
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    MarketPage._LoanDetailCol("总资产",
                        Config.FormatNumber(totalAssets), C.accent_green),
                    MarketPage._LoanDetailCol("总负债",
                        Config.FormatNumber(totalDebt),
                        totalDebt > 0 and C.accent_red or C.text_primary),
                    MarketPage._LoanDetailCol("杠杆率",
                        leveragePct .. "%", leverageColor),
                },
            },
            -- 破产风险提示（渐进式：清算→警告→破产）
            (state.loan_consecutive_defaults or 0) >= 2 and UI.Panel {
                width = "100%",
                padding = 6,
                backgroundColor = { 180, 40, 40, 40 },
                borderRadius = S.radius_btn,
                borderWidth = 1,
                borderColor = C.accent_red,
                gap = 2,
                children = {
                    UI.Label {
                        text = string.format("⚠ 已连续违约 %d 季（强制清算后仍无法偿付），达 %d 季将破产！",
                            state.loan_consecutive_defaults,
                            (Balance.LOAN.bankruptcy or {}).consecutive_defaults or 4),
                        fontSize = F.body_minor,
                        fontColor = C.accent_red,
                    },
                    UI.Label {
                        text = "提示：违约时系统会自动变卖黄金、降级矿山来偿付，仍不足才计入违约",
                        fontSize = F.label,
                        fontColor = C.text_tertiary,
                    },
                },
            } or nil,
            (state.negative_net_worth_turns or 0) >= 2 and UI.Panel {
                width = "100%",
                padding = 6,
                backgroundColor = { 180, 40, 40, 40 },
                borderRadius = S.radius_btn,
                borderWidth = 1,
                borderColor = C.accent_red,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = string.format("⚠ 净资产连续为负 %d 季，达 %d 季将破产！",
                            state.negative_net_worth_turns,
                            (Balance.LOAN.bankruptcy or {}).negative_net_worth_turns or 4),
                        fontSize = F.body_minor,
                        fontColor = C.accent_red,
                    },
                },
            } or nil,
        },
    })

    -- 现有贷款列表
    local loans = state.loans or {}
    if #loans > 0 then
        for i, loan in ipairs(loans) do
            local remainingInterest = math.ceil(loan.principal * loan.interest * loan.remaining_turns)
            table.insert(children, UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderLeftWidth = 2,
                borderLeftColor = C.accent_amber,
                flexDirection = "column",
                gap = 6,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = string.format("贷款 #%d", i),
                                fontSize = F.subtitle,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            UI.Panel {
                                flexDirection = "row",
                                gap = 4,
                                children = {
                                    (loan.rollovers and loan.rollovers > 0) and UI.Panel {
                                        backgroundColor = C.accent_red,
                                        borderRadius = S.radius_badge,
                                        paddingHorizontal = 6, paddingVertical = 2,
                                        children = {
                                            UI.Label {
                                                text = "已展期",
                                                fontSize = F.label,
                                                fontColor = { 255, 255, 255, 255 },
                                                pointerEvents = "none",
                                            },
                                        },
                                    } or nil,
                                    UI.Panel {
                                        backgroundColor = (loan.rollovers and loan.rollovers > 0)
                                            and C.accent_red or C.accent_amber,
                                        borderRadius = S.radius_badge,
                                        paddingHorizontal = 6, paddingVertical = 2,
                                        children = {
                                            UI.Label {
                                                text = string.format("剩 %d 季", loan.remaining_turns),
                                                fontSize = F.label,
                                                fontColor = { 255, 255, 255, 255 },
                                                pointerEvents = "none",
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        children = {
                            MarketPage._LoanDetailCol("本金",
                                Config.FormatNumber(loan.principal), C.text_primary),
                            MarketPage._LoanDetailCol("季利率",
                                string.format("%.1f%%", loan.interest * 100), C.accent_amber),
                            MarketPage._LoanDetailCol("每季利息",
                                Config.FormatNumber(math.ceil(loan.principal * loan.interest)),
                                C.accent_red),
                            MarketPage._LoanDetailCol("已付",
                                Config.FormatNumber(loan.total_paid or 0), C.accent_green),
                        },
                    },
                },
            })
        end
    else
        table.insert(children, UI.Panel {
            width = "100%",
            paddingVertical = 24,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "暂无活跃贷款",
                    fontSize = F.body,
                    fontColor = C.text_muted,
                },
            },
        })
    end

    -- 申请新贷款
    table.insert(children, UI.Panel {
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_card,
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Label {
                text = "申请贷款",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            MarketPage._LoanOptionsGrid(state, accent),
        },
    })

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.section_gap,
        children = children,
    }
end

--- 贷款详情列
function MarketPage._LoanDetailCol(label, value, color)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_secondary,
            },
            UI.Label {
                text = value,
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = color or C.text_primary,
            },
        },
    }
end

--- 贷款选项网格（动态额度 = 抵押价值 × ratio，利率根据杠杆动态调整）
function MarketPage._LoanOptionsGrid(state, accent)
    local collateralValue = GameState.CalcLoanCollateralValue(state)
    local totalDebt = GameState.CalcTotalDebt(state)
    local leverage = GameState.CalcLeverage(state)
    local maxLev = Balance.LOAN.max_leverage or 0.80
    local leverageMul = Balance.LOAN.leverage_interest_multiplier or 1.5
    local slotsLeft = Balance.LOAN.max_active - #(state.loans or {})
    local remainingCapacity = math.max(0, math.floor(collateralValue * maxLev - totalDebt))

    local optionCards = {}
    for _, opt in ipairs(Balance.LOAN.options) do
        -- 动态计算额度
        local calcAmount = math.max(
            opt.min_amount or 300,
            math.floor(collateralValue * (opt.amount_ratio or 0.15)))
        -- 动态利率
        local effectiveRate = (opt.base_interest or 0.04) * (1 + leverage * leverageMul)
        -- 能否借
        local canTake = slotsLeft > 0 and leverage < maxLev and calcAmount <= remainingCapacity

        table.insert(optionCards, UI.Panel {
            flexGrow = 1, flexBasis = 0,
            padding = 10,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = canTake and accent or C.paper_mid,
            flexDirection = "column",
            alignItems = "center",
            gap = 4,
            pointerEvents = "auto",
            opacity = canTake and 1.0 or 0.45,
            onPointerUp = (function(option, amount, rate)
                return Config.TapGuard(function(self)
                    MarketPage._OnTakeLoan(state, option, amount, rate)
                end)
            end)(opt, calcAmount, effectiveRate),
            children = {
                UI.Label {
                    text = opt.label or "贷款",
                    fontSize = F.body_minor,
                    fontWeight = "bold",
                    fontColor = C.text_secondary,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = Config.FormatNumber(calcAmount),
                    fontSize = F.card_title,
                    fontWeight = "bold",
                    fontColor = accent,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = string.format("利率 %.1f%%", effectiveRate * 100),
                    fontSize = F.body_minor,
                    fontColor = effectiveRate > 0.08 and C.accent_red or C.text_secondary,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = string.format("%d 季 | 息 %d/季",
                        opt.duration,
                        math.ceil(calcAmount * effectiveRate)),
                    fontSize = F.label,
                    fontColor = C.text_muted,
                    pointerEvents = "none",
                },
            },
        })
    end

    -- 杠杆过高警告
    if leverage >= maxLev then
        table.insert(optionCards, UI.Panel {
            width = "100%",
            paddingVertical = 8,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = string.format("杠杆率 %d%% 超过上限 %d%%，无法继续贷款",
                        math.floor(leverage * 100), math.floor(maxLev * 100)),
                    fontSize = F.body_minor,
                    fontColor = C.accent_red,
                },
            },
        })
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 8,
        children = optionCards,
    }
end

-- ============================================================================
-- 商品标签页内容
-- ============================================================================
function MarketPage._GoodsTabContent(state, accent)
    local inflation = state.inflation_factor or 1.0
    local BG = Balance.GOLD
    local BM = Balance.MINE
    -- 金价公式与 economy.lua Settle 保持一致
    local goldPriceCalc = BM.gold_price * (inflation ^ BG.price_inflation_exponent)
    if state.flags and state.flags.at_war then
        goldPriceCalc = goldPriceCalc * (1 + BG.war_premium)
    end
    local priceModifier = GameState.GetModifierValue and GameState.GetModifierValue(state, "military_industry_profit") or 0
    if priceModifier > 0 then goldPriceCalc = goldPriceCalc * (1 + priceModifier * 0.5) end
    local goldPriceBonus = state.gold_price_bonus or 0
    if goldPriceBonus > 0 then goldPriceCalc = goldPriceCalc * (1 + goldPriceBonus) end
    local goldPriceMod = GameState.GetModifierValue and GameState.GetModifierValue(state, "gold_price_mod") or 0
    if goldPriceMod ~= 0 then goldPriceCalc = goldPriceCalc * (1 + goldPriceMod) end
    local goldPriceNow = math.floor(goldPriceCalc)
    local copperPriceMod = GameState.GetModifierValue and GameState.GetModifierValue(state, "copper_price_mod") or 0
    local copperPriceNow = math.max(1, math.floor(BM.copper_price * inflation * (1 + copperPriceMod)))
    local BCOAL = Balance.COAL or {}
    local coalPriceMod = GameState.GetModifierValue and GameState.GetModifierValue(state, "coal_price_mod") or 0
    local coalPriceNow = BM.coal_price * inflation * (1 + coalPriceMod)
    if state.flags and state.flags.at_war then
        coalPriceNow = coalPriceNow * (1 + (BCOAL.war_price_premium or 0.5))
    end
    coalPriceNow = math.max(1, math.floor(coalPriceNow))

    -- 库存信息
    local goldStock = state.gold or 0
    local copperStock = state.copper or 0
    local coalStock = state.coal or 0
    local goldValue = goldStock * goldPriceNow
    local copperValue = copperStock * copperPriceNow
    local coalValue = coalStock * coalPriceNow

    -- 铜维护减免
    local BCOPPER = Balance.COPPER or {}
    local copperReduction = 0
    if copperStock >= 10 then
        copperReduction = math.min(
            BCOPPER.maintenance_reduction_cap or 0.25,
            math.floor(copperStock / 10) * (BCOPPER.maintenance_reduction_per_10 or 0.05))
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = S.section_gap,
        children = {
            -- 市场行情
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.bg_surface,
                borderRadius = S.radius_card,
                flexDirection = "column",
                gap = 8,
                children = {
                    UI.Label {
                        text = "商品行情",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 8,
                        children = {
                            MarketPage._GoodsPriceCard("🟡", "黄金",
                                goldPriceNow .. " 克朗/单位",
                                accent, inflation),
                            MarketPage._GoodsPriceCard("🟠", "铜",
                                copperPriceNow .. " 克朗/单位",
                                C.paper_light, inflation),
                            MarketPage._GoodsPriceCard("⚫", "煤炭",
                                coalPriceNow .. " 克朗/单位"
                                .. ((state.flags and state.flags.at_war) and " ⚔" or ""),
                                C.text_secondary, inflation),
                        },
                    },
                    -- 通胀指标
                    UI.Panel {
                        width = "100%",
                        paddingVertical = 8,
                        paddingHorizontal = S.card_padding,
                        backgroundColor = C.bg_elevated,
                        borderRadius = S.radius_btn,
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "📊 通胀系数",
                                fontSize = F.body,
                                fontColor = C.text_secondary,
                            },
                            UI.Label {
                                text = string.format("×%.2f", inflation),
                                fontSize = F.subtitle,
                                fontWeight = "bold",
                                fontColor = inflation > 1.3 and C.accent_red
                                    or (inflation > 1.1 and C.accent_amber or C.accent_green),
                            },
                        },
                    },
                },
            },

            -- 商品总市值
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                backgroundColor = C.paper_dark,
                borderRadius = S.radius_card,
                borderLeftWidth = 2,
                borderLeftColor = accent,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "商品总市值",
                        fontSize = F.body,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = Config.FormatNumber(goldValue + copperValue + coalValue) .. " 克朗",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = accent,
                    },
                },
            },

            -- 黄金交易卡
            MarketPage._GoodsTradeCard(state, {
                icon = "🟡", name = "黄金",
                stateKey = "gold", autoSellKey = "gold_auto_sell",
                stock = goldStock, price = goldPriceNow, value = goldValue,
                color = accent,
                autoSellDesc = "每季自动售出，保留10%库存",
                hint = "囤积可对冲通胀，金价随通胀超线性增长",
            }),

            -- 铜交易卡
            MarketPage._GoodsTradeCard(state, {
                icon = "🟠", name = "铜",
                stateKey = "copper", autoSellKey = "copper_auto_sell",
                stock = copperStock, price = copperPriceNow, value = copperValue,
                color = { 184, 115, 51, 255 },
                autoSellDesc = "每季自动售出全部铜",
                hint = "高级装备原料，持有可降低装备维护费",
                copperReduction = copperReduction,
            }),

            -- 煤炭交易卡
            MarketPage._GoodsTradeCard(state, {
                icon = "⚫", name = "煤炭",
                stateKey = "coal", autoSellKey = "coal_auto_sell",
                stock = coalStock, price = coalPriceNow, value = coalValue,
                color = { 140, 130, 120, 255 },
                autoSellDesc = "每季自动售出剩余煤炭",
                hint = "兵工厂燃料，也可分配给矿山。战时价格上涨",
                warTag = (state.flags and state.flags.at_war) and " ⚔战时+50%" or nil,
            }),
        },
    }
end

--- 商品价格卡片
function MarketPage._GoodsPriceCard(icon, name, priceText, color, inflation)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        padding = 10,
        backgroundColor = C.bg_elevated,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        alignItems = "center",
        gap = 4,
        children = {
            UI.Label { text = icon, fontSize = 24 },
            UI.Label {
                text = name,
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Label {
                text = priceText,
                fontSize = F.body_minor,
                fontColor = color,
            },
        },
    }
end

--- 通用商品交易卡片（黄金/铜/煤）
--- @param state table 游戏状态
--- @param opts table { icon, name, stateKey, autoSellKey, stock, price, value, color,
---                      autoSellDesc, hint, copperReduction?, warTag? }
function MarketPage._GoodsTradeCard(state, opts)
    local stock = opts.stock
    local price = opts.price
    local railwayBlocked = GameState.GetModifierValue(state, "railway_blocked") > 0
    local canSell = stock > 0 and not railwayBlocked

    -- 出售数量（闭包状态）
    local sellQty = math.min(5, stock)
    local qtyLabel, revenueLabel, sellBtn

    local function refreshSellUI()
        if not stateRef_ then return end
        local curStock = stateRef_[opts.stateKey] or 0
        sellQty = math.max(0, math.min(sellQty, curStock))
        if qtyLabel then qtyLabel:SetText(tostring(sellQty)) end
        if revenueLabel then
            revenueLabel:SetText(string.format("预计收入：💰%d", sellQty * price))
        end
        if sellBtn then
            local ok = sellQty > 0 and sellQty <= curStock
            sellBtn:SetText(ok
                and string.format("出售 %d → 💰%d", sellQty, sellQty * price)
                or "无法出售")
        end
    end

    local function adjustQty(delta)
        if not stateRef_ then return end
        local curStock = stateRef_[opts.stateKey] or 0
        sellQty = math.max(1, math.min(curStock, sellQty + delta))
        refreshSellUI()
    end

    -- 数量标签
    qtyLabel = UI.Label {
        text = tostring(sellQty),
        fontSize = F.card_title,
        fontWeight = "bold",
        fontColor = C.text_primary,
        textAlign = "center",
        minWidth = 40,
    }

    -- 收入预估
    revenueLabel = UI.Label {
        text = string.format("预计收入：💰%d", sellQty * price),
        fontSize = F.label,
        fontColor = C.accent_gold,
    }

    -- 出售按钮
    sellBtn = UI.Button {
        text = canSell
            and string.format("出售 %d → 💰%d", sellQty, sellQty * price)
            or (railwayBlocked and "🚂 铁路瘫痪" or "无库存"),
        fontSize = F.body_minor,
        height = S.btn_small_height,
        width = "100%",
        variant = canSell and "primary" or "outlined",
        disabled = not canSell,
        backgroundColor = canSell and C.accent_gold or nil,
        fontColor = canSell and C.bg_base or C.text_muted,
        borderRadius = S.radius_btn,
        onClick = Config.ClickGuard(function(self)
            MarketPage._OnSellGoods(opts.stateKey, opts.name, price, sellQty)
        end),
    }

    -- 数量按钮工厂
    local function qtyBtn(label, delta)
        return UI.Panel {
            width = 34, height = 30,
            borderRadius = S.radius_btn,
            backgroundColor = C.bg_elevated,
            borderWidth = 1, borderColor = C.paper_light,
            justifyContent = "center", alignItems = "center",
            pointerEvents = "auto",
            onPointerUp = Config.TapGuard(function() adjustQty(delta) end),
            children = {
                UI.Label {
                    text = label, fontSize = F.body,
                    fontColor = C.text_primary, pointerEvents = "none",
                },
            },
        }
    end

    -- 自动出售开关
    local isAutoOn = state[opts.autoSellKey] or false
    local autoBtn
    autoBtn = UI.Button {
        text = isAutoOn and "已开启" or "已关闭",
        fontSize = F.label,
        fontWeight = "bold",
        fontColor = isAutoOn and C.accent_green or C.text_muted,
        backgroundColor = isAutoOn
            and { C.accent_green[1], C.accent_green[2], C.accent_green[3], 40 }
            or C.bg_elevated,
        borderRadius = S.radius_btn,
        borderWidth = 1,
        borderColor = isAutoOn and C.accent_green or C.border_card,
        paddingHorizontal = 10,
        paddingVertical = 4,
        onClick = Config.ClickGuard(function()
            if not stateRef_ then return end
            stateRef_[opts.autoSellKey] = not stateRef_[opts.autoSellKey]
            local on = stateRef_[opts.autoSellKey]
            autoBtn:SetText(on and "已开启" or "已关闭")
            autoBtn:SetStyle({
                fontColor = on and C.accent_green or C.text_muted,
                backgroundColor = on
                    and { C.accent_green[1], C.accent_green[2], C.accent_green[3], 40 }
                    or C.bg_elevated,
                borderColor = on and C.accent_green or C.border_card,
            })
            if onLightRefresh_ then onLightRefresh_() end
        end),
    }

    -- 卡片子元素
    local cardChildren = {
        -- 标题行：图标 + 名称 + 库存
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label { text = opts.icon, fontSize = 18 },
                        UI.Label {
                            text = opts.name,
                            fontSize = F.subtitle,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "column", alignItems = "flex-end", gap = 1,
                    children = {
                        UI.Label {
                            text = stock .. " 单位",
                            fontSize = F.subtitle,
                            fontWeight = "bold",
                            fontColor = opts.color,
                        },
                        UI.Label {
                            text = "市值 " .. Config.FormatNumber(opts.value)
                                .. (opts.warTag or ""),
                            fontSize = F.label,
                            fontColor = C.text_muted,
                        },
                    },
                },
            },
        },
        -- 单价
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "单价",
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                },
                UI.Label {
                    text = price .. " 克朗/单位",
                    fontSize = F.body_minor,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
            },
        },
    }

    -- 铜维护减免提示
    if opts.copperReduction and opts.copperReduction > 0 then
        table.insert(cardChildren, UI.Label {
            text = string.format("持铜效果：装备维护费 -%d%%",
                math.floor(opts.copperReduction * 100)),
            fontSize = F.label,
            fontColor = C.accent_green,
        })
    end

    -- 提示文字
    table.insert(cardChildren, UI.Label {
        text = "💡 " .. opts.hint,
        fontSize = F.label,
        fontColor = C.text_muted,
        whiteSpace = "normal",
    })

    -- 分隔线
    table.insert(cardChildren, UI.Divider { color = C.divider })

    -- 自动出售行
    table.insert(cardChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Panel {
                flexDirection = "column", flexShrink = 1, gap = 1,
                children = {
                    UI.Label {
                        text = "自动出售",
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                    },
                    UI.Label {
                        text = opts.autoSellDesc,
                        fontSize = 10,
                        fontColor = C.text_muted,
                    },
                },
            },
            autoBtn,
        },
    })

    -- 手动出售区（有库存时显示）
    if canSell then
        table.insert(cardChildren, UI.Panel {
            width = "100%",
            flexDirection = "column",
            gap = 6,
            children = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    justifyContent = "center",
                    gap = 6,
                    children = {
                        qtyBtn("-10", -10),
                        qtyBtn("-1", -1),
                        qtyLabel,
                        qtyBtn("+1", 1),
                        qtyBtn("+10", 10),
                    },
                },
                -- 快捷：半数 / 全部
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 8,
                    justifyContent = "center",
                    children = {
                        UI.Panel {
                            paddingHorizontal = 12, paddingVertical = 4,
                            borderRadius = S.radius_btn,
                            backgroundColor = C.bg_elevated,
                            borderWidth = 1, borderColor = C.paper_light,
                            pointerEvents = "auto",
                            onPointerUp = Config.TapGuard(function()
                                if stateRef_ then
                                    sellQty = math.max(1, math.floor(
                                        (stateRef_[opts.stateKey] or 0) / 2))
                                    refreshSellUI()
                                end
                            end),
                            children = {
                                UI.Label {
                                    text = "半数", fontSize = F.label,
                                    fontColor = C.text_secondary, pointerEvents = "none",
                                },
                            },
                        },
                        UI.Panel {
                            paddingHorizontal = 12, paddingVertical = 4,
                            borderRadius = S.radius_btn,
                            backgroundColor = C.bg_elevated,
                            borderWidth = 1, borderColor = C.paper_light,
                            pointerEvents = "auto",
                            onPointerUp = Config.TapGuard(function()
                                if stateRef_ then
                                    sellQty = stateRef_[opts.stateKey] or 0
                                    refreshSellUI()
                                end
                            end),
                            children = {
                                UI.Label {
                                    text = "全部", fontSize = F.label,
                                    fontColor = C.text_secondary, pointerEvents = "none",
                                },
                            },
                        },
                    },
                },
                revenueLabel,
            },
        })
    end

    -- 出售按钮
    table.insert(cardChildren, sellBtn)

    return UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 8,
        children = cardChildren,
    }
end

--- 手动出售商品（通用）
function MarketPage._OnSellGoods(stateKey, name, price, amount)
    if not stateRef_ then return end

    -- 铁路瘫痪检查
    if GameState.GetModifierValue(stateRef_, "railway_blocked") > 0 then
        UI.Toast.Show("🚂 铁路瘫痪，无法运出！", { variant = "error", duration = 2 })
        return
    end

    local curStock = stateRef_[stateKey] or 0
    if curStock <= 0 then
        UI.Toast.Show("没有" .. name .. "可出售", { variant = "warning", duration = 1.5 })
        return
    end

    amount = math.max(1, math.min(amount or curStock, curStock))
    local revenue = amount * price
    stateRef_[stateKey] = curStock - amount
    stateRef_.cash = stateRef_.cash + revenue

    GameState.AddLog(stateRef_, string.format("手动出售 %d 单位%s，获得 %d", amount, name, revenue))
    UI.Toast.Show(string.format("出售 %d %s → 💰+%d", amount, name, revenue),
        { variant = "success", duration = 2 })

    if onStateChanged_ then onStateChanged_() end
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
-- 金价 / 铜价 / 通胀列
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

    -- 公允价值 vs 当前价格 → 估值标签
    local valuationTag = ""
    local valuationColor = C.text_muted

    -- 持仓标记
    local holding = state.portfolio and state.portfolio.holdings
        and state.portfolio.holdings[stock.id]
    local holdingText = holding and string.format(" 持%d", holding.shares) or ""
    local holdingLevel = StockEngine.GetHoldingLevel and StockEngine.GetHoldingLevel(state, stock.id) or "none"
    local holdingLevelText = StockEngine.GetHoldingLevelLabel
        and StockEngine.GetHoldingLevelLabel(holdingLevel) or ""

    return UI.Panel {
        width = "100%",
        paddingVertical = 10,
        paddingHorizontal = S.card_padding,
        backgroundColor = bgColor,
        flexDirection = "row",
        alignItems = "center",
        pointerEvents = "auto",
        onPointerUp = Config.TapGuard(function(self)
            MarketPage._OpenTradeModal(state, stock, accent)
        end),
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
                                text = holdingLevel ~= "none"
                                    and (sectorLabel .. " · " .. holdingLevelText .. valuationTag)
                                    or (sectorLabel .. valuationTag),
                                fontSize = F.label,
                                fontColor = valuationTag ~= "" and valuationColor or C.text_muted,
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
function MarketPage._TabUnderline(label, active, accent, tabId)
    return UI.Panel {
        flexGrow = 1, flexBasis = 0,
        paddingVertical = 10,
        justifyContent = "center", alignItems = "center",
        borderBottomWidth = active and 2 or 0,
        borderBottomColor = accent,
        pointerEvents = "auto",
        onPointerUp = Config.TapGuard(function(self)
            if tabId and activeTab_ ~= tabId then
                activeTab_ = tabId
                if onStateChanged_ then onStateChanged_() end
            end
        end),
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
        tradeModal_:Close() -- onClose 回调负责 Destroy 和置 nil
    end

    -- 安全网：强制隐藏系统键盘 & 清除残留焦点，防止上一个弹窗的
    -- TextField 焦点/键盘状态泄漏到新弹窗
    input:SetScreenKeyboardVisible(false)
    UI.ClearFocus()

    -- 内部数量状态（闭包）
    local qty = 10
    local qtyInput

    local function refreshQty()
        if qtyInput then qtyInput:SetValue(tostring(qty)) end
    end

    local function adjustQty(delta)
        qty = math.max(1, qty + delta)
        refreshQty()
    end

    local holding = state.portfolio and state.portfolio.holdings
        and state.portfolio.holdings[stock.id]
    local holdingShares = (holding and holding.shares) or 0

    qtyInput = UI.TextField {
        value = tostring(qty),
        fontSize = F.card_title,
        width = 80, height = 36,
        textAlign = "center",
        maxLength = 6,
        placeholder = "数量",
        onChange = function(self, val)
            local n = tonumber(val)
            if n and n >= 1 then
                qty = math.floor(n)
            elseif val == "" then
                qty = 1
            end
        end,
        onSubmit = function(self, val)
            local n = tonumber(val)
            if n and n >= 1 then
                qty = math.floor(n)
            else
                qty = 1
            end
            refreshQty()
        end,
    }

    tradeModal_ = UI.Modal {
        title = stock.name,
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            UI.ClearFocus()                        -- 清焦点 → TextField:OnBlur
            input:SetScreenKeyboardVisible(false)  -- 保底：确保键盘一定关闭
            tradeModal_ = nil
            self:Destroy()
        end,
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
            -- 板块信息
            UI.Label {
                text = string.format("板块：%s", SECTOR_NAMES[stock.sector] or ""),
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
                    MarketPage._QtyBtn("-100", function() adjustQty(-100) end),
                    MarketPage._QtyBtn("-10", function() adjustQty(-10) end),
                    qtyInput,
                    MarketPage._QtyBtn("+10", function() adjustQty(10) end),
                    MarketPage._QtyBtn("+100", function() adjustQty(100) end),
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
            -- 梭哈 + 全仓快捷
            UI.Panel {
                flexDirection = "row",
                gap = 8,
                children = {
                    MarketPage._ActionBtn("🔥 梭哈", C.accent_gold, function()
                        local maxQty = math.floor((state.cash or 0) / stock.price)
                        if maxQty >= 1 then
                            MarketPage._OnBuy(state, stock.id, maxQty)
                        else
                            UI.Toast.Show("现金不足，无法买入", { variant = "error", duration = 1.5 })
                        end
                    end),
                    holdingShares > 0
                        and MarketPage._ActionBtn("全部卖出 (×" .. holdingShares .. ")",
                            C.accent_amber, function()
                                MarketPage._OnSell(state, stock.id, holdingShares)
                            end)
                        or UI.Panel { width = 0, height = 0 },
                },
            },
        },
    }
    tradeModal_:AddContent(content)
    -- Modal 必须加入 UI 树才能渲染
    if uiRoot_ then
        uiRoot_:AddChild(tradeModal_)
    end
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
        onPointerUp = Config.TapGuard(function(self) onClick() end),
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
        onPointerUp = Config.TapGuard(function(self) onClick() end),
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
        if tradeModal_ then tradeModal_:Close() end -- onClose 回调负责 Destroy 和置 nil
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
        if tradeModal_ then tradeModal_:Close() end -- onClose 回调负责 Destroy 和置 nil
        if onStateChanged_ then onStateChanged_() end
    else
        UI.Toast.Show(msg or "卖出失败", { variant = "error", duration = 1.5 })
    end
end

function MarketPage._OnTakeLoan(state, opt, calcAmount, effectiveRate)
    state.loans = state.loans or {}
    if #state.loans >= Balance.LOAN.max_active then
        UI.Toast.Show("贷款数量已达上限（" .. Balance.LOAN.max_active .. "）",
            { variant = "warning", duration = 1.5 })
        return
    end
    -- 杠杆检查
    local leverage = GameState.CalcLeverage(state)
    local maxLev = Balance.LOAN.max_leverage or 0.80
    if leverage >= maxLev then
        UI.Toast.Show(string.format("杠杆率 %d%% 已超上限 %d%%，无法贷款",
            math.floor(leverage * 100), math.floor(maxLev * 100)),
            { variant = "error", duration = 2 })
        return
    end
    local collateralValue = GameState.CalcLoanCollateralValue(state)
    local remainingCapacity = math.max(0,
        math.floor(collateralValue * maxLev - GameState.CalcTotalDebt(state)))
    if calcAmount > remainingCapacity then
        UI.Toast.Show("抵押额度不足，无法申请该档贷款",
            { variant = "error", duration = 1.5 })
        return
    end
    state.cash = state.cash + calcAmount
    table.insert(state.loans, {
        principal       = calcAmount,
        interest        = opt.base_interest or effectiveRate,  -- 存 base_interest，结算时动态计算
        remaining_turns = opt.duration,
        total_paid      = 0,
        rollovers       = 0,
    })
    GameState.AddLog(state, string.format("[贷款] 借入 %s（%s），%d 季后到期，当前利率 %.1f%%",
        Config.FormatNumber(calcAmount), opt.label or "贷款",
        opt.duration, effectiveRate * 100))
    UI.Toast.Show(string.format("借入 %s 克朗", Config.FormatNumber(calcAmount)),
        { variant = "success", duration = 1.5 })
    if onStateChanged_ then onStateChanged_() end
end

function MarketPage.Refresh(root, state)
    stateRef_ = state
end

return MarketPage
