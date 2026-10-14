# 随附 Windows 引擎

本目录随项目提供 Godot 4.7.2 标准版 Windows x86_64 引擎，版本标识为 `4.7.2.stable.official.ed1daf0bf`。直接双击项目根目录的 Play.cmd 即可；首次启动会校验并解压本目录的 ZIP，无需联网下载。

压缩包包含主程序和配套控制台启动程序，原始主程序超过 GitHub 普通仓库的单文件限制，因此以 ZIP 保存。ZIP 为本项目从已有、已验证的两份引擎 EXE 重新压缩，不是独立游戏导出包。解压后的 EXE 被 Git 忽略；两份 EXE 均存在时后续启动会复用。

- ZIP 大小：87,710,475 字节（约 83.65 MiB）。
- ZIP SHA-256：`6BF5B2D5BB1580D62615DE321EE4D5896CE0DB452603CA61F1AB9B5157D9AB87`。
- 引擎许可：LICENSE.txt；第三方许可：COPYRIGHT.txt，均来自 Godot 对应版本源代码。
- 官方说明：https://godotengine.org/license/
- 对应源代码：https://github.com/godotengine/godot/tree/4.7.2-stable

更新引擎时需同时更新压缩包、许可文件，以及 tools/run.ps1 中的文件名与 SHA-256。
