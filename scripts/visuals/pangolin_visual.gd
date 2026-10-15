extends "res://scripts/visuals/actor_visual.gd"
const Models = preload("res://scripts/models.gd")
@export var surface_material: Material
@export var use_arrival_animation := false
var target_index := -1
var working := false
var finished := false
var unlocked := false
var progress := 0.0
var last_completed_target := -1
var arrival_remaining := 0.0

func _make_fallback() -> Node3D:
	return Models.pangolin()

func _model_changed() -> void:
	if surface_material:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = surface_material

func set_facing(direction: Vector2) -> void:
	if direction.length_squared() > 0.001:
		rotation.y = atan2(-direction.x, -direction.y)

func _work_loop() -> StringName:
	if finished:
		return &"finished"
	if working:
		return &"walk" if arrival_remaining > 0 else &"dig"
	if not unlocked and animation_player and animation_player.has_animation(_animation_name(&"locked")):
		return &"locked"
	return &"idle"

func set_work(target: int, active: bool, all_done: bool, fraction: float, is_unlocked: bool = true) -> void:
	if target_index >= 0 and target != target_index and active and use_arrival_animation:
		arrival_remaining = 0.35
	if not active:
		arrival_remaining = 0.0
	target_index = target
	working = active
	finished = all_done
	unlocked = is_unlocked
	progress = clampf(fraction, 0, 1)
	_set_loop(_work_loop())

func play_complete(completed_target: int) -> void:
	last_completed_target = completed_target
	_action(&"complete", 0.70)

func advance(delta: float, clock: float) -> void:
	var action_time: float = _remaining if current_action != &"" else 0.0
	_advance_animation(delta)
	if arrival_remaining > 0 and current_action == &"":
		arrival_remaining = maxf(0, arrival_remaining - maxf(0, delta - action_time))
		if arrival_remaining == 0:
			_set_loop(_work_loop())
	if not model_scene:
		rotation.x = sin(clock * 8) * 0.1 if working else 0.0
