extends SceneTree
## Deliberate regression fixtures, all saves confined to a fresh artifacts folder.
## Optional screenshots show these fixtures, never claimed as a played-through save.
const State = preload("res://scripts/state.gd")
const Store = preload("res://scripts/save_store.gd")
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0
var game: Node3D
var records: Array = []
var folder := ""
var output := ""

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func boot(path: String) -> void:
	game = Main.new()
	game.save_path = path
	game.muted = true
	root.add_child(game)
	await game.wait_until_ready()
	game.set_process(false)
	game.set_physics_process(false)
	expect(game.save_enabled and game.save_path.begins_with("res://artifacts/"), "normal save/load behavior runs only against isolated fixture files")

func close() -> void:
	game.queue_free()
	await process_frame
	await process_frame

func place(point: Vector2) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, State.BIRD_HOVER_HEIGHT, point.y)
	game.world.bird_body.velocity = Vector3.ZERO
	game.world.update_camera(game.state, 1, true)

func shot(name: String) -> void:
	if output.is_empty():
		return
	game._refresh()
	game.world.animate(game.state, 0, false, false, -1)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func action(name: String) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	game._unhandled_input(event)

func run() -> void:
	if "--qa" in OS.get_cmdline_user_args():
		push_error("Release save/load regression must omit --qa; its saves are explicitly isolated.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			output = arg.trim_prefix("--review-out=")
	if not output.is_empty():
		if DisplayServer.get_name() == "headless":
			push_error("Release screenshots require a real renderer.")
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		DisplayServer.window_set_size(Vector2i(1440, 900))
		root.size = Vector2i(1440, 900)
	folder = "res://artifacts/art/art09-regression/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for profile in State.PROFILES:
		var path := folder.path_join("journey-%d.json" % profile.target)
		await boot(path)
		expect(game.selection_pending and game.hud.modal_open, "missing save opens scale selection")
		game._modal_action("world_%d" % profile.target)
		await game.wait_until_ready()
		expect(game.state.target_stones == profile.target and not game.hud.modal_open and Store.load_game(path).state != null, "each new scale creates and saves its real default world")
		expect(game.world.bird_model.model_scene.resource_path.contains("characters/jingwei.glb") and game.world.npc_views[0].animal.model_scene.resource_path.contains("characters/pangolin.glb") and game.world.mountain_batches.size() == 8, "all four scales use formal actors and full mountain catalog")
		await shot("%d-new-coast" % profile.target)
		if not output.is_empty() and profile.target == 100000:
			var original_point: Vector2 = game.state.player
			place(game.state.npc_position(0) + Vector2(1.4, 1.4))
			game.world.zoom = .72
			game.world.update_camera(game.state, 1, true)
			game.world.sun.shadow_bias = .1
			await shot("shadow-before")
			game.world.sun.shadow_bias = .2
			await shot("shadow-after")
			game.world.zoom = 1
			place(original_point)
		for trip in range(4):
			game.state.tick(14)
			for i in range(4):
				place(game.state.stone_positions[i])
				game.interact()
			place(Vector2(-1, 3))
			expect(game.deposit_at(Vector2(.25, 3)) == 32, "real gather and throw entries deliver a starter bag")
			game.feedback.advance(.5)
		expect(game.state.total_delivered == 128 and game.state.mountains[0].started, "each scale unlocks its single worker at 128")
		game._advance_world(5)
		game._refresh()
		game.save_game(false)
		var saved: Dictionary = game.state.snapshot()
		var primary_bytes := FileAccess.get_file_as_bytes(path)
		expect(Store.load_game(path).state.snapshot() == saved, "partial excavation and cultivation are written without art changing the ledger")
		game.show_menu()
		var clock: float = game.world.time
		game._physics_process(.5)
		game._process(.5)
		expect(game.hud.modal_open and game.state.snapshot() == saved and game.world.time == clock, "pause freezes world, work and visual clock")
		await shot("%d-paused" % profile.target)
		game._modal_action("resume")
		action("jw_mute")
		expect(not game.muted and not game.soundscape.muted, "mute key enables sound")
		action("jw_mute")
		expect(game.muted and game.soundscape.muted, "mute key disables sound and clears pending audio")
		action("jw_overview")
		game.world.animate(game.state, 0, false, false, -1)
		expect(game.world.overview and not game.world.sun.shadow_enabled and game.hud.overview_panel.visible, "overview applies its independent display budget")
		await shot("%d-overview" % profile.target)
		action("jw_overview")
		game.world.animate(game.state, 0, false, false, -1)
		expect(not game.world.overview and game.world.sun.shadow_enabled, "normal camera and shadows return")
		await close()
		await boot(path)
		expect(not game.selection_pending and game.state.snapshot() == saved and FileAccess.get_file_as_bytes(path) == primary_bytes, "normal boot continues exact partial save without silently rewriting it")
		expect(game.feedback.events.is_empty(), "loading partial progress never replays historical effects")
		# Resource-balanced full-sea fixture; separate walkthrough verifies real progression.
		place(Vector2(2, 0))
		var remaining: int = game.state.target_stones - game.state.total_delivered
		game.state.carried = remaining
		game.state.total_generated += remaining
		expect(game.deposit_at(Vector2(2, 0)) == remaining and game.state.won, "all four full-sea fixtures finish through the ordinary deposit entry")
		game._physics_process(.001)
		expect(not game.hud.modal_open and game.feedback.completion_pending(), "victory waits for the final visible flight")
		game.feedback.advance(.49)
		game._physics_process(.001)
		expect(game.hud.modal_open and game.hud.modal_title.text == "填海完成" and not game.feedback.completion_pending(), "victory appears after final landing")
		# Completion now requests a background write. Observe its actual completion
		# before checking disk or destroying this deliberately process-disabled scene.
		var save_deadline := Time.get_ticks_msec() + 10000
		while game.save_worker.busy() and Time.get_ticks_msec() < save_deadline:
			game._poll_save()
			await process_frame
		expect(State.from_snapshot(game.state.snapshot()) != null and Store.load_game(path).state.won, "completed progress remains valid and is saved")
		await shot("%d-completed" % profile.target)
		var completed: Dictionary = game.state.snapshot()
		await close()
		await boot(path)
		expect(game.state.snapshot() == completed and game.win_shown and not game.hud.modal_open, "completed save reopens without replaying victory")
		var completed_bytes := FileAccess.get_file_as_bytes(path)
		game.show_menu()
		game._modal_action("reset_confirm")
		game._modal_action("pick_again")
		game._modal_action("world_%d" % (1000000 if profile.target == 100000 else 100000))
		await game.wait_until_ready()
		var preserved := false
		for name in DirAccess.get_files_at(folder):
			if name.begins_with(path.get_file() + ".before-reset-"):
				preserved = preserved or FileAccess.get_file_as_bytes(folder.path_join(name)) == completed_bytes
		expect(preserved and game.state.total_delivered == 0 and game.state.target_stones != profile.target, "reselecting scale archives the completed journey before making a fresh save")
		records.append({"target": profile.target, "old_delivered": completed.total_delivered, "new_target": game.state.target_stones, "archive_preserved": preserved})
		await close()
	var legacy_path := folder.path_join("legacy.json")
	var legacy_bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/coast_v2.json")
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_buffer(legacy_bytes)
	file.close()
	var migrated: Dictionary = Store.load_game(legacy_path).state.snapshot()
	await boot(legacy_path)
	expect(game.state.snapshot() == migrated and game.state.migrated_from == 2 and not game.selection_pending, "actual normal boot migrates the shipped legacy fixture")
	expect(FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes, "legacy boot retains the original file until a save is requested")
	game.save_game(false)
	expect(FileAccess.get_file_as_bytes(legacy_path + ".bak") == legacy_bytes and Store.load_game(legacy_path).state.snapshot() == migrated, "migration save retains the v2 bytes in its known-good backup")
	await shot("legacy-continued")
	await close()
	file = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string("{intentionally damaged fixture")
	file.close()
	await boot(legacy_path)
	expect(game.state.snapshot() == migrated and not game.save_blocked, "normal boot recovers a damaged primary from the known-good legacy backup")
	game.save_game(false)
	expect(Store.load_game(legacy_path).state.snapshot() == migrated and FileAccess.get_file_as_bytes(legacy_path + ".bak") == legacy_bytes, "recovery repairs the primary without overwriting the valid old backup")
	await close()
	var report_path := "res://artifacts/art/art09-audit"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path))
	file = FileAccess.open(report_path.path_join("release-regression.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "scales": records, "save_fixture_folder": folder,
		"display_server": DisplayServer.get_name(), "capture_output": output,
		"note": "Isolated normal save/load path; controlled regression poses and resource-balanced completion fixtures. No player save accessed."}, "\t"))
	print("RELEASE REGRESSION TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
