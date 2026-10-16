extends Node
## Render representative geometry, never operate a gameplay ledger/effect pool.
## Compatibility needs a real draw; a persisted "prepared" flag is insufficient.
const Coast = preload("res://scripts/visuals/coast_geometry.gd")
static var completed: Dictionary = {}
var viewport: SubViewport
var stage: Node3D
var signatures: Dictionary = {}
var material_keys: Dictionary = {}
var samples: Array[Dictionary] = []

static func session_key(world, quality: String) -> String:
	var paths: Array[String] = [quality, RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), world.bird_scene.resource_path, world.pangolin_scene.resource_path]
	for scene in world.mountain_scenes:
		paths.append(scene.resource_path if scene else "fallback")
	return "|".join(paths)

func prepare(world, feedback, quality: String, progress: Callable) -> Dictionary:
	var key := session_key(world, quality)
	if DisplayServer.get_name() == "headless":
		return {"skipped": "headless", "session_reused": false, "drawn": 0}
	if completed.has(key):
		return {"skipped": "", "session_reused": true, "drawn": 0}
	var started := Time.get_ticks_usec()
	viewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.msaa_3d = get_viewport().msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	for source in world.get_children():
		if source is WorldEnvironment:
			environment.environment = source.environment
	stage.add_child(environment)
	var sun: DirectionalLight3D = world.sun.duplicate()
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	camera.position = Vector3(0, 4, 5)
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	for source in world.find_children("*", "GeometryInstance3D", true, false):
		_collect(source)
	for source in feedback.find_children("*", "GeometryInstance3D", true, false):
		_collect(source)
	# These surfaces may not exist in a new journey until its first successful fill.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(0, 0, -1)]:
		tool.set_normal(Vector3.UP)
		tool.add_vertex(point)
	var terrain := MeshInstance3D.new()
	terrain.mesh = tool.commit()
	terrain.material_override = preload("res://assets/materials/reclaimed_ground.tres")
	_collect(terrain)
	terrain.free()
	tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	Coast.foam_strip(tool, Vector3(-1, .02, 0), Vector3(1, .02, 0))
	var foam := MeshInstance3D.new()
	foam.mesh = tool.commit()
	foam.material_override = world.foam_material
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collect(foam)
	foam.free()
	# Real actor hierarchies retain their Skeleton3D/skin bindings and overrides.
	for scene in [world.bird_scene, world.pangolin_scene]:
		var actor: Node3D = scene.instantiate()
		stage.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		for child in actor.find_children("*", "Node3D", true, false):
			child.show()
		actor.hide()
		samples.append({"node": actor, "name": scene.resource_path})
	var drawn := 0
	var evidence: Array = []
	for index in range(samples.size()):
		progress.call("准备画面 · %d / %d" % [index + 1, samples.size()], .82 + .14 * float(index) / samples.size())
		var node: Node3D = samples[index].node
		node.show()
		# The first viewport needs two frames before its draw statistics are available.
		await RenderingServer.frame_post_draw
		if index == 0:
			await RenderingServer.frame_post_draw
		var calls := RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		if calls == 0:
			await RenderingServer.frame_post_draw
			calls = RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		drawn += int(calls > 0)
		evidence.append({"name": samples[index].name, "draw_calls": calls})
		node.hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if drawn == samples.size():
		completed[key] = true
	return {"skipped": "", "session_reused": false, "drawn": drawn, "samples": samples.size(), "evidence": evidence, "wall_ms": (Time.get_ticks_usec() - started) / 1000.0}

func _material_key(material: Material) -> String:
	if material == null:
		return "default"
	var id := material.get_instance_id()
	if material_keys.has(id):
		return material_keys[id]
	var result := ""
	if material is ShaderMaterial:
		result = "shader:" + str(material.shader.get_instance_id())
	else:
		# StandardMaterial colors and scalar uniforms don't change its shader.
		# Stored bool/enum features and texture presence do, so retain those flags.
		var flags: Array[String] = [material.get_class()]
		for property in material.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE == 0:
				continue
			var value: Variant = material.get(property.name)
			if value is bool or value is int:
				flags.append("%s=%s" % [property.name, value])
			elif value is Texture:
				flags.append(String(property.name) + "=texture")
		result = ";".join(flags)
	material_keys[id] = result
	return result

func _collect(source: GeometryInstance3D) -> void:
	var mesh: Mesh
	var multi: MultiMesh
	if source is MeshInstance3D:
		if source.skin != null:
			return
		mesh = source.mesh
	elif source is MultiMeshInstance3D and source.multimesh != null:
		multi = source.multimesh
		mesh = multi.mesh
	if mesh == null:
		return
	var keys: Array[String] = ["multi" if multi else "mesh", str(source.cast_shadow)]
	if multi:
		keys.append(str(multi.use_colors) + str(multi.use_custom_data))
	for surface in range(mesh.get_surface_count()):
		keys.append(str(mesh.surface_get_format(surface)) if mesh is ArrayMesh else mesh.get_class())
		keys.append(_material_key(source.material_override if source.material_override else mesh.surface_get_material(surface)))
	var key := "|".join(keys)
	if signatures.has(key):
		return
	signatures[key] = true
	var copy: GeometryInstance3D
	if multi:
		var instance := MultiMeshInstance3D.new()
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = multi.use_colors
		batch.use_custom_data = multi.use_custom_data
		batch.mesh = mesh
		batch.instance_count = 1
		batch.set_instance_transform(0, Transform3D.IDENTITY)
		if batch.use_colors:
			batch.set_instance_color(0, Color.WHITE)
		if batch.use_custom_data:
			batch.set_instance_custom_data(0, Color(1, 0, 0, 1))
		instance.multimesh = batch
		copy = instance
	else:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		copy = instance
	copy.material_override = source.material_override
	copy.cast_shadow = source.cast_shadow
	var bounds := mesh.get_aabb()
	var size := maxf(.01, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	copy.scale = Vector3.ONE * (2 / size)
	copy.position = -bounds.get_center() * (2 / size)
	copy.hide()
	stage.add_child(copy)
	samples.append({"node": copy, "name": mesh.resource_path + ":" + key})
