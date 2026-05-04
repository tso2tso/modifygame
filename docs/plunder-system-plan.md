# 武力掠夺发展路线 — 开发计划

## 需求概述

当前玩家开局路线单一（屯矿卖矿稳健发展），需新增 **武力掠夺路线**，让玩家可通过烧杀抢掠积累前期资本。核心设计：**高收益但有声誉代价**，避免掠夺成为无脑最优解。

---

## 设计方案

### 三个掠夺行动

| 行动 | 目标 | AP | 现金门槛 | 预期收益 | 风险 |
|------|------|-----|---------|---------|------|
| 劫掠商队 | 截击过路商队 | 1 | 100 | 150-350 克朗 | 失败损失护卫 |
| 夺取矿脉 | 强占 AI 矿产 | 2 | 200 | 获得临时矿脉(4季) | 失败声誉暴跌 |
| 勒索外资 | 威胁外国资本 | 2 | 300 | 300-600 克朗 | 外资加速反击 |

### 掠夺判定机制

**不复用完整 `Combat.Resolve()`**，而是用轻量级力量对比检定：

```
成功率 = clamp(玩家战力 / (目标难度 x 随机因子), 0.15, 0.90)
骰点 < 成功率 -> 成功，获得战利品
骰点 >= 成功率 -> 失败，承受惩罚
```

- 劫掠商队难度=15，夺取矿脉难度=25，勒索外资难度=30
- 每个行动有独立冷却（劫掠2季，夺取4季，勒索3季）

### 声誉系统（核心平衡机制）

**新增 `reputation` 字段**（-100 ~ 0，初始 0）：

| 声誉范围 | 等级 | 效果 |
|---------|------|------|
| 0 ~ -10 | 清白 | 无影响 |
| -11 ~ -30 | 可疑 | 交易价格 +5% |
| -31 ~ -50 | 恶名 | 交易价格 +15%，外交行动 AP+1 |
| -51 ~ -80 | 臭名昭著 | 交易价格 +25%，无法外交，AI 攻击概率 +20% |
| -81 ~ -100 | 公敌 | 交易价格 +40%，AI 每季攻击，地区控制力 -2/季 |

**声誉变化**：
- 劫掠商队: -5
- 夺取矿脉: -15
- 勒索外资: -10
- 每季自然恢复: +2（但不超过 0）
- "公敌"级别时地区控制力每季 -2

### 数值平衡验证

**对比两条路线（前 8 年 / 32 回合）**：

| 路线 | 总收入 | 代价 |
|------|--------|------|
| 稳健采矿 | ~4,480 克朗 | 无负面效果 |
| 纯掠夺（每2季劫掠1次+偶尔夺矿） | ~6,800 克朗 | 声誉 -40~-60，交易溢价 15-25%，AI 攻击增加 |

掠夺路线收入高 ~50%，但交易溢价+AI 反击会吞噬大量利润，且中后期必须转型（声誉恢复需要 15-25 季）。这确保了掠夺是**可行但有代价的替代路线**，而非支配策略。

### AI 反应增强

- 声誉 < -30 时，AI `ai_attack_threshold` 从 -20 降至 -10（更容易主动攻击玩家）
- 声誉 < -50 时，AI 攻击概率额外 +20%
- 勒索外资后，`foreign_capital` 的 `aggression` 临时 +15（持续 4 季）

---

## 实现步骤（5 步，~340 行新代码）

### 步骤 1：数据层 -- `scripts/data/balance.lua`（+50 行）

在 `Balance.TRADE.raid_ai` 附近新增两个常量表：

```lua
Balance.PLUNDER = {
    raid_caravan   = { ap = 1, cash = 100, cooldown = 2, difficulty = 15,
                       loot_min = 150, loot_max = 350, rep_cost = -5,
                       fail_guard_loss = 2 },
    seize_vein     = { ap = 2, cash = 200, cooldown = 4, difficulty = 25,
                       vein_duration = 4, vein_gold_per_turn = 80, rep_cost = -15,
                       fail_rep_extra = -10 },
    extort_foreign = { ap = 2, cash = 300, cooldown = 3, difficulty = 30,
                       loot_min = 300, loot_max = 600, rep_cost = -10,
                       fail_aggression_boost = 15 },
    success_floor = 0.15,
    success_ceil  = 0.90,
}

Balance.REPUTATION = {
    initial        = 0,
    min            = -100,
    max            = 0,
    recovery_per_turn = 2,
    thresholds = {
        suspicious   = -10,
        notorious    = -30,
        infamous     = -50,
        public_enemy = -80,
    },
    trade_penalty = { 0, 0.05, 0.15, 0.25, 0.40 },
    ai_attack_bonus = { 0, 0, 0, 0.20, 0.50 },
    control_decay = { 0, 0, 0, 0, 2 },
}
```

