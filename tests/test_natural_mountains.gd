extends SceneTree
const Field = preload("res://scripts/mountain_field.gd")
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func run() -> void:
	var started := Time.get_ticks_msec()
	var signatures: Dictionary = {}
	for style in range(4):
		for seed_id in [17, 2817, 91231]:
			for amount in [1024, 32769, 2000000]:
				var field = Field.generate(amount, seed_id, style, 6.5)
				var again = Field.generate(amount, seed_id, style, 6.5)
				expect(field.heights == again.heights and field.cells == again.cells, "same seed reproduces exact columns")
				expect(field.heights.count(0) == 0 and field.heights.size() == field.cells.size(), "every column stands on the ground")
				var seen := {field.cells[0]: true}
				var queue: Array = [field.cells[0]]
				var cursor := 0
				while cursor < queue.size():
					var p: Vector2i = queue[cursor]
					cursor += 1
					for direction in Field.NEIGHBORS:
						var next: Vector2i = p + direction
						if field.lookup.has(next) and not seen.has(next):
							seen[next] = true
							queue.append(next)
				expect(seen.size() == field.cells.size(), "footprint is a single connected mountain")
				var previous: PackedInt32Array = field.heights
				for work in [0.0, 63.0, 64.0, amount * .37, amount - .1, float(amount)]:
					var levels: PackedInt32Array = field.remaining_heights(work)
					var total := 0
					var monotonic := true
					for i in range(levels.size()):
						total += levels[i]
						monotonic = monotonic and levels[i] <= previous[i] and levels[i] >= 0
					expect(total == field.total_cells - field.removed_cells(work) and monotonic, "top-down excavation removes exact whole cells only")
					previous = levels
				var mesh: ArrayMesh = field.surface(0)
				var bounded := true
				for p in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					bounded = bounded and p.y >= 0 and Vector2(p.x, p.z).length() <= 6.5
				expect(bounded, "shared surface vertices remain inside reserved plot")
				expect(field.surface(amount).get_surface_count() == 0, "empty mountain has no leftover skin")
				signatures[hash(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])] = true
	expect(signatures.size() >= 30, "seeds and families produce varied silhouettes")
	for profile in State.PROFILES:
		var state := State.new(profile.target, 2817)
		var saved := state.snapshot()
		var loaded := State.from_snapshot(saved)
		expect(loaded != null and loaded.snapshot() == saved, "new geometry version survives save/load")
		var total := 0
		for index in range(state.mountains.size()):
			var field = state.mountain_field(index)
			total += field.total_cells
			expect(field.heights == loaded.mountain_field(index).heights, "load regenerates same mountain")
		print("NATURAL PROFILE %d: %d cells, tallest %.2f" % [profile.target, total, state.high_flight_height()])
		# Removing the optional field simulates an unmodified v3 save.
		for mountain in saved.mountains:
			mountain.erase("terrain_version")
		var legacy := State.from_snapshot(saved)
		expect(legacy != null and not legacy.is_natural_mountain(0) and legacy.snapshot() == saved, "legacy v3 loads without reshaping or rewriting")
	var state := State.new(100000, 2817)
	var world := World.new()
	root.add_child(world)
	await world.setup(state)
	await physics_frame
	await physics_frame
	var surface: MeshInstance3D = world.natural_mountains[0]
	expect(surface.global_basis.get_scale().is_equal_approx(Vector3.ONE), "mountain nodes never scale with stock")
	var original := surface.mesh
	var other: MeshInstance3D = world.natural_mountains[-1]
	var center := other.global_position
	var ray := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 50, center - Vector3.UP)
	ray.exclude = [world.bird_body.get_rid()]
	expect(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "real physics ray hits the natural mountain")
	state.mountains[0].work = 63.9
	await world.sync(state)
	expect(surface.mesh == original, "partial cell mining does not rebuild or shrink geometry")
	state.mountains[0].work = 64.0
	await world.sync(state)
	await physics_frame
	await physics_frame
	expect(surface.mesh != original, "completed cell rebuilds surface")
	var shape: ConcavePolygonShape3D = world.mountain_collisions[0].shape
	expect(shape.get_faces() == surface.mesh.get_faces(), "visible surface and physics use identical triangles")
	state.mountains[0].work = state.mountains[0].yield
	state.mountains[0].settled = true
	state.mountains[0].stock = state.mountains[0].yield
	await world.sync(state)
	await physics_frame
	await physics_frame
	expect(not surface.visible and world.mountain_collisions[0].disabled, "completed mountain clears skin and collision")
	world.queue_free()
	await process_frame
	print("NATURAL MOUNTAINS: %d checks, %d failures, %d ms" % [checks, failures, Time.get_ticks_msec() - started])
	quit(1 if failures else 0)
