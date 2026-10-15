extends SceneTree
const FX = preload("res://scripts/visuals/action_feedback.gd")
const State = preload("res://scripts/state.gd")
var checks := 0
var failures := 0
var hits: Array = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += count_nodes(child)
	return total

func event(fx: Node3D, kind: String) -> int:
	return int(fx.events.get(kind, 0))

func place(game: Node3D, point: Vector2) -> void:
	game.state.player = point
	game.world.bird_body.position = Vector3(point.x, State.BIRD_HOVER_HEIGHT, point.y)
	game.world.bird_body.velocity = Vector3.ZERO
	game.world.update_camera(game.state, 1, true)

func run() -> void:
	for id in FX.RELICS:
		var instance: Node3D = FX.RELICS[id].instantiate()
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		expect(meshes.size() == 1 and meshes[0].transform.is_equal_approx(Transform3D.IDENTITY), id + " one mesh with applied transforms")
		var mesh: Mesh = meshes[0].mesh
		var arrays := mesh.surface_get_arrays(0)
		expect(mesh.get_surface_count() == 1 and arrays[Mesh.ARRAY_INDEX].size() / 3 <= 1500, id + " single material within 1500-triangle budget")
		expect(arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size(), id + " painted UVs complete")
		expect(instance.find_children("*", "CollisionObject3D", true, false).is_empty() and instance.find_children("*", "Skeleton3D", true, false).is_empty(), id + " no gameplay collision or skeleton")
		var image: Image = load("res://assets/icons/relics/%s.png" % id).get_image()
		image.decompress()
		var visible_pixels := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				visible_pixels += int(image.get_pixel(x, y).a > .5)
		expect(image.get_size() == Vector2i(256, 256) and image.get_pixel(0, 0).a == 0 and visible_pixels > 4000, id + " transparent 256px icon contains a readable silhouette")
		instance.free()
	var fx := FX.new()
	root.add_child(fx)
	var budget := count_nodes(fx)
	fx.landed.connect(func(sea: bool, formed: bool, completed: bool, epoch: int) -> void: hits.append([sea, formed, completed, epoch]))
	expect(fx.active_counts() == Vector3i.ZERO, "new world starts with every pooled effect hidden")
	fx.throw_stone(Vector3(0, 2, 0), Vector3(2, .25, 0), true, true, false, 12)
	fx.advance(.24)
	expect(hits.is_empty() and fx.flights[0].node.position.is_equal_approx(Vector3(1, 2.625, 0)), "halfway point follows fixed parabolic flight with no early impact")
	fx.advance(.239)
	expect(hits.is_empty(), "impact remains pending before 0.48 seconds")
	fx.advance(.0011)
	expect(hits == [[true, true, false, 12]], "landing signal carries settlement flags and launch audio epoch at 0.48 seconds")
	expect(event(fx, "water") == 1 and event(fx, "fill") == 1, "one successful landing produces splash and formation once")
	fx.advance(4)
	expect(fx.active_counts() == Vector3i.ZERO and hits.size() == 1, "expired effects return to pool without replaying landing")
	for kind in ["gather", "throw", "water", "land", "fill", "mined"]:
		fx.burst(kind, Vector3.ZERO, Vector3.UP)
		expect(fx.active_counts().y > 0, kind + " uses reusable burst")
	if DisplayServer.get_name() != "headless":
		fx.advance(.1)
		for slot in fx.bursts:
			if not slot.active:
				continue
			var visible_chips := true
			for index in range(FX.CHIP_COUNT):
				var transform: Transform3D = slot.chips.get_instance_transform(index)
				visible_chips = visible_chips and transform.origin.is_finite() and transform.basis.determinant() > 0
			expect(visible_chips and slot.node.visible, "renderer receives nonzero finite transforms for " + slot.kind)
	for id in FX.RELICS:
		fx.discover(id, Vector3.ZERO)
	fx.advance(.3)
	expect(fx.active_counts().z == 3 and fx.relics.basket.node.position.y > 0, "three different discoveries rise locally without modal UI")
	fx.advance(3)
	expect(fx.active_counts() == Vector3i.ZERO, "discovery display finishes within 2.2 seconds")
	for index in range(2000):
		fx.throw_stone(Vector3.UP, Vector3.ZERO, index % 2 == 0, false, false, 1)
		fx.burst("gather", Vector3.ZERO, Vector3.UP)
		fx.discover("basket", Vector3.ZERO)
	expect(fx.active_counts() == Vector3i(FX.FLIGHT_LIMIT, FX.BURST_LIMIT, 1), "spam is bounded to 12 flights, 24 bursts and three model slots")
	expect(count_nodes(fx) == budget and fx.suppressed_flights == 2000 - FX.FLIGHT_LIMIT, "thousands of events allocate no additional nodes or timers")
	expect(fx.throw_stone(Vector3.UP, Vector3.ZERO, true, true, true, 9), "final completion retains a flight even when ordinary pool is saturated")
	fx.advance(5)
	expect(count_nodes(fx) == budget and fx.active_counts() == Vector3i.ZERO, "entire pool reusable after saturation")
	var completions := 0
	for hit in hits:
		completions += int(hit[2])
	expect(completions == 1, "saturated final flight emits completion exactly once")
	fx.free()
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.choose_world(100000)
	game.set_physics_process(false)
	game.set_process(false)
	game.soundscape.set_muted(false)
	expect(game.feedback.active_counts() == Vector3i.ZERO, "choosing a fresh map never synthesizes historical discoveries")
	game.interact()
	expect(event(game.feedback, "gather") == 1 and game.state.carried > 0, "real successful gather triggers exactly one feedback event")
	game.state.carried = game.state.capacity()
	game.interact()
	expect(event(game.feedback, "gather") == 1, "full bag rejects gather feedback")
	game.world.bird_body.position.y = 5
	game.interact()
	expect(event(game.feedback, "gather") == 1, "high-flight gathering never emits success")
	game.world.bird_body.position.y = State.BIRD_HOVER_HEIGHT
	game.state.carried = 0
	var amounts: Array[int] = game.state.stone_amounts.duplicate()
	game.state.stone_amounts.fill(0)
	game.interact()
	expect(event(game.feedback, "gather") == 1, "depleted scattered resources never emit collection feedback")
	game.state.stone_amounts = amounts
	place(game, Vector2(-1, 3))
	game.state.carried = 0
	game.deposit_at(Vector2(2, 3))
	expect(event(game.feedback, "launch") == 0, "empty bag rejects success effects")
	game.state.carried = 10
	game.deposit_at(Vector2(20, 3))
	expect(event(game.feedback, "launch") == 0 and game.state.carried == 10, "out-of-range operation emits nothing and preserves cargo")
	game.deposit_at(Vector2(10000, 3))
	expect(event(game.feedback, "launch") == 0, "outside fog/map operation emits nothing")
	game.show_menu()
	game.deposit_at(Vector2(2, 3))
	expect(event(game.feedback, "launch") == 0, "modal rejects throw")
	game._modal_action("resume")
	expect(game.deposit_at(Vector2(2, 3)) == 10 and event(game.feedback, "launch") == 1, "successful state deposit launches one visual flight")
	var snapshot: Dictionary = game.state.snapshot()
	game.feedback.advance(.2)
	game.show_menu()
	game._process(1.0)
	expect(game.feedback.active_counts().x == 1 and is_equal_approx(game.feedback.flights[0].age, .2), "pause freezes flight and impact clock")
	expect(not game.soundscape.last_variant.has("water"), "paused flight never emits impact audio")
	game._modal_action("resume")
	game._process(.281)
	expect(event(game.feedback, "water") == 1 and game.soundscape.last_variant.has("water"), "resume continues remaining flight and uses same clock for sound")
	expect(game.state.snapshot() == snapshot, "visual advancement cannot mutate state or apply a second deposit")
	game.soundscape.reset()
	game.state.carried = 5
	game.deposit_at(Vector2(2, 3))
	game.soundscape.set_muted(true)
	game.soundscape.set_muted(false)
	game.feedback.advance(.5)
	expect(not game.soundscape.last_variant.has("water"), "mute/unmute discards pre-mute pending landing sound")
	game.soundscape.reset()
	game.state.carried = 5
	game.deposit_at(Vector2(-1, 3))
	game.feedback.advance(.5)
	expect(event(game.feedback, "land") == 1 and game.soundscape.last_variant.has("land"), "real land deposit has distinct dust and impact audio")
	game.state.carried = 5
	game.deposit_at(Vector2(2, 3))
	var old: WeakRef = weakref(game.feedback)
	game.choose_world(100000)
	await process_frame
	game.feedback.advance(2)
	expect(old.get_ref() == null and game.feedback.events.is_empty(), "map replacement releases all prior models, flights and bursts")
	expect(not game.soundscape.last_variant.has("water"), "old world cannot emit late landing audio")
	# Real unlock and mining timeline; no invented drops or altered artifact factors.
	place(game, Vector2(2, 3))
	game.state.carried = 128
	game.state.total_generated += 128
	game.deposit_at(Vector2(2, 3))
	game._advance_world(5000)
	expect(game.state.artifacts.size() == 3 and event(game.feedback, "discover") == 3, "one long real mining tick discovers each catalog relic once")
	expect(event(game.feedback, "mined") == game.state.mountains.size(), "each newly settled nearby mountain produces one bounded completion burst")
	expect(is_equal_approx(game.state.relic_factor(), 1.2), "basket bonus remains exactly the state-defined 20 percent")
	game._advance_world(.2)
	expect(event(game.feedback, "discover") == 3 and event(game.feedback, "mined") == game.state.mountains.size(), "settled mines and collected relics never replay next tick")
	game._refresh()
	game.hud.select_tab("relics")
	await process_frame
	await process_frame
	for index in range(3):
		expect(game.hud.relic_icons[index].modulate == Color.WHITE and game.hud.relic_labels[index].text.contains(State.ARTIFACT_CATALOG[index].name), "existing artifact tab shows matching discovered icon and effect")
	expect(game.hud.drawer.size.y < 360 and not game.hud.modal_open, "artifact presentation retains compact drawer without forced interruption")
	var saved: Dictionary = game.state.snapshot()
	game.choose_world(100000)
	game.state = State.from_snapshot(saved)
	game._refresh()
	game._advance_world(.2)
	expect(event(game.feedback, "discover") == 0, "restoring collected artifacts never replays discovery")
	game.choose_world(100000)
	place(game, Vector2(2, 3))
	game.state.carried = game.state.target_stones
	game.state.total_generated += game.state.carried
	game.deposit_at(Vector2(2, 3))
	game._physics_process(.001)
	expect(game.state.won and game.feedback.completion_pending() and not game.hud.modal_open, "final deposit leaves the last flight visible before opening completion modal")
	game.feedback.advance(.479)
	game._physics_process(.001)
	expect(not game.hud.modal_open, "completion modal cannot freeze the final flight before its landing")
	game.feedback.advance(.0011)
	game._physics_process(.001)
	expect(game.hud.modal_open and game.win_shown and not game.feedback.completion_pending(), "final landing finishes before the ordinary completion modal pauses the world")
	game.queue_free()
	await create_timer(.1).timeout
	var preview: Node3D = load("res://scenes/art/feedback_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	expect(not preview.save_enabled and not preview.selection_pending and preview.state.target_stones == 100000, "F6 playable feedback sample never reads or writes player saves")
	preview.queue_free()
	await process_frame
	print("FEEDBACK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
