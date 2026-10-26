extends SceneTree
const Main = preload("res://scripts/main.gd")
const State = preload("res://scripts/state.gd")
const Store = preload("res://scripts/save_store.gd")
const Worker = preload("res://scripts/save_worker.gd")
var checks := 0
var failures := 0
var game: Node3D
var output := "user://qa05-%d" % Time.get_ticks_usec()
var records: Array = []

class SlowWorker extends "res://scripts/save_worker.gd":
	func start(path: String, snapshot: Dictionary) -> Error:
		if busy():
			return ERR_BUSY
		thread = Thread.new()
		return thread.start(func() -> Error:
			OS.delay_msec(300)
			return Store.save_snapshot(path, snapshot))

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func drain() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while game.saves.worker.busy() and Time.get_ticks_msec() < deadline:
		game._poll_save()
		await process_frame
	expect(not game.saves.worker.busy(), "save finishes within test deadline")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autosave-out="):
			output = arg.trim_prefix("--autosave-out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = Main.new()
	game.save_enabled = false
	game.preferences_enabled = false
	game.skip_scale_picker = true
	game.muted = true
	root.add_child(game)
	await game.wait_until_ready()
	game.set_process(false)
	game.set_physics_process(false)
	game.save_enabled = true
	for target in [100000, 1000000, 10000000, 100000000]:
		game.state = State.new(target)
		game.save_path = output.path_join("journey-%d.json" % target)
		var stamp := Time.get_ticks_usec()
		game.request_autosave()
		var request_ms := (Time.get_ticks_usec() - stamp) / 1000.0
		expect(game.saves.worker.busy(), "request owns a background worker")
		var frozen: Dictionary = game.state.snapshot()
		game.state.elapsed += 1
		await drain()
		expect(Store.load_game(game.save_path).state.snapshot() == frozen, "worker owns a detached immutable snapshot")
		stamp = Time.get_ticks_usec()
		expect(Store.save_game(game.save_path + ".reference", game.state) == OK, "synchronous comparison saves valid data")
		records.append({"target": target, "request_main_ms": request_ms, "synchronous_main_ms": (Time.get_ticks_usec() - stamp) / 1000.0})
	game.saves.worker = SlowWorker.new()
	game.request_autosave()
	game.state.elapsed += 7
	for i in range(20):
		game.request_autosave()
	expect(game.saves.pending, "repeated requests coalesce while IO is delayed")
	var frames := 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 150:
		frames += 1
		await process_frame
	expect(frames > 1 and game.saves.worker.busy(), "main loop continues during simulated slow disk")
	await drain()
	expect(Store.load_game(game.save_path).state.snapshot() == game.state.snapshot(), "coalesced request saves latest state")
	expect(Store._read(game.save_path + ".bak") != null, "previous valid generation remains readable")
	game.request_autosave()
	game.state.elapsed += 2
	game.request_autosave()
	expect(game.save_game(true), "explicit save waits for pending automatic write")
	expect(not game.saves.worker.busy() and not game.saves.pending and Store.load_game(game.save_path).state.snapshot() == game.state.snapshot(), "manual durability barrier saves latest state without a later stale write")
	game.saves.worker = Worker.new()
	var primary := FileAccess.get_file_as_bytes(game.save_path)
	var backup := FileAccess.get_file_as_bytes(game.save_path + ".bak")
	DirAccess.make_dir_absolute(game.save_path + ".tmp")
	game.request_autosave()
	await drain()
	expect(game.save_failed and game.hud.save_label.text.contains("失败"), "write failure is reported")
	expect(FileAccess.get_file_as_bytes(game.save_path) == primary and FileAccess.get_file_as_bytes(game.save_path + ".bak") == backup, "failed temporary write preserves both generations")
	game._notification(Main.NOTIFICATION_WM_CLOSE_REQUEST)
	expect(game.hud.modal_open and game.hud.modal_title.text == "退出前保存失败", "failed exit save keeps game open with retry choice")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("save-failed.png"))
	game._modal_action("resume")
	DirAccess.remove_absolute(game.save_path + ".tmp")
	DirAccess.make_dir_absolute(game.save_path + ".bak.tmp")
	game.request_autosave()
	await drain()
	expect(game.save_failed and FileAccess.get_file_as_bytes(game.save_path + ".bak") == backup, "backup staging failure preserves old backup")
	DirAccess.remove_absolute(game.save_path + ".bak.tmp")
	game.state.elapsed += 3
	game.request_autosave()
	await drain()
	expect(not game.save_failed and Store.load_game(game.save_path).state.snapshot() == game.state.snapshot(), "automatic retry recovers after filesystem becomes writable")
	var file := FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string("{damaged fixture")
	file.close()
	expect(Store.load_game(game.save_path).status == "recovered", "damaged primary falls back to known-good backup")
	backup = FileAccess.get_file_as_bytes(game.save_path + ".bak")
	expect(game.save_game(true) and FileAccess.get_file_as_bytes(game.save_path + ".bak") == backup, "repair retains known-good backup")
	game.saves.worker = SlowWorker.new()
	game.request_autosave()
	game.choosing_again = true
	game.choose_world(100000)
	await game.wait_until_ready()
	expect(Store.load_game(game.save_path).state.target_stones == 100000 and not game.saves.worker.busy(), "new map waits for old writer before replacing save")
	game.queue_free()
	await process_frame
	await process_frame
	file = FileAccess.open(output.path_join("autosave.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "timings": records, "slow_disk_fixture_ms": 300, "responsive_frames": frames, "note": "Single local run. Snapshot copy remains on main thread; timings are not frame percentiles. Slow disk is a test-only delay."}, "\t"))
	file.close()
	print("AUTOSAVE TESTS: %d checks, %d failures; %s" % [checks, failures, output])
	quit(1 if failures else 0)
