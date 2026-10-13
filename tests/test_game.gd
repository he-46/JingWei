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
	game = load("res://scenes/main.tscn").instantiate()
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
	move_player(game.state.stone_positions[0])
	for action in range(4):
		game.interact()
	expect(game.state.carried == game.state.capacity(), "four E actions fill starter basket")
	var outside_view := Vector2(27, -23)
	expect(not game.world.point_visible(outside_view) and game.deposit_at(outside_view) == 0, "unseen location rejects throw without deleting cargo")
	var distant := Vector2(9, 3)
	expect(game.world.point_visible(distant) and game.state.player.distance_to(distant) > 4.5, "visible point lies beyond old throw radius")
	var cargo: int = game.state.carried
	expect(game.deposit_at(distant) == cargo and game.state.cultivation == cargo, "visible distant throw succeeds")
	expect(not game.world.terrain_chunks.is_empty(), "deposits create terrain chunks")
	for action in range(4):
		game.interact()
	game.toggle_overview()
	expect(game.world.overview and not game.hud.side_panels[0].visible, "overview shows map and hides obstructing sidebars")
	var deep: int = game.state.sea_indices[-1]
	expect(game.world.point_visible(game.state.cell_center(deep)), "overview reveals distant deep sea")
	cargo = game.state.carried
	expect(game.deposit_at(game.state.cell_center(deep)) == cargo and game.state.sea_fill[deep] == cargo, "overview allows deep-sea throws")
	game.toggle_overview()
	move_player(game.state.npc_position(0))
	game.interact()
	expect(game.hud.modal_open and not game.state.mountains[0]["started"], "NPC asks before starting its mine")
	var elapsed: float = game.state.elapsed
	for index in range(3):
		await physics_frame
	expect(game.state.elapsed == elapsed, "dialogue pauses simulation")
	game._modal_action("start_mining")
	expect(game.state.mountains[0]["started"] and not game.hud.modal_open, "dialogue begins specific mountain")
	game.state.tick(100)
	game._refresh()
	await process_frame
	expect(game.state.mountains[0]["settled"] and game.state.artifacts.has("basket"), "live mountain gives stock and relic")
	expect(game.world.mountain_cache[0] == 0 and game.world.pile_cache[0] == 1024 and game.world.mountain_collisions[0].disabled, "settled mountain removes rocks and collision")
	move_player(game.state.pile_position(0))
	for index in range(4):
		game.interact()
	expect(game.state.carried == game.state.capacity(), "mountain stone takes four E collections")
	game.toggle_overview()
	var land_point := Vector2(-2, 2)
	var cultivation: int = game.state.cultivation
	cargo = game.state.carried
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
	for target in [1000000, 10000000, 100000000]:
		game.show_menu()
		game._modal_action("reset_confirm")
		game._modal_action("pick_again")
		game._modal_action("world_%d" % target)
		await process_frame
		expect(game.state.target_stones == target and game.world.mountain_mesh.instance_count == game.state.mountains.size() * 32, "chosen profile allocates batched mountain geometry")
		game.toggle_overview()
		var corners_visible := true
		for index in [0, game.state.grid_size - 1, game.state.grid_size * (game.state.grid_size - 1), game.state.grid_size * game.state.grid_size - 1]:
			corners_visible = corners_visible and game.world.point_visible(game.state.cell_center(index))
		expect(corners_visible, "overview fits all four corners of %d map" % target)
		game.state.pickup_stone(0)
		var point: Vector2 = game.state.cell_center(game.state.sea_indices[-1])
		var screen: Vector2 = game.world.camera.unproject_position(Vector3(point.x, 0.2, point.y))
		var picked: Vector2 = game.mouse_world_point(screen)
		expect(picked.distance_to(point) < 0.001 and game.deposit_at(picked) > 0, "mouse ray reaches large-map far corner")
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
	for index in range(game.state.mountains.size()):
		game.state.begin_mining(index)
	game.state.tick(100000)
	var mine := 0
	while not game.state.won and mine < game.state.mountains.size():
		while game.state.carried < game.state.capacity() and mine < game.state.mountains.size():
			if game.state.pickup_pile(mine) == 0:
				mine += 1
		game.state.deposit(Vector2(2, 0))
		game.state.buy_upgrade("bag")
		game.state.buy_upgrade("mining")
	game._refresh()
	await physics_frame
	await physics_frame
	expect(game.state.won and game.win_shown and game.hud.modal_open, "complete world opens personal wish journal")
	game._modal_action("resume")
	expect(not game.hud.modal_open and game.state.won, "completion permits staying on current coast")
	print("GAME TESTS: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
