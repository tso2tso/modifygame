-- ============================================================================
-- 外国矿产操作系统：侦察 → 开采 → 重建
-- ============================================================================

local Balance = require("data.balance")
local GameState = require("game_state")
local MapTilesData = require("data.map_tiles_data")

local BF = Balance.FOREIGN_OPS
local BM = Balance.MINE

local ForeignOps = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保 state.foreign_ops 存在且结构完整
---@param state table
---@return table foreign_ops
local function ensureFO(state)
    if not state.foreign_ops then
        state.foreign_ops = { scouted = {}, scouting = nil, active = {} }
    end
    local fo = state.foreign_ops
    if not fo.scouted then fo.scouted = {} end
    if not fo.active then fo.active = {} end
    return fo
end

--- 判断 tile 是否是外国矿（非波黑本地矿）
---@param tileId string
---@return boolean
local function isForeignMine(tileId)
    return MapTilesData.FOREIGN_MINE_RESOURCES[tileId] ~= nil
end

--- 获取 tile 所属国家 ID
---@param state table
---@param tileId string
---@return string|nil
local function getTileCountry(state, tileId)
    local tile = MapTilesData.GetTile(state, tileId)
    return tile and tile.country_id or nil
end

--- 统计当前开采中的外国矿数量
---@param fo table
---@return number
local function countActive(fo)
    local n = 0
    for _ in pairs(fo.active) do n = n + 1 end
    return n
end

-- ============================================================================
-- 侦察（Scout）
-- ============================================================================

--- 检查能否侦察某 tile
---@param state table
---@param tileId string
---@return boolean available
---@return string|nil reason
function ForeignOps.CanScout(state, tileId)
    if not isForeignMine(tileId) then
        return false, "非外国矿产"
    end
    local fo = ensureFO(state)
    if fo.scouted[tileId] then
        return false, "已完成侦察"
    end
    if fo.scouting then
        return false, "正在执行另一项侦察任务"
    end
    local available = state.ap.current + (state.ap.temp or 0)
    if available < BF.scout_ap then
        return false, "行动点不足"
    end
    if state.cash < BF.scout_cash then
        return false, "资金不足（需要" .. BF.scout_cash .. "）"
    end
    return true, nil
end

--- 开始侦察
---@param state table
---@param tileId string
---@return boolean success
function ForeignOps.StartScout(state, tileId)
    local ok, reason = ForeignOps.CanScout(state, tileId)
    if not ok then return false, reason end
    local fo = ensureFO(state)

    GameState.SpendAP(state, BF.scout_ap)
    state.cash = state.cash - BF.scout_cash

    fo.scouting = {
        tile_id = tileId,
        remaining = BF.scout_turns,
    }

    local tile = MapTilesData.GetTile(state, tileId)
    local label = tile and tile.label or tileId
    GameState.AddLog(state, string.format("派遣侦察队前往[%s]勘探矿产（预计%d季完成）",
        label, BF.scout_turns))
    return true
end

--- 每季推进侦察进度（在 turn_engine 中调用）
---@param state table
function ForeignOps.TickScout(state)
    local fo = ensureFO(state)
    if not fo.scouting then return end

    -- 家族学位：采矿工程（prospect_speed_pct）—— 勘探加速
    local degreeProsRate = GameState.GetActiveDegreeEffect and GameState.GetActiveDegreeEffect(state, "prospect_speed_pct") or 0
    local tickAmount = 1
    if degreeProsRate > 0 and math.random() < degreeProsRate then
        tickAmount = 2  -- 有概率双倍推进
    end
    fo.scouting.remaining = fo.scouting.remaining - tickAmount
    if fo.scouting.remaining <= 0 then
        local tileId = fo.scouting.tile_id
        fo.scouted[tileId] = true
        fo.scouting = nil

        local tile = MapTilesData.GetTile(state, tileId)
        local label = tile and tile.label or tileId
        local res = MapTilesData.FOREIGN_MINE_RESOURCES[tileId]
        local parts = {}
        if res.gold and res.gold > 0 then table.insert(parts, "金矿" .. res.gold) end
        if res.copper and res.copper > 0 then table.insert(parts, "铜矿" .. res.copper) end
        if res.coal and res.coal > 0 then table.insert(parts, "煤矿" .. res.coal) end
        local resText = #parts > 0 and table.concat(parts, "、") or "无矿藏"

        GameState.AddLog(state, string.format("侦察完成！[%s]发现资源：%s", label, resText))
        table.insert(state.turn_messages, {
            text = string.format("📡 侦察报告：[%s]发现 %s", label, resText),
            type = "info",
        })
    end
