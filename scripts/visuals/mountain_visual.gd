extends RefCounted
## A disposable value snapshot: no reference to mutable resource ledgers.
var radius: float
var height: float
var remaining: float
var stock: int
var stock_fraction: float
var transform: Transform3D
var collision_radius: float
var collision_height: float
var settled: bool
var progress: float

static func from_state(state: JWState, index: int):
	var result = new()
	var mountain: Dictionary = state.mountains[index]
	result.radius = state.mountain_radius(index)
	result.height = state.mountain_height(index)
	result.remaining = clampf(1.0 - float(mountain["work"]) / float(mountain["yield"]), 0, 1)
	result.progress = 1.0 - result.remaining
	result.settled = bool(mountain["settled"])
	result.stock = int(mountain["stock"])
	result.stock_fraction = clampf(float(result.stock) / float(mountain["yield"]), 0, 1)
	var point := state.mountain_position(index)
	result.transform = Transform3D(Basis.from_euler(Vector3(0, float(mountain["yaw"]), 0)).scaled(Vector3(result.radius, result.height, result.radius)), Vector3(point.x, state.LAND_HEIGHT, point.y))
	result.collision_radius = result.radius * state.MOUNTAIN_COLLISION_RATIO
	result.collision_height = result.height * result.remaining
	return result

func stage_name() -> String:
	if settled:
		return "碎石场" if stock > 0 else "空山址"
	if progress <= 0:
		return "完整山体"
	if progress < 0.5:
		return "岩层暴露"
	return "分层开采" if progress < 0.75 else "山脚基底"

static func collision_envelopes(mesh: Mesh, slices: int = 8) -> PackedFloat32Array:
	# Each slab encloses all triangles crossing its bottom, plus higher vertices.
	# This also works for twin peaks and saddles that are not nested ring contours.
	var radii := PackedFloat32Array()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	else:
		for i in range(vertices.size()):
			indices.append(i)
	for slab in range(slices):
		var bottom := float(slab) / slices
		var radius := 0.0
		for point in vertices:
			if point.y >= bottom - .00001:
				radius = maxf(radius, Vector2(point.x, point.z).length())
		for face in range(0, indices.size(), 3):
			for edge in range(3):
				var a := vertices[indices[face + edge]]
				var b := vertices[indices[face + (edge + 1) % 3]]
				if (a.y < bottom and b.y > bottom) or (b.y < bottom and a.y > bottom):
					var point := a.lerp(b, (bottom - a.y) / (b.y - a.y))
					radius = maxf(radius, Vector2(point.x, point.z).length())
		radii.append(minf(JWState.MOUNTAIN_COLLISION_RATIO, radius + 0.02))
	return radii

static func pile_transform(visual, part: int, count: int = 32) -> Transform3D:
	var angle := part * 2.39996
	var spread: float = minf(2.5, visual.radius * 0.82)
	var radius := sqrt(float(part) / count) * spread
	var fraction: float = visual.stock_fraction
	var location: Vector3 = visual.transform.origin + Vector3(cos(angle) * radius, 0.02 + (1.0 - radius / (spread + 0.1)) * fraction * 1.1, sin(angle) * radius)
	if part >= ceili(fraction * count):
		location.y = -50
	var size: float = (0.60 + (part % 4) * 0.12) * minf(1.0, visual.radius / 2.2)
	return Transform3D(Basis.from_euler(Vector3(0, angle, 0)).scaled(Vector3.ONE * size), location)

static func imported_mesh(scene: PackedScene) -> Mesh:
	# Mountain GLBs contain one identity-transform mesh, normalized to radius/height 1.
	var instance := scene.instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	var result: Mesh = meshes[0].mesh if meshes.size() == 1 else null
	instance.free()
	return result
