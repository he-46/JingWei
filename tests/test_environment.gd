extends SceneTree
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
const Coast = preload("res://scripts/visuals/coast_geometry.gd")
const Visual = preload("res://scripts/visuals/mountain_visual.gd")
const Store = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func fill(state: JWState, col: int, row: int, fraction: float = 1.0) -> void:
	var index := row * state.grid_size + col
	var amount := roundi(state.sea_capacity[index] * fraction) - state.sea_fill[index]
	if amount <= 0:
		return
	state.player = state.cell_center(index)
	state.carried = amount
	state.total_generated += amount
	state.deposit(state.player)

func vertex_data(mesh: Mesh) -> Dictionary:
	var result: Dictionary = {}
	var arrays := mesh.surface_get_arrays(0)
	for index in range(arrays[Mesh.ARRAY_VERTEX].size()):
		var point: Vector3 = arrays[Mesh.ARRAY_VERTEX][index]
		result[point.snapped(Vector3.ONE * .0001)] = arrays[Mesh.ARRAY_NORMAL][index]
	return result

func matching_seam(a: Mesh, b: Mesh) -> bool:
	var left := vertex_data(a)
	var right := vertex_data(b)
	var common := 0
	for point in left:
		if right.has(point):
			common += 1
			if not left[point].is_equal_approx(right[point]):
				return false
	return common >= 2

