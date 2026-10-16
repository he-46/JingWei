extends SceneTree
var output := "res://artifacts/art/art02"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output + "/" + name + ".png") != OK:
		push_error("Could not save review capture: " + name)
		quit(1)

func run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Jingwei review capture requires --qa and a real renderer.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(output)
	var preview = load("res://scenes/art/jingwei_preview.tscn").instantiate()
	root.add_child(preview)
	preview.set_process(false)
	for item in [[0, 0.0, 0.0, 0.1, "hero"], [0, 1.0, 2.8, 0.1, "cargo_full"],
		[0, 0.4, 2.8, 0.1, "cargo_light"], [1, 0.0, 0.0, 0.17, "flight_up"],
		[1, 0.0, 0.0, 0.50, "flight_down"], [4, 0.0, 0.0, 0.21, "gather"],
		[6, 0.0, 0.0, 0.12, "throw_start"], [6, 0.0, 0.0, 0.30, "throw_release"],
		[2, 0.0, 0.0, 0.17, "turn_left"]]:
		preview.bird.set_load(item[1])
		preview.stage = 0 if item[1] == 0 else (1 if item[1] < 0.66 else 2)
		preview.bird.rotation.y = item[2]
		preview.show_clip(item[0])
		preview.bird.advance(item[3], item[3])
		await shot(item[4])
	preview.queue_free()
	await process_frame
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.choose_world(100000)
	await game.wait_until_ready()
	for stage in range(3):
		if stage > 0:
			for index in range(1 if stage == 1 else 3):
				game.state.pickup_stone(index + (1 if stage == 2 else 0))
		game._refresh()
		game.world.time = 0.1
		game.world.animate(game.state, 0, false, false, game.state.cell_at(game.q_target()))
		await shot("game_load_%d" % stage)
	game.world.zoom = 2
	game.world.update_camera(game.state, 1, true)
	await shot("game_far_zoom")
	game.world.zoom = 1
	game.world.update_camera(game.state, 1, true)
	game.choose_world(100000000)
	await game.wait_until_ready()
	game.world.zoom = 2
	game.world.update_camera(game.state, 1, true)
	await shot("game_large_far")
	game.queue_free()
	await process_frame
	print("JINGWEI CAPTURE: 14 poses and game views saved to " + output)
	quit()
