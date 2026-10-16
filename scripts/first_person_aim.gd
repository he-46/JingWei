extends RefCounted
## Read-only ray intersection with the same triangles used by reclaimed terrain.
const State = preload("res://scripts/state.gd")
const Coast = preload("res://scripts/visuals/coast_geometry.gd")

static func surface_hit(state: JWState, origin: Vector3, direction: Vector3) -> Variant:
	var best: Variant = null
	for height in [Coast.WATER_HEIGHT, State.LAND_HEIGHT]:
		var hit: Variant = Plane(Vector3.UP, height).intersects_ray(origin, direction)
		if hit != null and state.cell_at(Vector2(hit.x, hit.z)) >= 0 and ((height == Coast.WATER_HEIGHT and hit.x >= 0) or (height == State.LAND_HEIGHT and hit.x <= -3)):
			if best == null or origin.distance_squared_to(hit) < origin.distance_squared_to(best):
				best = hit
	# Walk exact grid crossings, including a straight-down ray; work scales with
	# map width, not area. Every candidate triangle is tested once per visited cell.
	var col := floori((origin.x - state.map_origin.x) / State.CELL_SIZE)
	var row := floori((origin.z - state.map_origin.y) / State.CELL_SIZE)
	var sx := 1 if direction.x >= 0 else -1
	var sz := 1 if direction.z >= 0 else -1
	var tx := INF if absf(direction.x) < .000001 else (state.map_origin.x + (col + (1 if sx > 0 else 0)) * State.CELL_SIZE - origin.x) / direction.x
	var tz := INF if absf(direction.z) < .000001 else (state.map_origin.y + (row + (1 if sz > 0 else 0)) * State.CELL_SIZE - origin.z) / direction.z
	var dx := INF if absf(direction.x) < .000001 else State.CELL_SIZE / absf(direction.x)
	var dz := INF if absf(direction.z) < .000001 else State.CELL_SIZE / absf(direction.z)
	for unused in range(state.grid_size * 2 + 2):
		if col < 0 or row < 0 or col >= state.grid_size or row >= state.grid_size:
			break
		var triangles: Array = []
		if col >= state.land_cols:
			for triangle in Coast.cell_triangles(state, col, row):
				triangles.append(triangle.points)
		elif col == state.land_cols - 1:
			# Match the original beach mesh, including its two-unit Z segments.
			for segment in range(2):
				var z := state.map_origin.y + row * State.CELL_SIZE + segment * 2
				var strips: Array = []
				for edge in [z, z + 2]:
					var width := Coast.beach_width(edge)
					strips.append([Vector3(-3, State.LAND_HEIGHT, edge), Vector3(-width, State.LAND_HEIGHT, edge), Vector3(-width * .20, .29, edge), Vector3(0, Coast.SHORE_HEIGHT, edge)])
				for band in range(3):
					triangles.append([strips[0][band], strips[1][band + 1], strips[1][band]])
					triangles.append([strips[0][band], strips[0][band + 1], strips[1][band + 1]])
		for triangle in triangles:
			var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, triangle[0], triangle[1], triangle[2])
			if hit != null and state.cell_at(Vector2(hit.x, hit.z)) >= 0 and (best == null or origin.distance_squared_to(hit) < origin.distance_squared_to(best)):
				best = hit
		var next := minf(tx, tz)
		if is_inf(next) or (best != null and next * next > origin.distance_squared_to(best)):
			break
		if tx <= tz:
			col += sx
			tx += dx
		else:
			row += sz
			tz += dz
	return best
