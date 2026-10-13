extends Node3D

const State = preload("res://scripts/state.gd")
const Models = preload("res://scripts/models.gd")
const CHUNK := 8
const ROCKS_PER_MOUNTAIN := 32

var camera: Camera3D
var bird_body: CharacterBody3D
var bird_model: Node3D
var stone_mesh: MultiMesh
var mountain_mesh: MultiMesh
var pile_mesh: MultiMesh
var drop_mesh: MultiMesh
var mountain_collisions: Array[CollisionShape3D] = []
var mountain_cache: Array[int] = []
var pile_cache: Array[int] = []
var mountain_local: Array[Transform3D] = []
var terrain_chunks: Dictionary = {}
var npc_views: Dictionary = {}
var cell_marker: MeshInstance3D
var pickup_marker: MeshInstance3D
var shadow: MeshInstance3D
var overview_marker: MeshInstance3D
var font: SystemFont
var time: float = 0
var overview: bool = false
var zoom: float = 1.0
var focus := Vector3.ZERO
var normal_size: float = 29.0
var camera_offset := Vector3(16, 29, 27)
var depth_labels: Array[Label3D] = []

func setup(state: JWState) -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "SimHei"])
	normal_size = 29.0 * pow(state.map_side / 48.0, 0.22)
	focus = Vector3(state.player.x, 0, state.player.y)
	_build_lighting(state)
	_build_land(state)
	_build_decor(state)
	_build_resources(state)
	bird_body = CharacterBody3D.new()
	bird_body.position = Vector3(state.player.x, 1.45, state.player.y)
	bird_body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := SphereShape3D.new()
	shape.radius = 0.32
	var collider := CollisionShape3D.new()
	collider.shape = shape
	bird_body.add_child(collider)
	bird_model = Models.bird()
	bird_model.scale = Vector3.ONE * 1.15
	bird_body.add_child(bird_model)
	add_child(bird_body)
	shadow = disc(Color(0.10, 0.18, 0.15, 0.22), 0.52)
	add_child(shadow)
	overview_marker = disc(Color("ffe3a0"), 0.65)
	overview_marker.visible = false
	add_child(overview_marker)
	cell_marker = ring(Color("f3d491"), State.CELL_SIZE * 0.43, 0.035)
	add_child(cell_marker)
	cell_marker.visible = false
	pickup_marker = ring(Color("fff1bd"), 0.64, 0.035)
	add_child(pickup_marker)
	sync(state)
	update_camera(state, 1.0, true)

func _build_lighting(state: JWState) -> void:
	var environment := WorldEnvironment.new()
	var config := Environment.new()
	config.background_mode = Environment.BG_COLOR
	config.background_color = Color("96bcba")
	config.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	config.ambient_light_color = Color("c6dfd5")
	config.ambient_light_energy = 0.28
	config.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = config
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -25, 0)
	light.light_color = Color("fff1ce")
	light.light_energy = 0.7
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 90.0
	add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = normal_size
	camera.far = state.map_side * 5 + 200
	add_child(camera)
	camera.current = true

