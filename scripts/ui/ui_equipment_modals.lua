-- ============================================================================
-- 装备弹窗集合：编队管理 / 装备生产 / 换装 / 维修
-- 设计规范：sarajevo_dynasty_ui_spec §6.5 武装页扩展
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")
local GameState = require("game_state")
local Equipment = require("systems.equipment")
local EquipmentData = require("data.equipment_data")

local AudioManager = require("systems.audio_manager")

local C = Config.COLORS
local F = Config.FONT
local S = Config.SIZE

local CATALOG = EquipmentData.CATALOG

local EquipModals = {}

local currentModal_ = nil
local onStateChanged_ = nil
local stateRef_ = nil
---@type table|nil UI 根节点引用
local uiRoot_ = nil

--- 设置回调
function EquipModals.SetCallbacks(state, onChanged)
    stateRef_ = state
    onStateChanged_ = onChanged
end

--- 设置 UI 根节点（Modal 必须 AddChild 到 UI 树才能渲染）
function EquipModals.SetRoot(root)
    uiRoot_ = root
end

local function closeModal()
    if currentModal_ then
        AudioManager.PlayUI("ui_modal_close")
        currentModal_:Close()
    end
end

local function notifyChanged()
    if onStateChanged_ then onStateChanged_() end
end

--- 通用列表弹窗
local function showList(title, rows)
    currentModal_ = UI.Modal {
        title = title,
        size = "md",
        closeOnOverlay = true,
        closeOnEscape = true,
        showCloseButton = true,
        onClose = function(self)
            currentModal_ = nil
            self:Destroy()
        end,
    }
    local content = UI.ScrollView {
        width = "100%",
        maxHeight = 480,
        flexShrink = 1,
        bounces = false,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                children = rows,
            },
        },
    }
    currentModal_:AddContent(content)
    if uiRoot_ then
        uiRoot_:AddChild(currentModal_)
    end
    currentModal_:Open()
end

--- 小型操作按钮
local function miniBtn(label, bg, onClick, disabled)
    return UI.Panel {
        height = 26,
        paddingLeft = 8,
        paddingRight = 8,
        borderRadius = S.radius_btn,
        backgroundColor = disabled and C.paper_mid or bg,
        justifyContent = "center",
        alignItems = "center",
        opacity = disabled and 0.55 or 1.0,
        pointerEvents = disabled and "none" or "auto",
        onPointerUp = Config.TapGuard(function()
            if not disabled then onClick() end
        end),
        children = {
            UI.Label {
                text = label,
                fontSize = F.label,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 255 },
                pointerEvents = "none",
            },
        },
    }
end

-- ============================================================================
-- 编队管理弹窗
-- ============================================================================

