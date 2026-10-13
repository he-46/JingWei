extends SceneTree

func _initialize() -> void:
	call_deferred("show_dialogue")

func show_dialogue() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.choose_world(100000)
	game.show_npc_dialogue(0)
