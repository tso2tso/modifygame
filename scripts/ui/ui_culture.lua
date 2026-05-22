-- ============================================================================
-- 文化胜利路线面板（C5）— 二级目录导航版
-- 风格：严格对齐 ui_expedition / ui_venture 的 Section-Card + MetricCell 模式
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Config     = require("config")
local Balance    = require("data.balance")
local Culture    = require("systems.culture")
local EuropeData = require("data.europe_data")

local C  = Config.COLORS
local F  = Config.FONT
local S  = Config.SIZE
local BC = Balance.CULTURE

local CulturePanel = {}

-- ── 导航状态 ──
---@type string
local currentView_ = "root"
---@type table
local stateRef_ = nil
---@type function|nil
local onStateChanged_ = nil

-- ============================================================================
-- 地区名映射
-- ============================================================================
local _regionLabels = nil
local function GetRegionLabel(id)
    if not _regionLabels then
        _regionLabels = {}
        if EuropeData.COUNTRIES then
            for _, c in ipairs(EuropeData.COUNTRIES) do
                _regionLabels[c.id] = c.label
            end
        end
        local LOCAL = {
            capital_city    = "萨拉热窝（首都）",
            mine_district   = "矿区",
            industrial_town = "工业区",
            lowlands        = "低地国家",
            bosnia          = "波斯尼亚",
            sarajevo        = "萨拉热窝",
            mostar          = "莫斯塔尔",
            banja_luka      = "巴尼亚卢卡",
        }
        for k, v in pairs(LOCAL) do _regionLabels[k] = v end
    end
    return _regionLabels[id] or id
end

-- ============================================================================
-- 通用组件（完全对齐 ui_expedition 风格）
-- ============================================================================

--- 数值格子：值在上 + 小标签在下（与 ExpeditionPanel._MetricCell 相同）
local function MetricCell(label, value, color)
    return UI.Panel {
        flexGrow      = 1,
        flexDirection = "column",
        alignItems    = "center",
        gap           = 2,
        padding       = 4,
        backgroundColor = C.bg_elevated,
        borderRadius  = S.radius_badge or 4,
        children = {
            UI.Label {
                text       = tostring(value),
                fontSize   = F.data_small,
                fontWeight = "bold",
                fontColor  = color or C.text_primary,
            },
            UI.Label {
                text     = label,
                fontSize = F.label,
                fontColor = C.text_muted,
            },
        },
    }
end

--- 分节分割线（与 ExpeditionPanel._SectionDivider 相同）
local function SectionDivider(text, color)
    return UI.Panel {
        width         = "100%",
        flexDirection = "row",
        alignItems    = "center",
        gap           = 6,
        marginTop     = 8,
        marginBottom  = 4,
        flexShrink    = 0,
        children = {
            UI.Divider { flexGrow = 1, color = C.divider },
            UI.Label {
                text       = text,
                fontSize   = F.label,
                fontColor  = color or C.text_secondary,
                fontWeight = "bold",
            },
            UI.Divider { flexGrow = 1, color = C.divider },
        },
    }
end

--- 空状态提示（与 ui_venture._EmptyHint 相同）
local function EmptyHint(text)
    return UI.Label {
        text      = text,
        fontSize  = F.body_minor,
        fontColor = C.text_muted,
        textAlign = "center",
        width     = "100%",
        marginTop = 12,
        marginBottom = 12,
    }
end

--- 清理错误原因字符串（去掉科技ID括号，如「（d5b_cinema）」）
local function CleanReason(r)
    if not r then return "" end
    return r:gsub("（[%w_]+）", ""):gsub("%([%w_]+%)", ""):gsub("%s+$", "")
end

--- 操作按钮
local function Btn(text, accentColor, onClick, disabled)
    local ac = accentColor or C.accent_blue
    return UI.Button {
        text             = text,
        fontSize         = F.label,
        fontColor        = disabled and C.text_muted or C.text_primary,
        backgroundColor  = disabled and C.bg_surface or { ac[1], ac[2], ac[3], 45 },
        borderRadius     = S.radius_btn or 4,
        borderWidth      = disabled and 0 or 1,
        borderColor      = disabled and nil or { ac[1], ac[2], ac[3], 140 },
        paddingHorizontal = 10,
        paddingVertical  = 5,
        disabled         = disabled or false,
        onClick          = onClick,
    }
end

--- CP 等级颜色
local function CPColor(cp)
    if cp >= (BC.cp_assimilation or 90) then return C.accent_amber
    elseif cp >= (BC.cp_identity  or 70) then return C.accent_green
    elseif cp >= (BC.cp_admire    or 50) then return C.accent_blue
    elseif cp >= (BC.cp_curious   or 30) then return C.accent_gold
    else return C.text_muted end
end

--- 内联错误提示
local function ErrHint(msg)
    if not msg or msg == "" then return UI.Panel{} end
    return UI.Label {
        text     = "! " .. msg,
        fontSize = F.label,
        fontColor = C.accent_red,
        marginTop = 2,
    }
end