function EquipModals.ShowSquadManagement(state, accent)
    AudioManager.PlayUI("ui_modal_open")
    closeModal()
    stateRef_ = state

    local mil = state.military
    local squads = mil.squads or {}
    local assigned = Equipment.GetAssignedGuards(state)
    local unassigned = Equipment.GetUnassignedGuards(state)

    local rows = {}

    -- 汇总头部
    table.insert(rows, UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label {
                text = string.format("总兵力 %d  已编队 %d  待编 %d",
                    mil.guards, assigned, unassigned),
                fontSize = F.body_minor,
                fontColor = C.text_primary,
            },
            UI.Label {
                text = string.format("%d/%d", #squads, EquipmentData.SQUAD.max_squads),
                fontSize = F.body_minor,
                fontWeight = "bold",
                fontColor = #squads >= EquipmentData.SQUAD.max_squads
                    and C.accent_red or C.accent_green,
            },
        },
    })

    -- 创建编队按钮
    if #squads < EquipmentData.SQUAD.max_squads
        and unassigned >= EquipmentData.SQUAD.min_size then
        table.insert(rows, UI.Panel {
            width = "100%",
            height = 34,
            borderRadius = S.radius_btn,
            backgroundColor = accent,
            justifyContent = "center",
            alignItems = "center",
            onPointerUp = Config.TapGuard(function()
                EquipModals._ShowCreateSquad(state, accent)
            end),
            children = {
                UI.Label {
                    text = "+ 创建新编队",
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = { 255, 255, 255, 255 },
                    pointerEvents = "none",
                },
            },
        })
    end

    -- 编队列表
    for _, sq in ipairs(squads) do
        local sqLocal = sq
        local ed = CATALOG[sq.equip_id] or CATALOG.rifle
        local vet = EquipmentData.VETERANCY[sq.veterancy] or EquipmentData.VETERANCY[0]
        local power = math.floor(Equipment.CalcSquadPower(sq))
        local condColor = sq.condition >= 60 and C.accent_green
            or (sq.condition >= 30 and C.accent_amber or C.accent_red)

        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = C.border_card,
            flexDirection = "column",
            gap = 6,
            children = {
                -- 行1: 名称 + 老兵徽章
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = sq.name,
                            fontSize = F.subtitle,
                            fontWeight = "bold",
                            fontColor = C.text_primary,
                        },
                        UI.Panel {
                            paddingLeft = 6, paddingRight = 6,
                            paddingTop = 2, paddingBottom = 2,
                            borderRadius = S.radius_badge,
                            backgroundColor = sq.veterancy >= 3
                                and C.accent_gold or C.paper_mid,
                            children = {
                                UI.Label {
                                    text = vet.name,
                                    fontSize = F.label,
                                    fontColor = sq.veterancy >= 3
                                        and { 255, 255, 255, 255 } or C.text_secondary,
                                },
                            },
                        },
                    },
                },
                -- 行2: 数据
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 12,
                    children = {
                        UI.Label {
                            text = string.format("👥%d人", sq.size),
                            fontSize = F.body_minor,
                            fontColor = C.text_primary,
                        },
                        UI.Label {
                            text = ed.icon .. " " .. ed.name,
                            fontSize = F.body_minor,
                            fontColor = C.text_primary,
                        },
                        UI.Label {
                            text = string.format("⚔%d", power),
                            fontSize = F.body_minor,
                            fontWeight = "bold",
                            fontColor = C.accent_gold,
                        },
                    },
                },
                -- 行3: 耐久条
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    children = {
                        UI.Label {
                            text = "耐久",
                            fontSize = F.label,
                            fontColor = C.text_muted,
                        },
                        UI.Panel {
                            flexGrow = 1,
                            height = 6,
                            borderRadius = 3,
                            backgroundColor = C.bg_surface,
                            overflow = "hidden",
                            children = {
                                UI.Panel {
                                    width = tostring(sq.condition) .. "%",
                                    height = "100%",
                                    backgroundColor = condColor,
                                    borderRadius = 3,
                                },
                            },
                        },
                        UI.Label {
                            text = sq.condition .. "%",
                            fontSize = F.label,
                            fontColor = condColor,
                        },
                    },
                },
                -- 行4: 操作按钮
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    gap = 6,
                    justifyContent = "flex-end",
                    children = {
                        miniBtn("换装", C.accent_blue, function()
                            EquipModals._ShowEquipPicker(state, accent, sqLocal)
                        end),
                        miniBtn("调整", C.accent_amber, function()
                            EquipModals._ShowResizeSquad(state, accent, sqLocal)
                        end),
                        miniBtn("解散", C.accent_red, function()
                            local ok, msg = Equipment.DisbandSquad(state, sqLocal.id)
                            UI.Toast.Show(msg, {
                                variant = ok and "success" or "error",
                                duration = 1.5,
                            })
                            if ok then closeModal(); notifyChanged() end
                        end),
                    },
                },
            },
        })
    end

    -- 空态
    if #squads == 0 then
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 16,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "暂无编队。编组护卫可大幅提升战力。",
                    fontSize = F.body,
                    fontColor = C.text_muted,
                },
            },
        })
    end

    showList("🛡️ 编队管理", rows)
