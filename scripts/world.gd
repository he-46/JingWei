extends Node3D

const State = preload("res://scripts/state.gd")
const Models = preload("res://scripts/models.gd")
const MountainVisual = preload("res://scripts/visuals/mountain_visual.gd")
const Coast = preload("res://scripts/visuals/coast_geometry.gd")
const Catalog = preload("res://scripts/visuals/asset_catalog.gd")
const SpatialBatch = preload("res://scripts/visuals/spatial_batch.gd")
const SAMPLE_MOUNTAIN = preload("res://assets/models/environment/strata_mountain.glb")
@export var bird_scene: PackedScene = preload("res://scenes/actors/jingwei.tscn")
@export var pangolin_scene: PackedScene = preload("res://scenes/actors/pangolin.tscn")
@export var mountain_scenes: Array[PackedScene] = Catalog.scenes(Catalog.MOUNTAINS)
const CHUNK := 8
const ROCKS_PER_MOUNTAIN := 32

var camera: Camera3D
var bird_body: CharacterBody3D
var bird_model: Node3D
var stone_mesh: RefCounted
var grass_mesh: RefCounted
var tree_mesh: RefCounted
var shrub_mesh: RefCounted
var shore_rocks: RefCounted
var coast_surface: MeshInstance3D
var water_surface: MeshInstance3D
var water_material: ShaderMaterial
var foam_material: ShaderMaterial
var foliage_material: ShaderMaterial
var foliage_materials: Array[ShaderMaterial] = []
var foam_chunks: Dictionary = {}
var mountain_batches: Array = []
var mountain_slots: Array[int] = []
var mountain_variants: Array[int] = []
var collision_profiles: Array[PackedFloat32Array] = []
var detail_batches: Array = []
var detail_clock := 0.0
var npc_animation_clock := 0.0
var sun: DirectionalLight3D
var flight_ceiling: float = 8.2
var range_ring: MeshInstance3D
var fog_layers: Array[MeshInstance3D] = []
var pile_mesh: MultiMesh
var drop_mesh: MultiMesh
var mountain_collisions: Array[CollisionShape3D] = []
var mountain_cache: Array[int] = []
var mountain_ratios: Array[float] = []
var mountain_collision_groups: Array = []
var sample_enabled := false
var sample_collision_radii := PackedFloat32Array()
var quarry_mesh: RefCounted
var quarry_site_mesh: RefCounted
var work_chip_mesh: RefCounted
var mining_dust: MultiMesh
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
var reduced_detail := false
var zoom: float = 1.0
var focus := Vector3.ZERO
var normal_size: float = 29.0
var camera_offset := Vector3(16, 29, 27)
var tree_canopies: Array[Vector4] = []
var locator_clock := 0.0
var player_obscured := false
var staged_loading := false
var loading_progress := Callable()
var loading_deadline := 0
var decor_mountains := PackedVector3Array()
var decor_workers := PackedVector2Array()

func setup(state: JWState, staged: bool = false, progress: Callable = Callable()) -> void:
	staged_loading = staged
	loading_progress = progress
	loading_deadline = Time.get_ticks_usec() + 6000
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "SimHei"])
	normal_size = 29.0 * pow(state.map_side / 48.0, 0.22)
	focus = Vector3(state.player.x, 0, state.player.y)
	_build_lighting(state)
	_build_land(state)
	_build_boundary_fog(state)
	flight_ceiling = state.high_flight_height()
	await _build_decor(state)
	await _build_resources(state)
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
	await sync(state)
	update_camera(state, 1.0, true)
	staged_loading = false
	loading_progress = Callable()
	decor_mountains.clear()
	decor_workers.clear()

func _loading_step(label_text: String, fraction: float) -> void:
	if not staged_loading:
		return
	if loading_progress.is_valid():
		loading_progress.call(label_text, fraction)
	if Time.get_ticks_usec() >= loading_deadline:
		await get_tree().process_frame
		loading_deadline = Time.get_ticks_usec() + 6000