-- ============================================================================
-- 子页框架：顶部返回栏
-- ============================================================================
local function SubPage(title, accentColor, children)
    local ac = accentColor or C.accent_gold
    local rows = {
        UI.Panel {
            width           = "100%",
            flexDirection   = "row",
            alignItems      = "center",
            padding         = S.card_padding or 8,
            marginBottom    = S.card_gap or 6,
            gap             = 10,
            backgroundColor = C.paper_dark,
            borderRadius    = S.radius_card or 6,
            borderWidth     = 1,
            borderColor     = C.border_soft,
            children = {
                UI.Button {
                    text            = "< 返回",
                    fontSize        = F.label,
                    paddingHorizontal = 10,
                    paddingVertical = 4,
                    backgroundColor = C.bg_elevated,
                    fontColor       = C.text_secondary,
                    borderRadius    = S.radius_btn or 4,
                    borderWidth     = 1,
                    borderColor     = C.border_soft,
                    onClick = function()
                        currentView_ = "root"
                        if onStateChanged_ then onStateChanged_("nav") end
                    end,
                },
                UI.Label {
                    text       = title,
                    fontSize   = F.body_minor,
                    fontColor  = { ac[1], ac[2], ac[3], 255 },
                    fontWeight = "bold",
                    flexGrow   = 1,
                },
            },
        },
    }
    for _, c in ipairs(children) do table.insert(rows, c) end
    return UI.Panel {
        width         = "100%",
        flexDirection = "column",
        gap           = S.card_gap or 6,
        paddingTop    = S.card_gap or 6,
        children      = rows,
    }
end

-- ============================================================================
-- 根页
-- ============================================================================
local function _BuildRoot(state)
    local cult  = state.culture or {}
    local ci    = cult.ci or 0
    local score = cult.score or 0
    local worksCount    = #(cult.works or {})
    local missionsCount = #(cult.missions or {})
    local cpCount = 0
    for _ in pairs(cult.region_cp or {}) do cpCount = cpCount + 1 end

    local prog     = Culture.GetVictoryProgress(state)
    local metCount = 0
    if prog.year_met         then metCount = metCount + 1 end
    if prog.tech_hegemony    then metCount = metCount + 1 end
    if prog.tech_renaissance then metCount = metCount + 1 end
    if prog.way_a_met or prog.way_b_met then metCount = metCount + 1 end
    if prog.score_met        then metCount = metCount + 1 end

    local gross, decay = Culture.CalcCIGain(state)
    local delta    = gross - decay
    local deltaStr = delta >= 0 and string.format("+%d/季", delta)
                                 or string.format("%d/季",  delta)
    local deltaColor = delta >= 0 and C.accent_green or C.accent_red

    -- ── 概览卡 ──
    local summaryCard = UI.Panel {
        width           = "100%",
        backgroundColor = C.paper_dark,
        borderRadius    = S.radius_card,
        borderWidth     = 1,
        borderColor     = C.border_gold,
        padding         = S.card_padding,
        flexDirection   = "column",
        gap             = 6,
        children = {
            UI.Label {
                text       = "文化胜利概览",
                fontSize   = F.card_title or F.body_minor,
                fontColor  = C.text_primary,
                fontWeight = "bold",
            },
            -- 第一行：文化影响力 / 影响/季 / 积分 / 胜利条件
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 4,
                children = {
                    MetricCell("文化影响力", ci, C.accent_gold),
                    MetricCell("影响力/季", deltaStr, deltaColor),
                    MetricCell("积分", score, C.text_primary),
                    MetricCell("胜利条件",
                        string.format("%d/5", metCount),
                        metCount >= 5 and C.accent_green or C.accent_amber),
                },
            },
            -- 第二行：文化作品 / 使团 / 渗透地区 / 文化行动
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 4,
                children = {
                    MetricCell("文化作品", worksCount, C.accent_blue),
                    MetricCell("海外使团", missionsCount, C.accent_blue),
                    MetricCell("渗透地区", cpCount, C.accent_green),
                    MetricCell("文化行动",
                        state.culture_action_this_turn and "已用" or "可用",
                        state.culture_action_this_turn and C.text_muted or C.accent_green),
                },
            },
        },
    }

    -- ── 导航行（无独立背景，由 GroupCard 统一提供）──
    local function NavRow(label, subtitle, accentCol, viewId, rightText, rightColor)
        local ac = accentCol or C.accent_blue
        return UI.Button {
            width           = "100%",
            padding         = 0,
            backgroundColor = { 0, 0, 0, 0 },
            onClick = function()
                currentView_ = viewId
                if onStateChanged_ then onStateChanged_("nav") end
            end,
            children = {
                UI.Panel {
                    width         = "100%",
                    flexDirection = "row",
                    alignItems    = "center",
                    paddingHorizontal = S.card_padding,
                    paddingVertical   = 12,
                    gap           = 10,
                    children = {
                        UI.Panel {
                            width = 3, height = 34,
                            backgroundColor = { ac[1], ac[2], ac[3], 200 },
                            borderRadius = 2, flexShrink = 0,
                        },
                        UI.Panel {
                            flexGrow = 1, flexShrink = 1,
                            flexDirection = "column", gap = 3,
                            children = {
                                UI.Label {
                                    text = label, fontSize = F.body_minor,
                                    fontColor = C.text_primary, fontWeight = "bold",
                                },
                                UI.Label {
                                    text = subtitle, fontSize = F.label,
                                    fontColor = C.text_secondary, flexWrap = "wrap",
                                },
                            },
                        },
                        UI.Label {
                            text = rightText or "", fontSize = F.label,
                            fontColor = rightColor or C.text_muted,
                            fontWeight = "bold", flexShrink = 0,
                        },
                        UI.Label {
                            text = ">", fontSize = 14,
                            fontColor = C.text_muted, flexShrink = 0,
                        },
                    },
                },
            },
        }
    end

    -- ── 分组卡片：多行导航共用一个卡片背景，行间用分割线隔开 ──
    local function GroupCard(rows)
        local children = {}
        for i, row in ipairs(rows) do
            table.insert(children, row)
            if i < #rows then
                table.insert(children, UI.Divider { color = C.divider, width = "100%" })
            end
        end
        return UI.Panel {
            width           = "100%",
            backgroundColor = C.paper_dark,
            borderRadius    = S.radius_card,
            borderWidth     = 1,
            borderColor     = C.border_soft,
            overflow        = "hidden",
            flexDirection   = "column",
            flexShrink      = 0,
            children        = children,
        }
    end

    return UI.Panel {
        width         = "100%",
        flexDirection = "column",
        gap           = S.card_gap,
        paddingTop    = S.card_gap,
        children = {
            summaryCard,
            SectionDivider("当前局势", C.accent_blue),
            GroupCard({
                NavRow("现有文化作品",
                    string.format("已创作 %d 件（剧团 / 电影 / 史诗）", worksCount),
                    C.accent_blue, "works",
                    tostring(worksCount) .. " 件", C.text_label),
                NavRow("地区文化渗透",
                    string.format("已渗透 %d 个地区", cpCount),
                    C.accent_green, "cp",
                    tostring(cpCount) .. " 地区", C.accent_green),
            }),
            SectionDivider("文化行动", C.accent_gold),
            GroupCard({
                NavRow("文化创作",
                    "创作剧团、电影、史诗、举办赛事与世博",
                    C.accent_gold, "create",
                    state.culture_action_this_turn and "已行动" or "可行动",
                    state.culture_action_this_turn and C.text_muted or C.accent_green),
                NavRow("海外文化使团",
                    string.format("进行中 %d 支  —  派遣使团提升海外文化渗透值", missionsCount),
                    C.accent_blue, "missions",
                    string.format("%d 支", missionsCount), C.text_label),
            }),
            SectionDivider("胜利目标", C.accent_amber),
            GroupCard({
                NavRow("胜利进度",
                    string.format("达成条件 %d / 5", metCount),
                    C.accent_amber, "victory",
                    metCount >= 5 and "已达成" or string.format("%d/5", metCount),
                    metCount >= 5 and C.accent_green or C.accent_gold),
            }),
        },
    }
