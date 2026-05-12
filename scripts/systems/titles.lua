-- ============================================================================
-- 称号检查引擎  titles.lua
-- 每回合末调用 Titles.Check(state)，扫描所有称号并解锁新达成的
-- v3: 新增奖励应用逻辑（modifier + unlock_features）
-- ============================================================================

local TitlesData = require("data.titles_data")
local GameState  = require("game_state")
local Expedition = require("systems.expedition")

local Titles = {}

--- 应用称号奖励（内部函数）
---@param state table
---@param def table 称号定义
local function applyRewards(state, def)
    local rewards = def.rewards
    if not rewards then return end

    -- 应用 modifier 加成（duration=0 表示永久）
    if rewards.modifiers then
        for _, mod in ipairs(rewards.modifiers) do
            GameState.AddModifier(state,
                "title_" .. def.id .. "_" .. mod.key, -- id: 保证唯一
                mod.key,                               -- target
                mod.value,                             -- value
                0                                      -- duration: 永久
            )
        end
    end

    -- 记录功能解锁（供其他系统查询）
    if rewards.unlock_features then
        state.unlocked_features = state.unlocked_features or {}
        for _, feat in ipairs(rewards.unlock_features) do
            state.unlocked_features[feat] = true
        end

        -- 远征功能解锁时，初始化国家HP系统
        if state.unlocked_features["expedition"]
            and not Expedition.IsHPInitialized(state) then
            Expedition.InitCountryHP(state)
        end
    end
end

--- 检查所有未解锁的称号，返回本回合新解锁列表
---@param state table
---@return table[] newlyUnlocked  { {id, name, icon, category, rewards}, ... }
function Titles.Check(state)
    state.titles_unlocked = state.titles_unlocked or {}
    local stats = state.stats or {}
    local newlyUnlocked = {}

    for _, def in ipairs(TitlesData.TITLES) do
        if not state.titles_unlocked[def.id] then
            local ok, result = pcall(def.check, state, stats)
            if ok and result then
                -- 解锁
                state.titles_unlocked[def.id] = state.turn_count or 0
                table.insert(newlyUnlocked, {
                    id       = def.id,
                    name     = def.name,
                    icon     = def.icon,
                    category = def.category,
                    rewards  = def.rewards,
                })

                -- 应用称号奖励
                applyRewards(state, def)

                -- 记录日志
                local rewardTexts = {}
                if def.rewards and def.rewards.modifiers then
                    for _, mod in ipairs(def.rewards.modifiers) do
                        table.insert(rewardTexts, mod.label)
                    end
                end
                if def.rewards and def.rewards.unlock_features then
                    for _, feat in ipairs(def.rewards.unlock_features) do
                        if feat == "gp_actions" then
                            table.insert(rewardTexts, "解锁大国外交行动")
                        elseif feat == "foreign_trade" then
                            table.insert(rewardTexts, "解锁跨国贸易")
                        elseif feat == "expedition" then
                            table.insert(rewardTexts, "解锁军事远征")
                        end
                    end
                end
                if #rewardTexts > 0 then
                    GameState.AddLog(state, string.format(
                        "获得称号「%s」—— 奖励: %s",
                        def.name, table.concat(rewardTexts, ", ")
                    ))
                end
            end
        end
    end

    -- 存入 state 供 UI 弹窗 / 标记使用
    state.titles_new = newlyUnlocked
    return newlyUnlocked
end

--- 检查某功能是否已通过称号解锁
---@param state table
---@param featureId string  例如 "foreign_trade", "expedition"
---@return boolean
function Titles.IsFeatureUnlocked(state, featureId)
    return state.unlocked_features ~= nil
        and state.unlocked_features[featureId] == true
end

--- 获取已解锁称号数量
---@param state table
---@return number
function Titles.UnlockedCount(state)
    local n = 0
    for _ in pairs(state.titles_unlocked or {}) do
        n = n + 1
    end
    return n
end

--- 获取某类别已解锁数 / 总数
---@param state table
---@param catId string
---@return number unlocked, number total
function Titles.CategoryProgress(state, catId)
    local all = TitlesData.GetByCategory(catId)
    local unlocked = 0
    for _, def in ipairs(all) do
        if state.titles_unlocked and state.titles_unlocked[def.id] then
            unlocked = unlocked + 1
        end
    end
    return unlocked, #all
end

return Titles
