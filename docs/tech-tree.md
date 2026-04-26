# 科技树系统方案文档

> **百年萨拉热窝：黄金家族** — 科技研发子系统  
> 最后更新：2026-04-26

---

## 1. 系统概述

科技树是游戏的核心长线成长系统。玩家在 110 年（1904–2014）的游戏周期中，通过投入现金和行动点 (AP) 研发科技，获得采矿、经济、军事、文化四个维度的永久增益，支撑经济胜利或军事胜利路线。

**设计理念**：

- **单队列**：同一时间只能研发一项科技，强制玩家做取舍
- **线性前置**：每条科技线从左到右依次解锁，不存在跨线依赖
- **即时扣费 + 周期产出**：启动时一次性扣除现金和 AP，之后自动推进，完成后立即生效

---

## 2. 科技线总览

共 **30 项科技**，分 4 条独立科技线，每条线内部链式前置：

| 科技线 | ID 前缀 | 数量 | 核心收益 | 代表性效果 |
|--------|---------|------|----------|-----------|
| A · 采矿 | `a1`–`a8` | 8 | 矿山产出 & 工人效率 | 基础产出 +N, 产出倍率 ×1.2 |
| B · 经济 | `b1`–`b8` | 8 | 税率 & 被动收入 & AP | 税率 -N%, 贸易收入 +N |
| C · 军事 | `c1`–`c7` | 7 | 装备 & 战力 & 补给 | 装备等级 +N, 战力 +N% |
| D · 文化 | `d1`–`d7` | 7 | 影响力 & 士气 & 研发速度 | 每季影响力 +N, AP +1 |

### 2.1 A 线 · 采矿（8 项）

```
a1_hand_drill → a2_steam_drill → a3_electric_mine → a4_ventilation
→ a5_conveyor → a6_hydraulic → a7_auto_drill → a8_deep_mining
```

| ID | 名称 | 图标 | 费用 | 周期 | 效果 |
|----|------|------|------|------|------|
| a1 | 手工钻孔 | ⛏️ | 200 | 3季 | 矿山基础产出 +1 |
| a2 | 蒸汽钻机 | ⚙️ | 400 | 4季 | 矿山基础产出 +2 |
| a3 | 电气化矿井 | 💡 | 600 | 5季 | 矿区安全 +1, 事故 -15% |
| a4 | 通风系统 | 🌬️ | 500 | 4季 | 工人效率 +10% |
| a5 | 传送带运输 | 🏗️ | 800 | 6季 | 矿山基础产出 +3 |
| a6 | 液压采掘 | 🔧 | 1200 | 7季 | 矿山产出 ×1.20 |
| a7 | 自动化钻探 | 🤖 | 1800 | 8季 | 矿山产出 ×1.25, 工人效率 +15% |
| a8 | 深层采矿 | ⬇️ | 2500 | 10季 | 矿山基础产出 +5, 产出 ×1.15 |

### 2.2 B 线 · 经济（8 项）

```
b1_bookkeeping → b2_accounting → b3_telegraph → b4_trade_route
→ b5_finance_net → b6_stock_exchange → b7_global_trade → b8_digital_finance
```

| ID | 名称 | 图标 | 费用 | 周期 | 效果 |
|----|------|------|------|------|------|
| b1 | 复式记账 | 📖 | 250 | 3季 | 税率 -1% |
| b2 | 现代会计学 | 📒 | 400 | 4季 | 税率 -2% |
| b3 | 电报网络 | 📡 | 600 | 5季 | AP 上限 +1 |
| b4 | 贸易路线 | 🛤️ | 700 | 5季 | 每季被动贸易收入 +60 |
| b5 | 金融网络 | 💹 | 1000 | 6季 | 军事补给成本 -20%, 被动收入 +80 |
| b6 | 证券交易所 | 📈 | 1200 | 7季 | 所有股票期望收益率 +2% |
| b7 | 全球贸易 | 🌍 | 1600 | 8季 | 贸易收入 +120, 黄金售价 +5% |
| b8 | 数字金融 | 💻 | 2200 | 9季 | AP 上限 +1, 税率 -3% |

