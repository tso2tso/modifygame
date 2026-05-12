# 贸易系统 & 军事互动 — 详细实现计划 v3

> 更新日期：2026-05-08
> v3 变更：整合全部已确认设计决策 + 称号奖励系统 + 国家HP血条系统 + 208回合节奏校准 + 分层征服设计

---

## 〇、已确认设计决策清单

| # | 决策项 | 确认结果 |
|---|--------|---------|
| 1 | 称号名称 | **幕后执政** |
| 2 | 区域控制阈值 | 每区 ≥**70**（降低门槛，因为可征服国家较多，需留足外交时间） |
| 3 | 和平时是否有贸易订单 | **有**，低级民用订单 |
| 4 | 占领系统设计 | **HP血条系统**：军事差距越大，占领越快（取代固定3次突袭前置） |
| 5 | 远征每回合上限 | **2次** |
| 6 | 称号立绘 | 暂不需要（`shadow_ruler` 无 portraitImage） |

---

## 一、称号奖励系统（全面增强）

### 1.0 设计理念

**每个称号都应有gameplay意义**，而不仅仅是成就展示。奖励分两类：
- **永久数值加成**：通过 modifier 系统实现（解锁后永久生效）
- **功能解锁**：特定功能的门控（如"幕后执政"解锁跨国行动）

### 1.1 称号奖励总表（19个称号）

#### 军事类（4个）

| 称号 | 当前条件 | v3 调整后条件 | 预计解锁回合 | 奖励 |
|------|---------|--------------|-------------|------|
| **初战告捷** | 赢1场战斗 | 不变 | 5-15 | `combat_power_bonus` +5% |
| **战争狂人** | 40次攻击+30武装 | **30次攻击+25武装** | 80-120 | `expedition_power_bonus` +10%，远征上限 +1次/回合 |
| **常胜将军** | 35胜+战意70 | **25胜+战意60** | 60-100 | `combat_power_bonus` +10%，小队经验获取 +50% |
| **铁壁防线** | 60武装+T6装备 | **45武装+T5装备** | 100-160 | `defense_bonus` +15%，占领据点维护费 -30% |

#### 掠夺类（3个）

| 称号 | 当前条件 | v3 调整后条件 | 预计解锁回合 | 奖励 |
|------|---------|--------------|-------------|------|
| **劫匪男爵** | 掠夺3次 | 不变 | 10-25 | 掠夺收入 +15%，解锁"黑市商人"（可向黑市出售装备） |
| **巴尔干之狼** | 掠夺25次+声誉-50 | **掠夺18次+声誉-40** | 60-100 | 突袭掠夺收入 +25%，突袭AP消耗 -1（2→1） |
| **臭名昭著** | 声誉-95+掠夺20次 | **声誉-80+掠夺15次** | 80-130 | 恐吓效果：突袭时敌方防御-10%，侵略衰减速度 +50% |

#### 经济类（4个）

| 称号 | 当前条件 | v3 调整后条件 | 预计解锁回合 | 奖励 |
|------|---------|--------------|-------------|------|
| **矿业新星** | 3座矿山 | 不变 | 15-30 | 矿产产出 +10%，铜矿售价 +5% |
| **金融巨鳄** | 50万现金+100万收入 | **30万现金+60万收入** | 120-180 | 所有收入 +5%，贷款利率 -1% |
| **债务帝王** | 3笔贷款+10万负债 | **3笔贷款+6万负债** | 40-80 | 贷款额度上限 +30%，解锁"信用体系"（高额低息贷款） |
| **通胀幸存者** | 通胀3.0+5万现金+100金 | **通胀2.5+3万现金+80金** | 80-140 | 通胀对收入的负面影响 -20%，黄金交易免税 |

#### 证券类（4个）

| 称号 | 当前条件 | v3 调整后条件 | 预计解锁回合 | 奖励 |
|------|---------|--------------|-------------|------|
| **初入股海** | 5笔交易 | 不变 | 8-20 | 交易手续费 -10% |
| **有形大手** | 操纵25次 | **操纵18次** | 50-90 | 操纵成功率 +8%，操纵成本 -15% |
| **操盘圣手** | 100笔交易 | **70笔交易** | 80-140 | 交易手续费 -25%，解锁"期货合约"（可预判下季走势） |
| **空头猎人** | 做空盈利5万 | **做空盈利3万** | 60-120 | 做空杠杆上限 +50%，做空保证金 -20% |

#### 综合类（4个）

