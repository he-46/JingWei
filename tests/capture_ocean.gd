extends SceneTree
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
var output := "res://artifacts/ocean-game"
var world: Node3D
var state: JWState

func _initialize() -> void:
	call_deferred("run")

func shot(label: String) -> void:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + label + ".png")

func close_camera() -> void:
	world.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	world.camera.fov = 65
	world.camera.position = Vector3(-1, 2.2, 7)
	world.camera.look_at(Vector3(8, .16, 0))

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	state = State.new(100000, 2817)
	world = World.new()
	root.add_child(world)
	await world.setup(state, true)
	world.animate(state, 1.3, false, false, -1)
	close_camera()
	await shot("coast")
	world.ocean.add_ripple(Vector3(4, .16, 3))
	world.animate(state, .6, false, false, -1)
	close_camera()
	await shot("ripple")
	for row in range(5, 8):
		for col in range(state.land_cols, state.land_cols + (3 if row == 6 else 2)):
			var index := row * state.grid_size + col
			state.sea_fill[index] = state.sea_capacity[index]
			state.sea_dirty[index] = true
	await world.sync(state)
	world.animate(state, .4, false, false, -1)
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.position = Vector3(18, 20, 28)
	world.camera.look_at(Vector3(4, 0, 1))
	world.camera.size = 25
	await shot("reclaimed-shore")
	var start := Time.get_ticks_msec()
	for frame in range(60):
		world.ocean.advance(1.0 / 60)
		await process_frame
	print("Ocean coast: 60 frames in %d ms" % (Time.get_ticks_msec() - start))
	world.queue_free()
	await process_frame
	state = State.new(100000000, 2817)
	world = World.new()
	root.add_child(world)
	await world.setup(state, true)
	world.overview = true
	world.animate(state, 1, false, false, -1)
	world.update_camera(state, 1, true)
	await shot("largest-overview")
	start = Time.get_ticks_msec()
	for frame in range(60):
		world.ocean.advance(1.0 / 60)
		await process_frame
	print("Ocean largest overview: 60 frames in %d ms" % (Time.get_ticks_msec() - start))
	world.queue_free()
	await process_frame
	quit()
