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

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local BM = Balance.MINE
local BW = Balance.WORKERS

local IndustryPage = {}

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

    -- 2. 矿山卡片（遍历所有矿山）
    for _, mine in ipairs(state.mines) do
        table.insert(children, IndustryPage._CreateMineCard(state, mine))
    end

    -- 3. 工人管理卡片
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
            -- 副指标：白银库存 + 通胀倍率
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    IndustryPage._EstimateItem("⚪ 白银库存",
                        tostring(state.silver or 0) .. " 单位", C.paper_light),
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
    local goldReserve = region and region.resources.gold_reserve or 0
    local security = region and region.security or 0
    local secText = RegionsData.GetSecurityText(security)

    -- 计算当前产出
    local currentOutput = Economy._CalcMineOutput(state, mine)

    -- 矿业总监加成
    local directorBonus = GameState.GetPositionBonus(state, "mine_director")
    local directorMember = GameState.GetMemberAtPosition(state, "mine_director")
    local directorName = directorMember and directorMember.name or "空缺"
    local directorColor = directorMember and C.accent_green or C.accent_red

    -- 升级费用
    local upgradeCost = math.floor(BM.upgrade_cost * mine.level * GameState.GetAssetPriceFactor(state))
    local canUpgrade = mine.level < BM.max_level and state.cash >= upgradeCost and state.ap.current >= 1

    return UI.Panel {
        id = "mineCard_" .. mine.id,
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        borderWidth = 1,
        borderColor = C.border_card,
        flexDirection = "column",
        overflow = "hidden",
        children = {
            -- 标题栏（§6.3 资产名 + 类型）
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                backgroundColor = C.bg_elevated,
                children = {
                    -- 图标占位（§6.3 资产图片 56×56）
                    UI.Panel {
                        width = 56,
                        height = 56,
                        backgroundColor = C.paper_mid,
                        borderRadius = S.radius_card,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "⛏️",
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
                                fontColor = C.accent_gold,
                            },
                            UI.Label {
                                text = "等级 " .. mine.level .. "/" .. BM.max_level,
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                        },
                    },
                    -- 产出徽章（§6.3 产量右对齐）
                    UI.Panel {
                        flexDirection = "column",
                        alignItems = "flex-end",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = currentOutput .. "/季",
                                fontSize = F.data_small,
                                fontWeight = "bold",
                                fontColor = C.accent_amber,
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
                    -- 黄金储量
                    IndustryPage._InfoRow("黄金储量", goldReserve .. " 单位",
                        goldReserve < 50 and C.accent_red or C.text_primary),
                    -- 储量进度条
                    UI.ProgressBar {
                        value = math.min(1, goldReserve / 200),
                        width = "100%",
                        height = 6,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = goldReserve < 50 and C.accent_red or C.accent_gold,
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

            -- 升级按钮
            UI.Panel {
                width = "100%",
                padding = S.card_padding,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Button {
                        id = "upgradeMine_" .. mine.id,
                        text = mine.level >= BM.max_level and "已满级"
                            or string.format("升级矿山 (💰%d ⚡1)", upgradeCost),
                        fontSize = F.body_minor,
                        height = S.btn_small_height,
                        flexGrow = 1,
                        variant = canUpgrade and "primary" or "outlined",
                        disabled = not canUpgrade,
                        backgroundColor = canUpgrade and C.accent_amber or nil,
                        fontColor = canUpgrade and C.bg_base or C.text_muted,
                        borderRadius = S.radius_btn,
                        onClick = function(self)
                            IndustryPage._OnUpgradeMine(mine.id)
                        end,
                    },
                },
            },
        },
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
                        variant = (state.cash >= hireCost * 5 and state.ap.current >= 1)
                            and "primary" or "outlined",
                        disabled = state.cash < hireCost * 5 or state.ap.current < 1,
                        borderRadius = S.radius_btn,
                        onClick = function(self)
                            IndustryPage._OnHireWorkers(5)
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
                            IndustryPage._OnFireWorkers(5)
                        end,
                    },
                },
            },
        },
    }
end

