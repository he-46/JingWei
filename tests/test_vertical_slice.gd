extends SceneTree
## Real 60 Hz controls and normal simulation. No teleporting, injected cargo, or time jumps
## during the resource-cycle walkthrough. Optional render captures are separate evidence.
const State = preload("res://scripts/state.gd")
var game: Node3D
var checks := 0
var failures := 0
var output := ""
var clip_frame := 0
var records: Array = []
var clip_labels: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func idle(frames: int) -> void:
	for frame in range(frames):
		await physics_frame

func clear_motion() -> void:
	for action in ["jw_left", "jw_right", "jw_up", "jw_down"]:
		Input.action_release(action)

func steer(direction: Vector2) -> void:
	var camera: Camera3D = game.world.camera
	var right := Vector2(camera.global_basis.x.x, camera.global_basis.x.z).normalized()
	var down := Vector2(camera.global_basis.z.x, camera.global_basis.z.z).normalized()
	var screen := Vector2(direction.dot(right), direction.dot(down))
	clear_motion()
	for item in [["jw_right", screen.x], ["jw_left", -screen.x], ["jw_down", screen.y], ["jw_up", -screen.y]]:
		if float(item[1]) > .001:
			Input.action_press(item[0], item[1])

func travel(point: Vector2, clip_label: String = "") -> void:
	var reached := false
	for frame in range(1200):
		var offset: Vector2 = point - game.state.player
		if offset.length() < .24:
			reached = true
			break
		steer(offset.normalized())
		await physics_frame
		if not output.is_empty() and not clip_label.is_empty() and frame % 6 == 0:
			await save_clip_frame(clip_label)
	clear_motion()
	await idle(14)
	if not reached:
		expect(false, "physical route blocked: %s -> %s" % [game.state.player, point])
		quit(1)

func gather() -> void:
	var before: int = game.state.carried
	Input.action_press("jw_interact")
	for frame in range(90):
		await physics_frame
		if game.state.carried > before or game.hud.modal_open:
			break
	Input.action_release("jw_interact")
	if game.hud.modal_open:
		expect(false, "gather route unexpectedly reached NPC dialogue")
		game._modal_action("resume")

func throw_at(point: Vector2, record_clip: bool = false) -> int:
	# Same method used by a mouse click after screen-to-world projection.
	var amount: int = game.deposit_at(point)
	for frame in range(34):
		await physics_frame
		if not output.is_empty() and record_clip and frame % 6 == 0:
			await save_clip_frame("投石与落点")
	return amount

func save_clip_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.resize(720, 450, Image.INTERPOLATE_LANCZOS)
	image.save_png(output.path_join("clip/%04d.png" % clip_frame))
	clip_frame += 1
	clip_labels.append(label)

