-- ============================================================================
-- 新手引导模块
-- 第一阶段：全屏故事幻灯片（沉浸式叙事）
-- 第二阶段：遮罩式操作引导（半透明覆盖主界面，高亮目标区域）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")

local Tutorial = {}

-- ============================================================================
-- 色彩常量
-- ============================================================================

local GOLD       = { 212, 175, 55, 255 }
local GOLD_DIM   = { 212, 175, 55, 80 }
local TEXT_LIGHT  = { 220, 215, 200, 255 }
local TEXT_DIM    = { 150, 145, 135, 255 }
local TEXT_XDIM   = { 120, 115, 105, 255 }
local CARD_BG     = { 28, 26, 22, 245 }
local CARD_BORDER = { 212, 175, 55, 60 }
local FADE_DURATION = 0.45

-- ============================================================================
-- 引导步骤
-- ============================================================================

local STEPS = {
    -- ── 故事幻灯片（全屏背景图 + 底部文字） ──
    {
        type  = "story",
        image = "image/tutorial/story_city.png",
        title = "1904年，萨拉热窝",
        text  = "奥匈帝国治下的波斯尼亚，一座新旧交替的城市。\n帝国的繁华与巴尔干的暗涌在这里交汇。",
    },
    {
        type  = "story",
        image = "image/tutorial/story_mine.png",
        title = "科瓦奇家族",
        text  = "凭借一座金矿，你的家族踏上了百年兴衰的征途。\n从矿区小镇开始，建立属于你的商业帝国。",
    },
    {
        type  = "story",
        image = "image/tutorial/story_era.png",
        title = "乱世将至",
        text  = "两次世界大战、经济危机、政治动荡…\n你能否在五十年的风雨中守住家业，走向辉煌？",
    },
    -- ── 遮罩式操作引导（半透明遮罩 + 高亮框 + 提示卡片） ──
    -- highlight.targetId: 通过 FindById 动态获取目标元素的绝对位置和尺寸
    -- highlight.pad: 高亮框向外扩展的像素（可选，默认 4）
    {
        type  = "guide",
        icon  = "💰",
        title = "现金与硬通货",
        text  = "顶栏中部记录家族的核心资源：现金用于雇人、投资和应急；黄金是更稳的储备。\n先盯住现金，别让季度结算把你拖进破产。",
        hint  = "↑ 看这里：现金、黄金、产能、声望都在顶栏资源组里",
        highlight = { targetId = "topInfoRow", pad = 2 },
        card = "middle",
    },
    {
        type  = "guide",
        icon  = "🎰",
        title = "广告幸运事件",
        text  = "现金旁的转盘按钮是激励广告入口。完整观看后会触发一次幸运事件，直接获得一笔克朗。\n每季度次数有限，连续观看奖励会衰减，适合在缺钱或开局加速时使用。",
        hint  = "↑ 点现金旁边的 🎰，观看广告后领取随机现金奖励",
        highlight = { targetId = "luckyAdBtn", pad = 6 },
        card = "middle",
    },
    {
        type  = "guide",
        icon  = "⚙️",
        title = "行动点 AP",
        text  = "第二行显示本季还剩多少 AP。大多数关键操作都会消耗 AP。\n右侧的「+」按钮可以花现金购买临时 AP，但每季度也有次数限制。",
        hint  = "↑ AP 数字、圆点和 + 按钮决定你这一季还能做多少事",
        highlight = { targetId = "apRow", pad = 2 },
        card = "middle",
    },
    {
        type  = "guide",
        icon  = "📜",
        title = "先处理当前事件",
        text  = "首页最上方是待处理事件。主线事件会影响矿权、战争与政治环境。\n看到「处理」按钮时，建议先读完事件再安排经营动作。",
        hint  = "↓ 事件卡片通常在首页第一屏顶部",
        highlight = { targetId = "eventSection", pad = 4 },
        card = "lower",
    },
    {
        type  = "guide",
        icon  = "⛏️",
        title = "矿山是开局核心",
        text  = "焦点卡展示第一座矿山的产量、工人、安全和维护费用。\n前期优先让矿山稳定赚钱，再考虑扩张或冒险。",
        hint  = "↓ 这里是首页的矿山焦点卡",
        highlight = { targetId = "focusCard", pad = 4 },
        card = "upper",
    },
    {
        type  = "guide",
        icon  = "🧭",
        title = "快速操作入口",
        text  = "情报、科技、外交、资产交易都在首页快速操作里。\n这些按钮会打开具体弹窗，是你每季度最常用的经营入口。",
        hint  = "↓ 点这里进入本季的关键经营动作",
        highlight = { targetId = "quickActions", pad = 4 },
        card = "upper",
    },
    {
        type  = "guide",
        icon  = "🌍",
        title = "底部标签页",
        text  = "底部导航会进入更细的系统：家族安排成员，产业升级矿山，市场买卖黄金和股票，武装保卫矿区，世界页处理大国关系。",
        hint  = "↓ 产业、市场、武装、世界都在底部标签栏",
        highlight = { targetId = "bottomNav", pad = 2 },
        card = "middle",
    },
}