| 称号 | 当前条件 | v3 调整后条件 | 预计解锁回合 | 奖励 |
|------|---------|--------------|-------------|------|
| **科技先驱** | 研究24项科技 | **研究18项科技** | 60-100 | 研究速度 +15%，科技分支解锁条件放宽 |
| **家族兴旺** | 6人在岗+影响力150 | **5人在岗+影响力100** | 80-130 | 家族成员技能效果 +20%，新成员初始适应期 -1 |
| **时代见证者** | 存活160回合 | **存活120回合** | 120 | 所有收入 +8%，事件选项额外奖励 +15% |
| **商业新秀** | — | 现金≥20000 + 矿山≥2 | 30-50 | `trade_price_bonus` +5%（贸易售价加成） |
| **幕后执政** ⭐ | 三区≥75+影响力80+武装20 | **三区≥70+影响力60+武装15** | **40-60** | **解锁军事远征**，外交影响力 +10%（注：跨国贸易改由科技树 b4a/b4b 解锁） |

### 1.2 奖励难度分布（208回合时间线）

```
回合数:  0    20    40    60    80   100   120   140   160   180   200   208
         ├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼────┤
入门称号: ┣━━━┫ 初战告捷(5-15), 初入股海(8-20), 劫匪男爵(10-25), 矿业新星(15-30)
                     │
         幕后执政: ──┣━━━━┫ (40-60) ←← 关键门控点
                          │
中级称号: ──────────────┣━━━━━━━━━━━━━━━━━┫ 债务帝王/常胜/有形大手/空头猎人等
                                              │
高级称号: ────────────────────────────────┣━━━━━━━━━━━━━━━━━┫ 铁壁/金融巨鳄/操盘等
                                                              │
终极称号: ──────────────────────────────────────────────────────────┫ 无(弹性)
```

**设计目标**：
- **前期（回合1-40）**：解锁4个入门称号，获得基础加成，熟悉各系统
- **中前期（回合40-60）**：解锁"幕后执政"，打开跨国玩法的大门
- **中期（回合60-120）**：根据玩法路线解锁对应中级称号，强化特长
- **后期（回合120-180）**：硬核玩家冲击高级称号，获得决定性优势
- **终盘（回合180-208）**：利用积累的加成冲刺胜利目标

### 1.3 "幕后执政"解锁节奏分析

**条件（v3调整后）**：三区控制度 ≥70 + 总影响力 ≥60 + 武装 ≥15

| 区域 | 初始值 | 目标值 | 需提升 | 每季提升速度（预估） | 预估所需回合 |
|------|--------|--------|--------|-------------------|-------------|
| 矿区 | 80 | 70 | 已满足 | — | 0（维持即可） |
| 工业区 | 20 | 70 | +50 | 战斗胜+3，每季1-2战 → +3~6/季 | 10-18回合 |
| 首都 | 5 | 70 | +65 | 战斗胜+3，但AI压制-3 → 净+1~3/季 | 22-40回合 |
| 影响力 | 0 | 60 | +60 | 科技/事件积累，~1.5/季 | 与控制度并行 |
| 武装 | ~5 | 15 | +10 | 招募+经济增长 | 与控制度并行 |

**结论**：首都控制度是瓶颈，预计 **35-55回合**解锁（约第9-14年），留下 **150-170回合** 用于跨国行动。

### 1.4 实现方案：称号奖励应用

#### 数据结构扩展（titles_data.lua）

```lua
-- 每个称号新增 rewards 字段
{
    id = "first_blood",
    name = "初战告捷",
    -- ... 现有字段 ...
    rewards = {
        modifiers = {
            { key = "combat_power_bonus", value = 0.05, label = "战斗力+5%" },
        },
    },
    check = function(state, stats) ... end,
},

{
    id = "shadow_ruler",
    name = "幕后执政",
    -- ... 现有字段 ...
    rewards = {
        unlock_features = { "expedition" },  -- 功能解锁（注：foreign_trade 已改由科技树 b4a/b4b 解锁）
        modifiers = {
            { key = "diplomacy_influence_bonus", value = 0.10, label = "外交影响力+10%" },
        },
    },
    check = function(state, stats) ... end,
},
```

#### 引擎改动（titles.lua）

```lua
function Titles.Check(state)
    -- 现有逻辑不变...
    for _, def in ipairs(TitlesData.TITLES) do
        if not state.titles_unlocked[def.id] then
            local ok, err = pcall(def.check, state, stats)
            if ok and err then
                state.titles_unlocked[def.id] = state.turn_count or 0
                table.insert(newlyUnlocked, { ... })

                -- 🆕 新增：应用称号奖励
                if def.rewards and def.rewards.modifiers then
                    for _, mod in ipairs(def.rewards.modifiers) do
                        GameState.AddModifier(state, mod.key, mod.value, 9999,
                            "称号：" .. def.name)
                    end
                end
            end
        end
    end
    return newlyUnlocked
end
```

