"""ART-02 original sculpted-mesh bird. Blender 4.5.3 / official bpy module.

blender --background --python art_source/build_jingwei.py
Rebuilds only this production asset; hand edits should use export_glb.py instead.
"""
from pathlib import Path
import json
import math
import sys
import bpy
import bmesh
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_glb import export

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/characters/jingwei.blend'
MODEL = ROOT / 'assets/models/characters/jingwei.glb'
TEXTURE = ROOT / 'assets/textures/characters/jingwei_atlas.png'
REPORT = ROOT / 'art_source/characters/jingwei-manifest.json'
PALETTE = ['305f70', '244552', '649b9d', 'fff0ca', 'da684d', 'a6453b',
           'e9b956', '132c36', 'f9f5df', 'b99158', 'c7c7b7', '8d9584',
           '427b89', '1e414f', 'd7b77d', 'e3dac0']
PARTS = []
RIG = None
MAT = None


def atlas():
    """A UV paint atlas: broad brush bands and restrained feather vein strokes."""
    size, tile = 1024, 256
    pixels = np.ones((size, size, 4), dtype=np.float32)
    v, u = np.mgrid[0:tile, 0:tile].astype(np.float32) / (tile - 1)
    for index, color in enumerate(PALETTE):
        rgb = np.array([int(color[i:i + 2], 16) / 255 for i in (0, 2, 4)])
        broad = 0.93 + 0.10 * np.sin(v * math.pi) + 0.035 * np.sin(u * 7 + v * 3 + index)
        stroke = 0.012 * np.sin(u * 38 + np.sin(v * 13) * 2) * np.sin(v * math.pi)
        grain = 0.005 * np.sin(u * 139 + v * 83) * np.cos(v * 151 - u * 59)
        if index in (0, 1, 2, 3, 4, 5, 12, 13):
            vein = np.exp(-((u - 0.5) / 0.018) ** 2) * np.sin(v * math.pi) * 0.05
            barbs = np.maximum(0, np.cos((v + np.abs(u - 0.5) * 0.42) * 79)) ** 16 * 0.025
        else:
            vein, barbs = 0, 0
        shade = broad + stroke + grain + vein - barbs
        painted = np.clip(rgb[None, None, :] * shade[:, :, None], 0, 1)
        row, col = divmod(index, 4)
        pixels[row * tile:(row + 1) * tile, col * tile:(col + 1) * tile, :3] = painted
    image = bpy.data.images.new('Jingwei_PaintedAtlas', size, size, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(TEXTURE)
    image.file_format = 'PNG'
    image.save()
    mat = bpy.data.materials.new('MAT_Jingwei_Feather')
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = 0.86
    bsdf.inputs['Specular IOR Level'].default_value = 0.22
    tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = image
    mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    return mat


def tile_uv(index, u, v):
    row, col = divmod(index, 4)
    # Eight-pixel gutters keep bilinear/mip filtering inside each paint swatch.
    return ((col + 0.035 + u * 0.93) / 4, (row + 0.035 + v * 0.93) / 4)


def skin_object(name, vertices, faces, weights, colors, uvs):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(MAT)
    layer = mesh.uv_layers.new(name='PaintUV')
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        swatch = colors[polygon.index]
        for loop in polygon.loop_indices:
            index = mesh.loops[loop].vertex_index
            layer.data[loop].uv = tile_uv(swatch, *uvs[index])
    for index, influences in enumerate(weights):
        for bone, value in influences.items():
            group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
            group.add([index], value, 'REPLACE')
    PARTS.append(obj)
    return obj


def rings_mesh(name, rings, sectors, weight_fn, color_fn, subdivide=False):
    vertices, weights, uvs, faces, colors = [], [], [], [], []
    for ring, (center, cross_a, cross_b) in enumerate(rings):
        t = ring / (len(rings) - 1)
        for segment in range(sectors):
            angle = segment / sectors * math.tau
            p = Vector(center) + Vector(cross_a) * math.sin(angle) + Vector(cross_b) * math.cos(angle)
            vertices.append(tuple(p))
            weights.append(weight_fn(p, t))
            uvs.append((segment / sectors, t))
    for ring in range(len(rings) - 1):
        for segment in range(sectors):
            nxt = (segment + 1) % sectors
            faces.append((ring * sectors + segment, ring * sectors + nxt, (ring + 1) * sectors + nxt, (ring + 1) * sectors + segment))
            average = sum((Vector(vertices[i]) for i in faces[-1]), Vector()) / 4
            colors.append(color_fn(average, (ring + 0.5) / (len(rings) - 1)))
    faces.extend([tuple(reversed(range(sectors))), tuple((len(rings) - 1) * sectors + i for i in range(sectors))])
    colors.extend([color_fn(Vector(rings[0][0]), 0), color_fn(Vector(rings[-1][0]), 1)])
    obj = skin_object(name, vertices, faces, weights, colors, uvs)
    # Correct orientation geometrically, including leaf directions and caps.
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    if subdivide:
        modifier = obj.modifiers.new('SculptSurface', 'SUBSURF')
        modifier.levels = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)
    return obj


