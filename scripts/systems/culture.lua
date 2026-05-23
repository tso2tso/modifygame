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

local function AvailableAP(state)
    if type(state.ap) == "table" then
        return (state.ap.current or 0) + (state.ap.temp or 0)
    end
    return state.ap or 0
end

local function SpendAP(state, cost)
    if cost <= 0 then return true end
    if type(state.ap) == "table" and GameState.SpendAP then
        return GameState.SpendAP(state, cost)
    end
    if (state.ap or 0) < cost then return false end
    state.ap = state.ap - cost
    return true
end

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
    -- 迁移：给旧存档中缺少 troupe_id 的剧团补 id
    if state.culture.works then
        local usedIds = {}
        for _, w in ipairs(state.culture.works) do
            if w.type == "theater_troupe" and w.troupe_id then
                usedIds[w.troupe_id] = true
            end
        end
        for _, w in ipairs(state.culture.works) do
            if w.type == "theater_troupe" and not w.troupe_id then
                for i = 1, 8 do
                    local tid = "t" .. i
                    if not usedIds[tid] then
                        w.troupe_id = tid
                        usedIds[tid] = true
                        break
                    end
                end
            end
        end
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

local HOME_ADJACENT_COUNTRIES = { "austria_hungary", "serbia", "montenegro" }

local function GetEpicNeighborTargets(state)
    local targets = {}
    for _, countryId in ipairs(HOME_ADJACENT_COUNTRIES) do
        targets[countryId] = true
    end
    for _, occ in ipairs((state.expeditions and state.expeditions.occupied_countries) or {}) do
        local country = state.europe and state.europe[occ.country_id]
        for _, adj in ipairs((country and country.adjacency) or {}) do
            targets[adj] = true
        end
    end
    for _, occ in ipairs((state.expeditions and state.expeditions.occupied_countries) or {}) do
        targets[occ.country_id] = nil
    end
    return targets
end

local function AddAttitude(state, targetId, amount)
    if amount == 0 then return end
    for _, faction in ipairs(state.ai_factions or {}) do
        if not targetId or faction.id == targetId then
            faction.attitude = clamp((faction.attitude or 0) + amount, -100, 100)
        end
    end
    local power = targetId and state.powers and state.powers[targetId] or nil
    if power then
        power.attitude_to_player = clamp((power.attitude_to_player or 0) + amount, -100, 100)
    end
    local country = targetId and state.europe and state.europe[targetId] or nil
    if country then
        country.attitude_to_player = clamp((country.attitude_to_player or 0) + amount, -100, 100)
    end
end

local function GetCountryLabel(state, countryId)
    local country = state.europe and state.europe[countryId]
    if country and country.label then return country.label end
    for _, faction in ipairs(state.ai_factions or {}) do
        if faction.id == countryId then return faction.name or countryId end
    end
    local power = state.powers and state.powers[countryId]
    if power then return power.label or countryId end
    return countryId
end

--- 获取电影发行目标列表（带好感分级）
--- 返回每个目标的 id/label/attitude/tier/cp，按好感降序
---@param state table
---@return table[]
function Culture.GetFilmTargets(state)
    local tiers = BC.film_tier or {}
    local targets = {}
    local seen = {}

    -- 己方地区（本国，无条件 domestic）
    for _, r in ipairs(state.regions or {}) do
        if not seen[r.id] then
            seen[r.id] = true
            table.insert(targets, {
                id       = r.id,
                label    = r.name or r.id,
                attitude = 100,
                tier     = "domestic",
                cp       = Culture.GetRegionCP(state, r.id),
                domestic = true,
            })
        end
    end

    -- 外国地区（按好感确定 tier）
    local function getAttitude(id)
        -- 先查 ai_factions
        for _, f in ipairs(state.ai_factions or {}) do
            if f.id == id then return f.attitude or 0 end
        end
        -- 再查 powers
        local p = state.powers and state.powers[id]
        if p then return p.attitude_to_player or 0 end
        -- 再查 europe
        local c = state.europe and state.europe[id]
        if c then return c.attitude_to_player or 0 end
        return 0
    end

    local function classifyTier(att)
        if (tiers.intl     and att >= (tiers.intl.att_min     or 70)) then return "intl"     end
        if (tiers.festival and att >= (tiers.festival.att_min or 50)) then return "festival"  end
        if (tiers.friendly and att >= (tiers.friendly.att_min or 20)) then return "friendly"  end
        return nil  -- 好感太低，不可发行
    end

    for id, country in pairs(state.europe or {}) do
        if not seen[id] then
            seen[id] = true
            local att  = getAttitude(id)
            local tier = classifyTier(att)
            -- 好感不足则仍加入列表但标记 locked，让 UI 展示门槛提示
            table.insert(targets, {
                id       = id,
                label    = country.label or id,
                attitude = att,
                tier     = tier,    -- nil = 好感不足，无法发行
                cp       = Culture.GetRegionCP(state, id),
                domestic = false,
            })
        end
    end

    table.sort(targets, function(a, b)
        -- 己方地区优先，其次按好感降序
        if a.domestic ~= b.domestic then return a.domestic and not b.domestic end
        if a.attitude == b.attitude  then return a.label < b.label end
        return a.attitude > b.attitude
    end)
    return targets
