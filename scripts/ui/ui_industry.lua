-- ============================================================================
-- 产业页 UI：矿山信息、工人管理、生产预估、操作按钮
-- 设计规范：sarajevo_dynasty_ui_spec §6.3
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Balance = require("data.balance")
local RegionsData = require("data.regions_data")
local Economy = require("systems.economy")
local Actions = require("systems.actions")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local BM = Balance.MINE
local BW = Balance.WORKERS

local IndustryPage = {}

--- 计算当前黄金实际单价（与自动售出逻辑保持一致）
---@param state table
---@return number price 每单位黄金的实际售价（已取整）
local function calcGoldPrice(state)
    local inflation = GameState.GetInflationFactor(state)
    local price = BM.gold_price * inflation
    -- 战时军需利润修正
    local priceModifier = GameState.GetModifierValue(state, "military_industry_profit")
    if priceModifier > 0 then
        price = price * (1 + priceModifier * 0.5)
    end
    -- 科技金价加成
    local goldPriceBonus = state.gold_price_bonus or 0
    if goldPriceBonus > 0 then
        price = price * (1 + goldPriceBonus)
    end
    -- 事件独立金价修正
    local goldPriceMod = GameState.GetModifierValue(state, "gold_price_mod")
    if goldPriceMod ~= 0 then
        price = price * (1 + goldPriceMod)
    end
    return math.floor(price)
end

---@type table 游戏状态引用
local stateRef_ = nil
---@type function|nil 状态变化回调
local onStateChanged_ = nil

--- 创建产业页完整内容
---@param state table
---@param callbacks table { onStateChanged = function }
---@return table widget
function IndustryPage.Create(state, callbacks)
    stateRef_ = state
    onStateChanged_ = callbacks and callbacks.onStateChanged

    return IndustryPage._BuildContent(state)
end

--- 构建页面内容
function IndustryPage._BuildContent(state)
    local children = {}

    -- 1. 收支预估卡片
    table.insert(children, IndustryPage._CreateEstimateCard(state))

    -- 2. 探矿卡片
    table.insert(children, IndustryPage._CreateProspectCard(state))

    -- 3. 矿山卡片（遍历所有矿山）
    for _, mine in ipairs(state.mines) do
        table.insert(children, IndustryPage._CreateMineCard(state, mine))
    end

    -- 4. 工人管理卡片
    table.insert(children, IndustryPage._CreateWorkerCard(state))

    -- 4. 操作按钮区
    table.insert(children, IndustryPage._CreateActionCard(state))

    return UI.Panel {
        id = "industryContent",
        width = "100%",
        flexDirection = "column",
        gap = S.card_gap,
        children = children,
    }
end

--- 收支预估卡片（§6.3 资产卡片样式）
function IndustryPage._CreateEstimateCard(state)
    local estIncome, estExpense, estimateDetails = Economy.GetEstimate(state)
    local estNet = estIncome - estExpense
    local netColor = estNet >= 0 and C.accent_green or C.accent_red
    local inflation = state.inflation_factor or 1.0
    local inflColor = inflation > 1.3 and C.accent_red
        or (inflation > 1.1 and C.accent_amber or C.text_primary)

    return UI.Panel {
        id = "estimateCard",
        width = "100%",
        padding = S.card_padding,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_gold,
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Label {
                text = "本季预估",
                fontSize = F.card_title,
                fontWeight = "bold",
                fontColor = C.accent_gold,
            },
            UI.Divider { color = C.divider },
            -- 收支三列
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    IndustryPage._EstimateItem("预估收入", "+" .. estIncome, C.accent_green),
                    IndustryPage._EstimateItem("预估支出", "-" .. estExpense, C.accent_red),
                    IndustryPage._EstimateItem("净利润",
                        (estNet >= 0 and "+" or "") .. estNet, netColor),
                },
            },
            -- 副指标：白银库存 + 煤炭库存 + 通胀倍率
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                flexWrap = "wrap",
                gap = 4,
                children = {
                    IndustryPage._EstimateItem("⚪ 白银库存",
                        tostring(state.silver or 0) .. " 单位", C.paper_light),
                    IndustryPage._EstimateItem("⚫ 煤炭库存",
                        tostring(state.coal or 0) .. " 单位", { 140, 130, 120, 255 }),
                    IndustryPage._EstimateItem("潜在售金",
                        "+" .. (estimateDetails.gold_potential_income or 0), C.accent_gold),
                    IndustryPage._EstimateItem("📊 通胀倍率",
                        string.format("×%.2f", inflation), inflColor),
                },
            },
        },
    }
end

