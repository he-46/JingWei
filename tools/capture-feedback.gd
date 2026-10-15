extends SceneTree
## Isolated, deterministic captures of real action entry points; never loads player saves.
const State = preload("res://scripts/state.gd")
var game: Node3D
var output := "res://artifacts/art/art06"
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func focus(point: Vector2, zoom: float = .6) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, State.BIRD_HOVER_HEIGHT, point.y)
	game.world.bird_body.velocity = Vector3.ZERO
	game.world.zoom = zoom
	game.world.update_camera(game.state, 1, true)
	game._refresh()

func capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	if error != OK:
		push_error("Capture failed: " + label)
		quit(1)
	captures += 1

func cargo(amount: int) -> void:
	# Stage only resources. Gameplay still settles through the real deposit entry point.
	game.state.total_generated += amount
	game.state.carried += amount

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_size(Vector2i(1440, 900))
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/art/feedback_preview.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.hud.notice_panel.hide()
	focus(game.state.player)
	game.interact()
	game.feedback.advance(.18)
	await capture("gather")
	game.feedback.advance(3)
	focus(Vector2(-1, 3))
	game.deposit_at(Vector2(2, 3))
	game.feedback.advance(.24)
	await capture("flight")
	game.feedback.advance(.4)
	await capture("water")
	game.feedback.advance(3)
	cargo(8)
	game.deposit_at(Vector2(-1, 3))
	game.feedback.advance(.64)
	await capture("land")
	game.feedback.advance(3)
	cargo(128)
	game.deposit_at(Vector2(2, 3))
	game.feedback.advance(.65)
	await capture("formed-land")
	game.feedback.advance(3)
	# Mining progresses only via the game's real tick; preserve every discovery location.
	game._advance_world(5000)
	game._refresh()
	game.feedback.advance(.24)
	for id in game.feedback.relics:
		var slot: Dictionary = game.feedback.relics[id]
		focus(Vector2(slot.point.x, slot.point.z))
		await capture("relic-" + id)
	var mine: Vector2 = game.state.mountain_position(0)
	focus(mine)
	await capture("quarry-completion")
	game.hud.select_tab("relics")
	await capture("artifact-tab")
	DisplayServer.window_set_size(Vector2i(1152, 720))
	root.size = Vector2i(1152, 720)
	await capture("artifact-tab-1152")
	game.toggle_overview()
	await capture("overview")
	game.queue_free()
	await process_frame
	print("FEEDBACK CAPTURES: ", captures)
	quit(0)
