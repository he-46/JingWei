extends SceneTree

func _initialize() -> void:
	call_deferred("capture_ui")

func capture_ui() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	await process_frame
	game.choose_world(100000)
	await game.wait_until_ready()
	var mode := "initial"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui="):
			mode = arg.trim_prefix("--ui=")
	match mode:
		"relics":
			game.hud.select_tab("relics")
		"overview":
			game.toggle_overview()
		"help":
			game.show_help()
		"picker":
			game.hud.show_world_picker()
		"collapsed":
			game.hud.toggle_drawer()
		"late":
			# Display-only boundary fixture; capture mode never writes player saves.
			game.state.upgrades["bag"] = 20
			game.state.upgrades["mining"] = 20
			game.state.carried = game.state.capacity()
			game.state.cultivation = 99999999
			game._refresh()
	game.hud.notification_time = 0
	game.hud.notice_panel.visible = false
	game._refresh()