end

-- ============================================================================
-- 子页：胜利进度
-- ============================================================================
local function _BuildVictoryPage(state)
    local prog = Culture.GetVictoryProgress(state)
    local BC_  = Balance.CULTURE

    -- 条件行（纯文字，不用特殊符号避免渲染问题）
    local function CondRow(met, label)
        local tagText  = met and "[达成]" or "[未达]"
        local tagColor = met and C.accent_green or C.text_muted
        local textColor = met and C.text_primary or C.text_secondary
        return UI.Panel {
            width         = "100%",
            flexDirection = "row",
            alignItems    = "flex-start",
            gap           = 8,
            marginBottom  = 5,
            children = {
                UI.Label {
                    text       = tagText,
                    fontSize   = F.label,
                    fontColor  = tagColor,
                    fontWeight = "bold",
                    width      = 44,
                },
                UI.Label {
                    text     = label,
                    fontSize = F.body_minor,
                    fontColor = textColor,
                    flexGrow  = 1,
                    flexWrap  = "wrap",
                },
            },
        }
    end

    -- 进度条
    local function ProgBar(value, maxV, color)
        local pct = maxV > 0 and math.min(1.0, value / maxV) or 0
        return UI.ProgressBar {
            value        = pct,
            height       = 5,
            trackColor   = C.bg_inset,
            fillColor    = color or C.accent_gold,
            borderRadius = 2,
        }
    end

    local wayANow = prog.identity_count
    local wayAMax = BC_.victory_cp_identity or 3
    local wayBNow = prog.assim_count
    local wayBMax = BC_.victory_cp_assimilation or 2

    local function CondCard(title, borderCol, rows)
        local items = { UI.Label {
            text = title, fontSize = F.body_minor, fontColor = C.text_secondary,
            fontWeight = "bold", marginBottom = 4,
        }}
        for _, r in ipairs(rows) do table.insert(items, r) end
        return UI.Panel {
            width = "100%", padding = S.card_padding,
            backgroundColor = C.bg_surface,
            borderRadius = S.radius_card, borderWidth = 1,
            borderColor = borderCol or C.border_soft,
            children = items,
        }
    end

    return SubPage("胜利进度详情", C.accent_amber, {
        CondCard("基础条件", C.border_gold, {
            CondRow(prog.year_met,
                string.format("年份 >= %d（当前 %d）",
                    BC_.victory_year or 1938, state.year or 0)),
            CondRow(prog.tech_hegemony,  "科技：文化霸权"),
            CondRow(prog.tech_renaissance, "科技：文化复兴"),
        }),
        CondCard("方式甲  地区文化认同", C.border_soft, {
            CondRow(prog.way_a_met,
                string.format("%d / %d 个地区达到文化认同（渗透值 >= 70）",
                    wayANow, wayAMax)),
            ProgBar(wayANow, wayAMax, C.accent_green),
        }),
        CondCard("方式乙  文化同化", C.border_soft, {
            CondRow(prog.way_b_met,
                string.format("%d / %d 个地区文化同化（渗透值 >= 90）且影响力 >= 150",
                    wayBNow, wayBMax)),
            ProgBar(wayBNow, wayBMax, C.accent_amber),
        }),
        CondCard("积分领先", C.border_soft, {
            CondRow(prog.score_met,
                string.format("积分领先 AI：%d / %d",
                    math.max(0, prog.score_lead), BC_.victory_score_lead or 500)),
            ProgBar(math.max(0, prog.score_lead),
                BC_.victory_score_lead or 500, C.accent_gold),
        }),
    })
end

-- ============================================================================
-- 子页：现有文化作品
-- ============================================================================
local FILM_THEMES = { historical = "历史", national = "民族", industrial = "工业" }
local EPIC_THEMES = { national = "民族史诗", religious = "宗教史诗", historical = "历史史诗" }