func _build_lighting(state: JWState) -> void:
	var environment := WorldEnvironment.new()
	var config := Environment.new()
	config.background_mode = Environment.BG_COLOR
	config.background_color = Color("a9beb7")
	config.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	config.ambient_light_color = Color("bdcfc4")
	config.ambient_light_energy = 0.42
	config.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = config
	add_child(environment)
	var light := DirectionalLight3D.new()
	sun = light
	light.rotation_degrees = Vector3(-50, -33, 0)
	light.light_color = Color("fff4df")
	light.light_energy = 0.68
	light.shadow_enabled = true
	# A small depth offset suppresses self-shadow stripes on narrow, faceted peaks.
	light.shadow_bias = 0.2
	light.shadow_normal_bias = 2.0
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
	water_material = ShaderMaterial.new()
	water_material.shader = preload("res://shaders/water.gdshader")
	water_material.set_shader_parameter("shallow_end", int(state.bands[0]) * State.CELL_SIZE)
	water_material.set_shader_parameter("far_end", (int(state.bands[0]) + int(state.bands[1])) * State.CELL_SIZE)
	water_material.set_shader_parameter("sea_end", (state.grid_size - state.land_cols) * State.CELL_SIZE)
	water_surface = Models.mesh_part(self, water, water_material, Vector3(0, Coast.WATER_HEIGHT, 0))
	water_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Mainland continues west/north/south beyond the square journey boundary.
	var land := PlaneMesh.new()
	land.size = Vector2(state.map_side * 3 - 3, state.map_side * 5)
	Models.mesh_part(self, land, preload("res://assets/materials/coast_ground.tres"), Vector3(-(state.map_side * 3 + 3) * .5, State.LAND_HEIGHT, 0))
	coast_surface = Models.mesh_part(self, Coast.coast_mesh(state.map_side), preload("res://assets/materials/coast_ground.tres"), Vector3.ZERO)
	foam_material = preload("res://assets/materials/shore_foam.tres").duplicate()
	var foam := Models.mesh_part(self, Coast.mainland_foam(state.map_side), foam_material, Vector3.ZERO)
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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

func spatial(meshes: Array[Mesh], transforms: Array[Transform3D], ids: Array[int], material: Material, shadows: bool = false, far_meshes: Array[Mesh] = []):
	var pool = SpatialBatch.new()
	var anchors: Array[Vector3] = []
	for transform in transforms:
		anchors.append(transform.origin)
	pool.configure(self, meshes, anchors, ids, material, true, false, shadows, far_meshes)
	for i in range(transforms.size()):
		pool.set_instance_transform(i, transforms[i])
		pool.set_instance_color(i, Color.WHITE)
	pool.refresh_bounds()
	detail_batches.append(pool)
	return pool

