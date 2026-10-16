extends SceneTree
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
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

func visible_stones(mesh, start: int = 0, count: int = 32) -> int:
	var visible := 0
	for part in range(start, start + count):
		if mesh.get_instance_transform(part).origin.y > -10:
			visible += 1
	return visible

func expect_visual(condition: bool, description: String) -> void:
	# Dummy headless RenderingServer cannot read back MultiMesh instance transforms.
	# These additional checks run with the actual Compatibility renderer as well.
	if DisplayServer.get_name() != "headless":
		expect(condition, description)

func unlock(state: JWState) -> void:
	for trip in range(4):
		state.tick(14)
		for index in range(4):
			state.pickup_stone(index)
		state.player = Vector2(2, 0)
		state.deposit(state.player)

func run() -> void:
	for name in ["strata_mountain", "quarry_stone", "quarry_site"]:
		var scene: PackedScene = load("res://assets/models/environment/%s.glb" % name)
		var instance := scene.instantiate()
		var objects := instance.find_children("*", "MeshInstance3D", true, false)
		expect(objects.size() == 1 and objects[0].transform.is_equal_approx(Transform3D.IDENTITY), name + " has one normalized mesh and identity transform")
		var mesh: Mesh = objects[0].mesh
		expect(mesh.get_surface_count() == 1, name + " uses one material surface")
		var triangles: int = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
		expect(triangles <= (4000 if name == "strata_mountain" else 300), name + " meets authored triangle budget")
		var arrays: Array = mesh.surface_get_arrays(0)
		expect(arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size(), name + " has UVs for all imported vertices")
		expect(mesh.get_aabb().position.y >= -0.00001, name + " sits on its ground origin")
		if name == "strata_mountain":
			expect(is_equal_approx(mesh.get_aabb().end.y, 1.0), "authored peak matches logical unit height")
			var bounded := true
			for point in arrays[Mesh.ARRAY_VERTEX]:
				bounded = bounded and Vector2(point.x, point.z).length() <= State.MOUNTAIN_COLLISION_RATIO
			expect(bounded, "all authored vertices fit logical footprint and NPC clearance")
		instance.free()
	var texture: Texture2D = load("res://assets/textures/environment/strata_paint.png")
	expect(texture.get_width() == 1024 and texture.get_image().has_mipmaps(), "one 1024-square painted atlas includes mipmaps")
	var preview = load("res://scenes/art/mountain_preview.tscn").instantiate()
	root.add_child(preview)
	for index in range(6):
		preview.show_stage(index)
		expect(preview.visual.stage_name() in ["完整山体", "岩层暴露", "分层开采", "山脚基底", "碎石场", "空山址"], "six art-only stages can be reproduced")
	preview.queue_free()
	await process_frame
	for profile in State.PROFILES:
		var state := State.new(int(profile["target"]), 10213)
		var world := World.new()
		root.add_child(world)
		world.setup(state)
		expect(world.sample_enabled and world.mountain_batches[0].mesh == Visual.imported_mesh(World.SAMPLE_MOUNTAIN), "default world uses sample mesh on every scale")
		expect(world.mountain_collision_groups[0].size() == 8 and world.mountain_collision_groups[1].size() == 8, "every mountain has eight contour slabs")
		expect(world.quarry_mesh.instance_count == state.mountains.size() * 32 and world.mining_dust.instance_count == 8, "all formal quarries and dust instance counts remain bounded")
		var visual = Visual.from_state(state, 0)
		expect(visual.radius < Visual.from_state(state, 5).radius and visual.height < Visual.from_state(state, 5).height, "same authored mountain grows with storage while respecting its plot")
		expect(int(state.mountains[0]["stock"]) == 0 and world.mining_dust.visible_instance_count == 0, "unmined mountain has no stock or working dust")
		expect_visual(visible_stones(world.quarry_mesh) == 0, "renderer hides all unmined stock instances")
		if DisplayServer.get_name() != "headless":
			for decor in [[world.tree_mesh, 2.7], [world.grass_mesh, 0.2]]:
				var avoids := true
				for instance in range(decor[0].instance_count):
					var point: Vector3 = decor[0].get_instance_transform(instance).origin
					if point.y > -10:
						avoids = avoids and state.clear_of_mountains(Vector2(point.x, point.z), decor[1] - .001)
				expect(avoids, "decoration stays outside full mountains and future quarry footprints")
		var safe := true
		for slab in world.mountain_collision_groups[0]:
			safe = safe and slab.position.y + slab.shape.height / 2 + State.BIRD_COLLISION_RADIUS < world.flight_ceiling - State.LAND_HEIGHT
		expect(safe, "maximum flight clears every collision slab")
		world.queue_free()
		await process_frame

	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.choose_world(100000)
	await game.wait_until_ready()
	game.save_enabled = false
	unlock(game.state)
	var full_yield: int = game.state.mountains[0]["yield"]
	var generated: int = game.state.total_generated
	var previous_progress := 0.0
	for progress in [0.0, 0.25, 0.50, 0.75, 0.98, 0.99]:
		game._advance_world((progress - previous_progress) * full_yield / game.state.mining_rate())
		previous_progress = progress
		game._refresh()
		await physics_frame
		await physics_frame
		var visual = Visual.from_state(game.state, 0)
		expect(is_equal_approx(game.world.mountain_ratios[0], 1 - progress), "continuous work refreshes the cut including within one old 32-step interval")
		expect_visual(absf(game.world.mountain_batches[0].get_instance_custom_data(0).r - (1 - progress)) < 0.0005, "renderer receives excavation ratio within Compatibility half-float precision")
		var top := 0.0
		for slab in game.world.mountain_collision_groups[0]:
			if not slab.disabled:
				top = maxf(top, slab.position.y + slab.shape.height / 2)
		expect(is_equal_approx(top, visual.collision_height), "collision top matches the displayed excavation plane")
		expect(game.state.total_generated == generated and game.state.pickup_pile(0) == 0, "work debris never becomes premature resources")
		expect_visual(visible_stones(game.world.quarry_mesh) == 0, "renderer shows no collectible stone groups during mining")
		var loaded := State.from_snapshot(game.state.snapshot())
		var loaded_visual = Visual.from_state(loaded, 0) if loaded else null
		expect(loaded_visual != null and is_equal_approx(loaded_visual.remaining, visual.remaining), "save restores exact partial mountain stage")
		if is_equal_approx(progress, 0.5):
			var point: Vector2 = game.state.mountain_position(0)
			var height: float = State.LAND_HEIGHT + visual.height * 0.5
			var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, height + 2, point.y), Vector3(point.x, State.LAND_HEIGHT, point.y))
			var hit: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(ray)
			expect(not hit.is_empty() and absf(hit["position"].y - height) < 0.002, "real physics ray hits the cut surface, not the old peak")
			var above := PhysicsRayQueryParameters3D.create(Vector3(point.x + visual.radius + .5, height + .4, point.y), Vector3(point.x - visual.radius - .5, height + .4, point.y))
			expect(game.world.get_world_3d().direct_space_state.intersect_ray(above).is_empty(), "flight corridor above the cut is physically clear")
			game.world.animate(game.state, 0.2, false, false, -1)
			var dust_clock: float = game.world.time
			game.show_menu()
			game.set_physics_process(true)
			for frame in range(4):
				await physics_frame
			expect(game.world.time == dust_clock, "menu pause freezes working dust as well as mining")
			game.set_physics_process(false)
			game._modal_action("resume")
	game._advance_world(0.01 * full_yield / game.state.mining_rate() + .001)
	game._refresh()
	await physics_frame
	await physics_frame
	expect(game.state.mountains[0]["settled"] and int(game.state.mountains[0]["stock"]) == full_yield and game.state.total_generated == generated + full_yield, "actual completion produces exactly one finite full reserve")
	expect_visual(visible_stones(game.world.quarry_mesh) == 32 and game.world.mountain_batches[0].get_instance_transform(0).origin.y < -10, "completion replaces the mountain with a full stone field")
	var all_disabled := true
	for slab in game.world.mountain_collision_groups[0]:
		all_disabled = all_disabled and slab.disabled
	expect(all_disabled, "completion disables every sample collision slab")
	var ledger: Dictionary = game.state.snapshot()
	for repeat in range(5):
		game.world.sync(game.state)
		game.world.animate(game.state, .1, false, false, -1)
	expect(game.state.snapshot() == ledger, "replaying and resyncing visual completion cannot duplicate stock")
	game.state.player = game.state.pile_position(0)
	while int(game.state.mountains[0]["stock"]) > full_yield / 2:
		if game.state.pickup_pile(0) == 0:
			game.state.deposit(game.state.player)
	game.world.sync(game.state)
	expect_visual(visible_stones(game.world.quarry_mesh) <= 16 and visible_stones(game.world.quarry_mesh) > 0, "stock depletion reduces the visible stone groups")
	var restored := State.from_snapshot(game.state.snapshot())
	var restored_world := World.new()
	root.add_child(restored_world)
	restored_world.setup(restored)
	expect(restored != null and restored.mountains[0]["stock"] == game.state.mountains[0]["stock"], "readback preserves the depleted stock without granting resources")
	expect_visual(visible_stones(restored_world.quarry_mesh) == visible_stones(game.world.quarry_mesh), "renderer restores the same remaining quarry groups")
	restored_world.queue_free()
	while int(game.state.mountains[0]["stock"]) > 0:
		if game.state.pickup_pile(0) == 0:
			game.state.deposit(game.state.player)
	game.world.sync(game.state)
	expect(game.state.pickup_pile(0) == 0 and game.state.nearby_pile(game.state.player) != 0, "empty site has no pickup or resource prompt")
	expect_visual(visible_stones(game.world.quarry_mesh) == 0, "empty site has no resource meshes")
	expect_visual(is_equal_approx(game.world.quarry_site_mesh.get_instance_transform(0).origin.y, State.LAND_HEIGHT), "empty mountain leaves a persistent noncollectable bedrock site")
	expect(game.state.remaining_stones() == game.state.total_generated, "entire six-stage journey conserves generated stone")
	var old_dust = weakref(game.world.mining_dust)
	var old_world = weakref(game.world)
	game.choose_world(1000000)
	await game.wait_until_ready()
	await process_frame
	expect(old_world.get_ref() == null and old_dust.get_ref() == null and game.world.mining_dust.visible_instance_count == 0, "new map frees old stages and working effects")
	var legacy: JWState = Store.load_game("res://tests/fixtures/coast_v2.json")["state"]
	var legacy_world := World.new()
	root.add_child(legacy_world)
	var legacy_before := legacy.snapshot()
	legacy_world.setup(legacy)
	expect(legacy.snapshot() == legacy_before and legacy_world.sample_enabled, "legacy migrated progress loads with the new sample and no resource changes")
	legacy_world.queue_free()
	game.queue_free()
	await process_frame
	expect(State.SAVE_VERSION == 3, "mountain art preserves existing save format")
	print("MOUNTAIN TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
