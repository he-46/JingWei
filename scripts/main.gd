extends Node3D

signal loading_finished

const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
const HUD = preload("res://scripts/hud.gd")
const Store = preload("res://scripts/save_store.gd")
const Soundscape = preload("res://scripts/soundscape.gd")
const Feedback = preload("res://scripts/visuals/action_feedback.gd")
const Preferences = preload("res://scripts/preferences.gd")
const RenderWarmup = preload("res://scripts/visuals/render_warmup.gd")
@export var bird_visual_scene: PackedScene
@export var pangolin_visual_scene: PackedScene
@export var mountain_visual_scenes: Array[PackedScene] = World.Catalog.scenes(World.Catalog.MOUNTAINS)

var state: JWState
var world: Node3D
var hud: CanvasLayer
var save_path: String = "user://coast_journey.json"
var save_enabled: bool = true
var save_blocked: bool = false
var selection_pending: bool = false
var skip_scale_picker := false
var choosing_again: bool = false
var muted: bool = false
var simulation_clock: float = 0
var refresh_clock: float = 0
var save_clock: float = 0
var pickup_clock: float = 0
var aimed_cell: int = -1
var capture_path: String = ""
var capture_continued := false
var capture_frames: int = 0
var showcase: bool = false
var win_shown: bool = false
var soundscape: Node
var feedback: Node3D
var preferences_path := "user://preferences.json"
var preferences_enabled := true
var preferences: Dictionary = Preferences.DEFAULTS.duplicate()
var preferences_dirty := false
var preferences_clock := 0.0
var preferences_error_shown := false
var loading := false
var loading_thread: Thread
var warmup_report: Dictionary = {}

func _ready() -> void:
	_setup_input()
	var target := 100000
	var atlas_view := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--qa":
			save_enabled = false
			muted = true
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
			muted = true
		if arg == "--capture-continued":
			capture_continued = true
		if arg.begins_with("--save-path="):
			save_path = arg.trim_prefix("--save-path=")
		if arg.begins_with("--target="):
			target = int(arg.trim_prefix("--target="))
		if arg == "--showcase":
			showcase = true
		if arg == "--overview":
			atlas_view = true
	if not capture_path.is_empty() and not capture_continued:
		save_enabled = false
	preferences_enabled = preferences_enabled and save_enabled and (capture_path.is_empty() or capture_continued)
	# Explicit fixture save paths also isolate preferences before any read occurs.
	if save_path != "user://coast_journey.json" and preferences_path == "user://preferences.json":
		preferences_path = save_path.get_base_dir().path_join("preferences.json")
	if preferences_enabled:
		preferences = Preferences.load_preferences(preferences_path)
		muted = muted or bool(preferences.muted)
	preferences.muted = muted
	soundscape = Soundscape.new()
	add_child(soundscape)
	soundscape.set_volume(float(preferences.volume))
	soundscape.set_muted(muted)
	hud = HUD.new()
	add_child(hud)
	hud.interact_requested.connect(interact)
	hud.throw_requested.connect(throw_forward)
	hud.upgrade_requested.connect(buy_upgrade)
	hud.save_requested.connect(save_game.bind(true))
	hud.menu_requested.connect(show_menu)
	hud.overview_requested.connect(toggle_overview)
	hud.help_requested.connect(show_help)
	hud.modal_action.connect(_modal_action)
	hud.setting_changed.connect(change_setting)
	get_tree().auto_accept_quit = false
	_apply_preferences()
	loading = true
	hud.show_loading("读取旅程", 0)
	# Let the first waiting screen draw before reading or constructing a world.
	await get_tree().process_frame
	var loaded: Dictionary = await _background(func() -> Dictionary:
		var result: Dictionary = Store.load_game(save_path) if save_enabled else {"state": null, "status": "new"}
		result.selection = result.state == null and not showcase and not skip_scale_picker
		if result.state == null:
			result.state = State.new(target)
		return result)
	state = loaded.state
	save_blocked = loaded.status == "invalid"
	selection_pending = loaded.selection
	if showcase:
		_prepare_showcase()
	if selection_pending:
		# A first-time choice does not need a disposable 3D coast or GPU compilation.
		loading = false
		hud.show_world_picker(false, true)
		if save_blocked:
			hud.modal_text.text = "现有旅程无法读取。选择新旅程后会保留原文件副本。\n选择这次心愿的大小，再出发。"
		loading_finished.emit()
		return
	await _build_world()
	if atlas_view:
		world.overview = true
		world.update_camera(state, 1.0, true)
		hud.set_overview(true)
	loading = false
	hud.hide_modal()
	_refresh()
	if selection_pending:
		hud.show_world_picker(false)
		if save_blocked:
			hud.modal_text.text = "现有旅程无法读取。选择新旅程后会保留原文件副本。\n选择这次心愿的大小，再出发。"
	elif state.migrated_from == 2:
		hud.notify("已续上旧旅程：填海与修行保留，山体和散石布局已适配新尺寸。")
	elif loaded["status"] == "recovered":
		hud.notify("已从上一份有效备份恢复旅程。")
	elif loaded["status"] == "loaded":
		hud.notify("已继续上次进度。")
	win_shown = state.won
	loading_finished.emit()

