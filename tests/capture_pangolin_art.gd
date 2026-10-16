extends SceneTree
var output := "res://artifacts/art/art03"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output + "/" + name + ".png") != OK:
		push_error("Cannot save pangolin review image: " + name)
		quit(1)

func frame_worker(game: Node3D) -> void:
	var point: Vector2 = game.state.npc_position(game.state.pangolin_mountain()) + Vector2(3, 3)
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, game.state.BIRD_HOVER_HEIGHT, point.y)
	game.world.zoom = 0.72
	game.world.update_camera(game.state, 1, true)
	game._refresh()

func unlock(game: Node3D) -> void:
	for trip in range(4):
		game.state.tick(14)
		for index in range(4):
			game.state.pickup_stone(index)
		game.state.player = Vector2(2, 0)
		game.state.deposit(game.state.player)
	game._refresh()

func run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Pangolin capture requires --qa and a real renderer.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(output)
	var preview = load("res://scenes/art/pangolin_preview.tscn").instantiate()
	root.add_child(preview)
	preview.set_process(false)
	for item in [[0, 0.10, 0.0, "hero"], [1, 0.55, 0.0, "locked"],
		[2, 0.20, 0.0, "walk"], [3, 0.23, 0.0, "dig_left"],
		[3, 0.68, 0.0, "dig_right"], [4, 0.35, 0.0, "complete"],
		[5, 0.25, 0.0, "finished"], [0, 0.1, 2.8, "back"]]:
		preview.animal.rotation.y = item[2]
		preview.show_clip(item[0])
		preview.animal.advance(item[1], item[1])
		await shot(item[3])
	preview.queue_free()
	await process_frame
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.choose_world(100000)
	await game.wait_until_ready()
	frame_worker(game)
	game.world.animate(game.state, 0.2, false, false, -1)
	await shot("game_locked")
	unlock(game)
	game._advance_world(4)
	frame_worker(game)
	game.world.animate(game.state, 0.23, false, false, -1)
	await shot("game_dig")
	game._advance_world(50)
	frame_worker(game)
	game.world.animate(game.state, 1.3, false, false, -1)
	await shot("game_next")
	game.world.zoom = 1
	game.world.update_camera(game.state, 1, true)
	await shot("game_normal")
	game._advance_world(100000)
	frame_worker(game)
	game.world.animate(game.state, 1.3, false, false, -1)
	await shot("game_finished")
	game.choose_world(100000000)
	await game.wait_until_ready()
	unlock(game)
	frame_worker(game)
	game.world.animate(game.state, 0.23, false, false, -1)
	await shot("game_large")
	game.queue_free()
	await process_frame
	print("PANGOLIN CAPTURE: 14 poses and game views saved to " + output)
	quit()