func checkpoint(label: String, record_clip: bool = true) -> void:
	# The logical completion tick can precede the ordinary 0.15s presentation
	# refresh. Capture the same settled state in the HUD and resource meshes.
	game._refresh()
	var s: JWState = game.state
	expect(State.from_snapshot(s.snapshot()) != null, label + ": resources and cultivation remain valid save data")
	records.append({"stage": label, "elapsed_simulation_seconds": s.elapsed,
		"player": [s.player.x, s.player.y], "carried": s.carried, "generated": s.total_generated,
		"delivered": s.total_delivered, "cultivation": s.cultivation, "filled_cells": s.filled_count,
		"first_mountain_work": s.mountains[0].work, "first_mountain_stock": s.mountains[0].stock,
		"artifacts": s.artifacts.duplicate(), "feedback_counts": str(game.feedback.active_counts())})
	print("SLICE_STAGE ", label, " delivered=", s.total_delivered, " stock=", s.mountains[0].stock)
	if output.is_empty():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	if record_clip:
		for frame in range(12):
			await idle(6)
			await save_clip_frame(label)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-output="):
			output = arg.trim_prefix("--capture-output=")
	if not output.is_empty():
		if DisplayServer.get_name() == "headless":
			push_error("Walkthrough captures require a real renderer.")
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join("clip")))
		DisplayServer.window_set_size(Vector2i(1440, 900))
		root.size = Vector2i(1440, 900)
	game = load("res://scenes/art/vertical_slice.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	await idle(3)
	expect(not game.save_enabled and not game.selection_pending and game.state.world_seed == 10213, "sample starts fixed seed without loading player saves")
	expect(game.state.total_generated == 0 and game.state.total_delivered == 0 and game.state.artifacts.is_empty(), "sample starts a genuine unplayed resource ledger")
	expect(game.world.bird_model.model_scene.resource_path == "res://assets/models/characters/jingwei.glb" and game.world.npc_views[0].animal.model_scene.resource_path == "res://assets/models/characters/pangolin.glb", "sample uses both formal characters")
	expect(game.world.sample_enabled and game.world.npc_views.size() == 1, "sample uses formal first mountain and a single worker")
	await checkpoint("01-birth")
	for trip in range(4):
		for stone in range(4):
			if game.state.carried == game.state.capacity():
				break
			await travel(game.state.stone_positions[stone])
			await gather()
		expect(game.state.carried == 32, "trip %d collects a full starter bag through E input" % (trip + 1))
		if trip == 0:
			await checkpoint("02-full-basket")
		await travel(Vector2(-1, 3), "衔石飞向海岸" if trip == 0 else "")
		var amount := await throw_at(Vector2(.25, 3), trip == 0)
		expect(amount == 32, "trip %d deposits only carried stones through the real throw entry" % (trip + 1))
		if trip == 0:
			await checkpoint("03-first-shore")
		if trip < 3:
			# Wait for ordinary scatter refresh; never skip or directly call state.tick.
			for frame in range(1200):
				if game.state.stone_amounts[0] > 0 and game.state.stone_amounts[1] > 0 and game.state.stone_amounts[2] > 0 and game.state.stone_amounts[3] > 0:
					break
				await physics_frame
	expect(game.state.total_delivered == 128 and game.state.mountains[0].started, "four physical gathering trips unlock the smallest mountain at 128")
	await checkpoint("04-mining-unlocked")
	game.buy_upgrade("bag")
	expect(int(game.state.upgrades.bag) == 1 and game.state.cultivation == 12, "upgrade spends actual cultivation at the ordinary price")
	await travel(game.state.npc_position(0))
	Input.action_press("jw_interact")
	for frame in range(90):
		await physics_frame
		if game.hud.modal_open:
			break
	Input.action_release("jw_interact")
	expect(game.hud.modal_open and game.hud.modal_title.text == "穿山甲", "sole worker can be physically approached for dialogue")
	var paused: float = game.state.elapsed
	await idle(30)
	expect(game.state.elapsed == paused, "dialogue freezes real mining progress")
	game._modal_action("resume")
	await checkpoint("05-working-mountain")
	for frame in range(6000):
		if game.state.artifacts.has("basket"):
			break
		await physics_frame
	expect(game.state.artifacts.has("basket") and game.feedback.events.get("discover", 0) == 1, "normal mining time discovers the planned basket exactly once")
	await checkpoint("06-relic-discovery")
	for frame in range(6000):
		if game.state.mountains[0].settled:
			break
		await physics_frame
	expect(game.state.mountains[0].settled and game.state.mountains[0].stock == 1024, "first mountain yields its finite stock once through normal simulation")
	await checkpoint("07-quarry-complete")
	var collected := 0
	var trips := 0
	var last_amount := 0
	while game.state.mountains[0].stock > 0 and trips < 40:
		await travel(game.state.mountain_position(0))
		for action in range(8):
			if game.state.carried >= game.state.capacity() or game.state.mountains[0].stock == 0:
				break
			var before: int = game.state.carried
			await gather()
			collected += game.state.carried - before
		if game.state.mountains[0].stock == 0:
			last_amount = game.state.carried
			break
		await travel(Vector2(-1, 3), "开山后的石料搬运" if trips == 0 else "")
		await throw_at(Vector2(.25, 3))
		trips += 1
	expect(collected == 1024 and game.state.mountains[0].stock == 0, "ordinary E collection and physical hauling exhaust exactly 1024 quarry stones")
	expect(game.state.pickup_pile(0) == 0, "exhausted mountain never produces more stones")
	await checkpoint("08-empty-quarry")
	# Carry the final quarry load to the nearest incomplete sea cell it can finish.
	var target := -1
	for index in game.state.sea_indices:
		var remaining: int = game.state.sea_capacity[index] - game.state.sea_fill[index]
		if remaining > 0 and remaining <= last_amount:
			if target < 0 or game.state.cell_center(index).distance_to(game.state.player) < game.state.cell_center(target).distance_to(game.state.player):
				target = index
	expect(target >= 0, "final legitimate quarry load can finish a remaining sea cell")
	if target >= 0:
		var point: Vector2 = game.state.cell_center(target)
		await travel(Vector2(-2, game.state.player.y))
		await travel(Vector2(-1, point.y))
		await travel(point - Vector2(1.5, 0))
		var filled: int = game.state.filled_count
		await throw_at(point)
		expect(game.state.filled_count > filled and game.state.total_delivered == 1152, "final mined stones form new land and complete the 128 + 1024 resource cycle")
	await checkpoint("09-new-land")
	expect(game.state.total_delivered == 1152 and game.state.carried == 0 and game.state.land_piles.is_empty() and State.from_snapshot(game.state.snapshot()) != null, "all first-cycle stones are delivered; subsequent mines retain their own valid finite stocks")
	game.save_game(true)
	expect(game.hud.notice.text.contains("本次运行"), "sample clearly explains its non-saving behavior")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("walkthrough.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"seed": 10213, "target": 100000, "checks": checks, "failures": failures,
			"method": "60 Hz physical movement + E input; normal simulation; actual deposit_at calls; no state teleports, cargo injection or tick skipping in resource cycle",
			"clip_fps": 10, "clip_frames": clip_frame, "clip_labels": clip_labels, "stages": records,
			"final_generated": game.state.total_generated, "final_delivered": game.state.total_delivered}, "\t"))
	clear_motion()
	game.queue_free()
	await process_frame
	print("VERTICAL SLICE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
