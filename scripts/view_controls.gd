extends RefCounted
## Stateless view/input helpers. Main owns focus, pause and scene lifetime.
const State = preload("res://scripts/state.gd")
const FirstPersonAim = preload("res://scripts/first_person_aim.gd")

static func setup_input(view_key: int) -> void:
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
		InputMap.action_erase_events(action)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	apply_view_key(view_key)

static func apply_view_key(view_key: int) -> void:
	if not InputMap.has_action("jw_view"):
		InputMap.add_action("jw_view")
	InputMap.action_erase_events("jw_view")
	var event := InputEventKey.new()
	event.physical_keycode = view_key
	InputMap.action_add_event("jw_view", event)

static func mouse_look(state: JWState, world: Node3D, event: InputEventMouseMotion, look_sensitivity: float) -> void:
	var sensitivity := .0025 * look_sensitivity
	world.look_yaw = wrapf(world.look_yaw - event.relative.x * sensitivity, -PI, PI)
	world.look_pitch = clampf(world.look_pitch - event.relative.y * sensitivity, deg_to_rad(-85), deg_to_rad(80))
	world.update_camera(state, 0, true)

static func target(state: JWState, world: Node3D) -> Dictionary:
	var origin: Vector3 = world.camera.global_position
	var direction: Vector3 = -world.camera.global_basis.z
	var hit: Variant = FirstPersonAim.surface_hit(state, origin, direction, world.ocean)
	if hit == null:
		return {"point": null, "reason": "瞄准海面或陆地" if direction.y >= 0 else "落点超出地图"}
	var query := PhysicsRayQueryParameters3D.create(origin, hit)
	query.exclude = [world.bird_body.get_rid()]
	# Mountain collisions block a ray aimed through the mountain at a coast.
	if not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return {"point": null, "reason": "山体遮挡"}
	return {"point": Vector2(hit.x, hit.z), "reason": ""}

static func update_hint(state: JWState, world: Node3D, hud: CanvasLayer, target: Vector2, aim_reason: String, visible_rect: Rect2) -> void:
	var usable: bool = target.is_finite() and state.can_throw(target, world.bird_body.position.y)
	hud.crosshair.add_theme_color_override("font_color", Color("fff1bd") if usable and state.carried > 0 else (Color("d38b79") if target.is_finite() and not usable else Color("b9c7c0")))
	hud.cell_label.visible = true
	if not target.is_finite():
		hud.cell_label.text = aim_reason
	elif state.carried == 0:
		hud.cell_label.text = "没有携石"
	else:
		var distance: float = state.player.distance_to(target)
		var reach: float = state.throw_distance(world.bird_body.position.y)
		var index: int = state.cell_at(target)
		var depth: int = state.sea_depth[index]
		hud.cell_label.text = "%s %s/%s 石" % [State.DEPTH_NAMES[depth], State.number(state.sea_fill[index]), State.number(state.sea_capacity[index])] if depth >= 0 else "陆地 · 可拾回"
		hud.cell_label.text += " · 距离 %.1f / 射程 %.1f" % [distance, reach]
		if usable:
			hud.cell_label.text += " · Q 投石"
		else:
			hud.cell_label.text += " · 超距"
	# Same priority and low-altitude rule as E; a screen hint never chooses a new
	# resource or bypasses proximity. Out-of-view targets remain in the bottom HUD.
	var point := Vector2.INF
	var caption := ""
	var height := .65
	if world.bird_body.position.y <= 2.7:
		var npc: int = state.nearby_mountain(state.player, 2.1, true)
		var drop: int = state.closest_drop(state.player)
		var pile: int = state.nearby_pile(state.player)
		var stone: int = state.closest_stone(state.player)
		if npc >= 0:
			point = state.npc_position(npc)
			caption = "E · 对话"
			height = 1.35
		elif state.carried < state.capacity():
			if drop >= 0:
				point = state.cell_center(drop)
				caption = "E · 拾回石子"
			elif pile >= 0:
				point = state.pile_position(pile)
				caption = "E · 搬运石料"
			elif stone >= 0:
				point = state.stone_positions[stone]
				caption = "E · 拾石"
	var screen := Vector2.INF
	if point.is_finite():
		var position := Vector3(point.x, height, point.y)
		if not world.camera.is_position_behind(position):
			var projected: Vector2 = world.camera.unproject_position(position)
			var rect: Rect2 = visible_rect.grow(-100)
			var query := PhysicsRayQueryParameters3D.create(world.camera.global_position, position)
			query.exclude = [world.bird_body.get_rid()]
			if rect.has_point(projected) and world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				screen = projected
	hud.set_interaction_hint(screen, caption)

static func mouse_target(state: JWState, world: Node3D, screen: Vector2) -> Variant:
	var origin: Vector3 = world.camera.project_ray_origin(screen)
	var ray: Vector3 = world.camera.project_ray_normal(screen)
	var hit: Variant = FirstPersonAim.surface_hit(state, origin, ray, world.ocean)
	return Vector2(hit.x, hit.z) if hit != null else null