func wait_until_ready() -> void:
	while loading:
		await loading_finished

func _background(job: Callable) -> Variant:
	loading_thread = Thread.new()
	var error := loading_thread.start(job)
	if error != OK:
		loading_thread = null
		# Unusual platforms without thread support still retain the safe loading UI.
		return job.call()
	while loading_thread.is_alive():
		await get_tree().process_frame
	var result: Variant = loading_thread.wait_to_finish()
	loading_thread = null
	return result

func _exit_tree() -> void:
	# Closing during a read/archive must finish its file operation before exit.
	if loading_thread != null and loading_thread.is_started():
		loading_thread.wait_to_finish()

func _build_world() -> void:
	if world != null:
		remove_child(world)
		world.queue_free()
		feedback = null
		# Release the previous scene before allocating the next set of batches.
		await get_tree().process_frame
	world = World.new()
	# The opaque loading panel conceals construction while the renderer prepares
	# materials incrementally. Hiding the entire 3D tree defers all first-use shader
	# work to its reveal and causes a long cold-render stall on Compatibility.
	_configure_visuals()
	add_child(world)
	hud.show_loading("铺设海岸", .06)
	await get_tree().process_frame
	await world.setup(state, true, func(stage: String, fraction: float) -> void: hud.show_loading(stage, .06 + fraction * .75))
	_setup_feedback()
	_apply_preferences()
	await _prepare_rendering()

