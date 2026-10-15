extends "res://scripts/visuals/actor_visual.gd"
const Models = preload("res://scripts/models.gd")
@export var cargo_path: NodePath
var load_fraction := 0.0
var moving := false
var high_flight := false
var _cargo: Node3D

func _make_fallback() -> Node3D:
	var result := Models.bird()
	result.scale = Vector3.ONE * 1.15
	return result

func _model_changed() -> void:
	rotation.x = 0
	position.y = 0
	_cargo = model.get_node_or_null(cargo_path) if model_scene and not cargo_path.is_empty() else null
	if not model_scene:
		_cargo = model.get_node("Load")
	set_load(load_fraction)

func set_facing(direction: Vector2, delta: float) -> void:
	if direction.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.y), minf(1, delta * 12))

func set_load(fraction: float) -> void:
	load_fraction = clampf(fraction, 0, 1)
	if is_instance_valid(_cargo):
		_cargo.visible = load_fraction > 0

func set_motion(is_moving: bool, is_high: bool) -> void:
	moving = is_moving
	high_flight = is_high
	_set_loop(&"carry_fly" if load_fraction > 0 and (moving or high_flight) else (&"fly" if moving or high_flight else &"idle"))

func play_gather(amount: int) -> void:
	if amount > 0:
		_action(&"gather", 0.3)

func play_throw(amount: int) -> void:
	if amount > 0:
		_action(&"throw", 0.48)

func advance(delta: float, clock: float) -> void:
	_advance_animation(delta)
	if not model_scene:
		var flutter := sin(clock * (17.0 if moving or high_flight else 8.0)) * (0.65 if moving or high_flight else 0.18)
		model.get_node("WingLeft").rotation.z = flutter
		model.get_node("WingRight").rotation.z = -flutter
		rotation.x = lerpf(rotation.x, -0.12 if moving else 0.0, minf(1, delta * 8))
		position.y = sin(clock * 3.8) * 0.045
