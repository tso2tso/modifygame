-- ============================================================================
-- C5: 文化系统（Culture System）
-- 管理文化影响力(CI)、文化点(CP)、作品、文化使团及胜利条件
-- ============================================================================

local Culture = {}

local Balance    = require("data.balance")
local GameState  = require("game_state")

local BC = Balance.CULTURE  -- 快捷引用

-- ============================================================================
-- 工具函数
-- ============================================================================

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--- 确保 culture 子状态存在（存档兼容）
---@param state table
local function EnsureCulture(state)
    if not state.culture then
        state.culture = {
            ci = 0, score = 0,
            region_cp = {}, cp_level_seen = {},
            works = {}, sports_cooldown = 0,
            exhibition_done = false, exhibition_progress = 0,
            missions = {}, mission_paused = {},
        }
    end
end

--- 获取地区 CP（缺省 0）
---@param state table
---@param regionId string
---@return number
function Culture.GetRegionCP(state, regionId)
    EnsureCulture(state)
    return state.culture.region_cp[regionId] or 0
end

--- 设置地区 CP（自动 clamp 0-100）
---@param state table
---@param regionId string
---@param cp number
function Culture.SetRegionCP(state, regionId, cp)
    EnsureCulture(state)
    state.culture.region_cp[regionId] = clamp(cp, 0, 100)
end

--- 修改地区 CP（增量）
---@param state table
---@param regionId string
---@param delta number
function Culture.AddRegionCP(state, regionId, delta)
    Culture.SetRegionCP(state, regionId, Culture.GetRegionCP(state, regionId) + delta)
end

--- 判断某地区是否为玩家控制区（control > 50）
---@param state table
---@param regionId string
---@return boolean
local function IsPlayerRegion(state, regionId)
    for _, r in ipairs(state.regions or {}) do
        if r.id == regionId and (r.control or 0) > 50 then return true end
    end
    return false
end

--- 获取某地区（欧洲地图或本地 regions）
---@param state table
---@param regionId string
---@return table|nil
local function GetRegion(state, regionId)
    for _, r in ipairs(state.regions or {}) do
        if r.id == regionId then return r end
    end
    if state.europe then return state.europe[regionId] end
    return nil
end

--- 获取文化顾问 bonus（0 / 0.5 / 1.0）
---@param state table
---@return number
local function GetCultureAdvisorBonus(state)
    return GameState.GetPositionBonus(state, "culture_advisor") or 0
end

--- 检查科技是否已研发
---@param state table
---@param techId string
---@return boolean
local function HasTech(state, techId)
    return state.tech and state.tech.researched and state.tech.researched[techId] == true
end

--- 统计某类型作品数量
---@param state table
---@param workType string
---@return number
function Culture.CountWorks(state, workType)
    EnsureCulture(state)
    local n = 0
    for _, w in ipairs(state.culture.works) do
        if w.type == workType then n = n + 1 end
    end
    return n
end

--- 统计某地区剧团数量
---@param state table
---@param regionId string
---@return number
function Culture.GetTroupeCount(state, regionId)
    EnsureCulture(state)
    local n = 0
    for _, w in ipairs(state.culture.works) do
        if w.type == "theater_troupe" and w.location == regionId then n = n + 1 end
    end
    return n
end

--- 获取地区 CP 等级名
---@param cp number
---@return string
function Culture.GetCPLevelName(cp)
    if cp >= (BC.cp_assimilation or 90) then return "文化同化"
    elseif cp >= (BC.cp_identity or 70) then return "文化认同"
    elseif cp >= (BC.cp_admire or 50) then return "文化倾慕"
    elseif cp >= (BC.cp_curious or 30) then return "文化好奇"
    else return "无感知" end
end

--- 获取地区 CP 数值等级索引（0-4）
---@param cp number
---@return number
function Culture.GetCPLevel(cp)
    if cp >= (BC.cp_assimilation or 90) then return 4
    elseif cp >= (BC.cp_identity or 70) then return 3
    elseif cp >= (BC.cp_admire or 50) then return 2
    elseif cp >= (BC.cp_curious or 30) then return 1
    else return 0 end
end

-- ============================================================================
-- CI 计算（每季产出）
-- ============================================================================

