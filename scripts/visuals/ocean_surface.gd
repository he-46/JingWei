extends RefCounted
## Presentation only: fixed-grid shore atlas, analytic waves and bounded impact rings.
const Coast = preload("res://scripts/visuals/coast_geometry.gd")
const CELL := 4.0
const CHUNK := 8
const SHORE_RANGE := 8.0
const RIPPLE_COUNT := 8
const RIPPLE_LIFE := 4.5
const WAVES := [Vector4(-.9805807, .1961161, .16, .70), Vector4(-.7071068, -.7071068, .07, 1.15), Vector4(-.8574929, .5144958, .035, 1.90)]
const SPEEDS := [1.05, 1.38, 1.85]
var clock := 0.0
var origin: Vector2
var side: float
var image: Image
var texture: ImageTexture
var segments: Dictionary = {}
var terrain_cache: Dictionary = {}
var events := PackedVector4Array()
var event_serial := 0
var material: ShaderMaterial
var revision := 0

func setup(state: JWState, target: ShaderMaterial) -> void:
	origin = state.map_origin
	side = state.map_side
	material = target
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
	var size := side + 24
	var steps := ceili(size / spacing)
	var stride := steps + 1
	var start := origin - Vector2.ONE * 12
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
	if dirty.is_empty(): return
	terrain_cache.clear()
	var rect := Rect2i()
	for key in dirty:
		var part := Rect2i(Vector2i(key) * CHUNK * int(CELL) - Vector2i.ONE * 9, Vector2i.ONE * (CHUNK * int(CELL) + 18))
		rect = part if rect.size == Vector2i.ZERO else rect.merge(part)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := origin + Vector2(x, y)
			image.set_pixel(x, y, Color(minf(SHORE_RANGE, absf(p.x)), terrain_height(state, p), 0))
	# Rasterize only the narrow band around actual triangle/water intersections.
	for list in segments.values():
		for line: Vector4 in list:
			var a := Vector2(line.x, line.y)
			var b := Vector2(line.z, line.w)
			var low := Vector2i((a.min(b) - origin - Vector2.ONE * SHORE_RANGE).floor())
			var high := Vector2i((a.max(b) - origin + Vector2.ONE * SHORE_RANGE).ceil())
			var bounds := Rect2i(low, high - low + Vector2i.ONE).intersection(rect)
			var edge := b - a
			var length_squared := maxf(.000001, edge.length_squared())
			for y in range(bounds.position.y, bounds.end.y):
				for x in range(bounds.position.x, bounds.end.x):
					var p := origin + Vector2(x, y)
					var distance := p.distance_to(a + edge * clampf((p - a).dot(edge) / length_squared, 0, 1))
					var value := image.get_pixel(x, y)
					value.r = minf(value.r, distance)
					image.set_pixel(x, y, value)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var value := image.get_pixel(x, y)
			if value.g > Coast.WATER_HEIGHT: value.r = -value.r
			image.set_pixel(x, y, value)
	texture.update(image)
	revision += 1

func field(point: Vector2) -> Color:
	var q := point - origin
	if q.x < 0 or q.y < 0 or q.x > side or q.y > side:
		return Color(clampf(point.x, -SHORE_RANGE, SHORE_RANGE), .44 if point.x < 0 else -2, 0)
	var x := mini(floori(q.x), image.get_width() - 2)
	var y := mini(floori(q.y), image.get_height() - 2)
	return image.get_pixel(x, y).lerp(image.get_pixel(x + 1, y), q.x - x).lerp(image.get_pixel(x, y + 1).lerp(image.get_pixel(x + 1, y + 1), q.x - x), q.y - y)

func displacement(point: Vector2, at_time: float = -1) -> Vector3:
	var now := clock if at_time < 0 else at_time
	var fade := smoothstep(.35, 3.0, field(point).r)
	var result := Vector3.ZERO
	for i in range(WAVES.size()):
		var wave: Vector4 = WAVES[i]
		var direction := Vector2(wave.x, wave.y)
		var phase: float = wave.w * direction.dot(point) - SPEEDS[i] * now
		result += Vector3(direction.x * .55 * wave.z * cos(phase), wave.z * sin(phase), direction.y * .55 * wave.z * cos(phase))
	var ripple := 0.0
	for event in events:
		var age := now - event.z
		if age < 0 or age > RIPPLE_LIFE: continue
		var distance := point.distance_to(Vector2(event.x, event.y))
		var front := distance - age * 2.8
		ripple += event.w * sin(front * 5.0) * exp(-front * front * 1.5) * exp(-age * .7)
	result.y += clampf(ripple, -.10, .10)
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
	events[event_serial % RIPPLE_COUNT] = Vector4(p.x, p.y, clock, .07)
	event_serial += 1
	material.set_shader_parameter("ripple_events", events)

func advance(seconds: float) -> void:
	clock += seconds
	material.set_shader_parameter("wave_time", clock)

func ray_hit(state: JWState, start: Vector3, direction: Vector3) -> Variant:
	if direction.y >= -.00001: return null
	var enter := maxf(0, (.60 - start.y) / direction.y)
	var leave := (-.26 - start.y) / direction.y
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