### 2.3 C 线 · 军事（7 项）

```
c1_rifled_arms → c2_logistics → c3_fortification → c4_motorized
→ c5_recon → c6_modern_arms → c7_elite_force
```

| ID | 名称 | 图标 | 费用 | 周期 | 效果 |
|----|------|------|------|------|------|
| c1 | 线膛步枪 | 🔫 | 300 | 3季 | 装备等级 +1 |
| c2 | 补给管理 | 📦 | 500 | 4季 | 护卫补给消耗 -1 |
| c3 | 防御工事 | 🏰 | 700 | 5季 | 护卫战斗力 +15% |
| c4 | 机械化部队 | 🚛 | 900 | 6季 | 装备等级 +1, 补给消耗 -1 |
| c5 | 侦察网络 | 🔭 | 1100 | 7季 | 每季影响力 +1, 士气 +3 |
| c6 | 现代武装 | 🎯 | 1500 | 8季 | 战斗力 +25%, 装备等级 +1 |
| c7 | 精锐部队 | ⚔️ | 2000 | 9季 | 战斗力 +20%, 雇佣成本 -15% |

### 2.4 D 线 · 文化（7 项）

```
d1_propaganda → d2_education → d3_newspaper → d4_radio
→ d5_university → d6_television → d7_internet
```

| ID | 名称 | 图标 | 费用 | 周期 | 效果 |
|----|------|------|------|------|------|
| d1 | 印刷宣传 | 🗞️ | 300 | 3季 | 每季影响力 +2 |
| d2 | 基础教育 | 📚 | 450 | 4季 | 工人效率 +8%, 士气 +3 |
| d3 | 报业帝国 | 📰 | 600 | 5季 | 每季影响力 +2, 士气 +2 |
| d4 | 广播电台 | 📻 | 800 | 6季 | 每季影响力 +3 |
| d5 | 大学 | 🎓 | 1000 | 6季 | 研发速度 +15%, AP +1 |
| d6 | 电视网络 | 📺 | 1400 | 7季 | 每季影响力 +4, 士气 +5 |
| d7 | 互联网 | 🌐 | 2000 | 9季 | AP +1, 研发速度 +20%, 影响力 +3 |

---

## 3. 效果系统 (Effects)

每项科技携带一个 `effects` 数组，完成时逐项应用。共 **18 种效果类型 (kind)**：

### 3.1 效果类型一览

| kind | 分类 | 累加方式 | 说明 |
|------|------|----------|------|
| `mine_output_base` | 采矿 | 加法 | 每座矿山 `output_bonus += value` |
| `mine_output_mult` | 采矿 | 加法→乘法 | 全局 `mine_output_mult_bonus += value`，结算时 `×(1+bonus)` |
| `security_bonus` | 采矿 | 加法 | 矿区安全等级 +value（上限 5） |
| `accident_reduction` | 采矿 | 加法 | 事故概率修正 `accident_rate_mod += value`（负数 = 降低） |
| `worker_efficiency` | 采矿 | 加法 | 工人效率 `worker_efficiency_bonus += value` |
| `tax_reduction` | 经济 | 加法 | 通过 `AddModifier` 永久降低税率 |
| `ap_bonus` | 经济/文化 | 加法 | 重算 `CalcMaxAP`，同时当前 AP +value |
| `trade_income` | 经济 | 加法 | `trade_passive_income += value`（每季结算时加入收入） |
| `gold_price_bonus` | 经济 | 加法 | `gold_price_bonus += value`（影响黄金售价） |
| `finance_network` | 经济 | 一次性 | 设置 `finance_supply_discount = 0.20` + `finance_passive_income = 80` |
| `stock_boost_all` | 经济 | 加法 | 所有股票 `mu += value`（提高期望收益率） |
| `equipment_up` | 军事 | 加法 | `military.equipment += value`（上限 5） |
| `supply_reduction` | 军事 | 加法 | `military.wage -= 1`（下限 6） |
| `guard_power_bonus` | 军事 | 加法 | `guard_power_tech_bonus += value`（乘法战力加成） |
| `hire_cost_reduction` | 军事 | 加法 | `hire_cost_discount += value`（负数 = 折扣） |
| `influence_gain` | 文化 | 加法 | `passive_influence += value`（每季自动增长） |
| `morale_bonus` | 文化 | 即时 | `morale += value`（一次性提升） |
| `research_speed` | 文化 | 加法 | `research_speed_bonus += value`（缩短后续研发周期） |

