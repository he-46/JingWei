extends SceneTree

# Controlled idle rendering benchmark. It never reads or writes player saves.
# Run with a real graphics backend and -- --qa; headless timings are not valid.
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
const TARGETS := [100000, 1000000, 10000000, 100000000]
const SEEDS := [10213, 20261014, 314159, 271828]
const VIEWS := ["coast", "mountain", "inland", "deep_sea", "overview"]
var game: Node3D
var seconds := 5.0
var output := "res://artifacts/art/art00-20261014"
var only_target := 0
var only_view := ""
var refresh_clock := 0.0
var simulation_clock := 0.0
var results: Array = []
var driver: Node

class IdleDriver extends Node:
	var harness: SceneTree
	func _physics_process(delta: float) -> void:
		harness.idle_step(delta)

func _initialize() -> void:
	call_deferred("run")

func idle_step(delta: float) -> void:
	if game == null:
		return
	refresh_clock += delta
	simulation_clock += delta
	if simulation_clock >= 0.2:
		game._advance_world(0.2)
		simulation_clock -= 0.2
	if refresh_clock >= 0.15:
		refresh_clock = 0
		refresh_hud()
	game.world.animate(game.state, delta, false, false, game.aimed_cell)

func refresh_hud() -> void:
	var target: Vector2 = game.q_target()
	game.aimed_cell = game.state.cell_at(target) if game.world.point_visible(target) else -1
	game.world.aim_point = target
	game.world.sync(game.state)
	game.hud.update_state(game.state, "基线：固定镜头", game.aimed_cell, target)

