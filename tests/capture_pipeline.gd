extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Pipeline capture requires --qa and a real graphics backend.")
		quit(1)
		return
	var output := "res://artifacts/art/art01"
	DirAccess.make_dir_recursive_absolute(output)
	var game = load("res://scenes/art/pipeline_preview.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.choose_world(100000)
	await game.wait_until_ready()
	game.world.normal_size = 12
	game.state.pickup_stone(0)
	game._refresh()
	game.world.bird_model.set_motion(true, false)
	game.world.bird_model.advance(0.2, 0.2)
	for view in ["coast", "mountain"]:
		if view == "mountain":
			game.state.player = game.state.npc_position(0) + Vector2(0, 2)
			game.world.bird_body.position = Vector3(game.state.player.x, game.state.BIRD_HOVER_HEIGHT, game.state.player.y)
		game.world.update_camera(game.state, 1, true)
		for frame in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output + "/imported-" + view + ".png")
		if error != OK:
			quit(1)
			return
	print("PIPELINE CAPTURE: two imported model screenshots saved to " + output)
	game.queue_free()
	await process_frame
	quit()
