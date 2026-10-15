# ART-01：资产导入流程

ART-01 建立导入与表现接口，pipeline_examples 仍保留为诊断占位模型。ART-02～05 已将两个正式角色、岩层山与海岸环境样板接入普通 Play.cmd。

## 玩家与制作环境

玩家只运行 Play.cmd。启动器从仓库内 ZIP 准备 Godot，导入已提交的 GLB；不调用 Blender 或 Python。`art_source/.gdignore` 排除全部建模源文件，`.godot/` 和 `.tools/` 不入库。

制作基线为 Blender 4.5.3、Godot 4.7.2、Compatibility。本包用官方 `bpy==4.5.3` 的 Windows Python 3.11 模块执行同一 Blender API，实际保存、重新打开三个 `.blend` 后导出 GLB。制作工具仅在本地忽略目录；后续美术可使用 Blender 4.5 的桌面程序。GLB 路线与 Godot 的[官方格式说明](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)一致。

## 路径与坐标

| 项目 | 约定 |
| --- | --- |
| 源文件 | `art_source/<类别>/<名称>.blend`，生成工具一起提交；Blender 备份不提交。 |
| 导出 | `assets/models/<类别>/<名称>.glb`；提交相应 `.glb.import` 导入设置，不提交 `.godot` 缓存。 |
| 预制场景 | `scenes/actors/`，组合模型与 `scripts/visuals/` 控制器；不编辑 GLB 导入缓存。 |
| 材质与贴图 | 手工 Godot 材质放 `assets/materials/`；外部原始贴图放 `assets/textures/`。本包用 GLB 内嵌纯色材质，不创建空贴图目录。 |
| 单位 | Blender Metric、Unit Scale 1；1 个 Godot 单位为 1 米，逻辑格宽 4。应用网格和骨架缩放，不用导入倍率修尺寸。 |
| 方向 | Blender +Z 向上、+Y 向前；导出启用 +Y Up，Godot +Y 向上、−Z 向前、+X 向右。不要再给场景加一个补偿旋转。 |
| 精卫原点 | 身体中心，悬停高度由逻辑给出 1.45，碰撞球半径 0.32；翅膀可超出碰撞球。导入模型直接使用米制大小，程序模型旧有 1.15 倍缩放仅在其适配器内。 |
| 穿山甲原点 | 足底中央，站位和对话点由逻辑给出，地面高度 0.45；导入根变换保持单位变换。 |
| 山体原点 | 地面中心，Godot Y 范围 0～1、XZ 最大半径约 1；单个单位变换 MeshInstance3D。逻辑按储量给出半径和高度，运行时统一缩放。 |
| 骨骼 | 一个 `Rig`、一个 `Root`，左右后缀 `_L`/`_R`；无负缩放，每顶点最多 4 权重。逻辑不读取骨骼名，名称供制作维护。 |
| 动画 | 独立命名 NLA 轨道，起点第 1 帧，24 fps 源文件；导出 NLA Tracks。无根运动位移、物理节点、脚本或资源结算方法轨道。 |

角色动作语义、可选附件和事件时序见[表现接口](visual-contract.md)。ART-04 样板山使用共享岩层着色器，兼容连续削顶和断面法线；其余原型/诊断山沿用顶点色削顶材质。GLB 材质不会覆盖世界指定的共享材质，不能直接套多网格场景并期望保留各子节点变换。

## 可复现制作步骤

在工程根目录运行，`blender` 可换成完整安装路径：

```powershell
blender --background --python art_source/build_pipeline_examples.py
```

此命令**重建三个诊断示例**，会覆盖 `art_source/pipeline_examples/` 与 `assets/models/pipeline_examples/` 中对应文件；不要用来导出已手工修改的正式资产。三个源文件均保存后重新打开，再调用统一导出器。

对于手工修改后的单个源文件，先在 Blender 保存，再运行：

```powershell
blender --background art_source/pipeline_examples/jingwei.blend --python art_source/export_glb.py -- assets/models/pipeline_examples/jingwei.glb
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode Test -NonInteractive
```

导出器检查单位比例、对象缩放；导出 GLB、Y Up、蒙皮、命名 NLA 动画。采集和投石结果不能放进动画帧事件。非均匀缩放要在绑定前应用，导出前清除相机、灯光和非资产对象。

Godot 中复制角色预制场景，设置 `model_scene`。默认动作名可直接使用；如导入命名不同，在 `animation_names` 中把语义映射到完整 AnimationPlayer 动作名。精卫携带物设置 `cargo_path`，路径相对于导入模型根，例如示例的 `Rig/CargoPreview`。

## 运行与验收

