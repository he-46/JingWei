extends SceneTree
const State = preload("res://scripts/state.gd")
const Store = preload("res://scripts/save_store.gd")
var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func move_player(point: Vector2) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, 1.45, point.y)
	game.world.bird_body.velocity = Vector3.ZERO
	game.world.update_camera(game.state, 1.0, true)

func run() -> void:
	game = load("res://scenes/art/pipeline_preview.tscn" if "--imported-visuals" in OS.get_cmdline_user_args() else "res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	expect(game.selection_pending and game.hud.modal_open, "new journey opens scale picker")
	expect(game.hud.modal_buttons.get_child_count() == 4, "picker has four scale options")
	var before: Vector2 = game.state.player
	Input.action_press("jw_right")
	for index in range(6):
		await physics_frame
	Input.action_release("jw_right")
	expect(game.state.player == before and game.state.elapsed == 0, "selection freezes gameplay")
	game._modal_action("resume")
	expect(game.hud.modal_open, "first picker cannot be dismissed without a choice")
	game._modal_action("world_100000")
	await process_frame
	expect(not game.selection_pending and not game.hud.modal_open and game.state.target_stones == 100000, "selection builds chosen map")
	expect(game.world.camera.current and game.world.bird_body is CharacterBody3D, "play scene has camera and physical bird")
	expect(game.hud.relic_labels.size() == 3 and game.hud.atlas_texture.get_width() == 12, "HUD has relics and compact map texture")
	Input.action_press("jw_right")
	for index in range(12):
		await physics_frame
	Input.action_release("jw_right")
	expect(game.state.player.distance_to(before) > 0.2, "movement input flies across coastline")
	for action in range(4):
		move_player(game.state.stone_positions[action])
		game.interact()
	expect(game.state.carried == game.state.capacity(), "four E collections at different scatters fill starter basket")
	expect(game.state.stone_amounts.slice(0, 4) == [0, 0, 0, 0], "harvested scatter instances are exhausted")
	var outside_view := Vector2(27, -23)
	expect(not game.world.point_visible(outside_view) and game.deposit_at(outside_view) == 0, "unseen location preserves inventory")
	move_player(Vector2(-2.5, 3))
	var distant := Vector2(9, 3)
	var cargo: int = game.state.carried
	expect(game.world.point_visible(distant) and game.deposit_at(distant) == 0 and game.state.carried == cargo, "visible but out-of-range throw is rejected")
	game.throw_forward()
	expect(game.state.total_delivered == cargo and game.state.carried == 0, "Q throws to nearby shoreline within starter range")
	expect(not game.world.terrain_chunks.is_empty(), "deposits create terrain chunks")
	game.state.tick(14)
	for action in range(4):
		move_player(game.state.stone_positions[action])
		game.interact()
	game.toggle_overview()
	expect(game.world.overview and not game.hud.side_panels[0].visible, "overview shows map and hides sidebars")
	var deep: int = game.state.sea_indices[-1]
	var deep_point: Vector2 = game.state.cell_center(deep)
	cargo = game.state.carried
	expect(game.world.point_visible(deep_point) and game.deposit_at(deep_point) == 0 and game.state.carried == cargo, "overview cannot bypass throwing distance")
	move_player(deep_point - Vector2(2, 0))
	expect(game.deposit_at(deep_point) == cargo and game.state.sea_fill[deep] == cargo, "flying near deep sea permits the same throw")
	expect(game.world.fog_layers.size() == 3, "land and sea share layered boundary fog")
	for fog in game.world.fog_layers:
		var bounds: Vector4 = fog.material_override.get_shader_parameter("map_bounds")
		expect(is_equal_approx(bounds.x, game.state.map_origin.x) and is_equal_approx(bounds.z - bounds.x, game.state.map_side), "fog shader uses actual playable boundary")
	game.toggle_overview()
	move_player(game.state.npc_position(0))
	game.interact()
	expect(game.hud.modal_open and not game.state.mountains[0]["started"], "NPC explains the fill threshold before mining unlocks")
	var elapsed: float = game.state.elapsed
	for index in range(3):
		await physics_frame
	expect(game.state.elapsed == elapsed, "dialogue pauses simulation")
	expect(game.hud.modal_text.text.contains("128") and game.hud.modal_buttons.get_child_count() == 1, "locked dialogue shows threshold with no mining bypass")
	game._modal_action("resume")
	for trip in range(2):
		game.state.tick(14)
		for action in range(4):
			move_player(game.state.stone_positions[action])
			game.interact()
		move_player(Vector2(-1, 0))
		game.throw_forward()
	expect(game.state.total_delivered == 128 and game.state.mountains[0]["started"], "real gathering and throwing unlock mining without another dialogue")
	expect(game.world.npc_views.size() == 1, "world contains exactly one pangolin")
	var actor: Node3D = game.world.npc_views[0]["root"]
	game.state.tick(100)
	game._refresh()
	await process_frame
	expect(game.state.mountains[0]["settled"] and game.state.artifacts.has("basket"), "live mountain gives stock and relic")
	expect(game.state.next_mountain() == 1 and game.world.npc_views.size() == 1 and game.world.npc_views[0]["root"] == actor, "same pangolin advances to second mountain")
	var npc_point: Vector2 = game.state.npc_position(1)
	expect(Vector2(actor.position.x, actor.position.z).distance_to(npc_point) < 0.001 and game.state.nearby_mountain(game.state.npc_position(0), 2.1, true) == -1, "NPC interaction moves with its sole actor and leaves no ghost behind")
	expect(game.world.mountain_cache[0] == 0 and game.world.pile_cache[0] == 1024 and game.world.mountain_collisions[0].disabled, "settled mountain removes rocks and collision")
	move_player(game.state.pile_position(0))
	for index in range(4):
		game.interact()
	expect(game.state.carried == game.state.capacity(), "mountain stone takes four E collections")
	var blocked_cargo: int = game.state.carried
	game.throw_forward()
	expect(game.state.carried == blocked_cargo, "starter cannot throw into sea while standing in a quarry")
	game.toggle_overview()
	var land_point := Vector2(-2, 2)
	var cultivation: int = game.state.cultivation
	cargo = game.state.carried
	move_player(land_point - Vector2(1, 0))
	expect(game.deposit_at(land_point) == cargo and game.state.cultivation == cultivation, "land throw has no cultivation reward")
	game.toggle_overview()
	move_player(game.state.cell_center(game.state.cell_at(land_point)))
	for action in range(4):
		game.interact()
	expect(game.state.carried == cargo and game.state.land_piles.is_empty(), "land stock can be recovered in live scene")
	expect(game.state.remaining_stones() == game.state.total_generated, "rendering and controls conserve resources")
	game.show_menu()
	game._modal_action("reset_confirm")
	game._modal_action("pick_again")
	game._modal_action("resume")
	expect(game.state.carried == cargo and not game.hud.modal_open, "cancel scale change keeps current journey")
	# Earn enough cultivation for the first range tier using actual nearby throws.
	for trip in range(4):
		move_player(game.state.pile_position(0))
		for action in range(4):
			game.interact()
		move_player(Vector2(-1, 0))
		game.throw_forward()
	var earlier_range: float = game.state.throw_distance()
	game.hud.upgrade_buttons["throw"].pressed.emit()
	expect(game.state.throw_distance() > earlier_range and game.hud.upgrade_buttons.size() == 4, "HUD range upgrade spends earned cultivation")
	await physics_frame
	await physics_frame
	expect(is_equal_approx(game.world.range_ring.scale.x, game.state.throw_distance()), "range ring follows the upgraded radius")
	var attempts := 0
	while int(game.state.mountains[0]["stock"]) > 0 and attempts < 100:
		move_player(game.state.pile_position(0))
		for action in range(4):
			game.interact()
		move_player(Vector2(-1, 0))
		game.throw_forward()
		attempts += 1
	game.state.tick(30)
	move_player(game.state.pile_position(0))
	game.interact()
	expect(int(game.state.mountains[0]["stock"]) == 0 and game.state.carried == 0 and game.world.pile_cache[0] == 0, "empty quarry disappears and does not yield new stones")
	game.show_npc_dialogue(0)
	expect(game.hud.modal_text.text.contains(game.state.mountain_name(game.state.pangolin_mountain())) and game.hud.modal_buttons.get_child_count() == 1, "dialogue follows the sole worker rather than reopening an empty quarry")
	game._modal_action("resume")
	for target in [1000000, 10000000, 100000000]:
		game.show_menu()
		game._modal_action("reset_confirm")
		game._modal_action("pick_again")
		game._modal_action("world_%d" % target)
		await process_frame
		var rendered := 0
		var different_meshes: Dictionary = {}
		for batch in game.world.mountain_batches:
			rendered += batch.instance_count
			different_meshes[hash(batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])] = true
		expect(game.state.target_stones == target and rendered == game.state.mountains.size() and different_meshes.size() == 5, "five shared mountain meshes cover all generated mountains")
		expect(game.world.npc_views.size() == 1, "larger world still has exactly one pangolin")
		var first_shape: CylinderShape3D = game.world.mountain_collisions[0].shape
		var last_shape: CylinderShape3D = game.world.mountain_collisions[-1].shape
		expect(last_shape.radius > first_shape.radius and last_shape.height > first_shape.height, "collision footprints grow with actual stock")
		expect(game.world.flight_ceiling > last_shape.height + 1, "high flight clears the largest mountain")
		game.toggle_overview()
		var corners_visible := true
		for index in [0, game.state.grid_size - 1, game.state.grid_size * (game.state.grid_size - 1), game.state.grid_size * game.state.grid_size - 1]:
			corners_visible = corners_visible and game.world.point_visible(game.state.cell_center(index))
		expect(corners_visible, "overview fits all four corners of %d map" % target)
		game.state.pickup_stone(0)
		var point: Vector2 = game.state.cell_center(game.state.sea_indices[-1])
		var screen: Vector2 = game.world.camera.unproject_position(Vector3(point.x, 0.2, point.y))
		var picked: Vector2 = game.mouse_world_point(screen)
		expect(picked.distance_to(point) < 0.001 and game.deposit_at(picked) == 0, "far-corner ray is accurate but still out of range")
		move_player(point - Vector2(2, 0))
		expect(game.deposit_at(picked) > 0, "large map target becomes available after moving nearby")
		expect(game.hud.atlas_texture.get_width() == game.state.grid_size and game.world.terrain_chunks.size() <= 4, "large map uses compact atlas and local dirty chunks")
	# Isolated save location verifies restart archival without touching player saves.
	game.save_enabled = true
	game.save_path = "res://artifacts/qa-profile/game-test-%d.json" % Time.get_ticks_usec()
	game.save_game(false)
	expect(Store.load_game(game.save_path)["state"].target_stones == 100000000, "scene saves selected large world")
	game.show_menu()
	game._modal_action("reset_confirm")
	game._modal_action("pick_again")
	game._modal_action("world_100000")
	await process_frame
	expect(Store.load_game(game.save_path)["state"].target_stones == 100000, "confirmed restart saves new scale")
	var archived := false
	var directory := DirAccess.open("res://artifacts/qa-profile")
	for file in directory.get_files():
		if file.begins_with(game.save_path.get_file() + ".before-reset-"):
			archived = Store.load_game("res://artifacts/qa-profile/" + file)["state"].target_stones == 100000000
	expect(archived, "restart archives full previous journey")
	game.save_enabled = false
	for trip in range(4):
		game.state.tick(14)
		for index in range(4):
			game.state.pickup_stone(index)
		game.state.player = Vector2(2, 0)
		game.state.deposit(game.state.player)
	game.state.tick(100000)
	var mine := 0
	while not game.state.won and mine < game.state.mountains.size():
		while game.state.carried < game.state.capacity() and mine < game.state.mountains.size():
			if game.state.pickup_pile(mine) == 0:
				mine += 1
		move_player(Vector2(2, 0))
		game.state.deposit(Vector2(2, 0))
		game.state.buy_upgrade("bag")
		game.state.buy_upgrade("mining")
	game._refresh()
	expect(game.world.npc_views.size() == 1 and game.state.next_mountain() == -1, "one worker remains resting after all mountains finish")
	await physics_frame
	await physics_frame
	expect(game.state.won and game.win_shown and game.hud.modal_open, "complete world opens personal wish journal")
	game._modal_action("resume")
	expect(not game.hud.modal_open and game.state.won, "completion permits staying on current coast")
	print("GAME TESTS: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