-- ============================================================================
-- 模块状态
-- ============================================================================

---@type table|nil UI 根节点
local uiRoot_ = nil
---@type table|nil 当前步骤的覆盖面板
local stepPanel_ = nil
---@type table|nil 淡出中的旧故事面板
local fadingPanel_ = nil
---@type table|nil 淡入淡出状态
local fade_ = nil
---@type number
local currentStep_ = 0
---@type function|nil
local onComplete_ = nil

-- ============================================================================
-- 入口
-- ============================================================================

--- 设置 UI 根节点（引导面板挂为其子元素）
---@param root table
function Tutorial.SetRoot(root)
    uiRoot_ = root
end

--- 启动新手引导
---@param onComplete function 引导结束后的回调
function Tutorial.Start(onComplete)
    onComplete_ = onComplete
    currentStep_ = 0
    fade_ = nil
    fadingPanel_ = nil

    -- 预加载故事图片，避免切换时闪烁
    for _, step in ipairs(STEPS) do
        if step.image then
            cache:GetResource("Texture2D", step.image)
        end
    end

    Tutorial._ShowNext()
end

--- 每帧更新，用于故事页之间的淡入淡出
---@param dt number
function Tutorial.Update(dt)
    if not fade_ then return end

    fade_.elapsed = fade_.elapsed + math.max(dt or 0, 0)
    local t = math.min(fade_.elapsed / FADE_DURATION, 1)
    local eased = 1 - (1 - t) * (1 - t)

    if fade_.newPanel and fade_.newPanel.SetStyle then
        fade_.newPanel:SetStyle({ opacity = eased })
    end
    if fade_.oldPanel and fade_.oldPanel.SetStyle then
        fade_.oldPanel:SetStyle({ opacity = 1 - eased })
    end

    if t >= 1 then
        if fade_.oldPanel then
            fade_.oldPanel:Destroy()
        end
        fadingPanel_ = nil
        fade_ = nil
    end
end

-- ============================================================================
-- 步骤切换
-- ============================================================================

function Tutorial._ShowNext()
    if fade_ then return end

    currentStep_ = currentStep_ + 1

    if currentStep_ > #STEPS then
        Tutorial._Finish()
        return
    end

    local step = STEPS[currentStep_]
    local isLast = currentStep_ == #STEPS
    local indicator = currentStep_ .. "/" .. #STEPS

    -- 构建新面板
    local newPanel
    if step.type == "story" then
        newPanel = Tutorial._BuildStorySlide(step, indicator, isLast)
    else
        newPanel = Tutorial._BuildGuideSlide(step, indicator, isLast)
    end

    local oldPanel = stepPanel_

    if uiRoot_ then
        uiRoot_:AddChild(newPanel)
    end

    if oldPanel and step.type == "story" then
        fadingPanel_ = oldPanel
        stepPanel_ = newPanel
        newPanel:SetStyle({ opacity = 0 })
        fade_ = {
            oldPanel = oldPanel,
            newPanel = newPanel,
            elapsed = 0,
        }
        return
    end

    if oldPanel then
        oldPanel:Destroy()
    end
    stepPanel_ = newPanel
