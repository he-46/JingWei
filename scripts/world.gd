extends Node3D

const State = preload("res://scripts/state.gd")
const Models = preload("res://scripts/models.gd")
const MountainVisual = preload("res://scripts/visuals/mountain_visual.gd")
@export var bird_scene: PackedScene = preload("res://scenes/actors/jingwei.tscn")
@export var pangolin_scene: PackedScene = preload("res://scenes/actors/pangolin.tscn")
@export var mountain_scenes: Array[PackedScene] = []
const CHUNK := 8
const ROCKS_PER_MOUNTAIN := 32

var camera: Camera3D
var bird_body: CharacterBody3D
var bird_model: Node3D
var stone_mesh: MultiMesh
var mountain_batches: Array[MultiMesh] = []
var mountain_slots: Array[int] = []
var flight_ceiling: float = 8.2
var range_ring: MeshInstance3D
var fog_layers: Array[MeshInstance3D] = []
var pile_mesh: MultiMesh
var drop_mesh: MultiMesh
var mountain_collisions: Array[CollisionShape3D] = []
var mountain_cache: Array[int] = []
var pile_cache: Array[int] = []
var terrain_chunks: Dictionary = {}
var npc_views: Dictionary = {}
var cell_marker: MeshInstance3D
var pickup_marker: MeshInstance3D
var shadow: MeshInstance3D
var overview_marker: MeshInstance3D
var font: SystemFont
var aim_point := Vector2.ZERO
var time: float = 0
var overview: bool = false
var zoom: float = 1.0
var focus := Vector3.ZERO
var normal_size: float = 29.0
var camera_offset := Vector3(16, 29, 27)

func setup(state: JWState) -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "SimHei"])
	normal_size = 29.0 * pow(state.map_side / 48.0, 0.22)
	focus = Vector3(state.player.x, 0, state.player.y)
	_build_lighting(state)
	_build_land(state)
	_build_boundary_fog(state)
	flight_ceiling = state.high_flight_height()
	_build_decor(state)
	_build_resources(state)
	bird_body = CharacterBody3D.new()
	bird_body.position = Vector3(state.player.x, State.BIRD_HOVER_HEIGHT, state.player.y)
	bird_body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := SphereShape3D.new()
	shape.radius = State.BIRD_COLLISION_RADIUS
	var collider := CollisionShape3D.new()
	collider.shape = shape
	bird_body.add_child(collider)
	bird_model = bird_scene.instantiate()
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
	range_ring = ring(Color("e9d192"), 1.0, 0.012)
	add_child(range_ring)
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

func _build_boundary_fog(state: JWState) -> void:
	for layer in range(3):
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * state.map_side * 5
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/boundary_fog.gdshader")
		mat.set_shader_parameter("map_bounds", Vector4(state.map_origin.x, state.map_origin.y, state.map_origin.x + state.map_side, state.map_origin.y + state.map_side))
		mat.set_shader_parameter("opacity", 1.0 if layer == 0 else 0.25)
		mat.set_shader_parameter("edge_width", clampf(state.map_side * 0.035, 1.8, 7.0))
		mat.set_shader_parameter("drift", layer * 4.1)
		var node := Models.mesh_part(self, plane, mat, Vector3(state.map_origin.x + state.map_side / 2, 0.82 + layer * 1.5, 0))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fog_layers.append(node)

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
	pile_mesh = batch(Models.rock_mesh(4), state.mountains.size() * ROCKS_PER_MOUNTAIN, false, Color("b8b6a6"))
	drop_mesh = batch(Models.rock_mesh(1), 0, false, Color("e1d3ad"))
	var counts := [0, 0, 0, 0, 0]
	for mountain in state.mountains:
		var shape: int = mountain["shape"]
		mountain_slots.append(counts[shape])
		counts[shape] += 1
	for shape in range(5):
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.use_colors = true
		mesh.use_custom_data = true
		mesh.mesh = Models.mountain_mesh(shape)
		if shape < mountain_scenes.size() and mountain_scenes[shape]:
			var imported := MountainVisual.imported_mesh(mountain_scenes[shape])
			if imported:
				mesh.mesh = imported
		mesh.instance_count = counts[shape]
		var node := MultiMeshInstance3D.new()
		node.multimesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/mountain.gdshader")
		node.material_override = mat
		add_child(node)
		mountain_batches.append(mesh)
	for index in range(state.mountains.size()):
		mountain_cache.append(-1)
		pile_cache.append(-1)
		var body := StaticBody3D.new()
		var visual = MountainVisual.from_state(state, index)
		var point := state.mountain_position(index)
		body.position = Vector3(point.x, State.LAND_HEIGHT, point.y)
		add_child(body)
		var shape := CylinderShape3D.new()
		shape.radius = visual.collision_radius
		shape.height = visual.height
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = state.mountain_height(index) * 0.5
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
		var visual = MountainVisual.from_state(state, index)
		var ratio: float = visual.remaining
		var count := int(ceil(ROCKS_PER_MOUNTAIN * ratio))
		if mountain_cache[index] != count:
			mountain_cache[index] = count
			var transform: Transform3D = visual.transform
			if count == 0:
				transform.origin.y = -100
			var mesh := mountain_batches[int(mountain["shape"])]
			var slot := mountain_slots[index]
			mesh.set_instance_transform(slot, transform)
			mesh.set_instance_custom_data(slot, Color(ratio, 0, 0, 1))
			mesh.set_instance_color(slot, Color("e5ead3") if index % 3 == 0 else Color.WHITE)
			var collider := mountain_collisions[index]
			collider.set_deferred("disabled", count == 0)
			collider.scale.y = maxf(0.05, ratio)
			collider.position.y = visual.height * 0.5 * ratio
		var stock: int = visual.stock
		if pile_cache[index] != stock:
			pile_cache[index] = stock
			var fraction: float = visual.stock_fraction
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
	bird_model.set_load(float(state.carried) / state.capacity())

