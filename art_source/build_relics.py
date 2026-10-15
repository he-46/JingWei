"""ART-06 original relic meshes, painted palette and icons rendered from the meshes.
Rebuild: Blender 4.5 --background --python art_source/build_relics.py
"""
from pathlib import Path
import sys, math, json
import bpy
import numpy as np
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from mesh_tools import MeshBuilder
from export_glb import export

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/relics'
MODELS = ROOT / 'assets/models/relics'
ICONS = ROOT / 'assets/icons/relics'
TEXTURE = ROOT / 'assets/textures/relics/relic_palette.png'
COLORS = ['946139', 'c69350', 'e1ba78', '634632', '39716d', '75b7ac', 'c3dfcd', 'e6ecd7',
          '365b50', '618f6f', '9fbe86', 'b55d42', 'd3a652', 'edd8a0', '4a5144', 'e9e2c7']

def material():
    pixels = np.ones((256, 256, 4), np.float32)
    y, x = np.mgrid[0:64, 0:64] / 63
    for i, color in enumerate(COLORS):
        rgb = np.array([int(color[k:k+2], 16) / 255 for k in (0, 2, 4)])
        shade = .94 + .08 * np.sin(y * math.pi) + .025 * np.cos(x * 18 + y * 4)
        row, col = divmod(i, 4)
        pixels[row*64:(row+1)*64, col*64:(col+1)*64, :3] = rgb * shade[:, :, None]
    image = bpy.data.images.new('Relic_PaintedPalette', 256, 256, alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw, image.file_format = str(TEXTURE), 'PNG'
    image.save()
    mat = bpy.data.materials.new('MAT_Relic_Palette')
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .72
    tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = image
    mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
    return mat

def loop(b, name, radius, z, swatch, tube=.027, sectors=16):
    # Closed horizontal woven band, with constant cross section.
    sections = []
    for i in range(sectors + 1):
        a = math.tau * i / sectors
        radial = Vector((math.cos(a), math.sin(a), 0))
        sections.append((radial * radius + Vector((0, 0, z)), radial * tube, (0, 0, tube)))
    b.rings(name, sections, 4, lambda p,t: {}, lambda p,t: swatch)

def basket(b):
    # Solid shallow bottom plus open weave; no opaque cap across the mouth.
    b.rings('BasketBase', [((0,0,.04),(.30,0,0),(0,.30,0)), ((0,0,.11),(.32,0,0),(0,.32,0))], 12, lambda p,t:{}, lambda p,t:0)
    for row in range(4):
        loop(b, 'WovenBand', .32 + row * .025, .14 + row * .12, 1 if row%2 else 0, sectors=12)
    for i in range(10):
        a = math.tau * i / 10
        b.tube('Upright', [(math.cos(a)*r,math.sin(a)*r,z) for r,z in [(.30,.08),(.35,.32),(.40,.56)]], .025, '', 2, 4)
    for side in [-1, 1]:
        b.tube('Handle', [(side*.37,0,.48),(side*.36,0,.78),(side*.21,0,.96),(0,0,1.01)], .041, '', 2, 5)
    for i, (x,y,z) in enumerate([(-.16,-.07,.50),(.13,-.10,.52),(0,.13,.53)]):
        b.ellipsoid('CarriedStone', (x,y,z), (.17,.14,.14), '', 15 if i%2 else 14, 7, 3)

def feather(b):
    b.tube('GoldenQuill', [(-.17,0,.02),(-.10,0,.32),(.04,0,.75),(.17,0,1.35)], .024, '', 12, 6)
    # Individually tapered barbs form the asymmetric teal-and-ivory vane.
    for i in range(8):
        z = .25 + i * .115
        center = -.13 + .23 * z / 1.35
        width = .32 * math.sin((i + 1) / 9 * math.pi) ** .65
        for side in [-1,1]:
            x = center + side * width * (1 if side<0 else .78)
            vertices = [(center,-.025,z-.045),(x,0,z+.12),(center+.045,-.02,z+.18),
                        (center,.025,z-.045),(x,.035,z+.12),(center+.045,.025,z+.18)]
            faces = [(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)]
            b.mesh('WindBarb', vertices, faces, [{}]*6, [4 + (i%3) if side<0 else 6]*5, [(0,0),(1,.5),(.3,1)]*2, False)

def box(b, name, lo, hi, color):
    x,y,z=lo; X,Y,Z=hi
    v=[(x,y,z),(X,y,z),(X,Y,z),(x,Y,z),(x,y,Z),(X,y,Z),(X,Y,Z),(x,Y,Z)]
    f=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    b.mesh(name,v,f,[{}]*8,[color]*6,[(0,0),(1,0),(1,1),(0,1)]*2,False)

def seal(b):
    box(b,'VermilionFoot',(-.37,-.32,.02),(.37,.32,.11),11)
    box(b,'JadeSeal',(-.35,-.30,.11),(.35,.30,.42),8)
    box(b,'GoldenRim',(-.37,-.32,.40),(.37,.32,.46),12)
    # Three peaked jade mountain crest, visually different from basket handle.
    for x,w,h in [(-.20,.13,.29),(0,.19,.48),(.23,.12,.25)]:
        b.rings('MountainCrest', [((x,0,.45),(w,0,0),(0,.17,0)), ((x-.015,0,.45+h),(.012,0,0),(0,.012,0))],4,lambda p,t:{},lambda p,t:9 if t<.5 else 10)
    for x in [-.12,.12]:
        box(b,'FrontInscription',(x-.025,-.315,.19),(x+.025,-.30,.35),13)
    box(b,'CrossInscription',(-.19,-.318,.25),(.19,-.30,.285),13)

def icon(name):
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=24
    scene.render.resolution_x=256; scene.render.resolution_y=256; scene.render.resolution_percentage=100
    scene.render.film_transparent=True
    scene.world=bpy.data.worlds.new('IconWorld')
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.72,.78,.72,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
    bpy.ops.object.camera_add(location=(2.3,-4.2,2.5))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,0,.62))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO'; camera.data.ortho_scale=1.65
    scene.camera=camera
    bpy.ops.object.light_add(type='AREA',location=(-3,-4,6))
    light=bpy.context.object; light.data.energy=450; light.data.shape='DISK'; light.data.size=4
    scene.view_settings.view_transform='Standard'
    scene.render.image_settings.file_format='PNG'; scene.render.image_settings.color_mode='RGBA'
    scene.render.filepath=str(ICONS/(name+'.png'))
    bpy.ops.render.render(write_still=True)