func _prepare_rendering() -> void:
	var warmup := RenderWarmup.new()
	add_child(warmup)
	warmup_report = await warmup.prepare(world, feedback, String(preferences.quality), hud.show_loading)
	warmup.queue_free()
	# Keep the opaque panel and simulation freeze through the actual world draw.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _setup_input() -> void:
	var keys := {
		"jw_left": [KEY_A, KEY_LEFT], "jw_right": [KEY_D, KEY_RIGHT],
		"jw_up": [KEY_W, KEY_UP], "jw_down": [KEY_S, KEY_DOWN],
		"jw_high": [KEY_SPACE], "jw_interact": [KEY_E], "jw_throw": [KEY_Q],
		"jw_menu": [KEY_ESCAPE], "jw_mute": [KEY_M], "jw_overview": [KEY_TAB],
		"jw_upgrades": [KEY_U], "jw_help": [KEY_F1],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _physics_process(delta: float) -> void:
	if loading or hud == null or hud.modal_open or selection_pending:
		return
	var direction := Input.get_vector("jw_left", "jw_right", "jw_up", "jw_down")
	var right := Vector3(world.camera.global_basis.x.x, 0, world.camera.global_basis.x.z).normalized()
	var down := Vector3(world.camera.global_basis.z.x, 0, world.camera.global_basis.z.z).normalized()
	var movement := (right * direction.x + down * direction.y).normalized()
	var high := Input.is_action_pressed("jw_high")
	var bird: CharacterBody3D = world.bird_body
	var speed := state.move_speed()
	bird.velocity.x = move_toward(bird.velocity.x, movement.x * speed, delta * speed * 7)
	bird.velocity.z = move_toward(bird.velocity.z, movement.z * speed, delta * speed * 7)
	bird.velocity.y = clampf(((world.flight_ceiling if high else State.BIRD_HOVER_HEIGHT) - bird.position.y) * 7, -6, 8)
	bird.move_and_slide()
	bird.position.x = clampf(bird.position.x, state.map_origin.x + 0.1, state.map_origin.x + state.map_side - 0.1)
	bird.position.z = clampf(bird.position.z, state.map_origin.y + 0.1, state.map_origin.y + state.map_side - 0.1)
	state.player = Vector2(bird.position.x, bird.position.z)
	if movement.length_squared() > 0.01:
		world.bird_model.set_facing(Vector2(movement.x, movement.z), delta)
	simulation_clock += delta
	while simulation_clock >= 0.2:
		_advance_world(0.2)
		simulation_clock -= 0.2
	pickup_clock -= delta
	if Input.is_action_pressed("jw_interact") and pickup_clock <= 0:
		interact()
		pickup_clock = 0.55
	refresh_clock += delta
	if refresh_clock >= 0.15:
		_refresh()
		refresh_clock = 0
	world.animate(state, delta, direction.length_squared() > 0.01, high, aimed_cell)
	var locator_point: Vector2 = world.update_player_locator(delta)
	hud.locate_player(locator_point, world.player_obscured)
	_drain_messages()
	save_clock += delta
	if save_clock >= 15:
		save_game(false)
		save_clock = 0
	if state.won and not win_shown and not feedback.completion_pending():
		win_shown = true
		hud.show_modal("填海完成", "已填入 %s 石。精卫完成了自己的心愿。" % State.number(state.target_stones), [{"text": "继续探索", "action": "resume"}, {"text": "保存", "action": "save"}])
		save_game(false)

func _process(delta: float) -> void:
	if loading:
		return
	if preferences_dirty:
		preferences_clock -= delta
		if preferences_clock <= 0:
			_save_preferences()
	if soundscape != null and hud != null:
		soundscape.set_context(state.player.x, hud.modal_open, selection_pending)
		if feedback != null and not hud.modal_open and not selection_pending:
			feedback.set_detail(world.bird_body.position, world.overview)
			feedback.advance(delta)
	if capture_path.is_empty():
		return
	capture_frames += 1
	if capture_frames == 45:
		var image := get_viewport().get_texture().get_image()
		var result := image.save_png(capture_path)
		print("CAPTURE_RESULT ", result, " ", capture_path)
		get_tree().quit(0 if result == OK else 1)

func _unhandled_input(event: InputEvent) -> void:
	if loading:
		return
	if event.is_action_pressed("jw_menu"):
		if selection_pending:
			return
		if hud.modal_open:
			_save_preferences()
			hud.hide_modal()
			choosing_again = false
		else:
			show_menu()
	elif event.is_action_pressed("jw_mute"):
		muted = not muted
		soundscape.set_muted(muted)
		preferences.muted = muted
		preferences_dirty = preferences_enabled
		_save_preferences()
		if hud.modal_title.text == "设置" and hud.modal_open:
			hud.refresh_settings(preferences)
		hud.notify("声音已关闭" if muted else "声音已开启")
	elif not hud.modal_open and event.is_action_pressed("jw_upgrades"):
		hud.toggle_drawer()
	elif not hud.modal_open and event.is_action_pressed("jw_help"):
		show_help()
	elif not hud.modal_open and event.is_action_pressed("jw_overview"):
		toggle_overview()
	elif not hud.modal_open and event.is_action_pressed("jw_throw"):
		throw_forward()
	elif not hud.modal_open and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not world.overview:
				world.zoom = clampf(world.zoom * (0.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.18), 0.6, 2.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var point: Variant = mouse_world_point(event.position)
			if point != null:
				deposit_at(point)

func mouse_world_point(screen: Vector2) -> Variant:
	var origin: Vector3 = world.camera.project_ray_origin(screen)
	var ray: Vector3 = world.camera.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, 0.2).intersects_ray(origin, ray)
	return Vector2(hit.x, hit.z) if hit != null else null

func toggle_overview() -> void:
	if hud.modal_open or selection_pending:
		return
	world.overview = not world.overview
	hud.set_overview(world.overview)
	world.update_camera(state, 1.0, true)
	_refresh()

func interact() -> void:
	if hud.modal_open or selection_pending:
		return
	if world.bird_body.position.y > 2.7:
		hud.notify("松开空格，降到低空后操作。")
		return
	var npc := state.nearby_mountain(state.player, 2.1, true)
	if npc >= 0:
		show_npc_dialogue(npc)
		return
	var amount := 0
	var pile := state.nearby_pile(state.player)
	var drop := state.closest_drop(state.player)
	var source := state.player
	if drop >= 0:
		source = state.cell_center(drop)
		amount = state.pickup_drop(drop)
	elif pile >= 0:
		source = state.pile_position(pile)
		amount = state.pickup_pile(pile)
	else:
		var stone := state.closest_stone(state.player)
		if stone >= 0:
			source = state.stone_positions[stone]
		amount = state.pickup_stone(stone)
	if amount > 0:
		world.bird_model.play_gather(amount)
		soundscape.play("gather")
		feedback.burst("gather", Vector3(source.x, .38, source.y), world.bird_body.position)
	elif state.carried >= state.capacity():
		hud.notify("负重已满，靠近海面投石。")
	else:
		var mine := state.nearby_mountain(state.player, 3.1)
		if mine >= 0 and state.mountains[mine]["settled"] and int(state.mountains[mine]["stock"]) == 0:
			hud.notify("这里的石料已搬空。")
		else:
			hud.notify("附近没有可采集的石子。")
	_refresh()

func show_npc_dialogue(_index: int = -1) -> void:
	var index := state.pangolin_mountain()
	var mountain: Dictionary = state.mountains[index]
	var body := ""
	if not state.mining_unlocked():
		body = "累计填海 %d 石后，自动从最小的山开始开采。\n\n当前 %d / %d 石" % [State.MINING_UNLOCK_STONES, state.total_delivered, State.MINING_UNLOCK_STONES]
	elif state.next_mountain() < 0:
		body = "所有山都已挖完。剩余石料在原山址，按 E 搬运。"
	else:
		body = "%s · %.1f%%\n完工产出 %s 石，然后自动转往下一座。\n\n提升采集等级可以加快开山。" % [state.mountain_name(index), float(mountain["work"]) / float(mountain["yield"]) * 100, State.number(int(mountain["yield"]))]
	hud.show_modal("穿山甲", body, [{"text": "返回", "action": "resume"}])

func q_target() -> Vector2:
	var current := state.cell_at(state.player)
	if current >= 0 and state.sea_depth[current] >= 0:
		return state.player
	return Vector2(0.25, clampf(state.player.y, state.map_origin.y + 0.1, -state.map_origin.y - 0.1))

func throw_forward() -> void:
	deposit_at(q_target())

func deposit_at(point: Vector2) -> int:
	if hud.modal_open or selection_pending:
		return 0
	if state.carried == 0:
		hud.notify("没有携带石子。")
		return 0
	var index := state.cell_at(point)
	if index < 0:
		hud.notify("无法投向地图边界外。")
		return 0
	if not world.point_visible(point):
		hud.notify("落点不在视野内。")
		return 0
	var flight_height: float = world.bird_body.position.y
	if not state.can_throw(point, flight_height):
		hud.notify("超出射程：%.1f / %.1f。" % [state.player.distance_to(point), state.throw_distance(flight_height)])
		return 0
	var sea := state.sea_depth[index] >= 0
	var was_unlocked := state.mining_unlocked()
	var was_won := state.won
	var before_cells := state.filled_count
	var amount := state.deposit(point, flight_height)
	if not was_unlocked and state.mining_unlocked():
		soundscape.play("unlock")
		save_game(false)
	if amount > 0:
		world.bird_model.play_throw(amount)
		_throw_effect(point, sea, state.filled_count > before_cells, state.won and not was_won)
	else:
		hud.notify("海域已填满。")
	_refresh()
	return amount

func buy_upgrade(kind: String) -> void:
	if hud.modal_open or selection_pending:
		return
	if state.buy_upgrade(kind):
		var descriptions := {
			"bag": "负重提升至 %s 石" % State.number(state.capacity()),
			"mining": "采集提升至 %s 石/次" % State.number(state.gather_power()),
			"speed": "飞速提升至 %.1f" % state.move_speed(),
			"throw": "基础射程提升至 %.1f" % state.throw_distance(),
		}
		hud.notify(descriptions[kind])
		soundscape.play("upgrade")
		_refresh()
	else:
		hud.notify("修行不足。")

func _refresh() -> void:
	var target: Vector2 = q_target()
	if get_viewport().gui_get_hovered_control() == null and not hud.modal_open:
		var mouse: Variant = mouse_world_point(get_viewport().get_mouse_position())
		if mouse != null and state.cell_at(mouse) >= 0:
			target = mouse
	aimed_cell = state.cell_at(target) if world.point_visible(target) else -1
	world.aim_point = target
	world.sync(state)
	var prompt := "寻找石子"
	var npc := state.nearby_mountain(state.player, 2.1, true)
	var pile := state.nearby_pile(state.player)
	if world.bird_body.position.y > 2.7:
		prompt = "高飞 · 射程 %.1f" % state.throw_distance(world.bird_body.position.y) if state.carried > 0 else "松开空格降落"
	elif npc >= 0:
		prompt = "穿山甲"
	elif state.carried >= state.capacity():
		prompt = "负重已满 · 靠近海面投石"
	elif pile >= 0:
		prompt = "碎石场 · 剩余 %s 石" % State.number(int(state.mountains[pile]["stock"]))
	elif state.closest_drop(state.player) >= 0:
		prompt = "拾回落地石子"
	elif state.closest_stone(state.player) >= 0:
		prompt = "散石 · 每次 %s 石" % State.number(state.gather_power())
	hud.update_state(state, prompt, aimed_cell, target, world.bird_body.position.y)
	if world.bird_body.position.y > 2.7:
		hud.interact_button.disabled = true

func _drain_messages() -> void:
	if state.messages.is_empty():
		return
	var message: String = state.messages.back()
	for item in state.messages:
		if item.contains("神器"):
			message = item
			break
	state.messages.clear()
	hud.notify(message)

func show_menu() -> void:
	if hud.modal_open or selection_pending:
		return
	hud.show_modal("暂停", "已填 %s / %s 石\n%s" % [State.number(state.total_delivered), State.number(state.target_stones), hud.save_label.text], [{"text": "继续", "action": "resume"}, {"text": "保存", "action": "save"}, {"text": "设置", "action": "settings"}, {"text": "操作说明", "action": "help"}, {"text": "重新开始…", "action": "reset_confirm"}])

func _apply_preferences() -> void:
	var smooth: bool = preferences.quality == "smooth"
	if world != null:
		world.reduced_detail = smooth
		world.animate(state, 0, false, false, aimed_cell)
	get_viewport().scaling_3d_scale = .75 if smooth else 1.0
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if smooth else Viewport.MSAA_2X
	if preferences_enabled and DisplayServer.get_name() != "headless":
		var mode := Window.MODE_FULLSCREEN if preferences.fullscreen else Window.MODE_WINDOWED
		if get_window().mode != mode:
			get_window().mode = mode

func change_setting(key: String, value: Variant) -> void:
	if loading or not hud.modal_open or hud.modal_title.text != "设置" or not Preferences.DEFAULTS.has(key) or key == "version":
		return
	preferences[key] = value
	preferences = Preferences.sanitize(preferences)
	muted = bool(preferences.muted)
	if key in ["quality", "fullscreen"]:
		_apply_preferences()
	else:
		soundscape.set_volume(float(preferences.volume))
		soundscape.set_muted(muted)
	hud.refresh_settings(preferences)
	preferences_dirty = preferences_enabled
	preferences_clock = .4
	if key != "volume":
		_save_preferences()
	if key == "quality" and world != null and DisplayServer.get_name() != "headless":
		loading = true
		_prepare_quality()

func _prepare_quality() -> void:
	hud.show_loading("准备画面", 0)
	await _prepare_rendering()
	loading = false
	hud.show_settings(preferences)
	loading_finished.emit()

func _save_preferences() -> void:
	if not preferences_enabled or not preferences_dirty:
		return
	var error := Preferences.save_preferences(preferences_path, preferences)
	if error == OK:
		preferences_dirty = false
		preferences_error_shown = false
	else:
		preferences_clock = 10
		if not preferences_error_shown and hud != null:
			hud.notify("设置暂未保存，请检查目录权限。")
			preferences_error_shown = true

func show_help() -> void:
	if hud.modal_open or selection_pending:
		return
	hud.show_modal("操作", "WASD / 方向键  移动\n空格  升高增程，松开降落\nE  低空采集 / 对话（可按住）\nQ / 鼠标左键  射程内投石\n\nU  收起升级栏　Tab  全图\n滚轮  缩放　M  静音　Esc  暂停\n\n满高度射程为基础的 2 倍，金圈显示当前范围。\n陆地石子可拾回；填入海中才获得修行。", [{"text": "返回", "action": "resume"}])

func _modal_action(action: String) -> void:
	if loading:
		return
	if action.begins_with("world_"):
		choose_world(int(action.trim_prefix("world_")))
		return
	match action:
		"resume":
			if not selection_pending:
				_save_preferences()
				hud.hide_modal()
				choosing_again = false
		"settings":
			hud.show_settings(preferences)
		"settings_back":
			_save_preferences()
			hud.hide_modal()
			show_menu()
		"help":
			hud.hide_modal()
			show_help()
		"save":
			save_game(true)
			hud.hide_modal()
		"reset_confirm":
			hud.show_modal("重新开始？", "当前进度会保留备份，然后选择新的填海规模。", [{"text": "取消", "action": "resume"}, {"text": "选择规模", "action": "pick_again"}])
		"pick_again":
			choosing_again = true
			hud.show_world_picker(true)

func choose_world(target: int) -> bool:
	# Returns whether the request was accepted; wait_until_ready awaits completion.
	if loading or State.profile_for(target) == null:
		return false
	loading = true
	soundscape.reset()
	soundscape.set_context(state.player.x, true, selection_pending)
	_replace_world(target)
	return true

func _replace_world(target: int) -> void:
	hud.show_loading("保留上一段旅程", 0)
	await get_tree().process_frame
	var prepared: Dictionary = await _background(func() -> Dictionary:
		if save_enabled and (selection_pending or choosing_again) and not _archive_before_new():
			return {"ok": false}
		return {"ok": true, "state": State.new(target)})
	if not prepared.ok:
		hud.show_world_picker(not selection_pending)
		hud.modal_text.text = "原存档暂时无法备份，请检查保存目录权限。当前旅程仍被保留。"
		loading = false
		loading_finished.emit()
		return
	state = prepared.state
	await _build_world()
	selection_pending = false
	choosing_again = false
	save_blocked = false
	win_shown = false
	simulation_clock = 0
	save_clock = 0
	refresh_clock = 0
	pickup_clock = 0
	aimed_cell = -1
	hud.seen_relics = 0
	var error := OK
	if save_enabled:
		hud.show_loading("保存旅程", .98)
		error = await _background(func() -> Error: return Store.save_game(save_path, state))
	loading = false
	hud.hide_modal()
	hud.set_overview(false)
	hud.notify("WASD 移动 · E 采集 · Q 投石")
	_refresh()
	if error != OK:
		hud.notify("旅程暂未保存，请检查保存目录权限。")
	loading_finished.emit()

func _archive_before_new() -> bool:
	# Persist the current in-memory journey before archiving when a restart was requested.
	if choosing_again and not save_blocked:
		if Store.save_game(save_path, state) != OK:
			return false
	for suffix in ["", ".bak"]:
		if FileAccess.file_exists(save_path + suffix):
			var archive: String = save_path + suffix + ".before-reset-" + str(int(Time.get_unix_time_from_system())) + "-" + str(Time.get_ticks_usec())
			if DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path + suffix), ProjectSettings.globalize_path(archive)) != OK:
				return false
	return true