func _build_land(state: JWState) -> void:
	var water := PlaneMesh.new()
	water.size = Vector2.ONE * state.map_side * 5
	var water_mat := ShaderMaterial.new()
	water_mat.shader = preload("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("shallow_end", int(state.bands[0]) * State.CELL_SIZE)
	water_mat.set_shader_parameter("far_end", (int(state.bands[0]) + int(state.bands[1])) * State.CELL_SIZE)
	water_mat.set_shader_parameter("sea_end", (state.grid_size - state.land_cols) * State.CELL_SIZE)
	Models.mesh_part(self, water, water_mat, Vector3(0, 0.16, 0))
	# Mainland continues west/north/south beyond the square journey boundary.
	var land := PlaneMesh.new()
	land.size = Vector2(state.map_side * 3, state.map_side * 5)
	Models.mesh_part(self, land, Models.material(Color("89a77b")), Vector3(-state.map_side * 1.5, 0.44, 0))
	var beach := PlaneMesh.new()
	beach.size = Vector2(0.9, state.map_side * 5)
	Models.mesh_part(self, beach, Models.material(Color("d9cba4")), Vector3(-0.35, 0.455, 0))
	var xmin := state.map_origin.x
	var xmax := xmin + state.map_side
	var zmin := state.map_origin.y
	var zmax := zmin + state.map_side
	var border_color := Color("c8c39a")
	var border_width := maxf(0.06, state.map_side * 0.0015)
	Models.box(self, Vector3((xmin + xmax) / 2, 0.5, zmin), Vector3(state.map_side, 0.025, border_width), border_color)
	Models.box(self, Vector3((xmin + xmax) / 2, 0.5, zmax), Vector3(state.map_side, 0.025, border_width), border_color)
	Models.box(self, Vector3(xmin, 0.5, 0), Vector3(border_width, 0.025, state.map_side), border_color)
	Models.box(self, Vector3(xmax, 0.23, 0), Vector3(border_width, 0.025, state.map_side), border_color)
	var band_start := 0.0
	for depth in range(3):
		var width := int(state.bands[depth]) * State.CELL_SIZE
		var caption := "%s\n%d～%d 石/格" % [State.DEPTH_NAMES[depth], State.DEPTH_MIN[depth], State.DEPTH_MAX[depth]]
		var node := label(caption, Vector3(band_start + width / 2, 0.4, zmin + state.map_side * 0.055), Color("e5ead3"), 40)
		depth_labels.append(node)
		band_start += width

func _build_decor(state: JWState) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = state.world_seed + 980
	var grass_shape := CylinderMesh.new()
	grass_shape.bottom_radius = 0.065
	grass_shape.top_radius = 0
	grass_shape.height = 0.28
	grass_shape.radial_segments = 3
	var grass := batch(grass_shape, mini(2500, state.grid_size * 40), true, Color.WHITE)
	for index in range(grass.instance_count):
		var p := Vector3(rng.randf_range(state.map_origin.x, -1), 0.56, rng.randf_range(state.map_origin.y, -state.map_origin.y))
		grass.set_instance_transform(index, Transform3D(Basis.IDENTITY, p))
		grass.set_instance_color(index, Color("6f905c") if index % 4 else Color("d7c58d"))
	# Distant trees use instancing; no per-tree scripts or animation nodes.
	var tree_shape := CylinderMesh.new()
	tree_shape.bottom_radius = 0.8
	tree_shape.top_radius = 0
	tree_shape.height = 2.8
	tree_shape.radial_segments = 7
	var trees := batch(tree_shape, mini(320, state.grid_size * 4), true, Color.WHITE)
	for index in range(trees.instance_count):
		var p := Vector3(rng.randf_range(state.map_origin.x + 1, -3), 1.84, rng.randf_range(state.map_origin.y + 1, -state.map_origin.y - 1))
		trees.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.7, 1.2)), p))
		trees.set_instance_color(index, Color("477d60") if index % 2 else Color("67946b"))

func batch(mesh: Mesh, count: int, colors: bool, color: Color) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_3D
	result.use_colors = colors
	result.mesh = mesh
	result.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.multimesh = result
	var mat := Models.material(color)
	mat.vertex_color_use_as_albedo = colors
	node.material_override = mat
	add_child(node)
	return result

