extends Node3D
## Art-only six-stage turntable; value snapshots, no journey/save/production access.
const Models = preload("res://scripts/models.gd")
const MountainVisual = preload("res://scripts/visuals/mountain_visual.gd")
const STAGES := ["完整 0%", "开采 25%", "开采 50%", "开采 75%", "完工石料", "搬空遗迹"]
var model_root: Node3D
var mountain_mesh: MultiMesh
var pile_mesh: MultiMesh
var camera: Camera3D
var info: Label
var progress_slider: HSlider
var stock_slider: HSlider
var visual = MountainVisual.new()

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var config := Environment.new()
	config.background_mode = Environment.BG_COLOR
	config.background_color = Color("dce5dc")
	config.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	config.ambient_light_color = Color("c6dfd5")
	config.ambient_light_energy = 0.28
	environment.environment = config
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -25, 0)
	light.light_color = Color("fff1ce")
	light.light_energy = 0.7
	light.shadow_enabled = true
	add_child(light)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 25
	Models.mesh_part(self, plane, Models.material(Color("b9c8b2")), Vector3(0, -0.015, 0))
	model_root = Node3D.new()
	add_child(model_root)
	visual.radius = 3.0
	visual.height = 6.75
	visual.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(3, 6.75, 3)), Vector3.ZERO)
	mountain_mesh = make_batch(preload("res://assets/models/environment/strata_mountain.glb"), 1, preload("res://assets/materials/strata_mountain.tres"), true)
	var site := make_batch(preload("res://assets/models/environment/quarry_site.glb"), 1, preload("res://assets/materials/quarry_site.tres"))
	site.set_instance_transform(0, visual.transform)
	pile_mesh = make_batch(preload("res://assets/models/environment/quarry_stone.glb"), 32, preload("res://assets/materials/quarry_stone.tres"))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.5
	camera.position = Vector3(10, 13, 16)
	add_child(camera)
	camera.look_at(Vector3(0, 2.2, 0))
	camera.current = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -155
	panel.offset_left = 20
	panel.offset_right = -20
	panel.offset_bottom = -20
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	info = Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	for index in range(STAGES.size()):
		var button := Button.new()
		button.text = STAGES[index]
		button.pressed.connect(show_stage.bind(index))
		row.add_child(button)
	progress_slider = HSlider.new()
	progress_slider.max_value = 1
	progress_slider.step = 0.001
	progress_slider.value_changed.connect(func(value: float) -> void: set_values(value, stock_slider.value))
	column.add_child(progress_slider)
	stock_slider = HSlider.new()
	stock_slider.max_value = 1
	stock_slider.step = 0.001
	stock_slider.value = 1
	stock_slider.value_changed.connect(func(value: float) -> void: set_values(progress_slider.value, value))
	column.add_child(stock_slider)
	show_stage(0)

func make_batch(scene: PackedScene, count: int, mat: Material, custom: bool = false) -> MultiMesh:
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.use_custom_data = custom
	mesh.mesh = MountainVisual.imported_mesh(scene)
	mesh.instance_count = count
	for index in range(count):
		mesh.set_instance_color(index, Color.WHITE)
	var node := MultiMeshInstance3D.new()
	node.multimesh = mesh
	node.material_override = mat
	model_root.add_child(node)
	return mesh

func show_stage(index: int) -> void:
	set_values(minf(index * 0.25, 1.0), 0.0 if index == 5 else 1.0)

func set_values(progress: float, fraction: float) -> void:
	visual.progress = clampf(progress, 0, 1)
	visual.remaining = 1.0 - visual.progress
	visual.settled = progress >= 1
	visual.stock_fraction = clampf(fraction, 0, 1) if visual.settled else 0.0
	visual.stock = ceili(1024 * visual.stock_fraction)
	var transform: Transform3D = visual.transform
	if visual.settled:
		transform.origin.y = -100
	mountain_mesh.set_instance_transform(0, transform)
	mountain_mesh.set_instance_custom_data(0, Color(visual.remaining, 0, 0, 1))
	for part in range(32):
		pile_mesh.set_instance_transform(part, MountainVisual.pile_transform(visual, part))
	progress_slider.set_value_no_signal(visual.progress)
	stock_slider.set_value_no_signal(fraction)
	stock_slider.editable = visual.settled
	info.text = "%s · 开采 %.1f%% · 库存 %.1f%%　｜　上：开采　下：库存　拖动旋转 · 滚轮缩放" % [visual.stage_name(), progress * 100, visual.stock_fraction * 100]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		model_root.rotation.y += event.relative.x * 0.01
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size + (-0.5 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.5), 8, 20)
