# 装备与编队系统设计方案

## 一、核心概念

将现有的"护卫人数"系统升级为 **编队 + 装备** 双层结构：

```
旧系统: guards(数量) × equipment(全局等级1-5) × morale → 战力
新系统: Σ(squad.power) + unassigned×0.6 → 基础战力 × morale × tech × chief → 总战力
        其中 squad.power = size × veterancy_mul × equipment.power_mul
```

---

## 二、编队系统 (Squad)

### 数据结构

```lua
state.military = {
    guards = 15,          -- 总护卫人口（不变）
    morale = 70,          -- 士气（不变）
    wage = 12,            -- 基础工资（不变）
    supply = 20,          -- 补给（不变）
    -- ↓ 新增 ↓
    squads = {
        { id = 1, name = "第一大队", size = 5, equip_id = "rifle", veterancy = 1, condition = 100 },
        { id = 2, name = "第二大队", size = 4, equip_id = "mg",    veterancy = 0, condition = 85 },
    },
    factory = nil,         -- 兵工厂（nil = 未建造）
    production_queue = {}, -- 生产队列
    outsource_slots = {},  -- 代工槽位
}
```

### 编队规则

| 参数 | 值 | 说明 |
|------|-----|------|
| 每队最小人数 | 3 | 低于 3 人自动解散回归未编队 |
| 每队最大人数 | 8 | 最多 8 人 |
| 最大编队数 | 6 | 玩家最多 6 个编队 |
| 未编队护卫战力系数 | 0.6 | 没编入队伍的护卫只有 60% 战力 |

### 老兵等级 (Veterancy)

| 等级 | 名称 | 战力加成 | 获得方式 |
|------|------|---------|---------|
| 0 | 新兵 | ×1.0 | 初始 |
| 1 | 老兵 | ×1.15 | 参与 2 次战斗 |
| 2 | 精锐 | ×1.30 | 参与 5 次战斗 |
| 3 | 王牌 | ×1.50 | 参与 10 次战斗 |

---

## 三、装备目录 (Equipment Catalog)

### 6 级装备体系

| 等级 | ID | 名称 | 战力倍率 | 生产回合 | 生产成本 | 维护/季 | 解锁科技 |
|------|-----|------|---------|---------|---------|--------|---------|
| T1 | rifle | 步枪 | ×1.0 | - | - | 5 | 初始 |
| T2 | improved_rifle | 改良步枪 | ×1.4 | 2 | 120 | 8 | c1(步枪改良) |
| T3 | mg | 机枪 | ×1.8 | 3 | 250 | 15 | c3(机枪) |
| T4 | mortar | 迫击炮 | ×2.3 | 4 | 400 | 22 | c4a/c4b |
| T5 | motorized | 机动装备 | ×3.0 | 5 | 650 | 35 | c5(摩托化) |
| T6 | elite_kit | 精锐套件 | ×4.0 | 6 | 1000 | 50 | c7(精锐) |

- T1 步枪为默认装备，不需要生产，新编队自动持有
- 每件装备只供一个编队使用（一队一装备）
- 装备有耐久度 condition（0-100），每次战斗 -10~-20，低于 30 战力打折，到 0 则损毁

### 装备耐久对战力影响

| condition 范围 | 效果 |
|---------------|------|
| 100-60 | 满战力 |
| 59-30 | 战力 ×0.7 |
| 29-1 | 战力 ×0.4 |
| 0 | 装备损毁，退回 T1 步枪 |

---

## 四、生产系统

### 4.1 兵工厂 (Arms Factory)

需要建造，占用 1 个建筑位。

| 等级 | 建造费用 | 建造时间 | 生产槽位 | 维护/季 | 解锁 |
|------|---------|---------|---------|--------|------|
| Lv1 | 500 | 4 季 | 1 | 30 | 初始可建 |
| Lv2 | 800 | 3 季 | 2 | 50 | 工业化科技 |
| Lv3 | 1200 | 3 季 | 3 | 80 | 重工业科技 |

- 生产槽同时只能生产 1 件装备（每槽）
- 升级期间现有槽位正常工作

### 4.2 代工 (Outsourcing)

不需要兵工厂，随时可用，但更贵更慢。

| 参数 | 值 |
|------|-----|
| 同时代工上限 | 2 件 |
| 成本加成 | +60% |
| 时间加成 | +1 季 |
| 可用条件 | 任何时候（不需要兵工厂） |

