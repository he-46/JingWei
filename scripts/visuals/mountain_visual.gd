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

static func from_state(state: JWState, index: int):
	var result = new()
	var mountain: Dictionary = state.mountains[index]
	result.radius = state.mountain_radius(index)
	result.height = state.mountain_height(index)
	result.remaining = clampf(1.0 - float(mountain["work"]) / float(mountain["yield"]), 0, 1)
	result.stock = int(mountain["stock"])
	result.stock_fraction = clampf(float(result.stock) / float(mountain["yield"]), 0, 1)
	var point := state.mountain_position(index)
	result.transform = Transform3D(Basis.from_euler(Vector3(0, float(mountain["yaw"]), 0)).scaled(Vector3(result.radius, result.height, result.radius)), Vector3(point.x, state.LAND_HEIGHT, point.y))
	result.collision_radius = result.radius * state.MOUNTAIN_COLLISION_RATIO
	result.collision_height = result.height * maxf(0.05, result.remaining)
	return result

static func imported_mesh(scene: PackedScene) -> Mesh:
	# Mountain GLBs contain one identity-transform mesh, normalized to radius/height 1.
	var instance := scene.instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	var result: Mesh = meshes[0].mesh if meshes.size() == 1 else null
	instance.free()
	return result
