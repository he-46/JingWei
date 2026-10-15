# 美术资产清单与制作安排

创建日期：2026-10-14，最近更新：2026-10-15。下表区分当前实现与计划资产。

ART-01 完成导入接口和三个诊断占位模型；ART-02/03 完成精卫与穿山甲，ART-04 完成岩层山与碎石场，ART-05 完成海岸、植被、水面与灯光样板，均接入普通游戏入口。实际交付规模见下方独立清单。

| ID | 对象 | 当前实现/入口 | 计划交付 | 负责包 | 当前状态 |
| --- | --- | --- | --- | --- | --- |
| CH-01 | 精卫 | characters/jingwei.glb：连续头身喙、分组羽翼、三簇尾羽、UV 图集与蒙皮 | 连贯网格、骨骼、六类动作、负重表现 | ART-02 | 已完成，7 段动作，3 档负重，主场景已使用 |
| CH-02 | 穿山甲 | characters/pangolin.glb：连续长吻与弓背、86 片叠覆鳞甲、长尾与大爪 | 鳞甲长尾角色、四类动作 | ART-03 | 已完成，6 段动作，主场景已使用 |
| MT-01 | 样板山 | strata_mountain.glb：1,918 三角形，岩层台阶与连续削顶；配套低矮遗迹 | 一套有岩层的山体、阶段与采空遗迹 | ART-04 | 已完成，替换第 0 类山体，其余轮廓待扩展 |
| MT-02～08 | 扩展山型 | 当前按 shape=0～4 共用五份网格 | 最终合计约 6～8 型及对应开采表现 | ART-08 | 待样板定稿后扩展 |
| RS-01 | 散石 | rock_mesh() 程序生成；每资源点三块石头，用 MultiMesh 绘制 | 约六种石形、统一材质与资源辨识规范 | ART-04/08 | 原型可用，正式资产待制作 |
| RS-02 | 碎石场 | 样板每山最多 32 个 quarry_stone.glb 实例，库存降低时减少组数与堆高 | 样板库存层级，扩展为约三组组合 | ART-04/08 | 样板已完成，其他组合留待 ART-08 |
| EV-01 | 地表与沙滩 | 连续地表材质、宽窄沙滩网格、湿岸与浅水石；新陆地石质表面及接水线 | 连续海岸的局部形态变化与共享材质 | ART-05 | 样板已完成 |
| EV-02 | 树木 | coast_tree.glb：分叉树干与五簇错落树冠，共享 MultiMesh | 三种树形、远景简化 | ART-05/08 | 一型样板已完成，其余留待 ART-08 |
| EV-03 | 草与灌木 | coast_grass.glb 六叶草丛、coast_shrub.glb 三簇灌木，共用图集 | 两类草丛、两类灌木 | ART-05/08 | 各一型样板已完成，其余留待 ART-08 |
| EV-04 | 海水 | 连续深浅渐变、低强度波纹、远景细节淡出、三角形接水线泡沫 | 层次更自然的水面、泡沫与填海湿边 | ART-05 | 样板已完成 |
| EV-05 | 边界迷雾 | 三层平面噪声雾与环境统一配色，扰动主要在地图外 | 保留遮挡规则，改善边缘与场景衔接 | ART-05 | 样板已完成，保留方形范围 |
| FX-01 | 采集和投石 | main.gd/world.gd 当前程序效果及落点回调 | 可复用的采集、起手、落水、落地效果 | ART-06 | 待改善 |
| FX-02 | 开山和成陆 | 样板有装饰碎屑、最多八团工作扬尘；完工以有限石场替换 | 扬尘、局部落石、成陆反馈 | ART-04/06 | 基础工作表现已完成，完工/成陆事件强化留待 ART-06 |
| RL-01 | 神农石篓 | 状态目录与神器页文字，无独立正式 3D 资产 | 模型、图标、出土反馈 | ART-06 | 待制作 |
| RL-02 | 乘风羽 | 同上 | 模型、图标、出土反馈 | ART-06 | 待制作 |
| RL-03 | 开山印 | 同上 | 模型、图标、出土反馈 | ART-06 | 待制作 |
| UI-01 | HUD、指示环和地图 | hud.gd 简洁侧栏；world.gd 范围与落点环 | 保持信息层级，按美术整合检查对比度 | ART-06/07 | 现有版本保留 |
| AU-01 | 音效 | assets/audio 中 19 个项目工具合成 WAV | 沿用，按动作校对时序 | ART-06 | 现有版本保留 |

