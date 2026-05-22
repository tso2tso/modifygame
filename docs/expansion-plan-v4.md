# 扩展计划 v4 — 后期深度与系统联动

> **背景**：当前版本后期玩法反馈"推图单一"。本计划针对中后期体验空洞问题，提出 A 级（中等投入、核心改善）和 C 级（系统级扩展）两层扩展方案，合并为一份可审核的设计文档。

---

## 已确认的核心问题

| 系统 | 具体症状 |
|------|---------|
| **远征** | 发起后是纯倒计时，8-15季内玩家零决策；终局一个隐藏骰决定胜负；占领后发展空间为零 |
| **商业远征** | 同样是倒计时模型，渗透期无中间决策；成功后据点收入是被动数字，缺乏运营感 |
| **家族系统** | 学位和岗位对游戏状态的实质影响偏弱；成员间彼此孤立，没有互动 |
| **贸易** | 中期极重要，后期因收入结构变化地位下降；快速交付是唯一主动操作 |
| **外交/大国** | 合作度机制存在但影响感弱；大国互动几乎单向（他们打我，我防守）|
| **AI 对手** | 现金/战力硬封顶，后期 AI 实质"原地踏步"；态度系统后期必然全员仇恨且无法逆转；压制选错目标；崩溃后无条件复活 |
| **文化系统** | D线科技、文化顾问、地区culture字段、事件culture修正器均已实现但互不连通；没有独立的文化资源和胜利路线；`culture_action_this_turn`、文化地图图层等"废弃管道"留存 |

---

## A 级方案：中等投入，核心改善

### A1. 远征过程事件

**目标**：打破"发起→等待→结算"的空洞区间，让每季都可能需要玩家响应。

#### 机制设计

在 `TickActiveExpeditions` 每季执行后，对每条活跃远征做一次事件抽检。触发概率为**每季 25%**，同一远征每 3 季最多触发一次（防止堆叠）。触发后推入 `state.events.active_events`，走现有事件卡系统显示。

#### 事件池（8 种）

| 事件 | 触发条件 | 选项 A | 选项 B（默认/拒绝）|
|------|---------|--------|------------------|
| **补给线受袭** | 远征持续 ≥ 4 季 | 花 120 克朗加固（无影响）| 拒绝：本季及下季伤害 -25% |
| **当地游击队** | 随机 | 花 1 AP + 情报镇压（无影响）| 拒绝：目标 HP 回复 +2 季不受压制 |
| **对方谈判使者** | 目标 HP 降至 30%–50% 区间 | 接受：立即获得 `stability×40` 克朗，远征结束（目标保留 40% HP）| 拒绝：继续，当季伤害 +15%（激怒效应）|
| **意外矿产发现** | 随机（占领后附加）| 立即变现 +200 克朗 | 投资开发：占领后净收入 +30 克朗/季（永久）|
| **大国警告函** | 侵略度 ≥ 4 时 | 公开道歉：侵略度 -1，合作度 +3 | 无视：侵略度阈值本季临时 -1（更危险）|
| **友军借道请求** | 己方已占领邻接国 | 批准：合作度 +5，对方下季帮助压制目标 HP 恢复 | 拒绝：无影响 |
| **叛逃情报** | 远征持续 ≥ 6 季 | 利用（花 50 情报）：成功率本次结算 +8% | 忽视 |
| **后方骚乱** | 己方有 2+ 条活跃远征时 | 花 150 克朗维稳 | 拒绝：守卫士气 -5（持续 2 季）|

#### 事件接轨方式（与现有事件系统的接口）

A1 事件走现有 `data/events_data.lua` + `EventBus` 路径，无需新文件：

1. **事件类型标识**：在 `events_data.lua` 中新增 8 条事件，均设 `type = "expedition_event"` 和 `expedition_id` 参数字段，以便处理回调时精确找到对应远征记录。
2. **推入队列**：`TickActiveExpeditions` 检测到触发后调用 `EventBus.Emit("push_event", { event_id = eid, expedition_id = rec.id })`，走现有事件卡系统弹出。
3. **处理回调**：玩家选项 A/B 的 `on_choose` 回调通过 `eventData:GetString("expedition_id")` 取回远征 id，再用 `state.expeditions.active[id]` 修改对应 record。
4. **"谈判使者"触发条件精确定义**：条件函数检查 `rec.target_hp / rec.target_hp_max`，满足 `0.30 ≤ ratio ≤ 0.50` 时才可触发（不在此区间则从候选事件池中排除）。

#### 数据结构扩展

远征 record 新增字段：
```lua
-- expedition record 新增（基于现有 active_expeditions[id] 结构追加）
event_cooldown = 0,        -- 距下次可触发事件的剩余季数（每次触发后置为 3）
pending_event  = nil,      -- 当前待处理事件 id（非 nil 时不再抽取新事件）
-- 已有字段确认（供回调使用）：
-- id / attacker / target_faction / target_hex / army_ids / phase / siege_turns
-- 注：expedition record 不含 "target_hp" 字段，需从 region.garrison 折算：
--   target_hp = region.garrison；target_hp_max = region.garrison_init（占领前记录）
```

#### 涉及文件

| 文件 | 改动 |
|------|------|
| `systems/expedition.lua` | `TickActiveExpeditions` 中加入事件检查逻辑 |
| `data/events_data.lua` | 新增 8 条远征专属事件（type = "expedition_event"）|
| `data/balance.lua` | 新增 `Balance.EXPEDITION.event_trigger_chance = 0.25` 等常量 |

---

### A2. 占领后发展策略

**目标**：让"拿下一个国家"之后还有运营决策，而不是被动收数字。

#### 机制设计

自占后，占领记录新增 `development_policy` 字段，玩家可在军事面板的占领地子页选择**一种策略**（选定后 4 季内不可更改）：

| 策略 | 初始费用 | 生效延迟 | 收入效果 | 侵略度影响 |
|------|---------|---------|---------|----------|
| **直接征税**（默认）| 无 | 立即 | 标准（+80 小国/+150 大国）| 无 |
| **工业开发** | 300 克朗 | 3 季后生效 | +130/+210 克朗/季 | 无 |
| **扶植傀儡** | 100 克朗 | 2 季后生效 | 减半（+40/+75）| 侵略度衰减速度 ×1.5（该国产生的不再累积）|
| **文化同化** | 200 克朗 + 需魅力≥3成员在岗 | 4 季后生效 | 标准 | 额外提供每季 +2 控制度（全局）|

#### 控制稳定度（新增子状态）

自占后，该国有 `stability_control`（0–100，初始 40）：
- 每季 +8（自然建立）
- 低于 50 时：实际收入 = 理论收入 × `(stability_control / 50)`
- 工业开发策略激活后：稳定度增速 ×1.5
- 发生叛乱事件（来自 A1 后方骚乱）：稳定度 -20

这让占领地变成需要短期投入换取长期回报的资源，而不是即得的被动收入。

#### 实现细节补全

**`stability_control` 初始化时机**：在 `expedition.lua` 的 `CompleteExpedition`（参见第 298 行附近的 `outcome == "victory"` 分支）执行完区域控制权转移后，立即写入：
```lua
-- CompleteExpedition 中，occupation 子状态初始化
region.stability_control = 40       -- 初始值 40（不稳定，需要 2–3 季才到 50）
region.development_policy = "tax"   -- 默认直接征税
region.policy_lock_turn   = 0       -- 策略锁定结束的季数（0 = 未锁定）
```

**策略锁定判断**：玩家切换策略时，写入 `region.policy_lock_turn = state.turn + 4`。每次结算前检查：
```lua
-- SettleTurn 中的策略切换守卫
if region.policy_lock_turn > state.turn then
    -- 仍在锁定期，不允许切换
end
```

**`income_only`（仅割收入）验证公式**：A2 的"直接征税"策略对应现有 `expedition.lua` 第 48 行的 `income_only` 分支，现有实现：`harvest_gold = floor(prosperity × 1.5)`。A2 扩展后，直接征税的季度收入改为：
```lua
-- territory.prosperity 对应 A2 中的 stability_control（两者都描述地区状态）
local base = (region.is_small and 80 or 150)   -- 小国80，大国150克朗/季
local stab_ratio = math.min(1.0, (region.stability_control or 40) / 50)
local income = math.floor(base * stab_ratio)   -- stability_control < 50 时按比例缩减
```

