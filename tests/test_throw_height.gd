extends SceneTree

const State = preload("res://scripts/state.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	for profile in State.PROFILES:
		var state := State.new(int(profile["target"]), 10213)
		var ceiling := state.high_flight_height()
		var middle := (State.BIRD_HOVER_HEIGHT + ceiling) * 0.5
		expect(is_equal_approx(state.throw_distance(), 4.0) and is_equal_approx(state.throw_distance(-5), 4.0), "hover and lower heights preserve base range")
		expect(is_equal_approx(state.throw_distance(middle), 6.0) and is_equal_approx(state.throw_distance(ceiling), 8.0), "all maps interpolate actual height to double range")
		expect(is_equal_approx(state.throw_distance(ceiling + 100), 8.0) and is_equal_approx(state.throw_distance(NAN), 4.0), "invalid and excess altitude cannot extend range")
		state.upgrades["throw"] = state.upgrade_limit("throw")
		expect(is_equal_approx(state.throw_distance(ceiling), state.throw_distance() * 2), "height bonus stacks with range upgrades on every scale")
		state.upgrades["throw"] = 0
		state.player = Vector2(-2, 0)
		expect(not state.can_throw(Vector2(5, 0)) and state.can_throw(Vector2(5, 0), ceiling) and not state.can_throw(Vector2(6.01, 0), ceiling), "height changes real horizontal reach with a strict upper boundary")
		expect(not state.can_throw(state.map_origin - Vector2.ONE, ceiling), "high flight still respects map boundaries")

	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.choose_world(100000)
	await process_frame
	game.save_enabled = false
	game.state.player = Vector2(-2.5, 3)
	game.world.bird_body.position = Vector3(-2.5, State.BIRD_HOVER_HEIGHT, 3)
	game.world.update_camera(game.state, 1, true)
	for index in range(4):
		game.state.pickup_stone(index)
	var cargo: int = game.state.carried
	var target := Vector2(4.5, 3)
	expect(cargo > 0 and game.world.point_visible(target), "height scenario uses real gathered cargo and a visible sea target")
	expect(game.deposit_at(target) == 0 and game.state.carried == cargo, "low flight rejects distant sea without consuming stones")
	Input.action_press("jw_high")
	await physics_frame
	expect(game.deposit_at(target) == 0, "pressing Space does not grant the peak bonus instantly")
	for frame in range(110):
		await physics_frame
	var bird: CharacterBody3D = game.world.bird_body
	var reach: float = game.state.throw_distance(bird.position.y)
	expect(reach > 7.9 and reach <= 8.0, "physical ascent gradually reaches the double-range ceiling")
	expect(is_equal_approx(game.world.range_ring.scale.x, reach), "gold ring follows actual flight height")
	game.world.aim_point = target
	game.world.animate(game.state, 0, false, true, game.state.cell_at(target))
	expect(game.world.cell_marker.material_override.albedo_color == Color("f3d491"), "reachable high-flight target has a gold marker")
	game.hud.update_state(game.state, "", game.state.cell_at(target), target, bird.position.y)
	expect(game.hud.cell_label.text.contains("射程 8.0") and not game.hud.cell_label.text.contains("超距"), "target HUD uses the same altitude range")
	game._refresh()
	expect(game.hud.context.text.contains("高飞") and game.hud.interact_button.disabled, "high-flight context shows reach and disables ground collection")
	var total: int = game.state.remaining_stones()
	expect(game.deposit_at(target) == cargo and game.state.total_delivered == cargo, "high-flight validation and resource settlement agree")
	expect(game.state.remaining_stones() == total, "height-assisted throw conserves resources")
	Input.action_release("jw_high")
	await physics_frame
	for frame in range(110):
		await physics_frame
	expect(game.state.throw_distance(bird.position.y) < 4.01 and game.world.range_ring.scale.x < 4.01, "descent contracts reach and ring back to base")
	game.world.aim_point = target
	game.world.animate(game.state, 0, false, false, game.state.cell_at(target))
	expect(game.world.cell_marker.material_override.albedo_color == Color("d38b79"), "same target becomes out of range after landing")
	game.hud.update_state(game.state, "", game.state.cell_at(target), target, bird.position.y)
	expect(game.hud.cell_label.text.contains("超距"), "HUD reflects lost altitude reach")
	var restored := State.from_snapshot(game.state.snapshot())
	expect(restored != null and is_equal_approx(restored.throw_distance(), 4.0), "save roundtrip keeps base progression without persisting temporary altitude")
	game.choose_world(1000000)
	expect(is_equal_approx(game.world.bird_body.position.y, State.BIRD_HOVER_HEIGHT), "new journey resets flight height")
	game.queue_free()
	await process_frame
	print("THROW HEIGHT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