func save_game(manual: bool = false) -> void:
	if loading or not save_enabled or selection_pending:
		return
	if save_blocked:
		hud.save_label.text = "原存档无法读取 · 自动保存停用"
		return
	var error := Store.save_game(save_path, state)
	if error == OK:
		hud.save_label.text = "已保存 · " + Time.get_time_string_from_system().substr(0, 5)
		if manual:
			hud.notify("已保存。")
	else:
		hud.save_label.text = "保存未成功 · 错误 %d" % error
		hud.notify("保存未成功，请检查保存目录权限。")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_preferences()
		if state != null and hud != null:
			save_game(false)
		get_tree().quit()

func _prepare_showcase() -> void:
	state.tick(18)
	for index in range(35):
		for action in range(4):
			state.pickup_stone(index % state.stone_positions.size())
		state.player = Vector2(-1, 3)
		state.deposit(Vector2(2, 3))
		if state.upgrade_cost("bag") > 0 and int(state.upgrades["bag"]) <= int(state.upgrades["mining"]):
			state.buy_upgrade("bag")
		state.buy_upgrade("mining")
	state.player = Vector2(-2.5, 3)
	state.pickup_stone(36 % state.stone_positions.size())
	state.messages.clear()

func _configure_visuals() -> void:
	if bird_visual_scene:
		world.bird_scene = bird_visual_scene
	if pangolin_visual_scene:
		world.pangolin_scene = pangolin_visual_scene
	world.mountain_scenes = mountain_visual_scenes

