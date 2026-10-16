extends SceneTree
const Main = preload("res://scripts/main.gd")
const Prefs = preload("res://scripts/preferences.gd")
const Coast = preload("res://scripts/visuals/coast_geometry.gd")
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

func place(point: Vector2, height: float = 1.45) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, height, point.y)
	game.world.update_camera(game.state, 0, true)

func aim(point: Vector3) -> void:
	var ray: Vector3 = point - game.world.camera.position
	game.world.look_yaw = atan2(-ray.x, -ray.z)
	game.world.look_pitch = atan2(ray.y, Vector2(ray.x, ray.z).length())
	game.world.update_camera(game.state, 0, true)
	game._refresh()
	game.world.animate(game.state, 0, false, false, game.aimed_cell)

func shot(name: String) -> void:
	if review.is_empty() or DisplayServer.get_name() == "headless":
		return
	game.hud.notice_panel.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(review.path_join(name + ".png"))

func run() -> void:
	if "--qa" in OS.get_cmdline_user_args():
		push_error("Polish persistence tests require isolated paths without --qa.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			review = arg.trim_prefix("--review-out=")
	if not review.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(review))
		root.size = Vector2i(1152, 720)
		DisplayServer.window_set_size(Vector2i(1152, 720))
	var old := Prefs.sanitize({"version": 1, "first_person": true, "view_key": KEY_B})
	expect(old.look_sensitivity == 1 and old.first_person_fov == 75 and old.first_person and old.view_key == KEY_B, "FP-01 settings retain view and key with safe observation defaults")
	for bad in ["fast", INF, NAN, true]:
		var clean := Prefs.sanitize({"version": 1, "look_sensitivity": bad, "first_person_fov": bad})
		expect(clean.look_sensitivity == 1 and clean.first_person_fov == 75, "invalid observation values fall back")
	expect(Prefs.sanitize({"version": 1, "look_sensitivity": -2, "first_person_fov": 1000}).look_sensitivity == .25, "sensitivity is bounded")
	expect(Prefs.sanitize({"version": 1, "look_sensitivity": 30, "first_person_fov": -1}).first_person_fov == 60, "FOV is bounded")
	var folder := "user://fp02/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	game = Main.new()
	game.skip_scale_picker = true
	game.muted = true
	game.save_path = folder.path_join("journey.json")
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.set_process(false)
	game.toggle_view()
	game.save_game()
	var bytes := FileAccess.get_file_as_bytes(game.save_path)
	var ledger: Dictionary = game.state.snapshot()
	game.show_menu()
	game._modal_action("settings")
	game.hud.settings_sensitivity.value = 2
	game.hud.settings_fov.value = 95
	expect(game.preferences.look_sensitivity == 2 and game.world.camera.fov == 95, "real sliders apply sensitivity and perspective FOV immediately")
	expect(game.preferences_dirty, "observation sliders coalesce disk writes")
	game._process(.5)
	var saved := Prefs.load_preferences(game.preferences_path)
	expect(saved.look_sensitivity == 2 and saved.first_person_fov == 95 and not game.preferences_dirty, "debounced observation settings reach independent file")
	expect(game.state.snapshot() == ledger and FileAccess.get_file_as_bytes(game.save_path) == bytes, "observation settings preserve journey memory and file")
	await process_frame
	expect(game.hud.root.get_global_rect().encloses(game.hud.settings_fov.get_global_rect()) and game.hud.root.get_global_rect().encloses(game.hud.modal_buttons.get_child(-1).get_global_rect()), "FOV and back control fit the window")
	await shot("settings")
	game._modal_action("resume")
	game.application_focused = true
	game._sync_pointer()
	if DisplayServer.get_name() != "headless":
		game.world.look_yaw = 0
		game.world.look_pitch = 0
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(20, 10)
		game._input(motion)
		expect(is_equal_approx(game.world.look_yaw, -.1) and is_equal_approx(game.world.look_pitch, -.05), "sensitivity scales actual mouse rotation")
	for target in [100000, 1000000, 10000000, 100000000]:
		game.choose_world(target)
		await game.wait_until_ready()
		for quality in ["standard", "smooth"]:
			game.preferences.quality = quality
			game._apply_preferences()
			expect(game.world.camera.fov == 95 and game.preferences.look_sensitivity == 2, "observation settings persist across scale and quality")
			place(Vector2(-.5, 3))
			for i in range(4):
				game.state.pickup_stone(i)
			aim(Vector3(1.5, .16, 3))
			expect(not game.world.range_ring.visible and not game.world.cell_marker.visible and not game.world.pickup_marker.visible, "first person replaces ground rings with screen feedback")
			expect(game.hud.cell_label.text.contains("距离") and game.hud.cell_label.text.contains("Q 投石"), "reachable aim shows distance and throw control")
			place(Vector2(-2, -5))
			aim(Vector3(5, .16, -5))
			expect(game.hud.cell_label.text.contains("超距") and game.hud.crosshair.get_theme_color("font_color") == Color("d38b79"), "distant aim has explicit range status and color")
			aim(game.world.camera.position + Vector3.UP + Vector3.RIGHT)
			expect(game.aimed_cell < 0 and game.hud.cell_label.text == "瞄准海面或陆地", "sky feedback stays separate from range failure")
			expect(float(game.world.foliage_material.get_shader_parameter("near_view")) == 1, "first-person foliage enables eye clearance")
			game.toggle_overview()
			game.world.animate(game.state, 0, false, false, -1)
			expect(float(game.world.foliage_material.get_shader_parameter("near_view")) == 0 and not game.hud.interaction_hint.visible, "overview clears local foliage and screen interaction state")
			game.toggle_overview()
			game.toggle_view()
			expect(game.world.range_ring.visible and float(game.world.foliage_material.get_shader_parameter("near_view")) == 0, "original view restores its rings and full foliage")
			game.toggle_view()
			# Equal geometry with and without normals; ray optimization cannot change land.
			var full := Coast.cell_triangles(game.state, game.state.land_cols, 1)
			var lean := Coast.cell_triangles(game.state, game.state.land_cols, 1, false)
			expect(full[0].points == lean[0].points and lean[0].normals.is_empty(), "aim geometry matches renderer while avoiding unused normal work")
		var npc: Vector2 = game.state.npc_position(game.state.pangolin_mountain())
		place(npc + Vector2(1.4, 1.4))
		await physics_frame
		aim(Vector3(npc.x, 1.35, npc.y))
		expect(game.hud.interaction_hint.text == "E · 对话" and game.hud.interaction_point.is_finite(), "nearby visible NPC has a precise E prompt")
		expect(not game.world.npc_views[0].label.visible, "first person removes oversized NPC overhead text")
		if target == 100000:
			await shot("pangolin")
		place(npc + Vector2(.8, .8), game.world.flight_ceiling)
		aim(Vector3(npc.x, 1.35, npc.y))
		expect(not game.hud.interaction_point.is_finite() and game.hud.interact_button.disabled, "high flight removes unavailable E prompt")
		place(Vector2(-.5, 3), game.world.flight_ceiling)
		aim(Vector3(5, .16, 3))
		if target == 100000:
			await shot("coast")
			var crown: Vector4 = game.world.tree_canopies[0]
			place(Vector2(crown.x, crown.z), crown.y - .18)
			game.world.look_yaw = -PI / 2
			game.world.look_pitch = 0
			game.world.update_camera(game.state, 0, true)
			game._refresh()
			game.world.animate(game.state, 0, false, false, -1)
			game.world.foliage_material.set_shader_parameter("near_view", 0.0)
			await shot("foliage-solid")
			game.world.foliage_material.set_shader_parameter("near_view", 1.0)
			await shot("foliage-clear")
	game.throw_forward()
	place(game.state.stone_positions[10] + Vector2(1, 0))
	var selected: int = game.state.closest_stone(game.state.player)
	var stone_point: Vector2 = game.state.stone_positions[selected]
	await physics_frame
	aim(Vector3(stone_point.x, .65, stone_point.y))
	expect(game.hud.interaction_hint.text == "E · 拾石" and game.hud.interaction_point.is_finite(), "visible nearby scatter gets its E prompt")
	await shot("stone")
	game.interact()
	expect(game.state.stone_amounts[selected] == 0 and game.state.carried > 0, "hinted stone is the resource collected by E")
	game.hud.toggle_drawer()
	var elapsed: float = game.world.time
	var launch_age: float = game.feedback.flights[0].age
	game._process(.2)
	game._physics_process(.2)
	expect(game.world.time == elapsed and game.feedback.flights[0].age == launch_age, "first-person upgrade drawer pauses simulation and effects together")
	expect(not game.hud.interaction_hint.visible, "released pointer hides world interaction prompt")
	game.hud.toggle_drawer()
	# Eye clearance also scales gather particles, without changing settlement/events.
	game.feedback.set_first_person_view(true, Vector3(0, 1.63, 0))
	game.feedback.set_detail(Vector3.ZERO, false)
	var burst: Dictionary = game.feedback.burst("gather", Vector3(0, .38, 0), Vector3(0, 1.45, 0))
	game.feedback.advance(.40)
	var near_scale: float = burst.chips.get_instance_transform(0).basis.get_scale().length()
	expect(game.feedback.eye_clearance(Vector3(0, 1.45, 0)) == 0 and game.feedback.eye_clearance(Vector3(0, .38, 0)) == 1, "eye clearance preserves ground effects and clears particles at the eye")
	game.feedback.set_first_person_view(false, Vector3.ZERO)
	game.feedback._update_burst(burst)
	if DisplayServer.get_name() != "headless":
		expect(near_scale < burst.chips.get_instance_transform(0).basis.get_scale().length(), "real gather particle geometry shrinks before reaching the eye")
	game.queue_free()
	await process_frame
	await process_frame
	game = Main.new()
	game.muted = true
	game.save_path = folder.path_join("journey.json")
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.set_process(false)
	expect(game.preferences.look_sensitivity == 2 and game.world.camera.fov == 95, "a real new instance restores observation preferences")
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	print("FIRST PERSON POLISH TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