--- 预估项小组件
function IndustryPage._EstimateItem(label, value, color)
    return UI.Panel {
        flexDirection = "column",
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = value,
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = color,
            },
            UI.Label {
                text = label,
                fontSize = F.label,
                fontColor = C.text_muted,
            },
        },
    }
end

--- 矿山卡片（§6.3 资产卡片样式）
function IndustryPage._CreateMineCard(state, mine)
    local region = GameState.GetRegion(state, mine.region_id)
    local mineReserve = mine.reserve or 0
    local security = region and region.security or 0
    local secText = RegionsData.GetSecurityText(security)

    -- 计算当前产出
    local currentOutput = Economy._CalcMineOutput(state, mine)
    local isDepleted = mineReserve <= 0
    local isMigrating = mine.migrating == true

    -- 矿业总监加成
    local directorBonus = GameState.GetPositionBonus(state, "mine_director")
    local directorMember = GameState.GetMemberAtPosition(state, "mine_director")
    local directorName = directorMember and directorMember.name or "空缺"
    local directorColor = directorMember and C.accent_green or C.accent_red

    -- 白银储量
    local silverReserve = region and region.resources.silver_reserve or 0

    -- 升级费用
    local upgradeCost = math.floor(BM.upgrade_cost * mine.level * GameState.GetAssetPriceFactor(state))
    local availAP = state.ap.current + (state.ap.temp or 0)
    local canUpgrade = mine.level < BM.max_level and state.cash >= upgradeCost
        and availAP >= 1 and not isDepleted and not isMigrating

    -- 状态标签
    local statusText = isMigrating and "🔄 迁移中" or (isDepleted and "⚠️ 储量耗尽" or nil)

    -- 底部操作区
    local bottomChildren = {}
    if isMigrating then
        -- 迁移中：显示提示
        table.insert(bottomChildren, UI.Label {
            text = "产能迁移进行中，下季度完成",
            fontSize = F.body_minor,
            fontColor = C.accent_blue,
            textAlign = "center",
            width = "100%",
        })
    elseif isDepleted then
        -- 耗尽：3 个处置按钮
        local depCfg = Balance.MINE.depletion or {}
        local migrateCost = math.floor((depCfg.migrate_cash_ratio or 0.5) * (Balance.TRADE.new_mine.cash or 1200)
            * GameState.GetAssetPriceFactor(state))
        local migrateAP = depCfg.migrate_ap or 1
        -- 是否有可迁移目标
        local hasTarget = false
        for _, m in ipairs(state.mines) do
            if m ~= mine and m.active and not m.migrating and (m.reserve or 0) > 0 then
                hasTarget = true; break
            end
        end
        local canMigrate = hasTarget and state.cash >= migrateCost and availAP >= migrateAP

        local cleanupCost = math.floor((depCfg.cleanup_cost_per_level or 200) * mine.level
            * GameState.GetAssetPriceFactor(state))
        local canCleanup = state.cash >= cleanupCost

        table.insert(bottomChildren, UI.Label {
            text = "矿山储量耗尽，请选择处置方式：",
            fontSize = F.body_minor,
            fontWeight = "bold",
            fontColor = C.accent_red,
            width = "100%",
        })
        -- 产能迁移
        table.insert(bottomChildren, UI.Button {
            text = canMigrate
                and string.format("🔄 产能迁移 (💰%d ⚡%d)", migrateCost, migrateAP)
                or (not hasTarget and "🔄 无可用目标矿山"
                or string.format("🔄 产能迁移 (💰%d ⚡%d) 资源不足", migrateCost, migrateAP)),
            fontSize = F.body_minor,
            height = S.btn_small_height,
            width = "100%",
            variant = canMigrate and "primary" or "outlined",
            disabled = not canMigrate,
            backgroundColor = canMigrate and C.accent_blue or nil,
            borderRadius = S.radius_btn,
            onClick = function(self)
                self.props.disabled = true
                IndustryPage._OnMigrateMine(mine, migrateCost, migrateAP)
            end,
        })
        -- 善后处理
        table.insert(bottomChildren, UI.Button {
            text = canCleanup
                and string.format("🧹 善后处理 (💰%d)", cleanupCost)
                or string.format("🧹 善后处理 (💰%d) 资金不足", cleanupCost),
            fontSize = F.body_minor,
            height = S.btn_small_height,
            width = "100%",
            variant = canCleanup and "primary" or "outlined",
            disabled = not canCleanup,
            backgroundColor = canCleanup and C.accent_amber or nil,
            borderRadius = S.radius_btn,
            onClick = function(self)
                self.props.disabled = true
                IndustryPage._OnCleanupMine(mine, cleanupCost)
            end,
        })
        -- 搁置不管
        table.insert(bottomChildren, UI.Button {
            text = "🚫 搁置不管（免费，影响力-5 士气-3）",
            fontSize = F.body_minor,
            height = S.btn_small_height,
            width = "100%",
            variant = "outlined",
            fontColor = C.accent_red,
            borderRadius = S.radius_btn,
            onClick = function(self)
                self.props.disabled = true
                IndustryPage._OnAbandonMine(mine)
            end,
        })
    else
        -- 正常：升级按钮
        table.insert(bottomChildren, UI.Button {
            id = "upgradeMine_" .. mine.id,
            text = mine.level >= BM.max_level and "已满级"
                or string.format("升级矿山 (💰%d ⚡1)", upgradeCost),
            fontSize = F.body_minor,
            height = S.btn_small_height,
            width = "100%",
            variant = canUpgrade and "primary" or "outlined",
            disabled = not canUpgrade,
            backgroundColor = canUpgrade and C.accent_amber or nil,
            fontColor = canUpgrade and C.bg_base or C.text_muted,
            borderRadius = S.radius_btn,
            onClick = function(self)
                self.props.disabled = true
                Actions.UpgradeMine(stateRef_, mine, onStateChanged_)
            end,
        })
    end

    return UI.Panel {
        id = "mineCard_" .. mine.id,
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = isDepleted and C.accent_red or C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 标题栏
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                backgroundColor = C.bg_elevated,
                children = {
                    UI.Panel {
                        width = 56,
                        height = 56,
                        backgroundColor = C.paper_mid,
                        borderRadius = S.radius_card,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = isDepleted and "⚠️" or "⛏️",
                                fontSize = 24,
                            },
                        },
                    },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = mine.name,
                                fontSize = F.subtitle,
                                fontWeight = "bold",
                                fontColor = isDepleted and C.accent_red or C.accent_gold,
                            },
                            UI.Label {
                                text = statusText or ("等级 " .. mine.level .. "/" .. BM.max_level),
                                fontSize = F.label,
                                fontColor = isDepleted and C.accent_red or C.text_secondary,
                            },
                        },
                    },
                    -- 产出徽章
                    UI.Panel {
                        flexDirection = "column",
                        alignItems = "flex-end",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = (isDepleted and "0" or tostring(currentOutput)) .. "/季",
                                fontSize = F.data_small,
                                fontWeight = "bold",
                                fontColor = isDepleted and C.text_muted or C.accent_amber,
                            },
                            UI.Label {
                                text = "产金",
                                fontSize = F.label,
                                fontColor = C.text_muted,
                            },
                        },
                    },
                },
            },

            -- 详细信息
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "column",
                gap = 6,
                children = {
                    -- 矿山独立储量
                    IndustryPage._InfoRow("矿山储量", mineReserve .. " 单位",
                        isDepleted and C.accent_red or (mineReserve < 100 and C.accent_amber or C.text_primary)),
                    UI.ProgressBar {
                        value = math.min(1, mineReserve / (Balance.TRADE.new_mine.base_reserve or 1500)),
                        width = "100%",
                        height = 6,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = isDepleted and C.accent_red or (mineReserve < 100 and C.accent_amber or C.accent_gold),
                    },
                    -- 白银储量（共享 region）
                    IndustryPage._InfoRow("白银储量", silverReserve .. " 单位",
                        silverReserve < 100 and C.accent_red or C.text_secondary),
                    UI.ProgressBar {
                        value = math.min(1, silverReserve / 500),
                        width = "100%",
                        height = 6,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = silverReserve < 100 and C.accent_red or { 192, 192, 192, 255 },
                    },
                    -- 治安
                    IndustryPage._InfoRow("矿区治安", secText,
                        security <= 2 and C.accent_red or (security >= 4 and C.accent_green or C.accent_amber)),
                    -- 矿业总监
                    IndustryPage._InfoRow("矿业总监", directorName, directorColor),
                    -- 总监加成
                    IndustryPage._InfoRow("岗位加成",
                        string.format("%+d%%", math.floor(directorBonus * 100)),
                        directorBonus >= 0 and C.accent_green or C.accent_red),
                },
            },

            UI.Divider { color = C.divider },

            -- 底部操作区
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "column",
                gap = 6,
                children = bottomChildren,
            },
        },
    }
