extends SceneTree
## No Main/World preload: timing includes the actual default entry's resource load.
var game: Node3D
var output := ""
var baseline := false
var repeat := false
var checks := 0
var failures := 0
var records: Array = []
var active := false
var intervals: Array[float] = []
var last_tick := 0
var first_waiting_draw := -1
var first_ready_draw := -1
var origin := 0
var observer: Node
var early_close := false
var review := false

class Observer extends Node:
	var harness: SceneTree
	func _process(_delta: float) -> void:
		harness.observe()

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func observe() -> void:
	var tick := Time.get_ticks_usec()
	if active:
		intervals.append((tick - last_tick) / 1000.0)
	last_tick = tick
	if current_scene is Node3D:
		game = current_scene
		game.set_physics_process(false)

func drawn() -> void:
	if not active:
		return
	var scene := current_scene
	var waiting: bool = scene is Control or (game != null and game.loading)
	if first_waiting_draw < 0 and waiting:
		first_waiting_draw = Time.get_ticks_usec() - origin
	if first_ready_draw < 0 and game != null and not game.loading:
		first_ready_draw = Time.get_ticks_usec() - origin

func begin() -> int:
	await process_frame
	intervals.clear()
	last_tick = Time.get_ticks_usec()
	active = true
	return last_tick

func finish(name: String, start: int) -> void:
	await process_frame
	await process_frame
	active = false
	var sorted := intervals.duplicate()
	sorted.sort()
	var item := {"case": name, "wall_ms": (Time.get_ticks_usec() - start) / 1000.0, "frames": intervals.size(),
		"max_frame_ms": sorted.back() if not sorted.is_empty() else 0}
	if not baseline and game != null:
		item.warmup = game.warmup_report.duplicate(true)
	records.append(item)

