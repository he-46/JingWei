# 表现层接口（ART-01 建立，ART-02 扩展）

`state.gd` 管资源与尺寸，`main.gd` 判断操作并结算，`world.gd` 将已确定的状态送给表现对象。表现控制器不持有 JWState，不保存游戏，不触发采集、投石或开山结算。山体接收一次性数值快照。

## 精卫：scenes/actors/jingwei.tscn

| 接口 | 输入与行为 |
| --- | --- |
| `set_facing(direction: Vector2, delta)` | 世界 X/Z 平面方向，非零方向平滑转向；Godot −Z 为正前。 |
| `set_motion(moving, high_flight)` | 选择待机、飞行或负重飞行；高空悬停也拍翼。正式角色在转向期间选择对应左右转动作。 |
| `set_load(fraction)` | 负重/容量，钳制到 0～1；0 为空载，(0, 0.65] 为轻载，(0.65, 1] 为满载。 |
| `play_gather(amount)` | 只在采集成功后调用，amount > 0 才播放。 |
| `play_throw(amount)` | 只在投石成功、库存已扣除后调用；连投重新开始动作，旧动作可中断。 |
| `advance(delta, clock)` | 唯一动画推进入口，跟随现有模拟暂停。clock 给旧程序模型保持原有拍翼与起伏相位。 |

动作语义为 `idle`、`fly`、`carry_fly`、`gather`、`throw`，ART-02 正式模型另有 `turn_left` / `turn_right`。循环动作采用 0.09 秒交叉混合，转向额外叠加小幅平滑侧倾。采集动作持续 0.42 秒，投石持续 0.48 秒；控制器按实际导入片长调整播放速度，避免导出帧取整改变操作时序。单次结束后回到最新运动状态。动作别名通过预制场景的 `animation_names` 字典配置；缺失动作跳过播放，保留姿态，不影响玩法。正式资产验收必须检查所需动作齐全。

`cargo_path` 和 `full_cargo_path` 是模型根下轻载、满载附件的可选 Node3D 路径。正式模型为 `Rig/Skeleton3D/CargoLight` 与 `Rig/Skeleton3D/CargoFull`，两组网格随 Spine 蒙皮，同一时刻最多显示一组。没有 full_cargo_path 的 ART-01 示例继续使用旧的有载/空载显隐。world/main 不读取附件、翅膀或骨骼节点。`surface_material` 为三个网格设置同一共享材质。`replace_model(scene)` 中断当前动作，保留朝向和负重数值，恢复循环；更换层级前须同步配置附件路径。

## 穿山甲：scenes/actors/pangolin.tscn

| 接口 | 输入与行为 |
| --- | --- |
| `set_work(target, active, all_done, fraction)` | 目标山编号、是否开采、是否全部完成、当前山开采比例；状态只读。 |
| `play_complete(completed_target)` | 逻辑 tick 确认整山完成后调用；仅记录并表现完工。 |
| `advance(delta, clock)` | 同精卫的模拟时钟。 |

动作语义为 `idle`、`dig`、`finished` 循环，`complete` 单次。每个世界仅有一个表现实例，根节点随逻辑对话点更新；动画不移动对话点。一次大步长完成多座山时，沿用原音效的合并规则，只表现该步开始时的目标完工，不逐个补播，库存全部由 tick 正常结算。读档直接显示现状，不补发历史完工事件。

## 山体：MountainVisual.from_state

快照包含 `radius`、`height`、`remaining`、`stock`、`stock_fraction`、`transform`、`collision_radius` 和 `collision_height`。所有字段均为值，不向表现对象暴露资源字典引用。尺寸从 state 的 mountain_radius/height 和常量统一取得。

world 保留 5 组共享 MultiMesh，每山 32 个上限固定的石堆实例。`mountain_scenes` 的第 0～4 项可分别替换对应轮廓；空缺继续使用原程序网格。导入约束为单网格、地面原点、单位变换、标准化尺度。

开采按原有 32 段刷新预算更新削顶比例与碰撞，库存改变时刷新石堆数量；stock=0 隐藏全部石料，remaining=0 隐藏山体并禁用碰撞。比例更新保留原有分段节奏；快照中的理论碰撞高度为 `height * max(0.05, remaining)`，碰撞中心仍按原公式 `height * remaining / 2`。最终雕刻或独立坍塌模型不得改变可采库存。

## 时序、暂停与存档

- `main.interact` 结算成功 → `play_gather` → 原采集音效 → 刷新负重。
- `main.deposit_at` 校验并结算 → `play_throw` → 原投射物与音效 → 刷新负重。投射物仍用原 0.48 秒时序；正式投石动作应对齐该时序，不反向决定扣库存时机。
- `main._advance_world` 调用 state.tick → 完工展示 → 原开山/神器音效。拒绝的操作不发送动作事件。
- AnimationPlayer 使用手动推进，world.animate 不调用时角色动作停止。既有投射物 Tween 沿用原行为，本包没有更改其暂停策略。
- 动画不使用方法轨道调用游戏逻辑。以后增加声音/粒子帧事件只能作用于表现对象，需避免与 main 的现有音效重复。
- `choose_world` 销毁旧 world，动作和骨骼随实例销毁；新世界重新应用预制场景配置。表现状态不进入存档，SAVE_VERSION 继续为 3。

验证入口为 `tests/test_visuals.gd`；`tests/test_game.gd -- --qa --imported-visuals` 在同一套玩法检查中使用导入模型。真实 GLB 含骨骼与动作，且没有 `WingLeft` / `WingRight` / `Load` 节点，能直接检验旧节点依赖是否已解除。
