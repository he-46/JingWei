extends SceneTree
const Catalog = preload("res://scripts/visuals/asset_catalog.gd")
const Models = preload("res://scripts/models.gd")
var scene: Node3D

func _initialize() -> void:
	call_deferred("run")

func caption(text: String, point: Vector3) -> void:
	var node := Label3D.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC"])
	node.font = font
	node.text = text
	node.font_size = 40
	node.pixel_size = .014
	node.position = point
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.no_depth_test = true
	scene.add_child(node)

func one(mesh: Mesh, material: Material, point: Vector3, scale: Vector3, cut: float = 1.0) -> void:
	var node := MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_colors = true
	node.multimesh.use_custom_data = true
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = 1
	node.multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(scale), point))
	node.multimesh.set_instance_color(0, Color.WHITE)
	node.multimesh.set_instance_custom_data(0, Color(cut, 0, 0, 1))
	node.material_override = material
	scene.add_child(node)

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = Node3D.new()
	viewport.add_child(scene)
	var env := WorldEnvironment.new()
	var config := Environment.new()
	config.background_mode = Environment.BG_COLOR
	config.background_color = Color("a9beb7")
	config.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	config.ambient_light_color = Color("bdcfc4")
	config.ambient_light_energy = .42
	env.environment = config
	scene.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -33, 0)
	light.light_energy = .68
	light.shadow_enabled = true
	scene.add_child(light)
	var ground := PlaneMesh.new()
	ground.size = Vector2(80, 80)
	Models.mesh_part(scene, ground, Models.material(Color("92ac81")), Vector3.ZERO)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 27
	camera.position = Vector3(4, 35, 38)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0, 2.3))
	camera.current = true
	var names := ["岩层山", "石笋峰", "双峰山", "连脊山", "平顶山", "孤针峰", "分岔峰", "锯齿岭"]
	var meshes := Catalog.meshes(Catalog.MOUNTAINS)
	for i in range(8):
		var x := (i - 3.5) * 4.5
		one(meshes[i], preload("res://assets/materials/strata_mountain.tres"), Vector3(x, 0, -8), Vector3(1.7, 4, 1.7))
		caption(names[i], Vector3(x, .3, -5.5))
		one(meshes[i], preload("res://assets/materials/strata_mountain.tres"), Vector3(x, 0, -.5), Vector3(1.7, 4, 1.7), .5)
	caption("完整山体 / 同一模型连续开采至 50%", Vector3(0, .3, 2))
	for group in [[Catalog.TREES, Vector3(-13, 0, 5)], [Catalog.SHRUBS, Vector3(-2, 0, 5)], [Catalog.GRASSES, Vector3(6, 0, 5)]]:
		var assets := Catalog.meshes(group[0])
		for i in range(assets.size()):
			one(assets[i], preload("res://assets/materials/coast_foliage.tres"), group[1] + Vector3(i * 3.2, 0, 0), Vector3.ONE)
	caption("三种树形", Vector3(-10, .3, 8))
	caption("两类灌木", Vector3(-.3, .3, 8))
	caption("两类草丛", Vector3(7.5, .3, 8))
	var stones := Catalog.meshes(Catalog.STONES)
	for i in range(6):
		one(stones[i], preload("res://assets/materials/quarry_stone.tres"), Vector3(-12 + i * 1.6, 0, 11.5), Vector3.ONE * 1.4)
	caption("六种石形", Vector3(-8, .3, 14))
	var fixture := preload("res://scripts/state.gd").new()
	fixture.mountains[0].settled = true
	fixture.mountains[0].stock = fixture.mountains[0].yield
	var visual = Catalog.Visual.from_state(fixture, 0)
	for layout in range(3):
		visual.transform.origin = Vector3(2 + layout * 4.5, 0, 11.5)
		for part in range(32):
			var t := Catalog.quarry_transform(visual, part, layout)
			one(stones[(part / 8 + layout) % 6], preload("res://assets/materials/quarry_stone.tres"), t.origin, t.basis.get_scale())
	caption("三组碎石场组合", Vector3(6.5, .3, 14))
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/art/art08-review"))
	var path := "res://artifacts/art/art08-review/asset-sheet.jpg"
	viewport.get_texture().get_image().save_jpg(path, .94)
	print("EXPANSION SHEET ", path)
	quit(0)
