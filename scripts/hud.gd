extends CanvasLayer

signal interact_requested
signal throw_requested
signal upgrade_requested(kind: String)
signal save_requested
signal menu_requested
signal overview_requested
signal help_requested
signal modal_action(action: String)

const State = preload("res://scripts/state.gd")
const INK := Color("29413b")
const MUTED := Color("78847a")
const RUST := Color("ab7044")
const PAPER := Color("f4f2e7")
const ACCENT := Color("547b61")

var root: Control
var cargo: Label
var cultivation_label: Label
var progress_label: Label
var goal: Label
var total_bar: ProgressBar
var mining_label: Label
var mining_bar: ProgressBar
var context: Label
var notice: Label
var notice_panel: Control
var save_label: Label
var cell_label: Label
var relic_labels: Array[Label] = []
var atlas: TextureRect
var map_caption: Label
var side_panels: Array[Control] = []
var overview_panel: Control
var overview_info: Label
var atlas_base: Image
var atlas_texture: ImageTexture
var atlas_stamp := ""
var upgrade_buttons: Dictionary = {}
var upgrade_details: Dictionary = {}
var modal: Control
var modal_box: VBoxContainer
var modal_title: Label
var modal_text: Label
var modal_buttons: VBoxContainer
var modal_open := false
var notification_time := 0.0
var drawer: Control
var upgrade_page: VBoxContainer
var relic_page: VBoxContainer
var tabs: Dictionary = {}
var drawer_open := true
var active_tab := "upgrades"
var overview := false
var drawer_button: Button
var interact_button: Button
var throw_button: Button
var map_button: Button
var seen_relics := 0

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "SimHei"])
	theme.default_font = font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", Color("ffffff"))
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_stylebox("normal", "Button", style(Color("ebece1"), 6, Color("dfe3d5")))
	theme.set_stylebox("hover", "Button", style(Color("dde7d8"), 6, Color("9fb698")))
	theme.set_stylebox("pressed", "Button", style(ACCENT, 6, ACCENT))
	theme.set_stylebox("disabled", "Button", style(Color("eceee6"), 6, Color("e1e4da")))
	theme.set_stylebox("focus", "Button", style(Color.TRANSPARENT, 6, ACCENT))
	theme.set_stylebox("background", "ProgressBar", style(Color("dce3d7"), 2))
	theme.set_stylebox("fill", "ProgressBar", style(ACCENT, 2))
	root.theme = theme
	_build_header()
	_build_drawer()
	_build_map()
	_build_bottom()
	_build_modal()

static func number(value: int) -> String:
	return State.number(value).replace(".00万", "万").replace(".00亿", "亿")

