extends SceneTree
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
var output := "res://artifacts/natural-mountains"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + name + ".png")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var preview = load("res://scenes/art/natural_mountain_preview.tscn").instantiate()
	root.add_child(preview)
	preview.get_node("Camera").look_at(Vector3(0, 1, 0))
	await shot("four-shapes")
	preview.mining_progress = .5
	await shot("half-mined")
	preview.queue_free()
	await process_frame
	var state := State.new(1000000, 2817)
	var world := World.new()
	root.add_child(world)
	await world.setup(state)
	world.camera.position = Vector3(-11, 22, 30)
	world.camera.look_at(Vector3(-20, 2, 8))
	world.camera.size = 42
	await shot("game-coast")
	var largest := state.mountain_position(state.mountains.size() - 1)
	world.camera.position = Vector3(largest.x + 12, 16, largest.y + 17)
	world.camera.look_at(Vector3(largest.x, 2, largest.y))
	world.camera.size = 23
	await shot("game-mountain")
	world.queue_free()
	await process_frame
	state = State.new(100000000, 2817)
	world = World.new()
	root.add_child(world)
	await world.setup(state, true)
	world.overview = true
	world.update_camera(state, 1, true)
	world.animate(state, 0, false, false, -1)
	await shot("largest-overview")
	var started := Time.get_ticks_msec()
	for frame in range(60):
		await process_frame
	print("Largest overview, 60 rendered frames: %d ms" % (Time.get_ticks_msec() - started))
	world.queue_free()
	await process_frame
	print("Natural mountain captures: " + output)
	quit()
