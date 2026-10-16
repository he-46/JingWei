extends SceneTree
## External harness also runs against the preceding shipping PCK with --baseline.
## Balanced completion fixtures; all files confined to a fresh output directory.
const Main = preload("res://scripts/main.gd")
const State = preload("res://scripts/state.gd")
const Store = preload("res://scripts/save_store.gd")
var game: Node3D
var baseline := false
var output := ""
var checks := 0
var failures := 0
var records: Array = []
var observer: Node
var active := false
var last_tick := 0
var frames: Array[float] = []
var loading_frames := 0
var stages: Array[String] = []
var progress := 0.0
var progress_backwards := false
var frozen_state: JWState
var frozen_elapsed := 0.0
var unfrozen := false
var screenshot_taken := false

class Observer extends Node:
	var harness: SceneTree
	func _process(_delta: float) -> void:
		harness.observe()

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + description)

func observe() -> void:
	var tick := Time.get_ticks_usec()
	if active:
		frames.append((tick - last_tick) / 1000.0)
		if not baseline and game != null and game.loading:
			loading_frames += 1
			var value: float = game.hud.loading_bar.value
			progress_backwards = progress_backwards or value < progress
			progress = value
			var stage: String = game.hud.modal_text.text
			if stages.is_empty() or stages.back() != stage:
				stages.append(stage)
			if frozen_state != null:
				unfrozen = unfrozen or frozen_state.elapsed != frozen_elapsed
	last_tick = tick

func begin() -> int:
	await process_frame
	frames.clear()
	stages.clear()
	loading_frames = 0
	progress = 0
	progress_backwards = false
	unfrozen = false
	last_tick = Time.get_ticks_usec()
	active = true
	return last_tick

func ready() -> void:
	if not baseline:
		await game.wait_until_ready()
	await process_frame
	# Keep the observer active through the first completed-world draw. Ending at
	# process_frame would omit renderer/driver work after its last _process sample.
	await process_frame
	active = false
	expect(not progress_backwards and not unfrozen, "loading progress is monotonic and simulation stays frozen")
	if not baseline:
		if game.world == null:
			expect(game.selection_pending and loading_frames >= 1, "initial scale choice needs no disposable 3D world")
		else:
			expect(loading_frames >= 2 and stages.size() >= 2, "real world construction spans observable frames and stages")
		expect(not game.loading and not game.hud.loading_bar.visible and (game.selection_pending or game.world.visible), "complete world or initial choice replaces loading screen")

func record(name: String, target: int, start: int) -> void:
	var sorted := frames.duplicate()
	sorted.sort()
	records.append({"case": name, "target": target, "started_at_ms": start / 1000.0, "wall_ms": (Time.get_ticks_usec() - start) / 1000.0,
		"frame_count": frames.size(), "max_frame_ms": sorted.back() if not sorted.is_empty() else 0,
		"p95_frame_ms": sorted[mini(sorted.size() - 1, floori(sorted.size() * .95))] if not sorted.is_empty() else 0,
		"loading_frames": loading_frames, "stages": stages.duplicate()})

func boot(path: String, name: String, target: int) -> void:
	game = Main.new()
	game.save_path = path
	game.preferences_path = output.path_join("preferences.json")
	game.muted = true
	frozen_state = null
	var start: int = await begin()
	root.add_child(game)
	game.set_physics_process(false)
	await ready()
	game.set_process(false)
	record(name, target, start)

func close() -> void:
	var old: WeakRef = weakref(game.world) if game.world != null else WeakRef.new()
	var effects: WeakRef = weakref(game.feedback) if game.feedback != null else WeakRef.new()
	game.queue_free()
	game = null
	frozen_state = null
	await process_frame
	await process_frame
	expect(old.get_ref() == null and effects.get_ref() == null, "world and effects are released after close")