**优势**：
- 利用已有 modifier 系统，零新架构
- 各系统通过 `GetModifierValue()` 自然读取加成，无需互相 require
- 奖励定义在数据文件中，方便调整

---

## 二、国家HP血条系统（占领机制重设计）

### 2.0 设计理念

**取代固定"赢3次突袭才能占领"的硬门槛**，改为连续HP削减系统：
- 每个国家有**稳定度HP**（基于 `stability` 字段）
- 突袭造成伤害，军事差距越大伤害越高
- HP归零 → 可占领
- HP每季自然恢复 → 需要持续施压

### 2.1 国家HP公式

```lua
-- 初始HP = stability × 10
-- 例：塞尔维亚 stability=70 → HP=700

country.max_hp = country.stability * 10    -- 最大HP
country.current_hp = country.max_hp         -- 当前HP
country.hp_regen = country.stability * 0.3  -- 每季自然恢复（无压力时）
```

**17国HP一览**（按tier分组）：

| 国家 | Tier | Stability | Max HP | 每季恢复 | 难度评估 |
|------|------|-----------|--------|---------|---------|
| 黑山 | minor | 65 | 650 | 19.5 | ⭐ 最易 |
| 希腊 | minor | 55 | 550 | 16.5 | ⭐ 易 |
| 罗马尼亚 | minor | 55 | 550 | 16.5 | ⭐ 易 |
| 保加利亚 | minor | 60 | 600 | 18.0 | ⭐⭐ 中等 |
| 芬兰 | minor | 60 | 600 | 18.0 | ⭐⭐ 中等 |
| 塞尔维亚 | minor | 70 | 700 | 21.0 | ⭐⭐ 中等 |
| 低地国家 | minor | 70 | 700 | 21.0 | ⭐⭐ 中等 |
| 丹麦 | minor | 75 | 750 | 22.5 | ⭐⭐⭐ 较难 |
| 意大利 | medium | 65 | 650 | 19.5 | ⭐⭐ 中等 |
| 西班牙 | neutral | 55 | 550 | 16.5 | ⭐⭐ 中等（远） |
| 奥斯曼 | major | 45 | 450 | 13.5 | ⭐⭐⭐ 较难（大国） |
| 奥匈帝国 | major | 55 | 550 | 16.5 | ⭐⭐⭐⭐ 难（宗主国） |
| 俄罗斯 | major | 60 | 600 | 18.0 | ⭐⭐⭐⭐ 难（大国） |
| 法兰西 | major | 75 | 750 | 22.5 | ⭐⭐⭐⭐⭐ 极难 |
| 德意志 | major | 80 | 800 | 24.0 | ⭐⭐⭐⭐⭐ 极难 |
| 英国 | major | 85 | 850 | 25.5 | ⭐⭐⭐⭐⭐ 极难 |
| 瑞士 | neutral | 95 | 950 | 28.5 | ⭐⭐⭐⭐⭐ 极难（中立堡垒） |
| 瑞典-挪威 | neutral | 85 | 850 | 25.5 | ⭐⭐⭐⭐⭐ 极难（中立） |

### 2.2 突袭伤害公式

```lua
--- 计算突袭对目标国家的HP伤害
function Expedition.CalcRaidDamage(attackerPower, defenderHP, defenderStability)
    local baseDamage = 50                                -- 基础伤害
    local powerRatio = attackerPower / (defenderStability * 5)  -- 军力对比系数
    local scaledDamage = baseDamage * powerRatio         -- 按军力差距缩放

    -- 伤害下限30、上限200（单次突袭不能秒杀）
    local finalDamage = math.max(30, math.min(200, scaledDamage))

    -- modifier 加成
    local bonus = GameState.GetModifierValue(state, "expedition_power_bonus")
    finalDamage = finalDamage * (1 + bonus)

    return math.floor(finalDamage)
end
```

**伤害示例**（假设玩家攻击力=300）：

| 目标国家 | Stability | 防御基数 | 军力比 | 单次伤害 | 需要几次清空HP |
|---------|-----------|---------|--------|---------|--------------|
| 黑山(65) | 65 | 325 | 0.92 | ~46 | ~15次 |
| 希腊(55) | 55 | 275 | 1.09 | ~55 | ~10次 |
| 塞尔维亚(70) | 70 | 350 | 0.86 | ~43 | ~17次 |
| 奥匈(55) | 55 | 275 | 1.09 | ~55 | ~10次（但大国有额外机制） |
| 德意志(80) | 80 | 400 | 0.75 | ~38 | ~22次 |

### 2.3 HP恢复机制

