# 美术参考与素材来源

查阅日期：2026-10-14。

## 本轮视觉来源

本轮仅分析本项目 models.gd、world.gd、现有着色器、HUD 和固定种子实机画面。文档中的参考图是本项目运行截图，不含从第三方游戏截取的图案或模型。本轮未下载外部美术资产，未生成概念图，未新增材质或模型。

## 技术资料

| 资料 | 用途 | 本轮如何使用 |
| --- | --- | --- |
| [Godot Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html) | 内置监视器的含义与局限 | 使用绘制调用、物理处理和静态内存监视器；保留原始字段名称，不把渲染 primitives 误当三角形数。部分监视器有更新延迟。 |
| [Godot 3D 渲染限制](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html) | 透明叠层、深度和画面限制 | 作为海岸、雾和植被验收时的技术参考，当前不据此更换渲染器。 |
| [Godot 3D 导入格式](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) | 正式资产导入路线 | 后续 ART-01 使用 GLB，避免向玩家引入 Blender 依赖；本轮仅记录计划。 |
| [Godot MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) | 共享网格与空间分区 | 后续在实测基础上评估分区，不在 ART-00 实施优化。 |

以上为技术参考链接，没有把网页图片或示例资产复制进游戏。每次后续引入外部美术资源，必须在资产清单中追加来源和分发许可，不能以“公开可见”代替可分发授权。

## ART-01 更新（2026-10-15）

本包使用 Blender 4.5.3 的官方 bpy 模块与 glTF 导出器，新增三个项目代码生成的诊断模型，不使用外部模型、纹理或参考图。Blender/bpy 仅是制作工具，不放入游戏文件夹或仓库；可编辑 `.blend` 与运行时 GLB 一并交付。使用方式见 [导入流程](asset-pipeline.md)，实际生成方法及规模见 [资产清单](asset-inventory.md)。

GLB 在 Godot 4.7.2 中直接导入，源文件通过 `.gdignore` 排除；全新源码副本的实际验证落实了上表原先记录的 GLB 路线。

## ART-02 更新（2026-10-15）

精卫的连续网格、分组羽翼、UV 图集和七段骨骼动作由项目 `art_source/build_jingwei.py` 构建，源文件和制作清单一并交付。颜色沿用 ART-00 调色板。没有引入第三方美术文件，图集采用项目内绘制算法，不含外部照片或纹理。交付记录中的画面全部由 Godot 实际渲染。

## ART-03 更新（2026-10-15）

穿山甲的连续头身长吻、86 片鳞甲、长尾、肢爪、UV 图集和六段骨骼动作由项目 `art_source/build_pangolin.py` 与网格工具构建。颜色沿用 ART-00 的暖褐鳞甲方向，图集通过项目绘制算法表现角质生长纹与磨亮边缘。无外部模型、照片、纹理或参考截图；交付画面为 Godot 实机渲染。源文件、生成器和制作清单随仓库提交，Blender/bpy 仅作本地制作工具。
