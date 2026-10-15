"""ART-03 original pangolin. Blender 4.5.3: --background --python THIS.
Rebuilds only this asset. Use export_glb.py after hand-editing the .blend source.
"""
from pathlib import Path
import json
import math
import sys
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Quaternion

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_glb import export
from mesh_tools import MeshBuilder

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/characters/pangolin.blend'
MODEL = ROOT / 'assets/models/characters/pangolin.glb'
TEXTURE = ROOT / 'assets/textures/characters/pangolin_atlas.png'
REPORT = ROOT / 'art_source/characters/pangolin-manifest.json'
PALETTE = ['78533d', 'b3915d', 'c6a46a', '977343', 'd4b581', '654936',
           'c9ad82', '242d2a', 'f4e5bf', 'd9c79e', '9e8059', 'a58a65',
           'b99b6b', '816345', 'dcc49a', 'c7b18c']
BODY = [(-0.86, 0.10, 0.39, 0.17), (-0.68, 0.35, 0.53, 0.38),
        (-0.43, 0.51, 0.60, 0.48), (-0.15, 0.55, 0.62, 0.50),
        (0.12, 0.51, 0.60, 0.46), (0.36, 0.42, 0.53, 0.38),
        (0.58, 0.30, 0.44, 0.28), (0.78, 0.22, 0.35, 0.19),
        (0.98, 0.15, 0.27, 0.13), (1.20, 0.085, 0.205, 0.075),
        (1.39, 0.03, 0.18, 0.034), (1.45, 0.007, 0.18, 0.01)]
CLIPS = {'idle': 1.6, 'locked': 2.0, 'walk': 0.85, 'dig': 0.90, 'complete': 0.70, 'finished': 2.0}


