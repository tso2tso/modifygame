-- ============================================================================
-- 音频管理器：集中管理 UI 音效、游戏音效、背景音乐
-- 支持分类音量控制、BGM 切换、设置持久化
-- ============================================================================

local Config = require("config")

local AudioManager = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

---@type Node|nil 音频挂载节点
local audioNode_ = nil
---@type SoundSource|nil 当前 BGM 播放源
local bgmSource_ = nil
---@type string|nil 当前正在播放的 BGM 名称
local currentBGM_ = nil

--- 音量设置（0.0 ~ 1.0）
local volumes_ = {
    music  = 0.5,
    effect = 0.7,
    ui     = 0.7,
}

--- 音效文件路径映射
local SOUND_PATHS = {
    -- UI 音效
    ui_button_click = "Sounds/UI/ui_button_click.ogg",
    ui_tab_switch   = "Sounds/UI/ui_tab_switch.ogg",
    ui_modal_open   = "Sounds/UI/ui_modal_open.ogg",
    ui_modal_close  = "Sounds/UI/ui_modal_close.ogg",
    ui_toast_info   = "Sounds/UI/ui_toast_info.ogg",
    ui_toast_warning= "Sounds/UI/ui_toast_warning.ogg",
    ui_toast_error  = "Sounds/UI/ui_toast_error.ogg",

    -- 游戏音效
    turn_end        = "Sounds/Effects/turn_end.ogg",
    event_trigger   = "Sounds/Effects/event_trigger.ogg",
    event_choose    = "Sounds/Effects/event_choose.ogg",
    coin_income     = "Sounds/Effects/coin_income.ogg",
    coin_expense    = "Sounds/Effects/coin_expense.ogg",
    mine_upgrade    = "Sounds/Effects/mine_upgrade.ogg",
    tech_complete   = "Sounds/Effects/tech_complete.ogg",
    combat_victory  = "Sounds/Effects/combat_victory.ogg",
    combat_defeat   = "Sounds/Effects/combat_defeat.ogg",
    danger_warning  = "Sounds/Effects/danger_warning.ogg",
    game_victory    = "Sounds/Effects/game_victory.ogg",
    game_defeat     = "Sounds/Effects/game_defeat.ogg",
}

--- BGM 路径映射
local BGM_PATHS = {
    peace = "Sounds/Music/bgm_peace.ogg",
    war   = "Sounds/Music/bgm_war.ogg",
}

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化音频管理器（在 scene 创建后调用）
---@param scene Scene
function AudioManager.Init(scene)
    audioNode_ = scene:CreateChild("AudioManager")

    -- 设置引擎音量分类
    audio:SetMasterGain("Music",  volumes_.music)
    audio:SetMasterGain("Effect", volumes_.effect)
    audio:SetMasterGain("Ui",     volumes_.ui)

    print("[AudioManager] 初始化完成")
end

-- ============================================================================
-- 音效播放
-- ============================================================================

--- 播放一次性音效（自动回收）
---@param name string 音效名称（SOUND_PATHS 中的 key）
---@param soundType string 音效分类 "Effect"|"Ui"
local function playOneShot(name, soundType)
    if not audioNode_ then return end
    local path = SOUND_PATHS[name]
    if not path then
        print("[AudioManager] 未知音效: " .. tostring(name))
        return
    end

    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("[AudioManager] 加载失败: " .. path)
        return
    end

    local source = audioNode_:CreateComponent("SoundSource")
    source:SetSoundType(soundType)
    source:SetAutoRemoveMode(REMOVE_COMPONENT)
    source:Play(sound)
end

--- 播放 UI 音效
---@param name string 音效名称（如 "ui_button_click"）
function AudioManager.PlayUI(name)
    playOneShot(name, "Ui")
end

--- 播放游戏音效
---@param name string 音效名称（如 "turn_end", "event_trigger"）
function AudioManager.PlayEffect(name)
    playOneShot(name, "Effect")
end

-- ============================================================================
-- BGM 控制
-- ============================================================================

--- 播放背景音乐（循环）
---@param name string BGM 名称 "peace"|"war"
function AudioManager.PlayBGM(name)
    if currentBGM_ == name then return end  -- 避免重复切换

    local path = BGM_PATHS[name]
    if not path then
        print("[AudioManager] 未知 BGM: " .. tostring(name))
        return
    end

    -- 停止当前 BGM
    AudioManager.StopBGM()

    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("[AudioManager] BGM 加载失败: " .. path)
        return
    end
    sound:SetLooped(true)

    if not audioNode_ then return end
    bgmSource_ = audioNode_:CreateComponent("SoundSource")
    bgmSource_:SetSoundType("Music")
    bgmSource_:Play(sound)
    currentBGM_ = name

    print("[AudioManager] BGM 切换: " .. name)
end

--- 停止背景音乐
function AudioManager.StopBGM()
    if bgmSource_ then
        bgmSource_:Stop()
        audioNode_:RemoveComponent(bgmSource_)
        bgmSource_ = nil
    end
    currentBGM_ = nil
end

--- 根据游戏状态自动选择 BGM
---@param state table 游戏状态
function AudioManager.UpdateBGM(state)
    if not state or not state.year then return end
    local era = Config.GetEraByYear(state.year)
    local targetBGM = era.war_stripe and "war" or "peace"
    AudioManager.PlayBGM(targetBGM)
end

-- ============================================================================
-- 音量控制
-- ============================================================================

--- 设置某分类音量
---@param category string "music"|"effect"|"ui"
---@param value number 0.0 ~ 1.0
function AudioManager.SetVolume(category, value)
    value = math.max(0, math.min(1, value))
    volumes_[category] = value

    local engineType = ({
        music  = "Music",
        effect = "Effect",
        ui     = "Ui",
    })[category]

    if engineType then
        audio:SetMasterGain(engineType, value)
    end
end

--- 获取某分类音量
---@param category string "music"|"effect"|"ui"
---@return number
function AudioManager.GetVolume(category)
    return volumes_[category] or 0.5
end

--- 获取全部音量设置（用于存档）
---@return table { music, effect, ui }
function AudioManager.GetSettings()
    return {
        music  = volumes_.music,
        effect = volumes_.effect,
        ui     = volumes_.ui,
    }
end

--- 加载音量设置（从存档恢复）
---@param settings table { music, effect, ui }
function AudioManager.LoadSettings(settings)
    if not settings then return end
    if settings.music  then AudioManager.SetVolume("music",  settings.music)  end
    if settings.effect then AudioManager.SetVolume("effect", settings.effect) end
    if settings.ui     then AudioManager.SetVolume("ui",     settings.ui)     end
end

return AudioManager