end

--- 探矿卡片
function IndustryPage._CreateProspectCard(state)
    local cfg = Balance.MINE.prospect
    local reserves = state.prospect_reserves or {}
    local prospecting = state.prospecting
    local availAP = state.ap.current + (state.ap.temp or 0)
    local maxMines = (Balance.TRADE.new_mine.max_mines or 4) + (state.mine_slots_bonus or 0)
    local prospectCost = math.floor(cfg.cash * GameState.GetAssetPriceFactor(state))

    -- 当前成功率
    local successCount = state.prospect_success_count or 0
    local baseChance = math.max(cfg.min_success,
        cfg.base_success - cfg.success_decay * successCount)
    local techBonus = state.prospect_success_bonus or 0
    local currentChance = math.min(1.0, baseChance + techBonus)

    local children = {}

    -- 标题栏
    table.insert(children, UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Label {
                text = "探矿",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            UI.Panel { flexGrow = 1 },
            UI.Chip {
                label = string.format("成功率 %d%%", math.floor(currentChance * 100)),
                color = currentChance >= 0.2 and "success" or (currentChance >= 0.1 and "warning" or "error"),
                variant = "soft",
                size = "sm",
            },
        },
    })

    -- 探矿中：进度显示
    if prospecting then
        local remaining = prospecting.total - prospecting.progress
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "column",
            gap = 6,
            children = {
                IndustryPage._InfoRow("探矿进度",
                    string.format("%d / %d 季度", prospecting.progress, prospecting.total),
                    C.accent_blue),
                UI.ProgressBar {
                    value = prospecting.progress / prospecting.total,
                    width = "100%",
                    height = 8,
                    borderRadius = 4,
                    trackColor = C.bg_surface,
                    fillColor = C.accent_blue,
                },
                UI.Label {
                    text = string.format("预计 %d 季度后出结果（成功率 %d%%）",
                        remaining, math.floor(prospecting.success_chance * 100)),
                    fontSize = F.label,
                    fontColor = C.text_muted,
                },
            },
        })
    else
        -- 空闲：启动按钮
        local canStart = #reserves < cfg.max_reserves
            and state.cash >= prospectCost
            and availAP >= cfg.ap
        local disableReason = nil
        if #reserves >= cfg.max_reserves then
            disableReason = "备用槽位已满"
        elseif state.cash < prospectCost then
            disableReason = "资金不足"
        elseif availAP < cfg.ap then
            disableReason = "行动点不足"
        end

        table.insert(children, UI.Button {
            text = canStart
                and string.format("🔍 启动探矿（💰%d ⚡%d 周期 %d季）", prospectCost, cfg.ap, cfg.turns)
                or (disableReason
                    and string.format("🔍 探矿（%s）", disableReason)
                    or "🔍 启动探矿"),
            fontSize = F.body_minor,
            height = S.btn_small_height,
            width = "100%",
            variant = canStart and "primary" or "outlined",
            disabled = not canStart,
            backgroundColor = canStart and C.accent_blue or nil,
            fontColor = canStart and C.bg_base or C.text_muted,
            borderRadius = S.radius_btn,
            onClick = function(self)
                self.props.disabled = true
                IndustryPage._OnStartProspect()
            end,
        })
    end

    -- 备用矿列表
    if #reserves > 0 then
        table.insert(children, UI.Divider { color = C.divider })
        table.insert(children, UI.Label {
            text = string.format("备用矿脉（%d/%d）", #reserves, cfg.max_reserves),
            fontSize = F.body_minor,
            fontWeight = "bold",
            fontColor = C.accent_gold,
        })
        for i, rm in ipairs(reserves) do
            local hasSlot = #state.mines < maxMines
            table.insert(children, UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                paddingVertical = 4,
                children = {
                    UI.Panel {
                        width = 32, height = 32,
                        backgroundColor = C.paper_mid,
                        borderRadius = 6,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label { text = "⛰️", fontSize = 16 },
                        },
                    },
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        flexDirection = "column",
                        gap = 1,
                        children = {
                            UI.Label {
                                text = rm.name,
                                fontSize = F.body_minor,
                                fontWeight = "bold",
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = "储量 " .. rm.reserve .. " 单位",
                                fontSize = F.label,
                                fontColor = C.text_muted,
                            },
                        },
                    },
                    UI.Button {
                        text = hasSlot and "激活" or "槽位满",
                        fontSize = F.label,
                        paddingHorizontal = 10,
                        paddingVertical = 4,
                        variant = hasSlot and "primary" or "outlined",
                        disabled = not hasSlot,
                        backgroundColor = hasSlot and C.accent_green or nil,
                        fontColor = hasSlot and C.bg_base or C.text_muted,
                        borderRadius = S.radius_btn,
                        onClick = function(self)
                            self.props.disabled = true
                            IndustryPage._OnActivateReserve(i)
                        end,
                    },
                },
            })
        end
    end

    return UI.Panel {
        id = "prospectCard",
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = prospecting and C.accent_blue or C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 8,
        children = children,
    }