func _build_decor(state: JWState) -> void:
	# Immutable placement circles avoid repeated Dictionary and radius lookups.
	for index in range(state.mountains.size()):
		var point := state.mountain_position(index)
		decor_mountains.append(Vector3(point.x, point.y, state.mountain_radius(index)))
		decor_workers.append(state.npc_position(index))
	var rng := RandomNumberGenerator.new()
	rng.seed = state.world_seed + 980
	foliage_material = preload("res://assets/materials/coast_foliage.tres").duplicate()
	var transforms: Array[Transform3D] = []
	var ids: Array[int] = []
	for index in range(mini(2500, state.grid_size * 40)):
		var p := _decor_point(state, rng, 0.2, -2.7, State.LAND_HEIGHT)
		transforms.append(Transform3D(Basis.IDENTITY, p))
		ids.append(Catalog.regional_variant(p, 2, index))
		if index % 32 == 0:
			await _loading_step("铺设草地", .10 + .14 * float(index) / mini(2500, state.grid_size * 40))
	var grass_mat: ShaderMaterial = foliage_material.duplicate()
	grass_mat.set_shader_parameter("detail_distance", 70.0)
	foliage_materials.append(grass_mat)
	grass_mesh = spatial(Catalog.meshes(Catalog.GRASSES), transforms, ids, grass_mat)
	grass_mesh.max_distance = 70
	for index in range(transforms.size()):
		grass_mesh.set_instance_color(index, Color.WHITE if index % 4 else Color("e2ddba"))
	transforms.clear()
	ids.clear()
	var tree_points := PackedVector2Array()
	for index in range(mini(200, state.grid_size * 2)):
		var size := rng.randf_range(0.7, 1.2)
		var p := _decor_point(state, rng, 2.9, -3.5, State.LAND_HEIGHT, 2.7)
		for attempt in range(8):
			var separated := true
			for other in tree_points:
				if other.distance_to(Vector2(p.x, p.z)) < 2.8:
					separated = false
			if separated:
				break
			p = _decor_point(state, rng, 2.9, -3.5, State.LAND_HEIGHT, 2.7) if attempt < 7 else Vector3(0, -40, 0)
		var variant := Catalog.regional_variant(p, 3, index)
		if p.y > -10:
			tree_points.append(Vector2(p.x, p.z))
			var crown: Vector2 = Catalog.TREE_CROWNS[variant]
			tree_canopies.append(Vector4(p.x, p.y + size * crown.x, p.z, size * crown.y))
		transforms.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * size), p))
		ids.append(variant)
		if index % 8 == 0:
			await _loading_step("种植林木", .26 + .06 * float(index) / mini(200, state.grid_size * 2))
	tree_mesh = spatial(Catalog.meshes(Catalog.TREES), transforms, ids, foliage_material, true)
	tree_mesh.keep_overview = true
	for index in range(transforms.size()):
		tree_mesh.set_instance_color(index, Color.WHITE if index % 2 else Color("d8e5ca"))
	transforms.clear()
	ids.clear()
	for index in range(mini(160, state.grid_size * 2)):
		var p := _decor_point(state, rng, 1.2, -2.8, State.LAND_HEIGHT, 1.2)
		transforms.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * rng.randf_range(.7, 1.0)), p))
		ids.append(Catalog.regional_variant(p, 2, index))
		if index % 8 == 0:
			await _loading_step("布置灌木", .34 + .04 * float(index) / mini(160, state.grid_size * 2))
	var shrub_mat: ShaderMaterial = foliage_material.duplicate()
	shrub_mat.set_shader_parameter("detail_distance", 85.0)
	foliage_materials.append(shrub_mat)
	shrub_mesh = spatial(Catalog.meshes(Catalog.SHRUBS), transforms, ids, shrub_mat)
	shrub_mesh.max_distance = 85
	transforms.clear()
	ids.clear()
	for index in range(clampi(state.grid_size * 2, 24, 160)):
		var z := rng.randf_range(state.map_origin.y + 1, -state.map_origin.y - 1)
		var x := rng.randf_range(-.4, .8)
		var size := rng.randf_range(.65, 1.15)
		var p := Vector3(x, -.08 if x > 0 else .10, z)
		if not _clear_of_resources(state, Vector2(x, z), 1.1):
			p.y = -40
		transforms.append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3.ONE * size), p))
		ids.append(0)
		if index % 8 == 0:
			await _loading_step("布置海岸", .40)
	shore_rocks = spatial(Catalog.meshes(["shore_rock"]), transforms, ids, preload("res://assets/materials/shore_rock.tres"))

func _decor_point(state: JWState, rng: RandomNumberGenerator, mountain_margin: float, xmax: float, height: float, resource_margin: float = 0.0) -> Vector3:
	# Keep future quarry sites clear too; mining never has to remove trees or grass.
	for attempt in range(24):
		var point := Vector2(rng.randf_range(state.map_origin.x + 1.5, xmax), rng.randf_range(state.map_origin.y + 1.5, -state.map_origin.y - 1.5))
		if _clear_of_decor_mountains(point, mountain_margin) and (resource_margin <= 0 or _clear_of_resources(state, point, resource_margin)):
			return Vector3(point.x, height, point.y)
	return Vector3(0, -40, 0)

func _clear_of_decor_mountains(point: Vector2, margin: float) -> bool:
	for circle in decor_mountains:
		if point.distance_squared_to(Vector2(circle.x, circle.y)) < (circle.z + margin) * (circle.z + margin):
			return false
	return true