end

-- ============================================================================
-- 故事幻灯片（全屏背景图 + 底部半透明文字区）
-- ============================================================================

function Tutorial._BuildStorySlide(step, indicator, isLast)
    return UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        -- 不透明黑色底色：图片加载前也不会露出主界面
        backgroundColor = { 0, 0, 0, 255 },
        backgroundImage = step.image,
        backgroundFit = "cover",
        flexDirection = "column",
        justifyContent = "flex-end",
        children = {
            -- 底部文字区（半透明遮罩）
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 8,
                paddingHorizontal = 20,
                paddingBottom = 40,
                paddingTop = 80,
                children = {
                    -- 遮罩背景
                    UI.Panel {
                        position = "absolute",
                        left = 0, right = 0, top = 0, bottom = 0,
                        backgroundColor = { 0, 0, 0, 160 },
                    },
                    -- 标题
                    UI.Label {
                        text = step.title,
                        fontSize = 22,
                        fontWeight = "bold",
                        fontColor = GOLD,
                        textAlign = "center",
                        width = "100%",
                    },
                    -- 正文
                    UI.Label {
                        text = step.text,
                        fontSize = 14,
                        fontColor = TEXT_LIGHT,
                        textAlign = "center",
                        whiteSpace = "normal",
                        lineHeight = 1.6,
                        width = "100%",
                    },
                    -- 按钮行
                    Tutorial._BuildButtons(indicator, isLast),
                },
            },
        },
    }
end

-- ============================================================================
-- 遮罩式操作引导（半透明覆盖 + 高亮框 + 浮动提示卡片）
-- ============================================================================