```lua
-- 每季结算时
function Expedition.TickCountryHP(state)
    for id, country in pairs(state.europe) do
        if country.current_hp < country.max_hp then
            -- 基础恢复（每季）
            local regen = country.hp_regen

            -- 如果本季被突袭过，恢复减半
            if country._raided_this_turn then
                regen = regen * 0.5
                country._raided_this_turn = false
            end

            -- 大国保护：被大国保护的小国恢复 +50%
            if country.sovereign ~= country.original then
                regen = regen * 1.5
            end

            country.current_hp = math.min(country.max_hp,
                country.current_hp + regen)
        end
    end
end
```

### 2.4 占领流程

```
突袭国家 → HP下降 → 继续突袭 → HP归零
                                    ↓
                            触发"占领窗口"（持续2回合）
                                    ↓
                    玩家在窗口期内发起"占领行动"（3AP, 500现金）
                                    ↓
                            占领成功 → 获得该国控制权
                                    ↓
                        每季获得占领收入 - 维护费用
                        该国成为前进基地（邻接扩展）
```

**占领窗口**：HP归零后不会立即被占领，而是出现2回合的占领窗口。窗口期内不占领→HP恢复到30%，需重新削减。

### 2.5 大国特殊机制

| 特殊机制 | 说明 |
|---------|------|
| **大国护盾** | major tier 的国家有30%伤害减免 |
| **联盟反击** | 攻击大国有概率触发盟友报复（aggression +2而非+1） |
| **HP双层** | 大国有"军事HP"和"政治HP"，两者都归零才能占领 |

```lua
-- 大国伤害减免
if country.tier == "major" then
    finalDamage = finalDamage * 0.7  -- 减免30%
end

-- 大国政治HP（额外层）
if country.tier == "major" then
    country.political_hp = country.stability * 5   -- 额外50% HP
    -- 政治HP需要通过贸易封锁、外交手段削减（非纯军事）
end
```

---

## 三、分层征服节奏设计

### 3.0 核心理念

**不同投入程度的玩家，体验不同的征服深度**：
- 🟢 **休闲路线**：专注经济/科技胜利，可能顺手占1-2个弱国
- 🟡 **普通路线**：目标征服2-3个周边小国，建立小型势力范围
- 🔴 **硬核路线**：全面征服所有可达国家，追求统治胜利

### 3.1 征服路线图（基于邻接关系）

**波斯尼亚的地理位置**：位于巴尔干半岛核心，隶属奥匈帝国。

**邻接推导**（波斯尼亚直接邻国）：
- 塞尔维亚（地图瓦片相邻）
- 黑山（地图瓦片相邻）
- 奥匈帝国（宗主国，直接相邻）

**征服链（逐层扩展）**：
```
                    🔴 法国(750) ← 🔴 低地(700)
                        ↑              ↑
          🔴 意大利(650) ← 🔴 瑞士(950,中立)
                ↑
         🔴 奥匈帝国(550,宗主)
            ↗        ↖
    ⭐ 波斯尼亚          🔴 德意志(800)
            ↘        ↙        ↖
     🟡 塞尔维亚(700)    🔴 俄罗斯(600)
         ↙      ↘             ↗
  🟢 黑山(650)   🟡 保加利亚(600)
                      ↘
                  🟡 希腊(550)  🟡 罗马尼亚(550)
                      ↓
                 🔴 奥斯曼(450)
```

### 3.2 三档征服目标

#### 🟢 休闲档（2个国家）

| 目标 | HP | 预估所需突袭次数 | 回合跨度 | 说明 |
|------|-----|----------------|---------|------|
| 黑山 | 650 | ~15次 | 8-10回合 | 最弱邻国，直接可达 |
| 希腊/罗马尼亚 | 550 | ~10次 | 6-8回合 | 通过塞尔维亚中转 |

**总耗时**：约20-25回合（含"幕后执政"后）
**在208回合游戏中的占比**：~12%
**目标玩家**：享受经营乐趣，征服只是锦上添花

#### 🟡 普通档（4-5个国家）

| 目标 | HP | 预估所需突袭次数 | 说明 |
|------|-----|----------------|------|
| 黑山 | 650 | ~15 | 直接邻国 |
| 塞尔维亚 | 700 | ~17 | 直接邻国 |
| 保加利亚 | 600 | ~13 | 经塞尔维亚 |
| 罗马尼亚 | 550 | ~10 | 经塞尔维亚 |
| 希腊（可选） | 550 | ~10 | 经保加利亚 |

**总耗时**：约60-80回合
**目标玩家**：征服巴尔干半岛小国，建立区域霸权

#### 🔴 硬核档（全部17国）

**路线规划**：
1. 先征服周边小国（黑山→塞尔维亚→保加利亚→罗马尼亚→希腊）~70回合
2. 挑战奥斯曼帝国（stability最低的大国）~20回合
3. 挑战奥匈帝国（宗主国，需双层HP）~30回合
4. 向西扩展（意大利→瑞士→法国→低地）~40回合
5. 北方/远征（德意志→丹麦→斯堪的纳维亚→芬兰→俄罗斯→英国）~50回合以上