func _clear_of_resources(state: JWState, point: Vector2, margin: float) -> bool:
	for stone in state.stone_positions:
		if point.distance_squared_to(stone) < margin * margin:
			return false
	var npc_margin := maxf(3.2, margin + 1.3)
	for worker in decor_workers:
		if point.distance_squared_to(worker) < npc_margin * npc_margin:
			return false
	return true

func batch(mesh: Mesh, count: int, colors: bool, color: Color, material_override: Material = null) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_3D
	result.use_colors = colors
	result.mesh = mesh
	result.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.multimesh = result
	var mat := Models.material(color)
	mat.vertex_color_use_as_albedo = colors
	node.material_override = material_override if material_override else mat
	add_child(node)
	return result

func resource_pool(meshes: Array[Mesh], anchors: Array[Vector3], ids: Array[int], material: Material, custom: bool = false, far_meshes: Array[Mesh] = []):
	var pool = SpatialBatch.new()
	pool.configure(self, meshes, anchors, ids, material, true, custom, true, far_meshes)
	detail_batches.append(pool)
	return pool

func _build_resources(state: JWState) -> void:
	var anchors: Array[Vector3] = []
	var ids: Array[int] = []
	var stones := Catalog.meshes(Catalog.STONES)
	var stone_material := preload("res://assets/materials/quarry_stone.tres")
	for index in range(state.stone_positions.size()):
		var point := state.stone_positions[index]
		for pebble in range(3):
			var p := Vector3(point.x, State.LAND_HEIGHT, point.y)
			anchors.append(p)
			ids.append(Catalog.regional_variant(p, 6, index) if pebble == 0 else (index + pebble) % 6)
	stone_mesh = resource_pool(stones, anchors, ids, stone_material)
	await _loading_step("摆放散石", .44)
	# Only a zero-sized legacy adapter remains; all actual stock uses formal stones.
	pile_mesh = batch(Models.rock_mesh(4), 0, false, Color.WHITE)
	drop_mesh = batch(stones[1], 0, false, Color.WHITE, stone_material)
	anchors.clear()
	ids.clear()
	var site_anchors: Array[Vector3] = []
	var site_ids: Array[int] = []
	var chip_anchors: Array[Vector3] = []
	var chip_ids: Array[int] = []
	for index in range(state.mountains.size()):
		var point := state.mountain_position(index)
		var p := Vector3(point.x, State.LAND_HEIGHT, point.y)
		site_anchors.append(p)
		site_ids.append(0)
		for part in range(ROCKS_PER_MOUNTAIN):
			anchors.append(p)
			ids.append((index + part / 8) % 6)
		for part in range(8):
			chip_anchors.append(p)
			chip_ids.append(part % 6)
	quarry_mesh = resource_pool(stones, anchors, ids, stone_material)
	quarry_site_mesh = resource_pool(Catalog.meshes(["quarry_site"]), site_anchors, site_ids, preload("res://assets/materials/quarry_site.tres"))
	quarry_site_mesh.keep_overview = true
	work_chip_mesh = resource_pool(stones, chip_anchors, chip_ids, stone_material)
	await _loading_step("布置碎石场", .50)
	var dust_shape := SphereMesh.new()
	dust_shape.radius = 0.12
	dust_shape.height = 0.24
	dust_shape.radial_segments = 8
	dust_shape.rings = 3
	mining_dust = batch(dust_shape, 8, true, Color.WHITE)
	var dust_node := get_child(get_child_count() - 1) as MultiMeshInstance3D
	var dust_mat := Models.material(Color.WHITE)
	dust_mat.vertex_color_use_as_albedo = true
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_node.material_override = dust_mat
	dust_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mining_dust.visible_instance_count = 0
	sample_enabled = not mountain_scenes.is_empty() and mountain_scenes[0] == SAMPLE_MOUNTAIN
	var expanded := sample_enabled and mountain_scenes.size() == 8
	var counts: Array[int] = []
	counts.resize(8 if expanded else 5)
	counts.fill(0)
	for index in range(state.mountains.size()):
		var shape: int = state.mountains[index]["shape"]
		var variant := Catalog.mountain_variant(shape, index) if expanded else shape
		mountain_variants.append(variant)
		mountain_slots.append(counts[variant])
		counts[variant] += 1
	var far_meshes: Array[Mesh] = []
	if expanded:
		far_meshes = Catalog.meshes(Catalog.MOUNTAINS, "_far")
	for variant in range(counts.size()):
		var asset: Mesh
		if variant < mountain_scenes.size() and mountain_scenes[variant]:
			asset = MountainVisual.imported_mesh(mountain_scenes[variant])
		else:
			asset = Models.mountain_mesh(variant % 5)
		var material: Material = preload("res://assets/materials/strata_mountain.tres")
		if not sample_enabled:
			var generic := ShaderMaterial.new()
			generic.shader = preload("res://shaders/mountain.gdshader")
			material = generic
		anchors.clear()
		ids.clear()
		for index in range(state.mountains.size()):
			if mountain_variants[index] == variant:
				anchors.append(site_anchors[index])
				ids.append(0)
		var meshes: Array[Mesh] = [asset]
		var distant: Array[Mesh] = []
		if expanded:
			distant.append(far_meshes[variant])
		var pool = resource_pool(meshes, anchors, ids, material, true, distant)
		pool.keep_overview = true
		mountain_batches.append(pool)
		collision_profiles.append(MountainVisual.collision_envelopes(asset))
		await _loading_step("塑造山体", .52 + .08 * float(variant + 1) / counts.size())
	sample_collision_radii = collision_profiles[0]
	for index in range(state.mountains.size()):
		mountain_cache.append(-1)
		mountain_ratios.append(-1)
		pile_cache.append(-1)
		var body := StaticBody3D.new()
		var visual = MountainVisual.from_state(state, index)
		body.position = site_anchors[index]
		add_child(body)
		var group: Array[CollisionShape3D] = []
		var profile: PackedFloat32Array = collision_profiles[mountain_variants[index]]
		for slab in range(8):
			var shape := CylinderShape3D.new()
			shape.radius = visual.radius * profile[slab]
			shape.height = visual.height / 8
			var collider := CollisionShape3D.new()
			collider.shape = shape
			body.add_child(collider)
			group.append(collider)
		mountain_collisions.append(group[0])
		mountain_collision_groups.append(group)
		if index % 8 == 0:
			await _loading_step("建立山体边界", .60 + .06 * float(index) / state.mountains.size())

