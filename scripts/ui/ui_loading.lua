-- ============================================================================
-- 加载界面模块
-- 3 张家族立绘轮播（淡入淡出） + 底部进度条 + 游戏标题
-- 用于新游戏/读档时的 UI 重建等待期
--
-- 设计：动画状态存储在模块变量中，UI 面板可按需重建（TransferTo）。
-- 这样在 UIManager.Create() 替换 UI 根节点后，可以在新根上
-- 重新创建加载面板并延续动画进度。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("config")

local Loading = {}

-- ============================================================================
-- 常量
-- ============================================================================

local GOLD       = { 212, 175, 55, 255 }
local GOLD_DIM   = { 212, 175, 55, 120 }
local TEXT_LIGHT  = { 220, 215, 200, 255 }
local TEXT_DIM    = { 150, 145, 135, 255 }
local BG_COLOR    = { 20, 18, 14, 255 }
local BAR_BG      = { 50, 44, 34, 255 }
local BAR_FILL    = { 201, 168, 76, 255 }

--- 立绘列表（3 张核心家族成员）
local PORTRAITS = {
    { path = "image/portraits/nikola.png", name = "尼古拉 · 科瓦奇", title = "家主" },
    { path = "image/portraits/marko.png",  name = "马尔科 · 科瓦奇", title = "长子" },
    { path = "image/portraits/lina.png",   name = "莉娜 · 科瓦奇",   title = "侄女" },
}

local CROSSFADE_DURATION = 0.6
local DISPLAY_DURATION   = 1.8
local MIN_SHOW_DURATION  = 2.0   -- 最短展示时间（秒）

-- 提示语池
local HINTS = {
    "工业帝国的基业，从一座金矿开始……",
    "乱世之中，家族的智慧是最好的铠甲",
    "黄金可以买来一切，除了时间",
    "巴尔干的暴风雨即将来临……",
    "每一个决策，都将改变家族的命运",
}

-- ============================================================================
-- 模块状态（动画相关，独立于 UI 面板生命周期）
-- ============================================================================

---@type boolean
local showing_ = false
---@type boolean
local workDone_ = false
---@type number
local elapsed_ = 0
---@type number 当前轮播索引（1-based）
local currentIndex_ = 1
---@type number
local slideElapsed_ = 0
---@type string display / fadeout / fadein
local fadeState_ = "display"
---@type number
local fadeElapsed_ = 0
---@type string 当前提示语
local hintText_ = ""
---@type function|nil 关闭后的回调
local onClosed_ = nil

-- UI Widget 引用（随面板重建而更新）
---@type table|nil
local panel_ = nil
---@type table|nil
local portraitWidget_ = nil
---@type table|nil
local nameLabel_ = nil
---@type table|nil
local progressFill_ = nil

-- ============================================================================
-- 内部：创建 UI 面板（根据当前动画状态）
-- ============================================================================

