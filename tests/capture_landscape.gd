extends SceneTree

func _initialize() -> void:
	call_deferred("show_inland")

func show_inland() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	await process_frame
	game.choose_world(10000000)
	await game.wait_until_ready()
	var point: Vector2 = game.state.npc_position(38)
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, 1.45, point.y)
	game.world.zoom = 1.5
	game.world.update_camera(game.state, 1.0, true)
	game._refresh()
	game.hud.notify("大陆深处：山的储量越多，体积越大。五种山形交错分布。")
