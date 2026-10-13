extends RefCounted

static func material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result

static func mesh_part(parent: Node3D, mesh: Mesh, mat: Material, point: Vector3, sizing: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = point
	node.scale = sizing
	parent.add_child(node)
	return node

static func sphere(parent: Node3D, point: Vector3, sizing: Vector3, color: Color, segments: int = 12) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	shape.radial_segments = segments
	shape.rings = 6
	return mesh_part(parent, shape, material(color), point, sizing)

static func box(parent: Node3D, point: Vector3, sizing: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = sizing
	return mesh_part(parent, shape, material(color), point)

static func cone(parent: Node3D, point: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = 0.0
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 7
	return mesh_part(parent, shape, material(color), point)

static func rock_mesh(variant: int = 0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 190 + variant * 71
	var count := 7
	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for index in range(count):
		var angle := float(index) / count * TAU
		var r := rng.randf_range(0.43, 0.62)
		lower.append(Vector3(cos(angle) * r, -0.24, sin(angle) * r))
		upper.append(Vector3(cos(angle + 0.16) * r * 0.78, rng.randf_range(0.16, 0.4), sin(angle + 0.16) * r * 0.78))
	for index in range(count):
		var next := (index + 1) % count
		var triangles: Array[Vector3] = [lower[index], upper[index], lower[next], lower[next], upper[index], upper[next], upper[index], Vector3(0.03, 0.51, -0.02), upper[next], lower[next], Vector3(0, -0.24, 0), lower[index]]
		for triangle in range(0, triangles.size(), 3):
			# Godot uses clockwise front faces.
			tool.add_vertex(triangles[triangle])
			tool.add_vertex(triangles[triangle + 2])
			tool.add_vertex(triangles[triangle + 1])
	tool.generate_normals()
	return tool.commit()

static func bird() -> Node3D:
	var root := Node3D.new()
	var blue := Color("305f70")
	var cream := Color("fff0ca")
	var coral := Color("da684d")
	sphere(root, Vector3(0, 0, 0), Vector3(0.68, 0.72, 1.05), blue)
	sphere(root, Vector3(0, -0.06, -0.27), Vector3(0.53, 0.53, 0.61), cream)
	sphere(root, Vector3(0, 0.45, -0.32), Vector3(0.62, 0.58, 0.62), coral)
	sphere(root, Vector3(0, 0.34, -0.53), Vector3(0.41, 0.32, 0.24), cream)
	var beak := cone(root, Vector3(0, 0.36, -0.81), 0.13, 0.4, Color("e9b956"))
	beak.rotation.x = -PI / 2.0
	for side in [-1.0, 1.0]:
		sphere(root, Vector3(side * 0.25, 0.48, -0.5), Vector3(0.075, 0.1, 0.08), Color("162c36"))
		var wing := Node3D.new()
		wing.name = "WingLeft" if side < 0 else "WingRight"
		wing.position = Vector3(side * 0.25, 0.12, 0.03)
		root.add_child(wing)
		for feather in range(4):
			var part := sphere(wing, Vector3(side * (0.17 + feather * 0.12), 0, float(feather) * 0.11), Vector3(0.23, 0.1, 0.73 - feather * 0.07), cream if feather == 3 else blue, 8)
			part.rotation.y = side * 0.28
		var foot := box(root, Vector3(side * 0.17, -0.4, 0.03), Vector3(0.07, 0.18, 0.09), Color("cc8f4b"))
		foot.rotation.x = 0.3
	for index in range(3):
		var tail := sphere(root, Vector3((index - 1) * 0.16, 0.09, 0.67), Vector3(0.17, 0.12, 0.85), coral if index == 1 else blue, 8)
		tail.rotation.x = -0.26
	for index in range(3):
		var crest := cone(root, Vector3((index - 1) * 0.11, 0.83, -0.19), 0.065, 0.28 + index * 0.06, coral)
		crest.rotation.x = 0.4
	var load := Node3D.new()
	load.name = "Load"
	load.position = Vector3(0, 0.2, 0.12)
	root.add_child(load)
	for index in range(3):
		mesh_part(load, rock_mesh(index), material(Color("bab7a7")), Vector3((index - 1) * 0.15, 0.2, 0), Vector3.ONE * 0.34)
	load.visible = false
	return root

static func pangolin() -> Node3D:
	var root := Node3D.new()
	var brown := Color("9c7951")
	sphere(root, Vector3(0, 0.48, 0), Vector3(1.1, 0.94, 1.8), brown)
	sphere(root, Vector3(0, 0.32, -0.97), Vector3(0.52, 0.48, 0.9), Color("c4a073"))
	sphere(root, Vector3(0, 0.22, -1.4), Vector3(0.24, 0.22, 0.32), Color("78533d"))
	for side in [-1.0, 1.0]:
		sphere(root, Vector3(side * 0.23, 0.44, -1.02), Vector3.ONE * 0.09, Color("242d2a"))
		for z in [-0.53, 0.53]:
			sphere(root, Vector3(side * 0.47, 0.15, z), Vector3(0.27, 0.3, 0.43), Color("78533d"))
	for row in range(5):
		for col in range(5):
			var angle := (float(col) - 2.0) * 0.48
			var scale_piece := cone(root, Vector3(sin(angle) * 0.49, 0.5 + cos(angle) * 0.43, -0.65 + row * 0.32), 0.21, 0.15, Color("c6a46a") if (row + col) % 2 == 0 else Color("b3915d"))
			scale_piece.rotation.x = 0.5
	for index in range(5):
		sphere(root, Vector3(0, 0.35 - index * 0.04, 0.92 + index * 0.25), Vector3(0.65 - index * 0.1, 0.34 - index * 0.04, 0.56), brown, 8)
	return root

static func tree(parent: Node3D, point: Vector3, size: float) -> void:
	var root := Node3D.new()
	root.position = point
	root.scale = Vector3.ONE * size
	parent.add_child(root)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.09
	trunk.bottom_radius = 0.16
	trunk.height = 1.7
	trunk.radial_segments = 6
	mesh_part(root, trunk, material(Color("7e6249")), Vector3(0, 0.85, 0))
	cone(root, Vector3(0, 1.6, 0), 0.95, 1.5, Color("427961"))
	cone(root, Vector3(0, 2.25, 0), 0.72, 1.35, Color("598b69"))
	cone(root, Vector3(0, 2.8, 0), 0.43, 1.0, Color("78a077"))
