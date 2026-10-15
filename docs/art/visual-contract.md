# 表现层接口（ART-01 建立，ART-02～04 扩展）

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
| `set_work(target, active, all_done, fraction, is_unlocked=true)` | 目标山编号、是否开采、是否全部完成、当前山开采比例及解锁状态；状态只读。最后一项可省略，兼容 ART-01 示例。 |
| `set_facing(direction)` | 朝向当前山体工作面，−Z 为模型正前方；根站位仍由逻辑提供。 |
| `play_complete(completed_target)` | 逻辑 tick 确认整山完成后调用；仅记录并表现完工。 |
| `advance(delta, clock)` | 同精卫的模拟时钟。 |

ART-03 动作语义为 `idle`、`locked`、`walk`、`dig`、`finished` 循环，`complete` 单次。未解锁时选 `locked`，解锁且正在工作时选 `dig`，全部完工时选 `finished`。缺少 locked 的旧占位模型回退到 idle。

普通循环使用 0.10 秒混合。目标切换且仍在开采时，正式角色播放 0.35 秒原地入场步；完工动作持续 0.70 秒，随后进入入场步和新山的挖掘状态。两段计时依次消耗模拟时间，暂停时都停止。此移动动作不模拟两山之间的路径，根节点立即对齐新目标，生产不停顿；`use_arrival_animation` 为 false 的旧示例跳过入场步。

每个世界仅有一个表现实例，根节点随逻辑对话点更新，正面朝向 `mountain_position - npc_position`；骨骼动作不移动对话点或地图标记。一次大步长完成多座山时，沿用原音效的合并规则，只表现该步开始时的目标完工，不逐个补播，库存全部由 tick 正常结算。读档直接显示现状，不补发历史完工或入场事件。`surface_material` 为整只穿山甲设置共享鳞甲材质。

## 山体：MountainVisual.from_state

快照包含 `radius`、`height`、`remaining`、`progress`、`settled`、`stock`、`stock_fraction`、`transform`、`collision_radius` 和 `collision_height`。所有字段均为值，不向表现对象暴露资源字典引用。尺寸从 state 的 mountain_radius/height 和常量统一取得。`stage_name()` 仅提供预览中的阶段描述，不触发任何模拟事件。

world 保留 5 组共享 MultiMesh，每山 32 个上限固定的石堆实例。`mountain_scenes` 的第 0～4 项可分别替换对应轮廓；空缺继续使用原程序网格。默认第 0 项为 `strata_mountain.glb`，只替换对应山型，ART-01 占位示例显式覆盖它时继续使用诊断模型及旧材质。导入约束为单网格、地面原点、单位变换、标准化尺度。

ART-04 起开采比例变化就更新削顶面，取消原先 1/32 刷新门槛。快照中的总碰撞高度为 `height * remaining`。样板使用八层圆柱包络，半径从共享导入网格按高度区间取得并留 0.02 单位归一化余量，不超过原 0.96 山脚上限；顶部层按当前剩余高度截短，移除的层全部禁用。其他山使用单圆柱；碰撞不再保留 5% 最低高度。圆柱是保守包络，不承诺逐三角形贴合岩层凹口。

库存改变时调用 `pile_transform` 计算样板石堆位置、堆高与最多 32 组显隐；stock=0 隐藏全部资源石块，remaining=0 隐藏山体并禁用所有碰撞。`quarry_site.glb` 为无碰撞、无采集能力的低矮遗迹，最大高度为山原高度的 2.4%。开采中每样板八块装饰碎屑和全世界最多八团扬尘都不进入资源层；扬尘只随 world.animate 的模拟时钟推进，暂停不动，换图随世界释放。

样板与石堆共享一张 1024² 岩层图；正式山、石料与遗迹分别使用可复用材质。Compatibility 实例自定义颜色读回存在半精度误差，实机检查按 0.0005 的归一化绝对误差验收，碰撞仍以完整逻辑比例计算。正式雕刻或视觉重放不得改变可采库存。

## 时序、暂停与存档

- `main.interact` 结算成功 → `play_gather` → 原采集音效 → 刷新负重。
- `main.deposit_at` 校验并结算 → `play_throw` → 原投射物与音效 → 刷新负重。投射物仍用原 0.48 秒时序；正式投石动作应对齐该时序，不反向决定扣库存时机。
- `main._advance_world` 调用 state.tick → 完工展示 → 原开山/神器音效。拒绝的操作不发送动作事件。
- AnimationPlayer 使用手动推进，world.animate 不调用时角色动作停止。既有投射物 Tween 沿用原行为，本包没有更改其暂停策略。
- 动画不使用方法轨道调用游戏逻辑。以后增加声音/粒子帧事件只能作用于表现对象，需避免与 main 的现有音效重复。
- `choose_world` 销毁旧 world，动作和骨骼随实例销毁；新世界重新应用预制场景配置。表现状态不进入存档，SAVE_VERSION 继续为 3。

验证入口为 `tests/test_visuals.gd`；`tests/test_game.gd -- --qa --imported-visuals` 在同一套玩法检查中使用导入模型。真实 GLB 含骨骼与动作，且没有 `WingLeft` / `WingRight` / `Load` 节点，能直接检验旧节点依赖是否已解除。