**A1 后方骚乱事件的稳定度惩罚落点**：后方骚乱（A1 事件表最后一条）选择"拒绝"时，其 `on_choose_b` 回调中修改：
```lua
-- 找到所有己方占领地（region.controller == player_faction）
for _, region in ipairs(state.regions) do
    if region.controller == state.player_faction and region.stability_control then
        region.stability_control = math.max(0, region.stability_control - 20)
    end
end
-- 同时：guardian morale -5 持续 2 季，通过 state.modifiers 写入时限 modifier
```

#### 涉及文件

| 文件 | 改动 |
|------|------|
| `systems/expedition.lua` | `CompleteExpedition` 的 `outcome == "victory"` 分支后追加 `stability_control` 和 `development_policy` 初始化；`SettleTurn` 中加入稳定度计算（+8/季）和收入修正（stab_ratio）；策略锁定守卫 |
| `ui/ui_expedition.lua` | 占领地详情新增策略选择 UI（含锁定倒计时提示）|
| `data/balance.lua` | 新增 `Balance.EXPEDITION.occupation_stability_init = 40`、`stability_recovery = 8`、`stability_income_threshold = 50` 等常量 |

---

### A3. 商业远征中间决策

**目标**：渗透期同样有"要不要响应"的决策，而不只是等进度条。

商业远征与军事远征共享"空洞等待"的问题，但机制独立，单独设计：

#### 渗透危机（每季 20% 触发）

活跃渗透触发危机事件，不处理则渗透速度降低或投资额临时上升：

| 危机 | 后果（不处理）| 处理代价 |
|------|------------|---------|
| **本地竞争者崛起** | 本季渗透效率 -20% | 花 200 克朗收购（直接 +5% 渗透进度）|
| **关税壁垒临时上调** | 本季投资额 ×1.3 | 外交操作（花 1 AP + 情报）取消 |
| **内部腐败调查** | 渗透冷却 +2 季（完成后） | 花 300 克朗疏通 |

#### 策略切换时机

现有 `Venture.ChangeStrategy` 已实现，但当前玩家没有理由切换。新增**策略时机奖励**：
- 在市场壁垒降至 50% 以下时切换为"倾销"：渗透速度临时 +25%（只在此窗口有效）
- 在大国处于战争状态时切换为"技术出口"：合作度加成翻倍

#### 与现有 venture 状态字段的对应关系

危机事件和策略时机直接读写 `venture.lua` 的 `VentureSystem.Init` 已有字段（第 356–387 行），无需新增字段：

| A3 设计概念 | 对应现有字段 | 读写方式 |
|------------|-----------|---------|
| 渗透被阻断 | `venture.blocked = true` | `VentureSystem.Sabotage` 在 hp→0 时设置；危机 C（内部腐败）将此临时置 true + 加计时器 |
| 渗透进度降低 | `venture.infiltrated` / `venture.infiltrate_turn` | 危机 A（竞争者崛起）将本季渗透进度 ×0.8（乘以效率修正，不改字段） |
| 投资额上升 | `venture.barrier`（市场壁垒） | 危机 B（关税壁垒）调用 `venture.barrier = venture.barrier + 15`（临时，2 季后恢复）|
| 渗透冷却 | `venture.infiltrate_turn`（最后渗透季） | 危机 C（腐败调查）：`venture.infiltrate_turn = state.turn + 2`（强制冷却 2 季）|
| 渗透效率 | （新增临时字段）`venture.efficiency_mod = 0.8` | 危机 A 未处理时，`TickActiveVentures` 本季渗透增量 × `efficiency_mod`（默认 1.0）|

**策略时机窗口触发判断**：

```lua
-- ChangeStrategy 中加入窗口检查（venture.lua 新增逻辑）
function VentureSystem.GetStrategyBonus(venture, strategy, state)
    -- 窗口一：市场壁垒降至50%以下 → 倾销加速
    local barrier = VentureSystem.CalcMarketBarrier(venture, state)
    if strategy == "dumping" and barrier < (state.balance.VENTURE.MARKET_BARRIER_BASE * 0.5) then
        return 1.25  -- 渗透速度临时 +25%（仅在此窗口持续，barrier 回升后失效）
    end
    -- 窗口二：目标大国处于战争状态 → 技术出口加成翻倍
    if strategy == "tech_export" then
        for _, conflict in pairs(state.active_conflicts) do
            if conflict.faction_a == venture.target_country
            or conflict.faction_b == venture.target_country then
                return 2.0  -- 合作度加成翻倍
            end
        end
    end
    return 1.0  -- 无窗口加成
end
```

`state.active_conflicts` 是 `game_state.lua` 第 28 行的已有字段（keyed by "factionA_factionB"），直接读取即可。

#### 涉及文件

| 文件 | 改动 |
|------|------|
| `systems/venture.lua` | `TickActiveVentures` 中加入危机抽检逻辑（读 `venture.infiltrated`/`venture.barrier`）；新增 `GetStrategyBonus` 函数（读 `state.active_conflicts`）；`ChangeStrategy` 调用 `GetStrategyBonus` |
| `data/events_data.lua` | 新增 3 条商业远征危机事件（`type = "venture_crisis_event"`，携带 `venture_id` 参数）|

---

### A4. 家族成员专精岗位效果

**目标**：让岗位分配真正影响核心数值，让"用对人"产生明显差异。

#### 现状

当前岗位效果多为 `function_unlock`（解锁操作权限），很少直接影响数值。属性加成对游戏状态的映射路径不透明。

#### 改动方向

为每个岗位新增**属性联动加成**，使用成员最相关的属性计算：

| 岗位 | 关联属性 | 新增效果 |
|------|---------|---------|
| 军事统帅 | 谋略 | 每点谋略提供编队伤害 +2%（上限 +20%）|
| 贸易经理 | 野心 | 每点野心提供贸易订单利润 +1.5%（上限 +15%）|
| 情报主任 | 野心 | 每点野心提供 AP 行动情报折扣（远征事件处理消耗 -1 情报）|
| 外交官 | 魅力 | 每点魅力提供侵略度衰减 +0.1/季（叠加到默认 -0.5）|
| 矿场监管 | 管理 | 每点管理提供矿山产量 +3%（上限 +30%）|

#### 属性系统实现细节

**属性取值范围**：基于 `config.lua`（第 33–42 行），成员属性取值范围为 **0–100**（`MIN_ATTRIBUTE = 0`，`MAX_ATTRIBUTE = 100`），初始基础值：`competence = 50`，`charisma = 50`，`loyalty = 100`。属性表中未定义"谋略/野心/魅力/管理"这些具体属性——**实现时应使用现有通用字段 `competence`（能力）和 `charisma`（魅力）映射到对应岗位效果**，或在成员数据中直接扩展新字段（建议取值同样 0–100）。

**属性读取方式**：使用 `family.lua` 第 24–31 行的 `FamilySystem.GetMemberAttr(member, attr)` 函数。该函数支持 `base + bonus` 结构：
```lua
-- FamilySystem.GetMemberAttr 内部逻辑（family.lua 第 25–31 行）
local base = member[attr] or 0          -- 如 member.charisma = 65
local bonus = member[attr .. "_bonus"] or 0  -- 如 member.charisma_bonus = 10（装备/事件临时加成）
return base + bonus  -- 返回 75
```

**岗位读取方式**：`FamilySystem.GetMemberAtPosition(family, position)` 遍历 `family.members`，找 `member.position == positionId`。结合上文，完整调用示例：
```lua
-- turn_engine.lua 结算阶段（Phase B / C 前），写入临时 modifier
local family = state.family
-- 军事统帅（position = "military_commander"）
local commander = FamilySystem.GetMemberAtPosition(family, "military_commander")
if commander then
    local strategy = FamilySystem.GetMemberAttr(commander, "competence")  -- 0–100
    -- 每点 competence 提供 +2% 伤害，上限 +20%（即 10 点封顶）
    local dmg_bonus = math.min(20, math.floor(strategy / 10) * 2)
    state.modifiers["commander_dmg_bonus"] = dmg_bonus
end
```

**加成写入位置**：所有岗位加成写入 `state.modifiers`（键值对，value 为数值），在 Phase 结算消耗时读取，**不持久化到 game_state 的固定字段**——这样成员退出岗位后加成自动失效（下季结算时不再写入）。

#### 涉及文件

