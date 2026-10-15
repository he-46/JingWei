# 表现层接口（ART-01 建立，ART-02～07 扩展）

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

## 海岸与环境：Coast / World

`coast_geometry.gd` 只读网格状态，提供 `beach_width`、`coast_mesh`、`cell_height`、`corner_height`、`corner_normal`、`cell_triangles`、`water_segment` 和 `foam_strip`。海面固定 0.16，海岸端点固定 x=0/y=0.22；海格中心仍使用原填充比例到高度的映射。其他角点从全局相邻格取得，法线也按全局坐标计算，不依赖某区块已有的网格。

world 按既有 dirty 数据更新投放位置周围两格涉及的区块，重建石质表面及其真实接水线。泡沫只在三角形穿过海面时生成，已消失的接水线清空网格并隐藏节点，最多保留每区块一个泡沫节点。原大陆海岸使用独立连续泡沫带，新陆地盖上后由正常深度测试遮住旧内岸线；不以效果修改海格类型或填充需求。

植被和岸石采用共享 MultiMesh，根位置由有限次数采样确定，避开山址与资源/未来工作位；没有逐棵动画脚本、刚体或采集能力。water_material、foam_material、foliage_material 为每世界独立实例，雾材质也各自创建；world.animate 同步 wave_time、wind_time、fog_time。暂停时不推进，换世界释放；全图隐藏草和灌木，返回恢复原实例。ShaderMaterial 图集与静态几何资源继续复用。

## 时序、暂停与存档

- `main.interact` 结算成功 → `play_gather` → 原采集音效 → 刷新负重。
- `main.deposit_at` 校验并结算 → `play_throw` → 效果池投射物与音效 → 刷新负重。投射物仍用 0.48 秒时序；正式投石动作对齐该时序，不反向决定扣库存时机。
- `main._advance_world` 调用 state.tick → 完工展示 → 原开山/神器音效。拒绝的操作不发送动作事件。
- AnimationPlayer 使用手动推进，world.animate 不调用时角色动作停止。ART-06 用效果池替换投射物 Tween；主场景只在未暂停且已选地图时推进效果与落点音时钟。
- 动画不使用方法轨道调用游戏逻辑。以后增加声音/粒子帧事件只能作用于表现对象，需避免与 main 的现有音效重复。
- `choose_world` 销毁旧 world，动作和骨骼随实例销毁；新世界重新应用预制场景配置。表现状态不进入存档，SAVE_VERSION 继续为 3。

验证入口为 `tests/test_visuals.gd`；`tests/test_game.gd -- --qa --imported-visuals` 在同一套玩法检查中使用导入模型。真实 GLB 含骨骼与动作，且没有 `WingLeft` / `WingRight` / `Load` 节点，能直接检验旧节点依赖是否已解除。

## 事件反馈：ActionFeedback

`scripts/visuals/action_feedback.gd` 不持有状态对象。main 仅在结算成功后发送 `burst(kind, point, target, radius)`、`throw_stone(start, end, sea, formed, completed, audio_epoch)` 和 `discover(id, point)`。采集位置来自实际散石、碎石场或落地石堆；发现模型展示在对应山体外侧上方，不改变碰撞。

`main._process` 在未暂停的每帧调用一次 `advance(delta)`。0.48 秒时发出 `landed`，main 比较起投时的音频 epoch 后播放落点、成陆或完成音。新建爆发只推进落点后的剩余帧时间，避免低帧率下提前老化。静音只关闭音频，画面继续；静音再开启不会补播旧落点。

每世界固定 12 个飞石、24 个爆发（每个一圈与一个 8 实例 MultiMesh）及三个神器模型；不创建逐事件 Tween、计时器、刚体或节点。爆发满额替换最旧槽；飞石满额省略普通新效果，成陆可替换普通飞石，最终完成优先替换非完成飞石。被省略的落点声音也不补播，资源结算保持完整。三件神器各复用一槽，2.2 秒内升起、旋转、缩小；不弹出强制模态面板。换图时随旧 world 一并释放，新存档加载不重放已发现神器。详情、事件表和复现方法见 [ART-06 交付](deliveries/ART-06.md)。

## ART-07 定位与边界投影

world生成植被时保留最多200个近似树冠球包络。`player_occluded()` 通过排除鸟自身的真实山体碰撞射线和树冠包络，检查鸟身体中心附近的视线；`update_player_locator(delta)` 以0.1秒间隔更新结果，投影位置逐物理帧更新。HUD的 `locate_player(point, obscured)` 只显示一个忽略鼠标输入的小菱形；模态/全图立即隐藏，换图重建缓存。此功能只辅助定位，不提供逐像素遮挡掩码，不修改碰撞或角色材质。

雾顶点沿正交相机视线投到 y=0.2 的近地参考平面，再把其XZ交给原范围/噪声计算。三层雾仍使用原模拟时钟，范围外继续遮挡；修正的是高层平面斜视时的屏幕偏移。实际图形检查比较同一内侧水点与范围外水点在雾开关前后的像素。

Sample入口在super._ready之前关闭保存，使用固定初始状态，且手动保存只解释本次运行不保存；启动器隔离APPDATA。验证器放置有效旧旅程文件并逐字节检查样板启动、手动保存与重选地图均不改原文件。完整实机与源复制记录见ART-07评审。
