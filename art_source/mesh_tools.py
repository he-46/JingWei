"""Small authored mesh/UV helpers for Blender source generation (not game runtime)."""
import math
import bpy
from mathutils import Vector


class MeshBuilder:
    def __init__(self, material):
        self.material = material
        self.parts = []

    def mesh(self, name, vertices, faces, weights, swatches, uvs, smooth=True):
        data = bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        data.materials.append(self.material)
        layer = data.uv_layers.new(name='PaintUV')
        for polygon in data.polygons:
            polygon.use_smooth = smooth
            row, col = divmod(swatches[polygon.index], 4)
            for loop in polygon.loop_indices:
                vertex = data.loops[loop].vertex_index
                u, v = uvs[vertex]
                layer.data[loop].uv = ((col + 0.035 + u * 0.93) / 4, (row + 0.035 + v * 0.93) / 4)
        for index, influences in enumerate(weights):
            for name, value in influences.items():
                if value <= 0:
                    continue
                group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                group.add([index], value, 'REPLACE')
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode='OBJECT')
        obj.select_set(False)
        self.parts.append(obj)
        return obj

    def rings(self, name, sections, sectors, weights, color, subdivide=False):
        vertices, influences, faces, swatches, uvs = [], [], [], [], []
        for index, (center, across, normal) in enumerate(sections):
            t = index / (len(sections) - 1)
            for sector in range(sectors):
                angle = math.tau * sector / sectors
                point = Vector(center) + Vector(across) * math.sin(angle) + Vector(normal) * math.cos(angle)
                vertices.append(tuple(point))
                influences.append(weights(point, t))
                uvs.append((sector / sectors, t))
        for ring in range(len(sections) - 1):
            for sector in range(sectors):
                nxt = (sector + 1) % sectors
                face = (ring * sectors + sector, ring * sectors + nxt, (ring + 1) * sectors + nxt, (ring + 1) * sectors + sector)
                faces.append(face)
                point = sum((Vector(vertices[v]) for v in face), Vector()) / 4
                swatches.append(color(point, (ring + 0.5) / (len(sections) - 1)))
        faces.extend([tuple(reversed(range(sectors))), tuple((len(sections) - 1) * sectors + i for i in range(sectors))])
        swatches.extend([color(Vector(sections[0][0]), 0), color(Vector(sections[-1][0]), 1)])
        obj = self.mesh(name, vertices, faces, influences, swatches, uvs)
        if subdivide:
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new('SculptSurface', 'SUBSURF')
            modifier.levels = 1
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        return obj

    def ellipsoid(self, name, center, size, bone, swatch, sectors=10, rows=5):
        sections = []
        for row in range(rows + 1):
            angle = math.pi * row / rows
            radius = max(0.01, math.sin(angle))
            sections.append(((center[0], center[1] + math.cos(angle) * size[1], center[2]),
                             (size[0] * radius, 0, 0), (0, 0, size[2] * radius)))
        return self.rings(name, sections, sectors, lambda _p, _t: {bone: 1}, lambda _p, _t: swatch)

    def tube(self, name, points, radius, bone, swatch, sectors=6):
        sections = []
        for index, point in enumerate(points):
            tangent = (Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(0, index - 1)])).normalized()
            across = tangent.cross(Vector((0, 0, 1)))
            if across.length < 0.01:
                across = tangent.cross(Vector((0, 1, 0)))
            across.normalize()
            normal = tangent.cross(across).normalized()
            r = radius * (1 - index / max(1, len(points) - 1) * 0.80)
            sections.append((point, across * r, normal * r))
        return self.rings(name, sections, sectors, lambda _p, _t: {bone: 1}, lambda _p, _t: swatch)

    def join(self, name, rig):
        bpy.ops.object.select_all(action='DESELECT')
        for obj in self.parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = self.parts[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = name
        obj.parent = rig
        obj.modifiers.new('Skin', 'ARMATURE').object = rig
        obj.select_set(False)
        return obj