func wait_game() -> void:
	while game == null or game.loading:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func write(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func run() -> void:
	var save := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--startup-out="):
			output = arg.trim_prefix("--startup-out=")
		if arg == "--baseline":
			baseline = true
		if arg == "--repeat":
			repeat = true
		if arg == "--startup-close":
			early_close = true
		if arg == "--startup-review":
			review = true
		if arg.begins_with("--save-path="):
			save = arg.trim_prefix("--save-path=")
	if save.is_empty():
		push_error("Startup fixtures require an explicit isolated --save-path.")
		quit(1)
		return
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://artifacts/startup-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	# The host runner isolates APPDATA. A normal source test uses explicit user paths.
	if not repeat and FileAccess.file_exists(save):
		push_error("Use a fresh isolated APPDATA; startup test never replaces an existing journey.")
		quit(1)
		return
	observer = Observer.new()
	observer.harness = self
	root.add_child(observer)
	AudioServer.set_bus_mute(0, true)
	RenderingServer.frame_post_draw.connect(drawn)
	origin = await begin()
	var entry: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var scene: Node = entry.instantiate()
	root.add_child(scene)
	current_scene = scene
	if review:
		active = false
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("boot.png"))
		await wait_game()
		root.get_texture().get_image().save_png(output.path_join("picker.png"))
		game._modal_action("world_100000")
		while game.loading and (game.world == null or game.hud.loading_bar.value < 82):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("prepare.png"))
		await wait_game()
		expect(not game.loading and game.world != null, "review captures real startup, selection and preparation screens")
		game.queue_free()
		game = null
		current_scene = null
		await process_frame
		await process_frame
		print("STARTUP TESTS: %d checks, %d failures; separate graphical review" % [checks, failures])
		quit(1 if failures else 0)
		return
	if early_close:
		await process_frame
		expect(current_scene is Control and not FileAccess.file_exists(save), "close reaches resource-loading entry without a placeholder save")
		write("close.json", {"checks": checks, "failures": failures, "phase": "resource-loading"})
		print("STARTUP TESTS: %d checks, %d failures; resource-loading close" % [checks, failures])
		current_scene.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		return
	await wait_game()
	await finish("entry", origin)
	expect(game.save_enabled and game.preferences_enabled, "ordinary entry retains real saving and independent settings")
	if not repeat:
		expect(game.selection_pending and game.hud.modal_open and game.state.elapsed == 0, "first entry opens frozen scale selection")
		expect(not FileAccess.file_exists(save), "scale selection does not write a placeholder journey")
		if not baseline:
			expect(game.world == null and game.feedback == null, "first choice constructs no disposable 3D world or effects")
		var start: int = await begin()
		game._modal_action("world_100000")
		await wait_game()
		await finish("first-world", start)
	else:
		expect(not game.selection_pending and game.state.target_stones == 100000, "second process continues the same isolated journey")
	expect(game.state.elapsed == 0 and game.state.total_generated == 0 and game.state.total_delivered == 0, "preparation never advances simulation or creates stones")
	expect(game.feedback.events.is_empty() and game.feedback.active_counts() == Vector3i.ZERO, "preparation never activates gameplay effects or discoveries")
	if not baseline:
		if DisplayServer.get_name() == "headless":
			expect(game.warmup_report.skipped == "headless", "headless diagnostics never claim to have warmed graphics")
		else:
			expect(game.warmup_report.drawn > 5 and game.warmup_report.drawn == game.warmup_report.samples, "every representative group has actual 3D draw calls")
			expect(not game.warmup_report.session_reused, "each new process performs actual preparation and relies on engine shader cache")
	var before: Dictionary = game.state.snapshot()
	var start: int = await begin()
	var point: Vector3 = game.world.bird_body.position
	game.feedback.set_detail(point, false)
	game.feedback.throw_stone(point, point + Vector3(2, 0, 0), true, true, false, game.soundscape.epoch)
	for kind in ["water", "land", "fill", "mined", "gather"]:
		game.feedback.burst(kind, point)
	for id in ["basket", "feather", "seal"]:
		game.feedback.discover(id, point)
	for frame in range(5):
		await process_frame
	await finish("first-effects", start)
	expect(game.state.snapshot() == before, "presentation-only first-use probe keeps ledger exact")
	# Explicit balanced completion fixture, outside measured first-effect work.
	start = await begin()
	game.state.player = Vector2(2, 0)
	game.world.bird_body.position = Vector3(2, 1.45, 0)
	game.state.carried = game.state.target_stones
	game.state.total_generated += game.state.carried
	game.state.deposit(Vector2(2, 0))
	game.win_shown = true
	game._refresh()
	await finish("first-reclaimed-surface", start)
	var State = load("res://scripts/state.gd")
	expect(game.state.won and State.from_snapshot(game.state.snapshot()) != null, "reclaimed-surface fixture conserves all stones")
	var old: WeakRef = weakref(game.world)
	start = await begin()
	game.show_menu()
	game._modal_action("reset_confirm")
	game._modal_action("pick_again")
	game._modal_action("world_100000")
	await wait_game()
	await finish("second-world", start)
	expect(old.get_ref() == null and game.state.total_delivered == 0, "later map releases the prepared scene without carrying its ledger")
	if not baseline and DisplayServer.get_name() != "headless":
		expect(game.warmup_report.session_reused, "same-session world uses the completed preparation set")
	before = game.state.snapshot()
	game.show_menu()
	game._modal_action("settings")
	start = await begin()
	game.hud.settings_quality.pressed.emit()
	await wait_game()
	await finish("smooth-preparation", start)
	expect(game.state.snapshot() == before and game.world.reduced_detail and game.hud.modal_title.text == "设置", "quality preparation preserves paused settings and exact ledger")
	if not baseline and DisplayServer.get_name() != "headless":
		expect(not game.warmup_report.session_reused and game.warmup_report.drawn == game.warmup_report.samples, "first different-quality preparation is actually drawn")
	game.hud.settings_quality.pressed.emit()
	await wait_game()
	if not baseline and DisplayServer.get_name() != "headless":
		expect(game.warmup_report.session_reused, "returning to prepared quality reuses the session set")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("ready.png"))
	var report := {"checks": checks, "failures": failures, "baseline": baseline, "repeat": repeat,
		"display": DisplayServer.get_name(), "engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "first_waiting_draw_ms": first_waiting_draw / 1000.0,
		"first_ready_draw_ms": first_ready_draw / 1000.0, "records": records,
		"note": "Default-entry resource loading included. Independent real frame observer, first post-draw events, and final world draw. Balanced controlled fixtures, isolated normal save/settings. Same-profile repeated process tests application cache reuse, not a cleared system GPU driver cache. Editor harness explicitly mounts shipping PCK, not release EXE performance."}
	game.queue_free()
	game = null
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	expect(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == 0, "startup and warmup leave no orphan scene nodes")
	report.checks = checks
	report.failures = failures
	write("startup.json", report)
	RenderingServer.frame_post_draw.disconnect(drawn)
	print("STARTUP TESTS: %d checks, %d failures; %s" % [checks, failures, output])
	quit(1 if failures else 0)
