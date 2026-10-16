extends SceneTree
const Prefs = preload("res://scripts/preferences.gd")
const Main = preload("res://scripts/main.gd")
const Store = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
var folder := ""
var game: Node3D
var capture_folder := ""

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func boot(enabled: bool = true) -> void:
	game = Main.new()
	game.save_path = folder.path_join("journey.json")
	game.preferences_path = folder.path_join("preferences.json")
	game.save_enabled = enabled
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.set_process(false)
	if game.selection_pending:
		game.choose_world(100000)
		await game.wait_until_ready()

func close() -> void:
	game.queue_free()
	await process_frame
	await process_frame

func shot(name: String) -> void:
	if capture_folder.is_empty():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_folder.path_join(name + ".png"))

func run() -> void:
	if "--qa" in OS.get_cmdline_user_args():
		push_error("Preference persistence tests must omit --qa; all paths are explicitly isolated.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			capture_folder = arg.trim_prefix("--review-out=")
	if not capture_folder.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_folder))
		DisplayServer.window_set_size(Vector2i(1152, 720))
		root.size = Vector2i(1152, 720)
	folder = "user://qa/preferences/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("validation.json")
	expect(Prefs.load_preferences(path) == Prefs.DEFAULTS, "missing preferences use standard, windowed, full volume defaults")
	write(path, "{broken")
	expect(Prefs.load_preferences(path) == Prefs.DEFAULTS, "corrupt preferences do not block boot")
	write(path, JSON.stringify({"version": 99, "quality": "smooth"}))
	expect(Prefs.load_preferences(path) == Prefs.DEFAULTS, "unknown schema does not apply unknown settings")
	write(path, " ".repeat(Prefs.LIMIT + 1))
	expect(Prefs.load_preferences(path) == Prefs.DEFAULTS, "oversized preferences are rejected")
	var clean := Prefs.sanitize({"version": 1, "quality": "unknown", "fullscreen": "true", "muted": 1, "volume": "loud", "mountains": [1]})
	expect(clean == Prefs.DEFAULTS and not clean.has("mountains"), "wrong types and ledger keys never enter preferences")
	expect(Prefs.sanitize({"version": 1, "volume": INF}).volume == 1, "non-finite volume falls back")
	expect(Prefs.sanitize({"version": 1, "volume": -5}).volume == 0 and Prefs.sanitize({"version": 1, "volume": 5}).volume == 1, "volume is bounded")
	var values := Prefs.DEFAULTS.duplicate()
	values.quality = "smooth"
	values.volume = .35
	expect(Prefs.save_preferences(path, values) == OK and Prefs.load_preferences(path) == values, "preference roundtrip persists independently")
	var before := FileAccess.get_file_as_bytes(path)
	values.volume = .8
	expect(Prefs.save_preferences(path, values) == OK and FileAccess.get_file_as_bytes(path + ".bak") == before, "atomic write preserves known-good backup")
	write(path, "{damaged")
	expect(Prefs.load_preferences(path).volume == .35, "damaged primary recovers known-good preference backup")
	expect(Prefs.save_preferences(path, values) == OK and FileAccess.get_file_as_bytes(path + ".bak") == before, "repair never replaces good backup with corrupt bytes")
	await boot()
	var snapshot: Dictionary = game.state.snapshot()
	var save_bytes := FileAccess.get_file_as_bytes(game.save_path)
	game.show_menu()
	expect(game.hud.modal_buttons.get_child_count() == 5, "settings live inside pause menu without a permanent HUD panel")
	game._modal_action("settings")
	expect(game.hud.modal_open and game.hud.modal_title.text == "设置", "pause routes to settings without resuming")
	await shot("settings-standard-1152")
	game.hud.settings_quality.pressed.emit()
	expect(game.preferences.quality == "smooth" and game.world.reduced_detail, "real quality button applies smooth preset")
	expect(not game.world.sun.shadow_enabled and game.world.grass_mesh.visible_instance_count == 0, "smooth disables shadows and decorative grass")
	expect(root.msaa_3d == Viewport.MSAA_DISABLED and is_equal_approx(root.scaling_3d_scale, .75), "smooth changes real viewport settings")
	expect(game.world.tree_canopies.size() > 0 and game.world.mountain_collisions.size() == game.state.mountains.size(), "navigation and collision geometry remain present")
	game.hud.settings_display.pressed.emit()
	expect(game.preferences.fullscreen, "fullscreen button saves fullscreen preference")
	if DisplayServer.get_name() != "headless":
		expect(root.mode == Window.MODE_FULLSCREEN, "real window enters fullscreen")
	game.hud.settings_display.pressed.emit()
	if DisplayServer.get_name() != "headless":
		expect(root.mode == Window.MODE_WINDOWED, "real window returns to windowed mode")
	game.hud.settings_volume.value = 37
	expect(is_equal_approx(game.soundscape.volume_level, .37) and game.hud.settings_volume_label.text.contains("37%"), "real slider updates sound and readable percentage")
	expect(game.preferences_dirty, "slider coalesces writes instead of saving every pointer movement")
	game._process(.5)
	expect(not game.preferences_dirty and is_equal_approx(Prefs.load_preferences(game.preferences_path).volume, .37), "paused process flushes debounced preference write")
	var bus := AudioServer.get_bus_index(game.soundscape.BUS)
	expect(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(.37)), "volume reaches actual game mixer bus")
	var epoch: int = game.soundscape.epoch
	game.hud.settings_volume.value = 0
	expect(AudioServer.is_bus_mute(bus) and game.soundscape.epoch > epoch and not game.soundscape.play("gather"), "zero volume silences bus and invalidates pending audio")
	game.hud.settings_volume.value = 37
	expect(not AudioServer.is_bus_mute(bus), "raising volume restores mixer without replaying old cues")
	game.hud.settings_mute.pressed.emit()
	expect(game.muted and game.soundscape.muted and game.preferences.muted, "mute button applies and persists")
	var event := InputEventAction.new()
	event.action = "jw_mute"
	event.pressed = true
	game._unhandled_input(event)
	expect(not game.muted and not game.preferences.muted and game.hud.settings_mute.text.contains("开启"), "M updates preferences and open settings consistently")
	game._unhandled_input(event)
	game._physics_process(.5)
	expect(game.state.snapshot() == snapshot and game.world.time == 0, "settings pause keeps ledger and simulation clocks frozen")
	expect(FileAccess.get_file_as_bytes(game.save_path) == save_bytes, "changing settings never rewrites journey bytes")
	game._modal_action("settings_back")
	expect(game.hud.modal_open and game.hud.modal_title.text == "暂停", "back returns to paused menu")
	game._modal_action("resume")
	await shot("smooth-coast-1152")
	game.toggle_overview()
	game.world.animate(game.state, 0, false, false, -1)
	expect(not game.world.sun.shadow_enabled and game.world.grass_mesh.visible_instance_count == 0, "overview respects smooth budget")
	game.toggle_overview()
	game.world.animate(game.state, 0, false, false, -1)
	expect(not game.world.sun.shadow_enabled and game.world.grass_mesh.visible_instance_count == 0, "leaving overview cannot restore expensive smooth details")
	game.choose_world(1000000)
	await game.wait_until_ready()
	expect(game.world.reduced_detail and not game.world.sun.shadow_enabled, "new map retains current preset")
	await close()
	await boot()
	expect(game.preferences.quality == "smooth" and game.muted and is_equal_approx(game.soundscape.volume_level, .37), "restart loads actual device preferences")
	expect(game.state.target_stones == 1000000 and Store.load_game(game.save_path).state.snapshot() == game.state.snapshot(), "restart still loads unchanged journey schema")
	game.show_menu()
	game._modal_action("settings")
	game.hud.settings_quality.pressed.emit()
	expect(not game.world.reduced_detail and game.world.sun.shadow_enabled and game.world.grass_mesh.visible_instance_count == -1, "standard restores original details")
	expect(root.msaa_3d == Viewport.MSAA_2X and root.scaling_3d_scale == 1, "standard restores original viewport")
	if not capture_folder.is_empty():
		await process_frame
		await process_frame
		expect(game.hud.root.get_global_rect().encloses(game.hud.settings_volume.get_global_rect()) and game.hud.root.get_global_rect().encloses(game.hud.settings_quality.get_global_rect()), "settings fit actual small window")
	await shot("settings-restored-1152")
	game._modal_action("resume")
	for target in [100000, 1000000, 10000000, 100000000]:
		game.choose_world(target)
		await game.wait_until_ready()
		var ledger: Dictionary = game.state.snapshot()
		game.show_menu()
		game._modal_action("settings")
		game.hud.settings_quality.pressed.emit()
		expect(game.state.snapshot() == ledger and game.world.reduced_detail and not game.world.sun.shadow_enabled, "smooth switches safely on scale %d" % target)
		game._modal_action("resume")
		game.toggle_overview()
		game.world.animate(game.state, 0, false, false, -1)
		game.toggle_overview()
		game.world.animate(game.state, 0, false, false, -1)
		expect(game.world.grass_mesh.visible_instance_count == 0 and not game.world.sun.shadow_enabled, "overview preserves smooth preset on scale %d" % target)
		if target == 100000000:
			await shot("smooth-largest-1152")
		game.show_menu()
		game._modal_action("settings")
		game.hud.settings_quality.pressed.emit()
		expect(game.state.snapshot() == ledger and game.world.sun.shadow_enabled and game.world.grass_mesh.visible_instance_count == -1, "standard restores safely on scale %d" % target)
		game._modal_action("resume")
	await close()
	var pref_bytes := FileAccess.get_file_as_bytes(folder.path_join("preferences.json"))
	await boot(false)
	expect(not game.preferences_enabled and game.preferences.quality == "standard" and not game.muted, "sample mode ignores persistent preferences")
	game.show_menu()
	game._modal_action("settings")
	game.hud.settings_quality.pressed.emit()
	game._process(1)
	expect(FileAccess.get_file_as_bytes(game.preferences_path) == pref_bytes, "sample preview changes never overwrite player preferences")
	await close()
	await create_timer(.1).timeout
	print("PREFERENCES TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