def main():
    for p in [SOURCE,MODELS,ICONS,TEXTURE.parent]: p.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system='METRIC'
    mat=material()
    report={'generator':'art_source/build_relics.py','license':'Original project art; no third-party assets.',
            'palette':TEXTURE.relative_to(ROOT).as_posix(),'icons':'256x256 RGBA, rendered from each exported source mesh','assets':{}}
    for name,build in [('basket',basket),('feather',feather),('seal',seal)]:
        for obj in list(bpy.data.objects): bpy.data.objects.remove(obj,do_unlink=True)
        b=MeshBuilder(mat); build(b)
        bpy.ops.object.select_all(action='DESELECT')
        for obj in b.parts: obj.select_set(True)
        bpy.context.view_layer.objects.active=b.parts[0]
        bpy.ops.object.join()
        obj=bpy.context.object; obj.name=name
        tri=sum(len(poly.vertices)-2 for poly in obj.data.polygons)
        source=SOURCE/(name+'.blend')
        bpy.ops.wm.save_as_mainfile(filepath=str(source)); bpy.ops.file.make_paths_relative(); bpy.ops.wm.save_as_mainfile(filepath=str(source))
        bpy.ops.wm.open_mainfile(filepath=str(source))
        mat=bpy.context.object.data.materials[0]
        export(MODELS/(name+'.glb'))
        icon(name)
        report['assets'][name]={'triangles':tri,'materials':1,'model':'assets/models/relics/'+name+'.glb','source':'art_source/relics/'+name+'.blend','icon':'assets/icons/relics/'+name+'.png'}
    (SOURCE/'relic-manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('ART-06',json.dumps(report))

if __name__=='__main__': main()