--- 计算本季 CI 净产出（产出 - 衰减）
---@param state table
---@return number gross, number decay, number modifiers
function Culture.CalcCIGain(state)
    EnsureCulture(state)
    local gross = 0
    local advisorBonus = GetCultureAdvisorBonus(state)

    -- 1. D 线科技每项 +1 CI
    local dTechs = {"d4a_nationalism","d5_radio","d5b_cinema","d6a_university",
                    "d7_wartime_media","d8_cultural_hegemony","d9_propaganda_art",
                    "d10_cultural_bureau","d11_cultural_renaissance"}
    for _, techId in ipairs(dTechs) do
        if HasTech(state, techId) then
            gross = gross + (BC.ci_tech_per_item or 1)
        end
    end

    -- 2. 首都 region.culture 字段接通（萨拉热窝 culture=20 → +2 CI/季）
    for _, r in ipairs(state.regions or {}) do
        if r.type == "capital" and (r.culture or 0) > 0 then
            gross = gross + math.floor((r.culture or 0) / 20) * (BC.ci_home_bonus or 2)
        end
    end

    -- 3. 大学科技 +3 CI
    if HasTech(state, "d6a_university") then
        gross = gross + (BC.ci_university or 3)
    end

    -- 4. 民族史诗每部 +2 CI
    gross = gross + Culture.CountWorks(state, "national_epic") * (BC.ci_epic_bonus or 2)

    -- 5. 事件 culture 修正器接通
    local cultMod = GameState.GetModifierValue(state, "culture") or 0
    gross = gross + math.floor(cultMod)

    -- 6. CP ≥ identity 的地区反哺 +1 CI/地区
    for _, cp in pairs(state.culture.region_cp) do
        if cp >= (BC.cp_identity or 70) then
            gross = gross + 1
        end
    end

    -- 文化顾问乘数
    if advisorBonus >= 0.5 then
        gross = math.floor(gross * (1 + advisorBonus * 0.25))
    end

    -- CI 衰减（满配顾问免疫）
    local decay = 0
    if advisorBonus < 1.0 then
        decay = BC.ci_decay_per_turn or 2
    end

    return gross, decay
end

-- ============================================================================
-- 每季结算（由 turn_engine 调用）
-- ============================================================================

