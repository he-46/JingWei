# 美术与音效来源、许可记录

2026-10-15，ART-09。范围为当前仓库的 Windows 64 位源码试玩候选版。可追溯路径与 SHA-256 见 [源码与资产核查记录](reference/art09/source-audit.json)，引擎内加载结果见 [正式资源核查](reference/art09/runtime-assets.json)。

| 内容 | 来源与可编辑文件 | 运行文件 / 重建入口 | 许可记录 |
| --- | --- | --- | --- |
| 精卫 | 项目代码制作的原创网格、UV 图集、12 骨骼与 7 动作；art_source/characters/jingwei.blend | assets/models/characters/jingwei.glb；art_source/build_jingwei.py | 未引入外部角色模型或贴图；项目对外授权见下文。 |
| 穿山甲 | 原创连续长吻身体、鳞甲、18 骨骼与 6 动作；art_source/characters/pangolin.blend | assets/models/characters/pangolin.glb；art_source/build_pangolin.py | 未引入外部角色或动画。 |
| 岩层山、石块、空山址 | art_source/environment 的同名 .blend，原创形状及手绘岩层图 | art_source/build_mountain.py；assets/models/environment；1024² strata_paint.png | 项目内制作，外部山石素材数为 0。 |
| 其余山型、全图简化山体、石形、植被变体 | 24 份同名 .blend，原创高程表面与网格 | art_source/build_expansion.py；沿用两张环境图集 | 项目内制作；新增 GLB 不嵌入重复纹理。 |
| 海岸树、灌木、草与岸石 | 原创网格与 512² coast_palette.png，同名 .blend | art_source/build_coast.py；coast_geometry.gd 与地表/海水/雾着色器 | 无外部植被、水面或天空素材。 |
| 三件神器与图标 | art_source/relics 的三份 .blend；项目网格及 256² 调色图，图标从同一模型渲染 | art_source/build_relics.py；assets/models/relics、assets/icons/relics | 无外部神器模型或图标包。 |
| 采集、投石、落水、升级等音效与海浪 | tools/generate_audio.py 用 Python 标准库及固定随机种子合成 | assets/audio 的 19 个 WAV | 未使用外部录音、采样库或音乐。 |
| UI、程序模型与特效几何 | 项目 GDScript 与 shader；诊断模型另置 pipeline_examples | scripts、shaders、scenes；诊断制作入口 build_pipeline_examples.py | 原创项目代码，诊断模型不在默认正式资源依赖图中。 |
| 字体 | 运行时请求系统 Microsoft YaHei / Noto Sans SC / SimHei | SystemFont；本机核查 Microsoft YaHei 的 296 个汉字/符号 | 仓库不分发任何字体文件。需要玩家系统有相应中文字库；未把系统字体许可当作项目资产许可。 |
| Godot 引擎 | 随附官方 4.7.2 Windows 64 位 ZIP；启动器校验固定 SHA-256 | Godot/Godot_v4.7.2-stable_win64.zip | MIT 正文见 [Godot/LICENSE.txt](../../Godot/LICENSE.txt)，引擎第三方组件的完整声明见 [Godot/COPYRIGHT.txt](../../Godot/COPYRIGHT.txt)，两者一并分发。 |
| 制作工具 | Blender/bpy 4.5.3、Python/numpy、Pillow、ffmpeg | 仅重建源资产或整理图文/录像 | 制作工具的本机安装目录及二进制未提交；运行试玩不需要这些工具。 |

36 个正式 GLB 均有对应可编辑源文件和制作清单，另有 3 个明确隔离的诊断 GLB。当前没有下载的第三方美术、外部录音、商业字体文件或外部音乐需要补交素材凭证。仓库内引擎及其第三方声明保留原文，不能用“素材原创”替代引擎声明。

**项目级对外授权仍待作者选择。** 仓库尚无项目根目录 LICENSE；本包记录来源和现有第三方声明，不擅自为原创代码、美术或音效添加 MIT、CC 或商用再分发授权。正式公开授权发行前应明确项目条款及署名方式。这个缺口与独立 EXE、商店页面等一起列在 [发布清单](release-checklist.md)。

制作复现步骤见 [资产流程](asset-pipeline.md)。Blender 源文件保存相对纹理路径并重开导出；玩家只加载 GLB/PNG/WAV。Godot 目录和 art_source/docs/art 的 .gdignore 防止将工具源文件作为运行资产导入。
