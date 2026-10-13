extends Node3D

const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
const HUD = preload("res://scripts/hud.gd")
const Store = preload("res://scripts/save_store.gd")
const Models = preload("res://scripts/models.gd")
const Soundscape = preload("res://scripts/soundscape.gd")

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
	add_child(world)
	world.setup(state)
	hud = HUD.new()
	add_child(hud)
	hud.interact_requested.connect(interact)
	hud.throw_requested.connect(throw_forward)
	hud.upgrade_requested.connect(buy_upgrade)
	hud.save_requested.connect(save_game.bind(true))
	hud.menu_requested.connect(show_menu)
	hud.overview_requested.connect(toggle_overview)
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
		hud.notify("旅程已续上。向大陆寻山，向更广的海出发。")
	elif showcase:
		hud.notify("向西是群山，向东是浅海、远海与深海。")
	win_shown = state.won

func _setup_input() -> void:
	var keys := {
		"jw_left": [KEY_A, KEY_LEFT], "jw_right": [KEY_D, KEY_RIGHT],
		"jw_up": [KEY_W, KEY_UP], "jw_down": [KEY_S, KEY_DOWN],
		"jw_high": [KEY_SPACE], "jw_interact": [KEY_E], "jw_throw": [KEY_Q],
		"jw_menu": [KEY_ESCAPE], "jw_mute": [KEY_M], "jw_overview": [KEY_TAB],
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
	bird.velocity.y = clampf(((world.flight_ceiling if high else 1.45) - bird.position.y) * 7, -6, 8)
	bird.move_and_slide()
	bird.position.x = clampf(bird.position.x, state.map_origin.x + 0.1, state.map_origin.x + state.map_side - 0.1)
	bird.position.z = clampf(bird.position.z, state.map_origin.y + 0.1, state.map_origin.y + state.map_side - 0.1)
	state.player = Vector2(bird.position.x, bird.position.z)
	if movement.length_squared() > 0.01:
		world.bird_model.rotation.y = lerp_angle(world.bird_model.rotation.y, atan2(-movement.x, -movement.z), delta * 12)
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
	_drain_messages()
	save_clock += delta
	if save_clock >= 15:
		save_game(false)
		save_clock = 0
	if state.won and not win_shown:
		win_shown = true
		hud.show_modal("这一次，心愿已成", "%s石，一次次衔起，一次次投入海中。\n\n你完成了这段属于自己的旅程。\n可以留在这片海岸，也可以带着新的心愿重新出发。" % State.number(state.target_stones), [{"text": "留在这片海岸", "action": "resume"}, {"text": "保存旅程", "action": "save"}])
		save_game(false)

func _process(_delta: float) -> void:
	if soundscape != null and hud != null:
		soundscape.set_context(state.player.x, hud.modal_open, selection_pending)
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
	hud.notify("全图俯瞰：金圈内可投石，远处请先飞过去；Tab 返回。" if world.overview else "随行视角：向大陆探索群山，向外海继续填海。")

func interact() -> void:
	if hud.modal_open or selection_pending:
		return
	if world.bird_body.position.y > 2.7:
		hud.notify("先松开空格，降到地面附近再采集或对话。")
		return
	var npc := state.nearby_mountain(state.player, 2.1, true)
	if npc >= 0:
		show_npc_dialogue(npc)
		return
	var amount := 0
	var pile := state.nearby_pile(state.player)
	var drop := state.closest_drop(state.player)
	if drop >= 0:
		amount = state.pickup_drop(drop)
	elif pile >= 0:
		amount = state.pickup_pile(pile)
	else:
		amount = state.pickup_stone(state.closest_stone(state.player))
	if amount > 0:
		hud.notify("采集 %s 石 · 携带 %s / %s" % [State.number(amount), State.number(state.carried), State.number(state.capacity())])
		soundscape.play("gather")
	elif state.carried >= state.capacity():
		hud.notify("石篓已满，飞近海岸，在金色射程圈内投石。")
	else:
		var mine := state.nearby_mountain(state.player, 3.1)
		if mine >= 0 and state.mountains[mine]["settled"] and int(state.mountains[mine]["stock"]) == 0:
			hud.notify("这座山的石料已搬空，不会再产出石子。向大陆深处寻山吧。")
		else:
			hud.notify("散石采集一次就会消失；累计填海 128 石后，穿山甲自动开山。")
	_refresh()

func show_npc_dialogue(_index: int = -1) -> void:
	var index := state.pangolin_mountain()
	var mountain: Dictionary = state.mountains[index]
	var body := ""
	if not state.mining_unlocked():
		body = "“这是你的心愿，我可以帮你开山。”\n\n“等你累计填海 %d 石，我就从最小的山开始挖。挖完一座，再去下一座，不用回来催我。”\n\n已填 %d / %d 石，还差 %d 石。" % [State.MINING_UNLOCK_STONES, state.total_delivered, State.MINING_UNLOCK_STONES, State.MINING_UNLOCK_STONES - state.total_delivered]
	elif state.next_mountain() < 0:
		body = "“山都开完啦，我也该歇一歇了。”\n\n“剩下的石料都在原来的山体位置，按 E 搬运。搬空的山不会再长出石头。”"
	else:
		body = "“我正在开采%s，已经挖了 %.1f%%。”\n\n“只有我一个，慢慢从小山挖到大山。整座挖完后会留下 %s 石，我就去下一座。”\n\n提升采矿修行会加快开山；你继续填海就好。" % [state.mountain_name(index), float(mountain["work"]) / float(mountain["yield"]) * 100, State.number(int(mountain["yield"]))]
	hud.show_modal("穿山甲 · 开山之约", body, [{"text": "我继续前行", "action": "resume"}])

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
		hud.notify("先采集石子，再把它们投向海中。")
		return 0
	var index := state.cell_at(point)
	if index < 0:
		hud.notify("这次旅程以方形边界为界，请选择地图内的落点。")
		return 0
	if not world.point_visible(point):
		hud.notify("落点在视野之外。向海飞行，或按 Tab 展开全图。")
		return 0
	if not state.can_throw(point):
		hud.notify("落点距你 %.1f，当前射程 %.1f。飞近一些，或修行投石。" % [state.player.distance_to(point), state.throw_distance()])
		return 0
	var sea := state.sea_depth[index] >= 0
	var was_unlocked := state.mining_unlocked()
	var was_won := state.won
	var before_cells := state.filled_count
	var amount := state.deposit(point)
	if not was_unlocked and state.mining_unlocked():
		soundscape.play("unlock")
		save_game(false)
	if amount > 0:
		_throw_effect(point, sea, state.filled_count > before_cells, state.won and not was_won)
		hud.notify("投入 %s 石 · 修行 +%s" % [State.number(amount), State.number(amount)] if sea else "在大陆放下 %s 石，石堆可再次采集。" % State.number(amount))
	else:
		hud.notify("海域已填满，多余石子仍在石篓中。")
	_refresh()
	return amount

func buy_upgrade(kind: String) -> void:
	if hud.modal_open or selection_pending:
		return
	if state.buy_upgrade(kind):
		var descriptions := {
			"bag": "负重提升 · 可携带 %s 石" % State.number(state.capacity()),
			"mining": "采矿提升 · 每次 %s 石，开山速度翻倍" % State.number(state.gather_power()),
			"speed": "羽翼渐丰 · 当前飞速 %.1f" % state.move_speed(),
			"throw": "投石修行 · 射程提升到 %.1f" % state.throw_distance(),
		}
		hud.notify(descriptions[kind])
		soundscape.play("upgrade")
		_refresh()
	else:
		hud.notify("修行尚不足，再向海中投入一些石子吧。")

func _refresh() -> void:
	var target: Vector2 = q_target()
	if get_viewport().gui_get_hovered_control() == null and not hud.modal_open:
		var mouse: Variant = mouse_world_point(get_viewport().get_mouse_position())
		if mouse != null and state.cell_at(mouse) >= 0:
			target = mouse
	aimed_cell = state.cell_at(target) if world.point_visible(target) else -1
	world.aim_point = target
	world.sync(state)
	var prompt := "E  采集 · 每次 %s 石" % State.number(state.gather_power())
	var npc := state.nearby_mountain(state.player, 2.1, true)
	var pile := state.nearby_pile(state.player)
	if npc >= 0:
		prompt = "E  与%s的穿山甲对话" % state.mountain_name(npc)
	elif pile >= 0:
		prompt = "E  碎石场 · 余 %s 石" % State.number(int(state.mountains[pile]["stock"]))
	elif state.carried >= state.capacity():
		prompt = "石篓已满 · 飞近海面再投石"
	hud.update_state(state, prompt, aimed_cell, target)

func _drain_messages() -> void:
	if state.messages.is_empty():
		return
	# Group queued progress messages after a long simulation step.
	var message: String = state.messages.pop_front()
	if state.messages.size() > 2:
		message += "（另有 %d 条开采进展）" % state.messages.size()
		state.messages.clear()
	hud.notify(message)

func show_menu() -> void:
	if hud.modal_open or selection_pending:
		return
	hud.show_modal("暂歇于海岸", "这次心愿：%s 石\n已填：%s 石 · 已成陆地 %d 格\n\nE 采集与对话，鼠标点击金色射程圈内投石。\nTab 全图，滚轮缩放。暂停和离线期间不生产。" % [State.number(state.target_stones), State.number(state.total_delivered), state.filled_count], [{"text": "继续旅程", "action": "resume"}, {"text": "保存旅程", "action": "save"}, {"text": "重新选择填海规模…", "action": "reset_confirm"}])

func _modal_action(action: String) -> void:
	if action.begins_with("world_"):
		choose_world(int(action.trim_prefix("world_")))
		return
	match action:
		"resume":
			if not selection_pending:
				hud.hide_modal()
				choosing_again = false
		"save":
			save_game(true)
			hud.hide_modal()
		"reset_confirm":
			hud.show_modal("重新踏上另一段旅程？", "确认后可以重新选择填海规模。\n\n当前旅程会先保留一份存档副本，再开始新地图。", [{"text": "继续当前旅程", "action": "resume"}, {"text": "选择新的规模", "action": "pick_again"}])
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
	add_child(world)
	world.setup(state)
	selection_pending = false
	choosing_again = false
	save_blocked = false
	win_shown = false
	simulation_clock = 0
	save_clock = 0
	hud.hide_modal()
	hud.set_overview(false)
	hud.notify("从第一石开始。向西探索群山，向东填海。")
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
			hud.notify("旅程已保存。下次打开将从这里继续。")
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

func _advance_world(seconds: float) -> void:
	var previous_artifacts := state.artifacts.size()
	var previous_mine := state.next_mountain()
	state.tick(seconds)
	if state.artifacts.size() > previous_artifacts:
		soundscape.play("relic")
	if previous_mine >= 0 and state.mountains[previous_mine]["settled"]:
		var distance := state.player.distance_to(state.mountain_position(previous_mine))
		if distance < 60.0:
			soundscape.play("mined", 1.0 / (1.0 + distance / 12.0))

func _throw_effect(target: Vector2, sea: bool, formed_land: bool, completed: bool) -> void:
	var journey := state
	var audio_epoch: int = soundscape.epoch
	soundscape.play("throw")
	var rock := Models.mesh_part(self, Models.rock_mesh(2), Models.material(Color("d9ceb3")), world.bird_body.position, Vector3.ONE * 0.3)
	var start: Vector3 = rock.position
	var end := Vector3(target.x, maxf(0.25, world.cell_height(state, state.cell_at(target)) + 0.04), target.y)
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		rock.position = start.lerp(end, t) + Vector3.UP * sin(t * PI) * 1.5
		rock.rotation += Vector3(0.1, 0.15, 0.05)
	, 0.0, 1.0, 0.48)
	tween.tween_callback(func() -> void:
		rock.queue_free()
		if journey != state:
			return
		if audio_epoch == soundscape.epoch:
			soundscape.play("water" if sea else "land")
			if completed:
				soundscape.play("complete")
			elif formed_land:
				soundscape.play("fill")
		var ripple: MeshInstance3D = world.ring(Color("e9e8c8"), 0.35, 0.04)
		ripple.position = end
		add_child(ripple)
		var fade := create_tween()
		fade.tween_property(ripple, "scale", Vector3(3, 0.1, 3), 0.55)
		fade.tween_callback(ripple.queue_free)
	)
