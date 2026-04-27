# 世界系统深度分析报告

> **分析范围**: ui_world.lua · ui_map_widget.lua · regions_data.lua · turn_engine.lua · combat.lua · game_state.lua · balance.lua  
> **生成日期**: 2026-04-27  
> **版本**: v1.0

---

## 目录

1. [总览](#1-总览)
2. [Report 标签页 — 状态引用错误](#2-report-标签页--状态引用错误)
3. [AI 行为系统 — 严重不足](#3-ai-行为系统--严重不足)
4. [AI 经济系统 — 无限增长](#4-ai-经济系统--无限增长)
5. [地图系统 — 大量未完成内容](#5-地图系统--大量未完成内容)
6. [外资系统 — 影响力不足](#6-外资系统--影响力不足)
7. [战斗系统 — 平衡性分析](#7-战斗系统--平衡性分析)
8. [区域系统 — 过于简单](#8-区域系统--过于简单)
9. [改进建议](#9-改进建议)

---

## 1. 总览

当前"世界"栏目存在以下核心问题：

| 严重度 | 问题 | 文件 |
|--------|------|------|
| 🔴 BUG | Report 标签页 4 处状态路径引用错误，会导致运行时 nil 错误 | ui_world.lua |
| 🔴 设计缺陷 | AI 态度只会下降，无正向触发器，必然走向敌对 | turn_engine.lua |
| 🟡 设计缺陷 | AI 现金复利增长无上限，后期数值爆炸 | turn_engine.lua |
| 🟡 未完成 | 8 个地图层级中 5 个标记为 locked，7 种节点类型仅用 3 种 | ui_map_widget.lua |
| 🟡 设计缺陷 | 外资系统对游戏的实际影响有限，缺少经济干预手段 | turn_engine.lua |
| 🟢 遗留 | ERA_MAP_THEMES 有 7 个时代条目，实际只有 5 个时代 | ui_map_widget.lua |
| 🟢 不足 | 无 AI-to-AI 交互，两个 AI 派系完全独立运作 | turn_engine.lua |

---

## 2. Report 标签页 — 状态引用错误

**文件**: `scripts/ui/ui_world.lua` → `_CreateSeasonSummary()`

Report 标签页的季度总结功能中存在 4 处无效的状态路径引用，会导致显示 nil 或运行时错误：

| # | 错误引用 | 正确路径 | 说明 |
|---|---------|---------|------|
| 1 | `state.resources.cash` | `state.cash` | cash 直接挂在 state 根级别 |
| 2 | `state.dynasty.prestige` | *(不存在)* | state 中没有 prestige 字段；家族数据在 `state.family` |
| 3 | `state.flags.total_influence` | `GameState.CalcTotalInfluence(state)` | 影响力是通过函数计算的，不是直接存储的字段 |
| 4 | `state.resources.guards` | `state.military.guards` | 守卫在 military 子表中 |

**影响**: 如果玩家实际进入 Report 标签页并触发季度总结渲染，会看到空白或 nil 值。

**修复难度**: 低（直接修正路径引用即可）

---

## 3. AI 行为系统 — 严重不足

**文件**: `scripts/systems/turn_engine.lua` → Phase 6 (AI Update)

### 3.1 态度系统：只降不升

AI 态度（attitude）有 4 个负向触发器，但 **0 个正向触发器**：

| 触发器 | 态度变化 | 条件 |
|--------|---------|------|
| 经济碾压 | **-3** | 玩家 cash > AI cash × 1.5 |
| 军事威胁 | **-2** | 守卫 > 20 且 AI power < 50 |
| 矿区竞争 | **-1** | 玩家矿场 ≥ 5 |
| 自然傲慢 | **-1** | AI power ≥ 60 且态度 > -50 |

**唯一的"保护"机制**: 如果玩家与该派系有互不侵犯条约（pact），态度底线为 10。但这不是正向增长，只是一个下限保护。

**后果**: 
- 游戏进行足够长时间后，所有 AI 态度必然降到 -20 以下
- 态度 ≤ -20 是触发 AI 攻击的条件之一
- 玩家无法通过任何游戏内行为改善关系（外交界面的"行贿"功能不在 turn_engine 的自动更新中）

### 3.2 扩张系统：过于缓慢

AI 每季度只对 **一个区域** 增加 **+2 ai_presence**：

```lua
-- turn_engine.lua 扩张逻辑
if faction.cash >= expand_threshold then
    -- 选择一个目标区域
    target_region.ai_presence[faction_id] = target_region.ai_presence[faction_id] + 2
end
```

以 200 个季度（50 年游戏时长）计算，AI 在单个区域最多增加 400 点存在感——但这是理论上限。实际上 AI 会分散到多个区域，每个区域增长更慢。

### 3.3 缺失的 AI 行为

以下行为在代码中 **完全缺失**：

| 缺失行为 | 影响 |
|---------|------|
| AI 贸易行动 | 无法通过贸易影响玩家经济 |
| AI 外交行动 | 无法主动提议结盟/制裁 |
| AI 经济制裁 | 无法削弱玩家现金流 |
| AI 间谍/渗透 | 无法降低玩家控制力 |
| AI-to-AI 交互 | 两个 AI 派系完全独立，不会结盟或冲突 |
| AI 对事件的反应 | 历史事件不影响 AI 行为 |

### 3.4 力量增长：线性且有上限

AI 力量（power）每季度仅增长 **+2**（战争时 +3），上限 100：

```lua
faction.power = math.min(100, faction.power + (is_war and 3 or 2))
```

这意味着 AI 力量增长是完全可预测的线性过程，缺乏戏剧性。

---

## 4. AI 经济系统 — 无限增长

**文件**: `scripts/systems/turn_engine.lua`

### 4.1 复利增长无上限

```lua
faction.cash = faction.cash + math.floor(faction.cash * rate)
```

| 派系 | 初始资金 | 增长率 | 50季度后 | 100季度后 | 200季度后 |
|------|---------|--------|---------|----------|----------|
| local_clan | 800 | 5%/季 | ~8,800 | ~97,000 | ~11.7 亿 |
| foreign_capital | 2,000 | 8%/季 | ~93,000 | ~4.3 百万 | ~9.3 万亿 |

**后果**:
- 经济碾压触发器（玩家 cash > AI cash × 1.5）后期几乎不可能触发
- 但反过来 AI 的高现金并不会产生实际游戏影响（AI 不会用现金做任何事，除了满足 expand_threshold 条件）
- 数值上 AI 看起来很强，但实际影响有限——造成"数值虚假"的感觉

### 4.2 建议

添加 AI 现金上限，或让 AI 主动花费现金执行游戏行为（扩张、军事、经济干预等）。

---

## 5. 地图系统 — 大量未完成内容

**文件**: `scripts/ui/ui_map_widget.lua`

### 5.1 层级系统：5/8 锁定

```lua
local LAYERS = {
    { id = "control",  label = "控制", always_on = true },  -- ✅ 功能正常
    { id = "resource", label = "资源" },                     -- ✅ 功能正常
    { id = "security", label = "安全" },                     -- ✅ 功能正常
    { id = "trade",    label = "贸易", locked = true },      -- 🔒 锁定
    { id = "politics", label = "政治", locked = true },      -- 🔒 锁定
    { id = "military", label = "军事", locked = true },      -- 🔒 锁定
    { id = "culture",  label = "文化", locked = true },      -- 🔒 锁定
    { id = "intel",    label = "情报", locked = true },      -- 🔒 锁定
}
```

只有 控制/资源/安全 三个层级有实际数据和渲染逻辑。其余 5 个在 UI 上显示为锁定按钮。

### 5.2 节点系统：7 种定义，3 种使用

代码定义了 7 种节点类型：mine, industrial, capital, port, border, cultural, strategic

实际使用的节点（GAME_NODES）只有 3 个：

| 节点 ID | 类型 | 名称 |
|---------|------|------|
| mine_district | mine | 矿区 |
| industrial_town | industrial | 工业城 |
| capital_city | capital | 首都 |

port、border、cultural、strategic 类型的节点完全未使用。

### 5.3 时代主题遗留

`ERA_MAP_THEMES` 包含 7 个时代条目（1-7），但游戏实际只有 5 个时代。时代 6、7 是历史遗留代码：

```lua
-- 这两个条目不会被使用
[6] = { bg = {30, 30, 40}, ... },   -- 不存在的第6时代
[7] = { bg = {20, 20, 30}, ... },   -- 不存在的第7时代
```

**影响**: 无功能影响（不会被索引到），但属于死代码，应清理。

---

## 6. 外资系统 — 影响力不足

**文件**: `scripts/systems/turn_engine.lua` + `scripts/data/balance.lua`

### 6.1 外资（foreign_capital）特性

| 属性 | 值 | 对比 local_clan |
|------|-----|----------------|
| 初始资金 | 2,000 | 800（2.5倍） |
| 增长率 | 8%/季 | 5%/季 |
| 攻击倾向 | 0.1 | 0.3（更被动） |
| 扩张门槛 | 1,000 | 600（更高） |
| 战争逃离率 | 0.6（60% 概率不逃） | 无此机制 |

### 6.2 战争逃离机制

当游戏处于战争状态时，每季度外资有 40% 概率"逃离"：
- 损失 15% 现金
- 损失 3 点力量

**问题**: 
- 这是外资唯一的特殊互动机制
- 逃离效果有限（15% 现金损失在复利增长下一两个季度就恢复了）
- 没有外资特有的经济干预手段（如操纵物价、控制矿产、影响通胀）

### 6.3 `foreign_control` 修饰符

balance.lua 中存在 `foreign_control` 相关的修饰符影响态度和力量，但在 turn_engine.lua 中没有系统性地生成或管理这个值。它只在个别事件中作为 modifier 效果出现，不是持续性系统。

---

## 7. 战斗系统 — 平衡性分析

**文件**: `scripts/systems/combat.lua`

### 7.1 AI 攻击条件

AI 发动攻击需要同时满足 3 个条件：

```
attitude ≤ -20  AND  power ≥ 40  AND  random() < 0.35
```

由于态度必然下降（见 §3.1），前两个条件迟早满足。35% 的随机概率意味着平均每 3 个季度一次攻击尝试。

### 7.2 战斗力计算

**玩家**:
```
player_power = guards × morale_mult × equipment_bonus × chief_bonus × tech_bonus
```

**AI**:
```
ai_power = faction.power × (1 + presence / 200)
```

AI 战斗力计算非常简单，仅依赖 power 和区域存在感。

### 7.3 战斗结果对地图影响

| 结果 | ai_presence | player control | 其他 |
|------|-------------|----------------|------|
| 玩家胜利 | -8 | +3 | 缴获 AI 现金 |
| 玩家失败 | +7 | -5 | 安全 -1，损失守卫和现金 |

**不对称性**: 失败惩罚（-5 control, +7 presence）远大于胜利收益（+3 control, -8 presence），这使得连败会急剧恶化局面。

---

## 8. 区域系统 — 过于简单

**文件**: `scripts/data/regions_data.lua`

### 8.1 初始状态

| 区域 | 玩家控制 | local_clan | foreign_capital |
|------|---------|------------|-----------------|
| 矿区 | 80 | 15 | 5 |
| 工业城 | 20 | 30 | 25 |
| 首都 | 5 | 20 | 35 |

**总玩家控制**: 105（3 区域之和）
**总 AI 存在**: local_clan 65, foreign_capital 65

### 8.2 不足之处

- 只有 3 个区域，战略深度有限
- 区域之间没有连接/邻接关系
- 没有区域特殊资源或独特产出
- 区域属性只有 control / ai_presence / security / development，缺少人口、贸易量等维度
- 区域事件（如叛乱、罢工、外资撤出）未与区域数据联动

---

## 9. 改进建议

### 9.1 紧急修复（BUG）

| 优先级 | 任务 | 文件 |
|--------|------|------|
| P0 | 修复 Report 标签页 4 处状态路径引用 | ui_world.lua |
| P0 | 清理 ERA_MAP_THEMES 多余的时代 6-7 条目 | ui_map_widget.lua |

### 9.2 AI 行为增强

| 优先级 | 建议 | 效果 |
|--------|------|------|
| P1 | 添加正向态度触发器（贸易合作、外交礼物） | 让玩家有改善关系的手段 |
| P1 | 给 AI 现金增长添加上限（如 10,000） | 避免数值爆炸 |
| P1 | AI 主动使用现金（雇佣兵、经济制裁、收买玩家员工） | 让 AI 资金有实际意义 |
| P2 | 外资特有行为：操纵通胀、控制矿价、资本外逃 | 区分两个 AI 派系 |
| P2 | AI-to-AI 交互（结盟、竞争、背叛） | 增加政治深度 |
| P3 | AI 对历史事件的反应（如战争期间外资加速逃离） | 增加沉浸感 |

### 9.3 地图系统扩展

| 优先级 | 建议 | 效果 |
|--------|------|------|
| P2 | 解锁贸易/军事层级（最少这两个） | 地图信息更丰富 |
| P2 | 增加 2-3 个游戏节点（港口、边境） | 增加战略选择 |
| P3 | 添加区域连接/邻接关系 | 为路径规划和包围战术铺路 |
| P3 | 区域独特资源和产出 | 增加经济策略深度 |

### 9.4 外资系统深化

| 优先级 | 建议 | 效果 |
|--------|------|------|
| P1 | `foreign_control` 作为持续性系统运作（每季度根据外资存在感自动计算） | 外资影响可感知 |
| P2 | 外资特有经济干预（通胀操纵、矿价波动、投资撤出） | 外资不只是"另一个 AI" |
| P2 | 玩家与外资的特殊互动选项（吸引投资 vs 驱逐外资） | 增加策略层 |

---

## 附录：关键代码位置速查

| 系统 | 文件 | 关键函数/区域 |
|------|------|-------------|
| 世界页面 UI | scripts/ui/ui_world.lua | `_CreateSeasonSummary()`, `_CreateRelationsTab()` |
| 地图渲染 | scripts/ui/ui_map_widget.lua | `LAYERS`, `GAME_NODES`, `ERA_MAP_THEMES` |
| 区域数据 | scripts/data/regions_data.lua | `RegionsData.GetInitialRegions()` |
| AI 更新 | scripts/systems/turn_engine.lua | Phase 6: AI Update |
| 战斗 | scripts/systems/combat.lua | `Combat.ResolveAIActions()` |
| AI 配置 | scripts/data/balance.lua | `Balance.AI`, `Balance.COMBAT` |
| 游戏状态 | scripts/game_state.lua | `GameState.CreateNew()` AI factions 初始化 |