func run() -> void:
	for item in [["coast_tree", 900], ["coast_shrub", 350], ["coast_grass", 60], ["shore_rock", 250]]:
		var scene: PackedScene = load("res://assets/models/environment/%s.glb" % item[0])
		var instance := scene.instantiate()
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		expect(meshes.size() == 1 and meshes[0].transform.is_equal_approx(Transform3D.IDENTITY), "sample exports one identity-transform mesh: " + item[0])
		var mesh: Mesh = meshes[0].mesh
		expect(mesh.get_surface_count() == 1 and mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3 <= item[1], "sample meets single-material triangle budget: " + item[0])
		expect(mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size() == mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), "sample has complete painted UVs: " + item[0])
		expect(mesh.get_aabb().position.y > -.01 and instance.find_children("*", "Skeleton3D", true, false).is_empty() and instance.find_children("*", "CollisionObject3D", true, false).is_empty(), "grounded decor adds no skeletons or gameplay collision: " + item[0])
		instance.free()
	var atlas: Texture2D = load("res://assets/textures/environment/coast_palette.png")
	expect(atlas.get_width() == 512 and atlas.get_image().has_mipmaps(), "environment samples share one mipmapped 512-square atlas")
	var mesh := Coast.coast_mesh(48)
	var on_land := true
	var heights := true
	var data: Array = mesh.surface_get_arrays(0)
	for point in data[Mesh.ARRAY_VERTEX]:
		on_land = on_land and point.x <= 0 and point.x >= -3
		if is_zero_approx(point.x) and point.y > 0:
			heights = heights and is_equal_approx(point.y, Coast.SHORE_HEIGHT)
	expect(on_land and heights, "variable beach geometry ends exactly at the original x=0 coast")
	var widths: Dictionary = {}
	var bounded_width := true
	for z in range(-24, 25):
		var width := Coast.beach_width(z)
		widths[roundi(width * 10)] = true
		bounded_width = bounded_width and width > .8 and width < 2.5
	expect(bounded_width, "beach width stays inside the three-unit coast strip")
	expect(widths.size() > 8, "coast has visibly different beach widths")
	var crossing := Coast.water_segment([Vector3(0, -.2, 0), Vector3(2, .5, 0), Vector3(0, .5, 2)])
	expect(crossing.size() == 2 and is_equal_approx(crossing[0].y, Coast.WATER_HEIGHT + .018), "foam comes from the actual terrain-water intersection")
	expect(Coast.water_segment([Vector3(0, .49, 0), Vector3(2, .49, 0), Vector3(0, .49, 2)]).is_empty(), "fully dry triangles do not emit interior foam")
	expect(Coast.water_segment([Vector3(0, -1, 0), Vector3(2, -1, 0), Vector3(0, -1, 2)]).is_empty(), "submerged triangles do not emit false shorelines")
	for profile in State.PROFILES:
		var state := State.new(int(profile["target"]), 10213)
		var before := state.snapshot()
		var world := World.new()
		root.add_child(world)
		world.setup(state)
		expect(state.snapshot() == before, "environment setup never changes generation, capacity or resource ledgers")
		expect(is_equal_approx(world.water_surface.position.y, Coast.WATER_HEIGHT) and world.coast_surface.mesh != null, "every scale uses the flat reference water and connected coastal mesh")
		expect(int(world.water_material.get_shader_parameter("shallow_end")) == int(state.bands[0]) * 4 and int(world.water_material.get_shader_parameter("far_end")) == (int(state.bands[0]) + int(state.bands[1])) * 4, "smooth water bands follow each map profile")
		expect(world.tree_mesh.instance_count <= 200 and world.shrub_mesh.instance_count <= 160 and world.shore_rocks.instance_count <= 160 and world.grass_mesh.instance_count <= 2500, "sample decor counts are bounded independently of stone totals")
		expect(state.cell_at(Vector2(.01, 0)) >= 0 and state.sea_depth[state.cell_at(Vector2(.01, 0))] >= 0 and state.sea_depth[state.cell_at(Vector2(-.01, 0))] < 0, "visual shore retains the original mainland and sea classifications")
		world.animate(state, .3, false, false, -1)
		expect(is_equal_approx(world.water_material.get_shader_parameter("wave_time"), world.foam_material.get_shader_parameter("wave_time")) and is_equal_approx(world.foliage_material.get_shader_parameter("wind_time"), world.time), "water, foam and foliage share the simulated clock")
		world.overview = true
		world.animate(state, 0, false, false, -1)
		expect(world.grass_mesh.visible_instance_count == 0 and world.shrub_mesh.visible_instance_count == 0, "overview hides small vegetation details")
		world.overview = false
		world.animate(state, 0, false, false, -1)
		expect(world.grass_mesh.visible_instance_count == -1 and world.shrub_mesh.visible_instance_count == -1, "normal view restores vegetation without rebuilding it")
		if DisplayServer.get_name() != "headless":
			for decor in [[world.tree_mesh, 2.9, 2.7], [world.shrub_mesh, 1.2, 1.2], [world.grass_mesh, .2, 0.0]]:
				var clear := true
				var grounded := true
				var count := 0
				for index in range(decor[0].instance_count):
					var position: Vector3 = decor[0].get_instance_transform(index).origin
					if position.y < -10:
						continue
					count += 1
					var point := Vector2(position.x, position.z)
					clear = clear and state.clear_of_mountains(point, decor[1] - .001)
					if decor[2] > 0:
						clear = clear and world._clear_of_resources(state, point, decor[2] - .001)
					grounded = grounded and absf(position.y - State.LAND_HEIGHT) < .001 and position.x < -2.6
				expect(clear and count > 0, "actual decor instances reserve mountain, pickup and future NPC clearances")
				expect(grounded, "actual vegetation roots stay on the mainland ground")
		world.queue_free()
		await process_frame
	var state := State.new(100000, 10213)
	var world := World.new()
	root.add_child(world)
	world.setup(state)
	for row in [7, 8]:
		for col in [7, 8]:
			fill(state, col, row)
	world.sync(state)
	expect(matching_seam(world.terrain_chunks[Vector2i(0, 0)].mesh, world.terrain_chunks[Vector2i(1, 0)].mesh), "horizontal chunk boundary shares exact vertices and normals")
	expect(matching_seam(world.terrain_chunks[Vector2i(1, 0)].mesh, world.terrain_chunks[Vector2i(1, 1)].mesh), "vertical chunk boundary shares exact vertices and normals")
	var corner := Vector3(12, .49, 8).snapped(Vector3.ONE * .0001)
	var before_normal: Vector3 = vertex_data(world.terrain_chunks[Vector2i(1, 1)].mesh)[corner]
	fill(state, 6, 7)
	world.sync(state)
	var after_normal: Vector3 = vertex_data(world.terrain_chunks[Vector2i(1, 1)].mesh)[corner]
	expect(not before_normal.is_equal_approx(after_normal) and after_normal.distance_to(Coast.corner_normal(state, 8, 8)) < .001, "a change two cells away rebuilds neighboring corner normals within mesh compression precision")
	expect(matching_seam(world.terrain_chunks[Vector2i(0, 1)].mesh, world.terrain_chunks[Vector2i(1, 1)].mesh), "normal refresh across the second ring leaves no chunk shading seam")
	expect(not world.foam_chunks.is_empty(), "new partial land creates a matching shoreline mesh")
	var flat := true
	for foam in world.foam_chunks.values():
		if foam.mesh:
			for point in foam.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				flat = flat and absf(point.y - (Coast.WATER_HEIGHT + .018)) < .0001
	expect(flat, "all foam sits above the fixed water plane without vertical fighting")
	var conserved := state.snapshot()
	world.animate(state, .2, false, false, -1)
	world.sync(state)
	expect(state.snapshot() == conserved and state.remaining_stones() == state.total_generated, "shoreline updates and animation do not generate or consume stones")
	var restored := State.from_snapshot(state.snapshot())
	var loaded := World.new()
	root.add_child(loaded)
	loaded.setup(restored)
	expect(loaded.terrain_chunks.size() == world.terrain_chunks.size() and loaded.foam_chunks.size() == world.foam_chunks.size(), "save readback reconstructs the same terrain and shoreline chunks")
	expect(loaded.water_material != world.water_material and loaded.foam_material != world.foam_material and loaded.foliage_material != world.foliage_material, "each world owns its animated material clocks")
	loaded.queue_free()
	for index in state.sea_indices:
		fill(state, index % state.grid_size, index / state.grid_size)
	world.sync(state)
	var none_inside := true
	for foam in world.foam_chunks.values():
		none_inside = none_inside and not foam.visible and foam.mesh == null
	expect(none_inside and state.won, "joining all sea cells removes every obsolete interior shoreline")
	expect(state.remaining_stones() == state.total_generated, "completed visual continent conserves the complete stone total")
	world.queue_free()
	await process_frame
	var game = load("res://scenes/art/coast_preview.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	await process_frame
	expect(not game.save_enabled and not game.selection_pending and game.state.target_stones == 100000, "F6 sample starts a playable fixed coast without accessing player saves")
	game.show_menu()
	var clock: float = game.world.time
	for frame in range(5):
		await physics_frame
	expect(game.world.time == clock and is_equal_approx(game.world.water_material.get_shader_parameter("wave_time"), clock), "menu pause freezes environmental clocks")
	var previous = weakref(game.world)
	game._modal_action("resume")
	game.choose_world(1000000)
	await game.wait_until_ready()
	await process_frame
	expect(previous.get_ref() == null and game.world.time < .2, "new journey discards old environmental meshes and clocks")
	game.queue_free()
	await process_frame
	var legacy: JWState = Store.load_game("res://tests/fixtures/coast_v2.json")["state"]
	var legacy_snapshot := legacy.snapshot()
	world = World.new()
	root.add_child(world)
	world.setup(legacy)
	expect(legacy.snapshot() == legacy_snapshot and not world.terrain_chunks.is_empty(), "real migrated save restores existing new land without altering progress")
	world.queue_free()
	await process_frame
	expect(State.SAVE_VERSION == 3, "environment art keeps the established save format")
	print("ENVIRONMENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
