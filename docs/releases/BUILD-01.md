# BUILD-01：Windows 独立试玩包

日期：2026-10-16。接续 ART-09，交付 Windows x86_64 便携试玩 ZIP，解压后双击 Jingwei.exe。使用 Godot 4.7.2 release 模板与 Compatibility 渲染，独立 EXE + PCK；不依赖编辑器、源码、Python、Blender、联网或首次资源导入。

状态：已完成。源码全套 1,615 项、打包资源 224 项、挂载 PCK 的存取档回归 107 项（无窗口与真实窗口各一次）通过，真实 release EXE 四档画面及普通新开局/v2 续档启动通过。设备：i9-13900HX、RTX 4060 Laptop、NVIDIA 581.57、Windows 10.0.22631，1440×900 Compatibility。不是全新系统或最低配置验收。

正式运行资源采用全资源导出并显式排除制作和诊断目录，保留通过字符串动态加载的 36 个 GLB、19 个声音及神器图标。新增衔石飞鸟图标、程序版本信息、中文操作说明、Godot 与第三方许可。原创代码和素材的项目级许可仍由作者决定。

## 重建

先运行 Play.cmd -Check -NonInteractive 准备随附编辑器。制作机另需 [官方 Godot 4.7.2 标准导出模板](https://godotengine.org/download/archive/4.7.2-stable/)；它不会装入玩家包或提交 Git。下载 TPZ 后：

```powershell
./tools/prepare-windows-template.ps1 -ArchivePath <官方TPZ文件>
./tools/build-windows.ps1 -Destination builds/BUILD-01
./tools/verify-windows.ps1 -ZipPath builds/BUILD-01.zip
```

准备脚本先核对完整官方 TPZ 的 SHA-256，再仅提取 Windows release 模板。导出脚本拒绝已有目录，记录引擎版本、Git 提交、工作区是否有未提交变化、文件大小与 SHA-256，输出 ZIP 时排除构建日志。没有把编辑器改名当作独立游戏。导出方式参照 [Godot Windows 导出说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)。

## 验证方式

解压实际 ZIP 至含中文和空格的新目录，限制 PATH 至 Windows 系统目录，清空引擎覆盖变量。release 模板不支持 --script，因此深度回归使用编辑器检查程序显式挂载实际下载包的 Jingwei.pck，检查正式资源加载、包内无制作/测试目录，并复用 ART-09 的 107 项实际存取档回归；测试脚本和 v2 夹具只放在包外。源码工作区不作为资源回退路径。

回归包括四档选图、采集投海与穿山甲解锁、部分开采存档、暂停、静音、全图、续档、最后落点、完成后续玩、重选归档、v2 迁移和损坏主文件备份恢复。全部存档隔离到验证目录，不读取玩家进度。真实 release EXE 单独完成四档实机画面捕获、新旅程选择界面和正常 v2 续档启动；挂载 PCK 的检查程序另捕获完整存取档回归画面。两种验证分别记录，不把检查程序当作 release EXE。源码原有 Test.cmd 继续单独执行。

## 兼容与范围

存档格式仍为 version=3；正常启动使用 %APPDATA%/AzVGames/Jingwei，与源码 Play.cmd 共用旅程。更新前可备份该文件夹，不要同时开启两个版本。玩法、数值、资源账本、模型与音效内容均保持原状。

本包未签名，不含安装器，也没有发布商店。低配/核显、无中文字库、其他系统与长时运行继续列为后续验证。便携 ZIP 不在 Git 跟踪范围，构建与验收工具、配置和说明提交 GitHub；本机可直接获取已经验证的 ZIP。