**总耗时**：约150-170回合（紧凑操作下）
**可行性**：幕后执政在40-60回合解锁，留150+回合，理论可行但极其紧张
**目标玩家**：完美主义者，追求全征服成就

### 3.3 征服难度调节器

为确保三档体验都合理，引入**动态难度系数**：

```lua
-- 已占领国家数量影响后续征服难度
function Expedition.GetConquestDifficultyMod(state)
    local occupiedCount = #(state.expeditions.occupied_countries or {})

    if occupiedCount <= 2 then
        return 1.0   -- 前2个国家：正常难度
    elseif occupiedCount <= 5 then
        return 1.15  -- 3-5个：+15% 防御（列强开始警觉）
    elseif occupiedCount <= 10 then
        return 1.35  -- 6-10个：+35%（多国联防）
    else
        return 1.60  -- 11+：+60%（全面对抗）
    end
end
```

**同时**：已占领国家提供"前进基地"加成：
```lua
-- 如果目标国家邻接已占领国家，攻击力+20%
function Expedition.GetForwardBaseBonus(state, targetCountryId)
    for _, occ in ipairs(state.expeditions.occupied_countries or {}) do
        if EuropeData.AreAdjacent(state.europe, occ.country_id, targetCountryId) then
            return 0.20  -- +20% 攻击力
        end
    end
    return 0
end
```

### 3.4 胜利条件扩展

```lua
-- 新增"统治胜利"（征服路线的终极目标）
Balance.VICTORY.domination = {
    type = "domination",
    label = "巴尔干霸主",
    desc = "占领巴尔干半岛全部小国（黑山、塞尔维亚、保加利亚、罗马尼亚、希腊）",
    required_countries = { "montenegro", "serbia", "bulgaria", "romania", "greece" },
    min_total_control = 100,  -- 同时需要国内控制度
}

Balance.VICTORY.world_domination = {
    type = "world_domination",
    label = "全面统治",
    desc = "占领所有可达国家",
    required_countries = "all_reachable",  -- 动态计算
    min_total_control = 100,
}
```

---

## 四、前置系统："幕后执政"称号

### 4.1 称号设计（v3 最终版）

| 字段 | 值 |
|------|---|
| id | `shadow_ruler` |
| name | **幕后执政** |
| desc | 掌控全国三大区域，成为波黑真正的幕后掌权者。解锁军事远征。（注：跨国贸易改由科技树 b4a/b4b 解锁） |
| category | `comprehensive` |
| icon | 🏛️ |
| portraitImage | nil（暂不需要） |

### 4.2 解锁条件（v3 调整后）

```lua
check = function(state, stats)
    -- 条件1：三个区域控制度都 >= 70（降低自75）
    for _, r in ipairs(state.regions or {}) do
        if (r.control or 0) < 70 then return false end
    end
    -- 条件2：总影响力 >= 60（降低自80）
    local totalInfluence = 0
    for _, r in ipairs(state.regions or {}) do
        totalInfluence = totalInfluence + (r.influence or 0)
    end
    if totalInfluence < 60 then return false end
    -- 条件3：拥有至少 15 武装（降低自20）
    local mil = state.military or {}
    if (mil.guards or 0) < 15 then return false end
    return true
end
```

### 4.3 功能门控（双通道）

跨国贸易和军事远征现在使用**不同的解锁路径**：

#### 跨国贸易门控（科技树）

```lua
-- trade.lua
function Trade.CanDoForeignAction(state)
    return state.unlocked_features
        and state.unlocked_features["foreign_trade"] == true
end
```

贸易由科技树 b4a（巴尔干贸易路线）或 b4b（走私网络）解锁，研发完成后 `tech.lua` 的 `applyEffect()` 自动设置 `state.unlocked_features["foreign_trade"] = true`。

#### 军事远征门控（称号）

```lua
-- expedition.lua
function canDoExpedition(state)
    return state.titles_unlocked and state.titles_unlocked["shadow_ruler"] ~= nil
end
```

**门控对照表**：
| 功能 | 解锁方式 | 解锁条件 |
|------|---------|---------|
| 跨国贸易订单系统 | 科技树 b4a 或 b4b | 研发完成即解锁 |
| 武装突袭 | "幕后执政"称号 | 三区控制度≥70 + 影响力≥60 + 武装≥15 |
| 支援作战 | "幕后执政"称号 | 同上 |
| 占领国家 | "幕后执政"称号 | 同上 + 目标HP归零 |
| 现有本地战斗 | **无门控** | 始终可用 |
| 贸易被动收入 | 科技树 b4a/b4b | 研发完成后每季获得被动贸易收入 |

