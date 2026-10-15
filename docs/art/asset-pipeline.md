# ART-01：资产导入流程

ART-01 建立导入与表现接口，pipeline_examples 仍保留为诊断占位模型。ART-02 已将正式精卫接入普通 Play.cmd；穿山甲与山体分别由 ART-03/04 制作。

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

角色动作语义、可选附件和事件时序见[表现接口](visual-contract.md)。正式山体目前沿用公共顶点色削顶着色器；GLB 材质不会覆盖该着色器。更复杂岩层材质与阶段模型在 ART-04 扩展，不能直接套多网格场景并期望保留各子节点变换。

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
3. `tools/run.ps1 -Mode Test` 自动执行原有玩法测试、41 项表现检查、39 项精卫检查，以及在占位导入场景上重跑的 70 项玩法检查。
4. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify-clean-art-copy.ps1` 创建新的可分发源码副本，排除本地引擎 EXE、缓存和建模工具，限制 PATH 后由副本内 ZIP 准备引擎并完成全部测试。副本及日志在 `artifacts/art/clean-时间/`。
5. 实机截图：Godot 运行 `--path . --resolution 1440x900 --script res://tests/capture_pipeline.gd -- --qa`，生成 `artifacts/art/art01/imported-*.png`。默认外观对照继续使用 ART-00 的基线工具。

检查骨骼确实变形、朝向正确、携带物显隐、暂停不前进、连投重启动作、换地图清理旧实例、开山后碰撞解除、资源不因动画重放改变。测试过后记录引擎版本、日志和截图；本包不把占位外观或无界面测试当作最终美术验收。

## ART-02 精卫制作入口

`blender --background --python art_source/build_jingwei.py` 重建本项目的精卫源模型、1024² UV 绘制图集、7 段动作和 GLB；仅用于重建该资产，会覆盖对应文件。生成器检查身体、头部和喙的连接性及封闭性，制作清单在 `art_source/characters/jingwei-manifest.json`。手工编辑源文件后继续使用上面的单资产导出器。

角色场景使用 `assets/materials/jingwei_feather.tres` 共享外部图集，并启用线性过滤和 mipmaps。GLB 导入设置采用内嵌纹理模式 3，避免额外生成 `assets/models/` 下的重复 PNG。默认游戏与精卫预览都使用同一个 `scenes/actors/jingwei.tscn`；独立 F6 预览入口为 `scenes/art/jingwei_preview.tscn`。具体动作时序、预算与画面见 [ART-02 交付](deliveries/ART-02.md)。