| 文件 | 改动 |
|------|------|
| `systems/turn_engine.lua` | Phase B/C 前新增"岗位加成结算"步骤：遍历 5 个岗位，调用 `GetMemberAtPosition` + `GetMemberAttr`，写入 `state.modifiers` 对应键 |
| `data/titles_data.lua` | 无需改动（岗位解锁逻辑不变，加成独立计算）|
| `game_state.lua` | `GetMemberAtPosition` 已在 `family.lua` 提供，无需重复新增 |

---

## C 级方案：系统级扩展

### C1. 联合远征（钳形攻势）

**目标**：让多路线同时进攻成为有战略深度的选择，而不只是"能开几条就开几条"。

#### 机制设计

当玩家同时对**互相邻接**的 2 个国家发动远征时，系统自动检测并激活"钳形攻势"状态：

```
条件：
  - 两条远征同一季发动（或间隔 ≤ 1 季）
  - 两个目标国家在地图上相邻
  - 发动时额外 +1 AP 消耗（总 3AP，强调协调代价）

效果：
  - 两个目标防御力各 -15%（分散兵力）
  - 两条远征成功率各 +5%（钳形包围心理优势）
  - 若其中一条先完成，另一条获得"后方威胁"加成 +20%（等效现有 forward base bonus）

反制：
  - 若其中一条失败，另一条当季伤害减少 20%（士气受挫）
  - 侵略度计算为两次独立计算（不是 1.5× 叠加，保持可控）
```

#### 联合撤退

若玩家从钳形攻势中撤回一条，另一条自动失去钳形加成（但不额外惩罚）。

#### UI 入口

在远征面板新增"战略态势"小节，当检测到可以发动钳形攻势时高亮提示目标组合。

#### 钳形检测实现细节

**相邻关系数据来源**：`expedition.lua` 第 145–154 行已有相邻检测逻辑，通过 `state.map[region.id .. "_" .. dir]`（四方向：north/south/east/west）获取邻格。C1 的钳形检测复用同一 map 结构：

```lua
-- LaunchExpedition 后执行的钳形检测（expedition.lua 新增辅助函数）
local function check_pincer(state, new_exp_id)
    local new_exp = state.expeditions.active[new_exp_id]
    for id, exp in pairs(state.expeditions.active) do
        if id ~= new_exp_id and exp.attacker == new_exp.attacker then
            -- 判断两个目标国家的首都 hex 是否相邻
            local a_hex = new_exp.target_hex
            local b_hex = exp.target_hex
            for _, dir in ipairs({"north", "south", "east", "west"}) do
                local neighbor = state.map[a_hex .. "_" .. dir]
                if neighbor and neighbor.hex_id == b_hex then
                    -- 找到！互相设置 pincer_partner
                    new_exp.pincer_partner = id
                    exp.pincer_partner = new_exp_id
                    return
                end
            end
        end
    end
end
```

**发动时机差距容忍**：两条远征的 `turns_in_phase` 差值 ≤ 1 季即视为"同时发动"（当季发动 + 上季发动均可组成钳形）。

**失败惩罚触发时机**：在 `CompleteExpedition`（第 298 行）处理完本次远征结局后，**立即检查** `expedition.pincer_partner`：
```lua
-- CompleteExpedition 末尾追加（outcome == "fail" 或 "defeat" 分支）
if expedition.pincer_partner then
    local partner = state.expeditions.active[expedition.pincer_partner]
    if partner then
        -- 伙伴本季伤害减少 20%（写入临时 modifier，持续 1 季）
        partner.pincer_failed_penalty = 0.80  -- CalcTurnDamage 读取此字段
        expedition.pincer_partner = nil       -- 清除关联
        partner.pincer_partner = nil
    end
end
```

#### 涉及文件

| 文件 | 改动 |
|------|------|
| `systems/expedition.lua` | `LaunchExpedition` 后调用 `check_pincer` 检测相邻；`CalcTurnDamage` 读取 `pincer_bonus`（-15% 防御）和 `pincer_failed_penalty`（-20% 伤害）修正；`CompleteExpedition` 中 fail/defeat 分支追加伙伴惩罚 |
| `game_state.lua` | `expeditions.active[id]` 新增 `pincer_partner = nil`（远征记录初始化时默认 nil）|
| `data/balance.lua` | 新增 `Balance.EXPEDITION.pincer_defense_reduce = 0.15`、`pincer_success_bonus = 0.05`、`pincer_fail_penalty = 0.20`、`pincer_forward_bonus = 0.20` |
| `ui/ui_expedition.lua` | 新增战略态势提示 UI |

---

### C2. 外交路线（非战争扩张）

**目标**：给外交/商业取向玩家提供一条不用打仗也能建立势力范围的路径，与军事路线形成真正的对称选择。

#### 前置条件

- 已开通对目标国家的贸易路线
- 在岗外交官魅力 ≥ 3
- 目标国家稳定度 ≤ 8（过于稳定的国家不接受外交渗透）
- 与军事远征互斥：同一目标不能同时进行两种路线

#### 核心流程

```
发起外交施压（1 AP）
    ↓
外交渗透期（每季被动推进，类似商业渗透）
    ↓
影响力达到阈值 → 谈判窗口
    ↓
签订协议（选择协议类型）
```

#### 外交渗透公式

```
每季影响力增量 = (外交官魅力 × 3) + (贸易路线数量 × 2) - (目标stability × 1.5)
```

对 stability 8 的国家，魅力 3 + 2 条路线：3×3+2×2−8×1.5 = 9+4−12 = **1 点/季**（需要约 30 季，偏慢但无伤亡）。

影响力池 = `target.stability × 15`（对比军事远征 HP = `stability × 7`，外交池约 2× 深）

#### 协议类型（影响力满时选择）

| 协议 | 效果 | 侵略度 | 限制 |
|------|------|--------|------|
| **贸易特许** | 该国所有贸易路线利润 +20%，不计入占领地 | 0 | 仅限贸易路线已开通 |
| **保护协议** | 每季 +50 克朗（小于自占），对方主权不变，维护 0 | 0 | 不能同时自占 |
| **军事同盟** | 对方帮助抵御 AI 侵略（守备 +1 等效编队），合作度 +10 | +1（一次性）| 需魅力 ≥ 4 |
| **臣服关系** | 相当于给予派系的弱化版：计入侵略度 +1，收入 +60，但对方保留 50% 自主性（可能反叛）| +1（一次性）| 需影响力 ×1.5 倍（更难）|

#### 反叛机制（臣服关系特有）

每季 5% 概率触发反叛事件：
- 选项 A：花 200 克朗镇压（关系保持）
- 选项 B：接受（关系破裂，退回保护协议状态，下次谈判难度 +20%）

#### 与军事远征的联动

- 军事路线完成后，该国外交渗透速度 +50%（战败国更容易接受外交）
- 外交路线进行中发动军事远征：外交进度归零，影响力清空

#### 实现细节补全

**外交影响力字段**：复用 `resource_manager.lua` 已有的 `state.diplomatic_influence` 字段（`game_state.lua` 第 12 行，初始值 0）。C2 的"外交影响力池"是**每条外交远征独立维护的进度变量**，与全局 `diplomatic_influence` 资源不同：
- `state.diplomatic_influence`：全局资源，每季通过 `resource_manager.influence_income` 积累（+5/盟友），用于**发起外交远征的消耗**（设定为一次性消耗 20 影响力发起）
- `diplomacy_rec.influence_progress`：每条外交远征独立的进度（0 → `target.stability × 15`），每季由渗透公式推进

**协议运行期间每季结算逻辑**：协议签订后，在 `TickDiplomacy` 中对 `diplomacy_active` 遍历，执行以下结算（以"保护协议"为例）：
```lua
-- 协议每季结算（写入 state.gold 和 state.diplomatic_influence）
for id, rec in pairs(state.expeditions.diplomacy_active) do
    if rec.status == "active_treaty" then
        if rec.treaty_type == "trade_concession" then
            -- 贸易特许：修正该国所有贸易路线利润，写入 modifier
            state.modifiers["trade_bonus_" .. rec.target] = 0.20
        elseif rec.treaty_type == "protection" then
            -- 保护协议：直接加克朗
            state.gold = state.gold + 50
        elseif rec.treaty_type == "vassal" then
            -- 臣服关系：加克朗，5% 反叛检查
            state.gold = state.gold + 60
            if math.random() < 0.05 then
                EventBus.Emit("push_event", { event_id = "vassal_revolt", diplomacy_id = id })
            end
        end
    end
end
```