--- 每季文化结算主函数
---@param state table
---@return table log  结算日志列表
function Culture.Tick(state)
    EnsureCulture(state)
    local BC_     = Balance.CULTURE
    local log     = {}
    local cult    = state.culture
    local advisor = GetCultureAdvisorBonus(state)

    -- ── 1. CI 产出 ──────────────────────────────────────────────
    local gross, decay = Culture.CalcCIGain(state)
    local ciDelta = gross - decay
    cult.ci = math.max(0, (cult.ci or 0) + ciDelta)
    if ciDelta ~= 0 then
        table.insert(log, string.format("文化影响力：%+d（产出 %d，衰减 -%d）→ 当前 %d",
            ciDelta, gross, decay, cult.ci))
    end

    -- ── 2. 剧团 CP 贡献 ─────────────────────────────────────────
    -- 按 location 分组，叠加衰减
    local troupeByRegion = {}
    for _, w in ipairs(cult.works) do
        if w.type == "theater_troupe" then
            troupeByRegion[w.location] = (troupeByRegion[w.location] or 0) + 1
        end
    end
    local troupeCpTable = BC_.troupe_cp or {5, 3, 1}
    for regionId, count in pairs(troupeByRegion) do
        local cpAdd = 0
        for i = 1, count do
            cpAdd = cpAdd + (troupeCpTable[math.min(i, #troupeCpTable)] or 0)
        end
        Culture.AddRegionCP(state, regionId, cpAdd)
    end

    -- ── 3. 民族史诗 CP 贡献 ──────────────────────────────────────
    local epicCount = Culture.CountWorks(state, "national_epic")
    if epicCount > 0 then
        -- 己方控制区 +epic_own_cp，邻近未占领地区 +epic_neighbor_cp
        for _, r in ipairs(state.regions or {}) do
            if (r.control or 0) > 50 then
                Culture.AddRegionCP(state, r.id, epicCount * (BC_.epic_own_cp or 2))
            end
        end
        -- 欧洲邻近地区（此处简化：对所有欧洲地区 +1，真正邻接判断可后续扩展）
        if state.europe then
            for regionId, _ in pairs(state.europe) do
                Culture.AddRegionCP(state, regionId, epicCount * (BC_.epic_neighbor_cp or 1))
            end
        end
    end

    -- ── 4. CP 自然衰减（外国地区）────────────────────────────────
    local decay_cp = BC_.cp_decay_foreign or 1
    for regionId, cp in pairs(cult.region_cp) do
        if not IsPlayerRegion(state, regionId) then
            Culture.SetRegionCP(state, regionId, cp - decay_cp)
        elseif advisor >= 1.0 then
            -- 满配顾问：己方控制区 CP 不衰减（空分支，保持现值）
        end
    end

    -- ── 5. 文化使团结算 ──────────────────────────────────────────
    local remainMissions = {}
    for _, mission in ipairs(cult.missions or {}) do
        -- CI 维持检查
        if (cult.ci or 0) < (BC_.mission_ci_maintain or 10) then
            -- CI 不足：暂停
            cult.mission_paused = cult.mission_paused or {}
            cult.mission_paused[mission.target] = (cult.mission_paused[mission.target] or 0) + 1
            if cult.mission_paused[mission.target] < 2 then
                table.insert(remainMissions, mission)
            else
                -- 连续 2 季 CI 不足 → 自动结束
                table.insert(log, string.format("文化使团【%s】因 CI 长期不足已自动结束", mission.target))
            end
        else
            cult.ci = cult.ci - (BC_.mission_ci_maintain or 10)
            cult.mission_paused = cult.mission_paused or {}
            cult.mission_paused[mission.target] = 0
            mission.turns_elapsed = (mission.turns_elapsed or 0) + 1

            -- 计算本季 CP 增量
            local missionCP = BC_.mission_base_cp or 12
            missionCP = missionCP + math.floor(advisor * 4)  -- 良好+4，满配+8
            -- 剧团协同加成
            if Culture.GetTroupeCount(state, mission.target) > 0 then
                missionCP = missionCP + 3
            end
            -- 史诗积淀加成
            missionCP = missionCP + epicCount
            Culture.AddRegionCP(state, mission.target, missionCP)

            -- 使团事件（20% 概率）
            if math.random() < (BC_.mission_event_chance or 0.20) and
               not mission.event_this_turn then
                mission.pending_event = Culture.RollMissionEvent(state, mission)
                mission.event_this_turn = true
            else
                mission.event_this_turn = false
            end

            -- 检查是否到期
            if mission.turns_elapsed >= (BC_.mission_max_turns or 6) then
                table.insert(log, string.format("文化使团【%s】完成（共 %d 季）",
                    mission.target, mission.turns_elapsed))
                -- 不加入 remainMissions → 自然结束
            else
                table.insert(remainMissions, mission)
            end
        end
    end
    cult.missions = remainMissions

    -- ── 6. 体育赛事冷却 ───────────────────────────────────────────
    if (cult.sports_cooldown or 0) > 0 then
        cult.sports_cooldown = cult.sports_cooldown - 1
    end

    -- ── 7. 世界博览会筹备推进 ──────────────────────────────────────
    if not cult.exhibition_done and (cult.exhibition_progress or 0) > 0 then
        cult.exhibition_progress = cult.exhibition_progress + 1
        if cult.exhibition_progress >= (BC_.exhibition_turns or 3) then
            Culture.TriggerExhibition(state, log)
        end
    end

    -- ── 8. 电影生产推进 ───────────────────────────────────────────
    for _, w in ipairs(cult.works) do
        if w.type == "film" and not w.ready then
            w.prod_progress = (w.prod_progress or 0) + 1
            if w.prod_progress >= (BC_.film_prod_turns or 2) then
                w.ready = true
                table.insert(log, string.format("电影【%s】制作完成，可选择发行方式", w.theme or "新作"))
            end
        end
    end

    -- ── 9. CP 等级触发好感（一次性）──────────────────────────────
    for regionId, cp in pairs(cult.region_cp) do
        local lvl = Culture.GetCPLevel(cp)
        local seen = (cult.cp_level_seen or {})[regionId] or 0
        if lvl > seen then
            -- 触发好感加成（对控制该地区的 AI）
            local attBonus = 0
            if lvl == 1 then attBonus = BC_.att_curious or 5
            elseif lvl == 2 then attBonus = BC_.att_admire or 10
            elseif lvl == 3 then attBonus = BC_.att_identity or 15 end
            if attBonus > 0 then
                -- 找到对应 AI 并加好感
                for _, faction in ipairs(state.ai_factions or {}) do
                    -- 简化：对所有外交可感知的 AI +好感
                    faction.attitude = clamp((faction.attitude or 0) + attBonus, -100, 100)
                end
                table.insert(log, string.format("地区 %s 文化影响达到【%s】，AI 好感 +%d",
                    regionId, Culture.GetCPLevelName(cp), attBonus))
            end
            cult.cp_level_seen = cult.cp_level_seen or {}
            cult.cp_level_seen[regionId] = lvl
        end
    end

    -- ── 10. culture_score 累积 ────────────────────────────────────
    local scoreGain = math.floor((cult.ci or 0) / (BC_.score_per_ci or 10))
    for _, cp in pairs(cult.region_cp) do
        if cp >= (BC_.cp_identity or 70) then
            scoreGain = scoreGain + (BC_.score_identity_bonus or 3)
        elseif cp >= (BC_.cp_admire or 50) then
            scoreGain = scoreGain + (BC_.score_admire_bonus or 1)
        end
    end
    cult.score = (cult.score or 0) + scoreGain
    -- 同步到 state.victory.culture
    state.victory = state.victory or {}
    state.victory.culture = cult.score

    -- ── 11. AI culture_score 被动积累 ────────────────────────────
    for _, faction in ipairs(state.ai_factions or {}) do
        if not faction.is_player and not faction.defeated then
            faction.culture_score = faction.culture_score or 0
            local power   = faction.power   or 0
            local economy = faction.economy or 0
            local aiGain  = math.floor(power / 25) + math.floor(economy / 50)
            local cap     = math.floor(power * 8)
            faction.culture_score = math.min(cap, faction.culture_score + aiGain)
        end
    end

    return log
end

-- ============================================================================
-- 作品：歌舞剧团
-- ============================================================================

--- 检查能否创建剧团
---@param state table
---@return boolean ok, string|nil reason
function Culture.CanCreateTroupe(state)
    EnsureCulture(state)
    if state.culture_action_this_turn then
        return false, "本季已执行过文化行动"
    end
    if (state.cash or 0) < (BC.troupe_cost or 200) then
        return false, string.format("克朗不足（需要 %d）", BC.troupe_cost or 200)
    end
    if Culture.CountWorks(state, "theater_troupe") >= (BC.troupe_global_max or 8) then
        return false, string.format("剧团总数已达上限（%d）", BC.troupe_global_max or 8)
    end
    return true
end

--- 创建歌舞剧团
---@param state table
---@param regionId string 驻扎地区
---@return boolean ok, string|nil msg
function Culture.CreateTroupe(state, regionId)
    local ok, reason = Culture.CanCreateTroupe(state)
    if not ok then return false, reason end
    state.cash = state.cash - (BC.troupe_cost or 200)
    table.insert(state.culture.works, {
        type = "theater_troupe",
        location = regionId,
        created_turn = state.turn or 0,
    })
    state.culture_action_this_turn = true
    return true, string.format("歌舞剧团驻扎至 %s", regionId)
end

--- 迁移剧团
---@param state table
---@param workIdx number 在 works 中的下标
---@param targetRegionId string 目标地区
---@return boolean ok, string|nil msg
function Culture.MoveTroupe(state, workIdx, targetRegionId)
    EnsureCulture(state)
    local work = state.culture.works[workIdx]
    if not work or work.type ~= "theater_troupe" then
        return false, "无效的剧团"
    end
    if (state.ap or 0) < (BC.troupe_move_ap or 1) then
        return false, "AP 不足"
    end
    state.ap = state.ap - (BC.troupe_move_ap or 1)
    work.location = targetRegionId
    return true, string.format("剧团迁移至 %s", targetRegionId)
end

-- ============================================================================
-- 作品：电影
-- ============================================================================

--- 检查能否制作电影
---@param state table
---@param theme string "historical"|"national"|"industrial"
---@return boolean ok, string|nil reason
function Culture.CanCreateFilm(state, theme)
    EnsureCulture(state)
    if not HasTech(state, "d5b_cinema") then
        return false, "需要科技「电影工业」（d5b_cinema）"
    end
    if state.culture_action_this_turn then
        return false, "本季已执行过文化行动"
    end
    if (state.cash or 0) < (BC.film_cost or 400) then
        return false, string.format("克朗不足（需要 %d）", BC.film_cost or 400)
    end
    if Culture.CountWorks(state, "film") >= (BC.film_max or 3) then
        return false, "电影主题已全部拍摄"
    end
    -- 检查主题唯一性
    for _, w in ipairs(state.culture.works) do
        if w.type == "film" and w.theme == theme then
            return false, string.format("主题「%s」已拍摄", theme)
        end
    end
    return true
end

--- 开始拍摄电影
---@param state table
---@param theme string
---@return boolean ok, string|nil msg
function Culture.CreateFilm(state, theme)
    local ok, reason = Culture.CanCreateFilm(state, theme)
    if not ok then return false, reason end
    state.cash = state.cash - (BC.film_cost or 400)
    table.insert(state.culture.works, {
        type = "film",
        theme = theme,
        ready = false,
        prod_progress = 0,
        created_turn = state.turn or 0,
    })
    state.culture_action_this_turn = true
    return true, string.format("开始拍摄电影【%s主题】（需 %d 季制作）",
        theme, BC.film_prod_turns or 2)
end

--- 发行电影
---@param state table
---@param workIdx number
---@param mode string "domestic"|"international"|"festival"
---@param targetFactionId string|nil 国际/节庆目标
---@return boolean ok, string|nil msg
function Culture.ReleaseFilm(state, workIdx, mode, targetFactionId)
    EnsureCulture(state)
    local work = state.culture.works[workIdx]
    if not work or work.type ~= "film" or not work.ready then
        return false, "电影尚未制作完成"
    end
    if work.released then
        return false, "该电影已经发行"
    end
    work.released = true
    work.release_mode = mode

    if mode == "domestic" then
        -- 己方控制区每地区 +3 CP
        for _, r in ipairs(state.regions or {}) do
            if (r.control or 0) > 50 then
                Culture.AddRegionCP(state, r.id, BC.film_domestic_cp or 3)
            end
        end
        return true, "国内公映：己方地区 CP +" .. (BC.film_domestic_cp or 3)
    elseif mode == "international" then
        -- 目标国家所有地区 +8 CP
        if state.europe then
            for regionId, reg in pairs(state.europe) do
                if reg.country == (targetFactionId or "") then
                    Culture.AddRegionCP(state, regionId, BC.film_intl_cp or 8)
                end
            end
        end
        return true, "国际发行：目标国地区 CP +" .. (BC.film_intl_cp or 8)
    elseif mode == "festival" then
        -- 目标 AI 好感 +15
        for _, faction in ipairs(state.ai_factions or {}) do
            if faction.id == targetFactionId then
                faction.attitude = clamp((faction.attitude or 0) + (BC.film_festival_att or 15), -100, 100)
                return true, string.format("节庆展映：%s 好感 +%d", faction.name, BC.film_festival_att or 15)
            end
        end
        return false, "未找到目标 AI 派系"
    end
    return false, "无效发行模式"
end

-- ============================================================================
-- 作品：民族史诗
-- ============================================================================

local EPIC_THEMES = {"national", "religious", "historical"}
local EPIC_THEME_NAMES = {national="民族史诗", religious="宗教史诗", historical="历史史诗"}

--- 检查能否出版民族史诗
---@param state table
---@param theme string "national"|"religious"|"historical"
---@return boolean ok, string|nil reason
function Culture.CanCreateEpic(state, theme)
    EnsureCulture(state)
    if not HasTech(state, "d6a_university") then
        return false, "需要科技「萨拉热窝大学」（d6a_university）"
    end
    if state.culture_action_this_turn then
        return false, "本季已执行过文化行动"
    end
    if (state.cash or 0) < (BC.epic_cost or 300) then
        return false, string.format("克朗不足（需要 %d）", BC.epic_cost or 300)
    end
    local rp = state.research_points or state.research or 0
    if rp < (BC.epic_rp_cost or 10) then
        return false, string.format("研发点不足（需要 %d）", BC.epic_rp_cost or 10)
    end
    if Culture.CountWorks(state, "national_epic") >= (BC.epic_max or 3) then
        return false, "史诗主题已全部出版"
    end
    for _, w in ipairs(state.culture.works) do
        if w.type == "national_epic" and w.theme == theme then
            return false, string.format("主题「%s」已出版", EPIC_THEME_NAMES[theme] or theme)
        end
    end
    return true
end

--- 出版民族史诗
---@param state table
---@param theme string
---@return boolean ok, string|nil msg
function Culture.CreateEpic(state, theme)
    local ok, reason = Culture.CanCreateEpic(state, theme)
    if not ok then return false, reason end
    state.cash = state.cash - (BC.epic_cost or 300)
    -- 消耗研发点
    if state.research_points then
        state.research_points = state.research_points - (BC.epic_rp_cost or 10)
    elseif state.research then
        state.research = state.research - (BC.epic_rp_cost or 10)
    end
    table.insert(state.culture.works, {
        type = "national_epic",
        theme = theme,
        created_turn = state.turn or 0,
    })
    state.culture_action_this_turn = true
    return true, string.format("出版【%s】！每季为己方地区 +%d CP，CI +%d/季",
        EPIC_THEME_NAMES[theme] or theme, BC.epic_own_cp or 2, BC.ci_epic_bonus or 2)
end

-- ============================================================================
-- 作品：体育赛事
-- ============================================================================

--- 检查能否举办体育赛事
---@param state table
---@param hostRegionId string
---@return boolean ok, string|nil reason
function Culture.CanHoldSportsEvent(state, hostRegionId)
    EnsureCulture(state)
    if state.culture_action_this_turn then
        return false, "本季已执行过文化行动"
    end
    if (state.culture.sports_cooldown or 0) > 0 then
        return false, string.format("体育赛事冷却中（剩余 %d 季）", state.culture.sports_cooldown)
    end
    if (state.cash or 0) < (BC.sports_cost or 250) then
        return false, string.format("克朗不足（需要 %d）", BC.sports_cost or 250)
    end
    return true
end

--- 举办体育赛事
---@param state table
---@param hostRegionId string 举办地
---@param invitedFactionIds table|nil 邀请的 AI 派系 id 列表
---@return boolean ok, string|nil msg, table results
function Culture.HoldSportsEvent(state, hostRegionId, invitedFactionIds)
    local ok, reason = Culture.CanHoldSportsEvent(state, hostRegionId)
    if not ok then return false, reason, {} end

    state.cash = state.cash - (BC.sports_cost or 250)
    state.culture.sports_cooldown = BC.sports_cooldown or 4

    -- 举办地 +20 CP，邻近地区 +8 CP
    Culture.AddRegionCP(state, hostRegionId, BC.sports_host_cp or 20)
    -- 邻近地区（简化：本地 regions 中非举办地）
    for _, r in ipairs(state.regions or {}) do
        if r.id ~= hostRegionId then
            Culture.AddRegionCP(state, r.id, BC.sports_neighbor_cp or 8)
        end
    end

    local results = { accepted = {}, rejected = {} }

    -- 邀请 AI 参赛
    for _, factionId in ipairs(invitedFactionIds or {}) do
        for _, faction in ipairs(state.ai_factions or {}) do
            if faction.id == factionId then
                if (faction.attitude or 0) >= 10 then
                    -- 接受邀请
                    faction.attitude = clamp((faction.attitude or 0) + (BC.sports_invite_att or 10), -100, 100)
                    table.insert(results.accepted, faction.name)
                else
                    -- 30% 公开拒绝
                    if math.random() < (BC.sports_reject_chance or 0.30) then
                        faction.attitude = clamp((faction.attitude or 0) + (BC.sports_reject_att or -5), -100, 100)
                        table.insert(results.rejected, faction.name)
                    end
                end
            end
        end
    end

    state.culture_action_this_turn = true
    local msg = string.format("体育赛事在 %s 举办！举办地 CP +%d", hostRegionId, BC.sports_host_cp or 20)
    if #results.accepted > 0 then
        msg = msg .. "，" .. table.concat(results.accepted, "/") .. " 参赛"
    end
    return true, msg, results
end

-- ============================================================================
-- 作品：世界博览会
-- ============================================================================

--- 检查能否启动世界博览会
---@param state table
---@return boolean ok, string|nil reason
function Culture.CanStartExhibition(state)
    EnsureCulture(state)
    if state.culture.exhibition_done then
        return false, "本局已举办过世界博览会"
    end
    if (state.culture.exhibition_progress or 0) > 0 then
        return false, "世界博览会筹备中"
    end
    if state.culture_action_this_turn then
        return false, "本季已执行过文化行动"
    end
    if GetCultureAdvisorBonus(state) < 1.0 then
        return false, "需要满配文化顾问（bonus 1.0）"
    end
    if not HasTech(state, "d8_cultural_hegemony") then
        return false, "需要科技「文化霸权」（d8_cultural_hegemony）"
    end
    if Culture.CountWorks(state, "national_epic") < (BC.exhibition_min_epics or 2) then
        return false, string.format("需要至少 %d 部民族史诗已出版", BC.exhibition_min_epics or 2)
    end
    if (state.cash or 0) < (BC.exhibition_cost or 800) then
        return false, string.format("克朗不足（需要 %d）", BC.exhibition_cost or 800)
    end
    local ap = state.ap or 0
    if ap < (BC.exhibition_ap or 2) then
        return false, string.format("AP 不足（需要 %d）", BC.exhibition_ap or 2)
    end
    return true
end

--- 启动世界博览会筹备
---@param state table
---@return boolean ok, string|nil msg
function Culture.StartExhibition(state)
    local ok, reason = Culture.CanStartExhibition(state)
    if not ok then return false, reason end
    state.cash = state.cash - (BC.exhibition_cost or 800)
    state.ap   = (state.ap or 0) - (BC.exhibition_ap or 2)
    state.culture.exhibition_progress = 1
    state.culture_action_this_turn = true
    return true, string.format("世界博览会开始筹备（需 %d 季）", BC.exhibition_turns or 3)
end

--- 触发世界博览会效果（由 Tick 内部调用）
---@param state table
---@param log table
function Culture.TriggerExhibition(state, log)
    local techCount = 0
    local tech = state.tech and state.tech.researched or {}
    for _, _ in pairs(tech) do techCount = techCount + 1 end
    local rep = (state.reputation or 0) / 100
    local cpBonus = math.floor((BC.exhibition_base_cp or 15)
        + techCount * 0.5
        + rep * (BC.exhibition_max_cp or 40 - (BC.exhibition_base_cp or 15)))
    cpBonus = clamp(cpBonus, BC.exhibition_base_cp or 15, BC.exhibition_max_cp or 40)

    -- 所有已追踪地区 +cpBonus CP
    local allRegions = {}
    for _, r in ipairs(state.regions or {}) do table.insert(allRegions, r.id) end
    if state.europe then
        for regionId, _ in pairs(state.europe) do table.insert(allRegions, regionId) end
    end
    for _, regionId in ipairs(allRegions) do
        Culture.AddRegionCP(state, regionId, cpBonus)
    end

    state.culture.exhibition_done = true
    state.culture.exhibition_progress = 0
    table.insert(log, string.format("世界博览会圆满落幕！全球地区 CP +%d", cpBonus))
end

-- ============================================================================
-- 海外文化使团
-- ============================================================================

--- 检查能否发起文化使团
---@param state table
---@param targetRegionId string
---@return boolean ok, string|nil reason
function Culture.CanLaunchMission(state, targetRegionId)
    EnsureCulture(state)
    if GetCultureAdvisorBonus(state) < 0.5 then
        return false, "需要良好级以上文化顾问（bonus ≥ 0.5）"
    end
    if state.culture_action_this_turn then
        return false, "本季已执行过文化行动"
    end
    if (state.culture.ci or 0) < (BC.mission_ci_min or 60) then
        return false, string.format("CI 储量不足（需要 %d，当前 %d）",
            BC.mission_ci_min or 60, state.culture.ci or 0)
    end
    if #(state.culture.missions or {}) >= (BC.mission_max_count or 2) then
        return false, string.format("已达最大并发使团数（%d）", BC.mission_max_count or 2)
    end
    -- 不能对己方地区发起
    if IsPlayerRegion(state, targetRegionId) then
        return false, "不能对己方控制地区发起文化使团"
    end
    -- 不能对同一目标重复发起
    for _, m in ipairs(state.culture.missions) do
        if m.target == targetRegionId then
            return false, "该地区已有进行中的文化使团"
        end
    end
    if (state.ap or 0) < (BC.mission_ap or 1) then
        return false, "AP 不足"
    end
    return true
end

--- 发起文化使团
---@param state table
---@param targetRegionId string
---@return boolean ok, string|nil msg
function Culture.LaunchMission(state, targetRegionId)
    local ok, reason = Culture.CanLaunchMission(state, targetRegionId)
    if not ok then return false, reason end
    state.culture.ci = (state.culture.ci or 0) - (BC.mission_ci_launch or 80)
    state.ap = (state.ap or 0) - (BC.mission_ap or 1)
    table.insert(state.culture.missions, {
        target = targetRegionId,
        turns_elapsed = 0,
        event_this_turn = false,
        pending_event = nil,
    })
    state.culture_action_this_turn = true
    return true, string.format("文化使团出发前往 %s（最长 %d 季）",
        targetRegionId, BC.mission_max_turns or 6)
end

--- 主动撤回文化使团（消耗 1 AP）
---@param state table
---@param targetRegionId string
---@return boolean ok, string|nil msg
function Culture.WithdrawMission(state, targetRegionId)
    EnsureCulture(state)
    if (state.ap or 0) < 1 then return false, "AP 不足" end
    for i, m in ipairs(state.culture.missions) do
        if m.target == targetRegionId then
            table.remove(state.culture.missions, i)
            state.ap = state.ap - 1
            return true, string.format("文化使团已从 %s 撤回", targetRegionId)
        end
    end
    return false, "未找到目标使团"
end

--- 生成使团随机事件
---@param state table
---@param mission table
---@return table event  { type, desc, options }
function Culture.RollMissionEvent(state, mission)
    local events = {
        {
            type = "official_pressure",
            desc = "当地官员施压禁演",
            options = {
                { text = "花 50 情报打通关节", cost_intel = 50, cp_penalty = 0 },
                { text = "忍受阻碍", cp_penalty = -8, turn_penalty = 1 },
            },
        },
        {
            type = "resonance",
            desc = "演出引发强烈共鸣",
            options = {
                { text = "追加场次（-20 CI）", cost_ci = 20, cp_bonus = 8 },
                { text = "正常结束", cp_bonus = 0 },
            },
        },
        {
            type = "faction_infiltrate",
            desc = "对手派系渗透使团",
            options = {
                { text = "花 80 克朗清查", cost_cash = 80, ci_penalty = 0 },
                { text = "忽视", ci_penalty = -5 },
            },
        },
        {
            type = "gov_invite",
            desc = "目标政府邀请官方访问",
            options = {
                { text = "接受（使团结束时好感 +15）", att_bonus = 15 },
                { text = "婉拒", att_bonus = 0 },
            },
        },
    }
    -- 简单随机选一种
    local idx = math.random(1, #events)
    local ev = events[idx]
    ev.mission_target = mission.target
    return ev
end

-- ============================================================================
-- 战争惩罚接口（由 expedition 系统调用）
-- ============================================================================

--- 对某地区发动军事远征时扣除 CP（由 expedition.lua 调用）
---@param state table
---@param regionId string
function Culture.ApplyWarPenalty(state, regionId)
    EnsureCulture(state)
    local penalty = BC.cp_war_penalty or 15
    Culture.AddRegionCP(state, regionId, -penalty)
end

-- ============================================================================
-- 胜利状态查询（供 UI 显示进度）
-- ============================================================================

---@param state table
---@return table progress
function Culture.GetVictoryProgress(state)
    EnsureCulture(state)
    local BC_   = Balance.CULTURE
    local cult  = state.culture
    local techs = state.tech and state.tech.researched or {}

    local identityRegions, assimRegions = {}, {}
    for regionId, cp in pairs(cult.region_cp or {}) do
        if cp >= (BC_.cp_assimilation or 90) then
            table.insert(assimRegions, regionId)
            table.insert(identityRegions, regionId)
        elseif cp >= (BC_.cp_identity or 70) then
            table.insert(identityRegions, regionId)
        end
    end

    -- AI 最强 culture_score
    local strongestAI = 0
    for _, faction in ipairs(state.ai_factions or {}) do
        strongestAI = math.max(strongestAI, faction.culture_score or 0)
    end

    return {
        ci           = cult.ci or 0,
        score        = cult.score or 0,
        score_lead   = (cult.score or 0) - strongestAI,
        tech_hegemony = techs["d8_cultural_hegemony"] == true,
        tech_renaissance = techs["d11_cultural_renaissance"] == true,
        identity_regions  = identityRegions,
        identity_count    = #identityRegions,
        assim_regions  = assimRegions,
        assim_count    = #assimRegions,
        way_a_met = #identityRegions >= (BC_.victory_cp_identity or 3),
        way_b_met = #assimRegions >= (BC_.victory_cp_assimilation or 2)
               and (cult.ci or 0) >= (BC_.victory_ci_assimilation or 150),
        year_met  = (state.year or 0) >= (BC_.victory_year or 1938),
        score_met = ((cult.score or 0) - strongestAI) >= (BC_.victory_score_lead or 500),
        works_troupe = Culture.CountWorks(state, "theater_troupe"),
        works_film   = Culture.CountWorks(state, "film"),
        works_epic   = Culture.CountWorks(state, "national_epic"),
        missions_active = #(cult.missions or {}),
        sports_cooldown = cult.sports_cooldown or 0,
        exhibition_done = cult.exhibition_done or false,
        exhibition_progress = cult.exhibition_progress or 0,
    }
end

return Culture
