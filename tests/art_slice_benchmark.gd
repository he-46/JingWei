extends SceneTree
## Real wall-clock rendering workload, separate from fixed-step walkthrough captures.
const State = preload("res://scripts/state.gd")
var game: Node3D
var driver: Node
var active_case := ""
var clock := 0.0
var throw_clock := 0.0
var output := "res://artifacts/art/art07-performance"

class Driver extends Node:
	var harness: SceneTree
	func _physics_process(delta: float) -> void:
		harness.step(delta)

func _initialize() -> void:
	call_deferred("run")

func release() -> void:
	for action in ["jw_left", "jw_right", "jw_up", "jw_down", "jw_interact"]:
		Input.action_release(action)

func steer(offset: Vector2) -> void:
	var camera: Camera3D = game.world.camera
	var right := Vector2(camera.global_basis.x.x, camera.global_basis.x.z).normalized()
	var down := Vector2(camera.global_basis.z.x, camera.global_basis.z.z).normalized()
	var direction := offset.normalized()
	var screen := Vector2(direction.dot(right), direction.dot(down))
	for item in [["jw_right", screen.x], ["jw_left", -screen.x], ["jw_down", screen.y], ["jw_up", -screen.y]]:
		if float(item[1]) > .001:
			Input.action_press(item[0], item[1])
		else:
			Input.action_release(item[0])

func step(delta: float) -> void:
	clock += delta
	throw_clock -= delta
	if active_case == "coast-actions":
		var point := Vector2(-2.5, 1 + 2.5 * sin(clock * 1.3))
		steer(point - game.state.player)
		Input.action_press("jw_interact")
		if throw_clock <= 0 and game.state.carried > 0:
			game.throw_forward()
			throw_clock = .6
	elif active_case == "quarry-actions":
		Input.action_press("jw_interact")
		if throw_clock <= 0 and game.state.carried > 0:
			game.deposit_at(game.state.player)
			throw_clock = .6
	elif active_case == "occluded-flight":
		var center: Vector2 = game.state.mountain_position(0)
		var radius: float = game.state.mountain_radius(0) + 1.0
		var point := center + Vector2(cos(clock * .8), sin(clock * .8)) * radius
		steer(point - game.state.player)

func place(point: Vector2) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, State.BIRD_HOVER_HEIGHT, point.y)
	game.world.bird_body.velocity = Vector3.ZERO
	game.world.update_camera(game.state, 1, true)
	game._refresh()

func percentile(values: Array[float], fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)]

func run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless" or "--fixed-fps" in OS.get_cmdline_args():
		push_error("Slice benchmark requires --qa, real graphics and real wall-clock timing.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_size(Vector2i(1440, 900))
	root.size = Vector2i(1440, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	var metadata := {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"os": OS.get_name(), "os_version": OS.get_version(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"video_driver": RenderingServer.get_current_rendering_driver_name(), "msaa_3d": root.msaa_3d,
		"vsync": DisplayServer.window_get_vsync_mode(), "physics_hz": Engine.physics_ticks_per_second,
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"viewport": [root.size.x, root.size.y], "warmup_seconds": 3, "sample_seconds": "coast-actions=16; other cases=8",
		"note": "CPU frame intervals in this desktop session; not GPU time, a release build, long-duration stress or minimum-spec acceptance. Audio muted. Setup excluded; normal main simulation and bounded feedback active."}
	game = load("res://scenes/art/vertical_slice.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	driver = Driver.new()
	driver.harness = self
	driver.process_physics_priority = -100
	root.add_child(driver)
	var cases: Array = []
	for name in ["coast-actions", "quarry-actions", "occluded-flight", "large-overview"]:
		driver.set_physics_process(false)
		release()
		game.choose_world(100000000 if name == "large-overview" else 100000)
		await game.wait_until_ready()
		clock = 0
		throw_clock = 0
		active_case = name
		if name == "quarry-actions":
			# Prepare an actual mined snapshot before timing, via the same state rules.
			for trip in range(4):
				game.state.tick(14)
				for index in range(4):
					game.state.pickup_stone(index)
				game.state.player = Vector2(-1, 3)
				game.state.deposit(Vector2(.25, 3))
			game._advance_world(43)
			place(game.state.mountain_position(0))
		elif name == "occluded-flight":
			place(game.state.mountain_position(0) + Vector2(game.state.mountain_radius(0) + 1, 0))
		elif name == "large-overview":
			game.toggle_overview()
		driver.set_physics_process(true)
		await create_timer(3).timeout
		var sample_seconds := 16 if name == "coast-actions" else 8
		var samples: Array[float] = []
		var draws: Array[float] = []
		var memory_peak := 0.0
		var marked := 0
		var start := Time.get_ticks_usec()
		var previous := start
		var before: Dictionary = game.feedback.events.duplicate()
		while Time.get_ticks_usec() - start < sample_seconds * 1000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - previous) / 1000.0)
			previous = now
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			memory_peak = maxf(memory_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
			marked += int(game.hud.player_locator.visible)
		driver.set_physics_process(false)
		release()
		var events: Dictionary = {}
		for kind in game.feedback.events:
			events[kind] = game.feedback.events[kind] - before.get(kind, 0)
		var result := {"case": name, "target": game.state.target_stones, "seed": game.state.world_seed,
			"frames": samples.size(), "seconds": (previous - start) / 1000000.0,
			"frame_ms_median": percentile(samples, .5), "frame_ms_p95": percentile(samples, .95),
			"frame_ms_max": samples.max(), "draw_calls_median": percentile(draws, .5),
			"engine_static_memory_peak_mib": memory_peak / 1048576.0,
			"locator_visible_frames": marked, "events_during_sample": events,
			"state_valid": State.from_snapshot(game.state.snapshot()) != null, "frame_ms_raw": samples}
		cases.append(result)
		print("SLICE BENCHMARK ", name, " p95=", result.frame_ms_p95, "ms events=", events)
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"metadata": metadata, "cases": cases}, "\t"))
	driver.queue_free()
	game.queue_free()
	await process_frame
	quit(0)