**关系层级设计**：C2 的外交关系状态通过 `rec.treaty_type` 字符串标识，存储在 `diplomacy_active[id]` 记录中，**不修改**现有 `state.relations[factionA][factionB]`（-100 到 +100 的数值）——后者继续用于 AI 态度判断，前者是独立的协议状态机：

| `treaty_type` 值 | 含义 | 每季结算 |
|----------------|-----|---------|
| `nil`（无协议）| 外交渗透中（`influence_progress` 积累中）| 推进渗透进度 |
| `"trade_concession"` | 贸易特许协议有效 | 写入 +20% 贸易 modifier |
| `"protection"` | 保护协议有效 | +50 克朗/季 |
| `"military_alliance"` | 军事同盟有效 | 守备 +1 等效编队 modifier |
| `"vassal"` | 臣服关系有效 | +60 克朗/季，5% 反叛检查 |
| `"broken"` | 协议破裂（反叛/取消）| 下季清除记录 |

#### 涉及文件

| 文件 | 改动 |
|------|------|
| `systems/expedition.lua` | 新增 `Expedition.LaunchDiplomacy`（消耗 `state.diplomatic_influence`）/ `TickDiplomacy`（渗透进度 + 协议结算）/ `ResolveDiplomacy`（谈判窗口触发）函数族 |
| `game_state.lua` | `expeditions` 表新增 `diplomacy_active = {}` 子表；`diplomatic_influence` 字段已存在，无需新增 |
| `ui/ui_expedition.lua` | 在远征面板新增"外交路线"标签页 |
| `data/balance.lua` | 新增 `Balance.EXPEDITION.diplomacy_*` 系列常量（`launch_cost = 20`、`influence_pool_mult = 15` 等）|

---

### C3. 大国动态博弈（被动战线升级）

**目标**：把当前"大国偶尔开战，玩家旁观或接佣兵"升级为玩家可以主动影响的地缘博弈。

#### 现状

当前大国战争是背景板，`state.fronts` 数据存在但玩家只能通过 `Support` 接佣兵。

#### 新增：暗中支援（Covert Support）

玩家可以选择向交战方之一提供**秘密支援**（不同于公开佣兵 Support 操作）：

```
行动：暗中支援 A 方打 B 方
消耗：1 AP + 情报 × 目标stability/2
效果：
  - A 方本季战力 +15%，战争结束更快
  - 如果 A 方赢：A 方对玩家好感 +20，B 方 -30
  - 如果被发现（20% 概率）：B 方好感 -50，合作度 -10，侵略度 +2
```

#### 新增：煽动战争

花情报"煽动"两个暂时和平的大国开战，为自己创造支援/佣兵机会：

```
消耗：3 AP + 200 情报
条件：目标双方关系值 ≤ -20（有积怨）
成功率：60% 基础
效果：目标双方在 2 季后开始冲突（加入 fronts）
      玩家可接后续佣兵订单
风险：如果被任何一方发现（30% 概率）：双方好感各 -40
```

#### 大国势力范围

在地图层面显示每个大国的**势力范围**（当前 `country.sovereign` 已有，只是没有可视化战略价值）：

- 玩家占领大国势力范围内的小国 → 侵略度额外 +1（踩了对方的地盘）
- 玩家主动将占领地的小国"送给"某大国 → 该大国对玩家好感 +10，成为潜在庇护者
- 若玩家合作度极高（≥ 50）：该大国不对玩家发动制裁，侵略度制裁阈值临时 +2

#### 实现细节补全

##### 关系字段确认：大国间"积怨"的判断依据

> 文档原文写"目标双方关系值 ≤ -20（有积怨）"。查阅代码后确认：游戏**不存在大国间关系矩阵**，仅有 `power.attitude_to_player`（-100~+100）记录玩家与大国的单向关系。

**大国间积怨改用以下代理指标判断**（两条件均满足才可煽动）：

| 条件 | 代理字段 | 判断逻辑 |
|------|---------|---------|
| A 方对 B 方有领土野心 | `state.powers[powA].war_goals` | `war_goals` 中包含属于 B 方主权(`sovereign == powB`)的地区 ID |
| 双方目前不处于历史剧本事件期 | `state._branch_war_accelerated` / `_branch_war_delayed` | 两个分支标记均为 false，即当前脚本未强制接管战争进程 |

```lua
-- player_actions_gp.lua — InciteWar 的 condition 检查
function CanInciteWar(state, powA, powB)
    local pA = state.powers[powA]
    local pB = state.powers[powB]
    if not pA or not pA.active or not pB or not pB.active then
        return false, "大国不活跃"
    end
    -- 检查 A 是否对 B 有领土野心（war_goals 中存在 B 主权的地区）
    local hasGoals = false
    for _, goalId in ipairs(pA.war_goals or {}) do
        local country = state.europe and state.europe[goalId]
        if country and country.sovereign == powB then
            hasGoals = true
            break
        end
    end
    if not hasGoals then return false, "双方无领土积怨" end
    -- 检查未被剧本锁定
    if state._branch_war_accelerated or (state._branch_war_delayed or 0) > 0 then
        return false, "当前历史进程已被锁定，无法煽动"
    end
    return true
end
```

##### 冲突生成逻辑：如何将"煽动"结果写入游戏状态

游戏的大国战争进程由 `grand_powers.lua` 按 `PowersData.GetConquestTimeline` 的**时间线事件**驱动，没有运行时动态冲突表。`state.fronts` 目前仅是初始化为 `{}` 的占位字段（Phase 2 功能），当前未被任何逻辑读取。

因此**煽动战争**的实现方式不是写入 `state.fronts`，而是**注入一条提前征服事件**：

```lua
-- systems/player_actions_gp.lua — InciteWar.execute
function ExecuteInciteWar(state, powA, powB, targetCountryId)
    -- targetCountryId：powA war_goals 中属于 powB 主权的某个地区
    -- 1. 标记"加速进攻"：2 季后触发一次 conquer 事件
    state._incited_wars = state._incited_wars or {}
    table.insert(state._incited_wars, {
        attacker     = powA,
        target       = targetCountryId,
        trigger_turn = state.turn + 2,       -- 2 季后生效
        instigator   = "player",             -- 溯源标记（用于被发现惩罚）
    })
    -- 2. 双方好感各 -40（被发现时）由 Turn_engine Phase 结算时概率触发
    -- 3. 侵略计数器不增加（属于大国间战争，非玩家直接行动）
end
```

**`turn_engine.lua` 中消费 `_incited_wars`**（在 `GrandPowers.Tick` 之后、Phase 结算前插入）：

```lua
-- turn_engine.lua — Phase 1（大国 Tick 后）新增片段
if state._incited_wars then
    local remaining = {}
    for _, inc in ipairs(state._incited_wars) do
        if state.turn >= inc.trigger_turn then
            -- 直接插入一条征服事件（复用 grand_powers 的征服处理路径）
            GrandPowers._ApplyConquest(state, {
                action   = "conquer",
                attacker = inc.attacker,
                target   = inc.target,
                year     = state.year,
            })
            -- 30% 概率被发现 → 双方好感 -40
            if math.random() < 0.30 then
                local pA = state.powers[inc.attacker]
                local pB = state.powers[state.europe[inc.target] and
                                         state.europe[inc.target].sovereign or ""]
                if pA then pA.attitude_to_player = math.max(-100, pA.attitude_to_player - 40) end
                if pB then pB.attitude_to_player = math.max(-100, pB.attitude_to_player - 40) end
                GameState.AddLog(state, "煽动战争阴谋败露，双方大国对玩家好感大幅下降")
            end
        else
            table.insert(remaining, inc)
        end
    end
    state._incited_wars = remaining
end
```

**暗中支援的战力加成写入位置**：`CovertSupport` 执行时写入 `state.modifiers["covert_military_bonus_" .. powerId]`，`grand_powers.lua` 的 `_ProcessConquestTimeline` 在读取 `attackerPower.military` 时叠加此修正器（需在该函数中增加一行 `math.min(100, military * (1 + mod))`）。

#### 涉及文件

