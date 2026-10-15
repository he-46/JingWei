"""Package final engine captures; Python/Pillow + explicit ffmpeg, no game edits."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAPTIONS = {'01-birth': '出生 · 十万石海岸', '02-full-basket': '拾石 · 满背包',
            '03-first-shore': '投海 · 石子产生修行', '04-mining-unlocked': '累计 128 石 · 穿山甲开始开山',
            '05-working-mountain': '开山 · 岩层逐渐降低', '06-relic-discovery': '神器出土',
            '07-quarry-complete': '完工 · 1,024 石有限库存', '08-empty-quarry': '第一座山已搬空',
            '09-new-land': '累计 1,152 石 · 新陆地形成'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ffmpeg', type=Path, required=True)
    args = parser.parse_args()
    walk = ROOT / 'artifacts/art/art09-walk'
    views = ROOT / 'artifacts/art/art09-views'
    regression = ROOT / 'artifacts/art/art09-review'
    audit = ROOT / 'artifacts/art/art09-audit'
    destination = ROOT / 'docs/art/validation/art09'
    reference = ROOT / 'docs/art/reference/art09'
    frames = ROOT / 'artifacts/art/art09-captioned-frames'
    for path in (destination, reference, frames):
        path.mkdir(parents=True, exist_ok=True)
    report = json.loads((walk / 'walkthrough.json').read_text(encoding='utf-8'))
    if report['failures'] or report['final_delivered'] != 1152:
        raise ValueError('Final real resource cycle did not pass')
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 20)
    small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 13)
    captured = []
    for target in [100000, 1000000, 10000000, 100000000]:
        for view in ['new-coast', 'overview']:
            captured.append((regression / f'{target}-{view}.png', f'{target:,} 石 · ' + ('新开局' if view == 'new-coast' else '全图')))
    for name in ['coast-normal', 'mountain-normal', 'high-flight', 'coast-1152', 'obscured-1152', 'boundary-water']:
        captured.append((views / f'{name}.png', name))
    captured += [(regression / 'legacy-continued.png', '旧档迁移后继续'),
                 (regression / '100000000-completed.png', '回归夹具 · 一亿石完成面板')]
    captured += [(walk / f'{name}.png', caption) for name, caption in CAPTIONS.items()]
    sheet = Image.new('RGB', (1440, ((len(captured) + 3) // 4) * 250), '#f4f2e7')
    draw = ImageDraw.Draw(sheet)
    for i, (path, caption) in enumerate(captured):
        image = Image.open(path).convert('RGB')
        x, y = i % 4 * 360, i // 4 * 250
        sheet.paste(image.resize((360, 225), Image.Resampling.LANCZOS), (x, y))
        draw.text((x + 7, y + 228), caption, font=small, fill='#29413b')
    sheet.save(destination / 'contact-sheet.jpg', quality=91, optimize=True)
    comparison = Image.new('RGB', (1440, 490), '#f4f2e7')
    text = ImageDraw.Draw(comparison)
    for index, (name, label) in enumerate([('shadow-before', '修正前：尖峰自阴影细纹'), ('shadow-after', 'ART-09：提高深度偏移，相同镜头')]):
        comparison.paste(Image.open(regression / (name + '.png')).convert('RGB').resize((720, 450), Image.Resampling.LANCZOS), (index * 720, 40))
        text.text((index * 720 + 14, 8), label, font=font, fill='#29413b')
    comparison.save(destination / 'shadow-comparison.jpg', quality=92, optimize=True)
    for source in [views / 'coast-normal.png', views / 'mountain-normal.png', views / 'high-flight.png',
                   views / 'coast-1152.png', regression / '100000000-overview.png',
                   regression / '100000000-completed.png', walk / '07-quarry-complete.png', walk / '09-new-land.png']:
        Image.open(source).convert('RGB').save(destination / (source.stem + '.jpg'), quality=90, optimize=True)
    for index, label in enumerate(report['clip_labels']):
        image = Image.new('RGB', (720, 510), '#f4f2e7')
        image.paste(Image.open(walk / 'clip' / f'{index:04d}.png').convert('RGB'), (0, 0))
        text = ImageDraw.Draw(image)
        text.text((14, 456), CAPTIONS.get(label, label), font=font, fill='#29413b')
        text.text((14, 486), '实机操作剪辑 · 省略往返与等待 · 无声 / 10 fps', font=small, fill='#68786c')
        image.save(frames / f'{index:04d}.png')
    movie = destination / 'resource-cycle.mp4'
    subprocess.run([str(args.ffmpeg.resolve()), '-y', '-hide_banner', '-loglevel', 'error', '-framerate', '10',
                    '-i', str(frames / '%04d.png'), '-frames:v', str(report['clip_frames']), '-c:v', 'libx264',
                    '-preset', 'medium', '-crf', '23', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', str(movie)], check=True)
    subprocess.run([str(args.ffmpeg.resolve()), '-hide_banner', '-loglevel', 'error', '-i', str(movie), '-f', 'null', '-'], check=True)
    report['clip'] = {'path': movie.relative_to(ROOT).as_posix(), 'bytes': movie.stat().st_size, 'seconds': report['clip_frames'] / 10,
                      'dimensions': [720, 510], 'audio': False, 'note': 'Real ordinary gameplay at fixed simulation step; edited excerpts omit waits and most hauling. Video frame rate is not a performance measurement.'}
    (reference / 'walkthrough.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for name in ['runtime-assets.json', 'release-regression.json']:
        shutil.copyfile(audit / name, reference / name)
    shutil.copyfile(views / 'views.json', reference / 'views.json')
    print('ART-09 packaged:', len(captured), 'review views;', report['clip_frames'] / 10, 'seconds;', movie.stat().st_size, 'video bytes')


if __name__ == '__main__':
    main()