end

--- 工人管理卡片
function IndustryPage._CreateWorkerCard(state)
    local workerWage = state.workers.hired * state.workers.wage
    local morale = state.workers.morale
    local moraleColor = morale >= 60 and C.accent_green or (morale >= 40 and C.accent_amber or C.accent_red)
    local moraleText = morale >= 80 and "高涨" or (morale >= 60 and "正常"
        or (morale >= 40 and "低落" or "极差"))

    local hireCost = math.floor(BW.hire_cost * GameState.GetLaborCostFactor(state)
        * (1 - GameState.GetInfluenceRecruitDiscount(state)))

    return UI.Panel {
        id = "workerCard",
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 标题
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = "工人管理",
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Chip {
                        label = moraleText,
                        color = morale >= 60 and "success" or (morale >= 40 and "warning" or "error"),
                        variant = "soft",
                        size = "sm",
                    },
                },
            },

            -- 工人信息
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                paddingTop = 0,
                flexDirection = "column",
                gap = 6,
                children = {
                    IndustryPage._InfoRow("雇佣人数", state.workers.hired .. " 人", C.text_primary),
                    IndustryPage._InfoRow("每人工资", state.workers.wage .. " /季", C.text_primary),
                    IndustryPage._InfoRow("工资总计", workerWage .. " /季",
                        workerWage > state.cash * 0.3 and C.accent_amber or C.text_primary),
                    IndustryPage._InfoRow("工人士气", morale .. "%", moraleColor),
                    -- 士气条
                    UI.ProgressBar {
                        value = morale / 100,
                        width = "100%",
                        height = 6,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = moraleColor,
                    },
                    -- 产能贡献提示
                    UI.Label {
                        text = string.format("产能贡献: 每 %d 名工人增加 +1 产金/季",
                            BW.workers_per_unit),
                        fontSize = F.label,
                        fontColor = C.text_muted,
                        whiteSpace = "normal",
                    },
                },
            },

            UI.Divider { color = C.divider },

            -- 操作按钮
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                gap = 8,
                children = {
                    UI.Button {
                        id = "hireWorker",
                        text = string.format("招募 +5 (💰%d ⚡1)", hireCost * 5),
                        fontSize = F.body_minor,
                        height = S.btn_small_height,
                        flexGrow = 1,
                        flexBasis = 0,
                        variant = (state.cash >= hireCost * 5 and (state.ap.current + (state.ap.temp or 0)) >= 1)
                            and "primary" or "outlined",
                        disabled = state.cash < hireCost * 5 or (state.ap.current + (state.ap.temp or 0)) < 1,
                        borderRadius = S.radius_btn,
                        onClick = function(self)
                            self.props.disabled = true
                            Actions.HireWorkers(stateRef_, 5, onStateChanged_)
                        end,
                    },
                    UI.Button {
                        id = "fireWorker",
                        text = "解雇 -5",
                        fontSize = F.body_minor,
                        height = S.btn_small_height,
                        flexGrow = 1,
                        flexBasis = 0,
                        variant = "outlined",
                        disabled = state.workers.hired < 5,
                        borderRadius = S.radius_btn,
                        onClick = function(self)
                            self.props.disabled = true
                            IndustryPage._OnFireWorkers(5)
                        end,
                    },
                },
            },
        },
    }
