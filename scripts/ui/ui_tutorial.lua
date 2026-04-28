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
    {
        type  = "guide",
        icon  = "💰",
        title = "资源管理",
        text  = "克朗是你的流动资金，黄金是硬通储备。\n每季度你有有限的行动点(AP)来执行各项操作。\n合理分配资源，是生存的第一课。",
        hint  = "↑ 顶栏显示你的核心资源与行动点",
        highlight = { area = "top", height = 56 },
    },
    {
        type  = "guide",
        icon  = "⛏️",
        title = "开局建议",
        text  = "前往「产业」页升级矿山，这是你最稳定的收入来源。\n关注「市场」页的黄金价格波动，低买高卖。\n留意随机事件，每个选择都会影响家族命运。",
    },
    {
        type  = "guide",
        icon  = "🌍",
        title = "外交与军事",
        text  = "你并非孤军奋战——本地望族、外国资本都在争夺控制权。\n在「世界」页管理外交关系，在「军事」页保卫家业。\n乱世之中，合纵连横方能立于不败。",
        hint  = "↓ 底部标签页切换不同模块",
        highlight = { area = "bottom", height = 56 },
    },
}

-- ============================================================================
-- 模块状态
-- ============================================================================

---@type table|nil UI 根节点
local uiRoot_ = nil
---@type table|nil 当前步骤的覆盖面板
local stepPanel_ = nil
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

    -- 预加载故事图片，避免切换时闪烁
    for _, step in ipairs(STEPS) do
        if step.image then
            cache:GetResource("Texture2D", step.image)
        end
    end

    Tutorial._ShowNext()
end

-- ============================================================================
-- 步骤切换（先挂新面板再销毁旧面板，防止闪烁）
-- ============================================================================

function Tutorial._ShowNext()
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

    -- 先挂新面板，再销毁旧面板 → 无缝切换
    if uiRoot_ then
        uiRoot_:AddChild(newPanel)
    end
    if stepPanel_ then
        stepPanel_:Destroy()
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

    -- 高亮框：在目标区域加亮色边框，透过遮罩凸显
    if step.highlight then
        local hl = step.highlight
        local frameProps = {
            position = "absolute",
            left = 0, right = 0,
            height = hl.height or 56,
            borderColor = { 212, 175, 55, 160 },
            borderWidth = 2,
            backgroundColor = { 255, 255, 255, 12 },
        }
        if hl.area == "top" then
            frameProps.top = 0
        elseif hl.area == "bottom" then
            frameProps.bottom = 0
        end
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

    -- 布局容器
    local layout = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        flexDirection = "column",
        paddingHorizontal = 24,
        children = {
            -- 上部弹性空间
            UI.Panel { flexGrow = 1 },
            -- 卡片
            card,
            -- 下部弹性空间
            UI.Panel { flexGrow = 1 },
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
    if stepPanel_ then
        stepPanel_:Destroy()
        stepPanel_ = nil
    end
    if onComplete_ then
        onComplete_()
    end
end

return Tutorial
