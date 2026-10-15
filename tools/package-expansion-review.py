"""Package already-captured ART-08 evidence; no game/asset mutation. Needs Pillow."""
from pathlib import Path
import argparse
import json
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
LABELS = {'coast-actions': '普通采集投石', 'full-reclamation': '全海域改造',
          'dense-mountains': '密集群山', 'concentrated-effects': '集中效果', 'overview': '全图'}
TARGETS = {100000: '10万', 1000000: '100万', 10000000: '1000万', 100000000: '1亿'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--benchmark', default='artifacts/art/art08-performance-accepted')
    parser.add_argument('--review', default='artifacts/art/art08-review')
    args = parser.parse_args()
    source, review = ROOT / args.benchmark, ROOT / args.review
    evidence = ROOT / 'docs/art/validation/art08'
    reference = ROOT / 'docs/art/reference/art08'
    evidence.mkdir(parents=True, exist_ok=True)
    reference.mkdir(parents=True, exist_ok=True)
    report = json.loads((source / 'results.json').read_text(encoding='utf-8'))
    memory = json.loads((source / 'process-memory.json').read_text(encoding='utf-8-sig'))
    if len(report['cases']) != 20 or any(not c['state_valid'] for c in report['cases']):
        raise ValueError('All twenty final fixtures must pass before packaging')
    if any(m['process_id'] != report['metadata']['process_id'] for m in memory):
        raise ValueError('Memory samples must belong to the actual Godot renderer process')
    report['metadata']['process_memory_sampling_seconds'] = .5
    report['metadata']['process_peak_working_set_mib_including_setup'] = max(m['peak_working_set_mib'] for m in memory)
    report['metadata']['cpu_owner_scope'] = 'ProfileGame times ordinary main _process and _physics_process; physics samples only on executed ticks. Excludes benchmark driver/sampler. Renderer CPU/GPU measured by the SubViewport.'
    for case in report['cases']:
        case.pop('frame_ms_raw')
        samples = [m for m in memory if case['unix_start'] <= m['unix_seconds'] <= case['unix_end']]
        case['process_working_set_sample_peak_mib'] = max(m['working_set_mib'] for m in samples)
        case['process_private_sample_peak_mib'] = max(m['private_mib'] for m in samples)
    (reference / 'performance-summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 15)
    sheet = Image.new('RGB', (1600, 864), '#edf0e5')
    draw = ImageDraw.Draw(sheet)
    for i, case in enumerate(report['cases']):
        image = Image.open(source / f"{case['target']}-{case['case']}.jpg").convert('RGB')
        image.thumbnail((320, 180), Image.Resampling.LANCZOS)
        x, y = (i % 5) * 320, (i // 5) * 216
        sheet.paste(image, (x, y))
        draw.text((x + 8, y + 185), f"{TARGETS[case['target']]} · {LABELS[case['case']]} · p95 {case['frame_ms_p95']:.2f} ms", font=font, fill='#294737')
    sheet.save(evidence / 'stress-contact-sheet.jpg', quality=92)
    shutil.copyfile(review / 'asset-sheet.jpg', evidence / 'asset-sheet.jpg')
    for target, name in [(1000000, 'dense-mountains'), (100000000, 'overview'),
                         (100000000, 'full-reclamation'), (100000000, 'concentrated-effects')]:
        shutil.copyfile(source / f'{target}-{name}.jpg', evidence / f'{target}-{name}.jpg')
    lines = ['| 目标 | 场景 | 帧 p95 / p99 / 最慢 (ms) | >16.67ms (%) | 绘制次数中位 | 工作集采样峰值 MiB |',
             '| --- | --- | ---: | ---: | ---: | ---: |']
    for c in report['cases']:
        lines.append(f"| {TARGETS[c['target']]} | {LABELS[c['case']]} | {c['frame_ms_p95']:.3f} / {c['frame_ms_p99']:.3f} / {c['frame_ms_max']:.3f} | {c['over_16_67_ms_percent']:.3f} | {c['draw_calls_median']:.0f} | {c['process_working_set_sample_peak_mib']:.1f} |")
    lines += ['', '| 目标 | 主脚本 process p95 | 物理脚本 p95 / 最慢 | 渲染 CPU p95 | 渲染 GPU p95 | 开图最慢 / 压力夹具准备最慢 | 引擎静态 / 显存峰值 MiB |',
              '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for target, title in TARGETS.items():
        cases = [c for c in report['cases'] if c['target'] == target]
        def high(key): return max(c[key] for c in cases)
        lines.append(f"| {title} | {high('cpu_process_ms_p95'):.3f} | {high('cpu_physics_ms_p95'):.3f} / {high('cpu_physics_ms_max'):.3f} | {high('render_cpu_ms_p95'):.3f} | {high('render_gpu_ms_p95'):.3f} | {high('map_setup_ms'):.1f} / {high('fixture_setup_ms'):.1f} | {high('engine_static_memory_peak_mib'):.1f} / {high('video_memory_peak_mib'):.1f} |")
    path = ROOT / 'docs/art/performance-report.md'
    text = path.read_text(encoding='utf-8')
    before, rest = text.split('<!-- measured-results -->', 1)
    _, after = rest.split('<!-- measured-end -->', 1)
    path.write_text(before + '<!-- measured-results -->\n' + '\n'.join(lines) + '\n<!-- measured-end -->' + after, encoding='utf-8')
    print('Packaged 20 cases; peak process working set:', report['metadata']['process_peak_working_set_mib_including_setup'])


if __name__ == '__main__':
    main()