end

function Culture.GetSportsInviteCandidates(state)
    local seen, candidates = {}, {}
    for _, faction in ipairs(state.ai_factions or {}) do
        if faction.id then
            seen[faction.id] = true
            table.insert(candidates, {
                id = faction.id,
                label = faction.name or faction.id,
                attitude = faction.attitude or 0,
            })
        end
    end
    for id, power in pairs(state.powers or {}) do
        if not seen[id] and power.active then
            seen[id] = true
            table.insert(candidates, {
                id = id,
                label = power.label or id,
                attitude = power.attitude_to_player or 0,
            })
        end
    end
    for id, country in pairs(state.europe or {}) do
        if not seen[id] then
            seen[id] = true
            table.insert(candidates, {
                id = id,
                label = country.label or id,
                attitude = country.attitude_to_player or 0,
            })
        end
    end
    table.sort(candidates, function(a, b)
        if a.attitude == b.attitude then return a.label < b.label end
        return a.attitude > b.attitude
    end)
    return candidates
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

--- 统计电影制作槽占用数（制作中 + 待发行；上映中和归档不占槽）
---@param state table
---@return number
function Culture.CountActiveFilmSlots(state)
    EnsureCulture(state)
    local n = 0
    for _, w in ipairs(state.culture.works) do
        if w.type == "film" and not w.archived then
            -- 上映中（screenings 非空）不占槽
            local isScreening = w.screenings and #w.screenings > 0
            if not isScreening then n = n + 1 end
        end
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
    local dTechs = {"d4a_nationalism","d5_radio","d5b_cinema",
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
        if w.type == "theater_troupe" and w.location then  -- 未派遣的剧团不产生 CP
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
        -- 邻近未占领地区 +epic_neighbor_cp：本土邻国 + 已占领国家的邻国
        if state.europe then
            for countryId, _ in pairs(GetEpicNeighborTargets(state)) do
                if state.europe[countryId] then
                    Culture.AddRegionCP(state, countryId, epicCount * (BC_.epic_neighbor_cp or 1))
                end
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
            if not mission.pending_event
               and math.random() < (BC_.mission_event_chance or 0.20)
               and not mission.event_this_turn then
                mission.pending_event = Culture.RollMissionEvent(state, mission)
                mission.event_this_turn = true
            else
                mission.event_this_turn = false
            end

            -- 检查是否到期
            if mission.turns_elapsed >= (BC_.mission_max_turns or 6) then
                table.insert(log, string.format("文化使团【%s】完成（共 %d 季）",
                    mission.target, mission.turns_elapsed))
                if (mission.att_bonus_on_complete or 0) > 0 then
                    AddAttitude(state, mission.target, mission.att_bonus_on_complete)
                    table.insert(log, string.format("文化使团官方访问提升 %s 好感 +%d",
                        GetCountryLabel(state, mission.target), mission.att_bonus_on_complete))
                end
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

    -- ── 8. 电影：生产推进 + 上映结算 ────────────────────────────────
    local tiers_     = BC_.film_tier or {}
    local themeBonus_ = BC_.film_theme_bonus or {}
    for _, w in ipairs(cult.works) do
        if w.type == "film" and not w.archived then
            -- 8a. 制作推进
            if not w.ready and (not w.screenings or #w.screenings == 0) then
                w.prod_progress = (w.prod_progress or 0) + 1
                local prodTurns = w.prod_turns or 2
                if w.prod_progress >= prodTurns then
                    w.ready = true
                    table.insert(log, string.format("电影【%s题材】制作完成，可选择上映地区", w.theme or "新作"))
                end
            end

            -- 8b. 上映结算
            if w.screenings and #w.screenings > 0 then
                local bonus = themeBonus_[w.theme or ""] or {}
                local remainingScreenings = {}
                for _, sc in ipairs(w.screenings) do
                    -- CP 增加
                    if (sc.cp_per_turn or 0) > 0 then
                        Culture.AddRegionCP(state, sc.region_id, sc.cp_per_turn)
                    end
                    -- 票房收入（通胀调整）
                    local income = sc.income_per_turn or 0
                    if income > 0 then
                        local inflFactor = state.inflation_factor or 1.0
                        local adjustedIncome = math.floor(income * inflFactor)
                        state.cash = (state.cash or 0) + adjustedIncome
                        w.total_income = (w.total_income or 0) + adjustedIncome
                    end
                    -- 好感加成（节庆/主题）
                    if (sc.att_per_turn or 0) > 0 then
                        AddAttitude(state, sc.region_id, sc.att_per_turn)
                    end
                    -- 倒计时
                    sc.turns_remaining = (sc.turns_remaining or 1) - 1
                    if sc.turns_remaining > 0 then
                        table.insert(remainingScreenings, sc)
                    else
                        local tierLabel = ({domestic="国内",friendly="友好发行",festival="节庆展映",intl="国际市场"})[sc.tier or ""] or ""
                        table.insert(log, string.format("电影【%s题材】在 %s[%s] 下映，累计票房 %d 克朗",
                            w.theme or "?", sc.region_id, tierLabel, w.total_income or 0))
                    end
                end
                w.screenings = remainingScreenings
                -- 所有上映结束 → 归档
                if #w.screenings == 0 then
                    w.archived = true
                    table.insert(log, string.format("电影【%s题材】全部下映，累计票房 %d 克朗",
                        w.theme or "?", w.total_income or 0))
                end
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
    local troupeCost = math.floor((BC.troupe_cost or 200) * GameState.GetInflationFactor(state))
    if (state.cash or 0) < troupeCost then
        return false, string.format("克朗不足（需要 %d）", troupeCost)
    end
    if AvailableAP(state) < (BC.troupe_create_ap or 1) then
        return false, string.format("AP 不足（需要 %d）", BC.troupe_create_ap or 1)
    end
    if Culture.CountWorks(state, "theater_troupe") >= (BC.troupe_global_max or 8) then
        return false, string.format("剧团总数已达上限（%d）", BC.troupe_global_max or 8)
    end
    return true
end

--- 创建歌舞剧团（培养，不绑定地点，自动分配 troupe_id）
---@param state table
---@return boolean ok, string|nil msg
function Culture.CreateTroupe(state)
    local ok, reason = Culture.CanCreateTroupe(state)
    if not ok then return false, reason end
    -- 找下一个可用 troupe_id（t1-t8）
    local usedIds = {}
    for _, w in ipairs(state.culture.works) do
        if w.type == "theater_troupe" and w.troupe_id then
            usedIds[w.troupe_id] = true
        end
    end
    local nextId = "t1"
    for i = 1, 8 do
        local tid = "t" .. i
        if not usedIds[tid] then
            nextId = tid
            break
        end
    end
    state.cash = state.cash - math.floor((BC.troupe_cost or 200) * GameState.GetInflationFactor(state))
    SpendAP(state, BC.troupe_create_ap or 1)
    table.insert(state.culture.works, {
        type         = "theater_troupe",
        troupe_id    = nextId,
        location     = nil,   -- 未驻扎，需后续派遣
        created_turn = state.turn or 0,
    })
    state.culture_action_this_turn = true
    return true, "歌舞剧团培养完成，可前往作品页派遣至目标地区"
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
    if AvailableAP(state) < (BC.troupe_move_ap or 1) then
        return false, "AP 不足"
    end
    SpendAP(state, BC.troupe_move_ap or 1)
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
    local cost = math.floor((BC.film_cost or 350) * GameState.GetInflationFactor(state))
    if (state.cash or 0) < cost then
        return false, string.format("克朗不足（需要 %d）", cost)
    end
    local activeMax = BC.film_active_max or 5
    if Culture.CountActiveFilmSlots(state) >= activeMax then
        return false, string.format("制作槽已满（%d/%d），等待现有影片上映后再开新片", activeMax, activeMax)
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
    local cost = math.floor((BC.film_cost or 350) * GameState.GetInflationFactor(state))
    state.cash = state.cash - cost
    -- 根据主题确定制作周期
    local turnsByTheme = (BC.film_prod_turns_by_theme or {})
    local prodTurns = turnsByTheme[theme] or 2
    table.insert(state.culture.works, {
        type         = "film",
        theme        = theme,
        ready        = false,
        archived     = false,
        prod_progress = 0,
        prod_turns   = prodTurns,
        screenings   = {},       -- 上映中的各地区计划
        total_income = 0,        -- 累计票房收益
        created_turn = state.turn or 0,
    })
    state.culture_action_this_turn = true
    return true, string.format("开始拍摄【%s题材】影片（需 %d 季制作，花费 %d 克朗）",
        theme, prodTurns, cost)
end

--- 发行电影（新系统：多地区同步上映）
--- targets 是一个地区 ID 列表，每个地区按其 tier 产生对应效果
---@param state table
---@param workIdx number  works 下标
---@param targetIds table  string[] 目标地区/国家 ID 列表
---@return boolean ok, string|nil msg
function Culture.ReleaseFilm(state, workIdx, targetIds)
    EnsureCulture(state)
    local work = state.culture.works[workIdx]
    if not work or work.type ~= "film" or not work.ready then
        return false, "电影尚未制作完成"
    end
    if work.screenings and #work.screenings > 0 then
        return false, "该电影已在上映中"
    end
    if not targetIds or #targetIds == 0 then
        return false, "请至少选择一个发行地区"
    end

    -- 构建目标查找表（id→tier 信息）
    local allTargets = Culture.GetFilmTargets(state)
    local targetMap  = {}
    for _, t in ipairs(allTargets) do targetMap[t.id] = t end

    local screeningTurns = BC.film_screening_turns or 2
    local tiers          = BC.film_tier or {}
    local themeBonus     = (BC.film_theme_bonus or {})[work.theme or ""] or {}

    local addedScreenings = {}
    local msgs = {}

    for _, tid in ipairs(targetIds) do
        local t = targetMap[tid]
        if not t then
            -- 跳过无效 ID
        elseif not t.tier then
            -- 好感不足，跳过（UI 已过滤，这里是防御）
        else
            local tierCfg = tiers[t.tier] or {}
            local cpPerTurn     = (tierCfg.cp     or 0) + (themeBonus.cp  or 0)
            local incomePerTurn = (tierCfg.income or 0) + (themeBonus.income or 0)
            local attPerTurn    = (tierCfg.att_bonus or 0) + (themeBonus.att or 0)
            table.insert(addedScreenings, {
                region_id       = tid,
                tier            = t.tier,
                turns_remaining = screeningTurns,
                cp_per_turn     = cpPerTurn,
                income_per_turn = incomePerTurn,
                att_per_turn    = attPerTurn,
            })
            local tierLabel = ({ domestic="国内", friendly="友好发行", festival="节庆展映", intl="国际市场" })[t.tier] or t.tier
            table.insert(msgs, string.format("%s[%s]", t.label, tierLabel))
        end
    end

    if #addedScreenings == 0 then
        return false, "所选地区均无法发行（好感不足或无效）"
    end

    work.screenings   = work.screenings or {}
    for _, s in ipairs(addedScreenings) do
        table.insert(work.screenings, s)
    end
    work.ready   = false   -- 已发行，不再显示"待发行"状态

    return true, string.format("影片开始上映：%s（共 %d 季）", table.concat(msgs, "、"), screeningTurns)
end

--- 查询电影是否处于"上映中"状态
---@param work table
---@return boolean
function Culture.IsFilmScreening(work)
    return work.type == "film" and work.screenings and #work.screenings > 0
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
    local epicCost = math.floor((BC.epic_cost or 300) * GameState.GetInflationFactor(state))
    if (state.cash or 0) < epicCost then
        return false, string.format("克朗不足（需要 %d）", epicCost)
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
    state.cash = state.cash - math.floor((BC.epic_cost or 300) * GameState.GetInflationFactor(state))
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
    local sportsCost = math.floor((BC.sports_cost or 250) * GameState.GetInflationFactor(state))
    if (state.cash or 0) < sportsCost then
        return false, string.format("克朗不足（需要 %d）", sportsCost)
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

    state.cash = state.cash - math.floor((BC.sports_cost or 250) * GameState.GetInflationFactor(state))
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
    local candidates = {}
    for _, cand in ipairs(Culture.GetSportsInviteCandidates(state)) do
        candidates[cand.id] = cand
    end

    -- 邀请 AI 参赛
    for _, factionId in ipairs(invitedFactionIds or {}) do
        local cand = candidates[factionId]
        if cand then
            if (cand.attitude or 0) >= 10 then
                AddAttitude(state, factionId, BC.sports_invite_att or 10)
                table.insert(results.accepted, cand.label)
            elseif math.random() < (BC.sports_reject_chance or 0.30) then
                AddAttitude(state, factionId, BC.sports_reject_att or -5)
                table.insert(results.rejected, cand.label)
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
    local exhibitionCost = math.floor((BC.exhibition_cost or 800) * GameState.GetInflationFactor(state))
    if (state.cash or 0) < exhibitionCost then
        return false, string.format("克朗不足（需要 %d）", exhibitionCost)
    end
    if AvailableAP(state) < (BC.exhibition_ap or 2) then
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
    state.cash = state.cash - math.floor((BC.exhibition_cost or 800) * GameState.GetInflationFactor(state))
    SpendAP(state, BC.exhibition_ap or 2)
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
    local baseCP = BC.exhibition_base_cp or 15
    local maxCP  = BC.exhibition_max_cp or 40
    local cpBonus = math.floor(baseCP + techCount * 0.5 + rep * (maxCP - baseCP))
    cpBonus = clamp(cpBonus, baseCP, maxCP)

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
    local ciNeed = math.max(BC.mission_ci_min or 60, BC.mission_ci_launch or 80)
    if (state.culture.ci or 0) < ciNeed then
        return false, string.format("CI 储量不足（需要 %d，当前 %d）",
            ciNeed, state.culture.ci or 0)
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
    if AvailableAP(state) < (BC.mission_ap or 1) then
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
    SpendAP(state, BC.mission_ap or 1)
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
    if AvailableAP(state) < 1 then return false, "AP 不足" end
    for i, m in ipairs(state.culture.missions) do
        if m.target == targetRegionId then
            table.remove(state.culture.missions, i)
            SpendAP(state, 1)
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

function Culture.ResolveMissionEvent(state, targetRegionId, optionIdx)
    EnsureCulture(state)
    optionIdx = optionIdx or 1
    local mission = nil
    for _, m in ipairs(state.culture.missions or {}) do
        if m.target == targetRegionId then
            mission = m
            break
        end
    end
    if not mission or not mission.pending_event then
        return false, "没有待处理的使团事件"
    end
    local ev = mission.pending_event
    local opt = ev.options and ev.options[optionIdx]
    if not opt then return false, "无效选项" end

    if opt.cost_intel and (state.intel or 0) < opt.cost_intel then
        return false, string.format("情报不足（需要 %d）", opt.cost_intel)
    end
    if opt.cost_ci and (state.culture.ci or 0) < opt.cost_ci then
        return false, string.format("影响力不足（需要 %d）", opt.cost_ci)
    end
    if opt.cost_cash and (state.cash or 0) < opt.cost_cash then
        return false, string.format("克朗不足（需要 %d）", opt.cost_cash)
    end

    if (opt.cost_intel or 0) > 0 then
        state.intel = math.max(0, (state.intel or 0) - opt.cost_intel)
    end
    state.culture.ci = math.max(0, (state.culture.ci or 0) - (opt.cost_ci or 0))
    if (opt.cost_cash or 0) > 0 then
        state.cash = math.max(0, (state.cash or 0) - opt.cost_cash)
    end

    local cpDelta = (opt.cp_bonus or 0) + (opt.cp_penalty or 0)
    if cpDelta ~= 0 then
        Culture.AddRegionCP(state, targetRegionId, cpDelta)
    end
    if opt.ci_penalty then
        state.culture.ci = math.max(0, (state.culture.ci or 0) + opt.ci_penalty)
    end
    if opt.turn_penalty then
        mission.turns_elapsed = math.max(0, (mission.turns_elapsed or 0) - opt.turn_penalty)
    end
    if opt.att_bonus then
        mission.att_bonus_on_complete = (mission.att_bonus_on_complete or 0) + opt.att_bonus
    end

    mission.pending_event = nil
    mission.event_this_turn = false
    return true, string.format("%s：%s", ev.desc or "使团事件", opt.text or "已处理")
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
        works_troupe      = Culture.CountWorks(state, "theater_troupe"),
        works_film_active = Culture.CountActiveFilmSlots(state),
        works_film_max    = BC_.film_active_max or 5,
        works_film        = Culture.CountWorks(state, "film"),
        works_epic        = Culture.CountWorks(state, "national_epic"),
        missions_active = #(cult.missions or {}),
        sports_cooldown = cult.sports_cooldown or 0,
        exhibition_done = cult.exhibition_done or false,
        exhibition_progress = cult.exhibition_progress or 0,
    }
end

return Culture
