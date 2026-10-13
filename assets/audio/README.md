# 精卫填海音效素材

全部 WAV 由 tools/generate_audio.py 原创合成，无第三方采样、网络下载或额外依赖。固定种子可重现素材。

- gather / land：石粒共振、碎石和低频落地冲击，各三种。
- throw / water：滤波掠风、水花和水滴，各三种。
- fill / upgrade / unlock / relic / complete：不同节奏与层次的和声提示。
- mined：逐渐消散的碎石声。
- surf：12 秒低音量立体声海浪循环。

所有声音为 44.1 kHz、16 bit PCM，短动作单声道，海浪立体声。保留 .wav.import 中的无压缩、无归一化设置，以保持生成器中的包络和峰值余量。实际增益、音高变化、触发间隔与声道优先级由 scripts/soundscape.gd 管理。
