extends Node3D

const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
const HUD = preload("res://scripts/hud.gd")
const Store = preload("res://scripts/save_store.gd")
const Soundscape = preload("res://scripts/soundscape.gd")
const Feedback = preload("res://scripts/visuals/action_feedback.gd")
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
var choosing_again: bool = false
var muted: bool = false
var simulation_clock: float = 0
var refresh_clock: float = 0
var save_clock: float = 0
var pickup_clock: float = 0
var aimed_cell: int = -1
var capture_path: String = ""
var capture_frames: int = 0
var showcase: bool = false
var win_shown: bool = false
var soundscape: Node
var feedback: Node3D

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
			save_enabled = false
			muted = true
		if arg.begins_with("--save-path="):
			save_path = arg.trim_prefix("--save-path=")
		if arg.begins_with("--target="):
			target = int(arg.trim_prefix("--target="))
		if arg == "--showcase":
			showcase = true
		if arg == "--overview":
			atlas_view = true
	soundscape = Soundscape.new()
	add_child(soundscape)
	soundscape.set_muted(muted)
	var loaded: Dictionary = Store.load_game(save_path) if save_enabled else {"state": null, "status": "new"}
	state = loaded["state"] if loaded["state"] != null else State.new(target)
	save_blocked = loaded["status"] == "invalid"
	selection_pending = loaded["state"] == null and not showcase
	if showcase:
		_prepare_showcase()
	world = World.new()
	_configure_visuals()
	add_child(world)
	world.setup(state)
	_setup_feedback()
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
	get_tree().auto_accept_quit = false
	if atlas_view:
		world.overview = true
		world.update_camera(state, 1.0, true)
		hud.set_overview(true)
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
	if hud == null or hud.modal_open or selection_pending:
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
	if event.is_action_pressed("jw_menu"):
		if selection_pending:
			return
		if hud.modal_open:
			hud.hide_modal()
			choosing_again = false
		else:
			show_menu()
	elif event.is_action_pressed("jw_mute"):
		muted = not muted
		soundscape.set_muted(muted)
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
	hud.show_modal("暂停", "已填 %s / %s 石\n%s" % [State.number(state.total_delivered), State.number(state.target_stones), hud.save_label.text], [{"text": "继续", "action": "resume"}, {"text": "保存", "action": "save"}, {"text": "操作说明", "action": "help"}, {"text": "重新开始…", "action": "reset_confirm"}])

func show_help() -> void:
	if hud.modal_open or selection_pending:
		return
	hud.show_modal("操作", "WASD / 方向键  移动\n空格  升高增程，松开降落\nE  低空采集 / 对话（可按住）\nQ / 鼠标左键  射程内投石\n\nU  收起升级栏　Tab  全图\n滚轮  缩放　M  静音　Esc  暂停\n\n满高度射程为基础的 2 倍，金圈显示当前范围。\n陆地石子可拾回；填入海中才获得修行。", [{"text": "返回", "action": "resume"}])

func _modal_action(action: String) -> void:
	if action.begins_with("world_"):
		choose_world(int(action.trim_prefix("world_")))
		return
	match action:
		"resume":
			if not selection_pending:
				hud.hide_modal()
				choosing_again = false
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
	if State.profile_for(target) == null:
		return false
	if save_enabled and (selection_pending or choosing_again):
		if not _archive_before_new():
			hud.modal_text.text = "原存档暂时无法备份，请检查保存目录权限。当前旅程仍被保留。"
			return false
	soundscape.reset()
	var fresh := State.new(target)
	state = fresh
	if world != null:
		remove_child(world)
		world.queue_free()
	world = World.new()
	_configure_visuals()
	add_child(world)
	world.setup(state)
	_setup_feedback()
	selection_pending = false
	choosing_again = false
	save_blocked = false
	win_shown = false
	simulation_clock = 0
	save_clock = 0
	hud.seen_relics = 0
	hud.hide_modal()
	hud.set_overview(false)
	hud.notify("WASD 移动 · E 采集 · Q 投石")
	_refresh()
	save_game(false)
	return true

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
	if not save_enabled or selection_pending:
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