local function _FilmButtons(state, work, idx)
    if not (work.type == "film" and work.ready and not work.released) then return nil end
    local targets = Culture.GetFilmTargets(state)

    -- 顶部行：国内公映
    local topRow = UI.Panel {
        width = "100%", flexDirection = "row", gap = 6,
        children = {
            Btn("国内公映", C.accent_green, function()
                local ok, msg = Culture.ReleaseFilm(state, idx, "domestic")
                if onStateChanged_ then onStateChanged_(ok and msg or ("发行失败：" .. (msg or ""))) end
            end),
        },
    }

    if #targets == 0 then
        return UI.Panel { width="100%", flexDirection="column", gap=6, marginTop=6,
            children = { topRow } }
    end

    -- 国际目标（全量）
    local intlBtns = {}
    for _, target in ipairs(targets) do
        local tid = target.id
        table.insert(intlBtns, Btn(GetRegionLabel(tid), C.accent_blue, function()
            local ok, msg = Culture.ReleaseFilm(state, idx, "international", tid)
            if onStateChanged_ then onStateChanged_(ok and msg or ("发行失败：" .. (msg or ""))) end
        end))
    end

    -- 节庆目标（全量）
    local festBtns = {}
    for _, target in ipairs(targets) do
        local tid = target.id
        table.insert(festBtns, Btn(GetRegionLabel(tid), C.accent_amber, function()
            local ok, msg = Culture.ReleaseFilm(state, idx, "festival", tid)
            if onStateChanged_ then onStateChanged_(ok and msg or ("发行失败：" .. (msg or ""))) end
        end))
    end

    return UI.Panel {
        width = "100%", flexDirection = "column", gap = 6, marginTop = 6,
        children = {
            topRow,
            UI.Panel { flexDirection="row", alignItems="center", gap=6, children = {
                UI.Label { text="国际", fontSize=F.label, fontColor=C.text_muted, width=28 },
                UI.Panel { flexDirection="row", flexWrap="wrap", gap=6, flexGrow=1,
                    children=intlBtns },
            }},
            UI.Panel { flexDirection="row", alignItems="center", gap=6, children = {
                UI.Label { text="节庆", fontSize=F.label, fontColor=C.text_muted, width=28 },
                UI.Panel { flexDirection="row", flexWrap="wrap", gap=6, flexGrow=1,
                    children=festBtns },
            }},
        },
    }
end