end

-- ============================================================================
-- 开采（Exploit）
-- ============================================================================

--- 检查能否开采某 tile
---@param state table
---@param tileId string
---@return boolean available
---@return string|nil reason
function ForeignOps.CanExploit(state, tileId)
    if not isForeignMine(tileId) then
        return false, "非外国矿产"
    end
    local fo = ensureFO(state)
    if not fo.scouted[tileId] then
        return false, "尚未侦察"
    end
    if fo.active[tileId] then
        return false, "已在开采中"
    end
    -- 检查该国是否被占领（sovereign 变更 = 被某方占领）
    local countryId = getTileCountry(state, tileId)
    local isOccupiedByPlayer = false
    if countryId and state.europe and state.europe[countryId] then
        local country = state.europe[countryId]
        if country.sovereign == country.original then
            return false, "该国未被占领"
        end
        -- 玩家亲自占领（sovereign == "bosnia"）可跳过合作分检查
        isOccupiedByPlayer = (country.sovereign == "bosnia")
    end
    -- 合作分（玩家已占领的国家免检）
    if not isOccupiedByPlayer
       and (state.collaboration_score or 0) < BF.exploit_min_collab then
        return false, "合作分不足（需要≥" .. BF.exploit_min_collab .. "）"
    end
    -- 并发上限
    if countActive(fo) >= BF.max_concurrent then
        return false, "开采数量已达上限（" .. BF.max_concurrent .. "）"
    end
    -- 资源
    local available = state.ap.current + (state.ap.temp or 0)
    if available < BF.exploit_ap then
        return false, "行动点不足"
    end
    if state.cash < BF.exploit_cash then
        return false, "资金不足（需要" .. BF.exploit_cash .. "）"
    end
    return true, nil
end

--- 开始开采
---@param state table
---@param tileId string
---@return boolean success
function ForeignOps.StartExploit(state, tileId)
    local ok, reason = ForeignOps.CanExploit(state, tileId)
    if not ok then return false, reason end
    local fo = ensureFO(state)

    GameState.SpendAP(state, BF.exploit_ap)
    state.cash = state.cash - BF.exploit_cash

    -- 从静态数据复制储量快照
    local template = MapTilesData.FOREIGN_MINE_RESOURCES[tileId]
    fo.active[tileId] = {
        damage = BF.initial_damage,
        reserve = {
            gold   = template.gold   or 0,
            copper = template.copper or 0,
            coal   = template.coal   or 0,
        },
    }

    local tile = MapTilesData.GetTile(state, tileId)
    local label = tile and tile.label or tileId
    GameState.AddLog(state, string.format("开始开采[%s]外国矿产（损毁率%d%%，产出大幅降低）",
        label, math.floor(BF.initial_damage * 100)))
    return true
end

-- ============================================================================
-- 重建（Rebuild）
-- ============================================================================

--- 检查能否重建某 tile
---@param state table
---@param tileId string
---@return boolean available
---@return string|nil reason
function ForeignOps.CanRebuild(state, tileId)
    local fo = ensureFO(state)
    local info = fo.active and fo.active[tileId]
    if not info then
        return false, "未在开采中"
    end
    if info.damage <= BF.rebuild_min_damage + 0.001 then
        return false, "已达最低损毁率"
    end
    local available = state.ap.current + (state.ap.temp or 0)
    if available < BF.rebuild_ap then
        return false, "行动点不足"
    end
    if state.cash < BF.rebuild_cash then
        return false, "资金不足（需要" .. BF.rebuild_cash .. "）"
    end
    return true, nil
end