1. 使用 Editor.cmd 打开项目，打开 `scenes/art/pipeline_preview.tscn`，按 F6。示例禁用存档，选择难度后按现有 WASD/E/Q/空格操作。
2. 示例替换精卫、唯一穿山甲和第 0 类山体，另外四类保留原模型以验证混用。再次选择难度仍保留替换配置。
3. `tools/run.ps1 -Mode Test` 自动执行状态、玩法、音效、UI、角色与表现、39 项高度增程、84 项山体、71 项环境、65 项反馈检查，以及在占位导入场景上重跑的 70 项玩法检查，当前合计 926 项，包含 33 项真实路线与 16 项样板隔离/遮挡检查。
4. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify-clean-art-copy.ps1` 创建新的可分发源码副本，排除本地引擎 EXE、缓存和建模工具，限制 PATH 后由副本内 ZIP 准备引擎并完成全部测试。副本及日志在 `artifacts/art/clean-时间/`。
5. 实机截图：Godot 运行 `--path . --resolution 1440x900 --script res://tests/capture_pipeline.gd -- --qa`，生成 `artifacts/art/art01/imported-*.png`。默认外观对照继续使用 ART-00 的基线工具。

检查骨骼确实变形、朝向正确、携带物显隐、暂停不前进、连投重启动作、换地图清理旧实例、开山后碰撞解除、资源不因动画重放改变。测试过后记录引擎版本、日志和截图；本包不把占位外观或无界面测试当作最终美术验收。

## ART-02 精卫制作入口

`blender --background --python art_source/build_jingwei.py` 重建本项目的精卫源模型、1024² UV 绘制图集、7 段动作和 GLB；仅用于重建该资产，会覆盖对应文件。生成器检查身体、头部和喙的连接性及封闭性，制作清单在 `art_source/characters/jingwei-manifest.json`。手工编辑源文件后继续使用上面的单资产导出器。

角色场景使用 `assets/materials/jingwei_feather.tres` 共享外部图集，并启用线性过滤和 mipmaps。GLB 导入设置采用内嵌纹理模式 3，避免额外生成 `assets/models/` 下的重复 PNG。默认游戏与精卫预览都使用同一个 `scenes/actors/jingwei.tscn`；独立 F6 预览入口为 `scenes/art/jingwei_preview.tscn`。具体动作时序、预算与画面见 [ART-02 交付](deliveries/ART-02.md)。

## ART-03 穿山甲制作入口

`blender --background --python art_source/build_pangolin.py` 重建穿山甲源文件、1024² 鳞甲图集、6 段动作和 GLB；仅覆盖对应穿山甲资产。`art_source/mesh_tools.py` 提供该生成器的网格、UV 与蒙皮构建工具。源文件保留相对纹理路径；手工编辑后仍使用单资产导出器。

生成器检查头身长吻为连续封闭网格，将 86 片浅脊鳞片、肢体和长尾合为一个蒙皮表面。`assets/materials/pangolin_keratin.tres` 使用外部图集、线性 mipmaps 和 0.88 粗糙度。GLB 内嵌纹理模式同样为 3；无需提交额外抽取的同名 PNG。默认角色为 `scenes/actors/pangolin.tscn`，独立 F6 入口为 `scenes/art/pangolin_preview.tscn`。源文件清单、动作与工作状态验证见 [ART-03 交付](deliveries/ART-03.md)。

## ART-04 山体制作入口

`blender --background --python art_source/build_mountain.py` 重建一套岩层山、石块、低矮遗迹和共享 1024² 岩层图。三个源文件在 `art_source/environment/`，生成器检查封闭流形，实际重新打开源文件后导出 `assets/models/environment/` 的三个 GLB。清单为 `art_source/environment/mountain-manifest.json`；手工修改后仍使用单资产导出器。GLB 采用内嵌纹理模式 3，正式材质共享外部图并启用 mipmaps。

编辑器 F6 入口为 `scenes/art/mountain_preview.tscn`，可切换六种状态、连续拖动进度和库存、旋转或缩放，不访问玩家旅程或存档。样板自动替换世界第 0 类山体；其余四类保留程序模型。普通 Test.cmd 执行 84 项山体检查；实际图形环境再运行 `--path . --resolution 1152x720 --script res://tests/test_mountain.gd -- --qa`，执行 113 项，包含 29 项 MultiMesh 读回与装饰避让检查。截图入口为 `tests/capture_mountain_art.gd`，详见 [ART-04 交付](deliveries/ART-04.md)。

## ART-05 海岸制作入口

`blender --background --python art_source/build_coast.py` 重建一型树、一型灌木、一型草丛、一型岸石及共用 512² 调色图。源文件在 `art_source/environment/`，运行模型在 `assets/models/environment/`；只覆盖本包四个资产。每个源文件保存后重新打开再导出，GLB 导入模式为 3，不提取重复 PNG。游戏只加载 GLB，不依赖 Blender。

