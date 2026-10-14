"""Build review images and compact metrics from an actual art baseline run.

Developer utility: Python 3 + Pillow. Not used by Play.cmd or the game.
Usage: python tools/summarize-art-baseline.py INPUT_DIR OUTPUT_DIR
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

source, destination = map(Path, sys.argv[1:])
data = json.loads((source / "results.json").read_text(encoding="utf-8"))
cases = data["cases"]
expected = [f"{target}-{view}" for target in [100000, 1000000, 10000000, 100000000]
            for view in ["coast", "mountain", "inland", "deep_sea", "overview"]]
assert [c["id"] for c in cases] == expected, "Expected all twenty canonical cases"
destination.mkdir(parents=True, exist_ok=True)
sheet = Image.new("RGB", (1800, 1000), "#f4f2e7")
draw = ImageDraw.Draw(sheet)
font = ImageFont.load_default(size=16)
rows = ["| 场景 | 平均 FPS | 帧中位 ms | p95 ms | 最大帧 ms | 绘制调用中位 | 引擎静态内存峰值 MiB |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
for index, case in enumerate(cases):
    raw = case.pop("frame_ms_raw")
    assert len(raw) == case["sample_count"] and raw
    assert abs(len(raw) / case["sample_seconds"] - case["fps_mean"]) < 0.001
    assert abs(sorted(raw)[math.ceil(len(raw) * .95) - 1] - case["frame_ms_p95"]) < 0.001
    image = Image.open(source / case["screenshot"]).convert("RGB")
    assert image.size == (1440, 900) == tuple(case["image_size"])
    image.resize((720, 450), Image.Resampling.LANCZOS).save(destination / f'{case["id"]}.jpg', quality=91)
    x, y = index % 5 * 360, index // 5 * 250
    sheet.paste(image.resize((360, 225), Image.Resampling.LANCZOS), (x, y))
    draw.text((x + 8, y + 228), case["id"], font=font, fill="#29413b")
    rows.append(f'| {case["id"]} | {case["fps_mean"]:.1f} | {case["frame_ms_median"]:.2f} | '
                f'{case["frame_ms_p95"]:.2f} | {case["frame_ms_max"]:.2f} | '
                f'{case["draw_calls_median"]:.0f} | {case["engine_static_memory_peak_mib"]:.1f} |')
sheet.save(destination / "contact-sheet.jpg", quality=93)
(destination / "results-summary.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(destination / "metrics.md").write_text("\n".join(rows) + "\n", encoding="utf-8")
print(f"Verified and summarized {len(cases)} cases; screenshots 1440x900; raw samples agree with metrics.")
