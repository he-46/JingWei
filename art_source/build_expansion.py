"""ART-08 original variants. Run with Python + bpy 4.5 or Blender --background --python.
Reads existing painted atlases; never rewrites earlier source files or gameplay data.
"""
from pathlib import Path
import json
import math
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_mountain import mesh, strata
from build_coast import cluster, grass
from mesh_tools import MeshBuilder
from export_glb import export

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/environment'
MODELS = ROOT / 'assets/models/environment'
MOUNTAINS = ['strata_mountain', 'spire_mountain', 'twin_mountain', 'ridge_mountain',
             'mesa_mountain', 'needle_mountain', 'split_mountain', 'crag_mountain']


def painted(name, texture):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .95
    shader.inputs['Specular IOR Level'].default_value = .15
    node = mat.node_tree.nodes.new('ShaderNodeTexImage')
    node.image = bpy.data.images.load(str(ROOT / 'assets/textures/environment' / texture), check_existing=True)
    mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Base Color'])
    return mat


def height(shape, x, z, r):
    taper = min(1, (1 - r) * 7)
    if shape == 0:
        return max(0, 1 - r) ** .65
    if shape == 1:
        return max(0, 1 - r) ** 1.55
    if shape == 2:
        return max(math.exp(-13 * ((x - .32) ** 2 + z * z)),
                   .88 * math.exp(-16 * ((x + .38) ** 2 + (z - .1) ** 2))) * taper
    if shape == 3:
        return max(0, 1 - abs(z) * 2.6) ** 1.2 * max(0, 1 - abs(x)) ** .35 * (.80 + .20 * math.cos(x * 12)) * taper
    if shape == 4:
        return min(1, max(0, 1 - r) * 2.9) * (.96 + .04 * math.cos(x * 3))
    if shape == 5:
        return math.exp(-12 * ((x - .12) ** 2 + (z + .08) ** 2)) * taper
    if shape == 6:
        return max(math.exp(-24 * ((x - .38) ** 2 + (z + .12) ** 2)),
                   .78 * math.exp(-22 * ((x + .35) ** 2 + (z - .23) ** 2))) * taper
    return max(0, 1 - abs(z) * 3.2) ** .8 * max(0, 1 - abs(x)) ** .25 * (.72 + .28 * math.cos(x * 17 + .5)) * taper


def mountain(mat, shape, low=False):
    # A single-valued height field closes against a ground cap. Clamping its Y
    # yields a continuous solid cut surface even across separate summits.
    rings, sectors = (10, 24) if low else (24, 40)
    vertices, uvs, faces = [(0, 0, height(shape, 0, 0, 0))], [(.5, 1)], []
    for row in range(1, rings + 1):
        r = row / rings
        for i in range(sectors):
            a = math.tau * i / sectors
            edge = .87 + .035 * math.sin(5 * a + shape) + .025 * math.cos(3 * a)
            x, z = math.cos(a) * r, math.sin(a) * r
            # A shallow rocky apron keeps tiny Gaussian tails above the ground;
            # otherwise nearly coplanar triangles shimmer in the real renderer.
            y = max(height(shape, x, z, r), .12 * (1 - r))
            vertices.append((x * edge, -z * edge, y))
            uvs.append((i / sectors, y))
    peak = max(v[2] for v in vertices)
    vertices = [(x, z, y / peak) for x, z, y in vertices]
    uvs = [(u, v / peak) for u, v in uvs]
    for i in range(sectors):
        faces.append((0, 1 + i, 1 + (i + 1) % sectors))
    for row in range(rings - 1):
        for i in range(sectors):
            a = 1 + row * sectors + i
            b = 1 + row * sectors + (i + 1) % sectors
            faces.append((a, b, b + sectors, a + sectors))
    faces.append(tuple(reversed(range(1 + (rings - 1) * sectors, 1 + rings * sectors))))
    return mesh(MOUNTAINS[shape], vertices, faces, uvs, mat)


def stone(mat, variant):
    # Six readable profiles including the previous quarry stone (variant 0).
    profiles = [None, [(.0, .48), (.08, .58), (.21, .51), (.27, .28)],
                [(0, .28), (.17, .38), (.56, .30), (.68, .10)],
                [(0, .40), (.08, .54), (.36, .48), (.39, .39)],
                [(0, .35), (.12, .57), (.31, .37), (.48, .12)],
                [(0, .30), (.06, .52), (.17, .48), (.23, .18)]]
    sectors = [0, 8, 7, 6, 9, 10][variant]
    vertices, uvs, faces = [], [], []
    for row, (y, radius) in enumerate(profiles[variant]):
        for i in range(sectors):
            a = math.tau * i / sectors
            irregular = 1 + .10 * math.sin(i * 2.4 + variant)
            vertices.append((math.cos(a) * radius * irregular, math.sin(a) * radius * (.63 if variant in (1, 5) else .88), y))
            uvs.append((i / sectors, .30 + y * .85))
    for row in range(3):
        for i in range(sectors):
            a, b = row * sectors + i, row * sectors + (i + 1) % sectors
            faces.append((a, b, b + sectors, a + sectors))
    faces += [tuple(reversed(range(sectors))), tuple(3 * sectors + i for i in range(sectors))]
    return mesh('ScatterStone', vertices, faces, uvs, mat)


