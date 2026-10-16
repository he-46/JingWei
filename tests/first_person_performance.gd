extends SceneTree
## Scripted camera route, real renderer/time. No fixed FPS or accelerated clock.
const Main = preload("res://scripts/main.gd")
var output := ""
var seconds := 8.0
var baseline := false
var game: Node3D
var cases: Array = []
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func write(name: String, value: Dictionary) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()

func stats(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	return {"count": sorted.size(), "median": sorted[sorted.size() / 2], "p95": sorted[mini(sorted.size() - 1, ceili(sorted.size() * .95) - 1)], "p99": sorted[mini(sorted.size() - 1, ceili(sorted.size() * .99) - 1)], "max": sorted.back()}

func pose(t: float) -> void:
	var phase := t / seconds * TAU
	var point := Vector2(-4 + sin(phase) * 3, cos(phase * .5) * game.state.map_side * .08)
	var height: float = lerpf(1.45, game.world.flight_ceiling, (1 - cos(phase)) * .5)
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, height, point.y)
	game.world.look_yaw = -PI / 2 + sin(phase) * 2.2
	game.world.look_pitch = -.3 + cos(phase * 2) * .5
	game.world.update_camera(game.state, 0, true)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fp-out="):
			output = arg.trim_prefix("--fp-out=")
		if arg.begins_with("--case-seconds="):
			seconds = clampf(float(arg.trim_prefix("--case-seconds=")), 3, 60)
		if arg == "--baseline":
			baseline = true
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Performance capture requires a real window and an explicit isolated output path.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_size(Vector2i(1440, 900))
	root.size = Vector2i(1440, 900)
	write("process.json", {"pid": OS.get_process_id(), "renderer": RenderingServer.get_video_adapter_name()})
	game = Main.new()
	game.save_enabled = false
	game.skip_scale_picker = true
	game.muted = true
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.set_process(false)
	game.preferences.first_person = true
	var total_start := Time.get_ticks_usec()
	for target in [100000, 1000000, 10000000, 100000000]:
		for quality in ["standard", "smooth"]:
			game.choose_world(target)
			await game.wait_until_ready()
			game.preferences.quality = quality
			game._apply_preferences()
			game.application_focused = true
			game.hud.hide_modal()
			pose(0)
			game._refresh()
			# Exclude map construction and the initial draw from steady route samples.
			await create_timer(.75).timeout
			var frames: Array[float] = []
			var refreshes: Array[float] = []
			var calls: Array[float] = []
			var start := Time.get_ticks_usec()
			var previous := start
			var refresh_clock := 0.0
			var effect_clock := 2.0
			var generated: int = game.state.total_generated
			var delivered: int = game.state.total_delivered
			var static_peak := 0.0
			write("heartbeat.json", {"target": target, "quality": quality})
			while (Time.get_ticks_usec() - start) / 1000000.0 < seconds:
				await process_frame
				var now := Time.get_ticks_usec()
				var delta := (now - previous) / 1000000.0
				frames.append(delta * 1000)
				previous = now
				pose((now - start) / 1000000.0)
				refresh_clock += delta
				if refresh_clock >= .15:
					var job := Time.get_ticks_usec()
					game._refresh()
					refreshes.append((Time.get_ticks_usec() - job) / 1000.0)
					refresh_clock = 0
				game.world.animate(game.state, delta, true, true, game.aimed_cell)
				game.feedback.set_detail(game.world.bird_body.position, false)
				if not baseline:
					game.feedback.set_first_person_view(true, game.world.camera.global_position)
				effect_clock += delta
				if effect_clock >= 2:
					var begin: Vector3 = game.world.camera.position - game.world.camera.basis.z * .7 - Vector3.UP * .2
					game.feedback.throw_stone(begin, Vector3(2, .25, game.state.player.y), true, false, false, game.soundscape.epoch, false)
					effect_clock = 0
				game.feedback.advance(delta)
				static_peak = maxf(static_peak, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
				calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			var duration := (Time.get_ticks_usec() - start) / 1000000.0
			expect(duration >= seconds and frames.size() > 20 and not refreshes.is_empty(), "real-time route collected frames")
			expect(game.world.first_person and game.world.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "route stays in first person")
			expect(game.state.total_generated == generated and game.state.total_delivered == delivered, "presentation route creates no resources")
			cases.append({"target": target, "quality": quality, "duration_seconds": duration, "frame_ms": stats(frames), "refresh_cpu_ms": stats(refreshes), "draw_calls": stats(calls), "static_peak_mib": static_peak})
			print("FP_CASE ", target, " ", quality, " seconds=", duration)
	var total_seconds := (Time.get_ticks_usec() - total_start) / 1000000.0
	game.queue_free()
	await process_frame
	await process_frame
	expect(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0, "route leaves no orphan nodes")
	write("performance.json", {"engine": Engine.get_version_info().string, "baseline": baseline, "resolution": [1440, 900], "route_seconds_per_case": seconds, "total_wall_seconds_including_loading": total_seconds, "renderer": RenderingServer.get_video_adapter_name(), "checks": checks, "failures": failures, "cases": cases, "scope": "scripted first-person camera route and visual effects; excludes loading from case statistics; no resource injection, human input or long soak"})
	await create_timer(.1).timeout
	print("FIRST PERSON PERFORMANCE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
