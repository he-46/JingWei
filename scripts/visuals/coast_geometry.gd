extends RefCounted
## Pure visual geometry. Reads the existing grid; never changes cells or resources.
const State = preload("res://scripts/state.gd")
const WATER_HEIGHT := 0.16
const SHORE_HEIGHT := 0.22

static func beach_width(z: float) -> float:
	return 1.65 + .55 * sin(z * .18) + .25 * sin(z * .43 + .8)

static func coast_mesh(side: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := ceili(side * 5 / 2.0)
	for segment in range(segments):
		var z0 := -side * 2.5 + segment * 2.0
		var z1 := minf(side * 2.5, z0 + 2)
		var rows: Array[Array] = []
		for z in [z0, z1]:
			var width := beach_width(z)
			rows.append([Vector3(-3, State.LAND_HEIGHT, z), Vector3(-width, State.LAND_HEIGHT, z),
				Vector3(-width * .20, .29, z), Vector3(0, SHORE_HEIGHT, z), Vector3(0, -.25, z)])
		for band in range(4):
			var a: Vector3 = rows[0][band]
			var b: Vector3 = rows[1][band]
			var c: Vector3 = rows[1][band + 1]
			var d: Vector3 = rows[0][band + 1]
			for point in [a, c, b, a, d, c]:
				tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()

static func cell_height(state: JWState, index: int) -> float:
	if index < 0 or index >= state.sea_fill.size():
		return -1.2
	if state.sea_depth[index] < 0:
		return State.LAND_HEIGHT
	return lerpf(-1.2 - state.sea_depth[index] * .65, .49, float(state.sea_fill[index]) / state.sea_capacity[index])

static func corner_height(state: JWState, col: int, row: int) -> float:
	# The original coast and first sea column share this exact edge; no cracks at x=0.
	if col == state.land_cols:
		return SHORE_HEIGHT
	var total := 0.0
	var count := 0
	for z in range(row - 1, row + 1):
		for x in range(col - 1, col + 1):
			if x >= 0 and x < state.grid_size and z >= 0 and z < state.grid_size:
				total += cell_height(state, z * state.grid_size + x)
				count += 1
	return total / maxi(1, count)

static func corner_normal(state: JWState, col: int, row: int) -> Vector3:
	return Vector3(corner_height(state, col - 1, row) - corner_height(state, col + 1, row),
		2 * State.CELL_SIZE, corner_height(state, col, row - 1) - corner_height(state, col, row + 1)).normalized()

static func cell_triangles(state: JWState, col: int, row: int) -> Array:
	var index := row * state.grid_size + col
	var point := state.cell_center(index)
	var center := Vector3(point.x, cell_height(state, index), point.y)
	var corners: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for offset in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]:
		var x: int = col + offset.x
		var z: int = row + offset.y
		corners.append(Vector3(state.map_origin.x + x * State.CELL_SIZE, corner_height(state, x, z), state.map_origin.y + z * State.CELL_SIZE))
		normals.append(corner_normal(state, x, z))
	var normal := (normals[0] + normals[1] + normals[2] + normals[3]).normalized()
	var result: Array = []
	for edge in range(4):
		result.append({"points": [center, corners[(edge + 1) % 4], corners[edge]],
			"normals": [normal, normals[(edge + 1) % 4], normals[edge]]})
	return result

static func water_segment(points: Array) -> PackedVector3Array:
	var hits := PackedVector3Array()
	for edge in range(3):
		var a: Vector3 = points[edge]
		var b: Vector3 = points[(edge + 1) % 3]
		if (a.y <= WATER_HEIGHT and b.y > WATER_HEIGHT) or (b.y <= WATER_HEIGHT and a.y > WATER_HEIGHT):
			var hit := a.lerp(b, (WATER_HEIGHT - a.y) / (b.y - a.y))
			hit.y = WATER_HEIGHT + .018
			if hits.is_empty() or not hits[0].is_equal_approx(hit):
				hits.append(hit)
	return hits if hits.size() == 2 and hits[0].distance_to(hits[1]) > .0001 else PackedVector3Array()

static func foam_strip(tool: SurfaceTool, a: Vector3, b: Vector3, width: float = .11) -> void:
	var across := Vector3(b.z - a.z, 0, a.x - b.x).normalized() * width
	var points := [a - across, a + across, b + across, a - across, b + across, b - across]
	var uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)]
	for index in range(6):
		tool.set_normal(Vector3.UP)
		tool.set_uv(uvs[index])
		tool.add_vertex(points[index])

static func mainland_foam(side: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(ceili(side * 5 / 2.0)):
		var z := -side * 2.5 + segment * 2.0
		foam_strip(tool, Vector3(0, WATER_HEIGHT + .018, z), Vector3(0, WATER_HEIGHT + .018, z + 2), .15)
	return tool.commit()