end

-- ============================================================================
-- 创建编队子弹窗
-- ============================================================================

function EquipModals._ShowCreateSquad(state, accent)
    closeModal()

    local unassigned = Equipment.GetUnassignedGuards(state)
    local maxSize = math.min(EquipmentData.SQUAD.max_size, unassigned)

    local sizeButtons = {}
    for s = EquipmentData.SQUAD.min_size, maxSize do
        local sLocal = s
        table.insert(sizeButtons, UI.Panel {
            width = 40, height = 36,
            borderRadius = S.radius_btn,
            backgroundColor = C.paper_mid,
            justifyContent = "center",
            alignItems = "center",
            onPointerUp = Config.TapGuard(function()
                local ok, msg = Equipment.CreateSquad(state, sLocal)
                UI.Toast.Show(msg, {
                    variant = ok and "success" or "error",
                    duration = 1.5,
                })
                if ok then closeModal(); notifyChanged() end
            end),
            children = {
                UI.Label {
                    text = tostring(s),
                    fontSize = F.body,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                    pointerEvents = "none",
                },
            },
        })
    end

    local rows = {
        UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            flexDirection = "column",
            gap = 8,
            children = {
                UI.Label {
                    text = string.format(
                        "可用护卫 %d 人（编队需 %d~%d 人）",
                        unassigned,
                        EquipmentData.SQUAD.min_size,
                        EquipmentData.SQUAD.max_size),
                    fontSize = F.body,
                    fontColor = C.text_secondary,
                    whiteSpace = "normal",
                },
                UI.Label {
                    text = "点击数字直接创建：",
                    fontSize = F.body_minor,
                    fontColor = C.text_muted,
                },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    gap = 8,
                    children = sizeButtons,
                },
            },
        },
    }

    showList("➕ 创建编队", rows)
end

-- ============================================================================
-- 换装子弹窗
-- ============================================================================

function EquipModals._ShowEquipPicker(state, accent, squad)
    closeModal()

    local mil = state.military
    local currentEd = CATALOG[squad.equip_id] or CATALOG.rifle

    local rows = {}

    -- 当前装备
    table.insert(rows, UI.Panel {
        width = "100%",
        padding = 10,
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card,
        children = {
            UI.Label {
                text = string.format("当前装备: %s %s (T%d)",
                    currentEd.icon, currentEd.name, currentEd.tier),
                fontSize = F.body,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
        },
    })

    -- 退回步枪选项
    if squad.equip_id ~= "rifle" then
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.bg_elevated,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = C.border_card,
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            onPointerUp = Config.TapGuard(function()
                local ok, msg = Equipment.AssignEquipment(state, squad.id, "rifle")
                UI.Toast.Show(msg, {
                    variant = ok and "success" or "error",
                    duration = 1.5,
                })
                if ok then closeModal(); notifyChanged() end
            end),
            children = {
                UI.Label {
                    text = "🔫 步枪 (T1) — 默认装备",
                    fontSize = F.body_minor,
                    fontColor = C.text_primary,
                    pointerEvents = "none",
                },
                UI.Label {
                    text = "装备",
                    fontSize = F.label,
                    fontWeight = "bold",
                    fontColor = C.accent_blue,
                    pointerEvents = "none",
                },
            },
        })
    end

    -- 从库存中按装备类型分组
    local inventory = mil.inventory or {}
    local inventoryByEquip = {}
    for i, item in ipairs(inventory) do
        if not item.repairing then
            if not inventoryByEquip[item.equip_id] then
                inventoryByEquip[item.equip_id] = {}
            end
            table.insert(inventoryByEquip[item.equip_id], { index = i, item = item })
        end
    end

    for _, eid in ipairs(EquipmentData.TIER_ORDER) do
        local items = inventoryByEquip[eid]
        if items and #items > 0 then
            local ed = CATALOG[eid]
            -- 选最佳耐久
            table.sort(items, function(a, b) return a.item.condition > b.item.condition end)
            local best = items[1]
            local condColor = best.item.condition >= 60 and C.accent_green
                or (best.item.condition >= 30 and C.accent_amber or C.accent_red)

            local eidLocal = eid
            table.insert(rows, UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = C.bg_elevated,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = C.border_card,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                onPointerUp = Config.TapGuard(function()
                    local ok, msg = Equipment.AssignEquipment(state, squad.id, eidLocal)
                    UI.Toast.Show(msg, {
                        variant = ok and "success" or "error",
                        duration = 1.5,
                    })
                    if ok then closeModal(); notifyChanged() end
                end),
                children = {
                    UI.Panel {
                        flexShrink = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = string.format("%s %s (T%d) — 库存×%d",
                                    ed.icon, ed.name, ed.tier, #items),
                                fontSize = F.body_minor,
                                fontColor = C.text_primary,
                                pointerEvents = "none",
                            },
                            UI.Label {
                                text = string.format("最佳耐久 %d%% | 战力 ×%.1f",
                                    best.item.condition, ed.power_mul),
                                fontSize = F.label,
                                fontColor = condColor,
                                pointerEvents = "none",
                            },
                        },
                    },
                    UI.Label {
                        text = "装备",
                        fontSize = F.label,
                        fontWeight = "bold",
                        fontColor = C.accent_blue,
                        pointerEvents = "none",
                    },
                },
            })
        end
    end

    -- 库存为空提示
    if #rows <= 1 and squad.equip_id == "rifle" then
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 16,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "库存为空，请先生产或代工装备。",
                    fontSize = F.body,
                    fontColor = C.text_muted,
                },
            },
        })
    end

    showList("🔄 换装 — " .. squad.name, rows)