def body():
    # One watertight loft, from rump through breast/neck/head to the beak tip.
    sections = [(-0.68, 0.09, -0.09, 0.10), (-0.54, 0.25, -0.04, 0.27),
                (-0.34, 0.35, 0.00, 0.37), (-0.10, 0.39, 0.025, 0.42),
                (0.13, 0.35, 0.09, 0.43), (0.30, 0.27, 0.20, 0.38),
                (0.40, 0.235, 0.34, 0.31), (0.53, 0.285, 0.46, 0.29),
                (0.69, 0.28, 0.48, 0.265), (0.82, 0.22, 0.435, 0.21),
                (0.89, 0.14, 0.38, 0.115), (0.925, 0.145, 0.365, 0.085),
                (1.04, 0.115, 0.34, 0.064), (1.20, 0.055, 0.30, 0.035),
                (1.27, 0.006, 0.285, 0.006)]
    rings = [((0, y, z), (rx, 0, 0), (0, 0, rz)) for y, rx, z, rz in sections]
    def weights(p, _t):
        head = max(0, min(1, (p.y - 0.25) / 0.3))
        return {'Spine': 1 - head, 'Head': head} if 0 < head < 1 else {'Head' if head else 'Spine': 1}
    def color(p, _t):
        if p.y > 0.90:
            return 6
        if p.y > 0.41 and p.z > 0.64:
            return 4
        if (p.z < 0.02 and p.y > -0.45) or (p.y > 0.38 and p.z < 0.44):
            return 3
        return 0 if p.z > 0.02 else 12
    return rings_mesh('ContinuousBodyHeadBeak', rings, 20, weights, color, True)


def leaf(name, start, end, width, bone, swatch=0, tip=None, curve=0.035, rings_count=9):
    start, end = Vector(start), Vector(end)
    direction = (end - start).normalized()
    across = Vector((-direction.y, direction.x, 0)).normalized()
    normal = direction.cross(across).normalized()
    rings = []
    for index in range(rings_count):
        t = index / (rings_count - 1)
        center = start.lerp(end, t) + Vector((0, 0, curve * math.sin(t * math.pi)))
        profile = max(0.025, math.sin(math.pi * t) ** 0.65) * (1 - t * 0.25)
        rings.append((center, across * width * profile, normal * width * profile * 0.16))
    return rings_mesh(name, rings, 8, lambda _p, _t: {bone: 1}, lambda _p, t: tip if tip is not None and t > 0.77 else swatch)