func _build_resources(state: JWState) -> void:
	stone_mesh = batch(Models.rock_mesh(), state.stone_positions.size() * 3, true, Color.WHITE)
	mountain_mesh = batch(Models.rock_mesh(3), state.mountains.size() * ROCKS_PER_MOUNTAIN, true, Color.WHITE)
	pile_mesh = batch(Models.rock_mesh(4), state.mountains.size() * ROCKS_PER_MOUNTAIN, false, Color("b8b6a6"))
	drop_mesh = batch(Models.rock_mesh(1), 0, false, Color("e1d3ad"))
	for layer in range(4):
		var count := 11 - layer * 2
		for index in range(count):
			var angle := float(index) / count * TAU + layer * 0.6
			var radius := 2.1 - layer * 0.55
			var p := Vector3(cos(angle) * radius, 1.2 + layer * 1.45, sin(angle) * radius)
			var scale_value := Vector3(2.2, 2.1, 2.4) * (1.0 - layer * 0.08)
			mountain_local.append(Transform3D(Basis.from_euler(Vector3(0, angle, 0)).scaled(scale_value), p))
	for index in range(state.mountains.size()):
		mountain_cache.append(-1)
		pile_cache.append(-1)
		var body := StaticBody3D.new()
		var point := state.mountain_position(index)
		body.position = Vector3(point.x, 0.44, point.y)
		add_child(body)
		var shape := CylinderShape3D.new()
		shape.radius = 2.9
		shape.height = 6.5
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = 3.25
		body.add_child(collider)
		mountain_collisions.append(collider)

func sync(state: JWState) -> void:
	for index in state.stone_dirty:
		var point := state.stone_positions[index]
		for pebble in range(3):
			var location := Vector3(point.x + (pebble - 1) * 0.28, 0.57, point.y + sin(index + pebble) * 0.18)
			if state.stone_amounts[index] == 0:
				location.y = -40
			var scale_value := 0.4 + pebble * 0.09
			stone_mesh.set_instance_transform(index * 3 + pebble, Transform3D(Basis.from_euler(Vector3(0, index + pebble, 0)).scaled(Vector3.ONE * scale_value), location))
			stone_mesh.set_instance_color(index * 3 + pebble, Color("ded4b9") if pebble % 2 else Color("a7b1a3"))
	state.stone_dirty.clear()
	for index in range(state.mountains.size()):
		var mountain: Dictionary = state.mountains[index]
		var ratio := 1.0 - float(mountain["work"]) / float(mountain["yield"])
		var count := int(ceil(ROCKS_PER_MOUNTAIN * ratio))
		if mountain_cache[index] != count:
			mountain_cache[index] = count
			var point := state.mountain_position(index)
			for part in range(ROCKS_PER_MOUNTAIN):
				var transform := mountain_local[part]
				transform.origin += Vector3(point.x, 0, point.y)
				if part >= count:
					transform.origin.y = -60
				mountain_mesh.set_instance_transform(index * ROCKS_PER_MOUNTAIN + part, transform)
				mountain_mesh.set_instance_color(index * ROCKS_PER_MOUNTAIN + part, Color("8c9e91") if part % 3 else Color("a5b09a"))
			var collider := mountain_collisions[index]
			collider.set_deferred("disabled", count == 0)
			collider.scale.y = maxf(0.05, ratio)
			collider.position.y = 3.25 * ratio
		var stock := int(mountain["stock"])
		if pile_cache[index] != stock:
			pile_cache[index] = stock
			var fraction := float(stock) / float(mountain["yield"])
			var point := state.pile_position(index)
			for part in range(ROCKS_PER_MOUNTAIN):
				var angle := part * 2.39996
				var radius := sqrt(float(part) / ROCKS_PER_MOUNTAIN) * 2.5
				var location := Vector3(point.x + cos(angle) * radius, 0.6 + (1.0 - radius / 2.6) * fraction * 1.4, point.y + sin(angle) * radius)
				if part >= ceili(fraction * ROCKS_PER_MOUNTAIN):
					location.y = -50
				pile_mesh.set_instance_transform(index * ROCKS_PER_MOUNTAIN + part, Transform3D(Basis.from_euler(Vector3(0, angle, 0)).scaled(Vector3.ONE * (0.6 + (part % 4) * 0.12)), location))
	if state.piles_dirty:
		drop_mesh.instance_count = state.land_piles.size() * 3
		var cursor := 0
		for key in state.land_piles:
			var point := state.cell_center(int(key))
			for part in range(3):
				drop_mesh.set_instance_transform(cursor, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.6), Vector3(point.x + (part - 1) * 0.45, 0.65, point.y + sin(part) * 0.4)))
				cursor += 1
		state.piles_dirty = false
	var dirty_chunks: Dictionary = {}
	for index in state.sea_dirty:
		var col: int = index % state.grid_size
		var row: int = index / state.grid_size
		for x in range(maxi(state.land_cols, col - 1), mini(state.grid_size, col + 2)):
			for z in range(maxi(0, row - 1), mini(state.grid_size, row + 2)):
				dirty_chunks[Vector2i(x / CHUNK, z / CHUNK)] = true
	for key in dirty_chunks:
		_update_chunk(state, key)
	state.sea_dirty.clear()
	_sync_npcs(state)
	bird_model.get_node("Load").visible = state.carried > 0

