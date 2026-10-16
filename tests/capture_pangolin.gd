extends SceneTree

func _initialize() -> void:
	call_deferred("capture_scene")

func capture_scene() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	await process_frame
	game.choose_world(100000)
	await game.wait_until_ready()
	if "--locked-dialogue" in OS.get_cmdline_user_args():
		game.show_npc_dialogue()
		return
	for trip in range(4):
		game.state.tick(14)
		for index in range(4):
			game.state.pickup_stone(index)
		game.state.player = Vector2(2, 0)
		game.state.deposit(game.state.player)
	game.state.tick(70)
	var point: Vector2 = game.state.npc_position(game.state.pangolin_mountain()) + Vector2(2, 2)
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, 1.45, point.y)
	game.world.update_camera(game.state, 1.0, true)
	game.state.messages.clear()
	game._refresh()
	game.hud.notify("青岚山已开尽。穿山甲正在继续开采下一座山。")