| 文件 | 改动 |
|------|------|
| `systems/expedition.lua` | 新增 `Expedition.CovertSupport` / `Expedition.InciteWar` 函数 |
| `systems/player_actions_gp.lua` | 实现 `CanInciteWar` 条件检查（基于 `war_goals` 代理指标）；`ExecuteInciteWar` 写入 `state._incited_wars` 列表 |
| `systems/turn_engine.lua` | Phase 1 大国 Tick 后新增消费 `_incited_wars` 的片段；大国战争结算时叠加 `covert_military_bonus` 修正器 |
| `systems/grand_powers.lua` | 暴露 `GrandPowers._ApplyConquest` 内部函数供 turn_engine 复用；`_ProcessConquestTimeline` 读取 `covert_military_bonus` 修正器 |
| `ui/ui_expedition.lua` | 在远征面板新增"大国博弈"操作区 |
| `data/balance.lua` | 新增 `Balance.GP.covert_support_ap = 1`、`incite_war_ap = 3`、`incite_war_intel_cost = 200`、`incite_success_rate = 0.60`、`incite_detected_chance = 0.30` |

---

### C5. 文化胜利路线

**目标**：把现有五处"已建好但断线"的文化基础设施接通，形成一条以**创作和传播文化作品**为核心的第三胜利路线——不靠军队占领，不靠资本收购，而是让其他地区主动向你靠拢。

---

#### 设计定位

| 路线 | 核心行动 | 扩张方式 | 节奏 |
|------|---------|---------|------|
| 经济胜利 | 赚钱、囤黄金、买矿 | 资本渗透 | 快，中期爆发 |
| 军事胜利 | 打仗、占领、压制 | 武力征服 | 激进，侵略度压力大 |
| **文化胜利** | **制作作品、传播影响** | **软实力辐射** | 慢而稳，对外零侵略度 |

文化路线与军事路线形成**真实策略对立**：军事占领会破坏被占地区的文化点（战争 -15 CP），所以纯文化路线玩家应**避免大规模战争**，走外交+文化的柔性扩张道路。

---

#### 核心资源：文化影响力（Cultural Influence，简称 CI）

CI 是文化路线的专属资源，类似"文化生产力"，用于创作作品和进行文化行动。

**CI 来源（每季）**：

| 来源 | 增量 |
|------|------|
| D线科技被动控制度增益（重新绑定） | +1 ~ +6（按已研发科技累计）|
| `region.culture` 字段（萨拉热窝 culture=20） | 首都每季额外 +2 CI（首次接通废弃字段）|
| 文化顾问 bonus（0.5/1.0） | CI 产出 × 1.25 / × 1.5 |
| 事件 `culture` 修正器（原来沉默的） | 直接转化为 CI 增量（首次接通废弃修正器）|
| 大学建筑（d6a_university） | +3 CI/季 |
| 民族史诗（作品效果，见下） | 每部 +2 CI/季（永久，可叠加）|

**CI 消耗**：用于制作和部署文化作品（见下）。

**CI 自然衰减**：每季 -2（鼓励持续投入）。文化顾问满配（1.0）获得"文化感召"——**CI 不衰减**（接通原来 UI 上无实现的"免疫衰减"）。

---

#### 核心机制：文化作品系统

玩家制作具体的文化作品，然后将其传播到目标地区，积累**文化点（Cultural Points，CP）**。

**每季限制**：复活 `culture_action_this_turn` flag，每季最多执行 **1 次文化行动**（创作或部署二选一）。

---

##### 作品一：歌舞剧团（Theater Troupe）

> *萨拉热窝国家剧院于1919年建立，巡演南斯拉夫民族史诗*

| 属性 | 值 |
|------|---|
| 解锁 | 无前置，早期核心手段 |
| 创作成本 | 200 克朗 + 1 AP |
| 机制 | 驻扎在一个地区，每季给该地区 **+5 CP**；消耗 1 AP 可迁移至邻近地区 |
| 叠加衰减 | 同一地区第 2 个剧团仅 +3 CP，第 3 个仅 +1 CP（鼓励扩散而非堆叠）|
| 特色 | 最灵活，可追随战略重心移动；早期民族主义运动的主要文化载体 |

---

##### 作品二：电影（Film Production）

> *1913年萨拉热窝拍摄了巴尔干第一部纪录片，随后出口至维也纳、贝尔格莱德*

| 属性 | 值 |
|------|---|
| 解锁 | `d5b_cinema`（电影工业科技）|
| 创作成本 | 400 克朗，**生产期 2 季**（不立即可用）|
| 机制 | 制作完成后选择发行方式（每部电影只能选一次）|
| 发行：国内公映 | 己方所有控制区 **+3 CP** |
| 发行：国际发行 | 目标国家所有地区 **+8 CP**（唯一能跨越未占领区影响远方的手段）|
| 发行：节庆展映 | 触发外交事件，目标 AI 好感 **+10 ~ +25**（随己方声誉浮动）|
| 特色 | 传播距离最远；每部电影主题唯一（历史/民族/工业），同主题不可重复拍摄 |

---

##### 作品三：民族史诗出版（National Epic）

> *《波黑史诗》印刷发行，在整个南斯拉夫地区引发民族认同浪潮*

| 属性 | 值 |
|------|---|
| 解锁 | `d6a_university`（萨拉热窝大学）|
| 创作成本 | 300 克朗 + 10 研发点 |
| 机制 | **永久效果**：每季给己方所有控制区 +2 CP，邻近未占领地区 +1 CP；同时 CI 产出 **+2/季** |
| 叠加上限 | 最多出版 3 部（三大主题：民族/宗教/历史），主题不可重复 |
| 特色 | 被动滚雪球；越早出版越划算；强调"有历史底蕴"的文化体系 |

---

##### 作品四：体育赛事（Sports Event）

> *1930年举办巴尔干杯足球锦标赛，五国派队参赛，观众逾万*

| 属性 | 值 |
|------|---|
| 解锁 | 无前置 |
| 创作成本 | 250 克朗，**冷却 4 季** |
| 机制 | 一次性爆发：举办地 **+20 CP**，邻近地区 **+8 CP** |
| 邀请机制 | 可邀请 AI 国家派队参赛（好感 ≥ 10 才接受）；每个接受邀请的国家 AI 好感 **+10** |
| 外交风险 | 邀请好感 < 10 的国家：有 30% 概率公开拒绝，触发外交紧张事件（AI 好感 -5）|
| 特色 | CP 爆发最高；兼顾外交效果；邀请谁参赛本身是策略决策 |

---

##### 作品五：世界博览会（Grand Exhibition）

> *1935年萨拉热窝国际展览会，展示巴尔干工业与文化成就，吸引欧洲各国使节出席*

| 属性 | 值 |
|------|---|
| 解锁 | 文化顾问满配（bonus 1.0）+ `d8_cultural_hegemony` + 至少 2 部史诗已出版 |
| 创作成本 | 800 克朗 + 2 AP，**筹备期 3 季** |
| 机制 | 全局文化事件：所有地区 **+15 ~ +40 CP**（按己方科技数量和声誉值加权）|
| 外交解锁 | 触发后解锁专属外交选项"文化保护国"——邀请 1 个 AI 国家成为文化盟友（永久好感 +30，该国不会主动对玩家宣战）|
| 限制 | **每局只能举办一次**，时机选择至关重要 |
| 特色 | 文化路线的终极大招；时机好时可一次完成大量地区的 CP 飞跃 |

---

#### 文化影响等级与地区效果

每个地区维护独立的 CP 值（0–100），达到不同等级时触发效果：

| CP 区间 | 等级名 | 效果 |
|---------|-------|------|
| 0–29 | 无感知 | 无 |
| 30–49 | 文化好奇 | AI 好感 **+5**（一次性），偶发文化事件（新闻报道/民间交流）|
| 50–69 | 文化倾慕 | AI 好感 **+10**（一次性），解锁"文化交流协议"外交选项 |
| 70–89 | 文化认同 | AI 好感 **+15**（一次性），该地区每季反向给玩家 **+1 CI**；AI 可能主动发起条约谈判 |
| 90–100 | 文化同化 | 计入胜利条件；即使未被军事占领，该地区也算玩家"软性势力范围"（商业渗透速度 +30%）|

**CP 自然衰减**：外国地区每季 -1 CP（强调"文化影响需要持续投入"）。文化顾问满配时己方控制区 CP 不衰减（配合"免疫衰减"标签）。