func write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func capture_loading() -> void:
	if DisplayServer.get_name() == "headless" or baseline or screenshot_taken:
		return
	while game.loading and game.hud.loading_bar.value < 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("loading.png"))
	screenshot_taken = true

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--baseline":
			baseline = true
		if arg.begins_with("--loading-out="):
			output = arg.trim_prefix("--loading-out=")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://artifacts/loading-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	observer = Observer.new()
	observer.harness = self
	root.add_child(observer)
	for profile in State.PROFILES:
		var target: int = profile.target
		var path := output.path_join("journey-%d.json" % target)
		await boot(path, "empty-selector", target)
		expect(game.selection_pending, "empty save opens selector")
		frozen_state = game.state
		frozen_elapsed = game.state.elapsed
		var old: WeakRef = weakref(game.world) if game.world != null else WeakRef.new()
		var start: int = await begin()
		game._modal_action("world_%d" % target)
		if not baseline:
			expect(game.loading and not game.choose_world(100000), "second map request is rejected while loading")
			game._modal_action("resume")
			game._modal_action("world_100000")
			var escape := InputEventAction.new()
			escape.action = "jw_menu"
			escape.pressed = true
			game._unhandled_input(escape)
			expect(game.hud.modal_open, "Escape cannot expose a partial world")
			game.save_game(true)
		await ready()
		record("new-map", target, start)
		expect(old.get_ref() == null and game.state.target_stones == target, "selected map replaces previous scene exactly once")
		expect(Store.load_game(path).state.snapshot() == game.state.snapshot(), "selected map saves complete initial ledger")
		# Inject an explicitly balanced completion fixture outside the measured load.
		game.state.carried = target
		game.state.total_generated = target
		game.state.player = Vector2(2, 0)
		game.state.deposit(Vector2(2, 0))
		game.win_shown = true
		expect(game.state.won and State.from_snapshot(game.state.snapshot()) != null, "completion fixture conserves every stone")
		game.save_game()
		game.save_game()
		var expected: Dictionary = Store.load_game(path).state.snapshot()
		await close()
		await boot(path, "completed-save", target)
		expect(game.state.snapshot() == expected and game.win_shown and not game.hud.modal_open, "completed save restores ledger without replaying victory")
		expect(game.world.terrain_chunks.size() > 0, "filled sea is rebuilt before controls resume")
		await close()
		var backup := FileAccess.get_file_as_bytes(path + ".bak")
		write(path, "{damaged primary fixture")
		await boot(path, "backup-recovery", target)
		expect(game.state.snapshot() == expected and not game.save_blocked, "background read recovers valid backup")
		game.save_game()
		expect(FileAccess.get_file_as_bytes(path + ".bak") == backup, "recovery preserves good backup bytes")
		game.show_menu()
		game._modal_action("reset_confirm")
		game._modal_action("pick_again")
		frozen_state = game.state
		frozen_elapsed = game.state.elapsed
		start = await begin()
		game._modal_action("world_%d" % target)
		await ready()
		record("restart", target, start)
		var archived := false
		for name in DirAccess.get_files_at(output):
			if name.begins_with(path.get_file() + ".before-reset-"):
				archived = archived or FileAccess.get_file_as_bytes(output.path_join(name)) == backup
		expect(archived and game.state.total_delivered == 0, "restart archives full ledger before writing new map")
		await close()
	if not baseline:
		var invalid_path := output.path_join("invalid.json")
		write(invalid_path, "{invalid and no backup")
		await boot(invalid_path, "invalid-save", 100000)
		expect(game.selection_pending and game.save_blocked, "invalid save keeps writes blocked at scale selector")
		game.save_game()
		expect(FileAccess.get_file_as_string(invalid_path) == "{invalid and no backup", "invalid original is never silently replaced")
		game.choose_world(100000)
		await game.wait_until_ready()
		# A directory at the backup destination makes a save fail deterministically.
		DirAccess.make_dir_absolute(invalid_path + ".bak")
		var before: Dictionary = game.state.snapshot()
		game.choosing_again = true
		game.choose_world(1000000)
		await game.wait_until_ready()
		expect(game.state.snapshot() == before and game.hud.modal_open and not game.loading, "failed archive retains original playable world and allows retry")
		# UI review is separate from the measured cases: PNG readback/writes add work.
		game.save_enabled = false
		game.choose_world(100000000)
		await capture_loading()
		await game.wait_until_ready()
		await close()
		var closed_path := output.path_join("close-during-read.json")
		var bytes := FileAccess.get_file_as_bytes(output.path_join("journey-100000000.json"))
		var file := FileAccess.open(closed_path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		game = Main.new()
		game.save_path = closed_path
		game.muted = true
		root.add_child(game)
		await process_frame
		expect(game.loading, "early close fixture reaches real pending load")
		game.save_game()
		game.queue_free()
		game = null
		await process_frame
		await process_frame
		expect(FileAccess.get_file_as_bytes(closed_path) == bytes and not FileAccess.file_exists(closed_path + ".bak"), "closing pending read leaves original bytes intact")
	var report := {"baseline": baseline, "checks": checks, "failures": failures, "engine_elapsed_ms": Time.get_ticks_usec() / 1000.0, "engine": Engine.get_version_info().string,
		"display": DisplayServer.get_name(), "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"records": records, "note": "Independent _process observer measures actual frame intervals, including load work. Controlled balanced fixtures; isolated saves. Includes thread/frame scheduling and diagnostics, not ordinary gameplay FPS or minimum-spec certification."}
	write(output.path_join("loading.json"), JSON.stringify(report, "\t"))
	print("LOADING TESTS: %d checks, %d failures; %s" % [checks, failures, output])
	quit(1 if failures else 0)