local function _CreatePanel()
    local p = PORTRAITS[currentIndex_]

    -- 当前立绘透明度
    local portraitOpacity = 1
    if fadeState_ == "fadeout" then
        local t = math.min(fadeElapsed_ / CROSSFADE_DURATION, 1)
        portraitOpacity = 1 - t
    elseif fadeState_ == "fadein" then
        local t = math.min(fadeElapsed_ / CROSSFADE_DURATION, 1)
        portraitOpacity = t
    end

    -- 进度条百分比
    local progress = 0
    if workDone_ then
        progress = math.min(1, elapsed_ / MIN_SHOW_DURATION)
    else
        progress = math.min(0.85, elapsed_ / (MIN_SHOW_DURATION * 1.2))
    end
    local pctStr = math.floor(progress * 100) .. "%"

    -- 立绘展示：用超高内面板 + cover 使图片从顶部铺满，展示上半身
    portraitWidget_ = UI.Panel {
        width = "100%",
        height = 1200,
        backgroundImage = p.path,
        backgroundFit = "cover",
        opacity = portraitOpacity,
    }

    nameLabel_ = UI.Label {
        text = p.name .. "  ·  " .. p.title,
        fontSize = 14,
        fontColor = TEXT_DIM,
        textAlign = "center",
    }

    progressFill_ = UI.Panel {
        width = pctStr,
        height = "100%",
        backgroundColor = BAR_FILL,
        borderRadius = 3,
    }

    local newPanel = UI.Panel {
        id = "loadingScreen",
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        backgroundColor = BG_COLOR,
        flexDirection = "column",
        alignItems = "center",
        children = {
            -- 顶部标题区
            UI.Panel {
                width = "100%",
                paddingTop = 60,
                paddingBottom = 16,
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = "⚜️",
                        fontSize = 28,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = Config.TITLE,
                        fontSize = 20,
                        fontWeight = "bold",
                        fontColor = GOLD,
                        textAlign = "center",
                    },
                },
            },

            -- 立绘区域
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                overflow = "hidden",
                paddingHorizontal = 24,
                children = {
                    UI.Panel {
                        width = "100%",
                        height = "100%",
                        borderRadius = 10,
                        overflow = "hidden",
                        borderWidth = 1,
                        borderColor = GOLD_DIM,
                        children = {
                            portraitWidget_,
                        },
                    },
                },
            },

            -- 底部信息区
            UI.Panel {
                width = "100%",
                paddingHorizontal = 32,
                paddingTop = 16,
                paddingBottom = 48,
                flexDirection = "column",
                alignItems = "center",
                gap = 12,
                children = {
                    nameLabel_,
                    -- 进度条
                    UI.Panel {
                        width = "80%",
                        height = 6,
                        backgroundColor = BAR_BG,
                        borderRadius = 3,
                        overflow = "hidden",
                        children = {
                            progressFill_,
                        },
                    },
                    -- 提示语
                    UI.Label {
                        text = hintText_,
                        fontSize = 12,
                        fontColor = TEXT_DIM,
                        textAlign = "center",
                        whiteSpace = "normal",
                    },
                },
            },
        },
    }

    return newPanel
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 展示加载界面并挂载到指定的 UI 根节点
---@param parentRoot table 当前 UI 根节点
---@param onClosed function|nil 加载界面关闭后的回调（可选）
function Loading.Show(parentRoot, onClosed)
    if showing_ then return end
    showing_ = true
    workDone_ = false
    elapsed_ = 0
    currentIndex_ = 1
    slideElapsed_ = 0
    fadeState_ = "display"
    fadeElapsed_ = 0
    onClosed_ = onClosed
    hintText_ = HINTS[math.random(1, #HINTS)]

    -- 预加载立绘纹理
    for _, p in ipairs(PORTRAITS) do
        cache:GetResource("Texture2D", p.path)
    end

    -- 创建面板并挂载
    panel_ = _CreatePanel()
    if parentRoot then
        parentRoot:AddChild(panel_)
    end
end

--- 将加载面板转移到新的 UI 根节点
--- 用于 UIManager.Create() 替换根节点后，在新根上重建加载面板
---@param newRoot table 新的 UI 根节点
function Loading.TransferTo(newRoot)
    if not showing_ then return end

    -- 销毁旧面板（可能已脱离渲染树）
    if panel_ then
        panel_:Destroy()
        panel_ = nil
        portraitWidget_ = nil
        nameLabel_ = nil
        progressFill_ = nil
    end

    -- 基于当前动画状态重建面板
    panel_ = _CreatePanel()
    if newRoot then
        newRoot:AddChild(panel_)
    end
end

--- 标记实际工作已完成
---@param onClosed function|nil Loading 关闭后的回调（可选，会覆盖 Show 传入的 onClosed）
function Loading.MarkDone(onClosed)
    workDone_ = true
    if onClosed then
        onClosed_ = onClosed
    end
end

--- 立即关闭加载界面
function Loading.Close()
    if not showing_ then return end
    showing_ = false
    if panel_ then
        panel_:Destroy()
        panel_ = nil
    end
    portraitWidget_ = nil
    nameLabel_ = nil
    progressFill_ = nil
    local cb = onClosed_
    onClosed_ = nil
    if cb then cb() end
end

--- 是否正在展示
---@return boolean
function Loading.IsShowing()
    return showing_
end

--- 每帧更新（立绘轮播 + 进度条 + 自动关闭检测）
---@param dt number
function Loading.Update(dt)
    if not showing_ then return end

    elapsed_ = elapsed_ + dt

    -- ── 进度条 ──
    local progress
    if workDone_ then
        -- 工作完成后快速填满
        local fillTime = math.max(0, elapsed_ - (MIN_SHOW_DURATION - 0.4))
        progress = 0.85 + 0.15 * math.min(1, fillTime / 0.4)
    else
        progress = math.min(0.85, elapsed_ / (MIN_SHOW_DURATION * 1.2))
    end
    if progressFill_ and progressFill_.SetStyle then
        progressFill_:SetStyle({ width = math.floor(progress * 100) .. "%" })
    end

    -- ── 立绘轮播 ──
    slideElapsed_ = slideElapsed_ + dt

    if fadeState_ == "display" then
        if slideElapsed_ >= DISPLAY_DURATION then
            fadeState_ = "fadeout"
            fadeElapsed_ = 0
        end
    elseif fadeState_ == "fadeout" then
        fadeElapsed_ = fadeElapsed_ + dt
        local t = math.min(fadeElapsed_ / CROSSFADE_DURATION, 1)
        if portraitWidget_ and portraitWidget_.SetStyle then
            portraitWidget_:SetStyle({ opacity = 1 - t })
        end
        if t >= 1 then
            -- 切换到下一张
            currentIndex_ = (currentIndex_ % #PORTRAITS) + 1
            local p = PORTRAITS[currentIndex_]
            if portraitWidget_ and portraitWidget_.SetStyle then
                portraitWidget_:SetStyle({
                    backgroundImage = p.path,
                    opacity = 0,
                })
            end
            if nameLabel_ then
                nameLabel_:SetText(p.name .. "  ·  " .. p.title)
            end
            fadeState_ = "fadein"
            fadeElapsed_ = 0
        end
    elseif fadeState_ == "fadein" then
        fadeElapsed_ = fadeElapsed_ + dt
        local t = math.min(fadeElapsed_ / CROSSFADE_DURATION, 1)
        if portraitWidget_ and portraitWidget_.SetStyle then
            portraitWidget_:SetStyle({ opacity = t })
        end
        if t >= 1 then
            fadeState_ = "display"
            slideElapsed_ = 0
        end
    end

    -- ── 自动关闭检测 ──
    if workDone_ and elapsed_ >= MIN_SHOW_DURATION then
        Loading.Close()
    end
end

return Loading