**战争惩罚**：对某地区发动军事远征时，该地区 CP **-15**（文化与武力不相容）。

---

#### 文化胜利条件

```
当以下条件同时满足时触发文化胜利：

1. 年份 >= 1938
2. 已研发 d8_cultural_hegemony（文化霸权）和 d11_cultural_renaissance（文化复兴）
3. 以下两种达成方式之一：
   方式 A：3 个地区达到"文化认同"（CP >= 70）
   方式 B：2 个地区达到"文化同化"（CP >= 90）+ CI 储量 >= 150
4. 己方 culture_score（累积分）领先最强 AI >= 500 分
```

`culture_score` 每季累积规则（在 `turn_engine.lua` Phase 结算中加入）：
```lua
-- 每季 culture_score 增量
local cultureGain = floor(state.culture.ci / 10)    -- CI 转化
for _, region in ipairs(state.regions) do
    local cp = GetRegionCP(state, region.id) or 0
    if cp >= 70 then cultureGain = cultureGain + 3   -- 认同地区奖励
    elseif cp >= 50 then cultureGain = cultureGain + 1
    end
end
state.victory.culture = (state.victory.culture or 0) + cultureGain
```

胜利标题：**文化胜利：巴尔干文明灯塔**

---

#### 接通现有废弃管道

| 废弃结构 | 原状态 | 接通后 |
|---------|-------|-------|
| `region.culture` 字段 | 展示数字，无计算意义 | 萨拉热窝 culture=20 → 每季额外 +2 CI |
| 事件 `culture` 修正器 | 写入 `state.modifiers` 后永远沉默 | `GetModifierValue(state,"culture")` 接入 CI 结算 |
| `culture_action_this_turn` flag | 设置后无人读取 | 每季限 1 次文化行动的门卫 |
| 文化地图图层（`locked=true`）| 永久锁定无法激活 | 解锁，渲染各地区 CP 热力图（同控制度图层逻辑）|
| 文化顾问"免疫衰减"UI文本 | 无实现逻辑 | 满配时 CI 不衰减 + 己方控制区 CP 不衰减 |

---

#### 实现细节补全

##### 剧团数量上限

文档描述了同一地区的叠加衰减（第 2 个 +3 CP、第 3 个 +1 CP），但未明确上限硬封顶。

| 限制类型 | 值 | 依据 |
|---------|---|------|
| 单地区上限 | **最多 3 个**（第 3 个 +1 CP，再多无收益）| 叠加衰减表自然封顶 |
| 全局总上限 | **最多 8 个**（约覆盖 2–3 个完整国家）| 防止后期全地图无脑堆剧团；单局经济总成本 ≥ 1600 克朗 |

实现方式：

```lua
-- 创作剧团时的前置检查（在 CreateTroupe 中）
local function CanCreateTroupe(state)
    local total = 0
    for _, work in ipairs(state.culture.works) do
        if work.type == "theater_troupe" then total = total + 1 end
    end
    if total >= Balance.CULTURE.troupe_global_max then   -- 8
        return false, "剧团总数已达上限（" .. Balance.CULTURE.troupe_global_max .. "）"
    end
    return true
end

-- 查询某地区已有剧团数（用于叠加衰减系数计算）
local function GetTroupeCount(state, regionId)
    local count = 0
    for _, work in ipairs(state.culture.works) do
        if work.type == "theater_troupe" and work.location == regionId then
            count = count + 1
        end
    end
    return count
end

-- CP 叠加衰减系数表（第 n 个剧团的系数）
local TROUPE_CP_DECAY = { 5, 3, 1 }  -- index 1/2/3 对应第1/2/3个
local function GetTroupeCP(state, regionId)
    local n = GetTroupeCount(state, regionId)
    return TROUPE_CP_DECAY[math.min(n, 3)] or 0
end
```

##### 作品存储上限（`state.culture.works` 列表）

各类作品的存储上限汇总：

| 作品类型 | 存储方式 | 上限 | 说明 |
|---------|---------|------|------|
| 歌舞剧团（theater_troupe）| 每个实体一条记录（含 `location` 字段）| **全局 8 个**（见上节）| 迁移不增减条数 |
| 电影（film）| 每部一条记录（含 `theme` 字段）| **最多 3 部**（三大主题：历史/民族/工业，主题不重复）| 主题唯一性由 `work.theme` 判断 |
| 民族史诗（national_epic）| 每部一条记录（含 `theme` 字段）| **最多 3 部**（三大主题：民族/宗教/历史，主题不重复）| 主题唯一性同上 |
| 体育赛事（sports_event）| 仅记录冷却状态，不持久存储作品 | **无限次**（受 4 季冷却约束）| 用 `culture.sports_cooldown` 单独记录 |
| 世界博览会（grand_exhibition）| 全局 flag，不存入 works 列表 | **每局 1 次**（用 `culture.exhibition_done = true` 标记）| — |

`state.culture.works` 理论最大记录数：**8 + 3 + 3 = 14 条**。

##### AI 的 culture_score 算法

胜利条件第 4 条"己方 `culture_score` 领先**最强 AI** >= 500 分"需要 AI 同样有 `culture_score` 积累。AI 使用**简化无需 CI/作品系统的被动公式**：

```lua
-- turn_engine.lua Phase 结算末尾（和 AI victory 积分同位置）
-- 遍历所有活跃 AI 派系
for _, faction in ipairs(state.factions or {}) do
    if not faction.is_player and not faction.defeated then
        faction.culture_score = faction.culture_score or 0

        -- AI culture_score 每季增量：按战力和经济基础被动积累
        -- 战力(0-100) / 25 → 0-4 pt/季；经济力(0-100) / 50 → 0-2 pt/季
        local power   = faction.power   or 0
        local economy = faction.economy or 0
        local aiGain  = math.floor(power / 25) + math.floor(economy / 50)

        -- 封顶：AI culture_score 最高不超过 power × 8
        -- （全强派系约 800 分，确保玩家努力即可超越）
        local cap = math.floor(power * 8)
        faction.culture_score = math.min(cap, faction.culture_score + aiGain)
    end
end
```

**设计意图**：

| 场景 | AI 每季增量 | 全程（120 季）上限 |
|------|-----------|----------------|
| 弱派系（power=20, economy=20）| +0 pt | 160 pt |
| 中等派系（power=50, economy=50）| +3 pt | 400 pt |
| 强派系（power=80, economy=70）| +4 pt | 640 pt |

玩家只要有 2 个认同地区 + 持续使团，每季可获 10–20 pt，120 季能达 1200–2400 pt。即使面对最强 AI（上限 640 pt），领先 500 pt 的目标是可实现但需持续投入的。

**读取最强 AI culture_score**（在 CheckVictory 中）：

```lua
local function GetStrongestAICultureScore(state)
    local max = 0
    for _, faction in ipairs(state.factions or {}) do
        if not faction.is_player and not faction.defeated then
            max = math.max(max, faction.culture_score or 0)
        end
    end
    return max
end

-- CheckVictory 片段
local playerScore  = state.culture and state.culture.score or 0
local strongestAI  = GetStrongestAICultureScore(state)
local cultureWin   = (playerScore - strongestAI) >= Balance.CULTURE.victory_score_lead  -- 500
```

---

#### 涉及文件

| 文件 | 改动内容 |
|------|---------|
| `game_state.lua` | `CreateNew` 中新增 `culture = { ci = 0, works = {}, region_cp = {}, sports_cooldown = 0, exhibition_done = false, score = 0, missions = {} }` 子状态；AI 派系初始化时新增 `culture_score = 0`；`CheckVictory` 中加入文化胜利判断（含 `GetStrongestAICultureScore`）|
| `systems/turn_engine.lua` | Phase 结算新增 CI 产出计算（读取 D线科技、region.culture、文化顾问 bonus、修正器）；CP 自然衰减；culture_score 累积 |
| `data/balance.lua` | 新增 `Balance.CULTURE` 系列常量（CI衰减率、CP等级阈值、各作品成本；`troupe_global_max = 8`、`victory_score_lead = 500`）|
| `data/events_data.lua` | `culture` 修正器的两条事件（第714/1685行）调整为有效触发（增加 CI 而非写入无用修正器）|
| `ui/ui_world.lua` 或新增 `ui/ui_culture.lua` | 文化作品管理面板（当前 CI 值、作品列表、创作/部署操作）|
| `ui/ui_map_widget.lua` | 文化图层 `locked = false`，渲染逻辑接入 `region_cp` 数据 |
| `utils/save_load.lua` | 序列化/反序列化新增 `state.culture` 子状态 |