## 共享约定

- 先完成 CH-01、CH-02、MT-01、EV-01～05 的一个海岸样板，其他山型和植被不提前批量生产。
- 三角形、材质、纹理和骨骼预算以 style-guide.md 为初始要求，交付时增加实测列。
- 每项正式资产应记录：源文件、运行文件、作者/生成方法、纹理列表、三角形数、材质数、骨骼数、动画名、LOD、碰撞说明、许可来源、使用场景。
- 资产 ID 用于生产管理，不替换存档中的山型、神器 ID；旧档映射需要单独兼容。
- 当前视觉资产来自项目代码，外部模型/纹理引入数为 0；Godot 引擎及第三方组件许可继续由 Godot/ 下文件说明。

## ART-01 导入诊断资产

均由本项目 `art_source/build_pipeline_examples.py` 原创生成，`.blend` 在 `art_source/pipeline_examples/`，游戏文件在 `assets/models/pipeline_examples/`。无第三方模型、纹理或录音；制作工具 Blender/bpy 不随游戏分发。这些模型用于验证接口，不计入正式资产完成数。

| 文件 | 三角形 | 材质 | 骨骼 | 动作 | GLB 大小 |
| --- | --- | --- | --- | --- | --- |
| jingwei | 720 | 2 | 3 | idle、fly、carry_fly、gather、throw | 95,580 字节 |
| pangolin | 360 | 2 | 3 | idle、dig、complete、finished | 52,984 字节 |
| mountain | 22 | 0，采用共享顶点色 shader | 0 | 无 | 3,116 字节 |

三角形数来自 GLB 索引计数，动作与蒙皮来自导出清单；Godot 自动生成导入 LOD，不提供手工 LOD。角色碰撞由世界逻辑创建，GLB 内无碰撞节点；山体使用逻辑尺寸的圆柱碰撞。使用场景为 `scenes/art/pipeline_preview.tscn`，默认主场景仍采用程序模型。

## ART-02 精卫资产

| 字段 | 实际交付 |
| --- | --- |
| 源与生成方法 | `art_source/characters/jingwei.blend`、`art_source/build_jingwei.py`；本项目原创拓扑、图集绘制与动作。 |
| 游戏模型 | `assets/models/characters/jingwei.glb`，1,070,952 字节。 |
| 材质/纹理 | `assets/materials/jingwei_feather.tres`；`assets/textures/characters/jingwei_atlas.png`，1024²、698,899 字节，无额外法线或金属贴图。 |
| LOD0 三角形 | 精卫 6,912，轻载附件 648，满载附件 876；最大可见合计 7,788。 |
| 表面与骨骼 | 1 个共享材质，最多同时 2 个可见表面；12 根骨骼，每顶点不超过 4 权重，实际归一化权重已检查。 |
| 动作 | idle、fly、carry_fly、turn_left、turn_right、gather、throw。 |
| LOD/碰撞 | Godot 导入生成 LOD；不交付手工 LOD。沿用逻辑碰撞球半径 0.32、低飞高度 1.45，无根运动和模型内物理节点。 |
| 来源 | 原创，无第三方美术文件；Blender/bpy 为本地制作工具，游戏运行不依赖它。 |
| 场景 | `scenes/actors/jingwei.tscn` 为默认游戏角色；`scenes/art/jingwei_preview.tscn` 提供动作与负重预览。 |

ART-01 小节中“默认主场景仍采用程序模型”是该包交付时的历史状态，ART-02 起精卫已替换；原占位示例保留供接口回归检查。

## ART-03 穿山甲资产