def ellipsoid(name, location, scale, bone, swatch, segments=10, rows=5):
    rings = []
    for index in range(rows + 1):
        t = index / rows * math.pi
        radius = max(0.01, math.sin(t))
        rings.append(((location[0], location[1] + math.cos(t) * scale[1], location[2]),
                      (scale[0] * radius, 0, 0), (0, 0, scale[2] * radius)))
    return rings_mesh(name, rings, segments, lambda _p, _t: {bone: 1}, lambda _p, _t: swatch)


def tube(name, points, radius, bone, swatch, sectors=6):
    rings = []
    for index, point in enumerate(points):
        tangent = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])
        tangent.normalize()
        across = tangent.cross(Vector((0, 0, 1)))
        if across.length < 0.01:
            across = tangent.cross(Vector((0, 1, 0)))
        across.normalize()
        normal = tangent.cross(across).normalized()
        r = radius * (1 - index / len(points) * 0.4)
        rings.append((point, across * r, normal * r))
    return rings_mesh(name, rings, sectors, lambda _p, _t: {bone: 1}, lambda _p, _t: swatch)


def feathers_and_details():
    for sign, side in [(-1, 'L'), (1, 'R')]:
        leaf('WingMantle_' + side, (sign * 0.23, 0.12, 0.13), (sign * 1.28, -0.14, 0.13), 0.30, 'Wing_' + side, 1)
        for index in range(6):
            leaf('Primary_%s_%02d' % (side, index), (sign * (0.42 + index * 0.11), -0.02, 0.12),
                 (sign * (0.60 + index * 0.18), -0.84 + index * 0.09, 0.06),
                 0.135 - index * 0.004, 'Wrist_' + side, 0 if index % 2 else 12, 3, curve=0.055)
        for index in range(4):
            leaf('Covert_%s_%02d' % (side, index), (sign * (0.28 + index * 0.18), 0.10, 0.18),
                 (sign * (0.42 + index * 0.20), -0.40 + index * 0.015, 0.18), 0.12,
                 'Wing_' + side, 12, 2, curve=0.04, rings_count=7)
        leaf('Scapular_' + side, (sign * 0.20, 0.24, 0.30), (sign * 0.46, -0.35, 0.29), 0.12, 'Spine', 0, 2, rings_count=7)
        # Eyes are deliberate inlays on the continuous head surface.
        ellipsoid('EyeMask_' + side, (sign * 0.258, 0.67, 0.54), (0.023, 0.13, 0.105), 'Head', 3)
        ellipsoid('Eye_' + side, (sign * 0.279, 0.695, 0.55), (0.023, 0.079, 0.071), 'Head', 7)
        ellipsoid('EyeLight_' + side, (sign * 0.300, 0.725, 0.578), (0.008, 0.022, 0.023), 'Head', 8, 8, 4)
        # Three retracted toes remain readable in a dive without dangling sticks.
        for toe in range(3):
            x = sign * (0.17 + (toe - 1) * 0.045)
            tube('Claw_%s_%s' % (side, toe), [(x, 0.02, -0.31), (x, 0.14, -0.43), (x, 0.30, -0.42)], 0.027, 'Foot_' + side, 6)
    for index, (x, end_y, swatch, bone) in enumerate([(-0.36, -1.48, 0, 'Tail_L'), (0, -1.78, 4, 'Tail_C'), (0.36, -1.48, 0, 'Tail_R')]):
        leaf('TailFan_%d' % index, (x * 0.22, -0.48, -0.10), (x, end_y, -0.015), 0.20 if x else 0.235, bone, swatch, 3 if x else 6, curve=0.08)
    for index in range(3):
        x = (index - 1) * 0.12
        leaf('ScarletCrest_%d' % index, (x * 0.6, 0.69, 0.69), (x, 0.21 - abs(index - 1) * 0.04, 1.04 - abs(index - 1) * 0.10),
             0.095, 'Head', 4 if index == 1 else 5, 4, curve=0.02, rings_count=7)


