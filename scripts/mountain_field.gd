@tool
extends RefCounted
## Version 1: fixed cells, compressed into grounded columns. No per-cell nodes.
const VERSION := 1
const UNIT := 0.25
const STONES_PER_CELL := 64
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var seed_value: int
var amount: int
var cells: Array[Vector2i] = []
var heights := PackedInt32Array()
var lookup: Dictionary = {}
var total_cells: int
var peak: int = 0
var radius: float

static func generate(stones: int, seed_id: int, style: int, limit: float):
	var result = new()
	result.amount = stones
	result.seed_value = seed_id
	result.total_cells = ceili(float(stones) / STONES_PER_CELL)
	result.radius = minf(limit - UNIT, UNIT * pow(result.total_cells, 1.0 / 3.0) * 1.05)
	result._build(style)
	return result

func _build(style: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var phase := rng.randf_range(-PI, PI)
	var aspect := rng.randf_range(.65, .92)
	var skew := rng.randf_range(-.22, .22)
	var noise := FastNoiseLite.new()
	noise.seed = int(seed_value % 2147483647)
	noise.frequency = 2.6
	noise.fractal_octaves = 3
	var extent := ceili(radius / UNIT)
	var weights: Dictionary = {}
	for z in range(-extent, extent):
		for x in range(-extent, extent):
			var p := Vector2(x + .5, z + .5) * UNIT / radius
			var angle := atan2(p.y, p.x)
			var rim := .88 + .07 * sin(angle * 3 + phase) + .04 * cos(angle * 5 - phase)
			var q := Vector2(p.x, p.y / aspect)
			var d := q.length() / rim
			if d >= 1.0:
				continue
			var ridge := 0.0
			match style % 4:
				0: # Offset summit; the radial term keeps the foot continuous.
					ridge = exp(-3.8 * (q - Vector2(skew, .12)).length_squared())
				1:
					ridge = exp(-7 * (q - Vector2(-.36, -.08)).length_squared()) + .8 * exp(-9 * (q - Vector2(.37, .14)).length_squared())
				2:
					ridge = exp(-9 * pow(q.y - .18 * sin(q.x * 4 + phase), 2)) * (1 - .35 * absf(q.x))
				3:
					ridge = minf(1.0, (1.0 - d) * 4.0)
			var value := (1.0 - d) * .55 + ridge * minf(1.0, (1.0 - d) * 5.0)
			value *= 1.0 + .24 * noise.get_noise_2d(q.x, q.y)
			weights[Vector2i(x, z)] = maxf(.001, value)
	# Flood-fill the footprint: even tiny mountains cannot acquire detached rocks.
	var pending: Array[Vector2i] = [Vector2i.ZERO]
	var visited := {Vector2i.ZERO: true}
	var cursor := 0
	while cursor < pending.size():
		var point := pending[cursor]
		cursor += 1
		if not weights.has(point):
			continue
		cells.append(point)
		for direction in NEIGHBORS:
			var next: Vector2i = point + direction
			if weights.has(next) and not visited.has(next):
				visited[next] = true
				pending.append(next)
	# A very small stock can fill only a connected prefix of the ground footprint.
	if cells.size() > total_cells:
		cells.resize(total_cells)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var weight_sum := 0.0
	for point in cells:
		weight_sum += float(weights[point])
	var extra := total_cells - cells.size()
	var assigned := cells.size()
	var fractions: Array[Vector2] = []
	for index in range(cells.size()):
		lookup[cells[index]] = index
		var share := extra * float(weights[cells[index]]) / weight_sum
		var whole := floori(share)
		heights.append(1 + whole)
		assigned += whole
		fractions.append(Vector2(index, share - whole))
	fractions.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y > b.y or (a.y == b.y and a.x < b.x))
	for index in range(total_cells - assigned):
		heights[int(fractions[index].x)] += 1
	# Limited thermal relaxation: move whole cells from abrupt internal spikes
	# toward lower neighbors, retaining all mass and every grounded column.
	for iteration in range(16):
		var moved := false
		for step in range(cells.size()):
			var index := step if iteration % 2 == 0 else cells.size() - 1 - step
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor: int = lookup.get(cells[index] + direction, -1)
				if neighbor < 0:
					continue
				var difference := heights[index] - heights[neighbor]
				var transfer := maxi(0, (absi(difference) - 3) / 2)
				if transfer > 0:
					var sign_value := 1 if difference > 0 else -1
					heights[index] -= transfer * sign_value
					heights[neighbor] += transfer * sign_value
					moved = true
		if not moved:
			break
	for height in heights:
		peak = maxi(peak, height)