func _sync_npcs(state: JWState) -> void:
	var radius := normal_size * zoom * 0.8 + 8.0
	for index in range(state.mountains.size()):
		var nearby := state.mountain_position(index).distance_to(state.player) < radius
		if nearby and not npc_views.has(index):
			var root := Node3D.new()
			var point := state.npc_position(index)
			root.position = Vector3(point.x, 0.45, point.y)
			add_child(root)
			var animal := Models.pangolin()
			animal.rotation.y = -0.5
			root.add_child(animal)
			Models.box(root, Vector3(0.95, 1.0, -0.65), Vector3(0.10, 2.0, 0.10), Color("866b4b"))
			Models.box(root, Vector3(1.3, 1.8, -0.65), Vector3(0.65, 0.55, 0.06), Color("d5905b"))
			var title := label("", Vector3(point.x, 3.0, point.y), Color("fff1c7"), 36)
			npc_views[index] = {"root": root, "animal": animal, "label": title}
		elif not nearby and npc_views.has(index):
			npc_views[index]["root"].queue_free()
			npc_views[index]["label"].queue_free()
			npc_views.erase(index)
		if npc_views.has(index):
			var mountain: Dictionary = state.mountains[index]
			var title: Label3D = npc_views[index]["label"]
			title.text = state.mountain_name(index) + (" · 碎石 %s" % State.number(int(mountain["stock"])) if mountain["settled"] else (" · 开采 %.0f%%" % (float(mountain["work"]) / float(mountain["yield"]) * 100) if mountain["started"] else " · 穿山甲"))
			title.visible = not overview
			npc_views[index]["root"].visible = not overview

func cell_height(state: JWState, index: int) -> float:
	if index < 0 or index >= state.sea_fill.size():
		return -1.2
	if state.sea_depth[index] < 0:
		return 0.44
	var base := -1.2 - state.sea_depth[index] * 0.65
	return lerpf(base, 0.49, float(state.sea_fill[index]) / state.sea_capacity[index])

func _corner_height(state: JWState, col: int, row: int) -> float:
	var total := 0.0
	var count := 0
	for z in range(row - 1, row + 1):
		for x in range(col - 1, col + 1):
			if x >= 0 and x < state.grid_size and z >= 0 and z < state.grid_size:
				total += cell_height(state, z * state.grid_size + x)
				count += 1
	return total / maxi(1, count)

func _update_chunk(state: JWState, key: Vector2i) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(key.y * CHUNK, mini(state.grid_size, (key.y + 1) * CHUNK)):
		for col in range(maxi(state.land_cols, key.x * CHUNK), mini(state.grid_size, (key.x + 1) * CHUNK)):
			var index := row * state.grid_size + col
			var point := state.cell_center(index)
			var center := Vector3(point.x, cell_height(state, index), point.y)
			var corners: Array[Vector3] = []
			for offset in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]:
				var x: int = col + offset.x
				var z: int = row + offset.y
				corners.append(Vector3(state.map_origin.x + x * State.CELL_SIZE, _corner_height(state, x, z), state.map_origin.y + z * State.CELL_SIZE))
			for edge in range(4):
				tool.set_color(Color("b6c18b") if state.sea_fill[index] == state.sea_capacity[index] else Color("ece0ba"))
				for vertex in [center, corners[(edge + 1) % 4], corners[edge]]:
					tool.add_vertex(vertex)
	tool.generate_normals()
	if not terrain_chunks.has(key):
		var node := MeshInstance3D.new()
		var mat := Models.material(Color.WHITE)
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
		add_child(node)
		terrain_chunks[key] = node
	terrain_chunks[key].mesh = tool.commit()

