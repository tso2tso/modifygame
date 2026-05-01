-- ============================================================================
-- 历史分支事件系统（Phase 4）
-- 5 个关键分支节点 + 合作分数战后清算
-- 与现有事件系统完全兼容：格式、入队、弹窗、效果
-- ============================================================================

local GrandPowers = require("systems.grand_powers")
local GameState   = require("game_state")
local Equipment   = require("systems.equipment")
local Config      = require("config")

local BranchEvents = {}

-- ============================================================================
-- 分支事件定义（按章节排列）
-- 每个事件包含 condition(state) 来判断触发时机
-- ============================================================================

local BRANCH_EVENTS = {
    -- ================================================================
    -- Ch1 分支：萨拉热窝刺杀 (1914 Q2)
    -- 玩家可以通报、协助、不干预或斡旋
    -- ================================================================
    {
        id = "branch_assassination_1914",
        title = "萨拉热窝的枪声",
        icon = "🔫",
        desc = "塞尔维亚民族主义者普林西普正密谋刺杀奥匈帝国王储弗朗茨·斐迪南大公。这个阴谋正在萨拉热窝的街头酝酿——而你恰好掌握了一些关键信息。你的选择，可能改变整个欧洲的命运。",
        priority = "main",
        condition = function(state)
            return state.year == 1914 and state.quarter == 2
        end,
        options = {
            {
                text = "📩 向奥匈当局通报阴谋",
                desc = "背叛同胞换取帝国庇护，刺杀失败，一战推迟",
                effects = { collaboration_score = 10 },
                apply = function(state)
                    -- 刺杀失败 → 一战推迟
                    local ah = state.powers and state.powers["austria_hungary"]
                    if ah then
                        ah.attitude_to_player = math.min(100, ah.attitude_to_player + 25)
                    end
                    -- 推迟战争标记
                    state._branch_war_delayed = math.random(2, 4) -- 推迟2-4季度
                    GameState.AddLog(state, "[分支] 你向奥匈通报了刺杀阴谋，弗朗茨大公安全离开了萨拉热窝")
                end,
            },
            {
                text = "🗡️ 暗中协助刺杀组织",
                desc = "助推刺杀赢得塞尔维亚好感，但战火加速降临",
                effects = { collaboration_score = -5 },
                apply = function(state)
                    local serbia = state.powers and state.powers["serbia"]
                    if serbia then
                        serbia.attitude_to_player = math.min(100, (serbia.attitude_to_player or 0) + 20)
                    end
                    -- 战争加速
                    state._branch_war_accelerated = true
                    GameState.AddLog(state, "[分支] 你暗中协助了刺杀组织，大公遇刺身亡")
                end,
            },
            {
                text = "🤷 明哲保身，不予干预",
                desc = "袖手旁观，历史按原定轨道运行",
                effects = {},
                apply = function(state)
                    GameState.AddLog(state, "[分支] 你选择了袖手旁观，历史按原轨迹运行")
                end,
            },
            {
                text = "🕊️ 刺杀后紧急斡旋",
                desc = "需影响力≥40且双方态度≥0。成功率极低，但若成功可改写历史",
                effects = {},
                condition = function(state)
                    local totalInf = GameState.CalcTotalInfluence(state)
                    if totalInf < 40 then return false end
                    local ah = state.powers and state.powers["austria_hungary"]
                    local serbia = state.powers and state.powers["serbia"]
                    if ah and ah.attitude_to_player < 0 then return false end
                    if serbia and serbia.attitude_to_player and serbia.attitude_to_player < 0 then return false end
                    return true
                end,
                apply = function(state)
                    -- 5% 概率阻止升级（蝴蝶效应）
                    if math.random(100) <= 5 then
                        state._branch_war_prevented = true
                        state._branch_war_delayed = 99 -- 大幅推迟
                        GameState.AddLog(state, "[分支·蝴蝶效应] 你的斡旋奇迹般地阻止了战争升级！奥匈仅对塞尔维亚发出最后通牒")
                    else
                        state._branch_war_delayed = 1
                        GameState.AddLog(state, "[分支] 你尽力斡旋，但列强的战争机器已无法停止。战争仅推迟了一个季度")
                    end
                end,
            },
        },
    },

    -- ================================================================
    -- Ch2 分支：奥匈帝国的命运 (1918 Q2)
    -- ================================================================
    {
        id = "branch_austria_fate_1918",
        title = "帝国的黄昏",
        icon = "👑",
        desc = "奥匈帝国在战火中摇摇欲坠，各民族的独立运动此起彼伏。作为萨拉热窝的望族，你有机会影响帝国的最终命运——联邦化改革、加速南斯拉夫统一，或在乱局中谋取私利。",
        priority = "main",
        condition = function(state)
            if state.year ~= 1918 or state.quarter ~= 2 then return false end
            local ah = state.powers and state.powers["austria_hungary"]
            return ah and ah.active
        end,
        options = {
            {
                text = "🏛️ 推动联邦化改革",
                desc = "需奥匈态度≥40且影响力≥50。推动帝国联邦化，维持其存在但削弱",
                effects = { collaboration_score = 8 },
                condition = function(state)
                    local totalInf = GameState.CalcTotalInfluence(state)
                    if totalInf < 50 then return false end
                    local ah = state.powers and state.powers["austria_hungary"]
                    return ah and ah.attitude_to_player >= 40
                end,
                apply = function(state)
                    -- 联邦化：奥匈不完全解体（保留存在但削弱）
                    state._branch_ah_federalized = true
                    local ah = state.powers["austria_hungary"]
                    if ah then
                        ah.military = math.max(10, ah.military - 20)
                        ah.economy = math.max(20, ah.economy - 10)
                        ah.war_fatigue = 0
                        ah.attitude_to_player = math.min(100, ah.attitude_to_player + 20)
                    end
                    GameState.AddLog(state, "[分支] 你推动了奥匈帝国的联邦化改革，帝国改组为多民族联邦")
                end,
            },
            {
                text = "🇷🇸 支持南斯拉夫统一",
                desc = "站在民族统一一边，加速南斯拉夫建国",
                effects = { collaboration_score = -3 },
                apply = function(state)
                    state._branch_yugo_accelerated = true
                    GameState.AddLog(state, "[分支] 你积极支持南斯拉夫统一运动，为建国铺平道路")
                end,
            },
            {
                text = "💰 趁乱扩张地盘",
                desc = "需现金≥5000。趁乱大肆收购资产，代价不菲但收获丰厚",
                effects = { collaboration_score = 2 },
                condition = function(state)
                    return state.cash >= 5000
                end,
                apply = function(state)
                    local inf = GameState.GetInflationFactor(state)
                    local cost = math.floor(3000 * inf)
                    state.cash = state.cash - cost
                    -- 大幅提升本地控制权
                    for _, r in ipairs(state.regions) do
                        r.control = math.min(100, (r.control or 0) + 15)
                    end
                    -- 获取黄金
                    state.gold = state.gold + 5
                    GameState.AddLog(state, string.format("[分支] 你在帝国崩溃的混乱中大肆扩张，花费%d克朗获取了大量资产", cost))
                end,
            },
        },
    },

    -- ================================================================
    -- Ch3 分支：面对纳粹扩张 (1938 Q1)
    -- ================================================================
    {
        id = "branch_nazi_expansion_1938",
        title = "乌云压境",
        icon = "⚡",
        desc = "纳粹德国吞并了奥地利，锋芒直指东南欧。希特勒的目光已经越过阿尔卑斯山，投向巴尔干半岛。南斯拉夫王国人心惶惶。你的家族必须在暴风雨来临前做出抉择。",
        priority = "main",
        condition = function(state)
            if state.year ~= 1938 or state.quarter ~= 1 then return false end
            local nazi = state.powers and state.powers["nazi_germany"]
            return nazi and nazi.active
        end,
        options = {
            {
                text = "🤝 与德国资本深度合作",
                desc = "与德国深度绑定，短期暴富但占领时会被清算",
                effects = { collaboration_score = 8 },
                apply = function(state)
                    local inf = GameState.GetInflationFactor(state)
                    state.cash = state.cash + math.floor(2000 * inf)
                    local nazi = state.powers["nazi_germany"]
                    if nazi then
                        nazi.attitude_to_player = math.min(100, nazi.attitude_to_player + 20)
                    end
                    -- 标记：二战时被特殊关照
                    state._branch_nazi_collaborator = true
                    GameState.AddLog(state, "[分支] 你与德国资本建立了深度合作关系，经济腾飞")
                end,
            },
            {
                text = "🛡️ 加固防御，秘密备战",
                desc = "需武装≥15。暗中备战增强抵抗力量，为未来解放铺路",
                effects = { collaboration_score = -5 },
                condition = function(state)
                    return state.military and state.military.guards >= 15
                end,
                apply = function(state)
                    state.military.guards = state.military.guards + 5
                    state._branch_fortified = true
                    GameState.AddLog(state, "[分支] 你暗中加固了防御工事，储备了武器弹药")
                end,
            },
            {
                text = "🕊️ 外交斡旋保持中立",
                desc = "需影响力≥60。外交斡旋争取中立时间，推迟被入侵",
                effects = {},
                condition = function(state)
                    return GameState.CalcTotalInfluence(state) >= 60
                end,
                apply = function(state)
                    -- 推迟南斯拉夫被入侵
                    state._branch_yugo_neutral = true
                    GameState.AddLog(state, "[分支] 你积极斡旋，南斯拉夫暂时保持中立立场")
                end,
            },
        },
    },

    -- ================================================================
    -- Ch4 分支：萨拉热窝解放方式 (1944 Q2)
    -- ================================================================
    {
        id = "branch_liberation_1944",
        title = "解放的曙光",
        icon = "🌅",
        desc = "轴心国的力量正在瓦解。萨拉热窝的解放只是时间问题——但谁来解放、如何解放，将决定这座城市未来数十年的命运。铁托的游击队、苏联红军和西方盟军都在逼近。",
        priority = "main",
        condition = function(state)
            if state.year ~= 1944 or state.quarter ~= 2 then return false end
            local isOccupied = GrandPowers.IsSarajevoOccupied(state)
            return isOccupied
        end,
        options = {
            {
                text = "⏳ 等待游击队/苏联解放",
                desc = "静待正规力量解放，安全但被动",
                effects = {},
                apply = function(state)
                    GameState.AddLog(state, "[分支] 你选择等待正规解放力量，铁托的游击队正在逼近")
                end,
            },
            {
                text = "⚔️ 组织本地武装起义",
                desc = "需合作度≤-20且武装≥15。自己动手提前解放，消耗武装但赢得巨大声望",
                effects = { collaboration_score = -15 },
                condition = function(state)
                    return (state.collaboration_score or 0) <= -20
                        and state.military and state.military.guards >= 15
                end,
                apply = function(state)
                    local oldGuards = state.military.guards
                    state.military.guards = math.max(0, state.military.guards - 8)
                    local lost = oldGuards - state.military.guards
                    if lost > 0 then
                        Equipment.OnGuardsLost(state, lost)
                    end
                    state._branch_self_liberation = true

                    -- 提前解放萨拉热窝
                    local EuropeData = require("data.europe_data")
                    EuropeData.ChangeSovereignty(state.europe, "austria_hungary", "yugoslavia")

                    -- 获得巨大声望
                    for _, r in ipairs(state.regions) do
                        r.influence = math.min(100, (r.influence or 0) + 15)
                    end
                    GameState.AddLog(state, "[分支·起义] 你领导本地武装起义，萨拉热窝提前解放！获得'解放者'称号")
                end,
            },
            {
                text = "🤝 与西方盟军接洽",
                desc = "需影响力≥50。引入西方力量改变战后格局（蝴蝶效应）",
                effects = { collaboration_score = -5 },
                condition = function(state)
                    return GameState.CalcTotalInfluence(state) >= 50
                end,
                apply = function(state)
                    state._branch_western_zone = true
                    GameState.AddLog(state, "[分支·蝴蝶效应] 你成功与西方盟军建立联系，萨拉热窝被划入西方占领区")
                end,
            },
        },
    },

    -- ================================================================
    -- Ch5 分支：铁托的抉择 (1948 Q2)
    -- ================================================================
    {
        id = "branch_tito_split_1948",
        title = "铁幕降临",
        icon = "🪧",
        desc = "铁托与斯大林的矛盾公开化。南斯拉夫正走向独立自主的道路——还是继续留在苏联的阵营中？你的家族在这场地缘博弈中再次面临抉择。",
        priority = "main",
        condition = function(state)
            if state.year ~= 1948 or state.quarter ~= 2 then return false end
            return true
        end,
        options = {
            {
                text = "🇾🇺 支持铁托独立路线",
                desc = "需合作度≤0。站在铁托一边，获得经济回报和政治好感",
                effects = { collaboration_score = -5 },
                condition = function(state)
                    return (state.collaboration_score or 0) <= 0
                end,
                apply = function(state)
                    local inf = GameState.GetInflationFactor(state)
                    state.cash = state.cash + math.floor(1500 * inf)
                    local tito = state.powers and state.powers["tito_yugoslavia"]
                    if tito then
                        tito.attitude_to_player = math.min(100, tito.attitude_to_player + 25)
                        tito.economy = math.min(100, tito.economy + 10)
                    end
                    GameState.AddLog(state, "[分支] 你支持铁托走独立路线，西方援助开始流入")
                end,
            },
            {
                text = "🇷🇺 暗中为苏联传递情报",
                desc = "高风险赌博：极小概率改写历史，大概率被发现遭严惩",
                effects = { collaboration_score = 5 },
                apply = function(state)
                    -- 10% 概率阻止决裂（蝴蝶效应）
                    if math.random(100) <= 10 then
                        state._branch_tito_stays_soviet = true
                        GameState.AddLog(state, "[分支·蝴蝶效应] 你传递的情报阻止了决裂，南斯拉夫留在苏联阵营")
                    else
                        -- 被发现
                        local inf = GameState.GetInflationFactor(state)
                        state.cash = math.max(0, state.cash - math.floor(2000 * inf))
                        local tito = state.powers and state.powers["tito_yugoslavia"]
                        if tito then
                            tito.attitude_to_player = math.max(-100, tito.attitude_to_player - 30)
                        end
                        GameState.AddLog(state, "[分支] 你的间谍活动被发现！资产被罚没2000克朗，铁托政权对你高度警惕")
                    end
                end,
            },
            {
                text = "🌐 推动亲西方路线",
                desc = "需解放时选择了西方盟军。推动南斯拉夫整体转向西方（蝴蝶效应）",
                effects = {},
                condition = function(state)
                    return state._branch_western_zone == true
                end,
                apply = function(state)
                    state._branch_yugo_western = true
                    local tito = state.powers and state.powers["tito_yugoslavia"]
                    if tito then
                        tito.faction = "allies"
                    end
                    local inf = GameState.GetInflationFactor(state)
                    state.cash = state.cash + math.floor(3000 * inf)
                    GameState.AddLog(state, "[分支·蝴蝶效应] 凭借西方占领区的基础，你推动南斯拉夫走向西方阵营")
                end,
            },
        },
    },
}

