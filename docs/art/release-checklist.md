# 美术试玩候选版发布清单

ART-09，2026-10-15。范围是 Windows 64 位源码试玩候选版及其内附 Godot 引擎，版本以本文件所在提交为准。ART-00～09 的美术任务完成不等于商店上线或独立 EXE 已发布。

| 项目 | 结果与证据 |
| --- | --- |
| 正式资源完整性 | 36 个正式 GLB、8 张 PNG（含三张图标）、10 份材质、19 个 WAV 可加载；默认运行依赖无 pipeline_examples，占位场景仅供诊断。见 [资源核查](reference/art09/runtime-assets.json)。 |
| 可编辑源与制作流程 | 每个正式模型对应 .blend 和制作清单；动画/图集/音效生成入口均已记录。见 [来源与许可](asset-sources-and-licenses.md)、[制作流程](asset-pipeline.md)。 |
| 中文与布局 | 本机 Microsoft YaHei 覆盖 296 个界面汉字/符号；1440×900 与 1152×720 画面已审阅，遮挡标记不遮按钮。字体文件不随包分发。 |
| 规则与场景检查 | Test.cmd 共 1,615 项：原 1,203 项＋305 项资源核查＋107 项真实存取档回归，全部通过。 |
| 四档旅程 | 新开局、128 石解锁、部分开采保存、暂停、静音、全图/普通切换、续档、完整填海面板、完成后续玩与重选规模均检查。见 [回归记录](reference/art09/release-regression.json)。 |
| 旧档和备份 | 真实 v2 夹具由普通启动路径迁移；原字节留存到首次保存，保存后 .bak 保留 v2；损坏主文件由有效备份恢复。所有测试文件位于 artifacts，不访问玩家旅程。 |
| 完成落点顺序 | 四档均在最后投射物落地后才显示完成面板并暂停，已完成存档重开不重播历史效果。完整填海为资源守恒的回归夹具，不宣称实际手动通关。 |
| 实机普通流程 | 实际移动、E 拾石、普通投放入口，四趟解锁、第一山 1,024 石开采/搬空、累计 1,152 石成陆；33 项通过。见 [流程账本](reference/art09/walkthrough.json) 与 [14.5 秒短片](validation/art09/resource-cycle.mp4)。 |
| 图形专项 | 正式资源 305、真实存档回归 107、定位/迷雾像素 31、普通流程 33 项通过。25 张联系图已逐图检查；修正尖峰自阴影细纹与截图在表现刷新前取样的问题。 |
| 源码下载启动 | 从最终 Git 提交创建 ZIP，解压到带中文和空格的新目录；开始时无已解压 EXE、.godot、.tools、.git。实际执行 Play.cmd -Check、Test.cmd、Sample.cmd -Check，及真实 Compatibility 窗口启动，全部通过。制作工具不在 PATH，只使用随包引擎。 |
| 跟踪文件与体积 | `.godot`、本机 `.tools`、解压 EXE、存档、日志、原始录像帧和 .blend 备份不进入 Git。可编辑源文件、正式 GLB、导入设置与引擎 ZIP保留。目录字节统计、模型/源文件 SHA-256 见 [源码审计](reference/art09/source-audit.json)。实际 ZIP 大小和 SHA-256 由下载验证工具生成到 artifacts。 |
| 引擎与第三方声明 | Godot ZIP 与启动器固定 SHA-256 一致；Godot/LICENSE.txt 和 COPYRIGHT.txt 一起分发，无外部美术/音频素材。项目级原创授权尚未指定，列在下方。 |
| 性能声明 | 引用 [ART-08 指定设备短时实测](performance-report.md)，原基线为 fa710d0；ART-09 的图集/阴影修正与功能回归不等同于重新测量全套性能。未把剪辑视频当作帧率证明。 |

## 实机审阅记录

设备与 ART-00/08 相同：i9-13900HX、RTX 4060 Laptop、NVIDIA 581.57、Windows 10.0.22631，Godot 4.7.2 / OpenGL Compatibility、2×MSAA、60Hz 物理。功能截图 1440×900，另复核 1152×720；短片以固定模拟步长录制普通流程，不测性能。

[联系图](validation/art09/contact-sheet.jpg) 包含四档新开局和全图、普通海岸/山体、高飞、窄窗口、边界水面、旧档继续、完成面板及九个实际资源循环阶段。对比图另列 [阴影修正](validation/art09/shadow-comparison.jpg)。核对人物负重、单个穿山甲、石料颜色、有限库存/空山址、海岸接缝、字体与按钮位置，未发现阻断游玩的美术缺陷。审阅由本轮工具捕获与逐图检查完成，不声称用户已批准最终审美。

## 正式发行前仍需完成

- **独立游戏打包**：Windows 导出模板、独立 EXE/PCK、包图标、发布配置、签名或安装器、全新系统安装/卸载与归档方式。
- **项目授权**：由作者指定原创代码、美术、动画和音效的对外授权与署名；本包不替作者选择许可证。
- **平台与商店**：商店页面、宣传文案与截图选取、平台审核、渠道账号、定价和发布安排。
- **兼容与长时运行**：低配/核显、不同驱动与电源状态、长时温控及内存、录屏并发、没有中文字体的 Windows；其他系统/手柄/触控未验证。
- **体验与性能**：用户试玩与最终审美反馈、节奏标定、一亿石开图停顿、已有短时帧尖峰的长时间复核。当前没有自动搬运、任意挖洞或离线收益。

这些事项属于正式发行与后续产品工作，本包不创建定时任务、不上传商店，也不擅自发布新平台构建。

## 复现与回滚

```powershell
./Test.cmd -NonInteractive
./tools/verify-art-release.ps1
python tools/package-art-release.py --ffmpeg <本机ffmpeg路径>
python tools/audit-release.py
./tools/verify-release-copy.ps1 -Ref HEAD -Destination "artifacts/art/ART09 源码下载验证"
```

最后一步只验证指定 Git 提交，不复制未提交文件；必须在提交完成后运行，目标目录需不存在。生成的 ZIP、日志、提交 ID、精确体积与校验值放在忽略的 artifacts。Play.cmd -Check 先验证真正首次解压/导入路径，随后 Test.cmd，再 Sample.cmd 和窗口启动。证书库读取诊断仅在精确匹配既有 `Failed to read the root certificate store.` 时排除，其余 ERROR/SCRIPT ERROR 和非零退出全部视为失败。

更新说明及保留存档的回滚方法见 [美术更新说明](art-update-notes.md)。本包基线为 `fa710d0b3f76c799a1b03387e74a1164740d8aeb`；version=3 不变，回退前复制整个存档目录，不要求删除进度。