end

--- 操作卡片（§6.3 底部新增资产样式）— 支持部分出售
function IndustryPage._CreateActionCard(state)
    local goldPrice = calcGoldPrice(state)
    local railwayBlocked = GameState.GetModifierValue(state, "railway_blocked") > 0
    local canSell = state.gold > 0 and not railwayBlocked

    -- 出售数量（闭包状态）
    local sellQty = math.min(10, state.gold)
    local qtyLabel  ---@type table
    local revenueLabel ---@type table
    local sellBtn ---@type table

    local function refreshSellUI()
        if qtyLabel then
            qtyLabel:SetText(tostring(sellQty))
        end
        if revenueLabel then
            revenueLabel:SetText(string.format("预计收入：💰%d", sellQty * goldPrice))
        end
        if sellBtn then
            local canSellNow = stateRef_ and sellQty > 0 and sellQty <= (stateRef_.gold or 0)
            sellBtn:SetText(canSellNow
                and string.format("出售 %d 单位 → 💰%d", sellQty, sellQty * goldPrice)
                or "无法出售")
        end
    end

    local function adjustQty(delta)
        if not stateRef_ then return end
        sellQty = math.max(1, math.min(stateRef_.gold, sellQty + delta))
        refreshSellUI()
    end

    -- 数量显示标签
    qtyLabel = UI.Label {
        text = tostring(sellQty),
        fontSize = F.card_title,
        fontWeight = "bold",
        fontColor = C.text_primary,
        textAlign = "center",
        minWidth = 50,
    }

    -- 预计收入标签
    revenueLabel = UI.Label {
        text = string.format("预计收入：💰%d", sellQty * goldPrice),
        fontSize = F.body_minor,
        fontColor = C.accent_gold,
    }

    -- 出售按钮
    sellBtn = UI.Button {
        id = "sellGoldQty",
        text = canSell and string.format("出售 %d 单位 → 💰%d", sellQty, sellQty * goldPrice)
            or (railwayBlocked and "🚂 铁路瘫痪，无法出售" or "无黄金可售"),
        fontSize = F.body_minor,
        height = S.btn_small_height,
        width = "100%",
        variant = canSell and "primary" or "outlined",
        disabled = not canSell,
        backgroundColor = canSell and C.accent_gold or nil,
        fontColor = canSell and C.bg_base or C.text_muted,
        borderRadius = S.radius_btn,
        onClick = function(self)
            self.props.disabled = true
            IndustryPage._OnSellGold(sellQty)
        end,
    }

    -- 数量调节按钮工厂
    local function qtyBtn(label, delta)
        return UI.Panel {
            width = 36, height = 32,
            borderRadius = S.radius_btn,
            backgroundColor = C.bg_elevated,
            borderWidth = 1, borderColor = C.paper_light,
            justifyContent = "center", alignItems = "center",
            pointerEvents = "auto",
            onPointerUp = Config.TapGuard(function(self) adjustQty(delta) end),
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

    return UI.Panel {
        id = "actionCard",
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Label {
                text = "手动交易",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
            IndustryPage._InfoRow("黄金库存", state.gold .. " 单位", C.accent_gold),
            IndustryPage._InfoRow("当前金价", goldPrice .. " /单位", C.text_primary),
            -- 自动出售开关
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "column",
                        gap = 1,
                        children = {
                            UI.Label {
                                text = "自动出售",
                                fontSize = F.body_minor,
                                fontColor = C.text_secondary,
                            },
                            UI.Label {
                                text = "每季结算时自动售出，保留10%库存",
                                fontSize = 10,
                                fontColor = C.text_muted,
                            },
                        },
                    },
                    UI.Button {
                        text = state.gold_auto_sell and "已开启" or "已关闭",
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = state.gold_auto_sell and C.accent_green or C.text_muted,
                        backgroundColor = state.gold_auto_sell
                            and { C.accent_green[1], C.accent_green[2], C.accent_green[3], 40 }
                            or C.bg_elevated,
                        borderRadius = S.radius_btn,
                        borderWidth = 1,
                        borderColor = state.gold_auto_sell and C.accent_green or C.border_card,
                        paddingHorizontal = 10,
                        paddingVertical = 4,
                        onClick = function()
                            if stateRef_ then
                                stateRef_.gold_auto_sell = not stateRef_.gold_auto_sell
                                if onStateChanged_ then onStateChanged_() end
                            end
                        end,
                    },
                },
            },
            -- 数量选择器
            canSell and UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 6,
                children = {
                    UI.Label {
                        text = "出售数量",
                        fontSize = F.body_minor,
                        fontColor = C.text_secondary,
                    },
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
                    -- 快捷按钮：半数 / 全部
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
                                onPointerUp = Config.TapGuard(function(self)
                                    if stateRef_ then
                                        sellQty = math.max(1, math.floor(stateRef_.gold / 2))
                                        refreshSellUI()
                                    end
                                end),
                                children = {
                                    UI.Label {
                                        text = "半数",
                                        fontSize = F.label,
                                        fontColor = C.text_secondary,
                                        pointerEvents = "none",
                                    },
                                },
                            },
                            UI.Panel {
                                paddingHorizontal = 12, paddingVertical = 4,
                                borderRadius = S.radius_btn,
                                backgroundColor = C.bg_elevated,
                                borderWidth = 1, borderColor = C.paper_light,
                                pointerEvents = "auto",
                                onPointerUp = Config.TapGuard(function(self)
                                    if stateRef_ then
                                        sellQty = stateRef_.gold
                                        refreshSellUI()
                                    end
                                end),
                                children = {
                                    UI.Label {
                                        text = "全部",
                                        fontSize = F.label,
                                        fontColor = C.text_secondary,
                                        pointerEvents = "none",
                                    },
                                },
                            },
                        },
                    },
                    revenueLabel,
                },
            } or UI.Panel { width = 0, height = 0 },
            -- 出售按钮
            sellBtn,
        },
    }
