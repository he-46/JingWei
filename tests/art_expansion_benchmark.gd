extends "res://tests/art_slice_benchmark.gd"
## Synthetic stress preparation is excluded from timing. Gameplay still runs
## normally during samples. The separate walkthrough tests real progression.
var viewport: SubViewport
var effect_clock := 0.0
var stress := false

class ProfileGame extends "res://scripts/visuals/vertical_slice.gd":
	var last_process_ms := 0.0
	var last_physics_ms := 0.0
	var physics_serial := 0
	func _process(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._process(delta)
		last_process_ms = (Time.get_ticks_usec() - start) / 1000.0
	func _physics_process(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._physics_process(delta)
		last_physics_ms = (Time.get_ticks_usec() - start) / 1000.0
		physics_serial += 1

func step(delta: float) -> void:
	if not stress:
		super.step(delta)
		return
	effect_clock -= delta
	if effect_clock > 0:
		return
	effect_clock = .08
	var origin: Vector3 = game.world.bird_body.position
	for i in range(12):
		game.feedback.throw_stone(origin, origin + Vector3(2 + i * .08, -.4, 0), true, i % 4 == 0, false, -1)
	for i in range(24):
		game.feedback.burst("mined" if i % 2 else "fill", origin + Vector3(cos(i) * 3, -.4, sin(i) * 3))
	for id in ["basket", "feather", "seal"]:
		game.feedback.discover(id, origin + Vector3(1.5, .5, 0))

func prepare_sea() -> void:
	# Full reclamation fixture via deposit; generated stones are explicitly balanced.
	game.state.player = Vector2(2, 0)
	game.state.carried = game.state.target_stones
	game.state.total_generated += game.state.carried
	game.state.deposit(game.state.player)
	game.win_shown = true
	game._refresh()

func dense_point() -> Vector2:
	var best := 0
	var best_count := 0
	for i in range(game.state.mountains.size()):
		var count := 0
		for j in range(game.state.mountains.size()):
			if game.state.mountain_position(i).distance_to(game.state.mountain_position(j)) < game.world.normal_size * 1.3:
				count += 1
		if count > best_count:
			best_count = count
			best = i
	return game.state.npc_position(best)

func run() -> void:
	if not "--qa" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless" or "--fixed-fps" in OS.get_cmdline_args():
		push_error("Expansion benchmark requires --qa, real graphics and wall-clock timing.")
		quit(1)
		return
	output = "res://artifacts/art/art08-performance"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_size(Vector2i(1440, 810))
	root.size = Vector2i(1440, 810)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	# Desktop window is smaller than 1080p; measure a real 1920x1080 render target,
	# with a scaled preview. Report the extra preview cost rather than claiming a
	# native 1080p desktop window or a direct comparison with ART-07's 1440x900.
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.msaa_3d = root.msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.size = Vector2(1440, 810)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(preview)
	game = ProfileGame.new()
	viewport.add_child(game)
	await game.wait_until_ready()
	game.muted = true
	game.soundscape.set_muted(true)
	driver = Driver.new()
	driver.harness = self
	driver.process_physics_priority = -100
	root.add_child(driver)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var metadata := {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(), "os": OS.get_name(), "os_version": OS.get_version(),
		"process_id": OS.get_process_id(),
		"rendering_method": RenderingServer.get_current_rendering_method(), "video_driver": RenderingServer.get_current_rendering_driver_name(),
		"msaa_3d": viewport.msaa_3d, "vsync": DisplayServer.window_get_vsync_mode(), "physics_hz": Engine.physics_ticks_per_second,
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "render_target": [viewport.size.x, viewport.size.y],
		"warmup_seconds": 2, "sample_seconds": 6, "seed": 10213,
		"note": "Real 1920x1080 SubViewport, plus scaled 1440x810 desktop preview. Uncapped Compatibility 2x MSAA. Synthetic fixtures before timing; normal simulation/HUD/feedback during timing. Screenshots and map creation excluded. Short-session measurements; not a minimum-spec or release-build claim."}
	var cases: Array = []
	var process_file := FileAccess.open(output.path_join("process-id.txt"), FileAccess.WRITE)
	process_file.store_string(str(OS.get_process_id()))
	process_file.close()
	for profile in State.PROFILES:
		for name in ["coast-actions", "full-reclamation", "dense-mountains", "concentrated-effects", "overview"]:
			driver.set_physics_process(false)
			release()
			stress = false
			var setup_start := Time.get_ticks_usec()
			game.choose_world(profile.target)
			await game.wait_until_ready()
			await process_frame
			var map_setup_ms := (Time.get_ticks_usec() - setup_start) / 1000.0
			clock = 0
			throw_clock = 0
			effect_clock = 0
			active_case = name
			if name in ["full-reclamation", "overview"]:
				prepare_sea()
				place(Vector2(game.state.map_side * .25, 0))
			if name == "dense-mountains":
				place(dense_point())
				game.world.zoom = 2
				game.world.update_camera(game.state, 1, true)
			if name == "concentrated-effects":
				prepare_sea()
				game.state.tick(game.state.target_stones * .25)
				game._refresh()
				place(game.state.mountain_position(0))
				stress = true
			if name == "overview":
				game.toggle_overview()
			var fixture_setup_ms := (Time.get_ticks_usec() - setup_start) / 1000.0
			driver.set_physics_process(true)
			await create_timer(2).timeout
			await RenderingServer.frame_post_draw
			var picture := viewport.get_texture().get_image()
			if picture.get_size() != Vector2i(1920, 1080):
				push_error("Actual render target is not 1080p")
				quit(1)
				return
			picture.save_jpg(output.path_join("%d-%s.jpg" % [profile.target, name]), .88)
			await create_timer(.25).timeout
			var samples: Array[float] = []
			var draws: Array[float] = []
			var triangles: Array[float] = []
			var cpu: Array[float] = []
			var physics: Array[float] = []
			var gpu: Array[float] = []
			var render_cpu: Array[float] = []
			var memory_peak := 0.0
			var video_peak := 0.0
			var pool_peak := Vector3i.ZERO
			var before: Dictionary = game.feedback.events.duplicate()
			var physics_serial: int = game.physics_serial
			var unix_start := Time.get_unix_time_from_system()
			var start := Time.get_ticks_usec()
			var previous := start
			while Time.get_ticks_usec() - start < 6000000:
				await process_frame
				var now := Time.get_ticks_usec()
				samples.append((now - previous) / 1000.0)
				previous = now
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				triangles.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				cpu.append(game.last_process_ms)
				if game.physics_serial != physics_serial:
					physics.append(game.last_physics_ms)
					physics_serial = game.physics_serial
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
				render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()))
				memory_peak = maxf(memory_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
				video_peak = maxf(video_peak, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
				var counts: Vector3i = game.feedback.active_counts()
				pool_peak = Vector3i(maxi(pool_peak.x, counts.x), maxi(pool_peak.y, counts.y), maxi(pool_peak.z, counts.z))
			driver.set_physics_process(false)
			release()
			var events: Dictionary = {}
			for kind in game.feedback.events:
				events[kind] = game.feedback.events[kind] - before.get(kind, 0)
			var valid := State.from_snapshot(game.state.snapshot()) != null
			var result := {"case": name, "target": game.state.target_stones, "frames": samples.size(), "seconds": (previous - start) / 1000000.0,
				"unix_start": unix_start, "unix_end": Time.get_unix_time_from_system(), "frame_ms_median": percentile(samples, .5),
				"frame_ms_p95": percentile(samples, .95), "frame_ms_p99": percentile(samples, .99), "frame_ms_max": samples.max(),
				"over_16_67_ms_percent": samples.filter(func(ms): return ms > 16.667).size() * 100.0 / samples.size(),
				"draw_calls_median": percentile(draws, .5), "triangles_median": percentile(triangles, .5),
				"cpu_process_ms_p95": percentile(cpu, .95), "cpu_physics_ms_p95": percentile(physics, .95),
				"cpu_physics_ms_max": physics.max(), "map_setup_ms": map_setup_ms, "fixture_setup_ms": fixture_setup_ms,
				"render_cpu_ms_p95": percentile(render_cpu, .95), "render_gpu_ms_p95": percentile(gpu, .95),
				"engine_static_memory_peak_mib": memory_peak / 1048576.0, "video_memory_peak_mib": video_peak / 1048576.0,
				"effect_pool_peak": [pool_peak.x, pool_peak.y, pool_peak.z], "events_during_sample": events,
				"state_valid": valid, "frame_ms_raw": samples}
			cases.append(result)
			print("EXPANSION BENCHMARK ", profile.target, " ", name, " p95=", result.frame_ms_p95, "ms valid=", valid)
			var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
			file.store_string(JSON.stringify({"metadata": metadata, "cases": cases}, "\t"))
			if not valid:
				push_error("Invalid benchmark fixture ledger")
				quit(1)
				return
	driver.queue_free()
	game.queue_free()
	await process_frame
	quit(0)