func _sync_npcs(state: JWState) -> void:
	# This actor is created once and moves with the worker, regardless of camera range.
	if npc_views.is_empty():
		var root := Node3D.new()
		add_child(root)
		var animal := pangolin_scene.instantiate()
		root.add_child(animal)
		Models.box(root, Vector3(0.95, 1.0, -0.65), Vector3(0.10, 2.0, 0.10), Color("866b4b"))
		Models.box(root, Vector3(1.3, 1.8, -0.65), Vector3(0.65, 0.55, 0.06), Color("d5905b"))
		npc_views[0] = {"root": root, "animal": animal, "label": label("", Vector3.ZERO, Color("fff1c7"), 36)}
	var index := state.pangolin_mountain()
	var point := state.npc_position(index)
	var view: Dictionary = npc_views[0]
	view["root"].position = Vector3(point.x, State.NPC_GROUND_HEIGHT, point.y)
	var unlocked := state.mining_unlocked()
	view["animal"].set_facing(state.mountain_position(index) - point)
	view["animal"].set_work(index, unlocked and state.next_mountain() >= 0, state.next_mountain() < 0, float(state.mountains[index]["work"]) / float(state.mountains[index]["yield"]), unlocked)
	var title: Label3D = view["label"]
	title.position = Vector3(point.x, 3.0, point.y)
	title.text = "穿山甲"
	title.visible = not overview
	view["root"].visible = not overview

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
	overview_marker.visible = overview
	overview_marker.position = Vector3(state.player.x, 0.6, state.player.y)
	overview_marker.scale = Vector3.ONE * maxf(1, state.map_side / 90.0)

func point_visible(point: Vector2) -> bool:
	var position := Vector3(point.x, 0.2, point.y)
	return not camera.is_position_behind(position) and get_viewport().get_visible_rect().has_point(camera.unproject_position(position))

func animate(state: JWState, delta: float, moving: bool, high_flight: bool, aimed_cell: int) -> void:
	time += delta
	update_camera(state, delta)
	bird_model.set_motion(moving, high_flight)
	bird_model.advance(delta, time)
	for index in npc_views:
		var animal: Node3D = npc_views[index]["animal"]
		animal.advance(delta, time)
	shadow.position = Vector3(state.player.x, 0.48 if state.player.x < 0 else 0.2, state.player.y)
	range_ring.position = Vector3(state.player.x, 0.58, state.player.y)
	var reach := state.throw_distance(bird_body.position.y)
	range_ring.scale = Vector3(reach, 1, reach)
	range_ring.visible = true
	cell_marker.visible = aimed_cell >= 0
	if aimed_cell >= 0:
		var point := state.cell_center(aimed_cell)
		cell_marker.position = Vector3(point.x, maxf(0.24, cell_height(state, aimed_cell) + 0.03), point.y)
		# Grey-red cells are visible but beyond the physical throwing range.
		cell_marker.material_override.albedo_color = Color("f3d491") if state.can_throw(aim_point, bird_body.position.y) else Color("d38b79")
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