end

--- 信息行组件
function IndustryPage._InfoRow(label, value, valueColor)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label {
                text = label,
                fontSize = F.body_minor,
                fontColor = C.text_secondary,
            },
            UI.Label {
                text = value,
                fontSize = F.body_minor,
                fontWeight = "bold",
                fontColor = valueColor or C.text_primary,
            },
        },
    }
end

-- ============================================================================
-- 操作回调
-- ============================================================================

--- 解雇工人
function IndustryPage._OnFireWorkers(count)
    if not stateRef_ then return end

    count = math.min(count, stateRef_.workers.hired)
    if count <= 0 then return end

    local compensation = math.floor(BW.fire_penalty * GameState.GetLaborCostFactor(stateRef_)) * count
    if stateRef_.cash < compensation then
        UI.Toast.Show(string.format("资金不足以支付遣散费 💰%d", compensation),
            { variant = "error", duration = 1.5 })
        return
    end
    stateRef_.cash = stateRef_.cash - compensation
    stateRef_.workers.hired = stateRef_.workers.hired - count
    stateRef_.workers.morale = math.max(0, stateRef_.workers.morale - 5)

    GameState.AddLog(stateRef_, string.format("解雇了 %d 名工人，补偿 %d", count, compensation))
    UI.Toast.Show(string.format("解雇 -%d 工人", count), { variant = "warning", duration = 1.5 })

    if onStateChanged_ then onStateChanged_() end
