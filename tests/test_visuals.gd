extends SceneTree
const State = preload("res://scripts/state.gd")
const MountainVisual = preload("res://scripts/visuals/mountain_visual.gd")
var checks := 0
var failures := 0
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func move_player(point: Vector2) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, State.BIRD_HOVER_HEIGHT, point.y)
	game.world.update_camera(game.state, 1.0, true)

func run() -> void:
	game = load("res://scenes/art/pipeline_preview.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	game.choose_world(100000)
	var bird = game.world.bird_model
	var animal = game.world.npc_views[0]["animal"]
	expect(not game.save_enabled, "preview never opens or overwrites a player save")
	expect(bird.animation_player != null and animal.animation_player != null, "both GLBs import an animation player")
	expect(bird.model.find_children("*", "Skeleton3D", true, false).size() == 1, "bird imports a real skeleton")
	expect(bird.model.find_child("WingLeft", true, false) == null and bird.model.find_child("Load", true, false) == null, "imported hierarchy has no legacy child names")
	for clip in ["idle", "fly", "carry_fly", "gather", "throw"]:
		expect(bird.animation_player.has_animation(clip), "bird clip imported: " + clip)
	for clip in ["idle", "dig", "complete", "finished"]:
		expect(animal.animation_player.has_animation(clip), "worker clip imported: " + clip)
	var cargo: Node3D = bird.model.get_node_or_null(bird.cargo_path)
	expect(cargo != null, "prefab resolves its optional cargo attachment")
	if cargo:
		bird.set_load(0.5)
		expect(cargo.visible and bird.load_fraction == 0.5, "imported cargo follows normalized load")
		bird.set_load(0)
		expect(not cargo.visible, "empty load hides the attachment")
	var ledger: Dictionary = game.state.snapshot()
	bird.set_facing(Vector2.RIGHT, 1)
	bird.set_motion(true, false)
	bird.advance(0.15, 0.15)
	expect(is_equal_approx(bird.rotation.y, -PI / 2), "model front follows gameplay direction")
	expect(bird.animation_player.current_animation == "fly", "moving selects flight clip")
	bird.set_motion(false, true)
	expect(bird.high_flight and bird.animation_player.current_animation == "fly", "high hover also flies")
	bird.set_load(1)
	bird.set_motion(false, true)
	expect(bird.animation_player.current_animation == "carry_fly", "loaded high flight selects cargo clip")
	bird.play_gather(10)
	var skeleton: Skeleton3D = bird.model.find_children("*", "Skeleton3D", true, false)[0]
	var bone_index := skeleton.find_bone("Root")
	var initial_pose := skeleton.get_bone_pose_rotation(bone_index)
	bird.advance(0.2, 0.2)
	expect(not skeleton.get_bone_pose_rotation(bone_index).is_equal_approx(initial_pose), "imported action actually deforms skeleton pose")
	var paused_position: float = bird.animation_player.current_animation_position
	for index in range(4):
		await process_frame
	expect(is_equal_approx(bird.animation_player.current_animation_position, paused_position), "imported animation stays paused without simulation advances")
	bird.play_throw(10)
	bird.advance(0.2, 0.4)
	bird.play_throw(10)
	expect(is_zero_approx(bird.animation_player.current_animation_position), "rapid repeated throw restarts gesture")
	bird.advance(1.2, 1.6)
	expect(bird.current_action == &"" and bird.animation_player.current_animation == "carry_fly", "gesture returns to latest movement state")
	expect(game.state.snapshot() == ledger, "replaying or interrupting imported animations cannot change resource ledger")
	move_player(game.state.stone_positions[0])
	game.interact()
	expect(game.state.carried == 10 and bird.current_action == &"gather", "successful gameplay gather sends visual result")
	move_player(Vector2(-2.5, 3))
	var thrown: int = game.deposit_at(Vector2(0.25, 3))
	expect(thrown == 10 and bird.current_action == &"throw" and game.state.total_delivered == 10, "successful gameplay throw settles once and starts gesture")
	bird.advance(2, 2)
	expect(game.deposit_at(Vector2(0.25, 3)) == 0 and bird.current_action == &"", "rejected empty throw does not animate")
	var source: PackedScene = load("res://assets/models/pipeline_examples/mountain.glb")
	var mesh := MountainVisual.imported_mesh(source)
	expect(mesh != null and is_equal_approx(mesh.get_aabb().size.y, 1) and is_zero_approx(mesh.get_aabb().position.y), "mountain exports ground origin and unit height")
	expect(game.world.mountain_batches[0].mesh == mesh, "world actually uses the imported mountain mesh")
	var fixture = State.new()
	fixture.mountains[0]["work"] = float(fixture.mountains[0]["yield"]) * 0.5
	var visual = MountainVisual.from_state(fixture, 0)
	expect(visual.remaining == 0.5 and is_equal_approx(visual.collision_height, fixture.mountain_height(0) * 0.5), "half excavated mountain shares logical dimensions")
	var original_remaining: float = visual.remaining
	fixture.mountains[0]["work"] = fixture.mountains[0]["yield"]
	expect(visual.remaining == original_remaining, "visual snapshot does not retain mutable mountain data")
	for trip in range(4):
		game.state.tick(14)
		for index in range(4):
			game.state.pickup_stone(index)
		move_player(Vector2(-1, 0))
		game.throw_forward()
	game._refresh()
	expect(animal.working and animal.target_index == game.state.next_mountain(), "worker targets logical smallest unfinished mountain")
	var worker_id: int = animal.get_instance_id()
	var previous: int = game.state.next_mountain()
	game._advance_world(100000)
	game._refresh()
	expect(animal.last_completed_target == previous and animal.current_action == &"complete", "completed mining sends a presentation-only completion event")
	expect(animal.finished and not animal.working and animal.get_instance_id() == worker_id, "same worker rests after all mines finish")
	animal.advance(2, 2)
	expect(animal.animation_player.current_animation == "finished", "completion returns to finished state")
	await process_frame
	expect(game.world.mountain_collisions[0].disabled and game.world.mountain_cache[0] == 0, "completed imported mountain disappears and releases collision")
	var snapshot: Dictionary = game.state.snapshot()
	for index in range(10):
		bird.play_throw(20)
		animal.play_complete(previous)
		bird.advance(0.2, index * 0.2)
		animal.advance(0.2, index * 0.2)
	expect(snapshot == game.state.snapshot(), "completion replays never grant stock or cultivation")
	var old_bird = weakref(bird)
	game.choose_world(1000000)
	await process_frame
	expect(old_bird.get_ref() == null and game.world.bird_model.current_action == &"", "new journey frees previous rig and interrupts old gestures")
	expect(game.world.bird_model.model_scene != null and game.state.total_delivered == 0, "new journey retains import configuration without old resources")
	expect(State.SAVE_VERSION == 3, "visual integration leaves save schema unchanged")
	print("VISUAL TESTS: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