end

-- ============================================================================
-- 调整人数子弹窗
-- ============================================================================

function EquipModals._ShowResizeSquad(state, accent, squad)
    closeModal()

    local unassigned = Equipment.GetUnassignedGuards(state)
    local maxNewSize = math.min(EquipmentData.SQUAD.max_size, squad.size + unassigned)

    local sizeButtons = {}
    for s = EquipmentData.SQUAD.min_size, maxNewSize do
        local sLocal = s
        local isCurrent = s == squad.size
        table.insert(sizeButtons, UI.Panel {
            width = 40, height = 36,
            borderRadius = S.radius_btn,
            backgroundColor = isCurrent and accent or C.paper_mid,
            justifyContent = "center",
            alignItems = "center",
            onPointerUp = Config.TapGuard(function()
                if sLocal == squad.size then return end
                local ok, msg = Equipment.ResizeSquad(state, squad.id, sLocal)
                UI.Toast.Show(msg, {
                    variant = ok and "success" or "error",
                    duration = 1.5,
                })
                if ok then closeModal(); notifyChanged() end
            end),
            children = {
                UI.Label {
                    text = tostring(s),
                    fontSize = F.body,
                    fontWeight = isCurrent and "bold" or "normal",
                    fontColor = isCurrent and { 255, 255, 255, 255 } or C.text_primary,
                    pointerEvents = "none",
                },
            },
        })
    end

    local rows = {
        UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            flexDirection = "column",
            gap = 8,
            children = {
                UI.Label {
                    text = string.format("%s — 当前 %d 人 | 未编队可用 %d 人",
                        squad.name, squad.size, unassigned),
                    fontSize = F.body,
                    fontColor = C.text_secondary,
                    whiteSpace = "normal",
                },
                UI.Label {
                    text = "选择新人数（当前高亮）：",
                    fontSize = F.body_minor,
                    fontColor = C.text_muted,
                },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    gap = 8,
                    children = sizeButtons,
                },
            },
        },
    }

    showList("📏 调整人数 — " .. squad.name, rows)
end

-- ============================================================================
-- 装备生产与管理弹窗
-- ============================================================================