def material():
    size, tile = 1024, 256
    pixels = np.ones((size, size, 4), dtype=np.float32)
    v, u = np.mgrid[0:tile, 0:tile].astype(np.float32) / (tile - 1)
    for index, color in enumerate(PALETTE):
        rgb = np.array([int(color[i:i + 2], 16) / 255 for i in (0, 2, 4)])
        # Broad keratin growth bands, brighter worn edge, no tiled photo noise.
        arc = np.sqrt(((u - 0.5) * 1.3) ** 2 + ((v + 0.2) * 0.85) ** 2)
        shade = 0.94 + 0.075 * np.sin(v * math.pi) + 0.025 * np.cos(u * math.pi * 2)
        shade += 0.017 * np.cos(arc * 48) + 0.008 * np.sin(u * 89 + v * 13)
        shade += 0.045 * np.exp(-((v - 0.13) / 0.09) ** 2)
        row, col = divmod(index, 4)
        pixels[row * tile:(row + 1) * tile, col * tile:(col + 1) * tile, :3] = np.clip(rgb * shade[:, :, None], 0, 1)
    image = bpy.data.images.new('Pangolin_KeratinPaint', size, size, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw, image.file_format = str(TEXTURE), 'PNG'
    image.save()
    mat = bpy.data.materials.new('MAT_Pangolin_Keratin')
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = 0.88
    bsdf.inputs['Specular IOR Level'].default_value = 0.18
    node = mat.node_tree.nodes.new('ShaderNodeTexImage')
    node.image = image
    mat.node_tree.links.new(node.outputs['Color'], bsdf.inputs['Base Color'])
    return mat


def body_section(y):
    for a, b in zip(BODY, BODY[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return tuple(a[i] * (1 - t) + b[i] * t for i in (1, 2, 3))
    raise ValueError(y)


def body_weights(point, _t):
    head = max(0, min(1, (point.y - 0.46) / 0.30))
    return {'Spine': 1 - head, 'Head': head}


def tail_weights(t):
    if t < 0.33:
        return {'Tail_A': 1}
    if t < 0.60:
        b = (t - 0.33) / 0.27
        return {'Tail_A': 1 - b, 'Tail_B': b}
    b = min(1, (t - 0.60) / 0.28)
    return {'Tail_B': 1 - b, 'Tail_C': b}


def tail_section(t):
    return (0.17 * t * t, -0.72 - 1.56 * t, 0.36 * (1 - t) + 0.075 * t), 0.31 * (1 - t) ** 0.85 + 0.012, 0.21 * (1 - t) + 0.018


def shield(builder, name, center, across, along, normal, width, length, influences, swatch):
    # Broad flat scales with a bevel and shallow central ridge: never cone spikes.
    outline = [(-0.85, 0.55), (-0.84, -0.05), (-0.45, -0.55), (0, -0.79),
               (0.45, -0.55), (0.84, -0.05), (0.85, 0.55), (0, 0.80)]
    center, across, along, normal = map(Vector, (center, across, along, normal))
    vertices = [tuple(center + normal * 0.058)]
    uvs = [(0.5, 0.5)]
    for radius, height in [(0.60, 0.050), (1.0, 0.009), (0.96, -0.012)]:
        for x, y in outline:
            vertices.append(tuple(center + across * x * width * radius + along * y * length * radius + normal * height))
            uvs.append((0.5 + x * 0.48 * radius, 0.5 + y * 0.48 * radius))
    faces, colors = [], []
    for i in range(8):
        nxt = (i + 1) % 8
        faces.append((0, 1 + i, 1 + nxt))
        colors.append(swatch)
        faces.append((1 + i, 9 + i, 9 + nxt, 1 + nxt))
        colors.append(swatch)
        faces.append((9 + i, 17 + i, 17 + nxt, 9 + nxt))
        colors.append(3 if swatch != 3 else 10)
    faces.append(tuple(reversed([17 + i for i in range(8)])))
    colors.append(0)
    return builder.mesh(name, vertices, faces, [influences] * len(vertices), colors, uvs, smooth=False)


def make_body(builder):
    sections = [((0, y, z), (rx, 0, 0), (0, 0, rz)) for y, rx, z, rz in BODY]
    body = builder.rings('ContinuousBackHeadSnout', sections, 20, body_weights,
                         lambda p, _t: 6 if p.y > 0.60 or p.z < 0.36 else 0, True)
    topology = bmesh.new()
    topology.from_mesh(body.data)
    topology.verts.ensure_lookup_table()
    assert all(edge.is_manifold for edge in topology.edges)
    visited, pending = set(), [topology.verts[0]]
    while pending:
        vertex = pending.pop()
        if vertex in visited:
            continue
        visited.add(vertex)
        pending.extend(edge.other_vert(vertex) for edge in vertex.link_edges)
    assert len(visited) == len(topology.verts)
    topology.free()
    for row in range(8):
        y = -0.67 + row * 0.16
        rx, z, rz = body_section(y)
        for col in range(7):
            angle = (col - 3) * 0.34 + (0.08 if row % 2 else -0.02)
            point = Vector((rx * math.sin(angle), y, z + rz * math.cos(angle)))
            normal = Vector((math.sin(angle) / rx, 0, math.cos(angle) / rz)).normalized()
            across = Vector((normal.z, 0, -normal.x))
            along = normal.cross(across).normalized()
            swatch = [1, 2, 12, 1][(row // 2 + abs(col - 3)) % 4]
            shield(builder, 'BackScale_%02d_%d' % (row, col), point + normal * 0.005,
                   across, along, normal, 0.15 if abs(col - 3) < 3 else 0.13, 0.23,
                   body_weights(point, 0), swatch)
    for row in range(2):
        y = 0.66 + row * 0.14
        rx, z, rz = body_section(y)
        for col in range(3):
            angle = (col - 1) * 0.55
            normal = Vector((math.sin(angle), 0, math.cos(angle)))
            across = Vector((normal.z, 0, -normal.x))
            shield(builder, 'HeadScale_%d_%d' % (row, col), (rx * math.sin(angle), y, z + rz * math.cos(angle)),
                   across, normal.cross(across), normal, 0.10, 0.15, {'Head': 1}, 1 if col == 1 else 12)
    sections = []
    for row in range(15):
        point, rx, rz = tail_section(row / 14)
        sections.append((point, (rx, 0, 0), (0, 0, rz)))
    builder.rings('LongTaperedTail', sections, 12, lambda _p, t: tail_weights(t), lambda _p, _t: 0)
    for row in range(8):
        t = 0.07 + row * 0.115
        point, rx, rz = tail_section(t)
        for col in range(3):
            angle = (col - 1) * 0.80
            normal = Vector((math.sin(angle), 0, math.cos(angle)))
            across = Vector((normal.z, 0, -normal.x))
            center = Vector(point) + Vector((rx * math.sin(angle), 0, rz * math.cos(angle)))
            shield(builder, 'TailScale_%d_%d' % (row, col), center, across, normal.cross(across), normal,
                   max(0.045, rx * 0.60), 0.18 - t * 0.055, tail_weights(t), 2 if col == 1 else 1)


def limbs_and_face(builder):
    for sign, side in [(-1, 'L'), (1, 'R')]:
        points = [(sign * 0.39, 0.35, 0.63), (sign * 0.47, 0.57, 0.44),
                  (sign * 0.50, 0.78, 0.24), (sign * 0.51, 1.03, 0.12), (sign * 0.51, 1.20, 0.095)]
        sections = [(point, (r, 0, 0), (0, 0, r * 0.65)) for point, r in zip(points, [0.15, 0.15, 0.13, 0.16, 0.11])]
        def weights(_p, t, side=side):
            if t < 0.3:
                return {'ForeUpper_' + side: 1}
            if t < 0.7:
                amount = (t - 0.3) / 0.4
                return {'ForeUpper_' + side: 1 - amount, 'ForeLower_' + side: amount}
            amount = min(1, (t - 0.7) / 0.2)
            return {'ForeLower_' + side: 1 - amount, 'FrontPaw_' + side: amount}
        builder.rings('Forelimb_' + side, sections, 10, weights, lambda _p, _t: 0)
        builder.ellipsoid('RearHaunch_' + side, (sign * 0.41, -0.50, 0.32), (0.22, 0.28, 0.28), 'BackUpper_' + side, 10)
        builder.ellipsoid('RearPaw_' + side, (sign * 0.43, -0.28, 0.09), (0.16, 0.22, 0.075), 'BackPaw_' + side, 0)
        for toe in range(3):
            x = sign * 0.51 + (toe - 1) * 0.07
            builder.tube('DiggingClaw_%s_%d' % (side, toe), [(x, 1.13, 0.105), (x, 1.29, 0.11), (x, 1.42 - abs(toe - 1) * 0.05, 0.035)], 0.040, 'FrontPaw_' + side, 9)
            x = sign * 0.43 + (toe - 1) * 0.065
            builder.tube('RearClaw_%s_%d' % (side, toe), [(x, -0.14, 0.09), (x, -0.03, 0.075), (x, 0.04, 0.035)], 0.026, 'BackPaw_' + side, 9)
        builder.ellipsoid('EyeSocket_' + side, (sign * 0.205, 0.82, 0.39), (0.020, 0.061, 0.052), 'Head', 5)
        builder.ellipsoid('Eye_' + side, (sign * 0.222, 0.84, 0.405), (0.018, 0.038, 0.039), 'Eyes', 7)
        builder.ellipsoid('EyeGlint_' + side, (sign * 0.237, 0.85, 0.42), (0.006, 0.010, 0.013), 'Eyes', 8, 8, 4)
    builder.ellipsoid('Nose', (0, 1.43, 0.185), (0.033, 0.034, 0.026), 'Head', 5)
    builder.ellipsoid('LowerJaw', (0, 1.08, 0.175), (0.073, 0.28, 0.036), 'Jaw', 6)


def rig():
    bpy.ops.object.armature_add()
    obj = bpy.context.object
    obj.name = 'Rig'
    bpy.ops.object.mode_set(mode='EDIT')
    obj.data.edit_bones.remove(obj.data.edit_bones[0])
    definitions = [('Root', (0, 0, 0), (0, 0, 0.15), None),
                   ('Spine', (0, -0.45, 0.55), (0, 0.45, 0.55), 'Root'),
                   ('Head', (0, 0.50, 0.43), (0, 1.17, 0.23), 'Spine'),
                   ('Jaw', (0, 0.78, 0.21), (0, 1.27, 0.17), 'Head'),
                   ('Eyes', (0, 0.84, 0.405), (0, 0.92, 0.405), 'Head'),
                   ('Tail_A', (0, -0.68, 0.38), (0, -1.21, 0.26), 'Spine'),
                   ('Tail_B', (0, -1.21, 0.26), (0.08, -1.75, 0.16), 'Tail_A'),
                   ('Tail_C', (0.08, -1.75, 0.16), (0.17, -2.28, 0.075), 'Tail_B')]
    for sign, side in [(-1, 'L'), (1, 'R')]:
        definitions.extend([('ForeUpper_' + side, (sign * 0.39, 0.35, 0.63), (sign * 0.47, 0.65, 0.37), 'Spine'),
                            ('ForeLower_' + side, (sign * 0.47, 0.65, 0.37), (sign * 0.51, 1.0, 0.12), 'ForeUpper_' + side),
                            ('FrontPaw_' + side, (sign * 0.51, 1.0, 0.12), (sign * 0.51, 1.3, 0.08), 'ForeLower_' + side),
                            ('BackUpper_' + side, (sign * 0.38, -0.50, 0.42), (sign * 0.43, -0.30, 0.14), 'Spine'),
                            ('BackPaw_' + side, (sign * 0.43, -0.30, 0.14), (sign * 0.43, -0.05, 0.07), 'BackUpper_' + side)])
    for name, head, tail, parent in definitions:
        bone = obj.data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = obj.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)
    return obj


def rotate_world(pose, pitch=0, yaw=0, roll=0):
    # Express common world axes in each bone's rest basis; mirrored limbs stay correct.
    inverse = pose.bone.matrix_local.to_3x3().inverted()
    pose.rotation_quaternion = (Quaternion(inverse @ Vector((0, 0, 1)), yaw) @
                                Quaternion(inverse @ Vector((0, 1, 0)), roll) @
                                Quaternion(inverse @ Vector((1, 0, 0)), pitch))


def animate(obj):
    obj.animation_data_create()
    for key, duration in CLIPS.items():
        action = bpy.data.actions.new(key)
        obj.animation_data.action = action
        for sample in range(25):
            t = sample / 24
            wave, pulse = math.sin(t * math.tau), math.sin(t * math.pi) ** 2
            for pose in obj.pose.bones:
                name = pose.name
                pose.rotation_mode = 'QUATERNION'
                pose.rotation_quaternion = Quaternion()
                pose.location = (0, 0, 0)
                pose.scale = (1, 1, 1)
                if name == 'Spine':
                    rotate_world(pose, pitch=0.025 * wave if key == 'dig' else 0.009 * wave)
                    pose.scale.x = 1 + 0.008 * wave
                    if key == 'complete':
                        rotate_world(pose, pitch=-0.07 * pulse)
                elif name == 'Head':
                    rotate_world(pose, pitch=0.06 * wave if key == 'dig' else 0.015 * wave)
                    if key == 'locked':
                        rotate_world(pose, pitch=-0.08, yaw=0.18 * wave)
                    elif key == 'finished':
                        rotate_world(pose, pitch=-0.10)
                    elif key == 'complete':
                        rotate_world(pose, pitch=0.15 * pulse, yaw=0.11 * wave * pulse)
                elif name == 'Eyes':
                    pose.scale.z = 0.18 if key == 'finished' else (0.12 if t > 0.45 and t < 0.55 and key in ('idle', 'locked') else 1)
                elif name.startswith('Tail_'):
                    segment = {'Tail_A': 0, 'Tail_B': 1, 'Tail_C': 2}[name]
                    yaw = 0.04 * math.sin(t * math.tau - segment * 0.45)
                    if key == 'dig':
                        yaw *= -0.7
                    elif key == 'finished':
                        yaw = [0.28, 0.22, 0.15][segment] + 0.008 * wave
                    elif key == 'complete':
                        yaw = 0.08 * math.sin(t * math.tau * 2 - segment * 0.3) * pulse
                    rotate_world(pose, yaw=yaw)
                elif name.startswith(('ForeUpper_', 'ForeLower_', 'FrontPaw_', 'BackUpper_', 'BackPaw_')):
                    side = 1 if name.endswith('L') else -1
                    limb_wave = side * wave
                    if key == 'dig':
                        if name.startswith('ForeUpper_'):
                            rotate_world(pose, pitch=0.24 * limb_wave)
                        elif name.startswith('ForeLower_'):
                            rotate_world(pose, pitch=-0.22 * side * math.sin(t * math.tau + 0.65))
                            pose.location = pose.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, 0.045))
                        elif name.startswith('FrontPaw_'):
                            # Counter-rotate the wrist so the claw rake stays near ground.
                            rotate_world(pose, pitch=-0.06 * limb_wave)
                    elif key == 'walk':
                        angle = 0.17 * limb_wave * (-1 if name.startswith('Back') else 1)
                        rotate_world(pose, pitch=angle)
                    elif key == 'complete' and name.startswith('FrontPaw_'):
                        rotate_world(pose, pitch=0.22 * wave * pulse)
                    elif key == 'finished':
                        if name.startswith('ForeUpper_'):
                            rotate_world(pose, pitch=0.18)
                        elif name.startswith('ForeLower_'):
                            rotate_world(pose, pitch=-0.28)
                pose.keyframe_insert('rotation_quaternion', frame=1 + t * duration * 24)
                pose.keyframe_insert('location', frame=1 + t * duration * 24)
                pose.keyframe_insert('scale', frame=1 + t * duration * 24)
        track = obj.animation_data.nla_tracks.new()
        track.name = key
        track.strips.new(key, 1, action).extrapolation = 'NOTHING'
        track.mute = True
    obj.animation_data.action = None
    for track in obj.animation_data.nla_tracks:
        track.mute = False


def main():
    for path in (SOURCE, MODEL, TEXTURE):
        path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.scene.render.fps = 24
    builder = MeshBuilder(material())
    skeleton = rig()
    make_body(builder)
    limbs_and_face(builder)
    builder.join('PangolinSkin', skeleton)
    animate(skeleton)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.objects.active = skeleton
    skeleton.select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    bpy.ops.file.make_paths_relative()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    export(MODEL)
    report = {'generator': 'art_source/build_pangolin.py', 'blender': bpy.app.version_string,
              'source': SOURCE.relative_to(ROOT).as_posix(), 'model': MODEL.relative_to(ROOT).as_posix(),
              'texture': TEXTURE.relative_to(ROOT).as_posix(), 'texture_size': [1024, 1024],
              'bones': len(bpy.data.objects['Rig'].data.bones), 'clips_source_seconds': CLIPS,
              'body_topology_verified': {'connected_components': 1, 'closed_manifold': True},
              'scales': {'back': 56, 'head': 6, 'tail': 24, 'shape': 'overlapping bevelled shields with shallow ridge'},
              'license_source': 'Original project mesh, UV paint atlas and animation; no third-party art.'}
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('ART-03: exported pangolin, 86 overlapping scales, 18 bones and six clips.')


if __name__ == '__main__':
    main()
