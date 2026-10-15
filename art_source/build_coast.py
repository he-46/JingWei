"""ART-05 original coastal tree, shrub, grass and wet-rock samples.
Blender 4.5: --background --python THIS. Does not rebuild previous packages.
"""
from pathlib import Path
import json
import math
import sys
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mesh_tools import MeshBuilder
from export_glb import export

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/environment'
MODELS = ROOT / 'assets/models/environment'
TEXTURE = ROOT / 'assets/textures/environment/coast_palette.png'
PALETTE = ['6b5541', '4d4436', '355a46', '4a6c4f', '64845e', '81966a',
           '7f9a64', '526f48', '677673', '425f60', '9aa494', 'b7b99e',
           'baa982', '8a795d', '365746', 'abaf72']


def material():
    size, tile = 512, 128
    pixels = np.ones((size, size, 4), np.float32)
    v, u = np.mgrid[0:tile, 0:tile].astype(np.float32) / (tile - 1)
    for index, color in enumerate(PALETTE):
        rgb = np.array([int(color[i:i + 2], 16) / 255 for i in (0, 2, 4)])
        shade = .95 + .07 * np.sin(v * math.pi) + .025 * np.cos(u * math.pi * 2)
        if index in (0, 1, 12, 13):
            shade += .025 * np.sin(u * 40 + np.sin(v * 11))
        elif index in (8, 9, 10, 11):
            shade += .025 * np.cos(v * 18 + u * 3)
        else:
            shade += .02 * np.sin((u + v) * 10)
        row, col = divmod(index, 4)
        pixels[row * tile:(row + 1) * tile, col * tile:(col + 1) * tile, :3] = np.clip(rgb * shade[:, :, None], 0, 1)
    image = bpy.data.images.new('Coast_PaintedPalette', size, size, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw, image.file_format = str(TEXTURE), 'PNG'
    image.save()
    mat = bpy.data.materials.new('MAT_Coast_Palette')
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .9
    shader.inputs['Specular IOR Level'].default_value = .15
    texture = mat.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = image
    mat.node_tree.links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    return mat


def cluster(builder, name, center, size, swatch, sectors=10, rows=4):
    sections = []
    # Ring silhouette is deliberately flattened at the shoulders, rather than a sphere/cone.
    for row in range(rows + 1):
        t = row / rows
        z = center[2] + (t * 2 - 1) * size[2]
        radius = max(.02, math.sin(t * math.pi) ** .65)
        sections.append(((center[0] + .08 * math.sin(t * 4), center[1], z),
                         (size[0] * radius, 0, 0), (0, size[1] * radius, 0)))
    obj = builder.rings(name, sections, sectors, lambda _p, _t: {},
                        lambda _p, t: swatch + (1 if t > .52 else 0))
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def tree(builder):
    builder.tube('LeaningTrunk', [(0, 0, 0), (.025, 0, .65), (.12, 0, 1.35), (.24, .02, 2.3)], .16, '', 0, 7)
    builder.tube('ForkWest', [(.10, 0, 1.12), (-.35, .03, 1.65), (-.52, .05, 2.12)], .095, '', 1, 6)
    builder.tube('ForkEast', [(.12, 0, 1.36), (.51, -.08, 1.85), (.65, -.12, 2.35)], .085, '', 0, 6)
    for index, (center, size, swatch) in enumerate([
        ((-.49, .02, 2.05), (.53, .57, .55), 2),
        ((.60, -.04, 2.30), (.51, .53, .55), 3),
        ((.15, .25, 2.64), (.65, .55, .59), 3),
        ((.05, -.37, 2.47), (.55, .49, .49), 2),
        ((.25, .00, 2.95), (.45, .43, .43), 4),
    ]):
        cluster(builder, 'Crown_%02d' % index, center, size, swatch)


def shrub(builder):
    for index, (center, size, swatch) in enumerate([
        ((-.28, .02, .27), (.38, .36, .25), 2),
        ((.26, .01, .35), (.43, .39, .33), 3),
        ((.00, -.22, .42), (.35, .36, .30), 4),
    ]):
        cluster(builder, 'Shrub_%d' % index, center, size, swatch, 8, 3)
    builder.tube('ShrubStem', [(0, 0, 0), (.03, 0, .45)], .045, '', 0, 5)


def grass(builder):
    for leaf in range(6):
        angle = leaf * 2.39996
        height = .27 + .045 * (leaf % 4)
        across = Vector((math.cos(angle), math.sin(angle), 0))
        bend = Vector((-math.sin(angle), math.cos(angle), 0))
        vertices, uvs, faces = [], [], []
        for row, t in enumerate([0, .5, 1]):
            center = bend * (.16 * t * t)
            center.z = height * t
            width = .045 * (1 - .95 * t)
            for side in [-1, 1]:
                vertices.append(tuple(center + across * width * side))
                uvs.append((.5 + side * .4, t))
        for row in range(2):
            faces.append((row * 2, row * 2 + 1, row * 2 + 3, row * 2 + 2))
        obj = builder.mesh('GrassLeaf_%d' % leaf, vertices, faces, [{} for _ in vertices], [6 + leaf % 2] * 2, uvs, False)


def shore_rock(builder):
    sections = []
    for height, radius in [(0, .67), (.05, .90), (.15, .97), (.36, .70), (.46, .36)]:
        sections.append(((.04 * height, 0, height), (radius * .65, 0, 0), (0, radius * .45, 0)))
    obj = builder.rings('ShoreRock', sections, 10, lambda _p, _t: {}, lambda _p, t: 8 if t < .45 else 10)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False


def main():
    for path in (SOURCE, MODELS, TEXTURE.parent):
        path.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    mat = material()
    report = {'generator': 'art_source/build_coast.py', 'blender': bpy.app.version_string,
              'texture': TEXTURE.relative_to(ROOT).as_posix(), 'texture_size': [512, 512],
              'source': 'Original project mesh and painted palette; no third-party art.', 'assets': {}}
    for name, build in [('coast_tree', tree), ('coast_shrub', shrub), ('coast_grass', grass), ('shore_rock', shore_rock)]:
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        builder = MeshBuilder(mat)
        build(builder)
        bpy.ops.object.select_all(action='DESELECT')
        for obj in builder.parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = builder.parts[0]
        if len(builder.parts) > 1:
            bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = name
        triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        source, model = SOURCE / (name + '.blend'), MODELS / (name + '.glb')
        bpy.ops.wm.save_as_mainfile(filepath=str(source))
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_as_mainfile(filepath=str(source))
        bpy.ops.wm.open_mainfile(filepath=str(source))
        mat = bpy.context.scene.objects[0].data.materials[0]
        export(model)
        report['assets'][name] = {'triangles': triangles, 'materials': 1,
                                  'source': source.relative_to(ROOT).as_posix(),
                                  'model': model.relative_to(ROOT).as_posix(), 'open_blades': name == 'coast_grass'}
    (SOURCE / 'coast-manifest.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('ART-05:', json.dumps(report['assets']))


if __name__ == '__main__':
    main()
