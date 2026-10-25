extends SceneTree
const Main = preload("res://scripts/main.gd")
const Prefs = preload("res://scripts/preferences.gd")
const Aim = preload("res://scripts/first_person_aim.gd")
var checks := 0
var failures := 0
var game: Node3D
var review := ""

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func key_event(key: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	return event

func place(point: Vector2, height: float = 1.45) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, height, point.y)
	game.world.bird_body.velocity = Vector3.ZERO
	game.world.update_camera(game.state, 1, true)

func aim_at(point: Vector3) -> void:
	var direction: Vector3 = point - game.world.camera.position
	game.world.look_yaw = atan2(-direction.x, -direction.z)
	game.world.look_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	game.world.update_camera(game.state, 1, true)

func shot(name: String) -> void:
	if review.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(review.path_join(name + ".png"))

func run() -> void:
	if "--qa" in OS.get_cmdline_user_args():
		push_error("First-person persistence tests require isolated paths without --qa.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			review = arg.trim_prefix("--review-out=")
	if not review.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(review))
		DisplayServer.window_set_size(Vector2i(1152, 720))
		root.size = Vector2i(1152, 720)
	expect(Prefs.sanitize({"version": 1}).view_key == KEY_V and not Prefs.sanitize({"version": 1}).first_person, "old settings gain safe defaults")
	for key in [KEY_W, KEY_E, KEY_Q, KEY_U, KEY_M, KEY_SPACE, KEY_ESCAPE, KEY_TAB, KEY_F1, KEY_F4, KEY_CTRL]:
		expect(not Prefs.valid_view_key(key), "reserved control cannot be rebound: %d" % key)
	expect(Prefs.sanitize({"version": 1, "view_key": "B", "first_person": "yes"}) == Prefs.DEFAULTS, "wrong view setting types are rejected")
	expect(Prefs.sanitize({"version": 1, "view_key": KEY_Q}).view_key == KEY_V, "conflicting stored key falls back")
	game = Main.new()
	game.save_enabled = false
	game.muted = true
	game.skip_scale_picker = true
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.set_process(false)
	game.application_focused = true
	var ledger: Dictionary = game.state.snapshot()
	game.toggle_view()
	expect(game.world.first_person and game.world.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and not game.world.bird_model.visible, "first person has a perspective camera without its own mesh blocking it")
	expect(game.world.camera.position.distance_to(game.world.bird_body.position) < .3 and game.world.camera.near < .1, "camera follows bird height closely")
	expect(game.state.snapshot() == ledger and not game.hud.drawer_open, "switch does not change resources and clears aiming space")
	if DisplayServer.get_name() != "headless":
		expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and game.hud.crosshair.visible, "real window captures pointer and shows crosshair")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 100000)
	game._input(motion)
	if DisplayServer.get_name() != "headless":
		expect(is_equal_approx(game.world.look_pitch, deg_to_rad(-85)), "look pitch is bounded")
	game.show_menu()
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not game.hud.crosshair.visible, "pause releases mouse and hides crosshair immediately")
	game._modal_action("settings")
	game.hud.settings_view_key.pressed.emit()
	game._input(key_event(KEY_W))
	expect(game.binding_view_key and game.preferences.view_key == KEY_V, "occupied key retains binding prompt without changing movement")
	game._input(key_event(KEY_ESCAPE))
	expect(not game.binding_view_key and game.hud.modal_title.text == "设置", "Escape cancels binding without closing settings")
	game.hud.settings_view_key.pressed.emit()
	game._input(key_event(KEY_B))
	expect(game.preferences.view_key == KEY_B and InputMap.action_get_events("jw_view")[0].physical_keycode == KEY_B, "UI rebind updates actual action")
	expect(not key_event(KEY_V).is_action_pressed("jw_view") and key_event(KEY_B).is_action_pressed("jw_view"), "old key stops switching and new key matches")
	var path := "user://fp01-%d/preferences.json" % OS.get_process_id()
	expect(Prefs.save_preferences(path, game.preferences) == OK and Prefs.load_preferences(path) == game.preferences, "view and binding survive JSON settings roundtrip")
	await shot("settings")
	game._modal_action("resume")
	game.toggle_overview()
	expect(game.world.overview and game.world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Tab temporarily restores overview and mouse")
	game.toggle_overview()
	expect(game.world.first_person and game.world.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "leaving overview returns to first person")
	game.hud.toggle_drawer()
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not game.hud.crosshair.visible, "upgrade drawer allows pointer interaction")
	game.hud.toggle_drawer()
	game._unhandled_input(key_event(KEY_B))
	expect(not game.world.first_person and game.world.bird_model.visible, "rebound physical key returns to original view")
	game._unhandled_input(key_event(KEY_B))
	place(Vector2(-2, 3))
	game.world.look_yaw = 0
	game.world.look_pitch = -.3
	game.world.update_camera(game.state, 1, true)
	Input.action_press("jw_up")
	for frame in range(12):
		await physics_frame
		game._physics_process(1.0 / 60)
	Input.action_release("jw_up")
	expect(game.state.player.y < 2.8 and absf(game.state.player.x + 2) < .03, "W flies toward camera heading without changing altitude")
	for target in [100000, 1000000, 10000000, 100000000]:
		game.choose_world(target)
		await game.wait_until_ready()
		expect(game.world.first_person and game.world.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "new scale preserves view %d" % target)
		for quality in ["standard", "smooth"]:
			if quality == "smooth":
				game.choose_world(target)
				await game.wait_until_ready()
			game.preferences.quality = quality
			game._apply_preferences()
			place(Vector2(-.5, 3))
			aim_at(Vector3(1.5, .16, 3))
			var hit: Variant = game.first_person_target()
			expect(hit != null and hit.distance_to(Vector2(1.5, 3)) < .03, "crosshair intersects visible sea on %d/%s" % [target, quality])
			for index in range(4):
				game.state.pickup_stone(index)
			var cargo: int = game.state.carried
			if quality == "standard":
				game.throw_forward()
			else:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				click.position = Vector2.ZERO # Captured input still uses screen center.
				game._unhandled_input(click)
			expect(game.state.total_delivered > 0 and game.state.carried < cargo and Main.State.from_snapshot(game.state.snapshot()) != null, "crosshair deposits through real resource ledger on %d/%s" % [target, quality])
			# Restore an empty sea cell as the sight line, retaining all resource accounting.
			place(Vector2(-2, -5))
			aim_at(Vector3(5, .16, -5))
			for index in range(4, 8):
				game.state.pickup_stone(index)
			cargo = game.state.carried
			var delivered: int = game.state.total_delivered
			game.throw_forward()
			expect(game.state.carried == cargo and game.state.total_delivered == delivered, "low altitude rejects distant aim %d/%s" % [target, quality])
			place(Vector2(-2, -5), game.world.flight_ceiling)
			aim_at(Vector3(5, .16, -5))
			game.throw_forward()
			expect(game.state.carried < cargo and game.state.total_delivered > delivered, "ascent extends crosshair throw range %d/%s" % [target, quality])
			aim_at(game.world.camera.position + Vector3(1, 1, 0))
			expect(game.first_person_target() == null, "sky has no target %d/%s" % [target, quality])
			if target == 100000 and quality == "standard":
				game.feedback.set_detail(game.world.bird_body.position, false)
				game.feedback.advance(1.5)
				game.world.animate(game.state, 0, false, true, game.aimed_cell)
				aim_at(Vector3(6, .16, -5))
				game._refresh()
				game._sync_pointer()
				await shot("coast-high")
		# Gathering and dialogue retain proximity and altitude constraints.
		place(game.state.stone_positions[10])
		var amount: int = game.state.carried
		game.interact()
		expect(game.state.carried > amount, "nearby E gathers in first person %d" % target)
		var delivered_before: int = game.state.total_delivered
		aim_at(game.world.bird_body.position - Vector3.UP * 2)
		game.throw_forward()
		expect(game.state.carried == 0 and game.state.total_delivered == delivered_before and game.state.closest_drop(game.state.player) >= 0, "aiming down drops recoverable stones without cultivation %d" % target)
		game.interact()
		expect(game.state.carried > 0, "E recovers first-person land throw %d" % target)
		place(game.state.npc_position(game.state.pangolin_mountain()))
		game.interact()
		expect(game.hud.modal_title.text == "穿山甲" and game.hud.modal_open, "E opens pangolin dialogue %d" % target)
		game._modal_action("resume")
		# Mountain body blocks aiming at the ground behind it.
		# The first 1024-stone mound is now genuinely small; use a mountain taller than eye level.
		var mountain: Vector2 = game.state.mountain_position(-1)
		var radius: float = game.state.mountain_radius(-1)
		place(mountain + Vector2(radius + 2, 0))
		await physics_frame
		aim_at(Vector3(mountain.x - radius - 2, .44, mountain.y))
		expect(game.first_person_target() == null, "real mountain blocks crosshair ray %d" % target)
		var snapshot: Dictionary = game.state.snapshot()
		game.toggle_view()
		game.toggle_view()
		expect(game.state.snapshot() == snapshot, "repeated switches preserve ledger %d" % target)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(game.hud.modal_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus loss pauses and releases pointer")
	game.queue_free()
	await process_frame
	await process_frame
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "shutdown releases pointer")
	game = Main.new()
	game.muted = true
	game.save_path = path.get_base_dir().path_join("journey.json")
	game.preferences_path = path
	game.skip_scale_picker = true
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.set_process(false)
	expect(game.preferences.first_person and game.world.first_person and game.preferences.view_key == KEY_B and game.world.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "new game instance restores actual saved view and custom key")
	expect(game.state.total_delivered == 0 and game.state.carried == 0, "device settings do not become journey resources")
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	print("FIRST PERSON TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