function EquipModals.ShowProduction(state, accent)
    AudioManager.PlayUI("ui_modal_open")
    closeModal()
    stateRef_ = state

    local mil = state.military
    local inflation = GameState.GetInflationFactor(state)
    local rows = {}

    -- === 兵工厂状态 ===
    local hasFactory = mil.factory and mil.factory.level and mil.factory.level > 0
        and not mil.factory.building
    local factoryFree = hasFactory and Equipment.GetFactoryFreeSlots(state) or 0

    if not mil.factory or (mil.factory.level == 0 and not mil.factory.building) then
        -- 未建造
        local lvData = EquipmentData.FACTORY.levels[1]
        local cost = math.floor(lvData.build_cost * inflation)
        local canBuild = state.cash >= cost
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 3,
            borderLeftColor = accent,
            flexDirection = "column",
            gap = 6,
            children = {
                UI.Label {
                    text = "🏭 兵工厂",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = string.format(
                        "建造兵工厂可自产装备，成本更低。费用 %d 克朗，%d 季完工。",
                        cost, lvData.build_turns),
                    fontSize = F.body_minor,
                    fontColor = C.text_secondary,
                    whiteSpace = "normal",
                },
                UI.Panel {
                    width = "100%",
                    height = 34,
                    borderRadius = S.radius_btn,
                    backgroundColor = canBuild and accent or C.paper_mid,
                    justifyContent = "center",
                    alignItems = "center",
                    opacity = canBuild and 1.0 or 0.55,
                    pointerEvents = canBuild and "auto" or "none",
                    onPointerUp = Config.TapGuard(function()
                        local ok, msg = Equipment.BuildFactory(state)
                        UI.Toast.Show(msg, {
                            variant = ok and "success" or "error",
                            duration = 1.5,
                        })
                        if ok then closeModal(); notifyChanged() end
                    end),
                    children = {
                        UI.Label {
                            text = string.format("建造 (💰%d)", cost),
                            fontSize = F.body,
                            fontWeight = "bold",
                            fontColor = { 255, 255, 255, 255 },
                            pointerEvents = "none",
                        },
                    },
                },
            },
        })
    elseif mil.factory.building then
        -- 建造/升级中
        local b = mil.factory.building
        local progress = b.progress / math.max(1, b.total)
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 3,
            borderLeftColor = C.accent_blue,
            flexDirection = "column",
            gap = 6,
            children = {
                UI.Label {
                    text = string.format("🏭 兵工厂 — 升级至 Lv%d", b.target_level),
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.ProgressBar {
                    value = progress,
                    width = "100%",
                    height = 7,
                    borderRadius = 4,
                    trackColor = C.bg_surface,
                    fillColor = C.accent_blue,
                },
                UI.Label {
                    text = string.format("进度 %d/%d 季", b.progress, b.total),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
            },
        })
    else
        -- 工厂运行中
        local lvl = mil.factory.level
        local lvData = EquipmentData.FACTORY.levels[lvl]
        local canUpgrade = lvl < EquipmentData.FACTORY.max_level

        local factoryChildren = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = string.format("🏭 兵工厂 Lv%d", lvl),
                        fontSize = F.subtitle,
                        fontWeight = "bold",
                        fontColor = C.text_primary,
                    },
                    UI.Label {
                        text = string.format("空槽 %d/%d | 维护 %d/季",
                            factoryFree, lvData.slots, lvData.maintenance),
                        fontSize = F.label,
                        fontColor = C.text_secondary,
                    },
                },
            },
        }

        if canUpgrade then
            local nextLv = EquipmentData.FACTORY.levels[lvl + 1]
            local upgCost = math.floor(nextLv.build_cost * inflation)
            local canAfford = state.cash >= upgCost
            table.insert(factoryChildren, miniBtn(
                string.format("升级 Lv%d (💰%d)", lvl + 1, upgCost),
                C.accent_amber,
                function()
                    local ok, msg = Equipment.UpgradeFactory(state)
                    UI.Toast.Show(msg, {
                        variant = ok and "success" or "error",
                        duration = 1.5,
                    })
                    if ok then closeModal(); notifyChanged() end
                end,
                not canAfford
            ))
        end

        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderLeftWidth = 3,
            borderLeftColor = C.accent_green,
            flexDirection = "column",
            gap = 6,
            children = factoryChildren,
        })
    end

    -- === 生产队列 ===
    local queue = mil.production_queue or {}
    local outsource = mil.outsource_slots or {}

    if #queue > 0 or #outsource > 0 then
        local queueChildren = {
            UI.Label {
                text = "生产队列",
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
        }

        for _, item in ipairs(queue) do
            local ed = CATALOG[item.equip_id]
            local label = item.source == "repair" and "维修" or "生产"
            local progress = item.progress / math.max(1, item.total)
            table.insert(queueChildren, UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 4,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = string.format("🏭 %s: %s %s",
                                    label,
                                    ed and ed.icon or "?",
                                    ed and ed.name or item.equip_id),
                                fontSize = F.body_minor,
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = string.format("%d/%d季",
                                    item.progress, item.total),
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                        },
                    },
                    UI.ProgressBar {
                        value = progress,
                        width = "100%",
                        height = 5,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = C.accent_blue,
                    },
                },
            })
        end

        for _, item in ipairs(outsource) do
            local ed = CATALOG[item.equip_id]
            local progress = item.progress / math.max(1, item.total)
            table.insert(queueChildren, UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 4,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = string.format("📦 代工: %s %s",
                                    ed and ed.icon or "?",
                                    ed and ed.name or item.equip_id),
                                fontSize = F.body_minor,
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = string.format("%d/%d季",
                                    item.progress, item.total),
                                fontSize = F.label,
                                fontColor = C.text_secondary,
                            },
                        },
                    },
                    UI.ProgressBar {
                        value = progress,
                        width = "100%",
                        height = 5,
                        borderRadius = 3,
                        trackColor = C.bg_surface,
                        fillColor = C.accent_amber,
                    },
                },
            })
        end

        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = C.border_card,
            flexDirection = "column",
            gap = 6,
            children = queueChildren,
        })
    end

    -- === 可生产装备列表 ===
    local outsourceFree = Equipment.GetOutsourceFreeSlots(state)
    local unlocked = EquipmentData.GetUnlockedList(state)
    local prodChildren = {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = "可生产装备",
                    fontSize = F.subtitle,
                    fontWeight = "bold",
                    fontColor = C.text_primary,
                },
                UI.Label {
                    text = string.format("工厂%s%d槽 | 代工%d/%d槽",
                        hasFactory and "空" or "无",
                        factoryFree,
                        #(mil.outsource_slots or {}),
                        EquipmentData.OUTSOURCE.max_slots),
                    fontSize = F.label,
                    fontColor = C.text_secondary,
                },
            },
        },
    }

    local hasProdOptions = false
    for _, ed in ipairs(unlocked) do
        if ed.id ~= "rifle" then
            hasProdOptions = true
            local edLocal = ed
            local factoryCost = math.floor(ed.prod_cost * inflation)
            local outsourceCost = math.floor(
                ed.prod_cost * EquipmentData.OUTSOURCE.cost_multiplier * inflation)

            local btns = {}
            if hasFactory then
                local canFactory = factoryFree > 0 and state.cash >= factoryCost
                table.insert(btns, miniBtn(
                    string.format("🏭%d/%d季", factoryCost, ed.prod_turns),
                    C.accent_green,
                    function()
                        local ok, msg = Equipment.StartProduction(state, edLocal.id)
                        UI.Toast.Show(msg, {
                            variant = ok and "success" or "error",
                            duration = 1.5,
                        })
                        if ok then closeModal(); notifyChanged() end
                    end,
                    not canFactory
                ))
            end
            local canOutsource = outsourceFree > 0 and state.cash >= outsourceCost
            table.insert(btns, miniBtn(
                string.format("📦%d/%d季", outsourceCost,
                    ed.prod_turns + EquipmentData.OUTSOURCE.time_bonus),
                C.accent_amber,
                function()
                    local ok, msg = Equipment.StartOutsource(state, edLocal.id)
                    UI.Toast.Show(msg, {
                        variant = ok and "success" or "error",
                        duration = 1.5,
                    })
                    if ok then closeModal(); notifyChanged() end
                end,
                not canOutsource
            ))

            table.insert(prodChildren, UI.Panel {
                width = "100%",
                padding = 8,
                backgroundColor = C.bg_elevated,
                borderRadius = S.radius_card,
                borderWidth = 1,
                borderColor = C.border_card,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Panel {
                        flexShrink = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = string.format("%s %s (T%d)",
                                    ed.icon, ed.name, ed.tier),
                                fontSize = F.body_minor,
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = string.format("战力×%.1f 维护%d/季",
                                    ed.power_mul, ed.maintenance),
                                fontSize = F.label,
                                fontColor = C.text_muted,
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 4,
                        children = btns,
                    },
                },
            })
        end
    end

    if hasProdOptions then
        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = C.border_card,
            flexDirection = "column",
            gap = 6,
            children = prodChildren,
        })
    end

    -- === 库存 + 维修 ===
    local inventory = mil.inventory or {}
    if #inventory > 0 then
        local invChildren = {
            UI.Label {
                text = string.format("📦 库存装备 (%d)", #inventory),
                fontSize = F.subtitle,
                fontWeight = "bold",
                fontColor = C.text_primary,
            },
        }

        for i, item in ipairs(inventory) do
            local iLocal = i
            local ed = CATALOG[item.equip_id]
            local condColor = item.condition >= 60 and C.accent_green
                or (item.condition >= 30 and C.accent_amber or C.accent_red)
            local canRepair = not item.repairing and item.condition < 100
                and hasFactory and factoryFree > 0
            local repairCost = 0
            if ed and canRepair then
                repairCost = math.floor(
                    ed.prod_cost * EquipmentData.REPAIR.cost_ratio * inflation)
                canRepair = canRepair and state.cash >= repairCost
            end

            local itemBtns = {}
            if canRepair then
                table.insert(itemBtns, miniBtn(
                    string.format("维修💰%d", repairCost),
                    C.accent_blue,
                    function()
                        local ok, msg = Equipment.StartRepair(state, iLocal)
                        UI.Toast.Show(msg, {
                            variant = ok and "success" or "error",
                            duration = 1.5,
                        })
                        if ok then closeModal(); notifyChanged() end
                    end
                ))
            end

            table.insert(invChildren, UI.Panel {
                width = "100%",
                padding = 8,
                backgroundColor = C.bg_elevated,
                borderRadius = S.radius_card,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Panel {
                        flexShrink = 1,
                        flexDirection = "column",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = string.format("%s %s (T%d)",
                                    ed and ed.icon or "?",
                                    ed and ed.name or "?",
                                    ed and ed.tier or 0),
                                fontSize = F.body_minor,
                                fontColor = C.text_primary,
                            },
                            UI.Label {
                                text = item.repairing and "🔧 维修中"
                                    or string.format("耐久 %d%%", item.condition),
                                fontSize = F.label,
                                fontColor = item.repairing and C.accent_blue
                                    or condColor,
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 4,
                        children = itemBtns,
                    },
                },
            })
        end

        table.insert(rows, UI.Panel {
            width = "100%",
            padding = 10,
            backgroundColor = C.paper_dark,
            borderRadius = S.radius_card,
            borderWidth = 1,
            borderColor = C.border_card,
            flexDirection = "column",
            gap = 6,
            children = invChildren,
        })
    end

    showList("⚒️ 装备生产与管理", rows)
end

return EquipModals
