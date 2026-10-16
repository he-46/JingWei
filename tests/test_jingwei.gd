extends SceneTree
const Actor = preload("res://scenes/actors/jingwei.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in range(mesh.get_surface_count()):
		count += mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3
	return count

func run() -> void:
	var bird = Actor.instantiate()
	root.add_child(bird)
	var skeleton: Skeleton3D = bird.model.find_children("*", "Skeleton3D", true, false)[0]
	var skin: MeshInstance3D = bird.model.find_child("JingweiSkin", true, false)
	var light: MeshInstance3D = bird.model.get_node(bird.cargo_path)
	var full: MeshInstance3D = bird.model.get_node(bird.full_cargo_path)
	expect(bird.model_scene.resource_path == "res://assets/models/characters/jingwei.glb", "default actor uses the production GLB")
	expect(skeleton.get_bone_count() <= 24 and skeleton.get_bone_count() == 12, "production rig stays within bone budget")
	expect(triangles(skin.mesh) + triangles(full.mesh) <= 8000, "full cargo plus bird stays within 8000 triangle budget")
	expect(triangles(skin.mesh) >= 4000, "production silhouette has authored geometry density")
	expect(skin.material_override == bird.surface_material and full.material_override == bird.surface_material, "skin and cargo share the authored material")
	var atlas: Texture2D = bird.surface_material.albedo_texture
	expect(atlas.get_size() == Vector2(1024, 1024), "paint atlas meets texture budget")
	var valid_weights := true
	for node in [skin, light, full]:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			valid_weights = valid_weights and weights.size() == arrays[Mesh.ARRAY_VERTEX].size() * 4
			for vertex in range(weights.size() / 4):
				var total := 0.0
				for influence in range(4):
					total += weights[vertex * 4 + influence]
				valid_weights = valid_weights and absf(total - 1.0) < 0.002
	expect(valid_weights, "every exported vertex has normalized weights and at most four influences")
	for clip in ["idle", "fly", "carry_fly", "turn_left", "turn_right", "gather", "throw"]:
		expect(bird.animation_player.has_animation(clip), "production clip available: " + clip)
	for item in [[0.0, 0], [0.01, 1], [0.65, 1], [0.66, 2], [1.0, 2], [1000000.0, 2], [-1.0, 0]]:
		bird.set_load(item[0])
		expect(bird.load_stage == item[1] and light.visible == (item[1] == 1) and full.visible == (item[1] == 2), "cargo uses finite stages at fraction %s" % item[0])
	var wrist_left := skeleton.find_bone("Wrist_L")
	var wrist_right := skeleton.find_bone("Wrist_R")
	var heights: Array[float] = []
	for phase in [0.16, 0.49]:
		bird.animation_player.stop()
		bird.animation_player.play("fly", 0)
		bird.animation_player.advance(phase)
		skeleton.force_update_all_bone_transforms()
		var left := skeleton.get_bone_global_pose(wrist_left).origin
		var right := skeleton.get_bone_global_pose(wrist_right).origin
		heights.append(left.y)
		expect(absf(left.y - right.y) < 0.003 and absf(left.x + right.x) < 0.003, "mirrored wings flap symmetrically at %s seconds" % phase)
	expect(absf(heights[0] - heights[1]) > 0.35, "flight has a visible upstroke and downstroke")
	bird.set_load(0)
	bird.rotation.y = 0
	bird.set_facing(Vector2.RIGHT, 0.016)
	bird.set_motion(true, false)
	expect(bird.animation_player.current_animation == "turn_right", "a right heading change selects the turn gesture")
	bird.advance(0.05, 0.05)
	expect(absf(bird.model.rotation.z) > 0.01, "turning adds a smooth bank without moving physics body")
	for index in range(30):
		bird.set_facing(Vector2.RIGHT, 0.016)
		bird.set_motion(true, false)
		bird.advance(0.016, index * 0.016)
	expect(bird.animation_player.current_animation == "fly", "settled heading returns to normal flight")
	bird.rotation.y = 3.1
	bird.set_facing(Vector2(-sin(-3.1), -cos(-3.1)), 0.05)
	expect(absf(angle_difference(3.1, bird.rotation.y)) < 0.1, "heading wrap takes the shortest turn")
	bird.set_motion(false, false)
	bird.play_gather(10)
	bird.advance(0.41, 0.41)
	expect(bird.current_action == &"gather", "gather remains active until its 0.42-second deadline")
	bird.advance(0.02, 0.43)
	expect(bird.current_action == &"", "gather ends before the next held-E collection")
	bird.play_throw(10)
	bird.advance(0.20, 0.20)
	var paused: float = bird.animation_player.current_animation_position
	for index in range(4):
		await process_frame
	expect(is_equal_approx(paused, bird.animation_player.current_animation_position), "throw freezes during simulation pause")
	bird.play_throw(10)
	expect(is_zero_approx(bird.animation_player.current_animation_position), "rapid throw resets its gesture")
	bird.advance(0.47, 0.47)
	expect(bird.current_action == &"throw", "throw remains active before the 0.48-second impact")
	bird.advance(0.02, 0.49)
	expect(bird.current_action == &"", "throw finishes on the existing impact schedule")
	bird.set_load(1)
	bird.set_motion(false, true)
	expect(bird.animation_player.current_animation == "carry_fly", "loaded high hover selects the slower cargo flight")
	bird.play_gather(10)
	bird.replace_model(bird.model_scene)
	expect(bird.current_action == &"" and bird.load_stage == 2, "replacement interrupts action and restores cargo state")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.choose_world(100000)
	await game.wait_until_ready()
	var body: CharacterBody3D = game.world.bird_body
	expect(is_equal_approx(body.get_child(0).shape.radius, game.state.BIRD_COLLISION_RADIUS), "formal mesh does not change collision radius")
	var ledger: Dictionary = game.state.snapshot()
	for index in range(12):
		game.world.bird_model.play_gather(10)
		game.world.bird_model.play_throw(10)
		game.world.animate(game.state, 0.1, true, index % 2 == 0, -1)
	expect(game.state.snapshot() == ledger, "production gesture replays and elevation changes cannot settle resources")
	var old = weakref(game.world.bird_model)
	game.choose_world(1000000)
	await game.wait_until_ready()
	await process_frame
	expect(old.get_ref() == null and game.world.bird_model.current_action == &"" and game.world.bird_model.load_stage == 0, "new map frees the old rig and cargo stage")
	game.queue_free()
	bird.queue_free()
	await process_frame
	print("JINGWEI TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
