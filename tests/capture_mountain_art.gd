extends SceneTree
var output := "res://artifacts/art/art04"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output + "/" + name + ".png") != OK:
		push_error("Cannot save mountain review image: " + name)
		quit(1)

func unlock(game: Node3D) -> void:
	for trip in range(4):
		game.state.tick(14)
		for index in range(4):
			game.state.pickup_stone(index)
		game.state.player = Vector2(2, 0)
		game.state.deposit(game.state.player)
	game._refresh()

func frame_mountain(game: Node3D) -> void:
	var point: Vector2 = game.state.mountain_position(0) + Vector2(3, 4)
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, game.state.BIRD_HOVER_HEIGHT, point.y)
	game.world.zoom = 0.72
	game.world.focus = Vector3(point.x, 0, point.y)
	game.world.update_camera(game.state, 1, true)
	game._refresh()
	game.world.animate(game.state, 0.2, false, false, -1)

func run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("Mountain capture requires --qa and a real renderer.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=")
	DirAccess.make_dir_recursive_absolute(output)
	var preview = load("res://scenes/art/mountain_preview.tscn").instantiate()
	root.add_child(preview)
	for index in range(6):
		preview.show_stage(index)
		await shot("stage_%d" % index)
	preview.set_values(1, 0.5)
	await shot("stock_half")
	preview.set_values(1, 0.03)
	await shot("stock_last")
	preview.show_stage(0)
	preview.model_root.rotation.y = 2.4
	await shot("mountain_back")
	preview.queue_free()
	await process_frame
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	game.save_enabled = false
	game.set_physics_process(false)
	game.choose_world(100000)
	await game.wait_until_ready()
	unlock(game)
	for index in range(4):
		if index > 0:
			game._advance_world(float(game.state.mountains[0]["yield"]) * .25 / game.state.mining_rate())
		frame_mountain(game)
		await shot("game_%d" % index)
	game._advance_world(100)
	frame_mountain(game)
	await shot("game_stock")
	# Move already generated stock into the basket only for this disposable review scene.
	game.state.upgrades["bag"] = 10
	while game.state.pickup_pile(0) > 0:
		pass
	game._refresh()
	await shot("game_empty")
	game.world.zoom = 1
	game.world.update_camera(game.state, 1, true)
	await shot("game_normal")
	game.choose_world(100000000)
	await game.wait_until_ready()
	frame_mountain(game)
	await shot("game_large")
	game.toggle_overview()
	await shot("game_overview")
	game.queue_free()
	await process_frame
	print("MOUNTAIN CAPTURE: 18 stage and game views saved to " + output)
	quit()