| 字段 | 实际交付 |
| --- | --- |
| 源与生成方法 | `art_source/characters/pangolin.blend`、`art_source/build_pangolin.py`、`art_source/mesh_tools.py`；本项目原创网格、UV 绘制图集与动作。 |
| 游戏模型 | `assets/models/characters/pangolin.glb`，1,321,788 字节。 |
| 材质/纹理 | `assets/materials/pangolin_keratin.tres`；`assets/textures/characters/pangolin_atlas.png`，1024²、634,352 字节。 |
| LOD0 | 8,040 三角形，1 个共享材质、1 个蒙皮表面；Godot 生成导入 LOD，无手工 LOD。 |
| 骨骼/权重 | 18 根骨骼；每顶点不超过 4 个归一化权重。 |
| 鳞片 | 背部 56、头部 6、尾部 24；浅脊带斜边的片状轮廓，全部并入角色网格。 |
| 动作 | idle、locked、walk、dig、complete、finished；分别覆盖待机、未解锁、移动、挖掘、完工和休息。 |
| 站位与碰撞 | 根节点继续使用逻辑 npc_position，正面朝向目标山；不新增角色碰撞或根运动，不改变对话距离及开山数值。 |
| 来源与场景 | 无第三方美术文件；默认 `scenes/actors/pangolin.tscn`，预览 `scenes/art/pangolin_preview.tscn`。Blender/bpy 不随游戏运行。 |

## ART-04 岩层山与碎石场

| 字段 | 实际交付 |
| --- | --- |
| 源与生成方法 | `art_source/environment/` 三个 `.blend`、`art_source/build_mountain.py`；项目原创封闭网格及岩层图，制作清单为 `mountain-manifest.json`。 |
| 山体 | `assets/models/environment/strata_mountain.glb`，504,336 字节，1,918 三角形，单网格/单材质，无骨骼。 |
| 石块 | `quarry_stone.glb`，404,400 字节，68 三角形；最多 32 个实例，完整石堆合计 2,176 三角形。仅用于样板碎石场，正式散石形态仍留待 ART-08。 |
| 山址 | `quarry_site.glb`，415,320 字节，252 三角形；低矮裸岩，裂纹与刨痕为共享材质表现，不具备采集或碰撞能力。 |
| 纹理/材质 | `assets/textures/environment/strata_paint.png`，1024²、398,440 字节；`strata_mountain.tres`、`quarry_stone.tres`、`quarry_site.tres` 共享该图，mipmaps 开启。 |
| 阶段/碰撞 | 连续削顶，0/25/50/75% 与完工、搬空六种入口；样板八层保守圆柱，顶面跟随开采，完工全部禁用。 |
| LOD/效果 | Godot 导入生成 LOD，无手工 LOD；每样板八块静态装饰碎屑，全世界八团复用扬尘，无逐石刚体。 |
| 来源/场景 | 无第三方美术文件；第 0 类山默认启用，独立 `scenes/art/mountain_preview.tscn`。运行不需要 Blender。 |

## ART-05 海岸与植被

| 字段 | 实际交付 |
| --- | --- |
| 源与生成方法 | `art_source/build_coast.py`、`art_source/environment/coast-manifest.json`，四个 `.blend` 源文件；原创网格与调色图。 |
| 树 | `assets/models/environment/coast_tree.glb`，596 三角形，161,796 字节；分叉树干、五簇树冠，单网格/单材质。 |
| 灌木/草 | `coast_shrub.glb`：196 三角形、139,612 字节；`coast_grass.glb`：24 三角形、129,016 字节，六片不透明双面草叶。 |
| 岸石 | `shore_rock.glb`：96 三角形、133,680 字节；深灰湿石，低矮且不具备采集能力。 |
| 图集/材质 | `assets/textures/environment/coast_palette.png`，512²、125,819 字节；共享植被/岸石材质，启用 mipmaps。地表、石质新陆地、泡沫使用可复用 ShaderMaterial。 |
| 运行几何 | 三单位宽陆地条带内生成沙滩/湿岸；8×8 格石质海床与按实际三角形接水线生成的泡沫，共享全局坐标和角点法线。 |
| 实例/LOD | 树最多 200、灌木 160、草 2,500、岸石 160；Godot 导入生成模型 LOD，全图隐藏草/灌木，水面与碎石纹理远景淡出。未交付完整空间分批/手工 LOD。 |
| 碰撞/来源/场景 | 装饰不新增碰撞或资源，无骨骼，无第三方美术文件。默认主场景与 `scenes/art/coast_preview.tscn` 共用环境；运行不需要 Blender。 |
