extends SceneTree
## Compare regional updates with an independent exhaustive raster reference.
const State = preload("res://scripts/state.gd")
const Ocean = preload("res://scripts/visuals/ocean_surface.gd")
const Coast = preload("res://scripts/visuals/coast_geometry.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func make_ocean(state: JWState):
	var ocean := Ocean.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	ocean.setup(state, material)
	return ocean

func all_chunks(state: JWState) -> Dictionary:
	var result := {}
	for z in range(ceili(state.grid_size / 8.0)):
		for x in range(ceili(state.grid_size / 8.0)):
			result[Vector2i(x, z)] = true
	return result

func edit(state: JWState, col: int, row: int, fill: bool, dirty: Dictionary) -> void:
	var index := row * state.grid_size + col
	state.sea_fill[index] = state.sea_capacity[index] if fill else 0
	for x in range(maxi(state.land_cols, col - 2), mini(state.grid_size, col + 3)):
		for z in range(maxi(0, row - 2), mini(state.grid_size, row + 3)):
			dirty[Vector2i(x / 8, z / 8)] = true

func update_segments(ocean, state: JWState, keys: Dictionary) -> void:
	for key in keys:
		var lines: Array = []
		for row in range(key.y * 8, mini(state.grid_size, (key.y + 1) * 8)):
			for col in range(maxi(state.land_cols, key.x * 8), mini(state.grid_size, (key.x + 1) * 8)):
				for triangle in Coast.cell_triangles(state, col, row, false):
					var segment := Coast.water_segment(triangle.points)
					if segment.size() == 2 and maxf(segment[0].x, segment[1].x) > .20:
						lines.append(Vector4(segment[0].x, segment[0].z, segment[1].x, segment[1].z))
		ocean.set_segments(key, lines)

func exhaustive_image(ocean, state: JWState) -> Image:
	# No dirty rectangles or spatial cache: visit the whole map and every segment.
	ocean.terrain_cache.clear()
	var reference := Image.create(ocean.image.get_width(), ocean.image.get_height(), false, Image.FORMAT_RGF)
	for y in range(reference.get_height()):
		for x in range(reference.get_width()):
			var p: Vector2 = ocean.origin + Vector2(x, y)
			reference.set_pixel(x, y, Color(minf(Ocean.SHORE_RANGE, absf(p.x)), ocean.terrain_height(state, p), 0))
	for lines in ocean.segments.values():
		for line: Vector4 in lines:
			var a := Vector2(line.x, line.y)
			var b := Vector2(line.z, line.w)
			var low := Vector2i((a.min(b) - ocean.origin - Vector2.ONE * Ocean.SHORE_RANGE).floor())
			var high := Vector2i((a.max(b) - ocean.origin + Vector2.ONE * Ocean.SHORE_RANGE).ceil())
			var bounds := Rect2i(low, high - low + Vector2i.ONE).intersection(Rect2i(Vector2i.ZERO, reference.get_size()))
			var edge := b - a
			for y in range(bounds.position.y, bounds.end.y):
				for x in range(bounds.position.x, bounds.end.x):
					var p: Vector2 = ocean.origin + Vector2(x, y)
					var distance := p.distance_to(a + edge * clampf((p - a).dot(edge) / maxf(.000001, edge.length_squared()), 0, 1))
					var value := reference.get_pixel(x, y)
					value.r = minf(value.r, distance)
					reference.set_pixel(x, y, value)
	for y in range(reference.get_height()):
		for x in range(reference.get_width()):
			var value := reference.get_pixel(x, y)
			if value.g > Coast.WATER_HEIGHT: value.r = -value.r
			reference.set_pixel(x, y, value)
	return reference

func run() -> void:
	var state := State.new(100000000, 2817)
	var ocean = make_ocean(state)
	var chunks := all_chunks(state)
	for center in [Vector2i(45, 12), Vector2i(78, 80), Vector2i(64, 48)]:
		for z in range(center.y - 1, center.y + 2):
			for x in range(center.x - 1, center.x + 2): edit(state, x, z, true, {})
	update_segments(ocean, state, chunks)
	ocean.refresh(state, chunks)
	var reference = make_ocean(state)
	update_segments(reference, state, chunks)
	expect(ocean.image.get_data() == exhaustive_image(reference, state).get_data(), "full rebuild matches exhaustive distance and height raster")
	var dirty := {}
	edit(state, 45, 12, false, dirty)
	edit(state, 78, 80, false, dirty)
	update_segments(ocean, state, dirty)
	var remote_cell := 48 * state.grid_size + 64
	expect(ocean.terrain_cache.has(remote_cell), "remote height sample is cached before local edits")
	var started := Time.get_ticks_usec()
	ocean.refresh(state, dirty)
	var regional_ms := (Time.get_ticks_usec() - started) / 1000.0
	var pixels: int = ocean.last_refresh_pixels
	var candidates: int = ocean.last_segment_candidates
	var total_segments := 0
	for lines in ocean.segments.values(): total_segments += lines.size()
	expect(candidates < total_segments, "regional raster skips distant shoreline segment buckets")
	expect(ocean.terrain_cache.has(remote_cell), "remote height samples survive regional invalidation")
	var old_union := Rect2i()
	for key in dirty:
		var rect := Rect2i(Vector2i(key) * 32 - Vector2i.ONE * 9, Vector2i.ONE * 50)
		old_union = rect if not old_union.has_area() else old_union.merge(rect)
	old_union = old_union.intersection(Rect2i(Vector2i.ZERO, ocean.image.get_size()))
	expect(pixels < old_union.get_area() * .3, "distant edits avoid at least 70 percent of the previous merged raster area")
	update_segments(reference, state, chunks)
	started = Time.get_ticks_usec()
	var expected := exhaustive_image(reference, state)
	var exhaustive_ms := (Time.get_ticks_usec() - started) / 1000.0
	expect(ocean.image.get_data() == expected.get_data(), "distant edits preserve every pixel compared with a fresh exhaustive rebuild")
	var middle_before: Color = ocean.field(state.cell_center(remote_cell))
	# Shared chunk corners, new coastline, removal and outermost map samples.
	for change in [Vector3i(48, 24, 1), Vector3i(48, 24, 0), Vector3i(95, 95, 1), Vector3i(38, 0, 1)]:
		dirty = {}
		edit(state, change.x, change.y, change.z == 1, dirty)
		update_segments(ocean, state, dirty)
		ocean.refresh(state, dirty)
		update_segments(reference, state, chunks)
		expect(ocean.image.get_data() == exhaustive_image(reference, state).get_data(), "incremental coastline matches reference at chunk/map edge %s" % change)
	expect(ocean.field(state.cell_center(remote_cell)) == middle_before, "distant coastline remains untouched")
	var unchanged: PackedByteArray = ocean.image.get_data()
	var revision: int = ocean.revision
	ocean.refresh(state, {})
	expect(ocean.revision == revision and ocean.last_refresh_pixels == 0 and ocean.image.get_data() == unchanged, "idle refresh performs no image work")
	# Read-only simulation assertions are made around a refresh, not the fixture edits.
	var snapshot := state.snapshot()
	ocean.refresh(state, chunks)
	expect(state.snapshot() == snapshot, "regional cache is independent of resource and save ledgers")
	print("OCEAN UPDATE PROFILE: regional %.2f ms / %d pixels / %d segment candidates; old merged region %d pixels; exhaustive %.2f ms" % [regional_ms, pixels, candidates, old_union.get_area(), exhaustive_ms])
	print("OCEAN UPDATE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