### 4.3 生产队列数据结构

```lua
-- 兵工厂生产
state.military.production_queue = {
    { equip_id = "mg", progress = 1, total = 3, source = "factory" },
}
-- 代工
state.military.outsource_slots = {
    { equip_id = "mortar", progress = 2, total = 5, source = "outsource" },
}
```

### 4.4 维修系统

- 在兵工厂中可以维修装备（占用 1 个生产槽位）
- 维修时间：1 季恢复 40 耐久
- 维修费用：装备生产成本的 20%

---

## 五、战力公式重写

### 新公式

```lua
function Combat.PlayerPower(state)
    local m = state.military
    local totalPower = 0

    -- 编队战力
    for _, squad in ipairs(m.squads or {}) do
        local equipData = EquipmentCatalog[squad.equip_id]
        local veterancyMul = VETERANCY_TABLE[squad.veterancy]
        local conditionMul = getConditionMul(squad.condition)
        local squadPower = squad.size * equipData.power_mul * veterancyMul * conditionMul
        totalPower = totalPower + squadPower
    end

    -- 未编队护卫（60% 效率，T1 装备）
    local assignedGuards = 0
    for _, sq in ipairs(m.squads or {}) do assignedGuards = assignedGuards + sq.size end
    local unassigned = math.max(0, m.guards - assignedGuards)
    totalPower = totalPower + unassigned * 0.6

    -- 全局系数（不变）
    local moraleMul = math.max(0.3, m.morale * BMI.morale_multiplier)
    local chiefBonus = GameState.GetPositionBonus(state, "military_chief")
    local techBonus = state.guard_power_tech_bonus or 0
    return totalPower * moraleMul * (1 + chiefBonus) * (1 + techBonus)
end
```

### 与旧公式对比

| | 旧 | 新 |
|--|---|---|
| 基础 | guards × 1.0 | Σ(squad.power) + unassigned×0.6 |
| 装备 | 全局 equipment×0.15 | 每队独立 equip.power_mul |
| 老兵 | 无 | veterancy ×1.0~1.5 |
| 耐久 | 无 | condition 影响战力 |
| morale/tech/chief | 不变 | 不变 |

---

## 六、经济影响

### 新增费用项

| 费用项 | 计算方式 | 典型值(中期) |
|--------|---------|-------------|
| 装备维护 | Σ(equip.maintenance) | 60-90/季 |
| 兵工厂维护 | factory.level 对应值 | 30-50/季 |
| 代工费 | 仅生产时支付 | 一次性 |

### 经济平衡目标

- 中期(年4-6)军费占比：从现在的 ~20% → ~30%
- T3-T4 装备是性价比甜区（大多数玩家停留在此）
- T5-T6 是"烧钱"装备，适合经济强势玩家

---

## 七、科技树修改

将现有 equipment_up 效果改为 equipment_unlock：

| 科技 | 旧效果 | 新效果 |
|------|--------|--------|
| c1 步枪改良 | equipment +1 | 解锁 T2 improved_rifle |
| c3 机枪 | +15% power, equipment +1 | 解锁 T3 mg |
| c4a 防御工事 | +20% defense | 解锁 T4 mortar + 防御加成 |
| c4b 突击战术 | +25% attack | 解锁 T4 mortar + 攻击加成 |
| c5 摩托化 | equipment +1, supply -1 | 解锁 T5 motorized, supply -1 |
| c7 精锐 | +40% power | 解锁 T6 elite_kit |

新增可选科技节点：
- **兵工业**(b线工业支线): 解锁兵工厂 Lv2
- **重工业**(b线工业支线): 解锁兵工厂 Lv3

---

## 八、胜利分修改（方案B：收紧系数）

```lua
-- 旧：guard_multiplier = 0.3，无装备分
-- 新（方案B）：
guard_multiplier = 0.25  -- 略降，因为装备分补充
equipScore = min(4, Σ(equip.tier - 1) × 0.8)   -- 装备分上限 4，系数 0.8
veterancyScore = min(2, 王牌编队数)              -- 老兵分上限 2，系数 1
-- 中期增量 ~20/季（vs 旧18），晚期 ~24/季（vs 旧20），124季累计 ~2500，阈值 2000 可达但需投入
```

---

## 九、UI 变化

