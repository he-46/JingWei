extends RefCounted
## Stable logical slots mapped to regional MultiMeshes. Changing stock never moves
## an instance into another region; hidden instances keep their original anchor.
const REGION := 32.0
var mesh: Mesh
var instance_count := 0
var visible_instance_count: int = -1:
	set(value):
		if visible_instance_count == value:
			return
		visible_instance_count = value
		_update_visibility()
var nodes: Array[MultiMeshInstance3D] = []
var far_nodes: Array[MultiMeshInstance3D] = []
var groups: Array = []
var slots: Array[Vector2i] = []
var far_slots: Array[Vector2i] = []
var transforms: Array[Transform3D] = []
var variants: Array[int] = []
var anchor_points: Array[Vector3] = []
var active_per_group: Array[int] = []
var active_far: Array[int] = []
var dirty_bounds: Dictionary = {}
var overview := false
var keep_overview := false
var max_distance := 0.0

func configure(parent: Node3D, meshes: Array[Mesh], anchors: Array[Vector3], ids: Array[int], material: Material, colors: bool = true, custom: bool = false, shadows: bool = false, far_meshes: Array[Mesh] = []) -> void:
	mesh = meshes[0]
	instance_count = anchors.size()
	variants = ids.duplicate()
	anchor_points = anchors.duplicate()
	var keys: Dictionary = {}
	var far_keys: Dictionary = {}
	for i in range(instance_count):
		var key := Vector3i(floori(anchors[i].x / REGION), floori(anchors[i].z / REGION), ids[i])
		if not keys.has(key):
			keys[key] = groups.size()
			groups.append([])
		var g: int = keys[key]
		slots.append(Vector2i(g, groups[g].size()))
		groups[g].append(i)
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(0, -100, 0)))
	for key in keys:
		var node := make_node(parent, meshes[key.z], groups[keys[key]].size(), material, colors, custom, shadows)
		node.position = Vector3(key.x * REGION, 0, key.y * REGION)
		# Dictionary insertion order matches stable group IDs.
		nodes.append(node)
		active_per_group.append(0)
	if not far_meshes.is_empty():
		keep_overview = true
		for i in range(instance_count):
			var id := ids[i]
			if not far_keys.has(id):
				far_keys[id] = {"group": far_keys.size(), "count": 0}
			far_slots.append(Vector2i(far_keys[id].group, far_keys[id].count))
			far_keys[id].count += 1
		for id in far_keys:
			far_nodes.append(make_node(parent, far_meshes[id], far_keys[id].count, material, colors, custom, false))
			active_far.append(0)
	for i in range(instance_count):
		set_instance_transform(i, transforms[i])
		if colors:
			set_instance_color(i, Color.WHITE)
	_update_visibility()

func make_node(parent: Node3D, asset: Mesh, count: int, material: Material, colors: bool, custom: bool, shadows: bool) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = colors
	batch.use_custom_data = custom
	batch.mesh = asset
	batch.instance_count = count
	node.multimesh = batch
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func set_instance_transform(index: int, value: Transform3D) -> void:
	var slot := slots[index]
	var was_active := transforms[index].origin.y > -10
	var is_active := value.origin.y > -10
	if not is_active:
		value.origin.x = anchor_points[index].x
		value.origin.z = anchor_points[index].z
	transforms[index] = value
	dirty_bounds[slot.x] = true
	if was_active != is_active:
		active_per_group[slot.x] += 1 if is_active else -1
		nodes[slot.x].visible = active_per_group[slot.x] > 0 and visible_instance_count != 0 and (not overview or (keep_overview and far_nodes.is_empty()))
	var local := value
	local.origin -= nodes[slot.x].position
	nodes[slot.x].multimesh.set_instance_transform(slot.y, local)
	if not far_slots.is_empty():
		var distant := far_slots[index]
		if was_active != is_active:
			active_far[distant.x] += 1 if is_active else -1
			far_nodes[distant.x].visible = active_far[distant.x] > 0 and overview and visible_instance_count != 0
		far_nodes[distant.x].multimesh.set_instance_transform(distant.y, value)

func refresh_bounds() -> void:
	# Hidden slots must not stretch a surviving group's culling bounds back to the
	# origin or 100 metres underground. Recompute only groups whose transforms changed.
	for group in dirty_bounds:
		var bounds := AABB()
		var first := true
		var node := nodes[group]
		for index in groups[group]:
			if transforms[index].origin.y <= -10:
				continue
			var local: Transform3D = transforms[index]
			local.origin -= node.position
			var box: AABB = local * node.multimesh.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		node.custom_aabb = bounds.grow(.05) if not first else AABB()
	dirty_bounds.clear()

func get_instance_transform(index: int) -> Transform3D:
	var slot := slots[index]
	var result := nodes[slot.x].multimesh.get_instance_transform(slot.y)
	result.origin += nodes[slot.x].position
	return result

func set_instance_color(index: int, value: Color) -> void:
	var slot := slots[index]
	nodes[slot.x].multimesh.set_instance_color(slot.y, value)
	if not far_slots.is_empty():
		var distant := far_slots[index]
		far_nodes[distant.x].multimesh.set_instance_color(distant.y, value)

func set_instance_custom_data(index: int, value: Color) -> void:
	var slot := slots[index]
	nodes[slot.x].multimesh.set_instance_custom_data(slot.y, value)
	if not far_slots.is_empty():
		var distant := far_slots[index]
		far_nodes[distant.x].multimesh.set_instance_custom_data(distant.y, value)

func get_instance_custom_data(index: int) -> Color:
	var slot := slots[index]
	return nodes[slot.x].multimesh.get_instance_custom_data(slot.y)

func set_overview(value: bool) -> void:
	if overview != value:
		overview = value
		_update_visibility()

func _update_visibility() -> void:
	for i in range(nodes.size()):
		nodes[i].visible = active_per_group[i] > 0 and visible_instance_count != 0 and (not overview or (keep_overview and far_nodes.is_empty()))
	for i in range(far_nodes.size()):
		far_nodes[i].visible = active_far[i] > 0 and overview and visible_instance_count != 0

func update_detail(_camera: Camera3D, origin: Vector3) -> void:
	for i in range(nodes.size()):
		var node := nodes[i]
		if max_distance > 0:
			# Fade in the shader over the last 12 metres; cull only fully faded chunks.
			var bounds := node.custom_aabb
			var center := node.position + bounds.get_center()
			center.y = origin.y
			var radius := Vector2(bounds.size.x, bounds.size.z).length() * .5
			node.visible = active_per_group[i] > 0 and not overview and visible_instance_count != 0 and center.distance_to(origin) - radius < max_distance + 4