def join_parts(name, objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.parent = RIG
    obj.modifiers.new('FeatherSkin', 'ARMATURE').object = RIG
    obj.select_set(False)
    return obj


def cargo(name, full):
    initial = len(PARTS)
    # A shallow woven sling sits behind the shoulder line, leaving the crest clear.
    ellipsoid('WovenBowl', (0, -0.22, 0.41), (0.29, 0.27, 0.085), 'Spine', 9)
    for row in range(3):
        z = 0.43 + row * 0.025
        points = [(math.cos(a) * 0.28, -0.22 + math.sin(a) * 0.26, z) for a in np.linspace(0, math.tau, 13)]
        tube('ReedRim', points, 0.016, 'Spine', 14, 5)
    for x in (-0.18, 0, 0.18):
        tube('ReedWeave', [(x, -0.46, 0.43), (x, -0.22, 0.40), (x, 0.02, 0.43)], 0.013, 'Spine', 14, 5)
    locations = [(0, -0.22, 0.51)] if not full else [(-0.12, -0.32, 0.53), (0.12, -0.30, 0.54), (0, -0.10, 0.55), (0.01, -0.25, 0.69)]
    for index, location in enumerate(locations):
        ellipsoid('Stone_%d' % index, location, (0.12, 0.12, 0.10), 'Spine', 10 if index % 2 == 0 else 11, 8, 4)
    obj = join_parts(name, PARTS[initial:])
    del PARTS[initial:]
    return obj


def make_rig():
    bpy.ops.object.armature_add()
    rig = bpy.context.object
    rig.name = 'Rig'
    bpy.ops.object.mode_set(mode='EDIT')
    rig.data.edit_bones.remove(rig.data.edit_bones[0])
    definitions = [('Root', (0, 0, 0), (0, 0, 0.18), None),
                   ('Spine', (0, -0.25, 0), (0, 0.28, 0.2), 'Root'),
                   ('Head', (0, 0.34, 0.28), (0, 0.78, 0.48), 'Spine')]
    for sign, side in [(-1, 'L'), (1, 'R')]:
        definitions.extend([('Wing_' + side, (sign * 0.22, 0.08, 0.14), (sign * 0.76, 0.02, 0.12), 'Spine'),
                            ('Wrist_' + side, (sign * 0.76, 0.02, 0.12), (sign * 1.36, -0.18, 0.08), 'Wing_' + side),
                            ('Foot_' + side, (sign * 0.17, -0.02, -0.25), (sign * 0.17, 0.20, -0.4), 'Spine')])
    for x, side in [(-0.2, 'L'), (0, 'C'), (0.2, 'R')]:
        definitions.append(('Tail_' + side, (x * 0.3, -0.5, -0.08), (x, -1.15, -0.02), 'Spine'))
    for name, head, tail, parent in definitions:
        bone = rig.data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = rig.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.select_set(False)
    return rig


def animations():
    RIG.animation_data_create()
    durations = {'idle': 1.5, 'fly': 0.66, 'carry_fly': 0.82, 'turn_left': 0.66, 'turn_right': 0.66, 'gather': 0.42, 'throw': 0.48}
    for key, duration in durations.items():
        action = bpy.data.actions.new(key)
        RIG.animation_data.action = action
        for sample in range(17):
            t = sample / 16
            wave = math.sin(t * math.tau)
            gesture = math.sin(t * math.pi) ** 2
            wing = (0.18 if key == 'idle' else 0.48) * wave
            if key == 'carry_fly':
                wing *= 0.85
            if key in ('gather', 'throw'):
                wing = -0.18 * gesture if key == 'gather' else 0.42 * math.sin(t * math.tau)
            for pose in RIG.pose.bones:
                pose.rotation_mode = 'XYZ'
                pose.rotation_euler = (0, 0, 0)
                pose.location = (0, 0, 0)
                name = pose.name
                if name == 'Root':
                    pose.location.z = wave * (0.018 if key == 'idle' else 0.025)
                elif name == 'Spine':
                    pose.rotation_euler.x = (-0.09 if key != 'idle' else 0) + wave * 0.025
                    if key == 'gather':
                        pose.rotation_euler.x = -0.20 * gesture
                        pose.location.z = -0.08 * gesture
                    elif key == 'throw':
                        pose.rotation_euler.x = 0.22 * math.sin(t * math.tau)
                elif name == 'Head':
                    pose.rotation_euler.x = 0.035 * wave
                    if key == 'gather':
                        pose.rotation_euler.x = -0.44 * gesture
                    elif key == 'throw':
                        pose.rotation_euler.x = -0.30 * math.sin(t * math.tau)
                elif name.startswith('Wing_'):
                    # Mirrored bones already mirror their local X axes.
                    pose.rotation_euler.x = wing
                    if key.startswith('turn'):
                        pose.rotation_euler.x += 0.18 if (key == 'turn_left') == name.endswith('L') else -0.10
                elif name.startswith('Wrist_'):
                    pose.rotation_euler.x = math.sin(t * math.tau - 0.3) * (0.07 if key == 'idle' else 0.17)
                elif name.startswith('Tail_'):
                    pose.rotation_euler.x = wave * 0.06 + (gesture * 0.18 if key == 'gather' else 0)
                    pose.rotation_euler.z = (0.10 if key == 'turn_left' else -0.10) if key.startswith('turn') else 0
                elif name.startswith('Foot_'):
                    pose.rotation_euler.x = -0.35 * gesture if key == 'gather' else 0.10
                pose.keyframe_insert('rotation_euler', frame=1 + t * duration * 24)
                pose.keyframe_insert('location', frame=1 + t * duration * 24)
        track = RIG.animation_data.nla_tracks.new()
        track.name = key
        strip = track.strips.new(key, 1, action)
        strip.extrapolation = 'NOTHING'
        track.mute = True
    RIG.animation_data.action = None
    for track in RIG.animation_data.nla_tracks:
        track.mute = False
    return durations


def main():
    global RIG, MAT
    for path in (SOURCE, MODEL, TEXTURE):
        path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.scene.render.fps = 24
    MAT = atlas()
    RIG = make_rig()
    sculpt = body()
    topology = bmesh.new()
    topology.from_mesh(sculpt.data)
    topology.verts.ensure_lookup_table()
    assert all(edge.is_manifold for edge in topology.edges), 'Body must remain a closed surface'
    visited, pending = set(), [topology.verts[0]]
    while pending:
        vertex = pending.pop()
        if vertex in visited:
            continue
        visited.add(vertex)
        pending.extend(edge.other_vert(vertex) for edge in vertex.link_edges)
    assert len(visited) == len(topology.verts), 'Body, head and beak must remain connected'
    topology.free()
    feathers_and_details()
    skin = join_parts('JingweiSkin', PARTS[:])
    PARTS.clear()
    cargo('CargoLight', False)
    cargo('CargoFull', True)
    clips = animations()
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.objects.active = RIG
    RIG.select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    export(MODEL)
    report = {'generator': 'art_source/build_jingwei.py', 'blender': bpy.app.version_string,
              'source': SOURCE.relative_to(ROOT).as_posix(), 'model': MODEL.relative_to(ROOT).as_posix(),
              'texture': TEXTURE.relative_to(ROOT).as_posix(), 'texture_size': [1024, 1024],
              'bones': len(bpy.data.objects['Rig'].data.bones),
              'clips_source_seconds': clips, 'body_topology': 'single continuous watertight loft from rump to beak; blended Spine/Head weights',
              'body_topology_verified': {'connected_components': 1, 'closed_manifold': True},
              'license_source': 'Original project geometry, UV paint atlas and animation; no third-party art.'}
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('ART-02: exported production Jingwei, three cargo stages, seven clips, UV paint atlas.')


if __name__ == '__main__':
    main()
