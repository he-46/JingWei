extends "res://scripts/visuals/actor_visual.gd"
const Models = preload("res://scripts/models.gd")
@export var cargo_path: NodePath
@export var full_cargo_path: NodePath
@export var surface_material: Material
@export var use_turn_animation := false
var load_fraction := 0.0
var load_stage := 0
var moving := false
var high_flight := false
var _cargo: Node3D
var _full_cargo: Node3D
var _turn_amount := 0.0

func _make_fallback() -> Node3D:
	var result := Models.bird()
	result.scale = Vector3.ONE * 1.15
	return result

func _model_changed() -> void:
	rotation.x = 0
	position.y = 0
	_cargo = model.get_node_or_null(cargo_path) if model_scene and not cargo_path.is_empty() else null
	_full_cargo = model.get_node_or_null(full_cargo_path) if model_scene and not full_cargo_path.is_empty() else null
	if surface_material:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = surface_material
	if not model_scene:
		_cargo = model.get_node("Load")
	set_load(load_fraction)

func set_facing(direction: Vector2, delta: float) -> void:
	if direction.length_squared() > 0.001:
		var heading := atan2(-direction.x, -direction.y)
		_turn_amount = clampf(angle_difference(rotation.y, heading) / 0.7, -1, 1)
		rotation.y = lerp_angle(rotation.y, heading, minf(1, delta * 12))

func set_load(fraction: float) -> void:
	load_fraction = clampf(fraction, 0, 1)
	load_stage = 0 if load_fraction <= 0 else (1 if load_fraction <= 0.65 else 2)
	if is_instance_valid(_cargo):
		_cargo.visible = load_stage == 1 if is_instance_valid(_full_cargo) else load_stage > 0
	if is_instance_valid(_full_cargo):
		_full_cargo.visible = load_stage == 2

func set_motion(is_moving: bool, is_high: bool) -> void:
	moving = is_moving
	high_flight = is_high
	var loop: StringName = &"carry_fly" if load_stage > 0 and (moving or high_flight) else (&"fly" if moving or high_flight else &"idle")
	if use_turn_animation and moving and absf(_turn_amount) > 0.22:
		loop = &"turn_left" if _turn_amount > 0 else &"turn_right"
	_set_loop(loop)

func play_gather(amount: int) -> void:
	if amount > 0:
		_action(&"gather", 0.42)

func play_throw(amount: int) -> void:
	if amount > 0:
		_action(&"throw", 0.48)

func advance(delta: float, clock: float) -> void:
	_advance_animation(delta)
	if use_turn_animation:
		model.rotation.z = lerpf(model.rotation.z, -_turn_amount * 0.18, minf(1, delta * 10))
		_turn_amount = move_toward(_turn_amount, 0, delta * 4)
	if not model_scene:
		var flutter := sin(clock * (17.0 if moving or high_flight else 8.0)) * (0.65 if moving or high_flight else 0.18)
		model.get_node("WingLeft").rotation.z = flutter
		model.get_node("WingRight").rotation.z = -flutter
		rotation.x = lerpf(rotation.x, -0.12 if moving else 0.0, minf(1, delta * 8))
		position.y = sin(clock * 3.8) * 0.045