func removed_cells(work: float) -> int:
	# The final, possibly partial cell is removed only when ALL its stones are worked.
	return total_cells if work >= amount else mini(total_cells - 1, floori(maxf(0, work) / STONES_PER_CELL))

func remaining_heights(work: float) -> PackedInt32Array:
	var remove := removed_cells(work)
	if remove == 0:
		return heights
	var remaining := heights.duplicate()
	# Find the highest fully retained layer without enumerating interior cells.
	var low := 0
	var high := peak
	while low < high:
		var mid := (low + high) / 2
		var above := 0
		for height in heights:
			above += maxi(0, height - mid)
		if above > remove:
			low = mid + 1
		else:
			high = mid
	var used := 0
	for index in range(remaining.size()):
		used += maxi(0, heights[index] - low)
		remaining[index] = mini(heights[index], low)
	# Stable z/x order within a layer makes save/load and frame sizes equivalent.
	for index in range(remaining.size()):
		if used >= remove:
			break
		if remaining[index] == low and low > 0:
			remaining[index] -= 1
			used += 1
	return remaining

func surface(work: float) -> ArrayMesh:
	var levels := remaining_heights(work)
	var corners: Dictionary = {}
	for index in range(cells.size()):
		if levels[index] <= 0:
			continue
		var cell := cells[index]
		for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]:
			var corner: Vector2i = cell + offset
			if not corners.has(corner):
				corners[corner] = _corner(corner, levels)
	# Include neighboring empty quads so all outer edges taper to the ground.
	var quads: Dictionary = {}
	for corner in corners:
		for offset in [Vector2i.ZERO, Vector2i.LEFT, -Vector2i.ONE, Vector2i.UP]:
			quads[corner + offset] = true
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for cell in quads:
		var points: Array[Vector3] = []
		for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]:
			var corner: Vector2i = cell + offset
			if not corners.has(corner):
				corners[corner] = _corner(corner, levels)
			points.append(corners[corner])
		if points[0].y + points[1].y + points[2].y + points[3].y <= 0:
			continue
		var triangles := [0, 1, 2, 0, 2, 3] if (cell.x + cell.y) % 2 == 0 else [0, 1, 3, 1, 2, 3]
		for face in range(0, 6, 3):
			var a := points[triangles[face]]
			var b := points[triangles[face + 1]]
			var c := points[triangles[face + 2]]
			var normal := (c - a).cross(b - a).normalized()
			var tint := Color("91988a").lerp(Color("c5bca2"), .35 + .14 * sin((a.y + b.y + c.y) * 3.1))
			for vertex in [a, b, c]:
				vertices.append(vertex)
				normals.append(normal)
				colors.append(tint)
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _corner(point: Vector2i, levels: PackedInt32Array) -> Vector3:
	var sum := 0
	for offset in [Vector2i.ZERO, Vector2i.LEFT, -Vector2i.ONE, Vector2i.UP]:
		var index: int = lookup.get(point + offset, -1)
		if index >= 0:
			sum += levels[index]
	var height := sum * UNIT * .25
	# Coordinate-based offsets are shared by adjoining faces: no cracks, no shimmer.
	var n := posmod(point.x * 73856093 ^ point.y * 19349663 ^ seed_value, 65521)
	var jitter_x := (float(n % 101) / 100.0 - .5) * UNIT * .3
	var jitter_z := (float(n % 97) / 96.0 - .5) * UNIT * .3
	return Vector3(point.x * UNIT + jitter_x, height, point.y * UNIT + jitter_z)