--- 执行重建
---@param state table
---@param tileId string
---@return boolean success
function ForeignOps.DoRebuild(state, tileId)
    local ok, reason = ForeignOps.CanRebuild(state, tileId)
    if not ok then return false, reason end
    local fo = ensureFO(state)
    local info = fo.active[tileId]

    GameState.SpendAP(state, BF.rebuild_ap)
    -- 家族学位：理工学院（repair_cost_reduction）—— 修复费用折扣
    local degreeRepairDisc = GameState.GetActiveDegreeEffect and GameState.GetActiveDegreeEffect(state, "repair_cost_reduction") or 0
    local rebuildCost = BF.rebuild_cash
    if degreeRepairDisc > 0 then
        rebuildCost = math.ceil(rebuildCost * (1 - degreeRepairDisc))
    end
    state.cash = state.cash - rebuildCost

    local oldDamage = info.damage
    info.damage = math.max(BF.rebuild_min_damage, info.damage - BF.rebuild_repair)

    local tile = MapTilesData.GetTile(state, tileId)
    local label = tile and tile.label or tileId
    GameState.AddLog(state, string.format("投资重建[%s]：损毁率 %d%% → %d%%",
        label, math.floor(oldDamage * 100), math.floor(info.damage * 100)))
    return true
end

-- ============================================================================
-- 据点升级（Lv2 专精分叉 / Lv3 终极强化）
-- ============================================================================

--- 获取据点当前等级
---@param info table  outpost info from fo.active[tileId]
---@return number level  1/2/3
local function getOutpostLevel(info)
    return info and info.level or 1
end

--- 检查能否升级据点
---@param state table
---@param tileId string
---@param targetLevel number  升级目标等级 (2 或 3)
---@param specType string     专精类型 "production" 或 "security"
---@return boolean available
---@return string|nil reason
function ForeignOps.CanUpgrade(state, tileId, targetLevel, specType)
    local fo = ensureFO(state)
    local info = fo.active and fo.active[tileId]
    if not info then
        return false, "未在开采中"
    end

    local curLevel = getOutpostLevel(info)
    if targetLevel ~= curLevel + 1 then
        return false, string.format("当前Lv%d，只能升级到Lv%d", curLevel, curLevel + 1)
    end

    -- Lv3 必须沿用 Lv2 的专精路线
    if targetLevel == 3 and info.specialization and info.specialization ~= specType then
        return false, "Lv3必须沿用已选专精路线（" .. info.specialization .. "）"
    end

    local levelCfg = BF.upgrade_levels and BF.upgrade_levels[targetLevel]
    if not levelCfg then
        return false, "无此升级等级配置"
    end
    local specCfg = levelCfg[specType]
    if not specCfg then
        return false, "无此专精类型"
    end

    -- 合作分
    if (specCfg.favor_required or 0) > 0 then
        if (state.collaboration_score or 0) < specCfg.favor_required then
            return false, "合作分不足（需要≥" .. specCfg.favor_required .. "）"
        end
    end

    -- AP
    local available = state.ap.current + (state.ap.temp or 0)
    if available < specCfg.ap then
        return false, "行动点不足"
    end
    -- 资金
    if state.cash < specCfg.cost then
        return false, "资金不足（需要" .. specCfg.cost .. "）"
    end
    return true, nil
end

--- 执行据点升级
---@param state table
---@param tileId string
---@param targetLevel number
---@param specType string
---@return boolean success
---@return string|nil reason
function ForeignOps.UpgradeOutpost(state, tileId, targetLevel, specType)
    local ok, reason = ForeignOps.CanUpgrade(state, tileId, targetLevel, specType)
    if not ok then return false, reason end

    local fo = ensureFO(state)
    local info = fo.active[tileId]
    local specCfg = BF.upgrade_levels[targetLevel][specType]

    GameState.SpendAP(state, specCfg.ap)
    state.cash = state.cash - specCfg.cost

    info.level = targetLevel
    info.specialization = specType

    local tile = MapTilesData.GetTile(state, tileId)
    local label = tile and tile.label or tileId
    GameState.AddLog(state, string.format("据点升级！[%s] → Lv%d %s %s",
        label, targetLevel, specCfg.icon or "", specCfg.name or specType))

    table.insert(state.turn_messages, {
        text = string.format("⬆️ [%s] 升级为 Lv%d %s",
            label, targetLevel, specCfg.name or specType),
        type = "info",
    })

    return true
end