### 军事面板 (ui_military.lua) 改造

```
┌─ 军事总览 ─────────────────────────────┐
│ 总战力: 45.2  护卫: 15  士气: 70       │
│ 军费: 285/季 (工资150+补给60+维护75)    │
├─ 编队列表 ──────────────────────────────┤
│ [1] 第一大队  5人  机枪(T3)  精锐  ██████░ 85% │
│ [2] 第二大队  4人  步枪(T1)  新兵  ██████████ 100% │
│ 未编队: 6人 (60%效率)                   │
├─ 操作 ─────────────────────────────────┤
│ [编组] [装备] [生产] [维修] [招募] [解散] │
└─────────────────────────────────────────┘
```

### 新增弹窗

1. **编组弹窗**: 创建/解散编队，分配人员
2. **装备弹窗**: 为编队分配已有装备
3. **生产弹窗**: 选择装备→选择生产方式(工厂/代工)→确认
4. **维修弹窗**: 选择损坏装备→维修

---

## 十、存档迁移

```lua
-- save_load.lua 中添加迁移逻辑
if not state.military.squads then
    -- 旧存档：所有护卫编为一队，装备等级映射到新装备
    local equipMap = { [1]="rifle", [2]="improved_rifle", [3]="mg", [4]="mortar", [5]="motorized" }
    state.military.squads = {
        { id=1, name="第一大队", size=state.military.guards,
          equip_id=equipMap[state.military.equipment] or "rifle",
          veterancy=0, condition=100 }
    }
    state.military.factory = nil
    state.military.production_queue = {}
    state.military.outsource_slots = {}
end
```

---

## 十一、实现文件清单

### 新建文件 (3个)

| 文件 | 内容 | 预估行数 |
|------|------|---------|
| scripts/data/equipment_data.lua | 装备目录、老兵表、耐久表、工厂配置 | ~120 |
| scripts/systems/equipment.lua | 编队管理、生产推进、维修、耐久衰减 | ~250 |
| scripts/ui/ui_equipment_modals.lua | 编组/装备/生产/维修弹窗 | ~350 |

### 修改文件 (9个)

| 文件 | 修改内容 |
|------|---------|
| scripts/data/balance.lua | 添加 SQUAD/FACTORY 参数块 |
| scripts/data/tech_data.lua | equipment_up → equipment_unlock，新增兵工业节点 |
| scripts/game_state.lua | military 初始状态添加 squads/factory/queue 字段 |
| scripts/systems/combat.lua | PlayerPower() 重写为编队聚合公式 |
| scripts/systems/economy.lua | 添加装备维护+工厂维护费用 |
| scripts/systems/turn_engine.lua | 每季推进生产队列、耐久自然衰减 |
| scripts/systems/tech.lua | 处理 equipment_unlock 效果类型 |
| scripts/ui/ui_military.lua | 编队列表展示、操作按钮 |
| scripts/utils/save_load.lua | 序列化新字段 + 旧存档迁移 |

### 实施阶段

| 阶段 | 内容 | 说明 |
|------|------|------|
| P1 | 数据层 | equipment_data.lua + balance.lua + game_state.lua |
| P2 | 编队核心 | equipment.lua（编队CRUD） + combat.lua 公式重写 |
| P3 | 生产系统 | equipment.lua（生产/维修） + turn_engine.lua 推进 |
| P4 | 经济+科技 | economy.lua 费用 + tech_data.lua + tech.lua 解锁 |
| P5 | UI + 存档 | ui_military.lua + ui_equipment_modals.lua + save_load.lua |

---

## 十二、验证方案

1. **编队测试**: 创建/解散编队，分配人员，验证人数上下限
2. **战力测试**: 对比新旧公式，确保中期(15护卫+T3装备)战力在合理范围(40-60)
3. **生产测试**: 工厂建造→生产T3→装备编队→战力提升
4. **代工测试**: 无工厂时代工T2，验证+60%成本、+1季时间
5. **耐久测试**: 多次战斗后装备耐久下降→战力打折→维修恢复
6. **经济测试**: 确认军费占比中期 ~30%，不会导致破产
7. **存档迁移**: 加载旧存档→自动生成编队→战力接近旧值
8. **科技解锁**: 研发 c3→解锁 T3 mg→可生产→装备编队
9. **构建验证**: 调用 mcp build 确保无语法/LSP 错误
