extends Node3D
## Art-only stage: no simulation, resource settlement, dialogue or save access.
const Models = preload("res://scripts/models.gd")
const Actor = preload("res://scenes/actors/pangolin.tscn")
const CLIPS := ["idle", "locked", "walk", "dig", "complete", "finished"]
const TITLES := ["待机", "尚未解锁", "移动", "挖掘", "完工", "全部挖完"]
var animal: Node3D
var camera: Camera3D
var selected := 0
var clock := 0.0
var replay := 0.0
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
	Models.mesh_part(self, plane, Models.material(Color("b9c8b2")), Vector3(0, -0.015, 0))
	animal = Actor.instantiate()
	add_child(animal)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.7
	camera.position = Vector3(4.5, 3.4, -5.5)
	add_child(camera)
	camera.look_at(Vector3(0, 0.40, 0.25))
	camera.current = true
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
	show_clip(0)

func show_clip(index: int) -> void:
	selected = index
	replay = 0
	animal.current_action = &""
	animal.animation_player.stop()
	if CLIPS[index] == "complete":
		animal.play_complete(0)
	else:
		animal._set_loop(StringName(CLIPS[index]))
		animal._play(StringName(CLIPS[index]), true)
	info.text = "穿山甲 · %s　｜　拖动旋转 · 滚轮缩放" % TITLES[index]

func _process(delta: float) -> void:
	clock += delta
	replay += delta
	animal.advance(delta, clock)
	if CLIPS[selected] == "complete" and replay >= 1.6:
		show_clip(selected)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		animal.rotation.y += event.relative.x * 0.01
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size + (-0.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.25), 3, 8)
