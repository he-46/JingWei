extends SceneTree
const State = preload("res://scripts/state.gd")
var output := "res://artifacts/art/art05"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output + "/" + name + ".png") != OK:
		push_error("Cannot save environment review: " + name)
		quit(1)

func frame_at(game: Node3D, point: Vector2, zoom: float = 1.0) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, State.BIRD_HOVER_HEIGHT, point.y)
	game.world.zoom = zoom
	game.world.focus = Vector3(point.x, 0, point.y)
	game.world.update_camera(game.state, 1, true)
	game._refresh()
	game.world.animate(game.state, .3, false, false, -1)

func fill(state: JWState, index: int, fraction: float) -> void:
	# Isolated review: generate an exact amount and settle through the normal rule API.
	var amount := roundi(state.sea_capacity[index] * fraction) - state.sea_fill[index]
	if amount <= 0:
		return
	state.player = state.cell_center(index)
	state.carried = amount
	state.total_generated += amount
	state.deposit(state.player)

func run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Environment capture requires --qa and a real renderer.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(output)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.choose_world(100000)
	frame_at(game, Vector2(-2.5, 3))
	await shot("coast")
	frame_at(game, Vector2(-2.5, 3), .6)
	await shot("coast_close")
	frame_at(game, game.state.npc_position(0) + Vector2(1.4, 1.4), .72)
	await shot("mountain")
	for item in [[Vector2(9, 0), "shallow"], [Vector2(18, 0), "far"], [Vector2(26, 0), "deep"]]:
		frame_at(game, item[0])
		await shot(item[1])
	for row in range(5, 10):
		for col in range(5, 9):
			fill(game.state, row * 12 + col, 1.0)
		fill(game.state, row * 12 + 9, .55)
	frame_at(game, Vector2(8, 8), .75)
	await shot("filled_adjacent")
	frame_at(game, Vector2(12, 8), .6)
	await shot("chunk_seam")
	game.toggle_overview()
	await shot("filled_overview")
	game.toggle_overview()
	frame_at(game, Vector2(game.state.map_origin.x + 1, game.state.map_origin.y + 1))
	await shot("fog_corner")
	game.choose_world(100000000)
	frame_at(game, Vector2(-2.5, 3))
	await shot("large_coast")
	game.toggle_overview()
	await shot("large_overview")
	game.queue_free()
	await process_frame
	print("ENVIRONMENT CAPTURE: 12 views saved to " + output)
	quit()
