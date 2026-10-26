extends RefCounted
## Presentation only: fixed-grid shore atlas, analytic waves and bounded impact rings.
const Coast = preload("res://scripts/visuals/coast_geometry.gd")
const Parameters = preload("res://scripts/visuals/ocean_parameters.gd")
const CELL := 4.0
const CHUNK := 8
const SHORE_RANGE := Parameters.SHORE_RANGE
const RIPPLE_COUNT := Parameters.RIPPLE_COUNT
const RIPPLE_LIFE := Parameters.RIPPLE_LIMITS.x
var clock := 0.0
var origin: Vector2
var side: float
var image: Image
var texture: ImageTexture
var segments: Dictionary = {}
var segment_cache: Dictionary = {}
var terrain_cache: Dictionary = {}
var events := PackedVector4Array()
var event_serial := 0
var material: ShaderMaterial
var revision := 0
var last_refresh_pixels := 0
var last_segment_candidates := 0

func setup(state: JWState, target: ShaderMaterial) -> void:
	origin = state.map_origin
	side = state.map_side
	material = target
	Parameters.apply_to(material)
	var size := int(side) + 1 # One metre per texel; independent of journey scale.
	image = Image.create(size, size, false, Image.FORMAT_RGF)
	for x in range(size):
		var wx := origin.x + x
		image.fill_rect(Rect2i(x, 0, 1, size), Color(clampf(wx, -SHORE_RANGE, SHORE_RANGE), .44 if wx < 0 else -2, 0))
	texture = ImageTexture.create_from_image(image)
	events.resize(RIPPLE_COUNT)
	events.fill(Vector4(0, 0, -100, 0))
	material.set_shader_parameter("shore_atlas", texture)
	material.set_shader_parameter("atlas_origin", origin)
	material.set_shader_parameter("atlas_size", Vector2.ONE * size)
	material.set_shader_parameter("map_side", side)
	material.set_shader_parameter("ripple_events", events)
	material.set_shader_parameter("wave_time", clock)