### 3.2 效果应用时机

```
Tech.Complete(state, techId)
  └─ 遍历 tech.effects[]
       └─ applyEffect(state, eff, techId)  -- 立即写入 state
```

所有效果在科技完成的**那一刻**立即生效，不存在"下回合生效"的延迟。

---

## 4. 研发机制

### 4.1 启动条件

启动研发 (`Tech.Start`) 需同时满足：

| 条件 | 检查 |
|------|------|
| 无其他研发中 | `state.tech.in_progress == nil` |
| 未已研发 | `state.tech.researched[id] ~= true` |
| 科技存在 | `TechData.GetById(id) ~= nil` |
| 前置已完成 | `requires == nil` 或 `researched[requires] == true` |
| 资金充足 | `state.cash >= tech.cost` |
| 行动点充足 | `current_ap >= Balance.TECH.base_research_ap`（= 2 AP） |

### 4.2 周期计算

基础周期取自 `tech.turns`，经过多层加速修正：

```lua
total = tech.turns                                    -- 基础值

-- 1) 科技顾问（家族成员岗位加成）
total = floor(total * (1 - bonus * 0.5))              -- 顾问 bonus=1 → ×0.5

-- 2) 影响力里程碑（总影响力 >= 200）
if hasInfluenceThreshold(200) then total = total - 1   -- 直接 -1 季

-- 3) 已研发的研发速度加成（research_speed 类效果累积）
total = floor(total * (1 - speedBonus))               -- 如 d5+d7 = 0.35 → ×0.65

-- 4) 科技奖励点数（事件/家族特质获得）
total = total - min(bonus_points, total - 1)           -- 最多减到 1 季

total = max(1, total)                                  -- 下限 1 季
```

### 4.3 每季推进

由 `TurnEngine` 在回合结算阶段调用 `Tech.Tick(state, report)`：

```
每季:
  progress += 1
  if 科技顾问 bonus > 0 且 random() < bonus:
      progress += 1          -- 额外加速（概率触发）
  if progress >= total:
      Tech.Complete()        -- 完成 & 应用效果
      in_progress = nil
      report.tech_completed = id
```

---

## 5. 数据结构

### 5.1 state.tech（运行时状态）

```lua
state.tech = {
    researched  = {},       -- { [tech_id] = true, ... }  已完成科技集合
    in_progress = nil,      -- { id = "a2_steam_drill", progress = 2, total = 4 }
    bonus_points = 0,       -- 事件/特质贡献的额外加速点数
}
```

### 5.2 TechData 单项定义（数据表）

```lua
{
    id          = "a1_hand_drill",      -- 唯一标识
    name        = "手工钻孔",           -- 显示名称
    icon        = "⛏️",                -- Emoji 图标
    desc        = "改进手工钻孔技术...", -- 描述文本
    cost        = 200,                  -- 研发现金成本（克朗）
    turns       = 3,                    -- 基础研发周期（季）
    requires    = nil,                  -- 前置科技 ID（nil = 线首）
    era_hint    = "1900s",              -- 时代标签（纯展示）
    effect_desc = "矿山基础产出 +1",    -- 效果文字（纯展示）
    effects     = {                     -- 效果数组（程序读取）
        { kind = "mine_output_base", value = 1 },
    },
}
```

---

## 6. UI 方案

### 6.1 科技树主界面

使用 `UI.SkillTree` 组件（文明 6 风格可缩放拖拽科技树）：