func run() -> void:
	if not OS.get_cmdline_user_args().has("--qa") or DisplayServer.get_name() == "headless":
		push_error("Art baseline requires --qa and a real graphics backend.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-out="):
			output = arg.trim_prefix("--baseline-out=")
		elif arg.begins_with("--baseline-seconds="):
			seconds = maxf(1, float(arg.trim_prefix("--baseline-seconds=")))
		elif arg.begins_with("--baseline-target="):
			only_target = int(arg.trim_prefix("--baseline-target="))
		elif arg.begins_with("--baseline-view="):
			only_view = arg.trim_prefix("--baseline-view=")
	if (only_target != 0 and not TARGETS.has(only_target)) or (not only_view.is_empty() and not VIEWS.has(only_view)):
		push_error("Unknown baseline target or view.")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		push_error("Cannot create baseline output directory.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.gui_disable_input = true
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	var metadata := {
		"engine": Engine.get_version_info()["string"],
		"os": OS.get_name(), "os_version": OS.get_version(),
		"processor": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"system_memory": OS.get_memory_info(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"video_driver": RenderingServer.get_current_rendering_driver_name(),
		"viewport": [root.size.x, root.size.y], "window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"vsync": DisplayServer.window_get_vsync_mode(),
		"msaa_3d": root.msaa_3d, "screen_space_aa": root.screen_space_aa,
		"physics_hz": Engine.physics_ticks_per_second,
		"warmup_seconds": 3, "sample_seconds_requested": seconds,
		"workload": "controlled idle; real World/HUD; animation 60 Hz; sync 0.15 s; simulation 0.2 s; no input, sound, saving or combat/throw effects",
		"captured_at_utc": Time.get_datetime_string_from_system(true)
	}
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.set_process_unhandled_input(false)
	game.hud.hide_modal()
	game.selection_pending = false
	game.soundscape.set_muted(true)
	driver = IdleDriver.new()
	driver.harness = self
	root.add_child(driver)
	for index in range(TARGETS.size()):
		var target: int = TARGETS[index]
		if only_target != 0 and only_target != target:
			continue
		for view in VIEWS:
			if not only_view.is_empty() and view != only_view:
				continue
			driver.set_physics_process(false)
			game.world.free()
			var begin := Time.get_ticks_usec()
			game.state = State.new(target, SEEDS[index])
			game.world = World.new()
			game.add_child(game.world)
			game.world.setup(game.state)
			var setup_ms := (Time.get_ticks_usec() - begin) / 1000.0
			configure_view(view)
			refresh_clock = 0
			simulation_clock = 0
			driver.set_physics_process(true)
			var warmup := Time.get_ticks_msec()
			while Time.get_ticks_msec() - warmup < 3000:
				await process_frame
			var samples: Array[float] = []
			var draw_calls: Array[float] = []
			var primitives: Array[float] = []
			var physics_times: Array[float] = []
			var memory_peak := 0.0
			var previous := Time.get_ticks_usec()
			var start := previous
			while Time.get_ticks_usec() - start < int(seconds * 1000000):
				await process_frame
				var now := Time.get_ticks_usec()
				samples.append((now - previous) / 1000.0)
				previous = now
				draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000)
				memory_peak = maxf(memory_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
			var elapsed := (previous - start) / 1000000.0
			var report := {
				"id": "%d-%s" % [target, view], "target": target, "seed": SEEDS[index],
				"view": view, "world_setup_ms": setup_ms,
				"player_xz": [game.state.player.x, game.state.player.y],
				"camera_position": vec(game.world.camera.position),
				"camera_rotation": vec(game.world.camera.rotation_degrees),
				"camera_size": game.world.camera.size, "zoom": game.world.zoom,
				"sample_count": samples.size(), "sample_seconds": elapsed,
				"fps_mean": samples.size() / elapsed, "frame_ms_median": percentile(samples, 0.5),
				"frame_ms_p95": percentile(samples, 0.95), "frame_ms_max": samples.max(),
				"draw_calls_median": percentile(draw_calls, 0.5),
				"render_primitives_monitor_median": percentile(primitives, 0.5),
				"physics_ms_p95": percentile(physics_times, 0.95),
				"engine_static_memory_peak_mib": memory_peak / 1048576.0,
				"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				"frame_ms_raw": samples
			}
			driver.set_physics_process(false)
			# Fixed CPU animation pose; shader TIME is intentionally not frozen.
			game.world.time = 1
			game.world.animate(game.state, 0, false, false, game.aimed_cell)
			await RenderingServer.frame_post_draw
			var path: String = output.path_join(report["id"] + ".png")
			var screenshot := root.get_texture().get_image()
			report["image_size"] = [screenshot.get_width(), screenshot.get_height()]
			if screenshot.save_png(path) != OK:
				push_error("Cannot save baseline screenshot: " + path)
				quit(1)
				return
			report["screenshot"] = report["id"] + ".png"
			results.append(report)
			print("BASELINE %s: %.1f FPS, p95 %.2f ms, %d draws" % [report["id"], report["fps_mean"], report["frame_ms_p95"], report["draw_calls_median"]])
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write baseline results.")
		quit(1)
		return
	file.store_string(JSON.stringify({"metadata": metadata, "cases": results}, "\t"))
	file.close()
	print("BASELINE_COMPLETE ", results.size(), " ", output)
	game.queue_free()
	await process_frame
	quit()

func configure_view(view: String) -> void:
	var state: JWState = game.state
	var point := state.player
	game.world.zoom = 1
	game.world.overview = view == "overview"
	if view == "mountain":
		point = state.npc_position(0) + Vector2(1.4, 1.4)
		game.world.zoom = 0.72
	elif view == "inland":
		# A known resource point gives a repeatable, mountain-free observation point.
		var desired := Vector2(state.map_origin.x * 0.7, -state.map_side * 0.1)
		var chosen := 0
		for i in range(state.stone_positions.size()):
			if state.stone_positions[i].distance_squared_to(desired) < state.stone_positions[chosen].distance_squared_to(desired):
				chosen = i
		point = state.stone_positions[chosen]
	elif view == "deep_sea":
		point = state.cell_center(state.grid_size / 2 * state.grid_size + state.grid_size - 2)
		# Smallest map has a one-column deep band.
		if state.sea_depth[state.cell_at(point)] != 2:
			point = state.cell_center(state.grid_size / 2 * state.grid_size + state.grid_size - 1)
	state.player = point
	game.world.bird_body.position = Vector3(point.x, 1.45, point.y)
	game.world.focus = Vector3(point.x, 0, point.y)
	game.world.update_camera(state, 1, true)
	game.hud.set_overview(game.world.overview)
	game.hud.notification_time = 0
	game.hud.notice_panel.visible = false
	refresh_hud()

func percentile(values: Array[float], fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)]

func vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
