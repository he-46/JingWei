@tool
extends Node3D
## Editor and F6 preview. Uses exactly the same generator as the game.
const Field = preload("res://scripts/mountain_field.gd")
@export var mountain_seed: int = 2817:
	set(value):
		mountain_seed = value
		_schedule()
@export_range(1024, 2000000, 64) var stones: int = 32768:
	set(value):
		stones = value
		_schedule()
@export_range(0, 1, .01) var mining_progress: float = 0.0:
	set(value):
		mining_progress = value
		_schedule()
var pending := false
var generated: Node3D

func _ready() -> void:
	_schedule()

func _schedule() -> void:
	if not is_inside_tree() or pending:
		return
	pending = true
	call_deferred("rebuild")

func rebuild() -> void:
	pending = false
	if is_instance_valid(generated):
		remove_child(generated)
		generated.queue_free()
	generated = Node3D.new()
	generated.name = "GeneratedPreview"
	add_child(generated)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = .93
	var spacing := maxf(6, minf(6.25, Field.UNIT * pow(ceili(float(stones) / Field.STONES_PER_CELL), 1.0 / 3.0) * 1.05) * 2 + 3)
	for style in range(4):
		var field = Field.generate(stones, mountain_seed, style, 6.5)
		var mesh := MeshInstance3D.new()
		mesh.mesh = field.surface(stones * mining_progress)
		mesh.material_override = material
		mesh.position = Vector3((style % 2) * spacing - spacing * .5, 0, (style / 2) * spacing - spacing * .5)
		generated.add_child(mesh)
		var label := Label3D.new()
		label.text = ["偏峰", "双峰", "曲折山脊", "台地"][style]
		label.position = mesh.position + Vector3(0, .2, field.radius + 1)
		label.font_size = 48
		label.pixel_size = .018
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("243730")
		label.outline_modulate = Color("f3eee0")
		generated.add_child(label)
	var camera := get_node_or_null("Camera") as Camera3D
	if camera:
		camera.size = spacing * 2.6
		camera.position = Vector3(1.2, 1.7, 2) * spacing
		camera.look_at(Vector3(0, 1, 0))

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_R:
		mountain_seed += 1
	elif event.keycode == KEY_RIGHT:
		mining_progress = minf(1, mining_progress + .1)
	elif event.keycode == KEY_LEFT:
		mining_progress = maxf(0, mining_progress - .1)
