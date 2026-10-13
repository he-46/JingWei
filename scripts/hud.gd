extends CanvasLayer

signal interact_requested
signal throw_requested
signal upgrade_requested(kind: String)
signal save_requested
signal menu_requested
signal overview_requested
signal modal_action(action: String)

const State = preload("res://scripts/state.gd")
const INK := Color("244641")
const MUTED := Color("6e8175")
const RUST := Color("b46643")

var root: Control
var cargo: Label
var cultivation_label: Label
var progress_label: Label
var goal: Label
var mining_label: Label
var mining_bar: ProgressBar
var context: Label
var notice: Label
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
var atlas_stamp: String = ""
var upgrade_buttons: Dictionary = {}
var modal: Control
var modal_box: VBoxContainer
var modal_title: Label
var modal_text: Label
var modal_buttons: VBoxContainer
var modal_open: bool = false
var notification_time: float = 0.0

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "SimHei"])
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", Color("f7edcf"))
	theme.set_color("font_disabled_color", "Button", Color("9b9c88"))
	theme.set_stylebox("normal", "Button", style(Color("e8e2cc"), 8))
	theme.set_stylebox("hover", "Button", style(Color("f5ecd4"), 8, Color("b9a782")))
	theme.set_stylebox("pressed", "Button", style(Color("4d7666"), 8))
	theme.set_stylebox("disabled", "Button", style(Color("dddccb"), 8))
	theme.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), 8, Color("b68549")))
	theme.set_stylebox("background", "ProgressBar", style(Color("d4d9c1"), 4))
	theme.set_stylebox("fill", "ProgressBar", style(Color("6c9272"), 4))
	root.theme = theme
	_build_header()
	_build_left()
	_build_right()
	_build_bottom()
	_build_modal()

