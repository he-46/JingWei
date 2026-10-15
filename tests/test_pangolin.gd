extends SceneTree
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
const Store = preload("res://scripts/save_store.gd")
const Actor = preload("res://scenes/actors/pangolin.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func unlock(state: JWState) -> void:
	for trip in range(4):
		state.tick(14)
		for index in range(4):
			state.pickup_stone(index)
		state.player = Vector2(2, 0)
		state.deposit(state.player)

func pose(actor: Node3D, clip: String, seconds: float) -> Skeleton3D:
	actor.animation_player.stop()
	actor.animation_player.play(clip, 0)
	actor.animation_player.advance(seconds)
	var skeleton: Skeleton3D = actor.model.find_children("*", "Skeleton3D", true, false)[0]
	skeleton.force_update_all_bone_transforms()
	return skeleton

func skin_point(skeleton: Skeleton3D, bone: String, rest_point: Vector3) -> Vector3:
	var index := skeleton.find_bone(bone)
	return skeleton.get_bone_global_pose(index) * skeleton.get_bone_global_rest(index).affine_inverse() * rest_point

func run() -> void:
	var actor = Actor.instantiate()
	root.add_child(actor)
	var skeleton: Skeleton3D = actor.model.find_children("*", "Skeleton3D", true, false)[0]
	var skin: MeshInstance3D = actor.model.find_child("PangolinSkin", true, false)
	expect(actor.model_scene.resource_path == "res://assets/models/characters/pangolin.glb", "default worker uses the production GLB")
	expect(skeleton.get_bone_count() == 18 and skeleton.get_bone_count() <= 28, "rig stays within bone budget")
	var tris := 0
	var weights_valid := true
	var uvs_valid := true
	for surface in range(skin.mesh.get_surface_count()):
		var arrays := skin.mesh.surface_get_arrays(surface)
		tris += arrays[Mesh.ARRAY_INDEX].size() / 3
		uvs_valid = uvs_valid and arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		weights_valid = weights_valid and weights.size() == arrays[Mesh.ARRAY_VERTEX].size() * 4
		for vertex in range(weights.size() / 4):
			var total := 0.0
			for influence in range(4):
				total += weights[vertex * 4 + influence]
			weights_valid = weights_valid and absf(total - 1) < 0.002
	expect(tris >= 5000 and tris <= 10000, "LOD0 is within the 5000-10000 triangle budget")
	expect(skin.mesh.get_surface_count() == 1 and skin.material_override == actor.surface_material, "entire worker uses one shared material surface")
	expect(actor.surface_material.albedo_texture.get_size() == Vector2(1024, 1024), "keratin paint atlas meets texture budget")
	expect(weights_valid and uvs_valid, "all vertices have UVs and normalized four-weight skinning")
	for clip in ["idle", "locked", "walk", "dig", "complete", "finished"]:
		expect(actor.animation_player.has_animation(clip), "worker clip imported: " + clip)
	actor.set_work(0, false, false, 0, false)
	expect(actor.animation_player.current_animation == "locked" and not actor.unlocked, "locked state has its own watchful animation")
	actor.set_work(0, false, false, 0, true)
	expect(actor.animation_player.current_animation == "idle", "unlocked idle remains distinct from locked state")
	var hand_differences: Array[float] = []
	var tail_positions: Array[Vector3] = []
	for phase in [0.23, 0.68]:
		skeleton = pose(actor, "dig", phase)
		var left := skeleton.get_bone_global_pose(skeleton.find_bone("FrontPaw_L")).origin
		var right := skeleton.get_bone_global_pose(skeleton.find_bone("FrontPaw_R")).origin
		hand_differences.append(left.y - right.y)
		tail_positions.append(skin_point(skeleton, "Tail_C", Vector3(0.17, 0.075, 2.28)))
	expect(hand_differences[0] > 0.10 and hand_differences[1] < -0.10, "dig alternates front paws instead of rocking only the whole body")
	expect(tail_positions[0].distance_to(tail_positions[1]) > 0.08, "tail actually counterbalances the digging stroke")
	skeleton = pose(actor, "walk", 0.2)
	var walking_left := skeleton.get_bone_global_pose(skeleton.find_bone("FrontPaw_L")).origin
	var walking_right := skeleton.get_bone_global_pose(skeleton.find_bone("FrontPaw_R")).origin
	expect(absf(walking_left.y - walking_right.y) > 0.10, "walk has a visible alternating stride")
	var idle_tail := skin_point(pose(actor, "idle", 0.1), "Tail_C", Vector3(0.17, 0.075, 2.28))
	var resting_tail := skin_point(pose(actor, "finished", 0.1), "Tail_C", Vector3(0.17, 0.075, 2.28))
	expect(idle_tail.distance_to(resting_tail) > 0.3, "finished state visibly curves the long tail")
	var min_claw := 100.0
	var max_snout := 0.0
	for frame in range(24):
		skeleton = pose(actor, "dig", frame * 0.90 / 24)
		max_snout = maxf(max_snout, -skin_point(skeleton, "Head", Vector3(0, 0.18, -1.45)).z)
		for side in ["L", "R"]:
			var claw := skin_point(skeleton, "FrontPaw_" + side, Vector3(-0.51 if side == "L" else 0.51, 0.035, -1.42))
			min_claw = minf(min_claw, claw.y)
	expect(max_snout <= 1.55, "head remains outside mountain collision footprint during the stroke")
	expect(min_claw >= -0.09, "only claw tips enter the shallow digging surface")
	actor.set_work(0, true, false, 0.2, true)
	actor.set_work(1, true, false, 0.1, true)
	expect(actor.target_index == 1 and actor.animation_player.current_animation == "walk", "a new working target starts an arrival stride")
	actor.advance(0.1, 0.1)
	var arrival: float = actor.arrival_remaining
	var paused: float = actor.animation_player.current_animation_position
	for frame in range(4):
		await process_frame
	expect(actor.arrival_remaining == arrival and is_equal_approx(paused, actor.animation_player.current_animation_position), "arrival and bone animation freeze without simulation advances")
	actor.advance(0.30, 0.4)
	expect(actor.animation_player.current_animation == "dig", "arrival returns to mining without delaying logical work")
	actor.play_complete(1)
	actor.set_work(2, true, false, 0, true)
	actor.advance(0.71, 0.71)
	expect(actor.current_action == &"" and actor.arrival_remaining > 0.3, "completion does not consume the following arrival stride's time")
	actor.advance(0.36, 1.07)
	expect(actor.animation_player.current_animation == "dig" and actor.last_completed_target == 1, "completion and arrival return to the new target's digging state")
	actor.set_work(2, false, true, 1, true)
	expect(actor.finished and not actor.working and actor.animation_player.current_animation == "finished", "all mines completed selects resting pose")
	actor.play_complete(2)
	actor.replace_model(actor.model_scene)
	expect(actor.current_action == &"" and actor.animation_player.current_animation == "finished", "model replacement cancels old completion and restores resting state")
	for target in [100000, 1000000, 10000000, 100000000]:
		var state = State.new(target)
		var world = World.new()
		root.add_child(world)
		world.setup(state)
		var animal = world.npc_views[0]["animal"]
		expect(world.npc_views.size() == 1 and animal.animation_player.current_animation == "locked", "one locked worker on map %d" % target)
		unlock(state)
		world.sync(state)
		expect(animal.working and animal.animation_player.current_animation == "dig", "real 128 delivered stones unlock formal worker on %d" % target)
		var npc: Vector2 = state.npc_position(state.pangolin_mountain())
		var mountain: Vector2 = state.mountain_position(state.pangolin_mountain())
		var forward: Vector3 = -animal.global_basis.z
		expect(Vector2(forward.x, forward.z).normalized().dot((mountain - npc).normalized()) > 0.999, "worker faces its actual mining face on %d" % target)
		expect(Vector2(world.npc_views[0]["root"].position.x, world.npc_views[0]["root"].position.z) == npc and state.nearby_mountain(npc, 2.1, true) == state.pangolin_mountain(), "model and dialogue point agree on %d" % target)
		var ledger: Dictionary = state.snapshot()
		for replay in range(4):
			animal.play_complete(0)
			world.animate(state, 0.1, false, false, -1)
		expect(state.snapshot() == ledger, "visual replays do not grant stock or cultivation on %d" % target)
		world.queue_free()
		await process_frame
	var loaded: Dictionary = Store.load_game("res://tests/fixtures/coast_v2.json")
	var legacy: JWState = loaded["state"]
	var legacy_world = World.new()
	root.add_child(legacy_world)
	var before: Dictionary = legacy.snapshot()
	legacy_world.setup(legacy)
	var legacy_actor = legacy_world.npc_views[0]["animal"]
	expect(legacy_actor.working and legacy_actor.target_index == legacy.next_mountain(), "legacy save restores worker target and work state")
	expect(is_equal_approx(legacy_actor.progress, float(legacy.mountains[legacy.next_mountain()]["work"]) / float(legacy.mountains[legacy.next_mountain()]["yield"])), "legacy partial progress drives presentation")
	expect(legacy.snapshot() == before and legacy_actor.last_completed_target == -1 and legacy_actor.arrival_remaining == 0, "loading a save does not replay historical completion or arrival")
	legacy_world.queue_free()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.choose_world(100000)
	unlock(game.state)
	game._refresh()
	var worker = game.world.npc_views[0]["animal"]
	var worker_id: int = worker.get_instance_id()
	var previous: int = game.state.next_mountain()
	game._advance_world(50)
	game._refresh()
	expect(worker.get_instance_id() == worker_id and worker.target_index == game.state.next_mountain() and worker.target_index != previous, "actual completion reuses the single worker at the new target")
	expect(worker.last_completed_target == previous and worker.current_action == &"complete", "actual tick sends exactly the completed target to its gesture")
	game.show_menu()
	game.set_physics_process(true)
	var frozen: float = worker.animation_player.current_animation_position
	var frozen_arrival: float = worker.arrival_remaining
	for frame in range(5):
		await physics_frame
	expect(is_equal_approx(frozen, worker.animation_player.current_animation_position) and worker.arrival_remaining == frozen_arrival, "real menu pause freezes completion and arrival")
	game.set_physics_process(false)
	game._modal_action("resume")
	game._advance_world(100000)
	game._refresh()
	worker.advance(1.1, 1.1)
	expect(worker.finished and worker.animation_player.current_animation == "finished" and game.world.npc_views.size() == 1, "same worker rests after the last mine finishes")
	var old = weakref(worker)
	game.choose_world(1000000)
	await process_frame
	expect(old.get_ref() == null and game.world.npc_views[0]["animal"].last_completed_target == -1, "new journey destroys old worker and completion state")
	game.queue_free()
	actor.queue_free()
	await process_frame
	print("PANGOLIN TESTS: %d checks, %d failures; claw minimum %.3f / snout reach %.3f" % [checks, failures, min_claw, max_snout])
	quit(1 if failures else 0)
