extends SceneTree
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
const Ocean = preload("res://scripts/visuals/ocean_surface.gd")
const Coast = preload("res://scripts/visuals/coast_geometry.gd")
const Aim = preload("res://scripts/first_person_aim.gd")
const FX = preload("res://scripts/visuals/action_feedback.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	for profile in State.PROFILES:
		var state := State.new(profile.target, 2817)
		var snapshot := state.snapshot()
		var ocean := Ocean.new()
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/water.gdshader")
		ocean.setup(state, material)
		var normal := ocean.mesh()
		var light := ocean.mesh(2)
		var vertices: PackedVector3Array = normal.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		expect(vertices.size() < 180000 and light.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() < vertices.size() * .3, "bounded meshes and genuinely cheaper smooth quality")
		var indices: PackedInt32Array = normal.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		var edges := {}
		for face in range(0, indices.size(), 3):
			for edge in range(3):
				var a := indices[face + edge]
				var b := indices[face + (edge + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				edges[key] = int(edges.get(key, 0)) + 1
		var seam_free := true
		for edge: Vector2i in edges:
			if edges[edge] == 1:
				# Open edges may exist only at the far perimeter, never at the detail/ring seam.
				var p := vertices[edge.x]
				var center := state.map_origin + Vector2.ONE * state.map_side * .5
				seam_free = seam_free and maxf(absf(p.x - center.x), absf(p.z - center.y)) > state.map_side
		expect(seam_free, "outer ocean ring shares every inner edge index")
		var first := ocean.height(Vector2(8, 2))
		ocean.advance(1.7)
		expect(absf(first - ocean.height(Vector2(8, 2))) > .01, "sea geometry changes with simulation time")
		expect(is_equal_approx(ocean.height(Vector2(.1, 2)), Coast.WATER_HEIGHT), "coastal amplitude vanishes before the land seam")
		for z in range(-10, 11, 2):
			var p := Vector2(5.7, z)
			var origin := Vector3(p.x - 3, 2.0, p.y + 2)
			var target := Vector3(p.x, ocean.height(p), p.y)
			var hit: Variant = Aim.surface_hit(state, origin, (target - origin).normalized(), ocean)
			expect(hit != null and hit.distance_to(target) < .025, "ray lands on the moving surface")
		for i in range(24): ocean.add_ripple(Vector3(6, .16, 2))
		expect(ocean.events.size() == Ocean.RIPPLE_COUNT and ocean.event_serial == 24, "rapid throws reuse a fixed ripple budget")
		ocean.advance(.4)
		for x in range(1, 15):
			expect(absf(ocean.height(Vector2(x, 2)) - Coast.WATER_HEIGHT) <= .366, "overlapping impacts remain bounded")
		ocean.advance(Ocean.RIPPLE_LIFE + 1)
		var with_expired := ocean.height(Vector2(6, 2))
		ocean.events.fill(Vector4(0, 0, -100, 0))
		expect(is_equal_approx(with_expired, ocean.height(Vector2(6, 2))), "expired impacts leave no permanent displacement")
		expect(state.snapshot() == snapshot, "wave simulation never changes resource or save data")
	var state := State.new(100000, 2817)
	var world := World.new()
	root.add_child(world)
	await world.setup(state, true)
	var before: int = world.ocean.revision
	for row in range(4, 8):
		for col in range(state.land_cols, state.land_cols + 3):
			var index := row * state.grid_size + col
			state.sea_fill[index] = state.sea_capacity[index]
			state.sea_dirty[index] = true
	var visual_fixture := state.snapshot()
	await world.sync(state)
	expect(world.ocean.revision > before and state.snapshot() == visual_fixture, "filling updates the atlas without settling resources twice")
	expect(world.ocean.field(Vector2(6, 0)).r < 0 and is_equal_approx(world.ocean.height(Vector2(6, 0)), Coast.WATER_HEIGHT), "filled interior suppresses waves and foam")
	var dry_target := Vector3(6, world.ocean.terrain_height(state, Vector2(6, 0)), 0)
	var outside_camera := Vector3(6, 60, state.map_side * 2)
	var dry_hit: Variant = Aim.surface_hit(state, outside_camera, (dry_target - outside_camera).normalized(), world.ocean)
	expect(dry_hit != null and dry_hit.distance_to(dry_target) < .025, "overview rays starting outside the map hit reclaimed ground before water")
	var near_new_shore := false
	for line_list in world.ocean.segments.values():
		for line: Vector4 in line_list:
			var p := (Vector2(line.x, line.y) + Vector2(line.z, line.w)) * .5
			if p.x > 4 and absf(world.ocean.field(p).r) < 1:
				near_new_shore = true
	expect(near_new_shore, "shore atlas follows terrain intersections away from the old mainland")
	var fx := FX.new()
	world.add_child(fx)
	fx.water_height = world.ocean.impact_height
	fx.water_impacted.connect(world.ocean.add_ripple)
	var serial: int = world.ocean.event_serial
	fx.throw_stone(Vector3(-1, 2, 0), Vector3(16, .16, 0), true, false, false, 0)
	fx.advance(.2)
	expect(world.ocean.event_serial == serial, "launch does not trigger an early ripple")
	fx.advance(.4)
	expect(world.ocean.event_serial == serial + 1, "actual water landing triggers one ripple")
	fx.advance(1)
	expect(world.ocean.event_serial == serial + 1, "completed projectile does not repeat its ripple")
	serial = world.ocean.event_serial
	world.ocean.add_ripple(Vector3(6, .49, 0))
	expect(world.ocean.event_serial == serial, "dry reclaimed land cannot emit water ripples")
	var stopped: float = world.ocean.height(Vector2(17, 0))
	for frame in range(3): await process_frame
	expect(world.ocean.height(Vector2(17, 0)) == stopped, "water is frozen without simulation advance")
	world.queue_free()
	await process_frame
	print("OCEAN TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
