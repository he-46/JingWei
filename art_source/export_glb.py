"""Export the opened .blend; run with Blender --background INPUT --python THIS -- OUTPUT."""
from pathlib import Path
import sys
import bpy


def export(destination):
    destination = Path(destination).resolve()
    if destination.suffix.lower() != '.glb':
        raise ValueError('Expected a .glb destination')
    if abs(bpy.context.scene.unit_settings.scale_length - 1.0) > 1e-6:
        raise ValueError('Use metric scale 1.0; apply mesh/armature transforms before export')
    for obj in bpy.context.scene.objects:
        if obj.type in {'MESH', 'ARMATURE'} and any(abs(v - 1) > 1e-6 for v in obj.scale):
            raise ValueError('Apply object scale before export: ' + obj.name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.frame_set(1)
    bpy.ops.export_scene.gltf(filepath=str(destination), export_format='GLB',
                              export_yup=True, export_animations=True,
                              export_animation_mode='NLA_TRACKS', export_skins=True)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if len(args) != 1:
        raise SystemExit('Usage: blender --background INPUT.blend --python art_source/export_glb.py -- OUTPUT.glb')
    export(args[0])