`scripts/visuals/coast_geometry.gd` 统一生成海岸、填海角点/法线与接水线；地表和新陆地材质使用世界坐标，跨区块连续。`scenes/art/coast_preview.tscn` 为 F6 可玩固定样板，沿用正常操作并禁用玩家存档访问。普通 Test.cmd 包含 71 项环境专项；实际图形环境运行 `--path . --resolution 1152x720 --script res://tests/test_environment.gd -- --qa` 为 95 项，额外验证装饰实际位置与避让。截图入口、前后对比与运行记录见 [ART-05 交付](deliveries/ART-05.md)。

## ART-06 神器与反馈制作入口

`blender --background --python art_source/build_relics.py` 重建三个 `.blend`、三个 GLB、256² 调色图及三个透明图标。模型先保存、重开并导出，再使用同一网格与图集在固定正交镜头渲染 256² RGBA 图标。制作需要 Blender 4.5 的 Python API 与 numpy；运行不需要。资产目录、事件表、固定池边界及实机命令见 [ART-06 交付](deliveries/ART-06.md)。Test.cmd 包含 65 项反馈专项；使用实际图形环境运行同一脚本为 71 项。F6 可玩入口为 `scenes/art/feedback_preview.tscn`，截图脚本为 `tools/capture-feedback.gd`，两者均不访问玩家存档。

## ART-07 样板与评审复现

双击 Sample.cmd 或编辑器 F6 打开 `scenes/art/vertical_slice.tscn`，种子 10213、十万石；不读取、写入或备份玩家旅程。Play.cmd 保持普通入口。`Sample.cmd -Check -NonInteractive` 验证独立样板启动；全新源码验证器会额外执行此启动路径。

真实路线与录像原始帧：`--path . --fixed-fps 60 --script res://tests/test_vertical_slice.gd -- --qa --capture-output=res://artifacts/art/art07-walk-final`。使用实际移动、E 和投放入口，没有注入资源或跳过模拟时间。镜头与遮挡/迷雾像素复核：`--path . --script res://tests/test_player_locator.gd -- --qa --review-out=res://artifacts/art/art07-review-final`。两者需要实际图形环境来保存画面；Test.cmd 默认以无窗口模式验证逻辑。

性能单独运行 `--path . --script res://tests/art_slice_benchmark.gd -- --qa`；此脚本拒绝无窗口和固定帧率模式，使用实际时钟，输出 `artifacts/art/art07-performance/results.json`。不要与录制、编码或其他重负载作业同时运行。

`tools/package-slice-review.py --walk artifacts/art/art07-walk-final --views artifacts/art/art07-review-final --performance artifacts/art/art07-performance/results.json --ffmpeg <ffmpeg.exe 路径>` 生成审阅 JPG、性能摘要和带章节说明的无声 MP4。制作工具需要 Python/Pillow、中文字体与 ffmpeg；只处理已捕获帧，游戏运行不需要这些工具。可选 `--fog-before <修正前 PNG>` 重建本包边界对照。原始帧和编码器留在忽略目录；已提交的对照图可直接审阅。完整证据、范围与下一包见 [样板评审](vertical-slice-review.md)。

## ART-08 全地图扩展入口

`blender --background --python art_source/build_expansion.py` 生成 24 份同名 `.blend` / GLB：7 个新山、8 份全图简化山、5 个新石形、4 个新植被。沿用已有两张环境图集，不覆盖前包源模型或图集。源文件实际重开后导出；新增 GLB 使用 `export(..., materials=False)`，保留 UV 与法线，运行材质通过 `asset_catalog.gd` / world 明确赋予，不携带重复图片。直接把单个新 GLB 拖入空场景时需指定同类正式材质；可编辑 Blender 源文件仍有纹理。

所有山均为单网格，标准地面 0、峰高 1、水平半径 <0.96。8 份全图模型为每型 478 三角形，正式模型每型 1,918；完整预算及存档家族映射见 [扩展资产清单](expansion-assets.md)。普通游戏的所有山均用正式资产，早期程序山只供导入诊断覆盖接口使用。

实机验证入口 `tools/verify-art-expansion.ps1`，包含 113 项山体、95 项环境、71 项反馈、281 项扩展、31 项定位检查及资产总览；扩展项比无窗口模式多四项实际实例颜色检查。普通 Test.cmd 增加 277 项扩展检查，合计 1,203 项。`tools/measure-art-expansion.ps1 -Output artifacts/art/art08-performance-accepted` 单独运行二十个实际 1080p 渲染压力场景，按引擎报告的游戏进程 ID 采样工作集；`tools/package-expansion-review.py` 整理最终摘要与图片。详见 [性能报告](performance-report.md)。
