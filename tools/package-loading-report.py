"""Archive measured loading cases, never fixture saves or driver caches."""
import argparse
import json
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--before', type=Path, required=True)
parser.add_argument('--after', type=Path, required=True)
parser.add_argument('--output', type=Path, default=Path('docs/releases/validation/qa03'))
args = parser.parse_args()
before = json.loads((args.before / 'measurement.json').read_text(encoding='utf-8-sig'))
after = json.loads((args.after / 'measurement.json').read_text(encoding='utf-8-sig'))
assert before['baseline'] and not after['baseline']
for data in (before, after):
    assert not data['headless'] and data['pack_sha256']
    assert data['report']['failures'] == 0
    assert len(data['report']['records']) >= 20
    assert all('started_at_ms' in r and r['frame_count'] >= 1 for r in data['report']['records'])
args.output.mkdir(parents=True, exist_ok=True)
summary = {'before': before, 'after': after,
           'scope': 'Editor harness mounts exact exported PCKs. Actual Compatibility frame intervals, including first completed-world draw. Balanced fixtures, isolated saves. Cold first-use work retained; no gameplay FPS or minimum-spec claim.'}
(args.output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
lookup = {(r['target'], r['case']): r for r in before['report']['records']}
labels = {'empty-selector': '初始选择界面', 'new-map': '选择新地图', 'completed-save': '满海域续档',
          'backup-recovery': '备份恢复', 'restart': '归档后重开', 'invalid-save': '无有效存档'}
lines = ['# QA-03 加载实测', '',
         '单位毫秒。每组为一次自动化加载，最长帧为独立逐帧采样值；前两场首次材质使用也保留。', '',
         '| 目标 | 操作 | 旧版总时长 | 本版总时长 | 旧版最长帧 | 本版最长帧 | 本版加载帧数 |',
         '| ---: | --- | ---: | ---: | ---: | ---: | ---: |']
for r in after['report']['records']:
    key = (r['target'], r['case'])
    if key not in lookup:
        continue
    b = lookup[key]
    lines.append(f"| {r['target']:,} | {labels[r['case']]} | {b['wall_ms']:.2f} | {r['wall_ms']:.2f} | {b['max_frame_ms']:.2f} | {r['max_frame_ms']:.2f} | {r['loading_frames']} |")
(args.output / 'table.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
shutil.copyfile(args.after / 'loading.png', args.output / 'loading.png')
print(f'Loading report archived: {args.output}')