func mesh(spacing: float = 1.0) -> ArrayMesh:
	# Detailed playable square, then a cheap outer ring extending behind boundary fog.
	var size := side + 2 * Parameters.OUTER_FADE.x
	var steps := ceili(size / spacing)
	var stride := steps + 1
	var start := origin - Vector2.ONE * Parameters.OUTER_FADE.x
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(stride):
		for x in range(stride):
			var p := start + Vector2(x, z) * size / steps
			vertices.append(Vector3(p.x, 0, p.y))
			normals.append(Vector3.UP)
	for z in range(steps):
		for x in range(steps):
			var a := z * stride + x
			indices.append_array(PackedInt32Array([a, a + 1, a + stride + 1, a, a + stride + 1, a + stride]))
	var rim: Array[int] = []
	for x in range(steps): rim.append(x)
	for z in range(steps): rim.append(z * stride + steps)
	for x in range(steps, 0, -1): rim.append(steps * stride + x)
	for z in range(steps, 0, -1): rim.append(z * stride)
	var outer_start := vertices.size()
	var center := origin + Vector2.ONE * side * .5
	for index in rim:
		var p := Vector2(vertices[index].x, vertices[index].z)
		p = center + (p - center) * (side * 5 / size)
		vertices.append(Vector3(p.x, 0, p.y))
		normals.append(Vector3.UP)
	for i in range(rim.size()):
		var j := (i + 1) % rim.size()
		indices.append_array(PackedInt32Array([rim[i], outer_start + i, outer_start + j, rim[i], outer_start + j, rim[j]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func set_segments(key: Vector2i, value: Array) -> void:
	segments[key] = value
	var cached: Array = []
	for line: Vector4 in value:
		var a := Vector2(line.x, line.y)
		var b := Vector2(line.z, line.w)
		var edge := b - a
		var low := Vector2i((a.min(b) - origin - Vector2.ONE * SHORE_RANGE).floor())
		var high := Vector2i((a.max(b) - origin + Vector2.ONE * SHORE_RANGE).ceil())
		cached.append({"a": a, "edge": edge, "length_squared": maxf(.000001, edge.length_squared()), "bounds": Rect2i(low, high - low + Vector2i.ONE)})
	segment_cache[key] = cached

func terrain_height(state: JWState, point: Vector2) -> float:
	if point.x <= 0: return .44
	var cell := state.cell_at(point)
	if cell < 0: return -2
	if not terrain_cache.has(cell):
		var col := cell % state.grid_size
		var row := cell / state.grid_size
		terrain_cache[cell] = PackedFloat32Array([Coast.cell_height(state, cell), Coast.corner_height(state, col, row), Coast.corner_height(state, col, row + 1), Coast.corner_height(state, col + 1, row + 1), Coast.corner_height(state, col + 1, row)])
	var h: PackedFloat32Array = terrain_cache[cell]
	var delta := (point - state.cell_center(cell)) / CELL
	var blend := maxf(absf(delta.x), absf(delta.y)) * 2
	if blend < .00001: return h[0]
	var edge: float
	if absf(delta.x) > absf(delta.y):
		var ratio := .5 + delta.y / (2 * absf(delta.x))
		edge = lerpf(h[4], h[3], ratio) if delta.x > 0 else lerpf(h[1], h[2], ratio)
	else:
		var ratio := .5 + delta.x / (2 * absf(delta.y))
		edge = lerpf(h[2], h[3], ratio) if delta.y > 0 else lerpf(h[1], h[4], ratio)
	return lerpf(h[0], edge, blend)

func refresh(state: JWState, dirty: Dictionary) -> void:
	last_refresh_pixels = 0
	last_segment_candidates = 0
	if dirty.is_empty(): return
	# Corner samples use adjacent cells. Evict only the changed chunk and its halo.
	for key in dirty:
		for row in range(maxi(0, key.y * CHUNK - 1), mini(state.grid_size, (key.y + 1) * CHUNK + 1)):
			for col in range(maxi(0, key.x * CHUNK - 1), mini(state.grid_size, (key.x + 1) * CHUNK + 1)):
				terrain_cache.erase(row * state.grid_size + col)
	for rect in dirty_rectangles(dirty):
		_refresh_rect(state, rect)
	# Godot ImageTexture.update uploads the full image; CPU raster work is regional.
	texture.update(image)
	revision += 1

func dirty_rectangles(dirty: Dictionary) -> Array[Rect2i]:
	# Union row intervals, then join identical intervals vertically. Distant edits
	# stay disjoint and overlapping halos never rasterize the same pixel twice.
	var rows: Dictionary = {}
	var padding := ceili(SHORE_RANGE) + 1
	for key in dirty:
		var rect := Rect2i(Vector2i(key) * CHUNK * int(CELL) - Vector2i.ONE * padding, Vector2i.ONE * (CHUNK * int(CELL) + padding * 2))
		rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if not rect.has_area(): continue
		for y in range(rect.position.y, rect.end.y):
			if not rows.has(y): rows[y] = []
			rows[y].append(Vector2i(rect.position.x, rect.end.x))
	var result: Array[Rect2i] = []
	var active: Dictionary = {}
	for y in range(image.get_height() + 1):
		var intervals: Array = rows.get(y, [])
		intervals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		var merged: Array[Vector2i] = []
		for interval: Vector2i in intervals:
			if not merged.is_empty() and interval.x <= merged[-1].y:
				merged[-1].y = maxi(merged[-1].y, interval.y)
			else:
				merged.append(interval)
		var next: Dictionary = {}
		for interval in merged:
			var rect: Rect2i = active.get(interval, Rect2i(interval.x, y, interval.y - interval.x, 0))
			rect.size.y += 1
			next[interval] = rect
		for interval in active:
			if not next.has(interval): result.append(active[interval])
		active = next
	return result

func _refresh_rect(state: JWState, rect: Rect2i) -> void:
	last_refresh_pixels += rect.get_area()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := origin + Vector2(x, y)
			image.set_pixel(x, y, Color(minf(SHORE_RANGE, absf(p.x)), terrain_height(state, p), 0))
	# Segment ownership is already spatial: only nearby terrain chunks can affect
	# this rectangle. The one-pixel guard includes segments on shared chunk edges.
	var nearby := rect.grow(ceili(SHORE_RANGE) + 1)
	var low := Vector2i(floori(float(nearby.position.x) / (CHUNK * CELL)), floori(float(nearby.position.y) / (CHUNK * CELL)))
	var high := Vector2i(floori(float(nearby.end.x) / (CHUNK * CELL)), floori(float(nearby.end.y) / (CHUNK * CELL)))
	for row in range(low.y, high.y + 1):
		for col in range(low.x, high.x + 1):
			for line: Dictionary in segment_cache.get(Vector2i(col, row), []):
				last_segment_candidates += 1
				var bounds: Rect2i = line.bounds.intersection(rect)
				for y in range(bounds.position.y, bounds.end.y):
					for x in range(bounds.position.x, bounds.end.x):
						var p := origin + Vector2(x, y)
						var distance: float = p.distance_to(line.a + line.edge * clampf((p - line.a).dot(line.edge) / line.length_squared, 0, 1))
						var value := image.get_pixel(x, y)
						value.r = minf(value.r, distance)
						image.set_pixel(x, y, value)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var value := image.get_pixel(x, y)
			if value.g > Coast.WATER_HEIGHT: value.r = -value.r
			image.set_pixel(x, y, value)

func field(point: Vector2) -> Color:
	var q := point - origin
	if q.x < 0 or q.y < 0 or q.x > side or q.y > side:
		return Color(clampf(point.x, -SHORE_RANGE, SHORE_RANGE), .44 if point.x < 0 else -2, 0)
	var x := mini(floori(q.x), image.get_width() - 2)
	var y := mini(floori(q.y), image.get_height() - 2)
	return image.get_pixel(x, y).lerp(image.get_pixel(x + 1, y), q.x - x).lerp(image.get_pixel(x, y + 1).lerp(image.get_pixel(x + 1, y + 1), q.x - x), q.y - y)

func displacement(point: Vector2, at_time: float = -1) -> Vector3:
	var now := clock if at_time < 0 else at_time
	var fade := smoothstep(Parameters.SHORE_FADE.x, Parameters.SHORE_FADE.y, field(point).r)
	var outer := maxf(absf(point.x - origin.x - side * .5), absf(point.y - origin.y - side * .5)) - side * .5
	fade *= 1.0 - smoothstep(Parameters.OUTER_FADE.x, Parameters.OUTER_FADE.y, outer)
	var result := Vector3.ZERO
	for i in range(Parameters.WAVES.size()):
		var wave: Vector4 = Parameters.WAVES[i]
		var direction := Vector2(wave.x, wave.y)
		var phase: float = wave.w * direction.dot(point) - Parameters.SPEEDS[i] * now
		result += Vector3(direction.x * Parameters.HORIZONTAL_SCALE * wave.z * cos(phase), wave.z * sin(phase), direction.y * Parameters.HORIZONTAL_SCALE * wave.z * cos(phase))
	var ripple := 0.0
	for event in events:
		var age := now - event.z
		if age < 0 or age > RIPPLE_LIFE: continue
		var distance := point.distance_to(Vector2(event.x, event.y))
		var shape := Parameters.RIPPLE_SHAPE
		var front := distance - age * shape.x
		ripple += event.w * sin(front * shape.y) * exp(-front * front * shape.z) * exp(-age * shape.w)
	result.y += clampf(ripple, -Parameters.RIPPLE_LIMITS.y, Parameters.RIPPLE_LIMITS.y)
	return result * fade

func height(point: Vector2) -> float:
	# Invert the small horizontal Gerstner offset for a query in world coordinates.
	var base := point
	for iteration in range(4):
		var offset := displacement(base)
		base = point - Vector2(offset.x, offset.z)
	return Coast.WATER_HEIGHT + displacement(base).y

func impact_height(point: Vector2) -> float:
	return maxf(height(point), field(point).g) + .015

func add_ripple(point: Vector3) -> void:
	var p := Vector2(point.x, point.z)
	if field(p).r <= .05: return
	events[event_serial % RIPPLE_COUNT] = Vector4(p.x, p.y, clock, Parameters.RIPPLE_AMPLITUDE)
	event_serial += 1
	material.set_shader_parameter("ripple_events", events)

func advance(seconds: float) -> void:
	clock += seconds
	material.set_shader_parameter("wave_time", clock)

func ray_hit(state: JWState, start: Vector3, direction: Vector3) -> Variant:
	if direction.y >= -.00001: return null
	var bound := Parameters.displacement_bound() + .05
	var enter := maxf(0, (Coast.WATER_HEIGHT + bound - start.y) / direction.y)
	var leave := (Coast.WATER_HEIGHT - bound - start.y) / direction.y
	for axis in [0, 2]:
		var minimum: float = origin.x if axis == 0 else origin.y
		var component: float = direction[axis]
		if absf(component) < .00001:
			if start[axis] < minimum or start[axis] > minimum + side: return null
		else:
			var a: float = (minimum - start[axis]) / component
			var b: float = (minimum + side - start[axis]) / component
			enter = maxf(enter, minf(a, b))
			leave = minf(leave, maxf(a, b))
	if leave <= enter: return null
	var previous := enter
	var distance := enter
	while distance <= leave + .0001:
		var p := start + direction * distance
		var point := Vector2(p.x, p.z)
		if p.y <= height(point):
			var low := previous
			var high := distance
			for iteration in range(12):
				var mid := (low + high) * .5
				var sample := start + direction * mid
				if sample.y > height(Vector2(sample.x, sample.z)): low = mid
				else: high = mid
			var hit := start + direction * ((low + high) * .5)
			if hit.x >= 0 and state.cell_at(Vector2(hit.x, hit.z)) >= 0: return hit
			return null
		if distance == leave: break
		previous = distance
		distance = minf(leave, distance + .65)
	return null