static func style(color: Color, radius: int = 14, border: Color = Color("ccc7ae")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(1)
	box.border_color = border
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func panel(parent: Control, rect: Rect2, right: bool = false, bottom: bool = false) -> VBoxContainer:
	var box := PanelContainer.new()
	if right:
		box.anchor_left = 1.0
		box.anchor_right = 1.0
	if bottom:
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
	box.position = rect.position
	box.size = rect.size
	box.add_theme_stylebox_override("panel", style(Color(0.96, 0.94, 0.86, 0.96)))
	parent.add_child(box)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	box.add_child(layout)
	return layout

func text(parent: Node, value: String, size: int = 17, color: Color = INK, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func button(parent: Node, value: String, callback: Callable, height: float = 42) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = height
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func _build_header() -> void:
	var box := PanelContainer.new()
	box.anchor_right = 1
	box.offset_left = 24
	box.offset_right = -24
	box.offset_top = 20
	box.offset_bottom = 94
	box.add_theme_stylebox_override("panel", style(Color(0.97, 0.95, 0.88, 0.98)))
	root.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	box.add_child(row)
	var title := VBoxContainer.new()
	row.add_child(title)
	text(title, "精卫填海", 28)
	text(title, "衔 石 成 洲   /   海 岸 远 行", 11, MUTED)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	cargo = text(row, "石子  0 / 32", 18)
	cultivation_label = text(row, "修行  0", 18, RUST)
	progress_label = text(row, "填海  0%", 20)
	button(row, "保存", func() -> void: save_requested.emit(), 40)
	button(row, "全图 Tab", func() -> void: overview_requested.emit(), 40)
	button(row, "暂停  Esc", func() -> void: menu_requested.emit(), 40)

func _build_left() -> void:
	var box := panel(root, Rect2(24, 114, 260, 196))
	side_panels.append(box.get_parent())
	text(box, "一石一羽，终成陆地", 19)
	text(box, "此 行", 12, RUST)
	goal = text(box, "", 17, INK, true)
	var divider := HSeparator.new()
	box.add_child(divider)
	text(box, "填海只是精卫自己的心愿。\n修行记录一路的坚持。", 13, MUTED, true)
	box = panel(root, Rect2(24, 326, 260, 330))
	side_panels.append(box.get_parent())
	text(box, "修行 · 日益精进", 19)
	for kind in ["bag", "mining", "throw", "speed"]:
		var id: String = kind
		upgrade_buttons[id] = button(box, "", func() -> void: upgrade_requested.emit(id), 54)
		upgrade_buttons[id].add_theme_font_size_override("font_size", 14)
		for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
			var compact: StyleBoxFlat = root.theme.get_stylebox(style_name, "Button").duplicate()
			compact.content_margin_top = 6
			compact.content_margin_bottom = 6
			upgrade_buttons[id].add_theme_stylebox_override(style_name, compact)
	text(box, "同级采矿、负重：约 4 次装满。", 12, MUTED)
	box = panel(root, Rect2(24, 674, 260, 120))
	side_panels.append(box.get_parent())
	text(box, "穿山甲的开山工坊", 18)
	mining_label = text(box, "尚未接洽", 14, MUTED)
	mining_bar = ProgressBar.new()
	mining_bar.custom_minimum_size.y = 9
	mining_bar.show_percentage = false
	box.add_child(mining_bar)
	text(box, "一只穿山甲 · 从小山依次开采", 12, MUTED)

func _build_right() -> void:
	var box := panel(root, Rect2(-284, 114, 260, 302), true)
	side_panels.append(box.get_parent())
	text(box, "山海遗珍", 20)
	text(box, "开山寻宝 · 发现后自动装备", 12, MUTED)
	for index in range(3):
		var entry := PanelContainer.new()
		entry.add_theme_stylebox_override("panel", style(Color("e5e4d2"), 8))
		box.add_child(entry)
		var line := text(entry, "◇  未知神器\n    藏于不同山脉的岩层中", 13, MUTED, true)
		relic_labels.append(line)
	box = panel(root, Rect2(-284, 436, 260, 350), true)
	side_panels.append(box.get_parent())
	text(box, "山海图志", 19)
	map_caption = text(box, "", 12, MUTED)
	atlas = TextureRect.new()
	atlas.custom_minimum_size = Vector2(210, 185)
	atlas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	atlas.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	atlas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	atlas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(atlas)
	text(box, "绿：大陆  青：浅海  蓝：远海\n深蓝：深海  褐：山脉\n白：精卫  橙：穿山甲", 11, MUTED)
	cell_label = text(box, "", 12, MUTED, true)
	save_label = text(root, "每 15 秒自动保存", 12, Color("eaf1dc"))
	save_label.anchor_left = 1
	save_label.anchor_right = 1
	save_label.offset_left = -278
	save_label.offset_right = -24
	save_label.offset_top = 803
	save_label.offset_bottom = 829
	box = panel(root, Rect2(24, 114, 260, 335))
	overview_panel = box.get_parent()
	overview_panel.visible = false
	text(box, "全图 · 山海远行", 20)
	overview_info = text(box, "", 15, INK, true)
	text(box, "西侧大陆，东侧海域\n金色光点：精卫的位置", 14, MUTED, true)
	text(box, "每格所需石子\n浅海    10～100\n远海    100～5000\n深海    5000～50000", 16, INK, true)
	text(box, "仅金色射程圈内可投石\n雾区不可到达\nTab 返回随行视角", 14, MUTED, true)

func _build_bottom() -> void:
	var banner := panel(root, Rect2(320, -179, 800, 52), false, true)
	var parent: Control = banner.get_parent()
	parent.anchor_right = 1
	parent.offset_right = -320
	notice = text(banner, "先拾起脚边的石子，再去海边投下第一石。", 16)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var box := panel(root, Rect2(320, -116, 800, 55), false, true)
	parent = box.get_parent()
	parent.anchor_right = 1
	parent.offset_right = -320
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	context = text(row, "", 14)
	context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button(row, "拾取 / 对话  E", func() -> void: interact_requested.emit(), 32)
	button(row, "投石  Q", func() -> void: throw_requested.emit(), 32)
	var footer := text(root, "WASD / 方向键  移动     空格  高飞     E  拾取 / 对话     Q  向海投石     鼠标左键  射程内投石     Tab  全图     滚轮  缩放     M  静音", 13, Color("e9f0df"))
	footer.anchor_top = 1
	footer.anchor_bottom = 1
	footer.anchor_right = 1
	footer.offset_left = 24
	footer.offset_top = -40
	footer.offset_right = -24
	footer.offset_bottom = -12
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_modal() -> void:
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.08, 0.17, 0.17, 0.62)
	modal.add_child(shade)
	modal_box = panel(modal, Rect2(-260, -230, 520, 420))
	var parent: Control = modal_box.get_parent()
	parent.anchor_left = 0.5
	parent.anchor_right = 0.5
	parent.anchor_top = 0.5
	parent.anchor_bottom = 0.5
	modal_box.add_theme_constant_override("separation", 22)
	text(modal_box, "山 海 手 札", 12, RUST)
	modal_title = text(modal_box, "", 28)
	modal_text = text(modal_box, "", 17, INK, true)
	modal_text.custom_minimum_size.y = 130
	modal_buttons = VBoxContainer.new()
	modal_buttons.add_theme_constant_override("separation", 10)
	modal_box.add_child(modal_buttons)
	modal.visible = false

func show_modal(title: String, body: String, choices: Array) -> void:
	modal_open = true
	modal.visible = true
	var parent: Control = modal_box.get_parent()
	parent.offset_top = -240
	parent.offset_bottom = 240
	modal_text.custom_minimum_size.y = 130
	modal_title.text = title
	modal_text.text = body
	for child in modal_buttons.get_children():
		modal_buttons.remove_child(child)
		child.queue_free()
	for choice in choices:
		var action: String = choice["action"]
		button(modal_buttons, String(choice["text"]), func() -> void: modal_action.emit(action))

func hide_modal() -> void:
	modal_open = false
	modal.visible = false

func notify(value: String) -> void:
	notice.text = value
	notification_time = 7.0

func show_world_picker(can_cancel: bool = false) -> void:
	var choices: Array = []
	for profile in State.PROFILES:
		choices.append({"text": "%s   /   %d×%d · %d 座山" % [profile["name"], profile["grid"], profile["grid"], profile["mountains"]], "action": "world_%d" % profile["target"]})
	if can_cancel:
		choices.append({"text": "继续当前旅程", "action": "resume"})
	show_modal("你想填多大的一片海？", "向西是大陆与群山，向东是更广的海。\n选择这次心愿的大小，山海会随之展开。", choices)
	var parent: Control = modal_box.get_parent()
	parent.offset_top = -290
	parent.offset_bottom = 290
	modal_text.custom_minimum_size.y = 65

func set_overview(enabled: bool) -> void:
	overview_panel.visible = enabled
	for side in side_panels:
		side.visible = not enabled
	save_label.visible = not enabled

func update_state(state: JWState, prompt: String, aimed_cell: int, aimed_point: Vector2 = Vector2.INF) -> void:
	overview_info.text = "所愿：%s 石\n%d×%d 格 · %d 座山" % [State.number(state.target_stones), state.grid_size, state.grid_size, state.mountains.size()]
	cargo.text = "石子  %s / %s" % [State.number(state.carried), State.number(state.capacity())]
	cultivation_label.text = "修行  %s" % State.number(state.cultivation)
	progress_label.text = "填海  %.2f%%" % (float(state.total_delivered) / state.target_stones * 100)
	context.text = prompt
	goal.text = "所愿：%s 石\n已填：%s 石" % [State.number(state.target_stones), State.number(state.total_delivered)]
	if state.won:
		goal.text = "✓ 这次心愿已经完成。\n%s 石，从第一石开始。" % State.number(state.total_delivered)
	var near := state.next_mountain()
	if not state.mining_unlocked():
		mining_bar.value = float(state.total_delivered) / State.MINING_UNLOCK_STONES * 100
		mining_label.text = "开山之约 · 填海 %d / %d 石" % [state.total_delivered, State.MINING_UNLOCK_STONES]
	elif near < 0:
		mining_bar.value = 100
		mining_label.text = "群山已开尽 · 石料留在原地"
	else:
		var mountain: Dictionary = state.mountains[near]
		mining_bar.value = float(mountain["work"]) / float(mountain["yield"]) * 100
		mining_label.text = "%s · 开采 %.0f%%" % [state.mountain_name(near), mining_bar.value]
	for index in range(3):
		var item: Dictionary = state.artifact_plan[index]
		var found := state.artifacts.has(String(item["id"]))
		relic_labels[index].text = "◆  %s\n%s · 已装备" % [item["name"], item["effect"]] if found else "◇  未知神器\n藏于%s的岩层中" % state.mountain_name(int(item["mountain"]))
		relic_labels[index].add_theme_color_override("font_color", RUST if found else MUTED)
	for kind in upgrade_buttons:
		var target: Button = upgrade_buttons[kind]
		var price := state.upgrade_cost(kind)
		var level := int(state.upgrades[kind])
		var title := ""
		match kind:
			"bag":
				var next := int(floor(32 * pow(2.0, level + 1) * state.relic_factor()))
				title = "负重  %s → %s 石" % [State.number(state.capacity()), State.number(next)]
			"mining":
				var next := int(ceil(32 * pow(2.0, level + 1) * state.relic_factor() / 3.5))
				title = "采矿  %s → %s 石/次" % [State.number(state.gather_power()), State.number(next)]
			"throw":
				title = "投石  %.1f → %.1f 距离" % [state.throw_distance(), State.THROW_DISTANCES[mini(level + 1, state.upgrade_limit("throw"))]]
			"speed":
				title = "羽翼  %.1f → %.1f" % [state.move_speed(), state.move_speed() / (1.0 + 0.08 * level) * (1.0 + 0.08 * (level + 1))]
		target.text = "%s\n%s" % [title, "%s 修行 · %d 阶" % [State.number(price), level] if price >= 0 else "已修至满阶"]
		target.disabled = price < 0 or state.cultivation < price
		target.tooltip_text = "采矿同时提高每次采集量和穿山甲开山速度。\n负重与采矿配套提升，前期约 6–10 趟、后期约 18–24 趟进入下一阶；神器可加快修行。"
		if kind == "throw":
			target.tooltip_text = "投石射程按水平距离计算，鼠标、Q 和全图都遵守。\n当前地图射程上限 %.1f。" % State.THROW_DISTANCES[state.upgrade_limit("throw")]
	map_caption.text = "%d×%d 方形地图 · %d 座山" % [state.grid_size, state.grid_size, state.mountains.size()]
	_update_atlas(state)
	if aimed_cell >= 0:
		var depth := state.sea_depth[aimed_cell]
		if depth >= 0:
			cell_label.text = "%s  %s / %s 石\n已满格子的余石流向邻格" % [State.DEPTH_NAMES[depth], State.number(state.sea_fill[aimed_cell]), State.number(state.sea_capacity[aimed_cell])]
		else:
			cell_label.text = "大陆落点：留下可拾回的石堆\n填入海中的石子才计入修行"
	else:
		cell_label.text = "当前射程 %.1f · 雾区不可投石\nTab 全图 · 滚轮缩放" % state.throw_distance()

	if aimed_point.is_finite() and aimed_cell >= 0:
		cell_label.text += "\n距离 %.1f / 射程 %.1f%s" % [state.player.distance_to(aimed_point), state.throw_distance(), " · 超出" if not state.can_throw(aimed_point) else ""]

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
