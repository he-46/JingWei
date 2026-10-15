extends SceneTree
const State = preload("res://scripts/state.gd")
const World = preload("res://scripts/world.gd")
const Catalog = preload("res://scripts/visuals/asset_catalog.gd")
const Visual = preload("res://scripts/visuals/mountain_visual.gd")
const Store = preload("res://scripts/save_store.gd")
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

func run() -> void:
	var shapes: Dictionary = {}
	for i in range(Catalog.MOUNTAINS.size()):
		var high: Mesh = Catalog.meshes([Catalog.MOUNTAINS[i]])[0]
		var low: Mesh = Catalog.meshes([Catalog.MOUNTAINS[i]], "_far")[0]
		var data := high.surface_get_arrays(0)
		expect(data[Mesh.ARRAY_TEX_UV].size() == data[Mesh.ARRAY_VERTEX].size(), "mountain retains complete UVs without embedded images")
		shapes[hash(data[Mesh.ARRAY_VERTEX])] = true
		expect(high.get_surface_count() == 1 and data[Mesh.ARRAY_INDEX].size() / 3 <= 4000, "mountain single surface triangle budget")
		expect(low.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() < data[Mesh.ARRAY_INDEX].size() * .3, "overview mountain reduces triangles by over 70 percent")
		for mesh in [high, low]:
			var bounded := true
			for point in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				bounded = bounded and point.y >= -.00001 and point.y <= 1.00001 and Vector2(point.x, point.z).length() < .96
			expect(bounded and absf(mesh.get_aabb().end.y - 1) < .015, "both meshes preserve ground, peak and safe logical footprint: %s %s" % [Catalog.MOUNTAINS[i], mesh.get_aabb()])
		expect(Visual.collision_envelopes(high).size() == 8, "every authored shape has a conservative collision profile")
	expect(shapes.size() == 8, "eight independent mountain vertex sets")
	for family in range(5):
		expect(Catalog.mountain_variant(family, family) == family, "legacy first family member retains its mapping")
		expect(Catalog.mountain_variant(family, family + 5) == (family + 4 if family in [1, 2, 3] else family), "repeat family uses documented compatible variation")
	for pair in [[Catalog.STONES, 250], [Catalog.TREES, 900], [Catalog.SHRUBS, 350], [Catalog.GRASSES, 60]]:
		for mesh in Catalog.meshes(pair[0]):
			expect(mesh.get_surface_count() == 1 and mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3 <= pair[1], "expanded decor triangle and material budget")
			var data := mesh.surface_get_arrays(0)
			expect(data[Mesh.ARRAY_TEX_UV].size() == data[Mesh.ARRAY_VERTEX].size(), "decor retains complete UVs for shared palettes")
	for profile in State.PROFILES:
		var state := State.new(profile.target, 10213)
		var before := state.snapshot()
		var world := World.new()
		root.add_child(world)
		world.setup(state)
		expect(state.snapshot() == before and State.from_snapshot(before) != null, "expanded world preserves valid exact save data")
		var rendered := 0
		for pool in world.mountain_batches:
			rendered += pool.instance_count
		expect(rendered == state.mountains.size(), "no duplicated mountains across regional pools")
		expect(world.quarry_mesh.instance_count == state.mountains.size() * 32 and world.pile_mesh.instance_count == 0, "all mountains use bounded formal quarry stones")
		var hidden_stock := true
		for node in world.quarry_mesh.nodes:
			hidden_stock = hidden_stock and not node.visible
		expect(hidden_stock and world.quarry_mesh.active_per_group.reduce(func(total, n): return total + n, 0) == 0, "unmined stock batches submit no geometry")
		if DisplayServer.get_name() != "headless":
			var slot: Vector2i = world.quarry_mesh.slots[0]
			var actual: Color = world.quarry_mesh.nodes[slot.x].multimesh.get_instance_color(slot.y)
			expect(actual.is_equal_approx(Color.WHITE), "formal stock starts with white instance tint instead of default black")
		var clear := true
		for i in range(state.mountains.size()):
			clear = clear and state.npc_position(i).x < -.1 and world.mountain_collision_groups[i].size() == 8
			for j in range(i):
				clear = clear and state.mountain_position(i).distance_to(state.mountain_position(j)) > state.mountain_radius(i) + state.mountain_radius(j)
			clear = clear and state.mountain_position(i).x + state.mountain_radius(i) < -3.0
		expect(clear, "mountains neither overlap nor invade the reserved coastal travel lane")
		expect(world.tree_mesh.instance_count <= 200 and world.grass_mesh.instance_count <= 2500 and world.shrub_mesh.instance_count <= 160, "variety does not increase global decor caps")
		var slots_valid := true
		for pool in world.detail_batches:
			var count := 0
			for group in pool.groups:
				count += group.size()
			slots_valid = slots_valid and count == pool.instance_count
			for i in range(pool.instance_count):
				var slot: Vector2i = pool.slots[i]
				slots_valid = slots_valid and pool.groups[slot.x][slot.y] == i
		expect(slots_valid, "regional slots cover all logical instances exactly once")
		world.overview = true
		world.animate(state, 0, false, false, -1)
		var low_only := not world.sun.shadow_enabled and not world.bird_model.visible
		for pool in world.mountain_batches:
			for node in pool.nodes:
				low_only = low_only and not node.visible
			for node in pool.far_nodes:
				low_only = low_only and node.visible
		expect(low_only and not world.quarry_mesh.nodes[0].visible, "overview uses far mountains, no ordinary stones, characters or shadows")
		world.overview = false
		world.animate(state, 0, false, false, -1)
		expect(world.sun.shadow_enabled and world.bird_model.visible and world.mountain_batches[0].nodes[0].visible, "normal view restores detailed rendering")
		world.grass_mesh.update_detail(world.camera, Vector3(10000, 0, 10000))
		world.grass_mesh.visible_instance_count = -1
		var culled := true
		for node in world.grass_mesh.nodes:
			culled = culled and not node.visible
		expect(culled, "repeating normal visibility does not undo far-region culling between updates")
		world.animate(state, 0, false, false, -1)
		var near_visible := false
		for node in world.grass_mesh.nodes:
			near_visible = near_visible or node.visible
		expect(near_visible, "returning near vegetation restores its regional batches")
		unlock(state)
		var kinds: Dictionary = {}
		for i in range(mini(10, state.mountains.size())):
			var reserve: int = state.mountains[i].yield
			state.tick(reserve * .5 / state.mining_rate())
			world.sync(state)
			await physics_frame
			await physics_frame
			var top := 0.0
			for slab in world.mountain_collision_groups[i]:
				if not slab.disabled:
					top = maxf(top, slab.position.y + slab.shape.height * .5)
			expect(absf(top - Visual.from_state(state, i).collision_height) < .001, "every family follows its excavation plane")
			state.tick((reserve - float(state.mountains[i].work)) / state.mining_rate())
			world.sync(state)
			var visual = Visual.from_state(state, i)
			var full := true
			for part in range(32):
				full = full and world.quarry_mesh.transforms[i * 32 + part].origin.y > -10
			expect(full and visual.settled and visual.stock == reserve and State.from_snapshot(state.snapshot()) != null, "each excavated family yields a finite valid reserve and full stone field")
			kinds[world.mountain_variants[i]] = true
			# Emptying this test reserve preserves the ledger through a ground cache.
			state.land_piles[str(state.cell_at(state.npc_position(i)))] = int(state.land_piles.get(str(state.cell_at(state.npc_position(i))), 0)) + reserve
			state.mountains[i].stock = 0
			world.sync(state)
			var empty := true
			for part in range(32):
				empty = empty and world.quarry_mesh.transforms[i * 32 + part].origin.y < -10
			expect(empty and state.pickup_pile(i) == 0 and State.from_snapshot(state.snapshot()) != null, "empty sites never regenerate collectible stock")
			var hidden_empty := true
			for node in world.quarry_mesh.nodes:
				hidden_empty = hidden_empty and not node.visible
			expect(hidden_empty, "depleted groups are hidden rather than drawing underground instances")
		if state.mountains.size() >= 10:
			expect(kinds.size() == 8, "larger maps exercise all eight mountain forms through depletion")
		world.queue_free()
		await process_frame
	var legacy: JWState = Store.load_game("res://tests/fixtures/coast_v2.json").state
	var saved := legacy.snapshot()
	var world := World.new()
	root.add_child(world)
	world.setup(legacy)
	expect(legacy.snapshot() == saved and State.SAVE_VERSION == 3, "actual migrated v2 fixture retains its v3 fields and progress")
	world.queue_free()
	await process_frame
	print("EXPANSION TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
