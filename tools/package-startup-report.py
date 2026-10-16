"""Keep startup evidence; do not archive fixture saves or device shader caches."""
import argparse
import json
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--before', required=True, type=Path)
parser.add_argument('--after', required=True, type=Path)
parser.add_argument('--review', required=True, type=Path)
parser.add_argument('--output', type=Path, default=Path('docs/releases/validation/qa04'))
args = parser.parse_args()
before = json.loads((args.before / 'measurement.json').read_text(encoding='utf-8-sig'))
after = json.loads((args.after / 'measurement.json').read_text(encoding='utf-8-sig'))
assert before['baseline'] and not after['baseline']
for data in (before, after):
    assert data['pack_sha256'] and not data['headless']
    assert [p['pass'] for p in data['passes']] == ['first', 'repeat']
    for p in data['passes']:
        assert p['report']['failures'] == 0
        assert p['report']['first_waiting_draw_ms'] > 0
    assert data['passes'][0]['cache_files_before'] == 0
    assert data['passes'][1]['cache_files_before'] > 0
for p in after['passes']:
    prepared = [r['warmup'] for r in p['report']['records'] if r.get('warmup', {}).get('samples')]
    assert prepared and all(w['drawn'] == w['samples'] for w in prepared)
args.output.mkdir(parents=True, exist_ok=True)
summary = {'before': before, 'after': after, 'scope': 'Actual default-entry resource load and post-draw observation. Explicit editor harness mounts exact shipping/candidate PCK. Independent frame observer. First/new application cache then same-profile new process; system GPU driver cache is not cleared. Controlled balanced fixtures; not minimum-spec or release EXE performance.'}
(args.output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
lines = ['# QA-04 首次使用与缓存复用实测', '',
         '时间单位毫秒。首轮是新的应用用户目录，不代表系统显卡驱动缓存已清空。', '',
         '| 场次 | 指标 | QA-03 | QA-04 |', '| --- | --- | ---: | ---: |']
for b, a in zip(before['passes'], after['passes']):
    label = '首轮 / 新应用缓存' if a['pass'] == 'first' else '次轮 / 同目录新进程'
    lines.append(f"| {label} | 首个等待帧 | {b['report']['first_waiting_draw_ms']:.2f} | {a['report']['first_waiting_draw_ms']:.2f} |")
    lines.append(f"| {label} | 初始选择或续档画面 | {b['report']['first_ready_draw_ms']:.2f} | {a['report']['first_ready_draw_ms']:.2f} |")
    lookup = {r['case']: r for r in b['report']['records']}
    for r in a['report']['records']:
        prior = lookup[r['case']]
        lines.append(f"| {label} | {r['case']} 总时长 / 最长帧 | {prior['wall_ms']:.2f} / {prior['max_frame_ms']:.2f} | {r['wall_ms']:.2f} / {r['max_frame_ms']:.2f} |")
(args.output / 'table.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
for name in ('boot.png', 'picker.png', 'prepare.png'):
    shutil.copyfile(args.review / name, args.output / name)
print(f'Startup evidence archived: {args.output}')
