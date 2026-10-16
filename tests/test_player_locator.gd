extends SceneTree
const State = preload("res://scripts/state.gd")
const Store = preload("res://scripts/save_store.gd")
var game: Node3D
var checks := 0
var failures := 0
var output := ""
var views: Array = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func frame_at(point: Vector2, zoom: float = 1.0, high: bool = false) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, game.world.flight_ceiling if high else State.BIRD_HOVER_HEIGHT, point.y)
	game.world.zoom = zoom
	game.world.update_camera(game.state, 1, true)
	game._refresh()
	game.hud.notification_time = 0
	game.hud.notice_panel.hide()
	game.world.animate(game.state, 0, false, high, game.aimed_cell)
	await physics_frame
	await physics_frame
	game.world.locator_clock = 0
	var screen: Vector2 = game.world.update_player_locator(.1)
	game.hud.locate_player(screen, game.world.player_obscured)
	await process_frame
	await process_frame

func shot(label: String) -> void:
	if output.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	expect(image.save_png(output.path_join(label + ".png")) == OK, "review image saved: " + label)
	views.append({"view": label, "image_size": [image.get_width(), image.get_height()],
		"player": [game.state.player.x, game.state.player.y], "height": game.world.bird_body.position.y,
		"zoom": game.world.zoom, "camera_size": game.world.camera.size,
		"camera_position": str(game.world.camera.position), "camera_rotation": str(game.world.camera.rotation_degrees),
		"obscured": game.world.player_obscured, "locator_visible": game.hud.player_locator.visible})

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=")
	if not output.is_empty():
		if DisplayServer.get_name() == "headless":
			push_error("Review capture requires a real renderer.")
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		DisplayServer.window_set_size(Vector2i(1440, 900))
		root.size = Vector2i(1440, 900)
	var path := "res://artifacts/qa-profile/art07-protected-save.json"
	var stored := State.new(1000000)
	expect(Store.save_game(path, stored) == OK, "isolated player-save sentinel prepared")
	var original := FileAccess.get_file_as_string(path)
	game = load("res://scenes/art/vertical_slice.tscn").instantiate()
	game.save_path = path
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.set_process(false)
	await process_frame
	expect(game.state.target_stones == 100000 and not game.save_enabled, "sample ignores an existing valid million-stone player save")
	game.save_game(true)
	game.choose_world(100000)
	await game.wait_until_ready()
	expect(FileAccess.get_file_as_string(path) == original, "sample save and restart leave protected journey byte-for-byte unchanged")
	expect(game.world.tree_canopies.size() <= 200 and not game.world.tree_canopies.is_empty(), "CPU canopy data is bounded and available even without GPU transform readback")
	await frame_at(Vector2(-2.5, 3))
	expect(not game.world.player_obscured and not game.hud.player_locator.visible, "clear coast has no permanent location badge")
	expect(game.hud.player_locator.mouse_filter == Control.MOUSE_FILTER_IGNORE, "location badge never intercepts mouse throws")
	await shot("coast-normal")
	game.hud.toggle_drawer()
	expect(not game.hud.drawer.visible, "sample can clear the sidebar without losing action controls")
	await shot("coast-ui-collapsed")
	game.hud.toggle_drawer()
	await frame_at(game.state.npc_position(0) + Vector2(1.4, 1.4), .72)
	await shot("mountain-normal")
	var behind: Vector2 = game.state.mountain_position(0) - Vector2(16, 27).normalized() * (game.state.mountain_radius(0) + .45)
	await frame_at(behind)
	expect(game.world.player_obscured and game.hud.player_locator.visible, "real mountain collision obscures the player and enables screen-space badge")
	var snapshot: Dictionary = game.state.snapshot()
	game.world.player_occluded()
	expect(game.state.snapshot() == snapshot, "occlusion query changes no resources, collision or saved state")
	game.hud.player_locator.hide()
	await shot("mountain-obscured-without-cue")
	game.hud.locate_player(game.world.update_player_locator(0), true)
	await shot("mountain-obscured-with-cue")
	game.show_menu()
	expect(not game.hud.player_locator.visible, "pause immediately hides auxiliary cue")
	game._modal_action("resume")
	await frame_at(behind, 1, true)
	expect(not game.world.player_obscured and not game.hud.player_locator.visible, "high flight above the mountain clears occlusion cue")
	await shot("high-flight")
	var tree: Vector4 = game.world.tree_canopies[0]
	for candidate in game.world.tree_canopies:
		if Vector2(candidate.x, candidate.z).distance_to(Vector2(-2.5, 3)) < Vector2(tree.x, tree.z).distance_to(Vector2(-2.5, 3)):
			tree = candidate
	var tree_point := Vector2(tree.x, tree.z) - Vector2(16, 27).normalized() * 1.15
	await frame_at(tree_point)
	expect(game.world.player_occluded(), "instanced canopy can be detected without adding tree physics bodies")
	await shot("tree-obscured")
	await frame_at(Vector2(-2.5, 3), 2)
	await shot("coast-distant")
	game.toggle_overview()
	game.world.animate(game.state, 0, false, false, -1)
	expect(not game.world.player_occluded() and not game.hud.player_locator.visible and game.world.overview_marker.visible, "overview uses its existing position marker instead of a second badge")
	await shot("overview")
	game.toggle_overview()
	if not output.is_empty():
		DisplayServer.window_set_size(Vector2i(1152, 720))
		root.size = Vector2i(1152, 720)
	await frame_at(Vector2(-2.5, 3))
	await shot("coast-1152")
	var bounds: Rect2 = game.hud.root.get_global_rect()
	expect(bounds.encloses(game.hud.interact_button.get_global_rect()) and bounds.encloses(game.hud.throw_button.get_global_rect()), "small-window action controls remain within the UI canvas")
	await frame_at(behind)
	expect(game.hud.player_locator.position.is_equal_approx(game.world.camera.unproject_position(game.world.bird_body.global_position + Vector3.UP * .15)), "small-window badge follows the actual projected player position")
	await shot("obscured-1152")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var scale := Vector2(image.get_size()) / root.get_visible_rect().size
		var point: Vector2 = (game.hud.player_locator.position + Vector2(4, 0)) * scale
		var actual := image.get_pixelv(Vector2i(point.round()))
		expect(Vector3(actual.r, actual.g, actual.b).distance_to(Vector3(.953, .831, .569)) < .08, "real rendered small-window badge has gold pixels at the projected position")
		await frame_at(Vector2(5, 22))
		await shot("boundary-water")
		await RenderingServer.frame_post_draw
		var with_fog := root.get_texture().get_image()
		for layer in game.world.fog_layers:
			layer.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var without_fog := root.get_texture().get_image()
		for layer in game.world.fog_layers:
			layer.show()
		for item in [[Vector3(5, .16, 23.5), true], [Vector3(5, .16, 28), false]]:
			var pixel: Vector2 = game.world.camera.unproject_position(item[0]) * scale
			var a := with_fog.get_pixelv(Vector2i(pixel.round()))
			var b := without_fog.get_pixelv(Vector2i(pixel.round()))
			var difference := Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))
			expect(difference < .03 if item[1] else difference > .2, "rendered fog preserves reachable water and obscures unreachable water: " + str(item[1]))
	game.choose_world(100000)
	await game.wait_until_ready()
	expect(not game.hud.player_locator.visible and game.world.locator_clock == 0, "new map clears obsolete occlusion result and marker")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("views.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"seed": 10213, "note": "Controlled review poses only; resource-cycle walkthrough is recorded separately.", "views": views}, "\t"))
	game.queue_free()
	await process_frame
	print("PLAYER LOCATOR TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