---

## 五、系统耦合与解耦分析

### 5.1 架构原则

```
              ┌────────────────────┐
              │    TurnEngine      │  ← 唯一编排者
              └─┬──┬──┬──┬──┬──┬──┘
                │  │  │  │  │  │
                ▼  ▼  ▼  ▼  ▼  ▼
    Economy  Stock Tech Equip Trade* Expedition*
                              (新)     (新)
```

### 5.2 耦合矩阵

#### Trade 需要耦合的系统

| 现有系统 | 耦合方式 | 说明 |
|---------|---------|------|
| GrandPowers | 只读 | 订单生成依赖列强战争状态 |
| Equipment | 只读 | 检查库存满足订单 |
| Economy | 写入 | 交付收入计入经济结算 |
| TurnEngine | 被调用 | Phase 1.9 |
| TitlesData | 只读 | `shadow_ruler` 门控 |

#### Expedition 需要耦合的系统

| 现有系统 | 耦合方式 | 说明 |
|---------|---------|------|
| Combat | 调用 | 复用战斗核心公式（新增 ResolveExpedition） |
| Military | 读写 | 小队锁定/解锁 |
| GrandPowers | 只读 | 列强战线、国家HP |
| EuropeData | 只读 | 邻接关系、国家数据 |
| TurnEngine | 被调用 | Phase 6.6 |
| Events | 触发 | 制裁事件 |
| TitlesData | 只读 | `shadow_ruler` 门控 |

#### 不直接耦合的系统

Stock、Family、Loan、Plunder、Tech、MapTilesData — 通过 modifier 系统间接交互。

### 5.3 Modifier 键清单

| modifier key | 来源 | 影响 |
|-------------|------|------|
| `combat_power_bonus` | 称号（初战告捷/常胜将军） | 战斗力 +% |
| `expedition_power_bonus` | 称号（战争狂人）/ 科技 | 远征战力 +% |
| `defense_bonus` | 称号（铁壁防线） | 防御/据点维护 |
| `trade_price_bonus` | 科技 | 订单报酬 +% |
| `trade_route_safety` | 科技/事件 | 路线安全度 +% |
| `order_frequency_bonus` | 称号/声誉 | 订单刷新频率 +% |
| `diplomacy_influence_bonus` | 称号（幕后执政） | 外交影响力 +% |
| `plunder_income_bonus` | 称号（劫匪男爵/巴尔干之狼） | 掠夺收入 +% |
| `research_speed_bonus` | 称号（科技先驱） | 研究速度 +% |
| `trade_fee_discount` | 称号（初入股海/操盘圣手） | 交易手续费 -% |

---

## 六、贸易/订单系统（详细设计）

### 6.1 模块接口（`scripts/systems/trade.lua`）

```lua
local Trade = {}

function Trade.GenerateOrders(state) end       -- 每季生成新订单
function Trade.AcceptOrder(state, orderId) end  -- 接受订单（1AP）
function Trade.AllocateEquipment(state, orderId, allocations) end  -- 分配装备
function Trade.ShipOrder(state, orderId, routeId, escortSquadId) end  -- 发货（1AP）
function Trade.SettleDeliveries(state) end      -- 每季结算交付
function Trade.CalcRouteSafety(state, route) end  -- 路线安全度

return Trade
```

### 6.2 订单数据结构

```lua
state.trade = {
    order_pool = {},         -- 当季可接订单
    active_orders = {},      -- 进行中订单
    routes = {},             -- 路线状态
    completed_count = 0,
    failed_count = 0,
    total_revenue = 0,
    reputation = 0,          -- 贸易信誉 -10~+10
    last_quarter_revenue = 0,
}

-- 单个订单
order = {
    id = "order_q12_001",
    buyer_power_id = "austria_hungary",
    buyer_label = "奥匈帝国",
    items_required = { { equip_id = "musket_t2", qty = 8 } },
    items_allocated = {},
    payment_base = 1800,
    deadline_turns = 3,
    risk_level = "medium",     -- low/medium/high
    diplo_effect = { buyer_collab = +5, buyer_enemy_collab = -3 },
    status = "available",      -- available→accepted→shipping→delivered/failed/expired
    route_id = nil,
    escort_squad_id = nil,
}
```

### 6.3 订单生成逻辑

- 战争时：在战列强数量决定订单数（上限5），高价军火订单
- 和平时：固定1个低价民用订单（T1-T2装备）
- modifier `order_frequency_bonus` 影响生成数量

### 6.4 路线系统

预定义路线（基于邻接关系），每条路线有：
- `base_safety`：基础安全度
- `base_cost`：运输成本
- `unlocked`：是否初始开通

