# ART-09 交付：美术版本发布验收与交付

日期：2026-10-15。范围为 Windows 64 位源码试玩候选版。交付完整 [发布清单](../release-checklist.md)、[美术更新说明与回滚方法](../art-update-notes.md)、[来源和许可记录](../asset-sources-and-licenses.md)、[源码审计](../reference/art09/source-audit.json)、[25 张实机联系图](../validation/art09/contact-sheet.jpg) 与 [14.5 秒普通流程短片](../validation/art09/resource-cycle.mp4)。

正式资源、纹理、材质、动作与字体逐项检查；修正神器图集 mipmaps、尖峰表面自阴影细纹，并让流程截图先同步已结算进度到 HUD/石堆，避免把刚完工、尚未表现刷新的帧当作阶段图。没有更改四档石量、开采顺序、修行、飞行增程或存档格式。

Test.cmd 从原 1,203 项扩展到 1,615 项，新增 305 项正式资源核查与 107 项实际存取档回归；覆盖四档新开局、暂停、静音、全图、部分开采续档、完成落点、重选归档、v2 迁移和坏主文件备份恢复。真实渲染专项及 33 项普通采集路线通过，全部测试存档隔离在 artifacts。

源码下载验证直接归档本文件所在 Git 提交，使用包含空格和中文的新目录；从没有缓存、已解压引擎、本机工具的状态执行 Play.cmd / Test.cmd / Sample.cmd，以及 Compatibility 窗口启动。实际 ZIP 字节、SHA-256 与提交标识由工具记录在 `artifacts/art/ART09 源码下载验证-verification.json`，不把未提交工作区当作下载版本。

设备：i9-13900HX、RTX 4060 Laptop、NVIDIA 581.57、Windows 10.0.22631，Godot 4.7.2 Compatibility。截图 1440×900 并复核 1152×720；视频为无声 10 fps 实机剪辑，省略往返和等待。性能引用 ART-08 基线的实际 1080p 渲染报告，本包不把录像或功能核查当作新的最低配置/长时性能验收。

原始帧、日志和隔离旅程位于忽略的 artifacts；制作环境可按流程重新生成，玩家运行不需要 Blender、Python 或 ffmpeg。版本基线 `fa710d0b3f76c799a1b03387e74a1164740d8aeb`，本文件所在提交是 ART-09 的回滚边界，version=3 未变。

正式 EXE/PCK 导出、签名/安装器、商店页面和审核、作者对原创资产的项目级许可，以及低配/无中文字库/长时运行验证仍列为发行前待办。不把本包或全部美术任务完成表述为整个游戏已上线。