---

#### 海外文化使团（Cultural Mission）

**定位**：文化路线的"主动进攻"手段，与军事远征平行——花费 CI 对指定外国地区发动集中文化攻势，快速拉高目标地区 CP。被动作品系统负责"维持已有阵地"，文化使团负责"突破新地区"。

**核心差异化**：使团目标**不需要与己方地区相邻**，可以跨越多个国家影响维也纳、贝尔格莱德等战略目标，这是军队和商队做不到的事；同时侵略度为零，是文化路线的专属优势。

---

##### 发起条件

| 条件 | 值 |
|------|---|
| 最低 CI 储量 | 60（发起时一次性消耗 80 CI）|
| AP 消耗 | 1 AP |
| 文化顾问 bonus | ≥ 0.5（需要"良好"级以上顾问在岗）|
| 目标地区限制 | 未被己方军事占领的任意外国地区 |
| 最大并发数 | 2 条（同时可运行 2 个使团）|
| 与军事远征互斥？ | **否**——可对同一目标同时进行文化使团和军事远征 |

---

##### 每季结算

```
每季维持消耗：10 CI/季（CI 不足则使团自动暂停，不消耗也不推进）
每季 CP 增量：基础 12 CP
    + 文化顾问 bonus × 4（良好+4，满配+8）
    + 已派驻剧团加成：目标地区有驻扎剧团 → 额外 +3 CP（文化协同）
    + 已出版史诗数量 × 1 CP（历史积淀加成）
```

**实际每季 CP 范围**：

| 顾问状态 | 无协同 | 有剧团+2部史诗 |
|---------|-------|-------------|
| 无顾问（不可发起）| — | — |
| 良好（0.5）| +14 CP | +19 CP |
| 满配（1.0）| +18 CP | +23 CP |

**对比**：被动剧团 +5 CP/季，文化使团约 3-4 倍速，是真正的"文化攻势"。

---

##### 使团期间事件（每季 20% 触发，每条使团 3 季冷却）

| 事件 | 触发条件 | 选项 A | 选项 B（代价）|
|------|---------|--------|-------------|
| **当地官员施压禁演** | 随机 | 花 50 情报打通关节（无影响）| 忍受：本季 CP +0，使团损失 1 季推进 |
| **演出引发共鸣** | 目标地区 CP ≥ 30 后 | 追加场次（消耗 20 CI）：本季 +8 额外 CP | 正常结束 |
| **对手派系渗透使团** | 存在敌对 AI 势力于目标地区 | 花 80 克朗清查（无影响）| 忽视：本季 CI 产出 -5（使团被"挖角"）|
| **目标政府邀请官方访问** | 目标地区 CP ≥ 50 | 接受：使团结束时 AI 好感 +15 | 婉拒：无影响 |
| **本地艺术家加入使团** | 随机 | 吸纳：使团剩余持续时间内每季 +3 CP | 礼貌谢绝 |

---

##### 使团结束

使团**没有"失败"状态**——目标是 CP 积累，不是二元胜负。结束方式：

| 结束原因 | 结果 |
|---------|------|
| 持续 6 季后自然结束 | CP 已积累，效果保留 |
| 玩家主动撤回（1 AP）| CP 保留，已消耗 CI 不退还 |
| CI 连续 2 季不足 | 使团自动暂停（状态保留，补充 CI 后可续接）|
| 目标地区被己方军事占领 | 使团提前结束，CP 转为控制度加成（+10 控制度）|

---

##### 与作品系统的分工和联动

```
被动作品（剧团/史诗/电影）
    └─ 维持已有 CP，防止衰减
    └─ 让己方地区和邻近地区持续稳固

海外文化使团
    └─ 集中资源快速突破特定目标地区
    └─ 3-4 倍速于被动扩散，但持续消耗 CI

配合打法示例（冲"文化认同"胜利条件）：
1. 用史诗 + 剧团把邻近地区 CP 慢推到 40-50（倾慕区间）
2. 发起文化使团集中推至 70+（认同），CI 连续 4 季即可完成
3. 收获认同地区反向 CI 收益（+1/季），滚动推进下一个目标
```

---

##### 对 AI 的文化压制（AI 发起文化使团）

AI 对手同样可以对玩家控制区发起文化使团（简化版，无事件）：
- 触发条件：AI `faction.power ≥ 40`，且对玩家好感 ≤ -20
- 效果：玩家该地区 CP **-3/季**（抵消玩家史诗的 +2 被动增益）
- 玩家应对：提高该地区驻扎剧团密度（叠加CP覆盖），或发动外交行动（C4-2 外交谈判 +20 好感打断）

---

##### 使团涉及文件（追加）

| 文件 | 改动内容 |
|------|---------|
| `game_state.lua` | `culture` 子状态新增 `missions = {}` 列表；新增 `LaunchMission` / `TickMission` / `RecallMission` 辅助函数 |
| `systems/turn_engine.lua` | Phase 结算中遍历 `state.culture.missions`，执行每季 CP 增量和 CI 消耗；CI 不足时标记 `paused` |
| `data/events_data.lua` | 新增 5 条文化使团专属事件（type = "culture_mission_event"）|
| `data/balance.lua` | `Balance.CULTURE` 中补充使团常量（`mission_launch_ci`、`mission_maintain_ci`、`mission_base_cp`、`mission_max_count`、`mission_event_chance`）|
| `ui/ui_culture.lua` | 使团列表区块：显示活跃使团目标、进度（已积累CP/目标CP等级）、剩余季数、事件提示；"发起使团"入口按钮 |

---

### C4. AI 对手重设计

**目标**：让 AI 在全程（尤其是 1930 年之后）保持真实威胁感，而不是变成可以无视的背景噪音。

#### 当前核心问题清单

| # | 问题 | 根因 |
|---|------|------|
| 1 | 后期 AI 经济冻结 | 现金上限硬编码，超出部分静默丢弃 |
| 2 | 后期 AI 战力无竞争力 | 战力上限 100，不随年代/难度伸展 |
| 3 | 后期全员永久仇恨 | 态度负向 -5/季 vs 正向 +1/季，净 -4；正向上限锁死在 60 |
| 4 | 压制行动选错目标 | 选目标函数用"AI 扩张评分"而非"玩家控制度最高区" |
| 5 | 花钱无统筹，可能一季爆花 | 5 种行动全部独立判定，无预算保留逻辑 |
| 6 | 崩溃后无条件复活 | 固定注入 400 现金 + 20 战力，与玩家压制程度无关 |
| 7 | 攻击频率不随年代升级 | `ai_attack_chance = 0.35` 是全程常数 |

---

#### 修复方案 C4-1：资源上限年代化

将现金上限和战力上限改为随**游戏年代**和**难度系数**动态计算，彻底解决 AI 后期"越来越弱"的根本原因。

**现金上限新公式：**

```
era_cash_mult = {
    [1878] = 1.0,   -- 第一章
    [1904] = 1.3,   -- 第二章
    [1914] = 1.6,   -- 战时
    [1919] = 2.0,   -- 第三章
    [1935] = 2.6,   -- 第四章前夕
    [1941] = 3.2,   -- 战时高峰
    [1946] = 2.8,   -- 战后（略降，反映重建期）
}

local_clan.cash_cap    = 8000  × era_mult × diff.ai_cash_cap_mult
foreign_capital.cash_cap = 12000 × era_mult × diff.ai_cash_cap_mult
```

在最终章（1946+），本地派系上限可达 22,400，外国势力上限可达 33,600，与玩家规模保持相对对称。

**战力上限新公式：**

```
base_power_cap = 100
era_power_bonus = floor((current_year - 1878) / 10) × 5
-- 每 10 年增加 5 点上限，1945 年额外 +33，即上限 133

war_power_cap = base_power_cap + era_power_bonus + 20  -- 战时额外 +20
```

**涉及文件：**

| 文件 | 改动 |
|------|------|
| `data/balance.lua` | `Balance.AI` 中拆分 era 上限表；删除旧的静态 `cash_cap` 和 `power_cap` |
| `systems/turn_engine.lua` | Phase B/C 中从 `Balance.AI.GetEraCapMultiplier(state)` 读取动态上限 |

---