func sync(state: JWState) -> void:
	for index in state.stone_dirty:
		var point := state.stone_positions[index]
		for pebble in range(3):
			var location := Vector3(point.x + (pebble - 1) * 0.28, State.LAND_HEIGHT + .02, point.y + sin(index + pebble) * 0.18)
			if state.stone_amounts[index] == 0:
				location.y = -40
			var scale_value := 0.4 + pebble * 0.09
			stone_mesh.set_instance_transform(index * 3 + pebble, Transform3D(Basis.from_euler(Vector3(0, index + pebble, 0)).scaled(Vector3.ONE * scale_value), location))
			stone_mesh.set_instance_color(index * 3 + pebble, Color("ded4b9") if pebble % 2 else Color("a7b1a3"))
	state.stone_dirty.clear()
	await _loading_step("恢复石料", .68)
	for index in range(state.mountains.size()):
		var mountain: Dictionary = state.mountains[index]
		var visual = MountainVisual.from_state(state, index)
		var ratio: float = visual.remaining
		var count := int(ceil(ROCKS_PER_MOUNTAIN * ratio))
		if mountain_ratios[index] != ratio:
			mountain_ratios[index] = ratio
			mountain_cache[index] = count
			var transform: Transform3D = visual.transform
			if count == 0:
				transform.origin.y = -100
			var mesh = mountain_batches[mountain_variants[index]]
			var slot := mountain_slots[index]
			mesh.set_instance_transform(slot, transform)
			mesh.set_instance_custom_data(slot, Color(ratio, 0, 0, 1))
			mesh.set_instance_color(slot, Color("e5ead3") if index % 3 == 0 else Color.WHITE)
			var group: Array = mountain_collision_groups[index]
			for slab in range(group.size()):
				var collider: CollisionShape3D = group[slab]
				var bottom := float(slab) / group.size()
				var top := minf(float(slab + 1) / group.size(), ratio)
				collider.set_deferred("disabled", top <= bottom)
				collider.shape.height = maxf(0.001, (top - bottom) * visual.height)
				collider.position.y = (bottom + maxf(bottom, top)) * visual.height * 0.5
			_update_quarry_site(index, visual)
		var stock: int = visual.stock
		if pile_cache[index] != stock:
			pile_cache[index] = stock
			for part in range(ROCKS_PER_MOUNTAIN):
				quarry_mesh.set_instance_transform(index * ROCKS_PER_MOUNTAIN + part, Catalog.quarry_transform(visual, part, index % 3))
		if index % 8 == 0:
			await _loading_step("恢复开采进度", .69 + .04 * float(index) / state.mountains.size())
	if state.piles_dirty:
		drop_mesh.instance_count = state.land_piles.size() * 3
		var cursor := 0
		for key in state.land_piles:
			var point := state.cell_center(int(key))
			for part in range(3):
				drop_mesh.set_instance_transform(cursor, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.6), Vector3(point.x + (part - 1) * 0.45, State.LAND_HEIGHT + .02, point.y + sin(part) * 0.4)))
				cursor += 1
		state.piles_dirty = false
	var dirty_chunks: Dictionary = {}
	for index in state.sea_dirty:
		var col: int = index % state.grid_size
		var row: int = index / state.grid_size
		# Shared corner normals sample one further ring than the vertex heights.
		for x in range(maxi(state.land_cols, col - 2), mini(state.grid_size, col + 3)):
			for z in range(maxi(0, row - 2), mini(state.grid_size, row + 3)):
				dirty_chunks[Vector2i(x / CHUNK, z / CHUNK)] = true
	var completed := 0
	for key in dirty_chunks:
		_update_chunk(state, key)
		completed += 1
		await _loading_step("恢复已填海域", .74 + .22 * float(completed) / dirty_chunks.size())
	state.sea_dirty.clear()
	_sync_npcs(state)
	bird_model.set_load(float(state.carried) / state.capacity())
	if mining_dust:
		_update_mining_dust(state)
	for pool in detail_batches:
		pool.refresh_bounds()