--- 操作卡片（§6.3 底部新增资产样式）
function IndustryPage._CreateActionCard(state)
    local goldPrice = BM.gold_price
    local canSell = state.gold > 0

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
                                text = "每季结算时自动售出超过10单位的黄金",
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
            UI.Button {
                id = "sellAllGold",
                text = canSell and string.format("立即出售全部 (%d 单位 → 💰%d)",
                    state.gold, state.gold * goldPrice) or "无黄金可售",
                fontSize = F.body_minor,
                height = S.btn_small_height,
                width = "100%",
                variant = canSell and "primary" or "outlined",
                disabled = not canSell,
                backgroundColor = canSell and C.accent_gold or nil,
                fontColor = canSell and C.bg_base or C.text_muted,
                borderRadius = S.radius_btn,
                onClick = function(self)
                    IndustryPage._OnSellAllGold()
                end,
            },
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

--- 升级矿山
function IndustryPage._OnUpgradeMine(mineId)
    if not stateRef_ then return end

    for _, mine in ipairs(stateRef_.mines) do
        if mine.id == mineId then
            if mine.level >= BM.max_level then
                UI.Toast.Show("矿山已达最高等级", { variant = "warning", duration = 1.5 })
                return
            end

            local cost = math.floor(BM.upgrade_cost * mine.level * GameState.GetAssetPriceFactor(stateRef_))
            if stateRef_.cash < cost then
                UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
                return
            end
            if not GameState.SpendAP(stateRef_, 1) then
                UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
                return
            end

            stateRef_.cash = stateRef_.cash - cost
            mine.level = mine.level + 1
            GameState.AddLog(stateRef_, string.format(
                "%s 升级到 %d 级，花费 %d", mine.name, mine.level, cost))
            UI.Toast.Show(string.format("%s → Lv.%d", mine.name, mine.level),
                { variant = "success", duration = 1.5 })

            if onStateChanged_ then onStateChanged_() end
            break
        end
    end
end

--- 招募工人
function IndustryPage._OnHireWorkers(count)
    if not stateRef_ then return end

    local totalCost = math.floor(BW.hire_cost * GameState.GetLaborCostFactor(stateRef_)
        * (1 - GameState.GetInfluenceRecruitDiscount(stateRef_))) * count
    if stateRef_.cash < totalCost then
        UI.Toast.Show("资金不足", { variant = "error", duration = 1.5 })
        return
    end
    if not GameState.SpendAP(stateRef_, 1) then
        UI.Toast.Show("行动点不足", { variant = "error", duration = 1.5 })
        return
    end

    stateRef_.cash = stateRef_.cash - totalCost
    stateRef_.workers.hired = stateRef_.workers.hired + count
    GameState.AddLog(stateRef_, string.format("招募了 %d 名工人，花费 %d", count, totalCost))
    UI.Toast.Show(string.format("招募 +%d 工人", count), { variant = "success", duration = 1.5 })

    if onStateChanged_ then onStateChanged_() end
end

--- 解雇工人
function IndustryPage._OnFireWorkers(count)
    if not stateRef_ then return end

    count = math.min(count, stateRef_.workers.hired)
    if count <= 0 then return end

    local compensation = math.floor(BW.fire_penalty * GameState.GetLaborCostFactor(stateRef_)) * count
    stateRef_.cash = stateRef_.cash - compensation
    stateRef_.workers.hired = stateRef_.workers.hired - count
    stateRef_.workers.morale = math.max(0, stateRef_.workers.morale - 5)

    GameState.AddLog(stateRef_, string.format("解雇了 %d 名工人，补偿 %d", count, compensation))
    UI.Toast.Show(string.format("解雇 -%d 工人", count), { variant = "warning", duration = 1.5 })

    if onStateChanged_ then onStateChanged_() end
end

--- 手动出售全部黄金
function IndustryPage._OnSellAllGold()
    if not stateRef_ then return end

    if stateRef_.gold <= 0 then
        UI.Toast.Show("没有黄金可出售", { variant = "warning", duration = 1.5 })
        return
    end

    local amount = stateRef_.gold
    local revenue = amount * BM.gold_price
    stateRef_.gold = 0
    stateRef_.cash = stateRef_.cash + revenue

    GameState.AddLog(stateRef_, string.format("手动出售 %d 单位黄金，获得 %d", amount, revenue))
    UI.Toast.Show(string.format("出售 %d 金 → 💰+%d", amount, revenue),
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
