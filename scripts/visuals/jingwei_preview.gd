extends Node3D
## Standalone art review: no state, simulation, audio or save file.
const BirdScene = preload("res://scenes/actors/jingwei.tscn")
const Models = preload("res://scripts/models.gd")
const CLIPS := ["idle", "fly", "turn_left", "turn_right", "gather", "carry_fly", "throw"]
const TITLES := ["待机", "飞行", "左转", "右转", "采石", "负重飞行", "投石"]
var bird: Node3D
var camera: Camera3D
var selected := 0
var clock := 0.0
var replay := 0.0
var stage := 0
var info: Label

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
	plane.size = Vector2.ONE * 12
	Models.mesh_part(self, plane, Models.material(Color("b9c8b2")), Vector3(0, -0.72, 0))
	bird = BirdScene.instantiate()
	add_child(bird)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.5
	camera.position = Vector3(3.4, 2.5, -5.5)
	add_child(camera)
	camera.look_at(Vector3(0, 0.1, 0))
	camera.current = true
	_build_controls()
	show_clip(0)

func _build_controls() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -112
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
	for index in range(CLIPS.size()):
		var button := Button.new()
		button.text = TITLES[index]
		button.pressed.connect(show_clip.bind(index))
		row.add_child(button)
	var cargo := Button.new()
	cargo.text = "切换负重"
	cargo.pressed.connect(cycle_load)
	row.add_child(cargo)

func show_clip(index: int) -> void:
	selected = index
	replay = 0
	bird.current_action = &""
	bird.animation_player.stop()
	if CLIPS[index] in ["gather", "throw"]:
		bird.play_gather(10) if CLIPS[index] == "gather" else bird.play_throw(10)
	else:
		bird._set_loop(StringName(CLIPS[index]))
		bird._play(StringName(CLIPS[index]), true)
	_update_info()

func cycle_load() -> void:
	stage = (stage + 1) % 3
	bird.set_load([0.0, 0.4, 1.0][stage])
	_update_info()

func _update_info() -> void:
	info.text = "精卫 · %s · %s　｜　拖动旋转 · 滚轮缩放 · 空格切换负重" % [TITLES[selected], ["空载", "轻载", "满载"][stage]]

func _process(delta: float) -> void:
	clock += delta
	replay += delta
	bird.advance(delta, clock)
	if CLIPS[selected] in ["gather", "throw"] and replay >= 1.4:
		show_clip(selected)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		bird.rotation.y += event.relative.x * 0.01
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size + (-0.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.25), 3, 8)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		cycle_load()