function Tutorial._BuildGuideSlide(step, indicator, isLast)
    local children = {}

    -- 高亮框：动态查询目标 UI 元素的绝对位置，自适应不同屏幕
    if step.highlight then
        local hl = step.highlight
        local frameProps = nil

        if hl.targetId and uiRoot_ then
            -- 通过 id 动态获取目标元素的实际位置和尺寸
            local target = uiRoot_:FindById(hl.targetId)
            if target then
                local layout = target:GetAbsoluteLayout()
                local pad = hl.pad or 4
                frameProps = {
                    position = "absolute",
                    left = layout.x - pad,
                    top = layout.y - pad,
                    width = layout.w + pad * 2,
                    height = layout.h + pad * 2,
                }
            end
        end

        -- 兼容：如果没有 targetId 或找不到元素，回退到手动坐标
        if not frameProps then
            frameProps = {
                position = "absolute",
                left = hl.left,
                right = hl.right,
                top = hl.top,
                bottom = hl.bottom,
                width = hl.width,
                height = hl.height or 56,
            }
        end

        frameProps.borderColor = { 212, 175, 55, 160 }
        frameProps.borderWidth = 2
        frameProps.backgroundColor = { 255, 255, 255, 12 }
        frameProps.borderRadius = 8
        frameProps.pointerEvents = "none"

        frameProps.children = {
            UI.Panel {
                position = "absolute",
                left = 3, right = 3, top = 3, bottom = 3,
                borderColor = { 255, 230, 170, 80 },
                borderWidth = 1,
                borderRadius = 6,
                pointerEvents = "none",
            },
        }
        table.insert(children, UI.Panel(frameProps))
    end

    -- 内容布局层（flexbox 居中卡片 + 底部按钮）
    local cardChildren = {
        -- 图标
        UI.Label {
            text = step.icon or "📖",
            fontSize = 42,
            textAlign = "center",
        },
        -- 标题
        UI.Label {
            text = step.title,
            fontSize = 18,
            fontWeight = "bold",
            fontColor = GOLD,
            textAlign = "center",
        },
        -- 分隔线
        UI.Panel {
            width = 50, height = 2,
            backgroundColor = GOLD_DIM,
            borderRadius = 1,
        },
        -- 正文
        UI.Label {
            text = step.text,
            fontSize = 13,
            fontColor = { 200, 195, 180, 255 },
            textAlign = "center",
            whiteSpace = "normal",
            lineHeight = 1.6,
            width = "100%",
        },
    }

    -- 方向提示（如 "↑ 顶栏显示你的核心资源"）
    if step.hint then
        table.insert(cardChildren, UI.Panel { height = 4 })
        table.insert(cardChildren, UI.Label {
            text = step.hint,
            fontSize = 12,
            fontColor = { 212, 175, 55, 150 },
            textAlign = "center",
        })
    end

    -- 提示卡片
    local card = UI.Panel {
        backgroundColor = CARD_BG,
        borderRadius = 14,
        borderColor = CARD_BORDER,
        borderWidth = 1,
        paddingVertical = 24,
        paddingHorizontal = 20,
        flexDirection = "column",
        alignItems = "center",
        gap = 8,
        width = "100%",
        children = cardChildren,
    }

    local topSpacer = 1
    local bottomSpacer = 1
    if step.card == "upper" then
        topSpacer = 0.25
        bottomSpacer = 1.75
    elseif step.card == "lower" then
        topSpacer = 1.75
        bottomSpacer = 0.25
    end

    -- 布局容器
    local layout = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        flexDirection = "column",
        paddingHorizontal = 24,
        children = {
            -- 上部弹性空间
            UI.Panel { flexGrow = topSpacer },
            -- 卡片
            card,
            -- 下部弹性空间
            UI.Panel { flexGrow = bottomSpacer },
            -- 按钮行
            Tutorial._BuildButtons(indicator, isLast),
            -- 底部留白（给 Tab 栏留空间）
            UI.Panel { height = 70 },
        },
    }
    table.insert(children, layout)

    return UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        -- 半透明遮罩：主界面可透视
        backgroundColor = { 0, 0, 0, 170 },
        children = children,
    }
end

-- ============================================================================
-- 底部按钮行
-- ============================================================================

function Tutorial._BuildButtons(indicator, isLast)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingTop = 12,
        children = {
            -- 跳过按钮
            UI.Button {
                text = "跳过引导",
                fontSize = 13,
                fontColor = TEXT_DIM,
                backgroundColor = { 0, 0, 0, 0 },
                paddingHorizontal = 8,
                paddingVertical = 6,
                onClick = function()
                    Tutorial._Finish()
                end,
            },
            -- 步骤指示器
            UI.Label {
                text = indicator,
                fontSize = 12,
                fontColor = TEXT_XDIM,
            },
            -- 继续 / 开始游戏
            UI.Button {
                text = isLast and "开始游戏" or "继续",
                fontSize = 14,
                fontWeight = "bold",
                fontColor = { 18, 16, 14, 255 },
                backgroundColor = GOLD,
                borderRadius = 6,
                paddingHorizontal = 20,
                paddingVertical = 8,
                onClick = function()
                    Tutorial._ShowNext()
                end,
            },
        },
    }
end

-- ============================================================================
-- 完成
-- ============================================================================

function Tutorial._Finish()
    fade_ = nil
    if fadingPanel_ then
        fadingPanel_:Destroy()
        fadingPanel_ = nil
    end
    if stepPanel_ then
        stepPanel_:Destroy()
        stepPanel_ = nil
    end
    local complete = onComplete_
    onComplete_ = nil
    if complete then
        complete()
    end
end

return Tutorial
