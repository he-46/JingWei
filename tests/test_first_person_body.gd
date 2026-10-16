extends SceneTree
const Main = preload("res://scripts/main.gd")
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
		push_error(message)

func shot(label: String) -> void:
	if review.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(review.path_join(label + ".png"))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			review = arg.trim_prefix("--review-out=")
	if not review.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(review))
	root.size = Vector2i(1152, 720)
	game = Main.new()
	game.skip_scale_picker = true
	game.save_enabled = false
	game.preferences_enabled = false
	game.muted = true
	root.add_child(game)
	await game.wait_until_ready()
	game.set_process(false)
	game.set_physics_process(false)
	game.application_focused = true
	expect(not game.first_person_body.visible, "original view hides local wings")
	game.preferences.first_person = true
	game._apply_preferences()
	var body = game.first_person_body
	expect(body.visible and body.get_parent() == game.world.camera, "first person uses camera-local body")
	game.state.player = Vector2(-1, 0)
	game.world.bird_body.position = Vector3(-1, 1.45, 0)
	game.world.update_camera(game.state, 0, true)
	for fov in [60.0, 75.0, 100.0]:
		game.world.first_person_fov = fov
		game.world.update_camera(game.state, 0, true)
		for fraction in [0.0, .3, 1.0]:
			game.state.carried = int(fraction * game.state.capacity())
			game._refresh()
			body.update_view(true, fraction, true, fov, .1)
			expect(body.cargo.visible == (fraction > 0), "empty/full cargo visibility")
			for wing in body.wings:
				var screen: Vector2 = game.world.camera.unproject_position(wing.global_position)
				var canvas_size: Vector2 = root.get_visible_rect().size
				expect(screen.y > canvas_size.y * .65 and absf(screen.x - canvas_size.x * .5) > canvas_size.x * .1, "wings stay outside central aim across FOV")
		await shot("carry-fov-%d" % fov)
	game.state.carried = 32
	game._process(0)
	var before: int = game.state.carried
	var amount: int = game.deposit_at(Vector2(1, 0))
	expect(amount > 0 and game.state.carried == before - amount, "accepted throw settles once")
	expect(body.action == "throw", "accepted throw starts local gesture")
	game._process(.12)
	expect(not body.cargo.visible, "released stone does not remain in wing")
	await shot("throw")
	var ledger: Dictionary = game.state.snapshot()
	game.hud.modal_open = true
	var frozen: float = body.remaining
	game._process(.3)
	expect(body.remaining == frozen, "pause freezes gesture")
	game.hud.modal_open = false
	game.hud.drawer_open = true
	game._process(.3)
	expect(body.remaining == frozen, "upgrade drawer freezes gesture")
	game.hud.drawer_open = false
	game._process(.6)
	expect(game.state.snapshot() == ledger and body.action.is_empty(), "animation completion never settles resources")
	game.state.carried = 0
	expect(game.deposit_at(Vector2(1, 0)) == 0 and body.action.is_empty(), "rejected throw has no gesture")
	game.state.player = game.state.stone_positions[10] + Vector2(1, 0)
	game.world.bird_body.position = Vector3(game.state.player.x, 1.45, game.state.player.y)
	game.world.update_camera(game.state, 0, true)
	game.interact()
	expect(game.state.carried > 0 and body.action == "gather", "successful E pickup starts gather gesture")
	ledger = game.state.snapshot()
	game._process(.1)
	await shot("gather")
	game._process(.5)
	expect(game.state.snapshot() == ledger, "gather animation does not duplicate stones")
	game.world.overview = true
	game._sync_pointer()
	expect(not body.visible and body.action.is_empty(), "overview clears local gesture")
	game.world.overview = false
	game.toggle_view()
	expect(not body.visible, "switch immediately hides local body")
	game.toggle_view()
	expect(body.visible and body.action.is_empty(), "return does not replay gesture")
	var weak: WeakRef = weakref(body)
	await game.choose_world(1000000)
	await game.wait_until_ready()
	await process_frame
	expect(weak.get_ref() == null and game.first_person_body != body, "new journey frees previous body")
	game.queue_free()
	await process_frame
	await process_frame
	print("FIRST PERSON BODY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
