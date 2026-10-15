"""Package engine captures into review JPGs, comparisons and a silent H.264 clip.
Artist tooling only: Python + Pillow + an explicitly supplied ffmpeg executable.
Never reads game saves or modifies runtime assets.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess
from PIL import Image, ImageDraw, ImageFont

CAPTIONS = {
    '01-birth': '出生 · 固定种子十万石样板',
    '02-full-basket': '拾石 · 实际采集填满背包',
    '03-first-shore': '投海 · 只计实际投入的石子',
    '04-mining-unlocked': '累计 128 石 · 穿山甲开始开山',
    '05-working-mountain': '开山 · 断面与碰撞同步降低',
    '06-relic-discovery': '神器出土 · 不打断操作',
    '07-quarry-complete': '完工 · 生成 1,024 石有限库存',
    '08-empty-quarry': '山址 · 第一座山已搬空',
    '09-new-land': '新陆地 · 首轮 1,152 石全部投海',
}

def comparison(left, right, labels, output, font):
    sheet = Image.new('RGB', (1440, 490), '#f4f2e7')
    draw = ImageDraw.Draw(sheet)
    for index, (path, label) in enumerate(zip((left, right), labels)):
        image = Image.open(path).convert('RGB').resize((720, 450), Image.Resampling.LANCZOS)
        sheet.paste(image, (index * 720, 40))
        draw.text((index * 720 + 16, 8), label, font=font, fill='#29413b')
    sheet.save(output, quality=90, optimize=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--walk', type=Path, required=True)
    parser.add_argument('--views', type=Path, required=True)
    parser.add_argument('--ffmpeg', type=Path, required=True)
    parser.add_argument('--fog-before', type=Path)
    parser.add_argument('--performance', type=Path)
    parser.add_argument('--font', type=Path, default=Path('C:/Windows/Fonts/msyh.ttc'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    dest = root / 'docs/art/validation/art07'
    reference = root / 'docs/art/reference/art07'
    frames = root / 'artifacts/art/art07-captioned-frames'
    for path in (dest, reference, frames):
        path.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(str(args.font), 20)
    small = ImageFont.truetype(str(args.font), 12)
    captured = []
    for folder in (args.walk, args.views):
        for source in sorted(folder.glob('*.png')):
            image = Image.open(source).convert('RGB')
            image.save(dest / (source.stem + '.jpg'), quality=88, optimize=True)
            captured.append(source)
    report = json.loads((args.walk / 'walkthrough.json').read_text(encoding='utf-8'))
    # Each stored frame came from a real render during movement, impact or the stage.
    # Keep original 10 fps timing inside clips; omitted intervals are explicit.
    for index, label in enumerate(report['clip_labels']):
        image = Image.new('RGB', (720, 510), '#f4f2e7')
        image.paste(Image.open(args.walk / 'clip' / ('%04d.png' % index)).convert('RGB'), (0, 0))
        draw = ImageDraw.Draw(image)
        draw.text((14, 456), CAPTIONS.get(label, label), font=font, fill='#29413b')
        draw.text((14, 486), '自动操作实机片段 · 剪辑省略往返与等待 · 无声 / 10 fps', font=small, fill='#68786c')
        image.save(frames / ('%04d.png' % index))
    movie = dest / 'resource-cycle.mp4'
    subprocess.run([str(args.ffmpeg.resolve()), '-y', '-hide_banner', '-loglevel', 'error',
                    '-framerate', '10', '-i', str(frames / '%04d.png'), '-frames:v', str(report['clip_frames']),
                    '-c:v', 'libx264', '-preset', 'medium', '-crf', '23', '-pix_fmt', 'yuv420p',
                    '-movflags', '+faststart', '-an', str(movie)], check=True)
    subprocess.run([str(args.ffmpeg.resolve()), '-hide_banner', '-loglevel', 'error', '-i', str(movie),
                    '-f', 'null', '-'], check=True)
    report['clip'] = {'path': 'docs/art/validation/art07/resource-cycle.mp4', 'size_bytes': movie.stat().st_size,
                      'seconds': report['clip_frames'] / 10, 'dimensions': [720, 510], 'audio': False,
                      'note': 'Edited real rendered excerpts, chronological order; cuts omit waits and most hauling trips.'}
    (reference / 'walkthrough.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (reference / 'views.json').write_text((args.views / 'views.json').read_text(encoding='utf-8'), encoding='utf-8')
    if args.performance:
        performance = json.loads(args.performance.read_text(encoding='utf-8'))
        names = {'coast-actions': '海岸移动、采集与投海', 'quarry-actions': '矿场采集、落地与拾回',
                 'occluded-flight': '绕山低空飞行与遮挡定位', 'large-overview': '一亿石地图全图'}
        table = ['| 场景 | p95 帧间隔（ms） | 最大单帧（ms） | 绘制调用中位数 |',
                 '| --- | ---: | ---: | ---: |']
        for case in performance['cases']:
            case.pop('frame_ms_raw', None)
            table.append('| %s | %.3f | %.3f | %d |' % (names[case['case']], case['frame_ms_p95'], case['frame_ms_max'], case['draw_calls_median']))
        (reference / 'performance-summary.json').write_text(json.dumps(performance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        review = root / 'docs/art/vertical-slice-review.md'
        text = review.read_text(encoding='utf-8')
        block = '<!-- PERFORMANCE_BEGIN -->\n' + '\n'.join(table) + '\n<!-- PERFORMANCE_END -->'
        text = text.replace('<!-- PERFORMANCE_TABLE -->', block)
        text = re.sub(r'<!-- PERFORMANCE_BEGIN -->.*?<!-- PERFORMANCE_END -->', lambda match: block, text, flags=re.S)
        review.write_text(text, encoding='utf-8')
    comparison(args.views / 'mountain-obscured-without-cue.png', args.views / 'mountain-obscured-with-cue.png',
               ['同版本：关闭遮挡提示', 'ART-07：仅遮挡时提示位置'], dest / 'occlusion-comparison.jpg', font)
    baseline = root / 'docs/art/reference/art00/screenshots/100000-coast.jpg'
    if not baseline.exists():
        baseline = next((root / 'docs/art/reference/art00').rglob('100000-coast.jpg'))
    comparison(baseline, args.views / 'coast-normal.png', ['ART-00 程序模型基线', 'ART-00～07 集成样板：同种子同镜头'], dest / 'baseline-comparison.jpg', font)
    if args.fog_before:
        comparison(args.fog_before, args.walk / '09-new-land.png', ['修正前：高处雾层遮入可达区域', 'ART-07：按近地面投影对齐边界'], dest / 'fog-comparison.jpg', font)
    rows = (len(captured) + 3) // 4
    sheet = Image.new('RGB', (1440, rows * 250), '#f4f2e7')
    draw = ImageDraw.Draw(sheet)
    for index, source in enumerate(captured):
        x, y = index % 4 * 360, index // 4 * 250
        sheet.paste(Image.open(source).convert('RGB').resize((360, 225), Image.Resampling.LANCZOS), (x, y))
        draw.text((x + 8, y + 228), source.stem, font=small, fill='#29413b')
    sheet.save(dest / 'contact-sheet.jpg', quality=90, optimize=True)
    print(json.dumps({'screenshots': len(captured), 'movie_seconds': report['clip_frames'] / 10,
                      'movie_bytes': movie.stat().st_size}, indent=2))

if __name__ == '__main__':
    main()