func _advance_world(seconds: float) -> void:
	var previous_artifacts := state.artifacts.size()
	var previous_mine := state.next_mountain()
	var unfinished: Array[int] = []
	for index in range(state.mountains.size()):
		if not state.mountains[index]["settled"]:
			unfinished.append(index)
	state.tick(seconds)
	if state.artifacts.size() > previous_artifacts:
		soundscape.play("relic")
		for index in range(previous_artifacts, state.artifacts.size()):
			var id: String = state.artifacts[index]
			for item in state.artifact_plan:
				if item["id"] == id:
					var point: Vector2 = state.mountain_position(int(item["mountain"]))
					point.x += state.mountain_radius(int(item["mountain"])) + .4
					feedback.discover(id, Vector3(point.x, 2.1, point.y))
	for index in unfinished:
		if state.mountains[index]["settled"]:
			var point := state.mountain_position(index)
			if state.player.distance_to(point) < 60.0:
				feedback.burst("mined", Vector3(point.x, .5, point.y), Vector3.ZERO, minf(state.mountain_radius(index), 3.0))
	if previous_mine >= 0 and state.mountains[previous_mine]["settled"]:
		world.npc_views[0]["animal"].play_complete(previous_mine)
		var distance := state.player.distance_to(state.mountain_position(previous_mine))
		if distance < 60.0:
			soundscape.play("mined", 1.0 / (1.0 + distance / 12.0))

func _throw_effect(target: Vector2, sea: bool, formed_land: bool, completed: bool) -> void:
	soundscape.play("throw")
	var end := Vector3(target.x, maxf(.25, world.cell_height(state, state.cell_at(target)) + .04), target.y)
	feedback.throw_stone(world.bird_body.position, end, sea, formed_land, completed, soundscape.epoch)

func _setup_feedback() -> void:
	feedback = Feedback.new()
	world.add_child(feedback)
	feedback.landed.connect(_impact_audio)

func _impact_audio(sea: bool, formed_land: bool, completed: bool, audio_epoch: int) -> void:
	if audio_epoch != soundscape.epoch:
		return
	soundscape.play("water" if sea else "land")
	if completed:
		soundscape.play("complete")
	elif formed_land:
		soundscape.play("fill")