--- 获取据点的专精配置（用于 UI 显示和产出计算）
---@param info table  outpost info
---@return table|nil specCfg  balance 配置项
function ForeignOps.GetSpecConfig(info)
    if not info then return nil end
    local lv = getOutpostLevel(info)
    if lv < 2 or not info.specialization then return nil end
    local levelCfg = BF.upgrade_levels and BF.upgrade_levels[lv]
    return levelCfg and levelCfg[info.specialization] or nil
end

-- ============================================================================
-- 产出计算（在 economy.lua 中调用）
-- ============================================================================

--- 计算某个外国矿本季产出
---@param state table
---@param tileId string
---@return table|nil output {gold, copper, coal}
function ForeignOps.CalcOutput(state, tileId)
    local fo = ensureFO(state)
    local info = fo.active and fo.active[tileId]
    if not info then return nil end

    -- 产出系数：根据据点等级 & 专精确定
    local specCfg = ForeignOps.GetSpecConfig(info)
    local outputRatio = specCfg and specCfg.output_ratio or BF.output_base_ratio

    -- 损毁乘数：堡垒/要塞专精可降低损毁影响
    local damageMult = specCfg and specCfg.damage_mult or 1.0
    local effectiveDamage = (info.damage or 0) * damageMult
    local effectiveRatio = (1 - effectiveDamage) * outputRatio

    local reserve = info.reserve
    local result = { gold = 0, copper = 0, coal = 0 }

    -- 金矿产出
    if (reserve.gold or 0) > 0 then
        local out = math.floor(BM.base_gold_output * effectiveRatio + 0.5)
        out = math.max(out, 1) -- 至少产出 1
        out = math.min(out, reserve.gold)
        result.gold = out
        if not state._estimate_mode then
            reserve.gold = reserve.gold - out
        end
    end

    -- 铜矿产出
    if (reserve.copper or 0) > 0 then
        local out = math.floor(BM.base_copper_output * effectiveRatio + 0.5)
        out = math.max(out, 1)
        out = math.min(out, reserve.copper)
        result.copper = out
        if not state._estimate_mode then
            reserve.copper = reserve.copper - out
        end
    end

    -- 煤矿产出
    if (reserve.coal or 0) > 0 then
        local out = math.floor(BM.base_coal_output * effectiveRatio + 0.5)
        out = math.max(out, 1)
        out = math.min(out, reserve.coal)
        result.coal = out
        if not state._estimate_mode then
            reserve.coal = reserve.coal - out
        end
    end

    -- Lv3 工业矿场额外铜产出
    if specCfg and (specCfg.copper_per_season or 0) > 0 then
        result.copper = result.copper + specCfg.copper_per_season
    end

    return result
end

-- ============================================================================
-- 有效性检查（每季调用）
-- ============================================================================

--- 检查开采中的矿是否仍有效（国家被解放则停止）
---@param state table
function ForeignOps.ValidateActive(state)
    local fo = ensureFO(state)
    local toRemoveSet = {}
    for tileId, _ in pairs(fo.active) do
        local countryId = getTileCountry(state, tileId)
        if countryId and state.europe and state.europe[countryId] then
            local country = state.europe[countryId]
            if country.sovereign == country.original then
                toRemoveSet[tileId] = true
            end
        end
        -- 检查储量是否全部耗尽
        local info = fo.active[tileId]
        if info and info.reserve then
            local totalReserve = (info.reserve.gold or 0)
                + (info.reserve.copper or 0)
                + (info.reserve.coal or 0)
            if totalReserve <= 0 then
                toRemoveSet[tileId] = true
            end
        end
    end

    local toRemove = {}
    for tileId in pairs(toRemoveSet) do
        table.insert(toRemove, tileId)
    end

    for _, tileId in ipairs(toRemove) do
        fo.active[tileId] = nil
        local tile = MapTilesData.GetTile(state, tileId)
        local label = tile and tile.label or tileId
        local countryId = getTileCountry(state, tileId)
        local country = countryId and state.europe and state.europe[countryId]
        local reason = "储量耗尽"
        if country and country.sovereign == country.original then
            reason = "该国已解放，矿权收回"
        end
        GameState.AddLog(state, string.format("[%s]外国矿开采终止：%s", label, reason))
        table.insert(state.turn_messages, {
            text = string.format("⛏️ [%s]开采终止：%s", label, reason),
            type = "warning",
        })
    end
end

return ForeignOps