func _update_quarry_site(index: int, visual) -> void:
	var slot := index
	quarry_site_mesh.set_instance_transform(slot, visual.transform)
	for part in range(8):
		var angle := part * TAU / 8
		var location: Vector3 = visual.transform.origin + Vector3(cos(angle), 0, sin(angle)) * visual.radius * 0.80
		location.y += 0.025
		# Work fragments remain decorative: no pickup stock before the mine settles.
		if visual.progress <= 0 or visual.settled:
			location.y = -50
		work_chip_mesh.set_instance_transform(slot * 8 + part, Transform3D(Basis.from_euler(Vector3(0, angle, 0)).scaled(Vector3.ONE * minf(0.35, visual.radius * 0.15)), location))

func _update_mining_dust(state: JWState) -> void:
	var index := state.next_mountain()
	var active := not overview and index >= 0 and state.mining_unlocked() and bool(state.mountains[index]["started"])
	if active:
		active = state.mountain_position(index).distance_to(state.player) < 55
	mining_dust.visible_instance_count = 8 if active else 0
	if not active:
		return
	var point := state.mountain_position(index)
	var radius := state.mountain_radius(index)
	for puff in range(8):
		var phase := fposmod(time * 1.15 + puff / 8.0, 1.0)
		var position := Vector3(point.x + radius * 0.92 + phase * 0.40, State.LAND_HEIGHT + 0.12 + phase * 0.60, point.y + sin(puff * 7.1) * phase * 0.40)
		mining_dust.set_instance_transform(puff, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.25 + phase * 0.8)), position))
		mining_dust.set_instance_color(puff, Color(0.74, 0.70, 0.55, sin(phase * PI) * 0.16))

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
	return Coast.cell_height(state, index)

func _corner_height(state: JWState, col: int, row: int) -> float:
	return Coast.corner_height(state, col, row)

