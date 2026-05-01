# 百年萨拉热窝：黄金家族 — 完整数值系统文档

> **版本**: v0.5.1  
> **游戏时间跨度**: 1904年 Q1 — 1955年 Q4（共 208 个季度 / 52 年）  
> **核心循环**: 采矿 → 结算 → 事件 → 行动 → 下一季度  
> **数据来源**: `scripts/data/balance.lua`、`scripts/systems/*.lua`、`scripts/data/*.lua`、`scripts/game_state.lua`

---

## 目录

1. [时间系统](#1-时间系统)
2. [行动点系统（AP）](#2-行动点系统ap)
3. [资源与起始状态](#3-资源与起始状态)
4. [矿业系统](#4-矿业系统)
5. [工人与人力系统](#5-工人与人力系统)
6. [武装系统](#6-武装系统)
7. [经济结算系统](#7-经济结算系统)
8. [通胀系统](#8-通胀系统)
9. [贷款系统](#9-贷款系统)
10. [股市系统（GBM）](#10-股市系统gbm)
11. [科技系统](#11-科技系统)
12. [家族系统](#12-家族系统)
13. [地区与地图系统](#13-地区与地图系统)
14. [AI 势力系统](#14-ai-势力系统)
15. [战斗系统](#15-战斗系统)
16. [事件系统](#16-事件系统)
17. [分支事件系统](#17-分支事件系统)
18. [大国博弈系统](#18-大国博弈系统)
19. [情报/外交/交易行动](#19-情报外交交易行动)
20. [影响力系统](#20-影响力系统)
21. [监管压力系统](#21-监管压力系统)
22. [胜利条件判定](#22-胜利条件判定)
23. [回合结算完整流程](#23-回合结算完整流程)
24. [幸运事件系统](#24-幸运事件系统广告激励)
25. [破产救济系统](#25-破产救济系统)
26. [附录：事件→股价映射完整表](#26-附录事件股价映射完整表)
27. [胜利条件可达性分析（详细计算）](#27-胜利条件可达性分析详细计算)

---

## 1. 时间系统

| 参数 | 值 | 说明 |
|------|-----|------|
| 起始时间 | 1904年 Q1 | 家族取得矿权 |
| 结束时间 | 1955年 Q4 | 游戏自然结束（战后重建期结束） |
| 季度/年 | 4 | 春/夏/秋/冬 |
| 总季度数 | 208 | (1955-1904+1) × 4 |

### 时代划分（5 章）

| 章节 | 时间段 | 名称 | 代号 | 战时标记 |
|------|--------|------|------|----------|
| 第一章 | 1904-1913 | 铜版帝国 | chapter1 | 否 |
| 第二章 | 1914-1918 | 战报红章 | chapter2 | **是** (`war_stripe = true`) |
| 第三章 | 1919-1940 | 黑金工业 | chapter3 | 否 |
| 第四章 | 1941-1945 | 战时灰幕 | chapter4 | **是** (`war_stripe = true`) |
| 第五章 | 1946-1955 | 战后余烬 | chapter5 | 否 |

> 战时章节（`war_stripe = true`）会影响：通胀加速（+12%/季 vs +0.6%/季）、股市波动放大（sigma ×1.8）、税率上升（12% vs 5%）、经济胜利点 ×0.6、军事胜利点 ×1.25、AI 势力增长加速（+3/季 vs +2/季）。

---

## 2. 行动点系统（AP）

### 基础值

| 参数 | 值 |
|------|-----|
| 每季基础 AP | 6 |
| 最大加成上限 | +4（即 AP 上限 = 10） |

### AP 计算公式（`CalcMaxAP()`）

```
max_ap = base_ap (6)
       + tech_ap_bonus（科技加成，如"电报网络"）
       + influence_ap_bonus（影响力阈值加成）
       - war_penalty（战争状态 -1）
       - security_penalty（矿区治安 ≤ 1 时 -1）
       - vacancy_penalty（空缺岗位 ≥ 2 时 -1）

最终 AP = max(1, min(max_ap, base_ap + max_bonus(4)))
```

> AP 最低保障 = 1，不会降到 0。

### AP 购买

| 参数 | 值 |
|------|-----|
| 每次购买价格 | 200 现金 |
| 每季最多购买次数 | 2 |
| 购买获得 | +1 临时 AP（当季有效） |

### AP 消耗优先级

优先消耗临时 AP (`ap.temp`)，再消耗常规 AP (`ap.current`)。

---

## 3. 资源与起始状态

### 起始资源

| 资源 | 初始值 | 说明 |
|------|--------|------|
| 现金 (cash) | 1,000 | |
| 黄金 (gold) | 5 | |
| 白银 (silver) | 0 | |
| 煤炭 (coal) | 0 | |
| 工人 (workers) | 10 | |
| 护卫 (guards) | 5 | |

### 其他初始状态

| 项目 | 初始值 |
|------|--------|
| 通胀乘数 | 1.0 |
| 工人士气 | 70 |
| 护卫士气 | 70 |
| 护卫装备等级 | 1 |
| 补给储备 | 20 |
| 经济胜利点 | 0 |
| 军事胜利点 | 0 |
| 黄金自动出售 | 关闭 (false) |
| 贷款 | 无 |
| 科技 | 无 |
| 家族成员 | 3 人 |
| 矿山 | 1 座（等级 1） |
| 矿山槽位 | 4（基础） |
| 勘探状态 | 无 |
| 影响力 | 0 |
| 监管压力 | 0 |
| 合作分数 | 0 |

---

## 4. 矿业系统

### 基础参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 黄金售价 | 50 / 单位 | 受通胀乘数影响 |
| 白银售价 | 15 / 单位 | 受通胀乘数影响 |
| 煤炭售价 | 8 / 单位 | 工业区 |
| 矿山最大等级 | 5 | — |
| 升级基础费用 | 200 × 当前等级 | 受资产价格因子 (`AssetPriceFactor`) 影响 |
| 基础矿山槽位 | 4 | 科技可增加 (`mine_slots` 效果) |
| 事故基础概率 | 5% / 季 | 受治安和科技影响 |

### 产金公式（`_CalcMineOutput()`）

```
单矿产金 = floor(
    (base_output + mine_output_base_bonus)
    × levelMultiplier
    × (1 + mine_output_mult_bonus)
    × (1 + positionBonus)
    + workerBonus
)

其中：
  base_output = mine.base_output（默认 2）
  mine_output_base_bonus = 来自科技/事件的加法加成
  levelMultiplier = 1.0 + (mine.level - 1) × 0.20
  mine_output_mult_bonus = 来自科技/事件的乘法加成
  positionBonus = 矿业总监岗位加成 (满配 1.0 / 半配 0.5 / 差配 -0.1 / 空缺 -0.30)
  workerBonus = floor(hired_workers / worker_per_bonus(10)) + worker_efficiency_bonus
```

> 产金受每座矿山独立的 `reserve` 储量限制，开采量 = min(计算产出, 剩余储量)。开采后储量减少。

### 产银公式

```
单矿产银 = floor(base_silver_output × (1 + (mine.level - 1) × 0.20))
```

> 白银消耗 `silver_reserve` 储量。

### 煤炭采集（工业区）

| 参数 | 值 |
|------|-----|
| 基础每季采煤量 | 8 单位 |
| 煤炭单价 | 8 / 单位 |
| 采煤公式 | `floor(base_coal_output × (1 + (development - 1) × 0.15))` |
| 储量消耗 | 每季采出量从 `coal_reserve` 中扣除 |

> 煤炭仅在工业区（`type = "industrial"`）且 `coal_reserve > 0` 时采集，全量出售。

### 黄金出售

| 模式 | 行为 |
|------|------|
| 手动（默认） | 玩家在产业页手动出售，保留全部库存 |
| 自动出售 | 开启后，每季结算时保留库存的 **10%**（四舍五入），出售剩余黄金 |

自动出售价格 = `gold_price × inflation × (1 + gold_price_bonus) × (1 + gold_price_mod)`

### 勘探系统

| 参数 | 值 | 说明 |
|------|-----|------|
| 基础费用 | 150 现金 | |
| 所需时间 | 2 季 | 进度每季 +1，到 2 完成 |
| AP 消耗 | 1 | 启动时 |
| 基础成功率 | 60% | |
| 衰减因子 | 0.85 / 次 | 每次勘探后成功率衰减：`base × decay^count` |
| 最低成功率 | 10% | `prospect_min_chance` |
| 科技加成 | `prospect_success` 效果直接加到成功率 | |

成功时新矿山属性：

| 属性 | 值 |
|------|-----|
| 等级 | 1 |
| 黄金储量 | 100-200（随机） |
| 白银储量 | 200-400（随机） |
| 基础产出 | 2 |

### 矿山迁移

当矿山储量耗尽（`reserve ≤ 0`）时：
- 如果存在其他未枯竭矿山，工人自动迁移到储量最多的矿山
- 枯竭矿山标记为 `depleted = true`，停止生产

---

## 5. 工人与人力系统

| 参数 | 值 | 说明 |
|------|-----|------|
| 工人基础工资 | 8 / 季 | 受通胀和劳动力成本因子影响 |
| 招聘费用 | 30 / 人 | 一次性，受 `LaborCostFactor` 和影响力折扣影响 |
| 解雇补偿 | 5 / 人 | 一次性 |
| 每 10 名工人 | +1 产能加成 | 体现为 `workerBonus` |
| 士气工资阈值 | 0.8 | 工资低于区域均值 80% 时士气下降 |

### 招聘费用公式

```
实际招聘费 = hire_cost(30) × LaborCostFactor × (1 - InfluenceRecruitDiscount) × hireCostMul × count
```

- `LaborCostFactor = inflation × (1 + worker_cost_multiplier修正)`
- `InfluenceRecruitDiscount` = 影响力阈值 70 时的 -10% 折扣
- `hireCostMul` = 事件修正器 `hire_cost_multiplier`

### 工人士气变动（每季结算）

| 条件 | 变动 |
|------|------|
| 工资 < 基础工资 (8) | 士气 -5 |
| 工资 ≥ 基础工资 | 士气 +1（自然恢复） |
| 士气 < 30 | 触发罢工警告 |

---

## 6. 武装系统

### 基础参数

| 参数 | 值 |
|------|-----|
| 护卫工资 | 12 / 季（受通胀影响） |
| 招募费用 | 30 / 人（一次性） |
| 装备费用 | 50 / 人（一次性） |
| 基础战力 | 1.0 / 护卫 |
| 士气乘数 | 0.01（70 士气 = ×0.7） |
| 补给消耗 | 3 单位 / 护卫 / 季 |
| 补给单价 | 2 / 单位 |
| 基础士气 | 70 |
| 装备等级 | 1-5 |
| 装备战力加成 | +15% / 级（`equipment_bonus = 0.15`） |

### 士气变动

| 事件 | 变动 |
|------|------|
| 每季自然衰减 | -2 |
| 军务主管加成 | +floor(posBonus × 3)（减缓衰减） |
| 战斗胜利 | +10 |
| 战斗失败 | **-18** (`defeat_morale = -18`) |

---

## 7. 经济结算系统

每季结算按以下顺序执行（`Economy.Settle()`）：

### 收入项

| 来源 | 计算方式 |
|------|----------|
| 黄金出售收入 | 仅在 `gold_auto_sell = true` 时：保留 10%（四舍五入），出售剩余。价格 = `gold_price × inflation × (1 + gold_price_bonus) × (1 + gold_price_mod)` |
| 白银出售收入 | 全量出售（消耗 silver_reserve）：`silver × silver_price(15) × inflation × (1 + silver_price_mod)` |
| 煤炭出售收入 | 工业区每季采煤并全量出售：`coal × coal_price(8) × inflation × (1 + coal_price_mod)` |
| 地区被动收入 | 见下方"地区控制度被动收入" |
| 金融被动收入 | 科技"金融网络"解锁后：`finance_network × inflation` |
| 贸易被动收入 | 科技"贸易路线"解锁后：`trade_income × inflation` |
| 影子收入 | 事件修正器 `shadow_income`：`shadow_income × inflation`（同时增加监管压力 +2） |

### 地区控制度被动收入

| 地区类型 | 触发条件 | 收入公式 |
|----------|----------|----------|
| 矿区 (mine) | 控制度 ≥ 50% | `floor((control - 50) / 10) × 20 × inflation` |
| 工业城 (industrial) | 控制度 ≥ 40% | `floor(control × 1.5 × inflation × max(0.4, 1 + civilian_demand))` |
| 首都 (capital) | 控制度 ≥ 30% | 减税效果：每超出 10% → 税率 -1% |

### AI 存在度负面效果

| 条件 | 效果 |
|------|------|
| 任意 AI 存在度 ≥ 50% | 每超出 10% → 额外支出 +15 × inflation |

### 支出项

| 类别 | 计算方式 |
|------|----------|
| 工人工资 | `hired × wage × laborCostFactor × hireCostMul` |
| 军事开支 | `guards × guard_wage(12) × inflation` |
| 补给开支 | `guards × supply_per_guard(3) × supply_cost(2) × inflation × supplyDiscount × (1 + transportRisk)` |
| 税收 | `cash × tax_rate`（详见下方税率计算） |
| AI 存在惩罚 | 见上方"AI 存在度负面效果" |
| 运输风险损失 | `exposedIncome × min(0.30, transportRisk × 0.25)` |

### 税率计算

```
base_tax = 战时 12% / 和平 5%

修正项（累加）：
+ legitimacy_mod     （合法性修正，正值加税负值减税）
+ political_standing_mod
+ public_support_mod
+ corruption_risk_mod
+ risk_mod
+ regulation_pressure_mod
+ tax_reduction（科技减税，负值）
- 首都减税（控制度 ≥30% 时：(control - 30) / 10 × 1%）

final_tax = max(0, base_tax + 各修正项合计)
```

### 收入修正器

全部总收入受事件修正器 `income_mod` 影响（范围 -75% ~ +100%）：
```
adjustment = floor(grossIncome × clamp(income_mod, -0.75, 1.00))
```

### 破产处理

当 `cash < 0` 时：
1. 紧急变卖黄金：`sellGold = min(gold, ceil(|cash| / gold_price))`
2. 仍为负则归零：`cash = 0`

---

## 8. 通胀系统

### 基础参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 基础因子 | 1.0 | 开局无通胀 |
| 和平漂移 | +0.006 / 季 | +0.6%/季，年化约 +2.4% |
| 战时漂移 | +0.12 / 季 | +12%/季，恶性通胀 |
| 通缩漂移下限 | -0.04 / 季 | 大萧条/战后通缩 |
| 上限 | 20.0 | 最多 20 倍物价 |
| 下限 | 0.45 | 大萧条通缩下限 |

### 通胀更新公式（乘法模型）

```
inflation_factor = inflation_factor × (1 + drift)

drift = base_drift (和平 0.006 / 战时 0.12)
      + inflation_drift_mod（事件修正器）
      + inflation_delta（事件一次性推动）

inflation_factor = clamp(inflation_factor, 0.45, 20.0)
```

> 注意：v0.5.0 起通胀使用**乘法模型**（`× (1 + drift)`），而非旧的加法模型（`+ drift`）。

### 资产价格因子

```
AssetPriceFactor = inflation_factor × (1 + asset_price_mod)

asset_price_mod 范围：[-0.60, +1.00]
  -0.60 = 大萧条期间资产价格跌 60%
  +1.00 = 战时资产泡沫价格翻倍
```

### 劳动力成本因子

```
LaborCostFactor = inflation_factor × (1 + worker_cost_multiplier_mod)
```

### 通胀影响范围

- 黄金/白银/煤炭售价 × inflation
- 工人工资 × LaborCostFactor
- 护卫工资 × inflation
- 补给费用 × inflation
- 地区被动收入 × inflation
- 矿山升级费用 × AssetPriceFactor
- 科技研发费用 × inflation

---

## 9. 贷款系统

### 基础参数

| 参数 | 值 |
|------|-----|
| 同时最多持有 | 3 笔 |
| 违约惩罚 | 本金膨胀 +15% |
| 最多展期次数 | 1 次 |
| 坏账核销士气惩罚 | -10 |
| 最大杠杆率 | 80%（超过禁止再贷款） |

### 抵押估值（`CalcLoanCollateralValue()`）

| 资产类型 | 抵押率 |
|----------|--------|
| 实体资产（现金 + 黄金 + 白银 + 煤炭 + 矿山价值） | 80% (`real_asset_ratio`) |
| 股票市值 | 25% (`stock_asset_ratio`) |

```
实体资产 = cash + gold × gold_price + silver × silver_price + coal × coal_price + Σ(mine.level × 200)
股票市值 = Σ(stock.shares × stock.price) for all stocks
抵押价值 = 实体资产 × 0.80 + 股票市值 × 0.25
```

### 可选贷款档

| 档位 | 额度比例 | 保底金额 | 基础季利率 | 期限（季） |
|------|---------|---------|-----------|-----------|
| 小额短贷 | 抵押价值 × 15% | 300 | 4% | 4 |
| 中额贷款 | 抵押价值 × 35% | 800 | 5% | 6 |
| 大额长贷 | 抵押价值 × 60% | 2,000 | 6% | 8 |

### 杠杆利率（`CalcLeverage()`）

```
leverage = 总负债 / 抵押价值
实际利率 = base_interest × (1 + leverage × 1.5)
```

示例：杠杆率 0.5 → 利率 ×1.75；杠杆率 1.0 → 利率 ×2.5

### 结算逻辑（每季 Phase 1.6）

1. **付息**：`interest = ceil(principal × 实际利率)`
   - 付得起 → 扣现金，累计 `total_paid`
   - 付不起 → 启动**强制抵押清算**：
     1. 第一步：强制变卖黄金偿付利息
     2. 第二步：黄金不够则降级矿山换现金（退还升级费的 50%）
     3. 每次清算额外扣士气 -5
     4. 清算后凑够 → 正常扣款
     5. 清算后仍不够 → 真正违约，本金 × 1.15 膨胀，连续违约计数 +1
2. **到期还本**：
   - 付得起 → 清偿，贷款消失
   - 付不起 + 未展期过 → 部分清偿 + 延长 4 季 + 本金 × 1.15
   - 付不起 + 已展期 → 强制清算偿还，仍不够则坏账核销（士气 -10）

### 破产条件

| 条件 | 阈值 |
|------|------|
| 连续违约（强制清算后仍无法偿付） | 4 季 → 触发破产 |
| 净资产连续为负 | 4 季 → 触发破产 |
| 预警 | 连续违约 2 季开始警告 |

---

## 10. 股市系统（GBM）

### 核心模型：几何布朗运动

```
P(t+1) = P(t) × exp((mu - sigma²/2) × dt + sigma × eps × sqrt(dt))

其中：
  eps ~ N(0,1) 由 Box-Muller 变换生成：
    u1, u2 ~ U(0,1)
    eps = sqrt(-2 × ln(u1)) × cos(2π × u2)
  dt = 1（每季度推进一次）
```

### 三层修正

| 层级 | 来源 | 说明 |
|------|------|------|
| L1 基本面 | 每支股票自带 `mu` / `sigma` | 长期趋势，由 `balance.lua STOCKS` 定义 |
| L2 事件修正 | `event_mu_mods[]` 中的 `delta_mu` | 短期冲击，每季消耗（`remaining -= 1`），到期移除 |
| L3 战时放大 | `sigma × 1.8` | 战争章节（`war_stripe = true`）全局生效 |

### 有效 mu 计算

```
effective_mu = stock.mu + Σ(event_mod.delta_mu for all active mods)
```

### 6 支股票数据

| ID | 名称 | 初始价 | mu/季 | sigma | 板块 |
|----|------|--------|-------|-------|------|
| sarajevo_mining | 萨拉热窝矿业 | 12.50 | +0.022 | 0.12 | 矿业 |
| imperial_railway | 帝国铁路公司 | 8.30 | -0.008 | 0.075 | 运输 |
| balkan_shipping | 巴尔干行船 | 15.60 | +0.005 | 0.14 | 运输 |
| military_industry | 军需工业集团 | 22.10 | 0.000 | 0.20 | 军工 |
| austro_bank_trust | 奥匈银行信托 | 31.40 | +0.014 | 0.09 | 金融 |
| oriental_trading | 东方贸易商行 | 9.75 | +0.011 | 0.15 | 贸易 |

### 价格约束

| 参数 | 值 |
|------|-----|
| 价格下限 | 1.0 |
| 价格上限 | 9,999.0 |
| 历史保留 | 12 季（3 年走势图） |

### 交易机制

- **买入**：以当前价格购买指定数量股票，更新 `avg_cost`（加权平均成本）
- **卖出**：以当前价格卖出指定数量股票，`avg_cost` 不变
- **科技加成**：`stock_boost_all` 效果对所有股票 mu +delta

> 事件→股价映射详见 [附录 §26](#26-附录事件股价映射完整表)。

---

## 11. 科技系统

### 基础参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 启动 AP 消耗 | 2 | |
| 研发费用 | 各科技独立 `cost` | 受通胀影响 |
| 研发周期 | 各科技独立 `turns` | |
| 科技顾问加成 | 研发周期 × (1 - bonus × 0.5) | |
| 影响力阈值加成 | 影响力 ≥ 200 时：-1 季 | |
| 奖励研发点数 | `bonus_points` 可加速当前研发 | |
| 研发速度加成 | `research_speed_bonus` 科技效果 | |

### 科技树（41 项科技，4 分支，8 个分叉点）

> 分叉科技使用 `excludes` 字段标记互斥。`requires` 字段支持管道语法 `"a|b"` 表示"需要 a 或 b"。

#### A 分支 — 矿业（10 项）

| ID | 名称 | 费用 | 周期 | 前置 | 互斥 | 效果 |
|----|------|------|------|------|------|------|
| a1_hand_drill | 手工钻机 | 150 | 2 | 无 | — | mine_output_base +1 |
| a2_steam_drill | 蒸汽钻机 | 300 | 3 | a1 | — | mine_output_base +2 |
| a3_electric_mine | 电气化矿井 | 500 | 4 | a2 | — | security_bonus +1, accident_reduction +0.02 |
| **a4a_ventilation** | 通风系统 | 400 | 3 | a3 | a4b | accident_reduction +0.03, worker_efficiency +0.1 |
| **a4b_blasting** | 爆破技术 | 400 | 3 | a3 | a4a | mine_output_mult +0.25 |
| a5_conveyor | 传送带系统 | 600 | 4 | a4a\|a4b | — | mine_output_base +2, worker_efficiency +0.15 |
| **a6a_hydraulic** | 液压采掘 | 700 | 4 | a5 | a6b | mine_output_mult +0.3, mine_slots +1 |
| **a6b_deep_shaft** | 深井开采 | 700 | 4 | a5 | a6a | mine_output_base +3, prospect_success +0.1 |
| a7_wartime_extraction | 战时紧急采掘 | 500 | 2 | a6a\|a6b | — | mine_output_mult +0.2（需 year ≥ 1940） |

> `a4a|a4b` 表示前置需要 a4a 或 a4b 中任意一个。

#### B 分支 — 经济（11 项）

| ID | 名称 | 费用 | 周期 | 前置 | 互斥 | 效果 |
|----|------|------|------|------|------|------|
| b1_bookkeeping | 簿记系统 | 200 | 2 | 无 | — | tax_reduction -0.01 |
| b2_accounting | 现代会计学 | 350 | 3 | b1 | — | tax_reduction -0.02 |
| b3_telegraph | 电报网络 | 450 | 3 | b2 | — | ap_bonus +1 |
| **b4a_trade_route** | 贸易路线 | 500 | 4 | b3 | b4b | trade_income +30 |
| **b4b_smuggling** | 走私网络 | 500 | 3 | b3 | b4a | trade_income +50（+ shadow_income 风险） |
| b5_finance_net | 金融网络 | 600 | 4 | b4a\|b4b | — | finance_network +40 |
| b6_stock_exchange | 证券交易所 | 700 | 4 | b5 | — | stock_boost_all +0.005 |
| **b7a_intl_trade** | 国际贸易 | 800 | 5 | b6 | b7b | trade_income +60, influence_gain +3 |
| **b7b_war_economy** | 战时经济 | 600 | 3 | b6 | b7a | trade_income +80（仅战时有效） |
| b8_central_banking | 中央银行 | 1000 | 5 | b7a\|b7b | — | tax_reduction -0.03, finance_network +60 |

#### C 分支 — 军事（10 项）

| ID | 名称 | 费用 | 周期 | 前置 | 互斥 | 效果 |
|----|------|------|------|------|------|------|
| c1_rifled_arms | 线膛步枪 | 250 | 2 | 无 | — | equipment_up +1 |
| c2_logistics | 后勤管理 | 350 | 3 | c1 | — | supply_reduction -0.2 |
| c3_machine_gun | 机枪阵地 | 500 | 4 | c2 | — | equipment_up +1, guard_power_bonus +0.1 |
| **c4a_fortification** | 防御工事 | 450 | 3 | c3 | c4b | security_bonus +2, guard_power_bonus +0.15 |
| **c4b_assault** | 突击战术 | 450 | 3 | c3 | c4a | guard_power_bonus +0.25, morale_bonus +5 |
| c5_motorized | 摩托化部队 | 600 | 4 | c4a\|c4b | — | equipment_up +1, supply_reduction -0.15 |
| **c6a_intelligence** | 军事情报 | 700 | 4 | c5 | c6b | security_bonus +1, research_speed +0.1 |
| **c6b_heavy_arms** | 重火力 | 700 | 4 | c5 | c6a | equipment_up +1, guard_power_bonus +0.2 |
| c7_elite_force | 精锐部队 | 800 | 4 | c6a\|c6b | — | guard_power_bonus +0.3, morale_bonus +10 |

#### D 分支 — 文化（10 项）

| ID | 名称 | 费用 | 周期 | 前置 | 互斥 | 效果 |
|----|------|------|------|------|------|------|
| d1_propaganda | 印刷宣传 | 200 | 2 | 无 | — | influence_gain +2 |
| d2_education | 基础教育 | 300 | 3 | d1 | — | research_speed +0.05, worker_efficiency +0.05 |
| d3_newspaper | 报业帝国 | 450 | 3 | d2 | — | influence_gain +3 |
| **d4a_nationalism** | 民族主义 | 400 | 3 | d3 | d4b | morale_bonus +8, influence_gain +2 |
| **d4b_internationalism** | 国际主义 | 400 | 3 | d3 | d4a | trade_income +20, hire_cost_reduction -0.1 |
| d5_radio | 广播电台 | 600 | 4 | d4a\|d4b | — | influence_gain +5, ap_bonus +1 |
| **d6a_university** | 大学教育 | 700 | 4 | d5 | d6b | research_speed +0.15, worker_efficiency +0.1 |
| **d6b_propaganda_machine** | 宣传机器 | 700 | 4 | d5 | d6a | influence_gain +8, morale_bonus +5 |
| d7_wartime_media | 战时媒体 | 500 | 2 | d6a\|d6b | — | influence_gain +5, morale_bonus +5（需 year ≥ 1940） |

### 科技效果类型一览

| 效果 ID | 说明 | 典型值 |
|---------|------|--------|
| mine_output_base | 矿山基础产出加法加成 | +1 ~ +3 |
| mine_output_mult | 矿山产出乘法加成 | +0.2 ~ +0.3 |
| security_bonus | 矿区安全等级加成 | +1 ~ +2 |
| accident_reduction | 事故概率降低 | -0.02 ~ -0.03 |
| worker_efficiency | 工人效率加成 | +0.05 ~ +0.15 |
| tax_reduction | 永久减税 | -0.01 ~ -0.03 |
| ap_bonus | AP 上限加成 | +1 |
| equipment_up | 装备等级提升 | +1 |
| supply_reduction | 补给消耗降低 | -0.15 ~ -0.20 |
| finance_network | 金融被动收入 | +40 ~ +60 |
| stock_boost_all | 所有股票 mu 加成 | +0.005 |
| influence_gain | 每季影响力增长 | +2 ~ +8 |
| morale_bonus | 护卫士气加成 | +5 ~ +10 |
| guard_power_bonus | 护卫战力加成 | +0.1 ~ +0.3 |
| research_speed | 研发速度加成 | +0.05 ~ +0.15 |
| trade_income | 贸易被动收入 | +20 ~ +80 |
| gold_price_bonus | 金价加成 | +x% |
| hire_cost_reduction | 招聘费折扣 | -0.1 |
| mine_slots | 矿山槽位增加 | +1 |
| prospect_success | 勘探成功率加成 | +0.1 |

---

## 12. 家族系统

### 基础参数

| 参数 | 值 |
|------|-----|
| 最大核心成员 | 6 人 |
| 培养新成员费用 | 200 现金 |
| 培养周期 | 10 季度 |

### 初始成员（3 人）

| ID | 名称 | 管理 | 谋略 | 魅力 | 学识 | 野心 | 隐藏特质 |
|----|------|------|------|------|------|------|----------|
| patriarch | 尼古拉·科瓦奇（家主） | 7 | 5 | 7 | 5 | 6 | 腐败 3, 忠诚 8, 激进 2 |
| eldest_son | 马尔科·科瓦奇（长子） | 4 | 8 | 4 | 3 | 8 | 腐败 2, 忠诚 6, 激进 7 |
| niece | 莉娜·科瓦奇（侄女） | 5 | 3 | 6 | 8 | 4 | 腐败 1, 忠诚 9, 激进 3 |

> 属性范围：1-10。隐藏特质（corruption、loyalty、radical）在特定事件中生效。

### 6 个岗位

| 岗位 ID | 名称 | 主属性 | 说明 |
|---------|------|--------|------|
| mine_director | 矿业总监 | 管理 | 影响矿山产出 |
| military_chief | 军务主管 | 谋略 | 影响士气衰减 |
| finance_director | 财务总监 | 管理 | 影响税务/财政 |
| culture_advisor | 文化顾问 | 魅力 | 影响影响力 |
| tech_advisor | 科技顾问 | 学识 | 影响研发速度 |
| diplomat | 外交总监 | 魅力 | 影响外交效果 |

### 岗位适配规则（`GetPositionFit()`）

| 主属性值 | 评级 | 加成系数 |
|----------|------|----------|
| ≥ 7 | 满配 (excellent) | +1.0 |
| 5-6 | 半配 (good) | +0.5 |
| < 5 | 差配 (poor) | -0.1 |
| 岗位空缺 | — | **-0.30** |

> 岗位加成直接影响：矿山产出（矿业总监）、士气衰减（军务主管）、研发速度（科技顾问）等。

### 家族培养（每季 Phase 8）

每季 `training_progress += 1`，达到 `training_duration(10)` 后新成员加入。

---

## 13. 地区与地图系统

### 3 个初始地区

| ID | 名称 | 类型 | 玩家控制度 | 治安 | 基建 | 人口 |
|----|------|------|-----------|------|------|------|
| mine_district | 巴科维奇矿区 | mine | **80** | 3 | 1 | — |
| industrial_town | 泽尼察工业区 | industrial | **20** | 4 | 2 | — |
| capital_city | 萨拉热窝 | capital | **5** | 4 | 3 | 50,000 |

### 地区资源储量

| 属性 | 矿区 | 工业区 | 首都 |
|------|------|--------|------|
| 黄金储量 (gold_reserve) | 500 | 0 | 0 |
| 白银储量 (silver_reserve) | 1,200 | 0 | 0 |
| 煤炭储量 (coal_reserve) | 0 | 2,500 | 0 |
| 文化值 | 0 | 5 | 20 |

### 政治渗透操作

| 参数 | 值 |
|------|-----|
| AP 消耗 | 2 |
| 基础控制增益 | +8% |
| 控制度 ≥ 60% 时 | 增益降为 +5%（递减） |
| 控制度 ≥ 80% 时 | 增益降为 +3%（进一步递减） |
| 影响力增益 | +2 / 次 |
| AI 存在减少 | 等比例减少（按各 AI 占比分摊） |

---

## 14. AI 势力系统

### 2 个 AI 势力

| 参数 | 米洛舍维奇家族 (local_clan) | 维也纳矿业公司 (foreign_capital) |
|------|---------------------------|-------------------------------|
| 初始现金 | 800 | 2,000 |
| 增长率 / 季 | 5% | 8% |
| 现金上限 | 8,000 | 12,000 |
| 攻击倾向 | 0.3 | 0.1 |
| 扩张阈值 | 600 | 1,000 |
| 初始态度 | 0 | +10 |
| 初始势力值 | 30 | 40 |
| 战时撤资阈值 | — | 0.6 |

> 现金上限 (`cash_cap`) 防止 AI 复利爆炸增长。

### AI 每季行为

1. **资产增长**：`cash += floor(cash × growth_rate)`（受情报渗透 debuff 影响，受 `cash_cap` 限制）
2. **势力增长**：和平时每季 **+2**，战时每季 **+3**；现金超过扩张阈值时额外 +1
3. **AI 花费行为**：满足条件时主动花费（见下表）
4. **态度变动**：负向/正向触发器（见下方）
5. **协议保护**：签约期内不敌对，态度不低于 10
6. **外资战时撤资**：战时有概率撤走 15% 现金，势力 -3

### AI 花费行为

| 行为 | 花费 | 效果 | 触发条件 | 概率 |
|------|------|------|----------|------|
| 雇佣兵 | 500 | power +5 | cash > 扩张阈值 且 power < 90 | 25% |
| 地区压制 | 400 | 玩家控制度 -3 | attitude < -30 | 20% |
| 经济制裁 | 600 | 玩家收入 -10%（3季） | 仅外资，attitude < -40 | 15% |
| 通胀操纵 | 800 | 额外通胀漂移 +1.2%/季（4季） | 仅外资，attitude < -50 | 12% |
| 矿价波动 | 700 | 金银价格 -15%（3季） | 仅外资，attitude < -35 | 15% |

### 态度系统

**负向触发器**：

| 触发条件 | 态度变化 |
|----------|----------|
| 玩家现金 > AI 现金 × 1.5 | -3 / 季 |
| 玩家护卫 > 20 且 AI power < 50 | -2 / 季 |
| 玩家矿山 ≥ 5 座 | -1 / 季 |
| AI power ≥ 60 且 attitude > -50 | -1 / 季 |

**正向触发器**：

| 触发条件 | 态度变化 |
|----------|----------|
| 每季基线 | +1（自然回暖） |
| 玩家现金 < 500 | +2 |
| 玩家矿山 < 2 座 | +1 |
| AI power < 30 | +1 |

> 态度范围 [-100, +100]，正向上限 (`attitude_cap`) = 60。

### 大国博弈联动

AI 代理势力（`proxy`）与大国博弈系统中的强国关联：
- `local_clan.proxy` → 与 Serbia 势力关联
- `foreign_capital.proxy` → 与 Austria-Hungary 势力关联

代理强国的军事/经济实力变化会影响本地 AI 的 power 值。

---

## 15. 战斗系统

### 玩家战力计算（`Combat.PlayerPower()`）

```
PlayerPower = guards × guard_base_power(1.0)
            × max(0.3, morale × morale_multiplier(0.01))
            × (1 + (equipment - 1) × equipment_bonus(0.15))
            × (1 + chiefBonus)
            × (1 + guard_power_tech_bonus)
```

| 因素 | 说明 |
|------|------|
| guards | 护卫数量 |
| morale | 士气 × 0.01（最低 0.3） |
| equipment | 装备等级 1-5，每级 +15% |
| chiefBonus | 军务主管岗位加成 |
| guard_power_tech_bonus | 科技带来的战力加成 |

### AI 战力（`Combat.FactionPowerInRegion()`）

```
FactionPower = faction.power × base_faction_power(1.0) × (1 + presence / 200)
```

> AI 在某地区的存在度 (`presence`) 会放大其战力。

### 冲突地区选择（`Combat.PickConflictRegion()`）

基于评分选择冲突爆发地区：
- AI 存在度高的地区优先
- 玩家控制度高但 AI 也有存在的地区优先

### 战斗判定

- 双方各 ×(0.8 + random × 0.4) 随机因子（±20% 波动）
- 比较 pRoll vs aRoll，大者胜

### 战斗结果（`Combat.ApplyResult()`）

| 结果 | 玩家胜 | 玩家败 |
|------|--------|--------|
| 现金 | +AI 现金 × 25% | -玩家现金 × 10% |
| 护卫 | 无损失 | -30% 护卫 |
| 士气 | +10 | -18 |
| AI 势力 | power -8, attitude -10 | power +5 |
| 地图影响 | 冲突地区: 控制度+3, AI存在度-8 | 冲突地区: 控制度-5, AI存在度+7, 治安-1 |
| 胜场计数 | `battle_wins_unclaimed +1` | AI 累计 +1 |

> 军事胜利点在每季回合结算 Phase 3 中以 `min(unclaimed, 3)` 计入。

### AI 主动进攻条件

| 条件 | 阈值 |
|------|------|
| AI 态度 | ≤ -20 |
| AI 势力值 | ≥ 40 |
| 每季概率 | `min(0.85, 0.35 × (1 + aggression))` |
| 协议保护 | 保护期内不进攻 |

---

## 16. 事件系统

### 概述

事件分为三类：**固定历史事件**（绑定特定年份/季度）、**随机事件**（概率触发，有冷却）、**分支事件**（历史分叉点，见 §17）。

同一季度可同时触发固定事件和随机事件。

### 早期阻尼

1904-1905 年间（前 8 个季度），随机事件概率降至 **40%**，降低早期压力。

### 干旱概率递增

连续 2-3 个季度无随机事件时，下一季度的随机事件概率乘以递增因子（鼓励"旱后必涝"）。

### 固定历史事件（35+）

#### 第一章：铜版帝国（1904-1913）

| 事件 ID | 触发时间 | 名称 | 关键效果 |
|---------|----------|------|----------|
| family_founding_1904 | 1904 Q1 | 金矿矿权 | 初始选择影响开局方向 |
| first_miners_1905 | 1905 Q1 | 第一批矿工 | 工人/资金相关 |
| railway_expansion_1906 | 1906 Q2 | 铁路扩建 | 运输/基建相关 |
| imperial_control_1908 | 1908 Q4 | 帝国管制令 | 税负/合法性，股市影响 |
| annexation_crisis_1909 | 1909 Q2 | 波黑危机 | 地缘政治紧张 |
| balkan_wars_1912 | 1912 Q2 | 巴尔干战云 | 军需/物资，股市大幅波动 |
| modernization_1910 | 1910 Q3 | 现代化浪潮 | 科技/发展 |

#### 第二章：战报红章（1914-1918）

| 事件 ID | 触发时间 | 名称 | 关键效果 |
|---------|----------|------|----------|
| sarajevo_shots_1914 | 1914 Q2 | 萨拉热窝枪声 | 战争开始，通胀加速，股市剧烈波动 |
| war_economy_1915 | 1915 Q1 | 战时经济体制 | 军需/管制 |
| eastern_front_1916 | 1916 Q2 | 东线攻势 | 军事/外交 |
| revolution_echoes_1917 | 1917 Q3 | 革命回声 | 社会/政治动荡 |
| empire_collapse_1918 | 1918 Q4 | 帝国崩解 | 秩序重建，所有股票受冲击 |

#### 第三章：黑金工业（1919-1940）

| 事件 ID | 触发时间 | 名称 | 关键效果 |
|---------|----------|------|----------|
| new_kingdom_1920 | 1920 Q1 | 新王国成立 | 政治重组 |
| roaring_twenties_1924 | 1924 Q2 | 繁荣年代 | 经济繁荣 |
| great_depression_1929 | 1929 Q4 | 大萧条 | 通缩、资产暴跌（asset_price_mod -0.60） |
| recovery_signs_1932 | 1932 Q2 | 经济复苏 | 温和回暖 |
| fascist_tide_1933 | 1933 Q3 | 法西斯浪潮 | 政治紧张 |
| king_assassination_1934 | 1934 Q4 | 国王遇刺 | 政治危机 |
| german_rearmament_1936 | 1936 Q2 | 德国重整军备 | 军工需求上升 |
| spanish_civil_war_1937 | 1937 Q1 | 西班牙内战 | 国际局势紧张 |
| munich_agreement_1938 | 1938 Q3 | 慕尼黑协定 | 绥靖政策 |
| wwii_outbreak_1939 | 1939 Q3 | 二战爆发 | 战争预警 |

#### 第四章：战时灰幕（1941-1945）

| 事件 ID | 触发时间 | 名称 | 关键效果 |
|---------|----------|------|----------|
| axis_ultimatum_1941 | 1941 Q1 | 轴心最后通牒 | 战争直接影响 |
| old_order_collapse_1941 | 1941 Q3 | 旧秩序崩溃 | 政权更迭 |
| partisan_warfare_1942 | 1942 Q2 | 游击战争 | 军事/安全 |
| italy_surrender_1943 | 1943 Q3 | 意大利投降 | 战局转折 |
| allied_bombing_1944 | 1944 Q1 | 盟军轰炸 | 破坏/损失 |
| new_regime_1945 | 1945 Q2 | 新政权建立 | 政治重组 |

#### 第五章：战后余烬（1946-1955）

| 事件 ID | 触发时间 | 名称 | 关键效果 |
|---------|----------|------|----------|
| land_reform_1946 | 1946 Q2 | 土地改革 | 经济重组 |
| five_year_plan_1947 | 1947 Q1 | 五年计划 | 工业化 |
| tito_stalin_split_1948 | 1948 Q2 | 铁托-斯大林决裂 | 地缘政治重大转折 |
| western_aid_1949 | 1949 Q3 | 西方援助 | 经济注入 |
| korean_war_boom_1951 | 1951 Q1 | 朝鲜战争景气 | 军工需求 |
| self_management_1952 | 1952 Q2 | 自治管理 | 政治改革 |
| trieste_resolution_1954 | 1954 Q1 | 的里雅斯特解决 | 领土/外交 |
| family_legacy_1955 | 1955 Q3 | 家族遗产 | 终局总结 |

### 随机事件模板（15 种）

| 事件 ID | 名称 | 触发条件 | 概率/季 | 冷却 |
|---------|------|----------|---------|------|
| mine_accident | 矿难事故 | 有矿山 + 治安 ≤ 3 | 15% | 4 季 |
| worker_strike | 工人罢工 | 工人 ≥ 15 | 12% | 6 季 |
| foreign_investors | 外资考察团 | 年份 ≥ 1906 + 基建 ≥ 2 | 10% | 8 季 |
| ore_vein_discovery | 矿脉发现 | 有矿山 | 8% | 8 季 |
| local_pressure | 地方势力施压 | — | 12% | 4 季 |
| gold_price_surge | 金价飙升 | — | 8% | 6 季 |
| smuggling_route | 走私路线 | 治安 ≤ 4 | 10% | 6 季 |
| disease_outbreak | 瘟疫爆发 | 工人 ≥ 10 | 8% | 8 季 |
| brain_drain | 人才外流 | 年份 ≥ 1910 | 6% | 8 季 |
| natural_disaster | 自然灾害 | — | 8% | 6 季 |
| commodity_boom | 大宗商品繁荣 | — | 10% | 6 季 |
| currency_crisis | 货币危机 | 年份 ≥ 1920 | 8% | 8 季 |
| espionage_scandal | 间谍丑闻 | — | 6% | 8 季 |
| drought_famine | 旱灾饥荒 | — | 8% | 6 季 |
| bandit_raid | 土匪袭击 | 治安 ≤ 3 | 12% | 4 季 |
| railway_shutdown | 铁路封锁 | — | 10% | 6 季 |

> 部分随机事件有 `chance_modifier`：如 `transport_risk` 修正器会增加 `bandit_raid` 和 `railway_shutdown` 的触发概率。

### 事件修正器系统

事件选项可产生持续修正器 (`modifiers`)，格式：`{ target, value, duration }`

- `duration = 0` → 永久生效
- `duration > 0` → 倒计时消耗，每季 -1，到期移除

**已知修正器目标（30+ 种）**：

| 类别 | 修正器 target |
|------|--------------|
| 经济 | `income_mod`, `tax_reduction`, `shadow_income`, `trade_income`, `finance_network` |
| 资产 | `asset_price_mod`, `gold_price_mod`, `silver_price_mod`, `coal_price_mod` |
| 劳动力 | `worker_cost_multiplier`, `hire_cost_multiplier`, `worker_efficiency_bonus` |
| 矿业 | `mine_output`, `mine_output_base_bonus`, `mine_output_mult_bonus` |
| 军事 | `guard_power_bonus`, `morale_bonus`, `supply_discount` |
| 通胀 | `inflation_drift`, `inflation_delta` |
| 政治 | `legitimacy`, `political_standing`, `public_support`, `corruption_risk`, `risk` |
| 运输 | `transport_risk` |
| 控制 | `foreign_control`, `civilian_demand` |
| 监管 | `regulation_pressure` |

---

## 17. 分支事件系统

分支事件是影响历史走向的关键决策点，玩家的选择会设置 flag（`_branch_*`），这些 flag 影响后续事件、大国博弈的征服逻辑、以及战后清算结果。

### 5 个分支节点 + 战后清算

#### 分支 1：萨拉热窝刺杀（1914 Q2）

| 选项 | 效果 | Flag |
|------|------|------|
| 报告当局 | 合作分数 -10，安全 +1 | — |
| 协助刺杀 | 合作分数 +15，军事 +5 | — |
| 置身事外 | 无直接影响 | — |
| 调解冲突 | **5% 概率阻止一战**（蝴蝶效应） | `_branch_war_prevented` |

> 若触发蝴蝶效应（5%），第二章战争事件将被跳过，历史走向完全改变。

#### 分支 2：奥匈帝国命运（1918 Q2）

| 选项 | 效果 | Flag |
|------|------|------|
| 支持联邦化 | 合作分数 -5，外交 +10 | `_branch_ah_federalized` |
| 支持南斯拉夫 | 合作分数 +5，影响力 +15 | `_branch_yugo_neutral` |
| 趁机扩张 | 现金 +500，合作分数 +10 | — |

#### 分支 3：纳粹扩张（1938 Q1）

| 选项 | 效果 | Flag |
|------|------|------|
| 合作 | 现金 +800，合作分数 +20 | `_branch_nazi_collaborator` |
| 筑防 | 安全 +2，合作分数 -15 | `_branch_fortified` |
| 中立 | 无直接影响 | — |

#### 分支 4：解放方式（1944 Q2）

| 选项 | 效果 | Flag |
|------|------|------|
| 等待解放 | 合作分数 -5 | `_branch_war_delayed` |
| 自行起义 | 军事 +10，损失风险 | `_branch_self_liberation` |
| 引入西方盟军 | 外交 +15 | `_branch_war_accelerated` |

#### 分支 5：铁托的抉择（1948 Q2）

| 选项 | 效果 | Flag |
|------|------|------|
| 支持铁托 | 影响力 +20，合作分数 -10 | — |
| 为苏联当间谍 | 现金 +1000，**10% 概率铁托留在苏联阵营**（蝴蝶效应） | — |
| 推动西方路线 | 贸易 +20，科技加速 | — |

### 战后清算（1946 Q1）

基于整场游戏的 `collaboration_score`（合作分数），范围约 -100 ~ +100：

| 合作分数 | 评价 | 后果 |
|----------|------|------|
| ≤ -30 | 人民英雄 | 大量正面加成 |
| -30 ~ -10 | 抵抗者 | 温和正面 |
| -10 ~ +10 | 普通市民 | 中性 |
| +10 ~ +30 | 灰色名单 | 温和惩罚 |
| ≥ +30 | 合作者 | 严厉惩罚 |

> 合作分数在整个游戏过程中通过分支选择和事件选项累积。

---

## 18. 大国博弈系统

大国博弈是一个覆盖整个欧洲的地缘政治模拟系统，在回合结算的 Phase 6.7 执行。

### 17 个国家/地区

#### 大国（tier = "major"）

| ID | 名称 | 初始稳定性 | 说明 |
|----|------|-----------|------|
| britain | 大不列颠 | 80 | |
| france | 法兰西 | 70 | |
| germany | 德意志 | 75 | |
| russia | 俄罗斯 | 60 | |
| austria_hungary | 奥匈帝国 | 55 | |
| ottoman | 奥斯曼 | 45 | |

#### 中等国家（tier = "medium"）

| ID | 名称 | 初始稳定性 |
|----|------|-----------|
| italy | 意大利 | 65 |

#### 小国（tier = "minor"）

| ID | 名称 | 初始稳定性 | 特殊状态 |
|----|------|-----------|----------|
| serbia | 塞尔维亚 | 50 | 本地 AI 代理 |
| romania | 罗马尼亚 | 55 | |
| bulgaria | 保加利亚 | 50 | |
| greece | 希腊 | 55 | |
| montenegro | 黑山 | 45 | |
| lowlands | 低地国家 | 70 | |
| denmark | 丹麦 | 75 | |
| iberia | 伊比利亚 | 65 | |

#### 中立国（tier = "neutral"）

| ID | 名称 | 初始稳定性 |
|----|------|-----------|
| scandinavia | 斯堪的纳维亚 | 85 |
| finland | 芬兰 | 60（俄罗斯主权下，抵抗 30） |
| switzerland | 瑞士 | 95 |

### 核心机制

#### 每季处理流程（`GrandPowers.Tick()`）

1. **激活检查**（CheckActivations）：根据年份激活/解散特定势力
2. **历史漂移**（ApplyDrift）：军事/经济向历史基线靠拢
3. **势力更新**（UpdateFactions）：联盟/敌对关系
4. **继承处理**（ProcessSuccessions）：帝国解体、国家新生、合并
5. **征服执行**（ProcessConquests）：占领、解放、吞并
6. **抵抗增长**（GrowResistance）：被占领国家 +2/季
7. **本地 AI 联动**（LinkLocalAI）：代理势力影响本地 AI

#### 抵抗系统

| 参数 | 值 |
|------|-----|
| 每季抵抗增长 | +2（受分支 flag 修正） |
| 自动解放阈值 | 95（抵抗 ≥ 95 时自动解放） |

#### 分支 Flag 对征服的影响

| Flag | 效果 |
|------|------|
| `_branch_war_accelerated` | 加速征服进程 |
| `_branch_war_delayed` | 延缓征服进程 |
| `_branch_war_prevented` | 阻止特定征服 |
| `_branch_ah_federalized` | 奥匈帝国联邦化（不解体） |
| `_branch_yugo_neutral` | 南斯拉夫保持中立 |
| `_branch_self_liberation` | 自主解放（抵抗增长加速） |
| `_branch_nazi_collaborator` | 纳粹合作者（特定征服不受抵抗） |
| `_branch_fortified` | 防御工事（抵抗增长加速） |

---

## 19. 情报/外交/交易行动

### 情报行动

| 行动 | AP | 现金 | 效果 |
|------|-----|------|------|
| 侦查 (scout) | 1 | 80 | 获取 AI 势力信息 |
| 渗透 (infiltrate) | 2 | 300 | AI 增长率 -4%，持续 4 季 |
| 贿赂 (bribe) | 2 | 400 | AI 态度 +12 |

### 外交行动

| 行动 | AP | 现金 | 前置条件 | 效果 |
|------|-----|------|----------|------|
| 赠礼 (gift) | 1 | 200 | 无 | AI 态度 +6 |
| 缔约 (treaty) | 2 | 500 | AI 态度 ≥ 20 | AI 态度 +15，保护 8 季 |
| 敌对宣言 (hostile) | 1 | 0 | 无 | AI 态度 -35 |

### 资产交易

| 行动 | AP | 现金 | 效果 |
|------|-----|------|------|
| 开新矿 (new_mine) | 2 | 1,200 | 新矿山（储量 600） |
| 出售矿山 (sell_mine) | 2 | +500/等级 | 出售获利 |
| 突袭 AI (raid_ai) | 2 | 400 | AI 失去 200 现金 + 8 势力 |

---

## 20. 影响力系统

影响力 (Influence) 是地区级别的战略资源，需要持续投入维护。

### 基础参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 自然衰减 | -1 / 季（Phase 4.5） | 除非本季执行了文化行动 |
| 来源：科技 | 印刷宣传 +2, 报业 +3, 广播 +5, 宣传机器 +8 等 | 被动增益 |
| 来源：政治渗透 | +2 / 次 | 行动增益 |

### 影响力阈值被动效果（`INFLUENCE.thresholds`）

| 阈值 | 名称 | 效果 |
|------|------|------|
| 30 | 地方认可 | 地区安全 +1 |
| 70 | 舆论优势 | 招募费 -10% |
| 120 | 政治联盟 | AP 上限 +1 |
| 200 | 文化霸权 | 科技研发 -1 季 |
| 300 | 不朽影响力 | 经济/军事双线各 **+5/季** |

### 影响力消费场景

| 行动 | 消耗影响力 |
|------|-----------|
| 签订协议 | 30 |
| 收买 AI | 15 |
| 政治渗透 | 20 |

---

## 21. 监管压力系统

监管压力 (`regulation_pressure`) 是一个累积型风险指标，反映当局对玩家灰色经济活动的关注程度。

### 累积来源

| 来源 | 增量 |
|------|------|
| 影子收入 (`shadow_income`) | +2 / 季 |
| 腐败风险修正 (`corruption_risk`) | 按修正值累加 |
| 走私路线科技/事件 | 按事件效果累加 |
| 合法性低 (`legitimacy` < 0) | 按修正值累加 |

### 触发机制（Phase 4.5）

| 条件 | 效果 |
|------|------|
| regulation_pressure ≥ 50 | 有概率触发监管检查：罚没现金 3% |
| 持续高压 | 压力值不会自动消退，需要合法性/政治地位提升来缓解 |

---

## 22. 胜利条件判定

### 三种胜利方式

| 方式 | 条件 | 最早生效年份 |
|------|------|-------------|
| **经济绝对胜利** | 经济胜利点 ≥ 1600 + 快照验证 | 1930 |
| **军事绝对胜利** | 军事胜利点 ≥ 2000 + 快照验证 | 1925 |
| **相对领先胜利** | 领先 AI 达到一定幅度 | 1945 |

### 经济胜利点 — 每季结算公式（Phase 3）

```lua
ecoDelta = floor(cash / 2000)
         + floor(gold × 0.5)
         + floor(totalControl / 15)
         + floor(totalInfluence / 50)

-- 战时修正：
ecoDelta = floor(ecoDelta × 0.6)

-- 影响力阈值加成：
if totalInfluence >= 300 then ecoDelta += 5 end
```

> **章节门控**：经济线到 **1930 年** 后才开始结算。

### 经济胜利快照验证（`CheckEconomicSnapshot()`）

达到 1600 点阈值瞬间，必须同时满足：

| 条件 | 最低值 |
|------|--------|
| 现金 | ≥ 10,000 |
| 黄金 | ≥ 20 |
| 总控制度 | ≥ 80 |

### 军事胜利点 — 每季结算公式

```lua
milDelta = floor(guards × 0.3)
         + floor(morale / 25)
         + floor(totalControl / 12)
         + min(battleWinsUnclaimed, 3)

-- 战时修正：
milDelta = floor(milDelta × 1.25)

-- 影响力阈值加成：
if totalInfluence >= 300 then milDelta += 5 end
```

> **章节门控**：军事线到 **1925 年** 后才开始结算。

### 军事胜利快照验证（`CheckMilitarySnapshot()`）

| 条件 | 最低值 |
|------|--------|
| 护卫 | ≥ 25 |
| 士气 | ≥ 50 |
| 总控制度 | ≥ 100 |

### 相对领先胜利（`GetVictoryStanding()`）

1945 年后，如果玩家领先 AI 足够多，可宣布胜利：

| 参数 | 值 |
|------|-----|
| 最早宣布年份 (`min_claim_year`) | 1945 |
| 经济领先幅度 | 800 点 |
| 军事领先幅度 | 150 点 |
| 全面优势幅度 | 900 点 |
| AI 军事折算系数 | 0.20（AI 势力值 × 0.20 = AI 军事分） |
| 全面优势需正增长 | 是 |

### AI 胜利点同步

AI 也在每季累积胜利点（基于 AI 势力值、现金等），用于相对领先比较。

### 游戏结束条件

| 条件 | 类型 |
|------|------|
| 经济胜利点 ≥ 1600 + 快照验证 | 经济胜利 |
| 军事胜利点 ≥ 2000 + 快照验证 | 军事胜利 |
| 相对领先达标（≥1945年） | 宣布胜利（可继续游玩） |
| 时间超过 1955 Q4 | 超时结束 |
| 破产（连续违约 4 季 / 净资产为负 4 季） | 家族破产 |

---

## 23. 回合结算完整流程

`TurnEngine.EndTurn(state)` 共 15+ 个阶段：

| 阶段 | 名称 | 关键操作 |
|------|------|----------|
| 0 | 通胀推进 | `inflation_factor × (1 + drift)`，drift = 基础漂移 + 事件修正，clamp [0.45, 20.0] |
| 1 | 经济结算 | `Economy.Settle()`：产矿（金+银+煤）→ 出售 → 地区被动收入 → 工资 → 税收 → AI惩罚 → 运输风险 → 破产检查 |
| 1.5 | 股市更新 | `StockEngine.UpdateAll()`：GBM 推进 + 事件修正消耗（remaining -1） |
| 1.6 | 贷款结算 | 杠杆利率 → 付息 → 强制抵押清算 → 到期还本/展期 → 破产检测 |
| 1.7 | 科技推进 | `Tech.Tick()`：进度 +1（科技顾问可能额外 +1），bonus_points 消耗 |
| 2 | 事件检查 | 冷却推进 → 固定事件触发 → 随机事件触发（早期阻尼 + 旱后必涝）→ 入队 |
| 3 | **胜利点结算** | 经济/军事胜利点累加 + 章节门控 + 战时修正 + AI 同步累积 |
| 4 | 修正器推进 | 持续效果 duration -1，到期移除 |
| 4.5 | **影响力衰减** | 所有地区 influence -1/季 |
| 4.5+ | **监管检查** | `regulation_pressure ≥ 50` 时有概率罚没现金 3% |
| 5 | 士气衰减 | 护卫士气 -2（军务主管减缓） |
| 6 | AI 更新 | 资产增长(cash_cap) → 势力增长(+2/+3) → AI花费行为 → 态度触发器 → 外资撤退 |
| 6.2 | 外资控制度修正 | 根据 foreign_capital 地区存在度计算 `foreign_control` 修正器 |
| 6.5 | AI 战斗 | `Combat.ResolveAIActions()`：满足条件时 AI 进攻 |
| 6.7 | **大国博弈** | `GrandPowers.Tick()`：激活 → 漂移 → 继承 → 征服 → 抵抗增长 → 本地AI联动 |
| 6.8 | **分支事件** | `BranchEvents.CheckBranchEvents()`：检查历史分支节点 → 入队 |
| 7 | 工人士气 | 工资检查 → 士气变动 → 罢工警告 |
| 8 | 家族培养 | 培养进度 +1 → 完成则新成员加入 |
| 8.5 | **勘探进度** | 勘探 progress +1 → 到达 `prospect_turns(2)` 时判定成功/失败 → 新矿/退费 |
| 9 | 推进季度 | year/quarter 推进 → AP 重置 → 日志记录 |

---

## 24. 幸运事件系统（广告激励）

玩家观看广告后可触发幸运事件，获得现金奖励。

### 奖励档位

| 档位 | 基础金额 | 初始权重 |
|------|---------|---------|
| 小额意外之财 | 666 | 50 |
| 商队赠礼 | 888 | 30 |
| 矿脉意外发现 | 1,200 | 12 |
| 贵族赞助 | 1,600 | 5 |
| 中了头彩！ | 2,000 | 3 |

> 实际奖励 = `base × inflation_factor`

### 概率递减机制

| 参数 | 值 |
|------|-----|
| 衰减因子 | 0.7 |
| 最低衰减 | 15% |
| 每季上限 | 3 次 |

---

## 25. 破产救济系统

当玩家触发破产条件时，可获得一次性救济：

| 参数 | 值 | 说明 |
|------|-----|------|
| 救济现金 | `BANKRUPTCY_RESCUE.cash` | 视 balance.lua 定义 |
| 触发条件 | 连续违约 4 季 或 净资产为负 4 季 | |
| 次数限制 | 有限次数 | 防止无限救济 |

---

## 26. 附录：事件→股价映射完整表

> 数据来源：`scripts/data/event_market_effects.lua`

### 固定历史事件影响

| 事件 | 股票 | delta_mu | 持续(季) |
|------|------|----------|----------|
| family_founding_1904 | sarajevo_mining | +0.04 | 3 |
| first_miners_1905 | sarajevo_mining | +0.03 | 2 |
| railway_expansion_1906 | imperial_railway | +0.06 | 4 |
| railway_expansion_1906 | sarajevo_mining | +0.02 | 3 |
| imperial_control_1908 | sarajevo_mining | -0.05 | 4 |
| imperial_control_1908 | austro_bank_trust | +0.03 | 4 |
| annexation_crisis_1909 | military_industry | +0.06 | 3 |
| annexation_crisis_1909 | balkan_shipping | -0.04 | 3 |
| modernization_1910 | sarajevo_mining | +0.03 | 3 |
| modernization_1910 | imperial_railway | +0.04 | 4 |
| balkan_wars_1912 | military_industry | +0.12 | 4 |
| balkan_wars_1912 | imperial_railway | +0.04 | 4 |
| balkan_wars_1912 | balkan_shipping | -0.08 | 4 |
| sarajevo_shots_1914 | military_industry | **+0.30** | 6 |
| sarajevo_shots_1914 | imperial_railway | +0.08 | 6 |
| sarajevo_shots_1914 | balkan_shipping | -0.22 | 6 |
| sarajevo_shots_1914 | austro_bank_trust | -0.12 | 6 |
| sarajevo_shots_1914 | oriental_trading | -0.10 | 4 |
| war_economy_1915 | military_industry | +0.15 | 4 |
| war_economy_1915 | sarajevo_mining | +0.05 | 3 |
| eastern_front_1916 | military_industry | +0.08 | 3 |
| eastern_front_1916 | imperial_railway | -0.06 | 3 |
| revolution_echoes_1917 | austro_bank_trust | -0.08 | 4 |
| revolution_echoes_1917 | oriental_trading | -0.05 | 3 |
| empire_collapse_1918 | military_industry | -0.18 | 4 |
| empire_collapse_1918 | austro_bank_trust | **-0.20** | 6 |
| empire_collapse_1918 | imperial_railway | -0.10 | 4 |
| empire_collapse_1918 | oriental_trading | -0.08 | 4 |
| empire_collapse_1918 | sarajevo_mining | -0.06 | 4 |
| new_kingdom_1920 | sarajevo_mining | +0.04 | 3 |
| new_kingdom_1920 | austro_bank_trust | +0.03 | 3 |
| roaring_twenties_1924 | 全部 6 支股票 | +0.04~+0.08 | 4-6 |
| great_depression_1929 | 全部 6 支股票 | **-0.12~-0.25** | 6-8 |
| recovery_signs_1932 | 全部 6 支股票 | +0.03~+0.06 | 3-4 |
| fascist_tide_1933 | military_industry | +0.08 | 4 |
| german_rearmament_1936 | military_industry | +0.10 | 4 |
| wwii_outbreak_1939 | military_industry | +0.20 | 6 |
| wwii_outbreak_1939 | balkan_shipping | -0.15 | 6 |
| tito_stalin_split_1948 | 全部股票 | ±0.05~0.10 | 4 |
| korean_war_boom_1951 | military_industry | +0.12 | 4 |
| korean_war_boom_1951 | oriental_trading | +0.08 | 3 |

### 随机事件影响

| 事件 | 股票 | delta_mu | 持续(季) |
|------|------|----------|----------|
| mine_accident | sarajevo_mining | -0.15 | 2 |
| mine_accident | military_industry | +0.04 | 2 |
| worker_strike | sarajevo_mining | -0.10 | 2 |
| worker_strike | imperial_railway | -0.05 | 2 |
| foreign_investors | sarajevo_mining | +0.06 | 3 |
| foreign_investors | austro_bank_trust | +0.05 | 3 |
| ore_vein_discovery | sarajevo_mining | +0.10 | 3 |
| gold_price_surge | sarajevo_mining | +0.08 | 2 |
| gold_price_surge | oriental_trading | +0.04 | 2 |
| natural_disaster | imperial_railway | -0.08 | 2 |
| natural_disaster | balkan_shipping | -0.06 | 2 |
| commodity_boom | oriental_trading | +0.10 | 3 |
| commodity_boom | balkan_shipping | +0.06 | 3 |
| currency_crisis | austro_bank_trust | -0.12 | 4 |
| currency_crisis | oriental_trading | -0.08 | 3 |
| bandit_raid | imperial_railway | -0.06 | 2 |
| railway_shutdown | imperial_railway | -0.10 | 3 |
| railway_shutdown | balkan_shipping | +0.05 | 2 |

---

## 27. 胜利条件可达性分析（详细计算）

> 本节对经济胜利（1600 点）和军事胜利（2000 点）进行严格的数学分析，
> 计算在不同游戏阶段、不同玩家发展水平下的每季增量和达标时间线。

### 27.1 时间窗口概览

| 胜利类型 | 门控年份 | 可用季度 (至1955Q4) | 阈值 |
|---------|---------|-------------------|----- |
| 经济胜利 | 1930 | **104 季**（1930Q1-1955Q4） | 1600 |
| 军事胜利 | 1925 | **124 季**（1925Q1-1955Q4） | 2000 |
| 相对领先 | 1945 | **44 季**（1945Q1-1955Q4） | 领先幅度 |

### 27.2 战争时期（影响 war_mod）

根据事件数据，战争期间 `at_war = true`：

| 战争 | 开始 | 结束 | 持续 |
|------|------|------|------|
| 一战 | 1914 Q2~Q3 (萨拉热窝事件) | 1918 Q4 (帝国崩解) | ~18 季 |
| 二战 | 1941 Q2 (德军入侵) | 1945 Q2 (新政权建立) | ~16 季 |

**对胜利点的影响**：
- 经济线：战时 ×0.6（大幅减速）
- 军事线：战时 ×1.25（加速）

---

### 27.3 经济胜利详细分析

#### 每季增量公式

```
ecoDelta = floor(cash/2000) + floor(gold×0.5) + floor(totalControl/15) + floor(totalInfluence/50)
战时: ecoDelta = floor(ecoDelta × 0.6)
影响力≥300: ecoDelta += 5
```

#### 各分量数值范围分析

**① 现金分量 `floor(cash/2000)`**

| 游戏阶段 | 典型现金范围 | 分量值 |
|---------|------------|--------|
| 早期 (1904-1915) | 500-3,000 | 0-1 |
| 中期 (1920-1930) | 3,000-8,000 | 1-4 |
| 成熟期 (1930-1940) | 5,000-15,000 | 2-7 |
| 晚期 (1940-1955) | 8,000-25,000+ | 4-12 |

> 注意：通胀使名义现金不断膨胀（和平 +0.6%/季，战时 +12%/季），但税率 5%-12% 和各种支出也在消耗。
> 现金高度依赖玩家策略：黄金自动出售开关、矿山等级、工人数量、科技等。

**② 黄金分量 `floor(gold×0.5)`**

| 策略 | 典型黄金存量 | 分量值 |
|------|------------|--------|
| 自动出售（不囤积） | 0-5 | 0-2 |
| 适度囤积 | 20-40 | 10-20 |
| 极端囤积 | 50-80+ | 25-40 |

> 黄金囤积是经济胜利的"秘密武器"——金价 ×0.5 乘数很高。但囤积黄金意味着放弃现金收入（gold_price × inflation 可达 50-200+/单位），存在机会成本。
> 
> **关键权衡**：囤金使 gold 分量飙升，但 cash 分量下降（失去售金收入 → 现金减少）。
> 需要平衡两者总和最大化。

**③ 控制度分量 `floor(totalControl/15)`**

| 控制状态 | 总控制度 | 分量值 |
|---------|---------|--------|
| 初始 | 105 (80+20+5) | **7** |
| 轻微扩张 | 130-150 | 8-10 |
| 中等扩张 | 170-200 | 11-13 |
| 全面控制 | 250-300 | 16-20 |

> 控制度可通过外交、军事行动提升，但 AI 也在每季扩张存在度（+2/季），会间接压低控制度。
> 初始 7 点就是一个不错的基础贡献。

**④ 影响力分量 `floor(totalInfluence/50)`**

| 影响力水平 | 总影响力 | 分量值 | 额外加成 |
|-----------|---------|--------|---------|
| 初始 | 0 | 0 | — |
| 低 | 30-60 | 0-1 | — |
| 中 | 100-200 | 2-4 | — |
| 高 | 300+ | 6+ | **+5 阈值加成** |

> 影响力每季自然衰减 -1（除非执行文化行动），需要持续投入才能维持。
> 达到 300 总影响力后的 +5/季加成非常强力，但维持 300 需要 3 个地区平均 100 影响力，投入巨大。

#### 分场景 ecoDelta 计算

**场景 A：保守型玩家（1935 年，和平期）**
- cash = 8,000, gold = 15, totalControl = 130, totalInfluence = 60
```
ecoDelta = floor(8000/2000) + floor(15×0.5) + floor(130/15) + floor(60/50)
         = 4 + 7 + 8 + 1
         = 20 点/季
```

**场景 B：均衡发展玩家（1940 年，和平期）**
- cash = 15,000, gold = 30, totalControl = 180, totalInfluence = 150
```
ecoDelta = floor(15000/2000) + floor(30×0.5) + floor(180/15) + floor(150/50)
         = 7 + 15 + 12 + 3
         = 37 点/季
```

**场景 C：经济集中型玩家（1945 年，和平期，囤金策略）**
- cash = 20,000, gold = 60, totalControl = 200, totalInfluence = 300+
```
ecoDelta = floor(20000/2000) + floor(60×0.5) + floor(200/15) + floor(300/50) + 5(阈值加成)
         = 10 + 30 + 13 + 6 + 5
         = 64 点/季
```

**场景 D：场景 B 在战时（×0.6 修正）**
```
ecoDelta = floor(37 × 0.6) = 22 点/季
```

#### 达标时间线估算

| 场景 | 每季增量 | 需要季度数 | 起始年 → 达标年 |
|------|---------|-----------|---------------|
| A (保守) | ~20 | 80 季 | 1930 → **1950** |
| B (均衡) | ~37 | 44 季 | 1930 → **1941** |
| C (集中) | ~64 | 25 季 | 1930 → **1936** |
| B (战时) | ~22 | 73 季 | 1930 → **1948** |

> **注意**：以上假设增量从 1930 Q1 起保持恒定，实际上玩家实力从低到高逐步增长，
> 早期增量远低于上述值。更现实的估算需要考虑递增过程。

#### 递增模型（更贴近实际）

假设玩家从 1930 起实力逐步增长：
- 1930-1935（20季）：平均 ecoDelta ≈ 12（早期积累不足）
- 1935-1940（20季）：平均 ecoDelta ≈ 25（中期成长）  
- 1940-1941（4季，二战前）：平均 ecoDelta ≈ 35
- 1941-1945（16季，二战，×0.6）：平均 ecoDelta ≈ floor(40×0.6) = 24
- 1945-1950（20季，战后）：平均 ecoDelta ≈ 45
- 1950-1955（20季）：平均 ecoDelta ≈ 55

**累积估算（均衡玩家）**：
```
1930-1935: 20 × 12  = 240
1935-1940: 20 × 25  = 500   → 累计 740
1940-1941:  4 × 35  = 140   → 累计 880
1941-1945: 16 × 24  = 384   → 累计 1264
1945-1950: 需要 336 点 / 45 = 约 8 季 → 1947 Q1 达标
```

**结论：均衡发展的玩家约在 1947 年前后达到经济胜利（1600 点）。**

**经济集中型玩家**（大量囤金 + 高影响力）：
```
1930-1935: 20 × 18  = 360
1935-1940: 20 × 40  = 800   → 累计 1160
1940-1941:  4 × 55  = 220   → 累计 1380
1941-1943:  8 × 38  = 304   → 累计 1684 → 约1943年Q1达标
```

**结论：专注经济路线的玩家约在 1942-1943 年可达标。**

#### 快照验证门槛分析

达到 1600 点时必须同时满足：
- **cash ≥ 10,000**：中后期只要不破产，通胀膨胀下很容易满足
- **gold ≥ 20**：如果一直自动出售，可能不足；需要在接近 1600 点时囤 20 个黄金
- **totalControl ≥ 80**：初始就是 105，只要不被 AI 大幅侵蚀就能满足

> 快照验证不构成重大障碍，只要玩家有意识地在冲刺阶段留存 20 黄金。

---

### 27.4 军事胜利详细分析

#### 每季增量公式

```
milDelta = floor(guards×0.3) + floor(morale/25) + floor(totalControl/12) + min(battleWins, 3)
战时: milDelta = floor(milDelta × 1.25)
影响力≥300: milDelta += 5
```

#### 各分量数值范围分析

**① 护卫分量 `floor(guards×0.3)`**

| 护卫规模 | 分量值 | 每季工资成本 (×通胀) |
|---------|--------|-------------------|
| 5 (初始) | 1 | 60 + 补给 30 |
| 15 | 4 | 180 + 补给 90 |
| 25 (快照门槛) | 7 | 300 + 补给 150 |
| 40 | 12 | 480 + 补给 240 |
| 60 | 18 | 720 + 补给 360 |
| 80 | 24 | 960 + 补给 480 |

> 护卫工资 = guards × 12 × inflation，补给 = guards × 3 × 2 × inflation
> 维持 40 名护卫在通胀 2x 时需要 ~1,440/季，是重大经济负担。

**② 士气分量 `floor(morale/25)`**

| 士气 | 分量值 |
|------|--------|
| 50 (快照门槛) | 2 |
| 70 (基础值) | 2 |
| 85 | 3 |
| 100 (上限) | 4 |

> 士气每季自然衰减 -2，战斗胜利 +10，失败 -18。
> 维持高士气需要频繁战斗并取胜，或有军务主管家族成员。
> 分量上限仅 4，贡献相对较小。

**③ 控制度分量 `floor(totalControl/12)`**

| 总控制度 | 分量值 |
|---------|--------|
| 105 (初始) | **8** |
| 150 | 12 |
| 200 | 16 |
| 300 | 25 |

> 军事路线的控制度除数更小（12 vs 15），控制度对军事线贡献更大。

**④ 战斗胜利分量 `min(battleWins, 3)`**

每季最多计入 3 场未结算的战斗胜利。战斗胜利来源：
- 玩家主动突袭 AI（消耗 2 AP + 180 现金）
- AI 主动进攻时防守胜利

> 实际上很难每季都有 3 场胜利，典型值为 0-1。

#### 分场景 milDelta 计算

**场景 A：保守型玩家（1930 年，和平期）**
- guards = 15, morale = 65, totalControl = 130, wins = 0
```
milDelta = floor(15×0.3) + floor(65/25) + floor(130/12) + 0
         = 4 + 2 + 10 + 0
         = 16 点/季
```

**场景 B：军事发展玩家（1935 年，和平期）**
- guards = 35, morale = 75, totalControl = 170, wins = 1
```
milDelta = floor(35×0.3) + floor(75/25) + floor(170/12) + 1
         = 10 + 3 + 14 + 1
         = 28 点/季
```

**场景 C：军事集中型（1940 年，战时，×1.25）**
- guards = 50, morale = 80, totalControl = 220, wins = 2, 影响力 300+
```
milDelta = floor(50×0.3) + floor(80/25) + floor(220/12) + 2
         = 15 + 3 + 18 + 2 = 38
战时: floor(38 × 1.25) = 47
+ 影响力加成: 47 + 5 = 52 点/季
```

**场景 D：极端军事化（1942 年，战时）**
- guards = 70, morale = 90, totalControl = 280, wins = 3, 影响力 300+
```
milDelta = floor(70×0.3) + floor(90/25) + floor(280/12) + 3
         = 21 + 3 + 23 + 3 = 50
战时: floor(50 × 1.25) = 62
+ 影响力加成: 62 + 5 = 67 点/季
```

#### 达标时间线估算

| 场景 | 每季增量 | 需要季度数 | 起始年 → 达标年 |
|------|---------|-----------|---------------|
| A (保守) | ~16 | 125 季 | 1925 → **超出1955** |
| B (军事) | ~28 | 72 季 | 1925 → **1943** |
| C (集中+战) | ~52 | 39 季 | 1925 → **1935** |
| D (极端+战) | ~67 | 30 季 | 1925 → **1932** |

#### 递增模型（更贴近实际）

```
1925-1930（20季）：平均 milDelta ≈ 10（护卫少，控制度低）
1930-1935（20季）：平均 milDelta ≈ 18（扩军中期）
1935-1940（20季）：平均 milDelta ≈ 28（成熟军事力量）
1940-1941（ 4季）：平均 milDelta ≈ 32
1941-1945（16季，战时×1.25）：平均 milDelta ≈ floor(38×1.25) ≈ 47
1945-1950（20季）：平均 milDelta ≈ 35（战后裁军，×1.0）
1950-1955（20季）：平均 milDelta ≈ 40
```

**均衡军事玩家累积**：
```
1925-1930: 20 × 10  = 200
1930-1935: 20 × 18  = 360   → 累计 560
1935-1940: 20 × 28  = 560   → 累计 1120
1940-1941:  4 × 32  = 128   → 累计 1248
1941-1945: 16 × 47  = 752   → 累计 2000 → 约1945年Q1达标
```

**结论：均衡发展的军事玩家约在 1945 年前后达到军事胜利。**

**专注军事路线（高护卫 + 高控制 + 战时利用）**：
```
1925-1930: 20 × 14  = 280
1930-1935: 20 × 26  = 520   → 累计 800
1935-1940: 20 × 38  = 760   → 累计 1560
1940-1942:  8 × 55  = 440   → 累计 2000 → 约1942年Q1达标
```

**结论：专注军事路线约在 1941-1942 年可达标。**

#### 快照验证门槛分析

达到 2000 点时必须同时满足：
- **guards ≥ 25**：军事路线玩家到中后期通常远超此值
- **morale ≥ 50**：需注意不要在冲刺阶段连败导致士气暴跌
- **totalControl ≥ 100**：初始就是 105，但 AI 扩张可能蚕食；需要维护

> 快照中最需注意的是 **totalControl ≥ 100**，如果放任 AI 势力扩张，
> 控制度可能跌破 100。需要通过军事/外交行动压制 AI 存在度。

---

### 27.5 相对领先胜利分析

#### AI 胜利点增量公式

```lua
-- AI 经济增量（1930 年后）:
ai_ecoDelta = floor(faction.cash / 2000) + floor(totalPresence / 15) + floor(weightedValue / 20)

-- AI 军事增量（1925 年后）:
ai_milDelta = floor(faction.power × 0.20) + floor(totalPresence / 18) + min(battle_wins, 3)
```

#### AI 初始状态

| AI 派系 | 初始现金 | 增长率 | 现金上限 | 初始 power | 存在度 (总/加权) |
|--------|---------|-------|---------|-----------|----------------|
| 地方家族 | 800 | 5%/季 | 8,000 | 38 | 65 / 13 |
| 外国资本 | 2,000 | 8%/季 | 12,000 | 45 | 65 / 13 |

#### AI 典型增量计算

**AI 地方家族 (1935年，cash 约 4,000 封顶后 ~8,000, power ~70)**:
```
ai_ecoDelta = floor(8000/2000) + floor(65/15) + floor(13/20) = 4 + 4 + 0 = 8
ai_milDelta = floor(70×0.20) + floor(65/18) + 0 = 14 + 3 + 0 = 17
```

**AI 外国资本 (1935年，cash ~12,000 封顶, power ~80)**:
```
ai_ecoDelta = floor(12000/2000) + floor(65/15) + floor(13/20) = 6 + 4 + 0 = 10  
ai_milDelta = floor(80×0.20) + floor(65/18) + 0 = 16 + 3 + 0 = 19
```

> **AI 最强方（外资）的典型增量**：经济 ~10/季，军事 ~19/季。
> 但 AI 存在度会随扩张增长（每季 +2），到后期增量更高。

**AI 外资后期（1945年，power 100，存在度 ~95，加权 ~20）**:
```
ai_ecoDelta = floor(12000/2000) + floor(95/15) + floor(20/20) = 6 + 6 + 1 = 13
ai_milDelta = floor(100×0.20) + floor(95/18) + 0 = 20 + 5 + 0 = 25
```

#### 相对领先需求

| 维度 | 领先幅度 | 含义 |
|------|---------|------|
| 经济领先 | ≥ 800 点 | 玩家经济分 - 最强AI经济分 ≥ 800 |
| 军事领先 | ≥ 150 点 | 玩家军事分 - 最强AI军事分 ≥ 150 |
| 全面优势 | ≥ 900 点 | 综合评分领先 900 (dominance) |

#### 经济领先可行性

从 1930 年开始，假设玩家平均 ecoDelta = 30，AI 外资平均 ai_ecoDelta = 10：
- 每季净领先 = 30 - 10 = 20 点
- 达到 800 点领先需要 40 季 = 10 年 → 1940 年
- 但相对领先只在 1945 年后可宣布 → **1945 年时领先约 (15年 × 4季 × 20) = 1200 点**，绰绰有余

**结论：经济相对领先在 1945 年可宣布时大概率已满足。**

#### 军事领先可行性

假设玩家平均 milDelta = 25，AI 外资平均 ai_milDelta = 20：
- 每季净领先 = 5 点
- 达到 150 点领先需要 30 季 → 从 1925 到 1932 年
- 1945 年时领先约 (20年 × 4季 × 5) = 400 点，满足 150 的要求

**但如果玩家军事投入不足**：
- 玩家 milDelta = 18，AI milDelta = 20 → 每季净领先 = -2（反而落后！）
- 此时军事相对领先不可能达成

**结论：军事相对领先需要玩家在军事投入上超过 AI 的自然增长速度（~20/季），否则难以达标。**

#### 全面优势分析

全面优势计算：
```
-- 玩家: dominance = economic + military + floor(totalControl/5) + floor(totalInfluence/10)
-- AI:   dominance = economic + military + floor(totalPresence/2) + weightedValue
```

AI dominance 有额外加成来自 `totalPresence/2`（后期约 95/2 = 47）和 `weightedValue`（约 20），
共 ~67 点每季「存量加成」。

玩家的存量加成来自 `totalControl/5`（初始 105/5 = 21）和 `totalInfluence/10`。

**结论：全面优势 900 点需要玩家在经济+军事两条线上都大幅领先 AI。**

---

### 27.6 综合结论与设计评估

#### 达标时间线总结

| 路线 | 保守玩家 | 均衡玩家 | 专注玩家 | 设计目标 |
|------|---------|---------|---------|---------|
| 经济胜利 (1600) | ~1950 | ~1947 | ~1942 | 1945-1950 ✅ |
| 军事胜利 (2000) | 超时 | ~1945 | ~1942 | 1940-1950 ✅ |
| 相对领先 | 1945+ | 1945 | 1945 | 1945+ ✅ |

#### 关键发现

1. **经济胜利设计合理**：阈值 1600 + 门控 1930 年，均衡玩家约 1947 年达标，符合设计目标 "1945-1950"。专注经济路线可提前到 1942 年。

2. **军事胜利难度偏高**：阈值 2000 + 门控 1925 年，虽然有更多时间（124 季 vs 104 季），但 2000 阈值比经济的 1600 高 25%。保守玩家可能无法在 1955 年前达标。
   - **优势**：战时 ×1.25 加速可利用二战期（1941-1945）冲刺
   - **劣势**：维持大量护卫的经济成本极高，可能导致破产

3. **相对领先胜利是保底路线**：对于达不到绝对阈值的玩家，只要在某一维度领先 AI 够多，1945 年后就能宣布胜利。经济相对领先（800 点）比军事相对领先（150 点）更容易达成，因为玩家经济增速通常远超 AI。

4. **囤金策略是经济胜利的关键加速器**：gold×0.5 乘数意味着 60 黄金 = +30 点/季。如果玩家在 1935 年开始囤金，到 1940 年可能累积 40-60 黄金，大幅加速经济胜利。

5. **影响力 300 阈值是双线加速器**：+5/季对两条线都有加成，但维持 300 影响力（3 地区各 100）需要大量文化行动投入和 AP 消耗，是一个高风险高回报的策略。

6. **二战期是军事线的黄金窗口**：战时 ×1.25 修正 + 16 季持续时间，集中在这段时间冲刺可累积约 750-1000 军事点。

#### 潜在平衡问题

| 问题 | 详情 | 建议 |
|------|------|------|
| 保守军事玩家超时 | milDelta ~16/季，124 季只能累积 ~1984 点，勉强达标 | 可考虑降低军事阈值至 1800 或提高 guard_multiplier 至 0.35 |
| 囤金策略过强 | 60 黄金 +30/季太高，经济线可能过早达标 | 可考虑降低 gold_multiplier 至 0.35 |
| AI 军事增长过快 | AI power 自然增长到 100 后，ai_milDelta ~25/季，接近中等玩家水平 | 军事相对领先（150 点）门槛偏低，可能需要调高 |

---

## 变更日志

### v0.5.1（当前版本）

与 v0.5.0 相比的主要变更：

| 变更类别 | 具体变化 |
|----------|----------|
| **新增胜利条件可达性分析（§27）** | 对经济胜利（1600分）、军事胜利（2000分）、相对领先胜利三条路径进行完整数学建模，含公式拆解、4种场景估算（保守/均衡/专注/战时）、AI评分对比、快照验证可行性分析，以及3个潜在平衡性问题的设计评估 |

---

### v0.5.0

与 v0.4.0 相比的主要变更：

| 变更类别 | 具体变化 |
|----------|----------|
| **科技系统全面重写** | 从 8 项/3 分支 → **41 项/4 分支/8 个分叉点**，新增互斥（excludes）和管道前置（requires "a\|b"）机制，完整列出 20 种效果类型 |
| **事件系统大幅扩展** | 固定事件从 5 个 → **35+**（覆盖全部 5 章），随机事件从 3 种 → **15 种**，新增触发条件和 chance_modifier |
| **新增分支事件系统** | 5 个历史分支节点 + 战后清算，蝴蝶效应（5% 阻止一战、10% 改变铁托走向），合作分数系统 |
| **新增大国博弈系统** | 17 个欧洲国家，主权/征服/解放机制，抵抗增长与自动解放，分支 flag 联动 |
| **新增监管压力系统** | 累积型风险指标，影子收入/腐败加压，≥50 触发监管检查 |
| **新增勘探系统** | 花费 150 + 2 季，成功率从 60% 起衰减（×0.85/次），最低 10%，科技可加成 |
| **新增矿山迁移** | 矿山枯竭时工人自动迁移到储量最多的矿山 |
| **新增煤炭资源** | 工业区独有，base_output 8，单价 8，消耗 coal_reserve |
| **通胀模型更新** | 从加法改为**乘法模型**（× (1 + drift)） |
| **股市补充** | 完整的 Box-Muller 实现、事件 mu 消耗机制、战时 sigma ×1.8 |
| **税率公式细化** | 新增 6 种修正项：legitimacy, political_standing, public_support, corruption_risk, risk, regulation_pressure |
| **胜利系统细化** | 新增 `GetVictoryStanding()` 相对评分、AI 胜利点同步、快照验证函数 |
| **回合流程补全** | 从 9 阶段 → **15+ 阶段**，新增 Phase 4.5（影响力衰减）、6.7（大国博弈）、6.8（分支事件）、8.5（勘探进度） |
| **移除设计问题追踪章节** | 原 §20 的问题已全部修复并整合到各系统章节中 |
| **修正数值差异** | 白银售价 10→15，煤炭售价 5→8，招聘费 15→30，地区储量多处更新 |

---

*文档版本：v0.5.1*  
*更新时间：2026-05-01*  
*数据来源：`scripts/data/balance.lua`、`scripts/systems/*.lua`、`scripts/data/*.lua`、`scripts/game_state.lua`*