安全度受以下因素影响：
- 途经国家战争状态 -20%
- 途经国家被占领 -15%
- 玩家外交分数 +0~20%
- modifier 加成
- 护送小队 +15~25%

### 6.5 收入过渡

```lua
-- economy.lua 中
if canDoForeignAction(state) then
    report.trade_income = state.trade.last_quarter_revenue or 0
else
    report.trade_income = state.trade_passive_income or 0
end
```

### 6.6 TurnEngine 集成

Phase 1.9（Equipment.TickProduction 之后，Events.CheckEvents 之前）：
```lua
if canDoForeignAction(state) then
    local tradeReport = Trade.SettleDeliveries(state)
    Trade.GenerateOrders(state)
    state.trade.last_quarter_revenue = tradeReport.total_revenue
end
```

---

## 七、军事远征系统（详细设计）

### 7.1 模块接口（`scripts/systems/expedition.lua`）

```lua
local Expedition = {}

function Expedition.Execute(state, action) end        -- 发起远征（玩家操作）
function Expedition.SettleTurn(state) end              -- 每季结算
function Expedition.GetValidTargets(state) end         -- 获取可攻击目标
function Expedition.EstimateWinRate(state, squadId, targetId) end  -- 预估胜率
function Expedition.CalcRaidDamage(attackerPower, defenderStab) end  -- 计算伤害
function Expedition.TickCountryHP(state) end           -- HP恢复
function Expedition.GetConquestDifficultyMod(state) end  -- 动态难度

return Expedition
```

### 7.2 三种行动类型

#### A. 武装突袭（raid）
- **AP**：2 | **现金**：200
- **目标**：与波斯尼亚/已占领国家邻接的国家
- **效果**：对目标国家HP造成伤害（公式见 §2.2），掠夺资源
- **失败**：小队成员-1~-3，士气-10

#### B. 支援作战（support）
- **AP**：2 | **现金**：300
- **前置**：目标列强处于战争状态
- **效果**：佣兵报酬500~2000，外交分数变化，小队经验

#### C. 占领行动（occupy）
- **AP**：3 | **现金**：500
- **前置**：目标国家HP已归零（在占领窗口期内）
- **效果**：控制该国，每季获得收入，可作为前进基地
- **维护**：每季120现金（大国200），不付自动丢失

### 7.3 远征数据结构

```lua
state.expeditions = {
    active = {},               -- 当前进行中远征
    occupied_countries = {},   -- 已占领国家（替代 occupied_tiles）
    aggression_counter = 0,
    history = {
        raids_won = 0,
        raids_lost = 0,
        support_missions = 0,
        total_loot = 0,
        countries_conquered = 0,
    },
}

-- 已占领国家
occupied_country = {
    country_id = "montenegro",
    income_per_turn = 200,
    maintenance = 120,
    since_turn = 65,
    garrison_squad_id = "squad_2",  -- 驻军小队（被锁定）
}
```

### 7.4 侵略制裁

```lua
-- 每次突袭 → aggression +1
-- 每次占领 → aggression +2
-- 每季自然衰减 -0.5

-- 阈值：
-- aggression >= 5 → 列强联合制裁（路线安全-30%、订单-50%、4回合）
-- aggression >= 8 → 列强军事干预（被额外攻击，占领国家稳定度受损）
```

### 7.5 TurnEngine 集成

Phase 6.6（Combat.ResolveAIActions 之后，GrandPowers.Tick 之前）：
```lua
if canDoForeignAction(state) then
    Expedition.SettleTurn(state)
    Expedition.TickCountryHP(state)  -- HP恢复
    -- 占领收入/维护
    for _, occ in ipairs(state.expeditions.occupied_countries) do
        state.cash = state.cash + occ.income_per_turn - occ.maintenance
    end
    -- 侵略衰减
    state.expeditions.aggression_counter =
        math.max(0, state.expeditions.aggression_counter - 0.5)
end
```

---

## 八、国家HP状态存储

### 8.1 数据存储位置

国家HP直接存储在 `state.europe` 中（EuropeData 初始化时不含这些字段，在"幕后执政"解锁时初始化）：

```lua
-- 称号解锁时初始化所有国家HP
function Expedition.InitCountryHP(state)
    for id, country in pairs(state.europe) do
        country.max_hp = country.stability * 10
        country.current_hp = country.max_hp
        country.hp_regen = country.stability * 0.3
        if country.tier == "major" then
            country.political_hp = country.stability * 5
        end
    end
end
```

---

## 九、完整文件变更清单