def foliage(mat, name):
    b = MeshBuilder(mat)
    if name == 'coast_pine':
        b.tube('Trunk', [(0, 0, 0), (.04, .02, 1.4), (.07, .04, 3.5)], .13, '', 0, 7)
        for i, (z, radius) in enumerate([(1.55, .80), (2.15, .66), (2.72, .48), (3.25, .28)]):
            cluster(b, 'PineTier', (.05, .02, z), (radius, radius * .8, .44), 2 + i % 2, 10, 3)
    elif name == 'coast_wind_tree':
        b.tube('BentTrunk', [(0, 0, 0), (.22, 0, .85), (.61, 0, 1.7), (.90, .02, 2.4)], .16, '', 0, 7)
        b.tube('ExposedFork', [(.35, 0, 1.2), (-.25, .04, 1.7), (-.45, .08, 2.1)], .085, '', 1, 6)
        for c, s in [((-.3, .06, 2.15), (.52, .48, .38)), ((.38, -.03, 2.4), (.72, .57, .42)), ((.98, .01, 2.65), (.55, .54, .40))]:
            cluster(b, 'WindCrown', c, s, 3, 10, 4)
    elif name == 'coast_scrub':
        for i in range(4):
            a = i * math.tau / 4
            c = (.32 * math.cos(a), .25 * math.sin(a), .27 + .06 * (i % 2))
            b.tube('Stem', [(0, 0, 0), c], .035, '', 0, 5)
            cluster(b, 'ScrubCrown', c, (.28, .24, .21), 4, 7, 3)
    else:
        # Low spreading leaves, unlike the upright six-blade sample.
        grass(b)
        for obj in b.parts:
            for v in obj.data.vertices:
                v.co.x *= 1.6
                v.co.y *= 1.6
                v.co.z *= .6
    bpy.ops.object.select_all(action='DESELECT')
    for obj in b.parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = b.parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.vertex_groups.clear()
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    report = {'generator': 'art_source/build_expansion.py', 'blender': bpy.app.version_string,
              'source': 'Original project topology; existing original painted atlases.', 'assets': {}}
    builds = [(name, 'strata_paint.png', lambda mat, i=i: mountain(mat, i)) for i, name in enumerate(MOUNTAINS) if i]
    # Original shape zero is decimated from its exact authored source for overview.
    builds += [(name + '_far', 'strata_paint.png', lambda mat, i=i: mountain(mat, i, True)) for i, name in enumerate(MOUNTAINS) if i]
    builds += [('strata_mountain_far', 'strata_paint.png', strata)]
    builds += [('scatter_stone_%d' % i, 'strata_paint.png', lambda mat, i=i: stone(mat, i)) for i in range(1, 6)]
    builds += [(name, 'coast_palette.png', lambda mat, name=name: foliage(mat, name)) for name in ['coast_pine', 'coast_wind_tree', 'coast_scrub', 'coast_low_grass']]
    for name, atlas, build in builds:
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        mat = painted('MAT_' + atlas, atlas)
        obj = build(mat)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        if name == 'strata_mountain_far':
            modifier = obj.modifiers.new('Overview', 'DECIMATE')
            modifier.ratio = .25
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            peak = max(v.co.z for v in obj.data.vertices)
            for vertex in obj.data.vertices:
                vertex.co.z = max(0, vertex.co.z / peak)
        triangles = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        source, model = SOURCE / (name + '.blend'), MODELS / (name + '.glb')
        bpy.ops.wm.save_as_mainfile(filepath=str(source))
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_as_mainfile(filepath=str(source))
        bpy.ops.wm.open_mainfile(filepath=str(source))
        # Runtime material overrides share the two external atlases. Keep painted
        # materials in the editable source; omit duplicate image payloads in GLB.
        export(model, materials=False)
        report['assets'][name] = {'triangles': triangles, 'materials': 1, 'glb_embedded_materials': 0, 'embedded_images': 0, 'atlas': atlas,
                                  'source': source.relative_to(ROOT).as_posix(), 'model': model.relative_to(ROOT).as_posix()}
    (SOURCE / 'expansion-manifest.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('ART-08:', json.dumps(report['assets']))


if __name__ == '__main__':
    main()