```
入口: 家族页 → 快速行动 "科技研发" → ActionModals.ShowTechnology()
```

**布局算法**：

1. 按前置依赖链计算每个节点的 **深度（列号）**
2. 同深度节点垂直排列，全局居中对齐
3. 节点间距：列间 220px, 行间 120px
4. 节点尺寸：80×80，圆角方形

**节点颜色编码**：

| 状态 | 颜色 | RGB |
|------|------|-----|
| 已研发 | 绿色 | (75, 175, 95) |
| 可研发 | 金色 | (235, 190, 55) |
| 未解锁 | 暗灰 | (70, 68, 80) |

**交互**：

- 拖拽平移、双指缩放（0.35x – 2.0x）
- 点击节点 → 弹出科技详情弹窗

### 6.2 科技详情弹窗

点击科技树节点后弹出 `UI.Modal`（size = "sm"），包含：

| 区域 | 内容 |
|------|------|
| 标题行 | 图标 + 科技名称 + 时代标签 |
| 状态标签 | ✓ 已研发 / ⏳ 研发中 X/Y 季 / 🔒 未解锁 / 🔓 可研发 |
| 描述 | 科技描述文本 |
| 效果列表 | 圆点 + 效果文字（通过 `EFFECT_LABELS` 映射 kind → 可读文本） |
| 费用信息 | 现金 / 研发周期 / AP 消耗（不足时标红） |
| 前置科技 | 前置名称 + ✓/✗ 标记 |
| 研发按钮 | 满足条件时可点击，否则灰色 + 提示文字 |

### 6.3 研发中进度条

科技树弹窗顶部显示当前研发进度：

```
⏳ 研发中：蒸汽钻机
[████████░░░░░░░░] 2 / 4 季
```

---

## 7. 文件清单

| 文件路径 | 职责 |
|----------|------|
| `scripts/data/tech_data.lua` | 科技数据定义（30 项科技、效果数组） |
| `scripts/data/balance.lua` → `TECH` | 研发平衡常数（AP 消耗 = 2） |
| `scripts/systems/tech.lua` | 科技系统逻辑（Start / Tick / Complete） |
| `scripts/game_state.lua` → `state.tech` | 运行时状态存储 |
| `scripts/systems/turn_engine.lua` | 每季调用 `Tech.Tick` 推进研发 |
| `scripts/ui/ui_action_modals.lua` | 科技树 UI（SkillTree + 详情弹窗） |

---

## 8. 关键设计决策

### 8.1 单队列 vs 多队列

**当前方案：单队列**。同一时间只能研发一项科技。

- 优点：决策更有权重感，防止后期科技爆炸
- 代价：玩家无法并行发展多条线

### 8.2 效果即时生效

科技完成后效果立即写入 `state`，不需要等到下一回合。AP 加成甚至会立即增加当前 AP。

### 8.3 加速叠加设计

多种加速手段可叠加，但都有保底下限（最少 1 季）：

- 科技顾问（家族成员岗位）→ 缩短周期 + 概率额外进度
- 影响力里程碑（>=200）→ -1 季
- 已研发 research_speed 效果 → 百分比缩短
- 事件奖励 bonus_points → 直接减季数

### 8.4 费用-收益曲线

科技费用从 200 到 2500 逐步递增，而效果也从 "+1 基础产出" 到 "+5 基础产出 + ×1.15 乘法加成" 逐步增强。晚期科技的性价比更高，但需要大量前期投入。

---

## 9. 扩展点

以下是可能的未来扩展方向：

| 方向 | 说明 |
|------|------|
| 跨线依赖 | 某些高级科技需要两条线的前置（如 "电气化矿井" + "电报网络" → "无线电通信"） |
| 时代门控 | 限制科技只能在对应时代研发（era_hint 当前仅为展示标签） |
| 科技树重置 | 付费重置已研发科技，换路线发展 |
| 分支选择 | 同深度的互斥科技二选一 |
| 科技事件 | 特定科技完成后触发剧情事件 |