| 文件 | 操作 | 变更内容 |
|------|------|---------|
| `scripts/systems/trade.lua` | **新建** | 贸易核心模块（~300行） |
| `scripts/systems/expedition.lua` | **新建** | 远征核心模块（~350行，含HP系统） |
| `scripts/data/trade_routes_data.lua` | **新建** | 预定义贸易路线（~80行） |
| `scripts/data/titles_data.lua` | **修改** | 新增 `shadow_ruler` + 所有称号的 `rewards` 字段（~150行） |
| `scripts/data/balance.lua` | **修改** | 新增 TRADE、EXPEDITION、VICTORY 常量（~80行） |
| `scripts/data/events_data.lua` | **修改** | 新增制裁事件、称号解锁事件（~30行） |
| `scripts/game_state.lua` | **修改** | 新增 trade、expeditions 初始状态（~30行） |
| `scripts/systems/titles.lua` | **修改** | 新增奖励应用逻辑（~20行） |
| `scripts/systems/economy.lua` | **修改** | 贸易收入条件分支（~10行） |
| `scripts/systems/turn_engine.lua` | **修改** | 新增 Phase 1.9、Phase 6.6（~30行） |
| `scripts/systems/combat.lua` | **修改** | 新增 ResolveExpedition()（~20行） |
| `scripts/utils/save_load.lua` | **修改** | trade/expeditions 序列化（~40行） |
| `scripts/ui/ui_trade.lua` | **新建** | 贸易面板 UI（~400行） |
| `scripts/ui/ui_expedition.lua` | **新建** | 远征面板 UI（~400行） |
| `scripts/ui/ui_map_widget.lua` | **修改** | 贸易/军事图层 + 国家HP显示（~250行） |
| `scripts/ui/ui_world.lua` | **修改** | 节点抽屉增加贸易/军事入口（~50行） |

**新增文件：4 个 | 修改文件：12 个 | 预估总新增代码：~2300行**

---

## 十、分步实施计划

### 阶段 1：称号系统增强
1. `titles_data.lua` — 新增 `shadow_ruler` + 所有称号的 `rewards` 字段
2. `titles.lua` — 奖励应用逻辑
3. 调整所有称号难度条件（适配208回合节奏）
4. 验证：称号解锁 → modifier 生效

### 阶段 2：国家HP系统
5. `expedition.lua` — HP初始化、伤害计算、HP恢复
6. `game_state.lua` — europe 字段扩展（HP数据）
7. `save_load.lua` — HP数据序列化
8. 验证：HP变化正确，恢复机制运作

### 阶段 3：贸易核心
9. `trade_routes_data.lua` — 路线数据
10. `trade.lua` — 完整贸易流程
11. `balance.lua` — TRADE 常量
12. `economy.lua` — 收入分支
13. `turn_engine.lua` — Phase 1.9
14. 验证：订单生成→接单→发货→交付→收入

### 阶段 4：远征核心
15. `expedition.lua` — 三种行动 + 占领流程
16. `combat.lua` — ResolveExpedition()
17. `balance.lua` — EXPEDITION 常量
18. `events_data.lua` — 制裁事件
19. `turn_engine.lua` — Phase 6.6
20. 验证：突袭→HP下降→占领→收入/维护

### 阶段 5：UI
21. `ui_trade.lua` — 订单列表、路线管理
22. `ui_expedition.lua` — 行动选择、国家HP显示、胜率预估
23. `ui_map_widget.lua` — 图层实现（路线、HP血条）
24. `ui_world.lua` — 入口集成

### 阶段 6：联动与平衡
25. 护送机制联动测试
26. 征服难度曲线调试
27. 胜利条件扩展
28. 数值调平（多局测试）

---

## 十一、验证检查清单

### 称号系统
- [ ] 所有19个称号有 `rewards` 字段
- [ ] 称号解锁 → modifier 自动生效
- [ ] "幕后执政"在40-60回合可解锁
- [ ] 入门称号在5-30回合可解锁

### HP血条系统
- [ ] 所有17国HP正确初始化
- [ ] 突袭造成HP伤害，公式正确
- [ ] HP每季恢复，被突袭时恢复减半
- [ ] 大国有30%伤害减免
- [ ] HP归零后2回合占领窗口
- [ ] 窗口过期→HP恢复到30%

### 征服节奏
- [ ] 休闲玩家可在150回合内征服2个弱国
- [ ] 普通玩家可在150回合内征服4-5个小国
- [ ] 硬核玩家理论上可征服全部（极度紧张）
- [ ] 动态难度系数随占领数增长

### 贸易系统
- [ ] 门控：未解锁称号→操作被拒
- [ ] 订单流程完整可走通
- [ ] 收入平滑过渡（旧→新）

### 远征系统
- [ ] 三种行动类型均可执行
- [ ] 侵略制裁正确触发
- [ ] 占领据点收入/维护平衡
