-- ============================================================================
-- 称号检查引擎  titles.lua
-- 每回合末调用 Titles.Check(state)，扫描所有称号并解锁新达成的
-- ============================================================================

local TitlesData = require("data.titles_data")

local Titles = {}

--- 检查所有未解锁的称号，返回本回合新解锁列表
---@param state table
---@return table[] newlyUnlocked  { {id, name, icon, category}, ... }
function Titles.Check(state)
    state.titles_unlocked = state.titles_unlocked or {}
    local stats = state.stats or {}
    local newlyUnlocked = {}

    for _, def in ipairs(TitlesData.TITLES) do
        if not state.titles_unlocked[def.id] then
            local ok, err = pcall(def.check, state, stats)
            if ok and err then
                -- 解锁
                state.titles_unlocked[def.id] = state.turn_count or 0
                table.insert(newlyUnlocked, {
                    id       = def.id,
                    name     = def.name,
                    icon     = def.icon,
                    category = def.category,
                })
            end
        end
    end

    -- 存入 state 供 UI 弹窗 / 标记使用
    state.titles_new = newlyUnlocked
    return newlyUnlocked
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