func update_camera(state: JWState, delta: float, instant: bool = false) -> void:
	var target := Vector3(state.map_origin.x + state.map_side / 2, 0, state.map_side * 0.055) if overview else Vector3(state.player.x, 0, state.player.y)
	focus = target if instant else focus.lerp(target, minf(1, delta * 8))
	var desired_size := state.map_side * 1.6 if overview else normal_size * zoom
	camera.size = desired_size if instant else lerpf(camera.size, desired_size, minf(1, delta * 8))
	# Pull camera back with overview so all mountains stay in front of its near plane.
	var distance_factor := maxf(1.0, camera.size / 29.0)
	camera.position = focus + (Vector3(0, 45, 6) if overview else camera_offset) * distance_factor
	camera.look_at(focus)
	for node in depth_labels:
		node.visible = not overview
	overview_marker.visible = overview
	overview_marker.position = Vector3(state.player.x, 0.6, state.player.y)
	overview_marker.scale = Vector3.ONE * maxf(1, state.map_side / 90.0)

func point_visible(point: Vector2) -> bool:
	var position := Vector3(point.x, 0.2, point.y)
	return not camera.is_position_behind(position) and get_viewport().get_visible_rect().has_point(camera.unproject_position(position))

func animate(state: JWState, delta: float, moving: bool, high_flight: bool, aimed_cell: int) -> void:
	time += delta
	update_camera(state, delta)
	var flutter := sin(time * (17.0 if moving or high_flight else 8.0)) * (0.65 if moving or high_flight else 0.18)
	bird_model.get_node("WingLeft").rotation.z = flutter
	bird_model.get_node("WingRight").rotation.z = -flutter
	bird_model.rotation.x = lerpf(bird_model.rotation.x, -0.12 if moving else 0.0, delta * 8)
	bird_model.position.y = sin(time * 3.8) * 0.045
	for index in npc_views:
		var animal: Node3D = npc_views[index]["animal"]
		animal.rotation.x = sin(time * 8) * 0.1 if state.mountains[index]["started"] and not state.mountains[index]["settled"] else 0.0
	shadow.position = Vector3(state.player.x, 0.48 if state.player.x < 0 else 0.2, state.player.y)
	cell_marker.visible = aimed_cell >= 0
	if aimed_cell >= 0:
		var point := state.cell_center(aimed_cell)
		cell_marker.position = Vector3(point.x, maxf(0.24, cell_height(state, aimed_cell) + 0.03), point.y)
	var nearby := state.closest_stone(state.player)
	pickup_marker.visible = nearby >= 0 and state.carried < state.capacity() and not overview
	if nearby >= 0:
		var point := state.stone_positions[nearby]
		pickup_marker.position = Vector3(point.x, 0.47, point.y)
		pickup_marker.scale = Vector3.ONE * (1.0 + sin(time * 3) * 0.08)

func label(value: String, point: Vector3, color: Color, size: int = 36) -> Label3D:
	var node := Label3D.new()
	node.text = value
	node.position = point
	node.font = font
	node.font_size = size
	node.pixel_size = 0.009
	node.modulate = color
	node.outline_modulate = Color("294b49")
	node.outline_size = 8
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(node)
	return node

func ring(color: Color, radius: float, width: float) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - width
	mesh.outer_radius = radius + width
	mesh.rings = 48
	mesh.ring_segments = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := Models.material(color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	return node

func disc(color: Color, radius: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.008
	mesh.radial_segments = 32
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := Models.material(color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = mat
	return node
