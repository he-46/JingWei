"""ART-04 authored strata prototype; Blender 4.5: --background --python THIS.
Rebuilds three normalized environment assets, not gameplay data or other mountain types.
"""
from pathlib import Path
import json
import math
import sys
import bpy
import bmesh
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_glb import export

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/environment'
MODELS = ROOT / 'assets/models/environment'
TEXTURE = ROOT / 'assets/textures/environment/strata_paint.png'


def material():
    size = 1024
    v, u = np.mgrid[0:size, 0:size].astype(np.float32) / (size - 1)
    # Quiet horizontal sediment bands and sparse hand-drawn mineral seams.
    lower, upper = np.array([101, 125, 107]) / 255, np.array([174, 177, 150]) / 255
    shade = 0.96 + 0.025 * np.sin(u * 21 + v * 6) + 0.012 * np.cos(u * 113 + v * 19)
    seam = np.zeros_like(u)
    for level, width in [(0.12, .010), (.29, .008), (.48, .011), (.67, .008), (.84, .010)]:
        seam += np.exp(-((v - level - .005 * np.sin(u * 18 + level * 7)) / width) ** 2)
    shade -= seam * 0.19
    # Discontinuous, subdued vertical fractures: large planes stay readable.
    for x, phase in [(.17, 1), (.43, 2), (.72, 3), (.91, 4)]:
        crack = np.exp(-((u - x - .006 * np.sin(v * 31 + phase)) / .0017) ** 2)
        shade -= crack * .13 * (np.sin(v * 17 + phase) > -.2)
    pixels = np.ones((size, size, 4), np.float32)
    pixels[:, :, :3] = np.clip((lower + (upper - lower) * v[:, :, None]) * shade[:, :, None], 0, 1)
    image = bpy.data.images.new('Strata_PaintedRock', size, size, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw, image.file_format = str(TEXTURE), 'PNG'
    image.save()
    mat = bpy.data.materials.new('MAT_Strata_Rock')
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .95
    shader.inputs['Specular IOR Level'].default_value = .15
    texture = mat.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = image
    mat.node_tree.links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    return mat


def mesh(name, vertices, faces, uvs, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.materials.append(mat)
    layer = data.uv_layers.new(name='StrataUV')
    for face in data.polygons:
        face.use_smooth = False
        for loop in face.loop_indices:
            layer.data[loop].uv = uvs[data.loops[loop].vertex_index]
    # Recalculate outward faces; the exported mesh has no mirrored transforms.
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if any(not edge.is_manifold for edge in bm.edges):
        raise ValueError(name + ' must be a closed manifold')
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def strata(mat):
    sectors = 32
    # Close rings at each sediment shelf make crisp strata and nested cut surfaces.
    levels = [0, .025, .06, .10, .14, .17, .20, .24, .27, .30, .34, .38,
              .41, .44, .48, .52, .55, .58, .62, .66, .69, .72, .76, .80,
              .83, .86, .90, .94, .97, .99]
    profile = [(0, .94), (.06, .88), (.17, .83), (.20, .72), (.30, .69),
               (.34, .59), (.44, .56), (.48, .46), (.58, .43), (.62, .33),
               (.72, .30), (.76, .21), (.86, .18), (.90, .12), (.99, .015), (1, 0)]
    vertices, faces, uvs = [], [], []
    for y in levels:
        for a, b in zip(profile, profile[1:]):
            if a[0] <= y <= b[0]:
                r = a[1] + (b[1] - a[1]) * (y - a[0]) / (b[0] - a[0])
                break
        for i in range(sectors):
            angle = math.tau * i / sectors
            # Three large buttresses and an offset crown; nested rings never reverse.
            ridge = .80 + .11 * math.cos(angle * 3 + .3) + .07 * math.sin(angle * 2)
            x = math.cos(angle) * r * ridge + .12 * y
            z = math.sin(angle) * r * ridge * .87 - .035 * y
            vertices.append((x, -z, y))  # Blender Z up, Godot Y up.
            uvs.append((i / sectors, y))
    for row in range(len(levels) - 1):
        for i in range(sectors):
            nxt = (i + 1) % sectors
            faces.append((row * sectors + i, row * sectors + nxt,
                          (row + 1) * sectors + nxt, (row + 1) * sectors + i))
    apex = len(vertices)
    vertices.append((.12, .035, 1))
    uvs.append((.5, 1))
    for i in range(sectors):
        faces.append(((len(levels) - 1) * sectors + i,
                      (len(levels) - 1) * sectors + (i + 1) % sectors, apex))
    faces.append(tuple(reversed(range(sectors))))
    return mesh('StrataMountain', vertices, faces, uvs, mat)


def stone(mat):
    sectors = 9
    vertices, faces, uvs = [], [], []
    for row, (height, radius) in enumerate([(0, .42), (.12, .53), (.38, .41), (.51, .22)]):
        for i in range(sectors):
            angle = math.tau * i / sectors
            r = radius * (1 + .09 * math.sin(i * 2.4))
            vertices.append((math.cos(angle) * r, math.sin(angle) * r, height))
            uvs.append((i / sectors, .30 + height * .85))
    for row in range(3):
        for i in range(sectors):
            nxt = (i + 1) % sectors
            faces.append((row * sectors + i, row * sectors + nxt,
                          (row + 1) * sectors + nxt, (row + 1) * sectors + i))
    faces.extend([tuple(reversed(range(sectors))), tuple(27 + i for i in range(sectors))])
    return mesh('QuarryStone', vertices, faces, uvs, mat)


def site(mat):
    sectors = 32
    vertices, faces, uvs = [], [], []
    for row, (radius, height) in enumerate([(.94, .002), (.80, .018), (.50, .024), (.18, .017)]):
        for i in range(sectors):
            angle = math.tau * i / sectors
            r = radius * (.93 + .04 * math.sin(angle * 5))
            vertices.append((math.cos(angle) * r, math.sin(angle) * r * .9, height))
            uvs.append((.5 + math.cos(angle) * radius * .46, .5 + math.sin(angle) * radius * .46))
    for row in range(3):
        for i in range(sectors):
            nxt = (i + 1) % sectors
            faces.append((row * sectors + i, row * sectors + nxt,
                          (row + 1) * sectors + nxt, (row + 1) * sectors + i))
    faces.extend([tuple(reversed(range(sectors))), tuple(96 + i for i in range(sectors))])
    return mesh('QuarrySite', vertices, faces, uvs, mat)


def main():
    for directory in [SOURCE, MODELS, TEXTURE.parent]:
        directory.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    mat = material()
    report = {'generator': 'art_source/build_mountain.py', 'blender': bpy.app.version_string,
              'texture': TEXTURE.relative_to(ROOT).as_posix(), 'texture_size': [1024, 1024],
              'source': 'Original authored topology and painted rock; no third-party art.', 'assets': {}}
    for name, build in [('strata_mountain', strata), ('quarry_stone', stone), ('quarry_site', site)]:
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        obj = build(mat)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        source, model = SOURCE / (name + '.blend'), MODELS / (name + '.glb')
        bpy.ops.wm.save_as_mainfile(filepath=str(source))
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_as_mainfile(filepath=str(source))
        bpy.ops.wm.open_mainfile(filepath=str(source))
        obj = bpy.context.scene.objects[0]
        mat = obj.data.materials[0]
        export(model)
        report['assets'][name] = {'triangles': triangles, 'materials': 1,
                                  'source': source.relative_to(ROOT).as_posix(),
                                  'model': model.relative_to(ROOT).as_posix(), 'closed_manifold': True}
    (SOURCE / 'mountain-manifest.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('ART-04:', json.dumps(report['assets']))


if __name__ == '__main__':
    main()