#### 修复方案 C4-2：态度系统重平衡

核心改动：**拆分"结构性敌意"与"可调节敌意"**，给玩家保留一条通过外交维系局部和平的实际路径。

**负向触发改为分层：**

```
-- 层 1：结构性（不可避免，随玩家成功自动触发）
  经济嫉妒（玩家现金 > AI 1.5×）  → -2/季（原 -3，降低）
  势力扩张（玩家矿山 ≥ 5）         → -1/季（不变）

-- 层 2：行为性（AI 被激怒，玩家行为导致）
  AI 遭受战败                       → -10（一次性，已有）
  玩家占领 AI 势力范围内的国家       → -8（一次性，新增）
  玩家发动制裁/操控事件             → -5（一次性，新增）

-- 层 3：自傲（AI 自身强大时的傲慢，已有但改值）
  faction.power ≥ 80               → -1/季（原触发条件 ≥60，提高阈值）
```

**正向上限解锁：**

```
正向上限从 60 提高到 80
新增：外交谈判行动（消耗 1 AP + 情报 × 20）
  → 一次性 attitude +20（每 8 季冷却）
  → 可以真正"维持"局部中立，但无法逆转结构性敌意
新增：联姻/联盟称号加成
  → 特定称号解锁后，对 local_clan 的态度下限提高至 -30（不会无限跌）
```

**涉及文件：**

| 文件 | 改动 |
|------|------|
| `data/balance.lua` | `Balance.AI.attitude_*` 系列数值调整 |
| `systems/turn_engine.lua` | Phase E 态度计算拆分为三层；新增外交谈判 action 入口 |
| `ui/ui_world.lua` 或外交面板 | 新增"外交谈判"按钮 |

---

#### 修复方案 C4-3：AI 行动决策升级

**压制目标修正：**

将 `PickAIExpansionRegion`（选 AI 最适合扩张的区域）改为压制时专用的 `PickAISuppressRegion`：

```lua
function PickAISuppressRegion(state, faction)
    -- 选玩家控制度最高 AND AI presence > 0 的区域
    -- 优先级：control ≥ 70 的区域（玩家核心区）
    local best, bestScore = nil, -1
    for _, region in ipairs(state.regions) do
        local playerControl = region.control or 0
        local aiPresence = (region.faction_presence or {})[faction.id] or 0
        if aiPresence > 0 and playerControl > bestScore then
            best = region
            bestScore = playerControl
        end
    end
    return best
end
```

**花钱预算保留：**

在五种行动判定前，先计算**本季预算上限** = `faction.cash × 0.6`（保留 40% 现金不花）。所有行动按优先级顺序判定，累计花费达到上限后停止后续判定。

优先级顺序：
1. 雇佣兵（power 太低时优先补强）
2. 区域压制（有战略价值）
3. 经济制裁（对玩家经济施压）
4. 矿价打压（仅 foreign_capital）
5. 通胀操控（最激进，最后判定）

**涉及文件：**

| 文件 | 改动 |
|------|------|
| `systems/turn_engine.lua` | Phase D 前计算 `budget_cap`；5 种行动改为顺序判定；新增 `PickAISuppressRegion` |

---

#### 修复方案 C4-4：攻击频率年代化 + 崩溃惩罚

**攻击频率随年代升级（反映局势越来越紧张）：**

```lua
local yearBonus = math.max(0, (state.year - 1910) / 100)
-- 1910 年：+0；1935 年：+0.25；1955 年：+0.45
local attackChance = BC.ai_attack_chance + yearBonus  -- 基础 0.35，最高约 0.80
attackChance = math.min(BC.ai_attack_chance_cap, attackChance)  -- 上限 0.75
```

攻击后增加**冷却**（2 季内不再对同一玩家攻击），防止无限连打：

```lua
faction.attack_cooldown = 2  -- 触发攻击后设置
-- Phase A 起始：attack_cooldown > 0 时跳过攻击判定，cooldown -= 1
```

**崩溃惩罚正比于被打程度：**

```lua
-- 崩溃复活时，注入资源与"被清零时的残余"挂钩
local recoveryMult = math.max(0.3, faction.pre_collapse_power / 100)
faction.cash  = floor(400 * recoveryMult)   -- 被打越惨，复活越弱
faction.power = floor(20  * recoveryMult)   -- 最低保证 6 power
```

同时，如果玩家在崩溃期间对该派系所在区域保持高控制度（≥ 60），崩溃恢复时间从 6 季延长至 9 季。

**涉及文件：**

| 文件 | 改动 |
|------|------|
| `systems/combat.lua` | `ResolveAIActions` 中加入年代攻击系数和冷却检查 |
| `systems/turn_engine.lua` | Phase A 加入冷却递减；Phase 崩溃恢复逻辑加入资源比例计算 |
| `data/balance.lua` | 新增 `Balance.COMBAT.ai_attack_year_scale`、`ai_attack_cooldown`、`ai_attack_chance_cap` |

---

#### AI 重设计影响评估

| 修复项 | 改动规模 | 预期效果 |
|--------|---------|---------|
| C4-1 资源上限年代化 | 小（数值+2处逻辑）| 消除"后期 AI 越打越弱"根本原因 |
| C4-2 态度系统重平衡 | 中（拆分逻辑+新 UI 入口）| 外交路线有实际价值；后期不再必然全员仇恨 |
| C4-3 行动决策升级 | 小（新增函数+预算逻辑）| 压制真正威胁玩家核心区；AI 花钱更理性 |
| C4-4 攻击频率+崩溃 | 小（数值+3处逻辑）| 后期压力持续升级；彻底打崩 AI 有实际意义 |

**C4 可以完全独立于其他 C 级方案提前实施**，且不新增任何 UI 组件（C4-2 的外交谈判按钮除外），是风险最低的系统级改动。

---

## 整体架构影响评估

| 方案 | 新文件 | 修改文件 | 新 UI 组件 | 风险等级 |
|------|--------|---------|-----------|---------|
| A1 远征事件 | 0（复用 events_data）| 2 | 0 | 低 |
| A2 占领发展策略 | 0 | 3 | 1（策略选择 UI）| 低-中 |
| A3 商业渗透中间决策 | 0 | 2 | 0 | 低 |
| A4 岗位专精效果 | 0 | 2 | 0 | 低 |
| C1 联合远征 | 0 | 3 | 1（战略态势提示）| 中 |
| C2 外交路线 | 0 | 4 | 1（外交标签页）| 高 |
| C3 大国博弈 | 0 | 3 | 1（博弈操作区）| 中-高 |
| **C4-1** AI 资源上限年代化 | 0 | 2 | 0 | **低** |
| **C4-2** AI 态度重平衡 | 0 | 3 | 1（外交谈判按钮）| 低-中 |
| **C4-3** AI 行动决策升级 | 0 | 1 | 0 | **低** |
| **C4-4** AI 攻击频率+崩溃 | 0 | 3 | 0 | **低** |
| **C5** 文化胜利路线 | 1（ui_culture.lua）| 7 | 1（文化作品面板含使团区块）+ 文化地图图层解锁 | 中 |

---

## 建议实施顺序

**第一批（数值调整为主，立竿见影）**：
1. C4-1 AI 资源上限年代化 — 纯数值改动，直接解决 AI 后期失效根本原因
2. C4-3 AI 行动决策升级 — 压制选对目标 + 花钱预算保留，逻辑改动最小
3. C4-4 AI 攻击频率+崩溃惩罚 — 让后期持续有压力，打崩 AI 有真实意义

**第二批（体验改善，玩家侧感知最强）**：
4. A1 远征过程事件 — 直接消除远征空洞等待感
5. A4 岗位专精效果 — 让家族系统"值得用"
6. C4-2 AI 态度重平衡 — 外交路线有实际意义，后期不再必然全员仇恨

**第三批（系统深度）**：
7. A2 占领后发展策略 — 占领后多一层运营决策
8. A3 商业渗透中间决策 — 补齐商业路线的空洞等待
9. C1 联合远征 — 战略地理变得重要

**第四批（新赛道，工作量最大）**：
10. C2 外交路线 — 完整非战争扩张路径
11. C3 大国博弈 — 幕后政治感，需要大国系统配合
12. C5 文化胜利路线 — 接通五处废弃管道；五种被动作品系统 + 海外文化使团（主动进攻）；第三条胜利路线

---

*最后更新：2026-05-22*
