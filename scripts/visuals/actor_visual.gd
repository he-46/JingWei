extends Node3D
## Presentation only. The caller advances animation on the simulation clock.
@export var model_scene: PackedScene
@export var animation_names: Dictionary = {}
@export_range(0.0, 0.3) var blend_seconds := 0.0
var model: Node3D
var animation_player: AnimationPlayer
var current_action: StringName = &""
var _loop: StringName = &"idle"
var _remaining := 0.0

func _ready() -> void:
	replace_model(model_scene)

func _make_fallback() -> Node3D:
	return Node3D.new()

func replace_model(scene: PackedScene) -> void:
	# Actor scenes contain their default model so the editor can display it.
	# Adopt that instance once; subsequent swaps retain the existing API.
	var authored := get_node_or_null("Model") if not is_instance_valid(model) and scene == model_scene else null
	if authored != null and (scene == null or authored.scene_file_path != scene.resource_path):
		remove_child(authored)
		authored.queue_free()
		authored = null
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	model_scene = scene
	model = authored if authored else (scene.instantiate() if scene else _make_fallback())
	if model.get_parent() == null:
		add_child(model)
	animation_player = null
	# Imported hierarchy names are not part of the gameplay contract.
	for child in model.find_children("*", "AnimationPlayer", true, false):
		animation_player = child
		break
	current_action = &""
	_remaining = 0.0
	if animation_player:
		animation_player.stop()
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_model_changed()
	_play(_loop, true)

func _model_changed() -> void:
	pass

func _animation_name(key: StringName) -> StringName:
	return StringName(animation_names.get(String(key), String(key)))

func _play(key: StringName, looped: bool, speed: float = 1.0, blend: float = -1.0) -> void:
	if not animation_player:
		return
	var clip := _animation_name(key)
	if not animation_player.has_animation(clip):
		return
	# Duplicate before changing playback metadata: imported resources are shared.
	var animation := animation_player.get_animation(clip)
	if animation.loop_mode != (Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE):
		var library := animation_player.get_animation_library(clip.get_slice("/", 0) if "/" in clip else "")
		var local_name := clip.get_slice("/", 1) if "/" in clip else String(clip)
		animation = animation.duplicate()
		animation.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
		library = library.duplicate()
		library.remove_animation(local_name)
		library.add_animation(local_name, animation)
		var library_name := clip.get_slice("/", 0) if "/" in clip else ""
		animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, library)
	animation_player.play(clip, blend_seconds if blend < 0 else blend, speed)
	animation_player.advance(0)

func _set_loop(key: StringName) -> void:
	if _loop == key:
		return
	_loop = key
	if current_action == &"":
		_play(key, true)

func _action(key: StringName, duration: float) -> void:
	current_action = key
	_remaining = duration
	if animation_player:
		var clip := _animation_name(key)
		if animation_player.has_animation(clip):
			var length := animation_player.get_animation(clip).length
			_remaining = duration if duration > 0 else length
			animation_player.stop()
			_play(key, false, length / maxf(_remaining, 0.001), 0.0)

func _advance_animation(delta: float) -> void:
	if animation_player:
		animation_player.advance(delta)
	if current_action != &"":
		_remaining -= delta
		if _remaining <= 0.0:
			current_action = &""
			_play(_loop, true)