end

--- 手动出售指定数量黄金
function IndustryPage._OnSellGold(amount)
    if not stateRef_ then return end

    -- 铁路瘫痪时禁止出售
    if GameState.GetModifierValue(stateRef_, "railway_blocked") > 0 then
        UI.Toast.Show("🚂 铁路瘫痪，黄金无法运出！", { variant = "error", duration = 2 })
        return
    end

    if stateRef_.gold <= 0 then
        UI.Toast.Show("没有黄金可出售", { variant = "warning", duration = 1.5 })
        return
    end

    amount = math.max(1, math.min(amount or stateRef_.gold, stateRef_.gold))
    local revenue = amount * calcGoldPrice(stateRef_)
    stateRef_.gold = stateRef_.gold - amount
    stateRef_.cash = stateRef_.cash + revenue

    GameState.AddLog(stateRef_, string.format("手动出售 %d 单位黄金，获得 %d", amount, revenue))
    UI.Toast.Show(string.format("出售 %d 金 → 💰+%d", amount, revenue),
        { variant = "success", duration = 2 })

    if onStateChanged_ then onStateChanged_() end
end

--- 产能迁移：标记矿山为迁移中，下季度 Economy._ProcessMigrations 处理
function IndustryPage._OnMigrateMine(mine, migrateCost, migrateAP)
    if not stateRef_ then return end

    -- 先验证 AP 是否足够
    if not GameState.SpendAP(stateRef_, migrateAP) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return
    end
    -- AP 扣除成功后再扣现金
    if stateRef_.cash < migrateCost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return
    end
    stateRef_.cash = stateRef_.cash - migrateCost

    -- 标记迁移
    mine.migrating = true

    GameState.AddLog(stateRef_, string.format(
        "[矿业] 启动产能迁移：%s（花费 💰%d ⚡%d），下季度完成",
        mine.name, migrateCost, migrateAP))
    UI.Toast.Show(string.format("🔄 %s 产能迁移已启动", mine.name),
        { variant = "info", duration = 2 })

    if onStateChanged_ then onStateChanged_() end
end

--- 善后处理：立即移除矿山，支付清理费用，无负面影响
function IndustryPage._OnCleanupMine(mine, cleanupCost)
    if not stateRef_ then return end

    -- 验证资金
    if stateRef_.cash < cleanupCost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return
    end
    stateRef_.cash = stateRef_.cash - cleanupCost

    -- 从矿山列表中移除
    local kept = {}
    for _, m in ipairs(stateRef_.mines) do
        if m ~= mine then
            table.insert(kept, m)
        end
    end
    stateRef_.mines = kept

    -- 同步区域储量
    if Economy._SyncRegionGoldReserve then
        Economy._SyncRegionGoldReserve(stateRef_)
    end

    GameState.AddLog(stateRef_, string.format(
        "[矿业] 善后处理完毕：%s 已安全关闭（花费 💰%d）",
        mine.name, cleanupCost))
    UI.Toast.Show(string.format("🧹 %s 已妥善关闭", mine.name),
        { variant = "success", duration = 2 })

    if onStateChanged_ then onStateChanged_() end
end

