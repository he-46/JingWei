extends Node3D
## Camera-local presentation only. Gameplay owns all collection and deposit amounts.
const Models = preload("res://scripts/models.gd")
var wings: Array[Node3D] = []
var cargo: Node3D
var clock := 0.0
var action := ""
var remaining := 0.0
var load_fraction := 0.0
var flight_blend := 0.0

# Curved feather vanes with baked facet shading. Each feather has
# a broad vane and a narrow tip; they overlap along an actual wing, not one fan pivot.
func _feather(tool: SurfaceTool, start: Vector3, end: Vector3, width: float, color: Color, side: float) -> void:
	var axis := (end - start).normalized()
	var across := Vector3(-axis.y, axis.x, 0).normalized()
	var rings: Array[PackedVector3Array] = []
	var profile := [.28, .82, 1.0, .94, .68, .30, .025]
	for j in range(7):
		var t := float(j) / 6
		var center := start.lerp(end, t) + Vector3(side * sin(t * PI) * .025, sin(t * PI) * .025, sin(t * PI) * .032)
		var ring := PackedVector3Array()
		for k in range(8):
			var angle := TAU * k / 8
			ring.append(center + across * cos(angle) * width * profile[j] + Vector3(0, 0, sin(angle) * width * .30 * profile[j]))
		rings.append(ring)
	for j in range(6):
		# Only the camera-facing vane is needed. With depth testing disabled,
		# an underside would paint through this surface and create triangle noise.
		for k in range(4):
			var next := (k + 1) % 8
			var shade := color.lightened(.12 * maxf(0, sin(TAU * (k + .5) / 8)))
			shade = shade.darkened(.16 * float(j) / 6)
			var points := [rings[j][k], rings[j + 1][k], rings[j + 1][next], rings[j][k], rings[j + 1][next], rings[j][next]]
			for p in points:
				tool.set_color(shade)
				tool.add_vertex(p)

func _wing_mesh(side: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Outer shoulder stays outside the frame. Long primaries sweep inward/forward;
	# shorter coverts overlap their roots and form a continuous curved leading edge.
	for i in range(9):
		var t := float(i) / 8
		_feather(tool, Vector3(side * (.37 + t * .24), -.20 - t * .065, -.02), Vector3(side * (.02 + t * .52), .14 + sin(t * PI) * .12 - t * .14, .025), .042 + t * .007, Color("284f61").lerp(Color("477c89"), t * .65), side)
	for i in range(7):
		var t := float(i) / 6
		_feather(tool, Vector3(side * (.53 + t * .16), -.29, .02), Vector3(side * (.18 + t * .36), .065 - t * .24, .065), .050, Color("55838b").lerp(Color("739b9d"), t * .65), side)
	for i in range(5):
		var t := float(i) / 4
		_feather(tool, Vector3(side * (.57 + t * .11), -.30, .055), Vector3(side * (.34 + t * .25), -.08 - t * .12, .10), .044, Color("9fae9f").lerp(Color("d0cbb1"), t * .6), side)
	# A small warm shoulder accent, not alternating bright stripes on every feather.
	for i in range(3):
		_feather(tool, Vector3(side * .65, -.30, .085), Vector3(side * (.48 + i * .055), -.18 - i * .025, .13), .032, Color("a2644e"), side)
	tool.generate_normals()
	return tool.commit()

func _ready() -> void:
	var mat := Models.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		add_child(wing)
		wings.append(wing)
		var mesh := Models.mesh_part(wing, _wing_mesh(side), mat, Vector3.ZERO)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	flight_blend = move_toward(flight_blend, 1.0 if flying else 0.0, delta * 3)
	var flutter := sin(clock * 5.5) * lerpf(.008, .045, flight_blend)
	var gesture := sin(remaining / (.48 if action == "throw" else .42) * PI) if remaining > 0 else 0.0
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		wings[i].position = Vector3(side * .46, -.43 + flutter + gesture * .025, -1)
		wings[i].rotation.z = side * (-.04 + flutter * .8 + gesture * .07)
		wings[i].rotation.x = flutter * 1.4
	cargo.position = Vector3(.52, -.48 + flutter - gesture * .10, -.98)
	cargo.visible = load_fraction > 0 and action != "throw"
	for i in range(3):
		cargo.get_child(i).visible = i == 0 or load_fraction > float(i) / 3

func launch_position() -> Vector3:
	return global_transform * Vector3(.52, -.40, -1.05)
