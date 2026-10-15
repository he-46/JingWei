extends "res://scripts/visuals/actor_visual.gd"
const Models = preload("res://scripts/models.gd")
var target_index := -1
var working := false
var finished := false
var progress := 0.0
var last_completed_target := -1

func _make_fallback() -> Node3D:
	return Models.pangolin()

func set_work(target: int, active: bool, all_done: bool, fraction: float) -> void:
	target_index = target
	working = active
	finished = all_done
	progress = clampf(fraction, 0, 1)
	_set_loop(&"dig" if working else (&"finished" if finished else &"idle"))

func play_complete(completed_target: int) -> void:
	last_completed_target = completed_target
	_action(&"complete", 0.5)

func advance(delta: float, clock: float) -> void:
	_advance_animation(delta)
	if not model_scene:
		rotation.x = sin(clock * 8) * 0.1 if working else 0.0
