"""Blender 4.5: blender --background --python art_source/build_pipeline_examples.py

Also runnable with Python 3.11 + the official bpy==4.5.3 wheel.
Original diagnostic primitives, not production art. No third-party art assets.
"""
from pathlib import Path
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_glb import export

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_source" / "pipeline_examples"
OUTPUT = ROOT / "assets" / "models" / "pipeline_examples"
SOURCE.mkdir(parents=True, exist_ok=True)
OUTPUT.mkdir(parents=True, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1
    scene.render.fps = 24
    scene.frame_start, scene.frame_end = 1, 25


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = 0.9
    return mat


def part(name, location, scale, mat, bone='Root'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.append(mat)
    if bone:
        obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    return obj


def rig_actor(kind):
    reset()
    blue = material('MAT_ExampleBody', (0.09, 0.24, 0.28) if kind == 'jingwei' else (0.40, 0.25, 0.12))
    cream = material('MAT_ExampleAccent', (0.85, 0.62, 0.30))
    bpy.ops.object.armature_add()
    rig = bpy.context.object
    rig.name = 'Rig'
    bpy.ops.object.mode_set(mode='EDIT')
    root = rig.data.edit_bones[0]
    root.name = 'Root'
    root.head, root.tail = (0, 0, 0), (0, 0, 0.3)
    for name, sign in [('Wing_L', -1), ('Wing_R', 1)]:
        bone = rig.data.edit_bones.new(name)
        bone.head, bone.tail = (sign * 0.2, 0, 0), (sign * 0.8, 0, 0)
        bone.parent = root
    bpy.ops.object.mode_set(mode='OBJECT')
    if kind == 'jingwei':
        pieces = [part('Body', (0, 0, 0), (0.32, 0.5, 0.32), blue),
                  part('Head', (0, 0.4, 0.32), (0.25, 0.3, 0.25), cream),
                  part('Beak', (0, 0.7, 0.28), (0.08, 0.24, 0.08), cream)]
        for name, sign in [('Wing_L', -1), ('Wing_R', 1)]:
            pieces.append(part('Panel_' + name, (sign * 0.55, -0.05, 0), (0.45, 0.24, 0.06), blue, name))
        cargo = part('CargoPreview', (0, -0.1, 0.42), (0.20, 0.18, 0.15), cream, None)
        cargo.parent = rig
        clips = ['idle', 'fly', 'carry_fly', 'gather', 'throw']
    else:
        pieces = [part('Body', (0, 0, 0.5), (0.5, 0.8, 0.45), blue),
                  part('Snout', (0, 0.9, 0.25), (0.2, 0.5, 0.2), cream),
                  part('Tail', (0, -1, 0.25), (0.2, 0.6, 0.18), cream)]
        clips = ['idle', 'dig', 'complete', 'finished']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = 'DiagnosticSkin'
    body.parent = rig
    body.modifiers.new('Skin', 'ARMATURE').object = rig
    rig.animation_data_create()
    for key in clips:
        action = bpy.data.actions.new(key)
        rig.animation_data.action = action
        for frame, wave in [(1, 0), (7, 1), (13, 0), (19, -1), (25, 0)]:
            for pose in rig.pose.bones:
                pose.rotation_mode = 'XYZ'
                pose.rotation_euler = (0, 0, 0)
                pose.location = (0, 0, 0)
                if kind == 'jingwei' and pose.name.startswith('Wing'):
                    pose.rotation_euler.y = wave * (0.5 if key in ('fly', 'carry_fly') else 0.12)
                if pose.name == 'Root':
                    pose.rotation_euler.x = wave * (0.22 if key in ('gather', 'throw', 'dig', 'complete') else 0.025)
                pose.keyframe_insert('rotation_euler', frame=frame)
                pose.keyframe_insert('location', frame=frame)
        track = rig.animation_data.nla_tracks.new()
        track.name = key
        track.strips.new(key, 1, action)
        track.mute = True
    rig.animation_data.action = None
    # Exporter reads each named NLA track separately, regardless of viewport mute.
    for track in rig.animation_data.nla_tracks:
        track.mute = False
    save_and_export(kind)


def save_and_export(name):
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (name + '.blend')))
    # Reopen the saved source: export verifies the exact .blend delivered to artists.
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / (name + '.blend')))
    export(OUTPUT / (name + '.glb'))


def mountain():
    reset()
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=1, radius2=0, depth=1, location=(0, 0, 0.5))
    obj = bpy.context.object
    obj.name = 'NormalizedMountain'
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # The shared mountain shader reads vertex color, with unit Y height after export.
    attr = obj.data.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
    for loop in obj.data.loops:
        height = obj.data.vertices[loop.vertex_index].co.z
        attr.data[loop.index].color = (0.25 + height * 0.3, 0.35 + height * 0.3, 0.25 + height * 0.2, 1)
    save_and_export('mountain')


if __name__ == '__main__':
    rig_actor('jingwei')
    rig_actor('pangolin')
    mountain()
    print('ART-01: saved and re-opened three Blender sources; exported three GLBs.')