-- ============================================================================
-- 合作分数战后清算事件 (1946 Q1)
-- ============================================================================

local POSTWAR_RECKONING = {
    id = "branch_postwar_reckoning_1946",
    title = "战后清算",
    icon = "⚖️",
    desc = "",  -- 动态生成
    priority = "main",
    condition = function(state)
        return state.year == 1946 and state.quarter == 1
    end,
}

--- 根据合作度生成清算事件
---@param state table
---@return table|nil event
local function BuildReckoningEvent(state)
    local score = state.collaboration_score or 0

    local event = {
        id = POSTWAR_RECKONING.id,
        title = POSTWAR_RECKONING.title,
        icon = POSTWAR_RECKONING.icon,
        priority = POSTWAR_RECKONING.priority,
        options = {},
    }

    if score >= 30 then
        -- 合作者清算
        event.desc = "战争结束了，但清算才刚刚开始。新政权的调查委员会翻开了你在占领期间的记录——大量与占领方的交易往来、供应合同、合作经营的证据堆满了桌面。你被定性为'合作者'。"
        event.options = {
            {
                text = "💰 接受罚没，低调求生",
                desc = "认罚求生，资产大幅缩水但保住性命和根基",
                apply = function(s)
                    s.cash = math.floor(s.cash * 0.5)
                    s.gold = math.floor(s.gold * 0.5)
                    for _, r in ipairs(s.regions) do
                        r.influence = math.max(0, math.floor((r.influence or 0) * 0.5))
                        r.control = math.max(10, math.floor((r.control or 0) * 0.7))
                    end
                    GameState.AddLog(s, "[清算] 你被定性为'合作者'，资产罚没50%")
                end,
            },
            {
                text = "🏃 转移资产出逃",
                desc = "携财出逃保住大部分资产，但在本地声望尽毁",
                apply = function(s)
                    s.cash = math.floor(s.cash * 0.7)
                    s.gold = math.floor(s.gold * 0.8)
                    for _, r in ipairs(s.regions) do
                        r.influence = 0
                        r.control = math.max(5, math.floor((r.control or 0) * 0.3))
                    end
                    GameState.AddLog(s, "[清算] 你携部分资产仓皇出逃，本地影响力归零")
                end,
            },
        }
    elseif score >= 10 then
        -- 灰色地带
        event.desc = "调查委员会审视了你的战时记录。虽然有一些与占领方合作的痕迹，但没有严重到需要公开清算的程度。你被列入'灰色名单'——小额罚款了事。"
        event.options = {
            {
                text = "💸 缴纳罚款，重新开始",
                desc = "小额罚款了事，影响不大",
                apply = function(s)
                    local fine = math.floor(s.cash * 0.15)
                    s.cash = s.cash - fine
                    GameState.AddLog(s, string.format("[清算] 你被列入'灰色名单'，缴纳%d克朗罚款", fine))
                end,
            },
        }
    elseif score > -10 then
        -- 普通市民
        event.desc = "新政权的调查对你没有特别关注。你在战争期间保持了中立立场，既没有积极合作，也没有冒险抵抗。生活继续。"
        event.options = {
            {
                text = "👤 普通人的日常继续",
                desc = "平安无事，生活照旧",
                apply = function(s)
                    GameState.AddLog(s, "[清算] 你以'普通市民'身份安然度过审查")
                end,
            },
        }
    elseif score > -30 then
        -- 抵抗者
        event.desc = "你在占领期间的抵抗行为被记录在案——资助游击队、庇护难民、破坏补给线。新政权将你认定为'抵抗者'，给予相应的政治地位和经济奖励。"
        event.options = {
            {
                text = "🎖️ 接受'抵抗者'荣誉",
                desc = "获得荣誉和奖励，在新政权中地位稳固",
                apply = function(s)
                    local inf = GameState.GetInflationFactor(s)
                    s.cash = s.cash + math.floor(1000 * inf)
                    for _, r in ipairs(s.regions) do
                        r.influence = math.min(100, (r.influence or 0) + 8)
                    end
                    GameState.AddLog(s, "[清算] 你被认定为'抵抗者'，获得荣誉和经济奖励")
                end,
            },
        }
    else
        -- 人民英雄
        event.desc = "你的名字出现在了解放纪念碑上。整个战争期间，你冒着生命危险资助游击队、破坏敌军补给、庇护被迫害者。新政权授予你'人民英雄'称号——国有化豁免、税收减免、终身政治荣誉。"
        event.options = {
            {
                text = "🏆 接受'人民英雄'称号",
                desc = "最高荣誉加身，丰厚奖赏和政治特权，前途一片光明",
                apply = function(s)
                    local inf = GameState.GetInflationFactor(s)
                    s.cash = s.cash + math.floor(3000 * inf)
                    s.gold = s.gold + 5
                    for _, r in ipairs(s.regions) do
                        r.influence = math.min(100, (r.influence or 0) + 15)
                        r.control = math.min(100, (r.control or 0) + 10)
                    end
                    -- 与铁托政权关系极佳
                    local tito = s.powers and s.powers["tito_yugoslavia"]
                    if tito then
                        tito.attitude_to_player = math.min(100, tito.attitude_to_player + 40)
                    end
                    GameState.AddLog(s, "[清算] 你被授予'人民英雄'称号，获得最高荣誉和丰厚奖励")
                end,
            },
        }
    end

    return event
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 检查当季是否有分支事件需要触发
---@param state table
---@return table[] events 需要入队的事件列表
function BranchEvents.CheckBranchEvents(state)
    local triggered = {}

    -- 检查 5 个分支节点
    for _, branchDef in ipairs(BRANCH_EVENTS) do
        if not state.events_fired[branchDef.id] then
            if branchDef.condition(state) then
                -- 过滤掉条件不满足的选项（标记为不可选但仍显示）
                local filteredOptions = {}
                for _, opt in ipairs(branchDef.options) do
                    local available = true
                    if opt.condition then
                        available = opt.condition(state)
                    end
                    table.insert(filteredOptions, {
                        text = opt.text,
                        desc = opt.desc .. (not available and "\n⛔ 条件不满足" or ""),
                        effects = opt.effects or {},
                        apply = available and opt.apply or nil,
                        _available = available,
                    })
                end

                table.insert(triggered, {
                    id = branchDef.id,
                    title = branchDef.title,
                    icon = branchDef.icon,
                    desc = branchDef.desc,
                    priority = branchDef.priority,
                    options = filteredOptions,
                    _is_branch = true,  -- 标记为分支事件
                })
            end
        end
    end

    -- 检查战后清算
    if not state.events_fired[POSTWAR_RECKONING.id] then
        if POSTWAR_RECKONING.condition(state) then
            local reckoningEvent = BuildReckoningEvent(state)
            if reckoningEvent then
                reckoningEvent._is_branch = true
                table.insert(triggered, reckoningEvent)
            end
        end
    end

    return triggered
end

--- 应用分支事件选项效果（由 Events.ApplyOption 的扩展调用）
---@param state table
---@param event table
---@param optionIndex number
---@return boolean handled 是否已处理
function BranchEvents.ApplyBranchOption(state, event, optionIndex)
    if not event._is_branch then return false end

    local option = event.options[optionIndex]
    if not option then return false end

    -- 应用 collaboration_score 效果
    if option.effects and option.effects.collaboration_score then
        state.collaboration_score = (state.collaboration_score or 0) + option.effects.collaboration_score
    end

    -- 执行自定义 apply 函数
    if option.apply then
        option.apply(state)
    elseif not option._available then
        -- 选项条件不满足，给出反馈
        GameState.AddLog(state, "[分支] 条件不满足，无法执行该行动")
    end

    return true
end

return BranchEvents