### 步骤 2：状态层 -- `scripts/game_state.lua`（+30 行）

**a)** 在 `CreateNew()` 中新增：

```lua
reputation = 0,
plunder_cooldowns = {
    raid_caravan   = 0,
    seize_vein     = 0,
    extort_foreign = 0,
},
seized_veins = {},
```

**b)** 新增工具函数：

```lua
function GameState.GetReputationTier(state)
    -- 返回 1-5 对应声誉等级
end

function GameState.GetTradePenalty(state)
    -- 返回声誉导致的交易溢价比例
end
```

**c)** 修改现有交易相关函数，叠加声誉交易溢价。

### 步骤 3：逻辑层 -- `scripts/systems/combat.lua`（+120 行）

新增掠夺核心逻辑函数：

```lua
function Combat.PlunderCheck(state, action_key)
    -- 轻量级力量检定（不走完整 Combat.Resolve）
end

function Combat.ApplyPlunderResult(state, action_key, success)
    -- 执行掠夺结果：扣AP/cash、修改声誉、发放/扣除战利品
end

function Combat.RaidCaravan(state) ... end
function Combat.SeizeVein(state) ... end
function Combat.ExtortForeign(state) ... end
```

修改现有 `Combat.ResolveAIActions()`（约 line 195）：
- 读取声誉等级，声誉差时降低 AI 攻击阈值、提高攻击概率

### 步骤 4：回合引擎 -- `scripts/systems/turn_engine.lua`（+40 行）

在 Phase 4.5（influence）之后、Phase 5（AI）之前，插入 **Phase 4.6**：

```lua
-- Phase 4.6: 掠夺系统每季结算
-- 1. 冷却计时器 tick（所有 cooldown > 0 的 -1）
-- 2. 声誉自然恢复（+2，不超过 0）
-- 3. 夺取矿脉到期检查（remaining -1，到 0 移除）
-- 4. 夺取矿脉产出（加到 cash）
-- 5. 公敌级别：地区控制力衰减
```

### 步骤 5：UI 层 -- `scripts/ui/ui_action_modals.lua`（+100 行）

在 `ShowTrade()` 的武装突袭按钮（`_TradeMilitaryStrike()`）之后，新增掠夺行动区块：

```lua
_SectionHeader("掠夺行动")
_PlunderOption("劫掠商队", "截击过路商队...", "raid_caravan")
_PlunderOption("夺取矿脉", "强占AI矿产...", "seize_vein")
_PlunderOption("勒索外资", "威胁外国资本...", "extort_foreign")
```

复用现有 UI 模式：
- `_TradeOption()` 构建选项行
- `_CanAfford()` 检查 AP + 现金
- `_Spend()` 原子扣减
- 冷却中按钮灰色，显示剩余冷却回合
- 声誉状态在交易弹窗中展示当前等级和效果

---

## 修改文件清单

| 文件 | 改动类型 | 预估行数 |
|------|---------|---------|
| `scripts/data/balance.lua` | 新增常量 | +50 |
| `scripts/game_state.lua` | 新增字段+工具函数 | +30 |
| `scripts/systems/combat.lua` | 新增掠夺函数+修改AI | +120 |
| `scripts/systems/turn_engine.lua` | 新增 Phase 4.6 | +40 |
| `scripts/ui/ui_action_modals.lua` | 新增掠夺 UI | +100 |

**总计**: ~340 行新代码，跨 5 个文件

---

## 向后兼容

- `reputation` 默认 0（旧存档等价清白状态）
- `plunder_cooldowns` 默认全 0（立即可用）
- `seized_veins` 默认空表
- 所有读取使用 `state.reputation or 0` 防护
- 无需 save_load.lua 迁移

---

## 验证方案

1. **构建验证**：调用 build 工具，无 LSP 错误
2. **数据检查**：`Balance.PLUNDER` 和 `Balance.REPUTATION` 表结构正确
3. **功能测试**：
   - 交易弹窗中出现 3 个掠夺按钮
   - AP/现金不足时按钮灰色
   - 冷却中显示剩余回合
   - 劫掠成功获得现金+声誉下降
   - 劫掠失败损失护卫
   - 声誉降至"恶名"后交易价格上升
   - 声誉降至"公敌"后地区控制力衰减
   - 每季声誉自然恢复 +2
   - 夺取矿脉成功后 4 季产金，到期自动移除
4. **平衡验证**：纯掠夺路线 32 回合总收入约 6800 但交易溢价抵消大量利润
5. **存档兼容**：旧存档加载不报错，掠夺系统处于初始状态