local function _BuildWorksPage(state)
    local works = state.culture and state.culture.works or {}
    local troupes, films, epics = {}, {}, {}
    for i, w in ipairs(works) do
        if w.type == "theater_troupe"  then table.insert(troupes, { w=w, i=i })
        elseif w.type == "film"        then table.insert(films,   { w=w, i=i })
        elseif w.type == "national_epic" then table.insert(epics, { w=w, i=i })
        end
    end

    if #works == 0 then
        return SubPage("现有文化作品", C.accent_blue, {
            EmptyHint("尚无文化作品，前往「文化创作」创建"),
        })
    end

    local rows = {}

    -- 剧团
    if #troupes > 0 then
        table.insert(rows, SectionDivider("歌舞剧团  " .. #troupes .. " 支", C.accent_blue))
        for _, item in ipairs(troupes) do
            local w = item.w
            local n = Culture.GetTroupeCount(state, w.location or "")
            local cpPerSeason = (BC.troupe_cp or {5,3,1})[n] or 1
            table.insert(rows, UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                padding = S.card_padding,
                backgroundColor = C.bg_surface,
                borderRadius = S.radius_card, borderWidth = 1, borderColor = C.border_soft,
                gap = 10,
                children = {
                    UI.Panel { width=3, height=30,
                        backgroundColor = C.accent_blue, borderRadius=2 },
                    UI.Panel { flexGrow=1, gap=2, children={
                        UI.Label { text=GetRegionLabel(w.location or "?"),
                            fontSize=F.body_minor, fontColor=C.text_primary, fontWeight="bold" },
                        UI.Label { text=string.format("每季 +%d 渗透值", cpPerSeason),
                            fontSize=F.label, fontColor=C.accent_green },
                    }},
                    UI.Label { text=string.format("第 %d 支", n),
                        fontSize=F.label, fontColor=C.text_muted },
                },
            })
        end
    end

    -- 电影
    if #films > 0 then
        table.insert(rows, SectionDivider("电影作品  " .. #films .. " 部", C.accent_green))
        for _, item in ipairs(films) do
            local w = item.w
            local themeLabel = FILM_THEMES[w.theme] or (w.theme or "?")
            local statusText, statusColor
            if w.released then
                statusText  = "已发行 — " .. (
                    w.release_mode == "domestic"      and "国内公映" or
                    w.release_mode == "international" and "国际发行" or "节庆展映")
                statusColor = C.text_muted
            elseif w.ready then
                statusText  = "制作完成，可发行"
                statusColor = C.accent_green
            else
                statusText  = string.format("制作中  %d/%d 季",
                    w.prod_progress or 0, BC.film_prod_turns or 2)
                statusColor = C.accent_amber
            end
            local filmBtns = _FilmButtons(state, w, item.i)
            local isReady    = w.ready and not w.released
            local isReleased = w.released
            -- 左竖条颜色：可发行=绿，已发行=灰，制作中=橙
            local barColor = isReady and C.accent_green
                          or isReleased and C.text_muted
                          or C.accent_amber

            -- 已发行的电影用紧凑行布局；待发行/制作中用展开卡片布局
            if isReleased then
                table.insert(rows, UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center",
                    paddingHorizontal = S.card_padding, paddingVertical = 8,
                    backgroundColor = C.bg_surface,
                    borderRadius = S.radius_card, borderWidth = 1, borderColor = C.border_soft,
                    gap = 10,
                    children = {
                        UI.Panel { width=3, height=28, backgroundColor=barColor, borderRadius=2, flexShrink=0 },
                        UI.Label { text=themeLabel.."题材",
                            fontSize=F.body_minor, fontColor=C.text_secondary, flexGrow=1 },
                        UI.Label { text=statusText, fontSize=F.label, fontColor=statusColor },
                    },
                })
            else
                table.insert(rows, UI.Panel {
                    width = "100%", padding = S.card_padding,
                    backgroundColor = C.bg_surface,
                    borderRadius = S.radius_card, borderWidth = 1,
                    borderColor = isReady and { C.accent_green[1], C.accent_green[2], C.accent_green[3], 180 } or C.border_soft,
                    flexDirection = "column", gap = 4,
                    children = {
                        UI.Panel { flexDirection="row", alignItems="center", gap=10, children = {
                            UI.Panel { width=3, height=28, backgroundColor=barColor, borderRadius=2, flexShrink=0 },
                            UI.Label { text=themeLabel.."题材",
                                fontSize=F.body_minor, fontColor=C.text_primary, fontWeight="bold", flexGrow=1 },
                            UI.Label { text=statusText, fontSize=F.label, fontColor=statusColor },
                        }},
                        filmBtns or UI.Panel{},
                    },
                })
            end
        end
    end

    -- 史诗
    if #epics > 0 then
        table.insert(rows, SectionDivider("民族史诗  " .. #epics .. " 部", C.accent_amber))
        for _, item in ipairs(epics) do
            local w = item.w
            table.insert(rows, UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                padding = S.card_padding,
                backgroundColor = C.bg_surface,
                borderRadius = S.radius_card, borderWidth = 1, borderColor = C.border_soft,
                gap = 10,
                children = {
                    UI.Panel { width=3, height=30,
                        backgroundColor=C.accent_amber, borderRadius=2 },
                    UI.Panel { flexGrow=1, gap=2, children={
                        UI.Label { text=EPIC_THEMES[w.theme] or (w.theme or "?"),
                            fontSize=F.body_minor, fontColor=C.text_primary, fontWeight="bold" },
                        UI.Label {
                            text=string.format("+%d 影响力/季  控制区 +%d 渗透值/季",
                                BC.ci_epic_bonus or 2, BC.epic_own_cp or 2),
                            fontSize=F.label, fontColor=C.accent_amber },
                    }},
                },
            })
        end
    end

    return SubPage("现有文化作品  " .. #works .. " 件", C.accent_blue, rows)
end

-- ============================================================================
-- 子页：地区 CP
-- ============================================================================
local function _BuildCPPage(state)
    local cult  = state.culture or {}
    local items = {}
    for regionId, cp in pairs(cult.region_cp or {}) do
        table.insert(items, { id=regionId, cp=cp })
    end
    table.sort(items, function(a,b) return a.cp > b.cp end)

    if #items == 0 then
        return SubPage("地区文化渗透", C.accent_green, {
            EmptyHint("尚无文化积累——创作作品或派遣使团后开始积累"),
        })
    end

    -- 按等级分组
    local groups = {
        { label="文化同化", color=C.accent_amber,  threshold=BC.cp_assimilation or 90, items={} },
        { label="文化认同", color=C.accent_green,  threshold=BC.cp_identity    or 70,  items={} },
        { label="文化倾慕", color=C.accent_blue,   threshold=BC.cp_admire      or 50,  items={} },
        { label="文化好奇", color=C.accent_gold,   threshold=BC.cp_curious     or 30,  items={} },
        { label="无感知",   color=C.text_muted,    threshold=0,                         items={} },
    }
    for _, item in ipairs(items) do
        for _, g in ipairs(groups) do
            if item.cp >= g.threshold then
                table.insert(g.items, item); break
            end
        end
    end

    local rows = {}
    for _, g in ipairs(groups) do
        if #g.items > 0 then
            table.insert(rows, SectionDivider(g.label .. "  " .. #g.items .. " 地区", g.color))
            for _, item in ipairs(g.items) do
                local pct = math.min(1.0, item.cp / 100)
                table.insert(rows, UI.Panel {
                    width = "100%",
                    paddingHorizontal = S.card_padding, paddingVertical = 7,
                    backgroundColor = C.bg_surface,
                    borderRadius = S.radius_card, borderWidth = 1, borderColor = C.border_soft,
                    flexDirection = "column", gap = 4,
                    children = {
                        UI.Panel {
                            width = "100%", flexDirection = "row",
                            justifyContent = "space-between", alignItems = "center",
                            children = {
                                UI.Label { text=GetRegionLabel(item.id),
                                    fontSize=F.body_minor, fontColor=C.text_primary },
                                UI.Label {
                                    text=tostring(item.cp),
                                    fontSize=F.body_minor, fontColor=g.color, fontWeight="bold" },
                            },
                        },
                        UI.ProgressBar {
                            value=pct, height=5, trackColor=C.bg_inset,
                            fillColor=g.color, borderRadius=2,
                        },
                    },
                })
            end
        end
    end

    return SubPage("地区文化渗透  " .. #items .. " 地区", C.accent_green, rows)
end

-- ============================================================================
-- 子页：文化创作
-- ============================================================================
local function ActionCard(title, typeLabel, accentCol, desc, contentWidget)
    local ac = accentCol or C.accent_gold
    return UI.Panel {
        width = "100%", padding = S.card_padding,
        backgroundColor = C.bg_surface,
        borderRadius = S.radius_card, borderWidth = 1, borderColor = C.border_soft,
        flexDirection = "column", gap = 4,
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Panel {
                        paddingHorizontal=7, paddingVertical=2,
                        backgroundColor={ ac[1],ac[2],ac[3],40 },
                        borderRadius=3, borderWidth=1,
                        borderColor={ ac[1],ac[2],ac[3],120 },
                        children = {
                            UI.Label { text=typeLabel, fontSize=F.label,
                                fontColor={ ac[1],ac[2],ac[3],255 }, fontWeight="bold" },
                        },
                    },
                    UI.Label { text=title, fontSize=F.body_minor,
                        fontColor=C.text_primary, fontWeight="bold", flexGrow=1 },
                },
            },
            -- 说明
            UI.Label { text=desc, fontSize=F.label, fontColor=C.text_secondary },
            -- 操作区
            contentWidget or UI.Panel{},
        },
    }
end

local function _BuildCreatePage(state)
    local alreadyDone = state.culture_action_this_turn
    local rows = {}

    if alreadyDone then
        table.insert(rows, UI.Panel {
            width="100%", padding=S.card_padding,
            backgroundColor=C.warning_bg, borderRadius=S.radius_card,
            borderWidth=1, borderColor=C.accent_amber,
            children = {
                UI.Label { text="本季已执行过文化行动，下季可继续",
                    fontSize=F.body_minor, fontColor=C.accent_amber },
            },
        })
    end

    -- 剧团
    local canTroupe, troupeReason = Culture.CanCreateTroupe(state)
    local troupeCount = Culture.CountWorks(state, "theater_troupe")
    local troupeMax   = BC.troupe_global_max or 8
    table.insert(rows, ActionCard(
        string.format("歌舞剧团  %d / %d", troupeCount, troupeMax),
        "剧", C.accent_blue,
        string.format("驻扎地区每季 +5/3/1 渗透值（叠加递减）  成本 %d 克朗 + %d AP",
            BC.troupe_cost or 200, BC.troupe_create_ap or 1),
        UI.Panel {
            flexDirection="column", gap=6,
            children = {
                UI.Panel { flexDirection="row", flexWrap="wrap", gap=6, children = {
                    Btn("驻扎首都", C.accent_blue, function()
                        local ok, msg = Culture.CreateTroupe(state, "capital_city")
                        if onStateChanged_ then onStateChanged_(ok and msg or "创建失败："..(msg or "")) end
                    end, not canTroupe or alreadyDone),
                    Btn("驻扎工业区", C.accent_blue, function()
                        local ok, msg = Culture.CreateTroupe(state, "industrial_town")
                        if onStateChanged_ then onStateChanged_(ok and msg or "创建失败："..(msg or "")) end
                    end, not canTroupe or alreadyDone),
                }},
                not canTroupe and ErrHint(CleanReason(troupeReason)) or UI.Panel{},
            },
        }
    ))

    -- 电影
    local filmCount  = Culture.CountWorks(state, "film")
    local filmMax    = BC.film_max or 3
    local doneThemes = {}
    for _, w in ipairs(state.culture and state.culture.works or {}) do
        if w.type == "film" then doneThemes[w.theme] = true end
    end
    if filmCount < filmMax then
        local filmBtns = {}
        local filmErrs = {}
        for themeKey, themeLabel in pairs(FILM_THEMES) do
            if not doneThemes[themeKey] then
                local canFilm, filmReason = Culture.CanCreateFilm(state, themeKey)
                local tk = themeKey
                table.insert(filmBtns, Btn(themeLabel.."题材", C.accent_green, function()
                    local ok, msg = Culture.CreateFilm(state, tk)
                    if onStateChanged_ then onStateChanged_(ok and msg or "拍摄失败："..(msg or "")) end
                end, not canFilm or alreadyDone))
                if not canFilm and filmReason then
                    table.insert(filmErrs, ErrHint(CleanReason(filmReason)))
                end
            end
        end
        local filmWidget = nil
        if #filmBtns > 0 then
            local children = { UI.Panel { flexDirection="row", flexWrap="wrap", gap=6, children=filmBtns } }
            for _, e in ipairs(filmErrs) do table.insert(children, e) end
            filmWidget = UI.Panel { flexDirection="column", gap=4, children=children }
        end
        table.insert(rows, ActionCard(
            string.format("电影制作  %d / %d", filmCount, filmMax),
            "影", C.accent_green,
            string.format("制作周期 %d 季，支持多种发行方式  成本 %d 克朗  需电影工业科技",
                BC.film_prod_turns or 2, BC.film_cost or 400),
            filmWidget
        ))
    end

    -- 民族史诗
    local epicCount = Culture.CountWorks(state, "national_epic")
    local epicMax   = BC.epic_max or 3
    local doneEpics = {}
    for _, w in ipairs(state.culture and state.culture.works or {}) do
        if w.type == "national_epic" then doneEpics[w.theme] = true end
    end
    if epicCount < epicMax then
        local epicBtns = {}
        local epicErrs = {}
        for themeKey, themeLabel in pairs(EPIC_THEMES) do
            if not doneEpics[themeKey] then
                local canEpic, epicReason = Culture.CanCreateEpic(state, themeKey)
                local tk = themeKey
                table.insert(epicBtns, Btn(themeLabel, C.accent_amber, function()
                    local ok, msg = Culture.CreateEpic(state, tk)
                    if onStateChanged_ then onStateChanged_(ok and msg or "出版失败："..(msg or "")) end
                end, not canEpic or alreadyDone))
                if not canEpic and epicReason then
                    table.insert(epicErrs, ErrHint(CleanReason(epicReason)))
                end
            end
        end
        local epicWidget = nil
        if #epicBtns > 0 then
            local children = { UI.Panel { flexDirection="row", flexWrap="wrap", gap=6, children=epicBtns } }
            for _, e in ipairs(epicErrs) do table.insert(children, e) end
            epicWidget = UI.Panel { flexDirection="column", gap=4, children=children }
        end
        table.insert(rows, ActionCard(
            string.format("民族史诗  %d / %d", epicCount, epicMax),
            "史", C.accent_amber,
            string.format("永久效果：己方 +%d 渗透值/季，+%d 影响力/季  成本 %d 克朗 + %d RP",
                BC.epic_own_cp or 2, BC.ci_epic_bonus or 2,
                BC.epic_cost or 300, BC.epic_rp_cost or 10),
            epicWidget
        ))
    end

    -- 体育赛事
    local cooldown     = (state.culture or {}).sports_cooldown or 0
    local canSports, sportsReason = Culture.CanHoldSportsEvent(state, "capital_city")
    local inviteCandidates = Culture.GetSportsInviteCandidates(state)
    local friendlyInvites = {}
    for _, cand in ipairs(inviteCandidates) do
        if (cand.attitude or 0) >= 10 then
            table.insert(friendlyInvites, cand.id)
        end
    end
    local sportsChildren = {
        Btn("在首都举办（不邀请）", C.accent_green, function()
            local ok, msg = Culture.HoldSportsEvent(state, "capital_city", {})
            if onStateChanged_ then onStateChanged_(ok and msg or "举办失败："..(msg or "")) end
        end, not canSports or alreadyDone),
    }
    if #friendlyInvites > 0 then
        table.insert(sportsChildren, Btn("邀请所有友好国家", C.accent_green, function()
            local ok, msg = Culture.HoldSportsEvent(state, "capital_city", friendlyInvites)
            if onStateChanged_ then onStateChanged_(ok and msg or "举办失败："..(msg or "")) end
        end, not canSports or alreadyDone))
    end
    for i = 1, math.min(6, #inviteCandidates) do
        local cand = inviteCandidates[i]
        local cid = cand.id
        table.insert(sportsChildren, Btn(
            string.format("邀请%s(%+d)", cand.label, cand.attitude or 0),
            (cand.attitude or 0) >= 10 and C.accent_green or C.accent_amber,
            function()
                local ok, msg = Culture.HoldSportsEvent(state, "capital_city", { cid })
                if onStateChanged_ then onStateChanged_(ok and msg or "举办失败："..(msg or "")) end
            end,
            not canSports or alreadyDone))
    end
    table.insert(rows, ActionCard(
        cooldown > 0 and string.format("体育赛事  冷却 %d 季", cooldown) or "体育赛事",
        "赛", C.accent_green,
        string.format("举办地 +%d 渗透值，邻近 +%d 渗透值  冷却 %d 季  成本 %d 克朗",
            BC.sports_host_cp or 20, BC.sports_neighbor_cp or 8,
            BC.sports_cooldown or 4, BC.sports_cost or 250),
        UI.Panel {
            flexDirection="column", gap=4,
            children = {
                UI.Panel { flexDirection="row", flexWrap="wrap", gap=6, children=sportsChildren },
                not canSports and ErrHint(CleanReason(sportsReason)) or UI.Panel{},
            },
        }
    ))

    -- 世界博览会
    local exDone = (state.culture or {}).exhibition_done or false
    local exProg = (state.culture or {}).exhibition_progress or 0
    if exDone then
        table.insert(rows, UI.Panel {
            width="100%", padding=S.card_padding,
            backgroundColor=C.bg_surface, borderRadius=S.radius_card,
            borderWidth=1, borderColor=C.border_gold,
            children = {
                UI.Label { text="世界博览会  本局已举办",
                    fontSize=F.body_minor, fontColor=C.accent_gold, fontWeight="bold" },
            },
        })
    else
        local canEx, exReason = Culture.CanStartExhibition(state)
        local exTitle = exProg > 0
            and string.format("世界博览会  筹备中 %d/%d 季", exProg, BC.exhibition_turns or 3)
            or  "世界博览会"
        table.insert(rows, ActionCard(
            exTitle, "博", C.accent_gold,
            string.format("全局渗透值 +%d~%d，每局仅一次  需满配顾问 + 文化霸权 + %d 部史诗  成本 %d 克朗 + %d AP",
                BC.exhibition_base_cp or 15, BC.exhibition_max_cp or 40,
                BC.exhibition_min_epics or 2, BC.exhibition_cost or 800, BC.exhibition_ap or 2),
            exProg == 0 and UI.Panel {
                flexDirection="column", gap=4,
                children = {
                    UI.Panel { flexDirection="row", flexWrap="wrap", gap=6, children = {
                        Btn("启动筹备", C.accent_gold, function()
                            local ok, msg = Culture.StartExhibition(state)
                            if onStateChanged_ then onStateChanged_(ok and msg or "启动失败："..(msg or "")) end
                        end, not canEx or alreadyDone),
                    }},
                    not canEx and ErrHint(CleanReason(exReason)) or UI.Panel{},
                },
            } or nil
        ))
    end

    return SubPage("文化创作", C.accent_gold, rows)
end

-- ============================================================================
-- 子页：海外文化使团
-- ============================================================================
local function _BuildMissionsPage(state)
    local cult     = state.culture or {}
    local missions = cult.missions or {}
    local maxCount = BC.mission_max_count or 2
    local ci       = cult.ci or 0
    local rows     = {}

    -- 概览格子行
    table.insert(rows, UI.Panel {
        width = "100%",
        backgroundColor = C.paper_dark,
        borderRadius = S.radius_card, borderWidth = 1, borderColor = C.border_card,
        padding = S.card_padding,
        flexDirection = "column", gap = 6,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 4,
                children = {
                    MetricCell("使团数量",
                        string.format("%d/%d", #missions, maxCount),
                        #missions >= maxCount and C.accent_amber or C.text_primary),
                    MetricCell("影响力储量", ci,
                        ci >= (BC.mission_ci_min or 60) and C.accent_green or C.accent_red),
                    MetricCell("每季渗透值",
                        string.format("+%d", (BC.mission_base_cp or 12) * math.max(1, #missions)),
                        C.accent_blue),
                },
            },
        },
    })

    -- 快速派遣
    if #missions < maxCount then
        local targets = {}
        if state.europe then
            for regionId, _ in pairs(state.europe) do
                if Culture.CanLaunchMission(state, regionId) then
                    table.insert(targets, { id=regionId, cp=Culture.GetRegionCP(state, regionId) })
                end
            end
        end
        table.sort(targets, function(a,b) return a.cp < b.cp end)

        if #targets > 0 then
            table.insert(rows, SectionDivider("派遣新使团", C.accent_blue))
            local btns = {}
            for i = 1, math.min(6, #targets) do
                local t = targets[i]; local tid = t.id
                table.insert(btns, Btn(GetRegionLabel(tid), C.accent_blue, function()
                    local ok, msg = Culture.LaunchMission(state, tid)
                    if onStateChanged_ then onStateChanged_(ok and msg or "发起失败："..(msg or "")) end
                end))
            end
            table.insert(rows, UI.Panel {
                width="100%", padding=S.card_padding,
                backgroundColor=C.bg_surface, borderRadius=S.radius_card,
                borderWidth=1, borderColor=C.border_soft,
                flexDirection="column", gap=6,
                children = {
                    UI.Label {
                        text=string.format("选择目标地区（消耗 %d 影响力 + 1 AP）",
                            BC.mission_ci_launch or 80),
                        fontSize=F.label, fontColor=C.text_secondary,
                    },
                    UI.Panel { width="100%", flexDirection="row", flexWrap="wrap", gap=6, children=btns },
                },
            })
        end
    end

    -- 进行中使团
    if #missions > 0 then
        table.insert(rows, SectionDivider("进行中  " .. #missions .. " 支", C.accent_blue))
        for _, mission in ipairs(missions) do
            local cp    = Culture.GetRegionCP(state, mission.target)
            local turns = mission.turns_elapsed or 0
            local maxT  = BC.mission_max_turns or 6
            local tid   = mission.target
            local pct   = maxT > 0 and math.min(1.0, turns / maxT) or 0
            local cpClr = CPColor(cp)

            local mItems = {
                -- 标题行
                UI.Panel {
                    width="100%", flexDirection="row",
                    justifyContent="space-between", alignItems="center",
                    marginBottom=4,
                    children = {
                        UI.Label { text=GetRegionLabel(mission.target),
                            fontSize=F.body_minor, fontColor=C.text_primary, fontWeight="bold" },
                        UI.Label { text=string.format("第 %d/%d 季", turns, maxT),
                            fontSize=F.label, fontColor=C.text_muted },
                    },
                },
                UI.ProgressBar {
                    value=pct, height=5, trackColor=C.bg_inset,
                    fillColor=C.accent_blue, borderRadius=2,
                },
                -- 数据格子
                UI.Panel {
                    width="100%", flexDirection="row", gap=4, marginTop=6,
                    children = {
                        MetricCell("当前渗透值", cp, cpClr),
                        MetricCell("渗透等级", Culture.GetCPLevelName(cp), cpClr),
                        MetricCell("每季+渗透", BC.mission_base_cp or 12, C.accent_blue),
                    },
                },
            }

            if mission.pending_event then
                local eventRows = {
                    UI.Label {
                        text = "! " .. (mission.pending_event.desc or ""),
                        fontSize = F.label, fontColor = C.accent_amber, marginBottom = 4,
                    },
                }
                for optIdx, opt in ipairs(mission.pending_event.options or {}) do
                    local idxCapture = optIdx
                    table.insert(eventRows, Btn(opt.text or ("选项" .. optIdx), C.accent_amber, function()
                        local ok, msg = Culture.ResolveMissionEvent(state, tid, idxCapture)
                        if onStateChanged_ then onStateChanged_(ok and msg or "处理失败："..(msg or "")) end
                    end))
                end
                table.insert(mItems, UI.Panel {
                    width = "100%",
                    padding = 6,
                    backgroundColor = C.warning_bg,
                    borderRadius = S.radius_card,
                    borderWidth = 1,
                    borderColor = C.accent_amber,
                    flexDirection = "row",
                    flexWrap = "wrap",
                    gap = 6,
                    children = eventRows,
                })
            end

            table.insert(mItems, Btn("撤回使团（1 AP）", C.accent_red, function()
                local ok, msg = Culture.WithdrawMission(state, tid)
                if onStateChanged_ then onStateChanged_(ok and msg or "撤回失败："..(msg or "")) end
            end))

            table.insert(rows, UI.Panel {
                width="100%", padding=S.card_padding,
                backgroundColor=C.bg_surface, borderRadius=S.radius_card,
                borderWidth=1, borderColor=C.border_soft,
                flexDirection="column", gap=4,
                children=mItems,
            })
        end
    else
        table.insert(rows, EmptyHint(
            string.format("暂无进行中的使团（需影响力 >= %d 且顾问达良好级）",
                math.max(BC.mission_ci_min or 60, BC.mission_ci_launch or 80))))
    end

    return SubPage(string.format("海外文化使团  %d/%d", #missions, maxCount),
        C.accent_blue, rows)
end

-- ============================================================================
-- 主入口
-- ============================================================================
function CulturePanel.Build(state, callbacks)
    stateRef_       = state
    onStateChanged_ = callbacks and callbacks.onStateChanged or nil

    if currentView_ == "victory"  then return _BuildVictoryPage(state)
    elseif currentView_ == "works"    then return _BuildWorksPage(state)
    elseif currentView_ == "cp"       then return _BuildCPPage(state)
    elseif currentView_ == "create"   then return _BuildCreatePage(state)
    elseif currentView_ == "missions" then return _BuildMissionsPage(state)
    else return _BuildRoot(state)
    end
end

return CulturePanel