func _update_chunk(state: JWState, key: Vector2i) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foam := SurfaceTool.new()
	foam.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foam_segments := 0
	for row in range(key.y * CHUNK, mini(state.grid_size, (key.y + 1) * CHUNK)):
		for col in range(maxi(state.land_cols, key.x * CHUNK), mini(state.grid_size, (key.x + 1) * CHUNK)):
			for triangle in Coast.cell_triangles(state, col, row):
				for vertex in range(3):
					tool.set_normal(triangle["normals"][vertex])
					tool.add_vertex(triangle["points"][vertex])
				var segment := Coast.water_segment(triangle["points"])
				if segment.size() == 2 and maxf(segment[0].x, segment[1].x) > .20:
					Coast.foam_strip(foam, segment[0], segment[1])
					foam_segments += 1
	if not terrain_chunks.has(key):
		var node := MeshInstance3D.new()
		node.material_override = preload("res://assets/materials/reclaimed_ground.tres")
		add_child(node)
		terrain_chunks[key] = node
	terrain_chunks[key].mesh = tool.commit()
	if foam_segments > 0:
		if not foam_chunks.has(key):
			var node := MeshInstance3D.new()
			node.material_override = foam_material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			foam_chunks[key] = node
		foam_chunks[key].mesh = foam.commit()
		foam_chunks[key].visible = true
	elif foam_chunks.has(key):
		foam_chunks[key].mesh = null
		foam_chunks[key].visible = false

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

func player_occluded() -> bool:
	# One ray through real mountain collisions and at most 200 analytic canopy tests.
	# Trees remain instanced decoration without added physics bodies.
	if overview or bird_body.position.x >= 0:
		return false
	var start := camera.global_position
	var end := bird_body.global_position + Vector3.UP * .15
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [bird_body.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return true
	var direction := end - start
	for canopy in tree_canopies:
		var center := Vector3(canopy.x, canopy.y, canopy.z)
		var t := clampf((center - start).dot(direction) / direction.length_squared(), 0, 1)
		if t < .99 and (start + direction * t).distance_squared_to(center) < canopy.w * canopy.w:
			return true
	return false

func update_player_locator(delta: float) -> Vector2:
	locator_clock -= delta
	if locator_clock <= 0:
		locator_clock = .1
		player_obscured = player_occluded()
	return camera.unproject_position(bird_body.global_position + Vector3.UP * .15)

func animate(state: JWState, delta: float, moving: bool, high_flight: bool, aimed_cell: int) -> void:
	time += delta
	water_material.set_shader_parameter("wave_time", time)
	foam_material.set_shader_parameter("wave_time", time)
	foliage_material.set_shader_parameter("wind_time", time)
	var detail_origin := bird_body.position
	foliage_material.set_shader_parameter("detail_origin", detail_origin)
	foliage_material.set_shader_parameter("overview", float(overview))
	for material in foliage_materials:
		material.set_shader_parameter("wind_time", time)
		material.set_shader_parameter("detail_origin", detail_origin)
	for layer in fog_layers:
		layer.material_override.set_shader_parameter("fog_time", time)
	grass_mesh.visible_instance_count = 0 if overview or reduced_detail else -1
	shrub_mesh.visible_instance_count = 0 if overview else -1
	detail_clock -= delta
	if detail_clock <= 0 or delta == 0:
		detail_clock = .2
		for pool in detail_batches:
			pool.set_overview(overview)
			pool.update_detail(camera, detail_origin)
		sun.shadow_enabled = not overview and not reduced_detail
	if mining_dust:
		_update_mining_dust(state)
	update_camera(state, delta)
	bird_model.set_motion(moving, high_flight)
	if not overview:
		bird_model.advance(delta, time)
	bird_model.visible = not overview
	npc_animation_clock += delta
	for index in npc_views:
		var animal: Node3D = npc_views[index]["animal"]
		var near := animal.global_position.distance_to(bird_body.position) < 35
		if not overview and (near or npc_animation_clock >= .1):
			animal.advance(delta if near else npc_animation_clock, time)
	if npc_animation_clock >= .1:
		npc_animation_clock = 0
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
