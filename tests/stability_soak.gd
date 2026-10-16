extends SceneTree
## External harness can mount the exact shipping PCK. Never touches player data.
const Main = preload("res://scripts/main.gd")
const State = preload("res://scripts/state.gd")
const Store = preload("res://scripts/save_store.gd")
const Prefs = preload("res://scripts/preferences.gd")
var game: Node3D
var output := ""
var case_seconds := 90.0
var checks := 0
var failures := 0
var boots := 0
var resets := 0
var saves := 0
var recoveries := 0
var gathered := 0
var deposits := 0
var injected := 0
var advanced := 0.0
var dead_worlds: Array[WeakRef] = []
var cases: Array = []
var cleanup: Array = []
var phase := "warmup"
var ledger_path := ""
var collecting := false
var frame_previous := 0
var frame_samples: Array[float] = []

class FrameObserver extends Node:
	var harness: SceneTree
	func _process(_delta: float) -> void:
		harness.sample_frame()

func sample_frame() -> void:
	if not collecting:
		return
	var now := Time.get_ticks_usec()
	if frame_previous > 0:
		frame_samples.append((now - frame_previous) / 1000.0)
	frame_previous = now

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func record(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(output.path_join(path), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()

func ledger_equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not ledger_equal(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for index in range(a.size()):
			if not ledger_equal(a[index], b[index]):
				return false
		return true
	if a is float and b is float:
		# Godot decimal JSON parsing can differ by a few double-precision ULPs.
		# Integer resources are never compared with a tolerance.
		return absf(a - b) <= maxf(1e-12, maxf(absf(a), absf(b)) * 1e-14)
	return a == b

func heartbeat(elapsed: float, target: int, quality: String) -> void:
	record("heartbeat.json", {"pid": OS.get_process_id(), "phase": phase, "target": target, "quality": quality,
		"case_seconds": elapsed, "checks": checks, "failures": failures, "saves": saves, "boots": boots,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "static_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0})

func boot(path: String, target: int, quality: String) -> void:
	ledger_path = path
	game = Main.new()
	game.save_path = path
	game.preferences_path = path.get_base_dir().path_join("preferences.json")
	var preferences := Prefs.DEFAULTS.duplicate()
	preferences.quality = quality
	expect(Prefs.save_preferences(game.preferences_path, preferences) == OK, "isolated preference fixture saved")
	root.add_child(game)
	await game.wait_until_ready()
	if game.selection_pending:
		expect(game.choose_world(target), "new scale selected through ordinary entry")
		await game.wait_until_ready()
	boots += 1
	expect(game.save_enabled and game.preferences_enabled and game.save_path.begins_with(output), "both journey and settings remain isolated")
	expect(game.state.target_stones == target and game.world.reduced_detail == (quality == "smooth"), "boot restores scale and quality")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

func close() -> void:
	Input.action_release("jw_high")
	dead_worlds.append(weakref(game.world))
	dead_worlds.append(weakref(game.feedback))
	root.remove_child(game)
	game.queue_free()
	game = null
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	for reference in dead_worlds:
		expect(reference.get_ref() == null, "old world and feedback are freed after lifecycle change")
	dead_worlds.clear()

func place(point: Vector2) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, State.BIRD_HOVER_HEIGHT, point.y)
	game.world.bird_body.velocity = Vector3.ZERO
	game.world.update_camera(game.state, 1, true)

func gather_action(index: int) -> void:
	if game.state.carried >= game.state.capacity():
		place(Vector2(-1, 3))
		deposits += int(game.deposit_at(Vector2(.25, 3)) > 0)
	else:
		place(game.state.stone_positions[index % game.state.stone_positions.size()])
		var before: int = game.state.carried
		game.interact()
		gathered += int(game.state.carried > before)
		if game.hud.modal_open:
			game._modal_action("resume")

func prepare_reclamation() -> void:
	if game.hud.modal_open:
		game._modal_action("resume")
	place(Vector2(2, 0))
	game.win_shown = true
	var extra: int = game.state.target_stones - game.state.total_delivered - game.state.carried
	if extra > 0:
		game.state.carried += extra
		game.state.total_generated += extra
		injected += extra
	game.deposit_at(Vector2(2, 0))
	# Explicit preparation only, never described as real elapsed play time.
	game._advance_world(43)
	advanced += 43
	game._refresh()
	expect(game.state.won and State.from_snapshot(game.state.snapshot()) != null, "full-sea fixture is resource balanced")

func effect_stress() -> Vector3i:
	var point: Vector3 = game.world.bird_body.position
	for i in range(12):
		game.feedback.throw_stone(point, point + Vector3(2 + i * .08, -.3, 0), true, i % 4 == 0, false, game.soundscape.epoch)
	for i in range(24):
		game.feedback.burst("mined" if i % 2 else "fill", point + Vector3(cos(i) * 2, -.4, sin(i) * 2))
	for id in ["basket", "feather", "seal"]:
		game.feedback.discover(id, point + Vector3(1, .4, 0))
	game.soundscape.play("gather")
	return game.feedback.active_counts()

func save_checkpoint() -> void:
	game.save_game(false)
	saves += 1
	var loaded: Dictionary = Store.load_game(ledger_path)
	if loaded.state == null or not ledger_equal(loaded.state.snapshot(), game.state.snapshot()):
		record("failed-save-memory.json", game.state.snapshot())
		if loaded.state != null:
			record("failed-save-loaded.json", loaded.state.snapshot())
	expect(loaded.state != null and ledger_equal(loaded.state.snapshot(), game.state.snapshot()), "repeated save preserves ledger; tolerance only for floating JSON roundoff")
	expect(game.state.remaining_stones() == game.state.total_generated, "all generated stones remain accounted for")

func reload_checkpoint(target: int, quality: String, corrupt: bool) -> void:
	save_checkpoint()
	# Identical second save makes the previous known-good backup an exact fixture.
	save_checkpoint()
	var snapshot: Dictionary = game.state.snapshot()
	var backup := FileAccess.get_file_as_bytes(ledger_path + ".bak")
	var path := ledger_path
	await close()
	if corrupt:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("{deliberately damaged stability fixture")
		file.close()
		expect(Store.load_game(path).status == "recovered", "damaged primary selects valid backup")
		recoveries += 1
	await boot(path, target, quality)
	expect(ledger_equal(game.state.snapshot(), snapshot) and not game.selection_pending and not game.save_blocked, "ordinary boot continues saved or recovered ledger")
	if corrupt:
		save_checkpoint()
		expect(FileAccess.get_file_as_bytes(path + ".bak") == backup, "recovery repairs primary without destroying known-good backup")

func reset_scale(target: int) -> void:
	var old: WeakRef = weakref(game.world)
	var feedback: WeakRef = weakref(game.feedback)
	game.show_menu()
	game._modal_action("reset_confirm")
	game._modal_action("pick_again")
	game._modal_action("world_%d" % target)
	await game.wait_until_ready()
	resets += 1
	expect(game.state.target_stones == target and game.state.total_delivered == 0, "real restart creates requested fresh journey")
	await process_frame
	await process_frame
	expect(old.get_ref() == null and feedback.get_ref() == null, "restart releases old map and bounded effect pools")

func distribution(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var slow := 0
	for sample in samples:
		slow += int(sample > 33.334)
	return {"frames": samples.size(), "p50_ms": sorted[clampi(ceili(sorted.size() * .5) - 1, 0, sorted.size() - 1)],
		"p95_ms": sorted[clampi(ceili(sorted.size() * .95) - 1, 0, sorted.size() - 1)],
		"p99_ms": sorted[clampi(ceili(sorted.size() * .99) - 1, 0, sorted.size() - 1)], "max_ms": sorted.back(), "over_33ms": slow}

func run_case(target: int, quality: String) -> void:
	phase = "timed-case"
	var path := output.path_join("journeys/%d-%s/coast.json" % [target, quality])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	await boot(path, target, quality)
	await process_frame
	var samples: Array[float] = []
	var operations: Array = []
	var flags: Dictionary = {}
	var peak := Vector3i.ZERO
	var action_at := 0.0
	var effect_at := 0.0
	var save_at := 2.0
	var beat_at := 0.0
	var action := 0
	var pause_snapshot: Dictionary = {}
	var pause_clock := 0.0
	var start := Time.get_ticks_usec()
	var unix_start := Time.get_unix_time_from_system()
	frame_samples = samples
	frame_previous = 0
	collecting = true
	# Expensive setup must not make a short preflight silently omit later stages.
	while (Time.get_ticks_usec() - start) / 1000000.0 < case_seconds or flags.size() < 7:
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := (now - start) / 1000000.0
		var fraction := elapsed / case_seconds
		var operation_start := Time.get_ticks_usec()
		var operation := ""
		if fraction < .2 and elapsed >= action_at:
			gather_action(action)
			action += 1
			action_at = elapsed + .3
		if fraction >= .2 and not flags.has("pause"):
			game.show_menu()
			pause_snapshot = game.state.snapshot()
			pause_clock = game.world.time
			flags.pause = true
		if fraction >= .23 and not flags.has("resume"):
			expect(game.state.snapshot() == pause_snapshot and game.world.time == pause_clock, "real pause freezes resources, work and visual clock")
			pause_snapshot.clear()
			game._modal_action("resume")
			flags.resume = true
		if fraction >= .25 and not flags.has("fixture"):
			prepare_reclamation()
			flags.fixture = true
			operation = "balanced full-sea preparation + 43s mining advance"
		if fraction >= .4 and not flags.has("reload"):
			var samples_before := samples.size()
			await reload_checkpoint(target, quality, false)
			expect(samples.size() >= samples_before + 2, "independent observer records frames while lifecycle harness awaits")
			flags.reload = true
			operation = "save + free + normal reload"
		if fraction >= .5 and not flags.has("overview"):
			game.toggle_overview()
			flags.overview = true
		if fraction >= .6 and not flags.has("recover"):
			game.toggle_overview()
			await reload_checkpoint(target, quality, true)
			flags.recover = true
			operation = "corrupt primary + backup recovery + reload"
		if fraction >= .75 and not flags.has("reset"):
			await reset_scale(1000000 if target == 100000 else 100000)
			await reset_scale(target)
			flags.reset = true
			place(game.state.npc_position(game.state.mountains.size() - 1))
			operation = "archive + two real scale resets"
		if operation != "":
			operations.append({"name": operation, "milliseconds": (Time.get_ticks_usec() - operation_start) / 1000.0})
		if not game.hud.modal_open and fraction > .25 and elapsed >= effect_at:
			var counts := effect_stress()
			peak = Vector3i(maxi(peak.x, counts.x), maxi(peak.y, counts.y), maxi(peak.z, counts.z))
			effect_at = elapsed + .2
			if int(elapsed) % 8 < 3:
				Input.action_press("jw_high")
			else:
				Input.action_release("jw_high")
		if elapsed >= save_at:
			save_checkpoint()
			save_at = elapsed + 2
		if elapsed >= beat_at:
			heartbeat(elapsed, target, quality)
			beat_at = elapsed + 1
	save_checkpoint()
	await process_frame
	collecting = false
	frame_samples = []
	expect(flags.size() == 7 and peak == Vector3i(12, 24, 3), "all lifecycle stages and full bounded effect pools were exercised")
	if case_seconds >= 30:
		expect(samples.size() >= case_seconds * 20, "enough real rendered frames exist; suspended process time is not sufficient")
	var duration := (Time.get_ticks_usec() - start) / 1000000.0
	var result := {"target": target, "quality": quality, "actual_seconds": duration, "unix_start": unix_start, "unix_end": Time.get_unix_time_from_system(), "frames": distribution(samples),
		"operations": operations, "stages": flags.keys(), "pool_peak": [peak.x, peak.y, peak.z], "state_valid": State.from_snapshot(game.state.snapshot()) != null,
		"static_mib_before_cleanup": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0}
	cases.append(result)
	record("frames-%d-%s.json" % [target, quality], {"frame_ms": samples})
	await close()
	cleanup.append({"target": target, "quality": quality, "static_mib": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)})
	print("SOAK CASE ", target, " ", quality, " seconds=", duration, " p95=", result.frames.p95_ms, "ms cleanup=", cleanup.back())
	record("partial-results.json", {"cases": cases, "cleanup": cleanup, "checks": checks, "failures": failures})

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=").replace("\\", "/")
		if arg.begins_with("--case-seconds="):
			case_seconds = float(arg.trim_prefix("--case-seconds="))
	if output.is_empty() or not output.contains("/artifacts/") or case_seconds < 2 or case_seconds > 600 or DisplayServer.get_name() == "headless" or Engine.time_scale != 1 or "--fixed-fps" in OS.get_cmdline_args() or "--qa" in OS.get_cmdline_user_args():
		push_error("Soak requires isolated artifacts output, real renderer/time, 2..600 seconds per case and normal save/load (omit --qa).")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var pid := FileAccess.open(output.path_join("process-id.txt"), FileAccess.WRITE)
	pid.store_string(str(OS.get_process_id()))
	pid.close()
	DisplayServer.window_set_size(Vector2i(1440, 900))
	root.size = Vector2i(1440, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	OS.low_processor_usage_mode = false
	var observer := FrameObserver.new()
	observer.harness = self
	observer.process_priority = -1000
	root.add_child(observer)
	var start := Time.get_ticks_usec()
	expect(not ledger_equal({"stone": 100000000}, {"stone": 100000001}), "integer resources never use numeric tolerance")
	expect(ledger_equal(22.399999999999974, 22.399999999999977) and not ledger_equal(1.0, 1.000001), "only tiny floating JSON roundoff is accepted")
	var metadata := {"process_id": OS.get_process_id(), "engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(), "os": OS.get_version(), "window": [1440, 900],
		"case_seconds_requested": case_seconds, "case_count": 8, "frame_cap": 60, "time_scale": Engine.time_scale,
		"harness": "editor executable mounts shipping PCK; not release EXE performance", "audio": "voice scheduling active; only process Master bus muted",
		"frame_sampler": "independent per-frame Node, including frames during harness coroutine waits",
		"fixture": "teleport gather/throw; balanced full-sea resource injection; 43 simulated seconds mining preparation per case; effects never alter ledger"}
	for target in [100000, 1000000, 10000000, 100000000]:
		var path := output.path_join("warmup/%d/coast.json" % target)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		await boot(path, target, "standard")
		prepare_reclamation()
		effect_stress()
		await process_frame
		await close()
	var warmup_end := Time.get_ticks_usec()
	metadata.warmup_seconds = (warmup_end - start) / 1000000.0
	metadata.cleanup_baseline_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	metadata.cleanup_baseline_orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	metadata.cleanup_baseline_static_mib = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	for target in [100000, 1000000, 10000000, 100000000]:
		for quality in ["standard", "smooth"]:
			await run_case(target, quality)
	for item in cleanup:
		expect(item.nodes == metadata.cleanup_baseline_nodes and item.orphans == metadata.cleanup_baseline_orphans, "no node/orphan accumulation at equivalent empty checkpoints")
	phase = "complete"
	var report := {"metadata": metadata, "cases": cases, "cleanup": cleanup, "checks": checks, "failures": failures,
		"session_seconds": (Time.get_ticks_usec() - start) / 1000000.0, "timed_seconds": (Time.get_ticks_usec() - warmup_end) / 1000000.0,
		"boots": boots, "resets": resets, "explicit_saves": saves, "corrupt_primary_recoveries": recoveries,
		"gather_actions": gathered, "deposits": deposits, "injected_stones": injected, "fixture_advanced_simulated_seconds": advanced}
	record("results.json", report)
	heartbeat(0, 0, "complete")
	print("STABILITY SOAK TESTS: %d checks, %d failures" % [checks, failures])
	observer.queue_free()
	await process_frame
	quit(1 if failures else 0)