--- 搁置不管：免费移除矿山，但造成负面影响
function IndustryPage._OnAbandonMine(mine)
    if not stateRef_ then return end

    -- 从矿山列表中移除
    local kept = {}
    for _, m in ipairs(stateRef_.mines) do
        if m ~= mine then
            table.insert(kept, m)
        end
    end
    stateRef_.mines = kept

    -- 负面影响：地区影响力 -5
    local region = GameState.GetRegion(stateRef_, mine.region_id)
    if region then
        region.influence = math.max(0, (region.influence or 0) - 5)
    end

    -- 负面影响：工人士气 -3
    stateRef_.workers.morale = math.max(0, stateRef_.workers.morale - 3)

    -- 同步区域储量
    if Economy._SyncRegionGoldReserve then
        Economy._SyncRegionGoldReserve(stateRef_)
    end

    GameState.AddLog(stateRef_, string.format(
        "[矿业] %s 被搁置废弃（影响力-5 士气-3）",
        mine.name))
    UI.Toast.Show(string.format("🚫 %s 已废弃，声誉受损", mine.name),
        { variant = "error", duration = 2.5 })

    if onStateChanged_ then onStateChanged_() end
end

--- 启动探矿：扣除 AP + 现金，创建进行中探矿任务
function IndustryPage._OnStartProspect()
    if not stateRef_ then return end

    -- 防止覆盖进行中的探矿
    if stateRef_.prospecting then
        UI.Toast.Show("探矿正在进行中", { variant = "warning", duration = 1.5 })
        return
    end

    local cfg = Balance.MINE.prospect
    local reserves = stateRef_.prospect_reserves or {}
    if #reserves >= cfg.max_reserves then
        UI.Toast.Show("备用矿脉槽位已满", { variant = "warning", duration = 1.5 })
        return
    end

    local cost = math.floor(cfg.cash * GameState.GetAssetPriceFactor(stateRef_))

    -- 先验证 AP 是否足够
    if not GameState.SpendAP(stateRef_, cfg.ap) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return
    end
    -- AP 扣除成功后再扣现金
    if stateRef_.cash < cost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return
    end
    stateRef_.cash = stateRef_.cash - cost

    -- 计算成功率
    local successCount = stateRef_.prospect_success_count or 0
    local baseChance = math.max(cfg.min_success,
        cfg.base_success - cfg.success_decay * successCount)
    local techBonus = stateRef_.prospect_success_bonus or 0
    local chance = math.min(1.0, baseChance + techBonus)

    stateRef_.prospecting = {
        progress = 0,
        total = cfg.turns,
        success_chance = chance,
    }

    GameState.AddLog(stateRef_, string.format(
        "[矿业] 启动探矿（💰%d ⚡%d，成功率 %d%%，周期 %d 季度）",
        cost, cfg.ap, math.floor(chance * 100), cfg.turns))
    UI.Toast.Show(string.format("🔍 探矿已启动（成功率 %d%%）", math.floor(chance * 100)),
        { variant = "info", duration = 2 })

    if onStateChanged_ then onStateChanged_() end
end

--- 激活备用矿脉：从备用列表移入活跃矿山
function IndustryPage._OnActivateReserve(index)
    if not stateRef_ then return end

    local reserves = stateRef_.prospect_reserves or {}
    local rm = reserves[index]
    if not rm then return end

    local maxMines = (Balance.TRADE.new_mine.max_mines or 4) + (stateRef_.mine_slots_bonus or 0)
    if #stateRef_.mines >= maxMines then
        UI.Toast.Show("矿山槽位已满，无法激活", { variant = "warning", duration = 1.5 })
        return
    end

    -- 从备用列表移除
    table.remove(stateRef_.prospect_reserves, index)

    -- 选择一个区域放置新矿山（复用第一座矿的区域，无矿时用默认矿区 ID）
    local regionId = stateRef_.mines[1] and stateRef_.mines[1].region_id or "mine_district"

    -- 创建新矿山
    table.insert(stateRef_.mines, {
        id = rm.id,
        name = rm.name,
        region_id = regionId,
        level = 1,
        reserve = rm.reserve,
        active = true,
    })

    -- 同步区域储量
    if Economy._SyncRegionGoldReserve then
        Economy._SyncRegionGoldReserve(stateRef_)
    end

    GameState.AddLog(stateRef_, string.format(
        "[矿业] 激活备用矿脉：%s（储量 %d），已投入运营",
        rm.name, rm.reserve))
    UI.Toast.Show(string.format("⛏️ %s 已激活运营！", rm.name),
        { variant = "success", duration = 2 })

    if onStateChanged_ then onStateChanged_() end
end

--- 刷新产业页
---@param root table UI 根控件
---@param state table
function IndustryPage.Refresh(root, state)
    stateRef_ = state
end

return IndustryPage
