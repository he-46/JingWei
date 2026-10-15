"""ART-09 source/provenance audit. Python standard library only; no game changes."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPORT = 'docs/art/reference/art09/source-audit.json'
ENGINE_HASH = '6BF5B2D5BB1580D62615DE321EE4D5896CE0DB452603CA61F1AB9B5157D9AB87'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    listed = subprocess.check_output(['git', '-c', 'core.quotepath=false', 'ls-files', '--cached', '--others', '--exclude-standard'], cwd=ROOT).decode('utf-8').splitlines()
    files = sorted(set(listed) - {REPORT})
    forbidden = [p for p in files if p.startswith(('.tools/', '.godot/')) or (p.startswith('artifacts/') and p != 'artifacts/.gdignore') or p.endswith(('.blend1', '.blend2', '.pem', '.key')) or (p.startswith('Godot/') and p.endswith('.exe'))]
    if forbidden:
        raise ValueError('Local outputs or credentials would be distributed: ' + repr(forbidden))
    manifests = ['characters/jingwei-manifest.json', 'characters/pangolin-manifest.json',
                 'environment/mountain-manifest.json', 'environment/coast-manifest.json',
                 'environment/expansion-manifest.json', 'relics/relic-manifest.json']
    # Character manifests use a top-level model/source; environment manifests use assets.
    provenance = {}
    for relative in manifests:
        path = ROOT / 'art_source' / relative
        data = json.loads(path.read_text(encoding='utf-8'))
        if 'assets' in data:
            entries = data['assets'].values()
        else:
            entries = [data]
        for entry in entries:
            model = entry.get('model', entry.get('glb'))
            source = entry.get('source', entry.get('blend'))
            if not model:
                # Character filenames are stable and explicitly inspected at runtime.
                name = relative.split('/')[-1].split('-')[0]
                model, source = f'assets/models/characters/{name}.glb', f'art_source/characters/{name}.blend'
            provenance[model] = {'source': source, 'manifest': 'art_source/' + relative}
    formal = sorted(p for p in files if p.startswith('assets/models/') and p.endswith('.glb') and '/pipeline_examples/' not in p)
    if len(formal) != 36 or set(formal) != set(provenance):
        raise ValueError('Every formal model must have a source and production manifest')
    assets = []
    for path in formal:
        source = provenance[path]['source']
        if source not in files or not (ROOT / source).is_file():
            raise ValueError('Missing editable source: ' + str(source))
        blob = (ROOT / path).read_bytes()
        header_size = struct.unpack_from('<I', blob, 12)[0]
        gltf = json.loads(blob[20:20 + header_size])
        if any('uri' in item and not item['uri'].startswith('data:') for key in ('buffers', 'images') for item in gltf.get(key, [])):
            raise ValueError('GLB depends on an external image/buffer: ' + path)
        assets.append({'model': path, 'model_bytes': len(blob), 'model_sha256': hashlib.sha256(blob).hexdigest(),
                       **provenance[path], 'source_sha256': sha(ROOT / source)})
    engine = ROOT / 'Godot/Godot_v4.7.2-stable_win64.zip'
    if sha(engine).upper() != ENGINE_HASH:
        raise ValueError('Bundled engine hash does not match the launcher pin')
    notices = []
    for path in ['Godot/LICENSE.txt', 'Godot/COPYRIGHT.txt']:
        if not (ROOT / path).is_file() or (ROOT / path).stat().st_size == 0:
            raise ValueError('Missing engine license notice: ' + path)
        notices.append({'path': path, 'sha256': sha(ROOT / path)})
    totals = {}
    for path in files:
        group = path.split('/')[0] if '/' in path else 'root_files'
        totals[group] = totals.get(group, 0) + (ROOT / path).stat().st_size
    data = {'scope': 'Git-tracked plus non-ignored delivery candidates; this audit JSON excludes itself to avoid a self hash. Actual committed ZIP is verified separately.',
            'files_count_excluding_this_report': len(files), 'uncompressed_bytes_excluding_this_report': sum(totals.values()),
            'bytes_by_top_directory': totals, 'formal_models': assets,
            'audio': {'count': len(list((ROOT / 'assets/audio').glob('*.wav'))), 'generator': 'tools/generate_audio.py', 'external_recordings': 0},
            'font_files_bundled': [p for p in files if p.lower().endswith(('.ttf', '.otf', '.woff', '.woff2'))],
            'engine_sha256': ENGINE_HASH, 'engine_notices': notices,
            'project_license_file_present': any((ROOT / name).exists() for name in ['LICENSE', 'LICENSE.md', 'LICENSE.txt']),
            'license_note': 'Original project assets have provenance records; no project-wide redistribution license has been selected. Godot and its bundled third-party notices remain separate.'}
    destination = ROOT / REPORT
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('SOURCE AUDIT:', len(assets), 'formal models;', len(files), 'delivery files;', round(sum(totals.values()) / 1048576, 2), 'MiB uncompressed excluding this report')


if __name__ == '__main__':
    main()
