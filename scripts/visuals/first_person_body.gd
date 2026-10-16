extends Node3D
## Camera-local presentation only. Gameplay owns all collection and deposit amounts.
const Models = preload("res://scripts/models.gd")
var wings: Array[Node3D] = []
var cargo: Node3D
var clock := 0.0
var action := ""
var remaining := 0.0
var load_fraction := 0.0

func _ready() -> void:
	var colors := [Color("305f70"), Color("477d88"), Color("fff0ca"), Color("da684d")]
	var materials: Array[StandardMaterial3D] = []
	for color in colors:
		var mat := Models.material(color)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.render_priority = 10
		materials.append(mat)
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		add_child(wing)
		wings.append(wing)
		for i in range(6):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			var root_point := Vector3(side * .12, -.02, 0)
			var tip := Vector3(side * (.38 + i * .052), .13 - i * .054, -.025)
			var middle := root_point.lerp(tip, .6)
			var ridge := middle + Vector3(0, 0, .025)
			var edge: Array[Vector3] = [root_point, middle + Vector3(0, .038, 0), tip + Vector3(side * .08, 0, 0), middle - Vector3(0, .038, 0)]
			for k in range(4):
				for p in [edge[k], edge[(k + 1) % 4], ridge]:
					tool.add_vertex(p)
			tool.generate_normals()
			var feather := Models.mesh_part(wing, tool.commit(), materials[i % 4], Vector3.ZERO)
			feather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cargo = Node3D.new()
	add_child(cargo)
	var stone_mat := Models.material(Color("afa28a"))
	stone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stone_mat.no_depth_test = true
	stone_mat.render_priority = 11
	for i in range(3):
		var stone := Models.mesh_part(cargo, Models.rock_mesh(i), stone_mat, Vector3(i * .055, i * .018, -i * .012), Vector3.ONE * .12)
		stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hide()

func play(kind: String, amount: int) -> void:
	if visible and amount > 0:
		action = kind
		remaining = .48 if kind == "throw" else .42

func update_view(enabled: bool, fraction: float, flying: bool, fov: float, delta: float) -> void:
	visible = enabled
	load_fraction = clampf(fraction, 0, 1)
	if not enabled:
		action = ""
		remaining = 0
		return
	clock += delta
	remaining = maxf(0, remaining - delta)
	if remaining == 0:
		action = ""
	# Keep the silhouette in the same screen region across the user's FOV range.
	var framing := tan(deg_to_rad(fov * .5)) / tan(deg_to_rad(75.0 * .5))
	scale = Vector3(framing, framing, 1)
	var flutter := sin(clock * (9 if flying else 3)) * (.055 if flying else .012)
	var gesture := sin(remaining / (.48 if action == "throw" else .42) * PI) if remaining > 0 else 0.0
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		wings[i].position = Vector3(side * .36, -.49 + flutter + gesture * .065, -1)
		wings[i].rotation.z = side * (-.12 + flutter + gesture * .16)
	cargo.position = Vector3(.52, -.48 + flutter - gesture * .10, -.98)
	cargo.visible = load_fraction > 0 and action != "throw"
	for i in range(3):
		cargo.get_child(i).visible = i == 0 or load_fraction > float(i) / 3

func launch_position() -> Vector3:
	return global_transform * Vector3(.52, -.40, -1.05)