static func style(color: Color, radius: int = 8, border: Color = Color("dce1d4")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = border
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func panel(parent: Control, rect: Rect2, right: bool = false, bottom: bool = false) -> VBoxContainer:
	var box := PanelContainer.new()
	parent.add_child(box)
	if right:
		box.anchor_left = 1
		box.anchor_right = 1
	if bottom:
		box.anchor_top = 1
		box.anchor_bottom = 1
	box.offset_left = rect.position.x
	box.offset_top = rect.position.y
	box.offset_right = rect.end.x
	box.offset_bottom = rect.end.y
	box.add_theme_stylebox_override("panel", style(PAPER))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	box.add_child(layout)
	return layout

func text(parent: Node, value: String, size: int = 15, color: Color = INK, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func button(parent: Node, value: String, callback: Callable, height: float = 36) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = height
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func bar(parent: Node, height: float) -> ProgressBar:
	var result := ProgressBar.new()
	result.custom_minimum_size.y = height
	result.show_percentage = false
	# Bars need no text padding; shared button/panel styles otherwise make them tall.
	for key in ["background", "fill"]:
		var skin: StyleBoxFlat = root.theme.get_stylebox(key, "ProgressBar").duplicate()
		skin.set_content_margin_all(0)
		result.add_theme_stylebox_override(key, skin)
	parent.add_child(result)
	return result

func _build_header() -> void:
	var box := panel(root, Rect2(20, 18, 1400, 70)).get_parent()
	box.anchor_right = 1
	box.offset_right = -20
	var old := box.get_child(0)
	box.remove_child(old)
	old.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	box.add_child(row)
	var pack := VBoxContainer.new()
	pack.custom_minimum_size.x = 210
	pack.add_theme_constant_override("separation", 1)
	row.add_child(pack)
	text(pack, "石子 / 负重", 11, MUTED)
	cargo = text(pack, "0 / 32", 21)
	var wallet := VBoxContainer.new()
	wallet.custom_minimum_size.x = 120
	wallet.add_theme_constant_override("separation", 1)
	row.add_child(wallet)
	text(wallet, "修行", 11, MUTED)
	cultivation_label = text(wallet, "0", 21, RUST)
	var progress := VBoxContainer.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.add_theme_constant_override("separation", 4)
	row.add_child(progress)
	var progress_row := HBoxContainer.new()
	progress.add_child(progress_row)
	progress_label = text(progress_row, "填海 0%", 16)
	progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal = text(progress_row, "", 12, MUTED)
	total_bar = bar(progress, 4)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	row.add_child(actions)
	drawer_button = button(actions, "升级  U", toggle_drawer)
	map_button = button(actions, "全图  Tab", func() -> void: overview_requested.emit())
	button(actions, "帮助", func() -> void: help_requested.emit()).tooltip_text = "操作说明 · F1"
	button(actions, "菜单  Esc", func() -> void: menu_requested.emit())

func _build_drawer() -> void:
	var box := panel(root, Rect2(20, 104, 278, 0))
	drawer = box.get_parent()
	side_panels.append(drawer)
	var row := HBoxContainer.new()
	box.add_child(row)
	for item in [["upgrades", "升级"], ["relics", "神器"]]:
		var id: String = item[0]
		var tab := button(row, item[1], func() -> void: select_tab(id), 32)
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs[id] = tab
	button(row, "×", toggle_drawer, 32).tooltip_text = "收起 · U"
	upgrade_page = VBoxContainer.new()
	upgrade_page.add_theme_constant_override("separation", 8)
	box.add_child(upgrade_page)
	for kind in ["bag", "mining", "throw", "speed"]:
		var id: String = kind
		var upgrade := button(upgrade_page, "", func() -> void: upgrade_requested.emit(id), 64)
		upgrade_buttons[id] = upgrade
		var name_label := text(upgrade, "", 12, MUTED)
		name_label.position = Vector2(12, 7)
		var value := text(upgrade, "", 16)
		value.position = Vector2(12, 29)
		var cost := text(upgrade, "", 13)
		cost.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		cost.offset_left = -84
		cost.offset_right = -12
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		upgrade_details[id] = {"name": name_label, "value": value, "cost": cost}
	var divider := HSeparator.new()
	upgrade_page.add_child(divider)
	mining_label = text(upgrade_page, "", 12, MUTED, true)
	mining_bar = bar(upgrade_page, 4)
	relic_page = VBoxContainer.new()
	relic_page.add_theme_constant_override("separation", 18)
	box.add_child(relic_page)
	for index in range(3):
		relic_labels.append(text(relic_page, "", 14, MUTED, true))
	select_tab("upgrades")

func _build_map() -> void:
	var box := panel(root, Rect2(20, 104, 242, 0))
	overview_panel = box.get_parent()
	overview_panel.visible = false
	text(box, "地图", 17)
	overview_info = text(box, "", 12, MUTED, true)
	atlas = TextureRect.new()
	atlas.custom_minimum_size = Vector2(214, 214)
	atlas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	atlas.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	atlas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	atlas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(atlas)
	map_caption = text(box, "白：精卫   橙：穿山甲", 12, MUTED)
	text(box, "浅海 10–100 / 格\n远海 100–5000 / 格\n深海 5000–50000 / 格", 12, MUTED)

func _build_bottom() -> void:
	var toast := panel(root, Rect2(-290, 104, 580, 0))
	notice_panel = toast.get_parent()
	notice_panel.anchor_left = 0.5
	notice_panel.anchor_right = 0.5
	notice_panel.offset_left = -290
	notice_panel.offset_right = 290
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice = text(toast, "", 14, INK, true)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_panel.visible = false
	var box := panel(root, Rect2(-310, -90, 620, 66), false, true)
	var parent: Control = box.get_parent()
	parent.anchor_left = 0.5
	parent.anchor_right = 0.5
	parent.offset_left = -310
	parent.offset_right = 310
	box.add_theme_constant_override("separation", 3)
	cell_label = text(box, "", 12, MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	context = text(row, "", 14)
	context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	interact_button = button(row, "采集  E", func() -> void: interact_requested.emit(), 32)
	throw_button = button(row, "投石  Q", func() -> void: throw_requested.emit(), 32)
	# Save feedback is available in the menu, not a permanent extra HUD label.
	save_label = text(root, "自动保存", 12, MUTED)
	save_label.visible = false

func _build_modal() -> void:
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.08, 0.14, 0.13, 0.56)
	modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)
	modal_box = panel(center, Rect2(0, 0, 500, 0))
	modal_box.get_parent().custom_minimum_size.x = 500
	modal_box.add_theme_constant_override("separation", 18)
	modal_title = text(modal_box, "", 24)
	modal_text = text(modal_box, "", 15, MUTED, true)
	modal_text.custom_minimum_size.x = 472
	modal_buttons = VBoxContainer.new()
	modal_buttons.add_theme_constant_override("separation", 8)
	modal_box.add_child(modal_buttons)
	modal.visible = false

func show_modal(title: String, body: String, choices: Array) -> void:
	modal_open = true
	modal.visible = true
	modal_title.text = title
	modal_text.text = body
	for child in modal_buttons.get_children():
		modal_buttons.remove_child(child)
		child.queue_free()
	for choice in choices:
		var action: String = choice["action"]
		button(modal_buttons, String(choice["text"]), func() -> void: modal_action.emit(action), 40)

func hide_modal() -> void:
	modal_open = false
	modal.visible = false

func notify(value: String) -> void:
	if notice_panel.visible and notice.text == value:
		return
	notice.text = value
	notification_time = 3.2
	notice_panel.modulate.a = 1.0
	notice_panel.visible = true

func _process(delta: float) -> void:
	if drawer.visible:
		# Wrapped labels can temporarily inflate the panel during its first layout.
		# Refit after containers settle, including when switching to the shorter tab.
		drawer.size.y = drawer.get_combined_minimum_size().y
	if notification_time <= 0:
		return
	notification_time = maxf(0, notification_time - delta)
	notice_panel.modulate.a = minf(1.0, notification_time / 0.3)
	if notification_time <= 0:
		notice_panel.visible = false

func show_world_picker(can_cancel: bool = false) -> void:
	var choices: Array = []
	for profile in State.PROFILES:
		choices.append({"text": "%s 石" % number(int(profile["target"])), "action": "world_%d" % profile["target"]})
	if can_cancel:
		choices.append({"text": "返回", "action": "resume"})
	show_modal("选择填海规模", "规模越大，海域越广，山也越多。", choices)

func toggle_drawer() -> void:
	if modal_open or overview:
		return
	drawer_open = not drawer_open
	drawer.visible = drawer_open

func select_tab(id: String) -> void:
	active_tab = id
	upgrade_page.visible = id == "upgrades"
	relic_page.visible = id == "relics"
	for key in tabs:
		tabs[key].set_pressed_no_signal(key == id)
	drawer.set_deferred("size", Vector2(278, 0))

func set_overview(enabled: bool) -> void:
	overview = enabled
	overview_panel.visible = enabled
	drawer.visible = drawer_open and not enabled
	drawer_button.disabled = enabled
	map_button.text = "返回  Tab" if enabled else "全图  Tab"

func update_state(state: JWState, prompt: String, aimed_cell: int, aimed_point: Vector2 = Vector2.INF, flight_height: float = State.BIRD_HOVER_HEIGHT) -> void:
	cargo.text = "%s / %s" % [number(state.carried), number(state.capacity())]
	cargo.add_theme_color_override("font_color", RUST if state.carried >= state.capacity() else INK)
	cultivation_label.text = number(state.cultivation)
	var percent := float(state.total_delivered) / state.target_stones * 100
	progress_label.text = "填海 %.2f%%" % percent
	goal.text = "%s / %s" % [number(state.total_delivered), number(state.target_stones)]
	total_bar.value = percent
	context.text = prompt
	var npc := state.nearby_mountain(state.player, 2.1, true)
	interact_button.text = "对话  E" if npc >= 0 else "采集  E"
	interact_button.disabled = npc < 0 and (state.carried >= state.capacity() or (state.nearby_pile(state.player) < 0 and state.closest_drop(state.player) < 0 and state.closest_stone(state.player) < 0))
	throw_button.disabled = state.carried == 0
	var near := state.next_mountain()
	if not state.mining_unlocked():
		mining_bar.value = float(state.total_delivered) / State.MINING_UNLOCK_STONES * 100
		mining_label.text = "开山解锁  %d / %d 石" % [state.total_delivered, State.MINING_UNLOCK_STONES]
	elif near < 0:
		mining_bar.value = 100
		mining_label.text = "山已挖完 · 石料待搬运"
	else:
		var mountain: Dictionary = state.mountains[near]
		mining_bar.value = float(mountain["work"]) / float(mountain["yield"]) * 100
		mining_label.text = "开采 %s  %.0f%%" % [state.mountain_name(near), mining_bar.value]
	if drawer.visible and active_tab == "relics":
		seen_relics = state.artifacts.size()
	tabs["relics"].text = "神器 · %d%s" % [state.artifacts.size(), " •" if state.artifacts.size() > seen_relics else ""]
	for index in range(3):
		var item: Dictionary = state.artifact_plan[index]
		var found := state.artifacts.has(String(item["id"]))
		relic_labels[index].text = "%s\n%s" % [item["name"], item["effect"]] if found else "未发现\n%s" % state.mountain_name(int(item["mountain"]))
		relic_labels[index].add_theme_color_override("font_color", INK if found else MUTED)
	for kind in upgrade_buttons:
		var target: Button = upgrade_buttons[kind]
		var detail: Dictionary = upgrade_details[kind]
		var price := state.upgrade_cost(kind)
		var level := int(state.upgrades[kind])
		var current := ""
		var next := ""
		match kind:
			"bag":
				current = number(state.capacity())
				next = number(int(floor(32 * pow(2.0, level + 1) * state.relic_factor())))
			"mining":
				current = number(state.gather_power())
				next = number(int(ceil(32 * pow(2.0, level + 1) * state.relic_factor() / 3.5)))
			"throw":
				current = "%.1f" % state.throw_distance()
				next = "%.1f" % State.THROW_DISTANCES[mini(level + 1, state.upgrade_limit("throw"))]
			"speed":
				current = "%.1f" % state.move_speed()
				next = "%.1f" % (state.move_speed() / (1.0 + 0.08 * level) * (1.0 + 0.08 * (level + 1)))
		var names := {"bag": "负重", "mining": "采集", "throw": "射程", "speed": "飞速"}
		detail["name"].text = "%s · %d 级" % [names[kind], level]
		detail["value"].text = "%s → %s" % [current, next] if price >= 0 else current
		var value_label: Label = detail["value"]
		var measured := value_label.get_theme_font("font").get_string_size(value_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		value_label.add_theme_font_size_override("font_size", clampi(floori(16 * 144 / maxf(144, measured)), 11, 16))
		detail["cost"].text = "%s\n修行" % number(price) if price >= 0 else "已满级"
		target.disabled = price < 0 or state.cultivation < price
		detail["cost"].add_theme_color_override("font_color", MUTED if target.disabled else ACCENT)
		detail["value"].add_theme_color_override("font_color", INK if not target.disabled else MUTED)
		target.tooltip_text = {"bag": "每次最多携带的石子数", "mining": "每次采集量，同时加快穿山甲开山", "throw": "基础水平射程；按住空格升高，最高可达 2 倍", "speed": "飞行速度"}[kind]
		if price >= 0 and state.cultivation < price:
			target.tooltip_text += "\n还需 %s 修行" % number(price - state.cultivation)
	overview_info.text = "%d × %d 格 · %d 座山" % [state.grid_size, state.grid_size, state.mountains.size()]
	_update_atlas(state)
	cell_label.visible = state.carried > 0 and aimed_cell >= 0
	if aimed_cell >= 0:
		var depth := state.sea_depth[aimed_cell]
		cell_label.text = "%s  %s / %s 石" % [State.DEPTH_NAMES[depth], number(state.sea_fill[aimed_cell]), number(state.sea_capacity[aimed_cell])] if depth >= 0 else "大陆 · 石子可拾回"
		if aimed_point.is_finite():
			cell_label.text += "   射程 %.1f" % state.throw_distance(flight_height)
			if not state.can_throw(aimed_point, flight_height):
				cell_label.text += " · 超距"

func _update_atlas(state: JWState) -> void:
	var mine_code := ""
	for mountain in state.mountains:
		mine_code += "2" if mountain["settled"] else ("1" if mountain["started"] else "0")
	var stamp := "%d:%d:%d:%s" % [state.target_stones, state.world_seed, state.total_delivered, mine_code]
	if stamp != atlas_stamp:
		atlas_stamp = stamp
		atlas_base = Image.create(state.grid_size, state.grid_size, false, Image.FORMAT_RGB8)
		for index in range(state.sea_depth.size()):
			var depth := state.sea_depth[index]
			var color := Color("84a572")
			if depth >= 0:
				color = [Color("66afa4"), Color("326d83"), Color("193c60")][depth]
				color = color.lerp(Color("dfc78b"), float(state.sea_fill[index]) / state.sea_capacity[index])
			atlas_base.set_pixel(index % state.grid_size, index / state.grid_size, color)
		for index in range(state.mountains.size()):
			var cell := state.cell_at(state.mountain_position(index))
			atlas_base.set_pixel(cell % state.grid_size, cell / state.grid_size, Color("c6b597") if state.mountains[index]["settled"] else Color("665746"))
	var image: Image = atlas_base.duplicate()
	var npc_cell := state.cell_at(state.npc_position(state.pangolin_mountain()))
	image.set_pixel(npc_cell % state.grid_size, npc_cell / state.grid_size, Color("ed9742"))
	var player_cell := state.cell_at(state.player)
	if player_cell >= 0:
		image.set_pixel(player_cell % state.grid_size, player_cell / state.grid_size, Color.WHITE)
	if atlas_texture == null or atlas_texture.get_width() != state.grid_size:
		atlas_texture = ImageTexture.create_from_image(image)
		atlas.texture = atlas_texture
	else:
		atlas_texture.update(image)
