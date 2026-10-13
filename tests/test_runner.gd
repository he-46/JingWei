extends SceneTree

const State = preload("res://scripts/state.gd")
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

func run() -> void:
	test_generation()
	test_collection()
	test_mining()
	test_deposits()
	test_growth()
	test_throw_range()
	test_legacy_migration()
	test_snapshots()
	test_disk()
	test_complete_journeys()
	print("STATE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_generation() -> void:
	var previous_speed := 0.0
	for profile in State.PROFILES:
		for seed_value in [10213, 321, 789, 20261013]:
			var state := State.new(int(profile["target"]), seed_value)
			var sum := 0
			var valid := true
			var centres := true
			for index in range(state.sea_capacity.size()):
				var depth: int = state.sea_depth[index]
				var cap: int = state.sea_capacity[index]
				sum += cap
				valid = valid and (cap == 0 if depth < 0 else cap >= State.DEPTH_MIN[depth] and cap <= State.DEPTH_MAX[depth])
				centres = centres and state.cell_at(state.cell_center(index)) == index
			expect(sum == state.target_stones and valid, "all cell bands and exact total %d seed %d" % [state.target_stones, seed_value])
			expect(centres and state.map_side == state.grid_size * State.CELL_SIZE, "square grid indexing roundtrip")
			expect(state.cell_at(state.map_origin) == 0 and state.cell_at(state.map_origin + Vector2(state.map_side, 0)) == -1, "map boundary is half-open")
			var yields := 0
			var clear := true
			for index in range(state.mountains.size()):
				yields += int(state.mountains[index]["yield"])
				clear = clear and state.mountain_position(index).distance_to(state.player) >= 5.0
				clear = clear and state.cell_at(state.npc_position(index)) >= 0
			expect(state.mountains.size() == int(profile["mountains"]) and yields == int(state.target_stones * 1.2), "mountain count and finite reserve scale with selected goal")
			expect(clear, "spawn clear of mountains and NPCs inside map")
			var footprints_clear := true
			var grows := true
			var shapes: Dictionary = {}
			for index in range(state.mountains.size()):
				var point := state.mountain_position(index)
				var radius := state.mountain_radius(index)
				shapes[state.mountains[index]["shape"]] = true
				footprints_clear = footprints_clear and point.x - radius > state.map_origin.x and point.x + radius < 0
				footprints_clear = footprints_clear and point.y - radius > state.map_origin.y and point.y + radius < -state.map_origin.y
				footprints_clear = footprints_clear and state.pile_position(index).x + 3.1 < -state.throw_distance()
				if index > 0:
					grows = grows and radius >= state.mountain_radius(index - 1)
				for earlier in range(index):
					footprints_clear = footprints_clear and point.distance_to(state.mountain_position(earlier)) > radius + state.mountain_radius(earlier) + 0.6
			expect(footprints_clear, "variable footprints fit mainland without overlapping or allowing early quarry throws")
			expect(grows and state.mountain_radius(-1) > state.mountain_radius(0), "more stock increases size up to plot limit")
			expect(shapes.size() == 5, "five mountain silhouettes appear on every map")
			var accessible := true
			for point in state.stone_positions:
				for index in range(state.mountains.size()):
					accessible = accessible and point.distance_to(state.mountain_position(index)) >= state.mountain_radius(index) + 0.7
			expect(accessible, "scatter can be reached without entering a mountain")
			expect(state.remaining_stones() == state.total_generated, "initial stock conserves resources")
			var restored := State.from_snapshot(JSON.parse_string(JSON.stringify(state.snapshot(), "", true, true)))
			expect(restored != null and restored.sea_capacity == state.sea_capacity and restored.mountains == state.mountains, "generated layout roundtrips without reroll")
			if seed_value == 10213:
				expect(state.move_speed() > previous_speed, "larger maps have higher base flight speed")
				previous_speed = state.move_speed()
				print("PROFILE %d: %dx%d / %d mountains / speed %.2f / save %d bytes" % [state.target_stones, state.grid_size, state.grid_size, state.mountains.size(), state.move_speed(), JSON.stringify(state.snapshot(), "", true, true).length()])
	var a := State.new(100000, 321)
	var b := State.new(100000, 321)
	var c := State.new(100000, 789)
	expect(a.snapshot() == b.snapshot(), "same seed reproduces world")
	expect(a.sea_capacity != c.sea_capacity and a.artifact_plan != c.artifact_plan, "different seed varies cells and relic depth")

func test_collection() -> void:
	var state := State.new()
	expect(state.capacity() == 32 and state.gather_power() == 10, "starter bag and gathering amounts")
	expect(state.closest_stone(state.player) == 0, "spatial lookup finds first reachable scatter")
	expect(state.pickup_stone(0) == 10 and state.stone_amounts[0] == 0, "one collection removes a scatter")
	state.tick(1)
	var cooldown: float = state.stone_cooldowns[0]
	expect(state.pickup_stone(0) == 0 and state.stone_cooldowns[0] == cooldown, "empty scatter cannot be mined again or restart its timer")
	for index in range(1, 4):
		state.pickup_stone(index)
	expect(state.carried == 32 and state.stone_amounts[3] == 0, "four different scatters fill bag; final pickup tops up remaining two")
	expect(state.pickup_stone(4) == 0 and state.stone_amounts[4] == 1, "full bag does not consume a scatter")
	var generated: int = state.total_generated
	state.tick(12.9)
	expect(state.stone_amounts[0] == 0, "depleted scatter waits for cooldown")
	state.tick(0.2)
	expect(state.stone_amounts[0] == 1 and state.total_generated == generated, "respawn restores availability without manufacturing stored inventory")
	expect(state.remaining_stones() == state.total_generated, "harvesting accounts for every produced stone")
	state.player = Vector2(2, 0)
	state.deposit(state.player)
	state.upgrades["mining"] = 1
	expect(state.pickup_stone(4) == state.gather_power() and state.stone_amounts[4] == 0, "existing unpicked scatter uses current gathering strength")
	expect(state.pickup_stone(-1) == 0 and state.pickup_pile(999) == 0, "invalid resource indices do nothing")
	for relic in [false, true]:
		var balanced := true
		for level in range(25):
			state.upgrades["bag"] = level
			state.upgrades["mining"] = level
			if relic and not state.artifacts.has("basket"):
				state.artifacts.append("basket")
			var actions := ceili(float(state.capacity()) / state.gather_power())
			balanced = balanced and actions >= 3 and actions <= 4
		expect(balanced, "matched upgrades retain 3-4 collections, relic %s" % relic)

func earn_mining_unlock(state: JWState) -> void:
	while state.total_delivered < State.MINING_UNLOCK_STONES:
		state.tick(State.RESPAWN_SECONDS)
		for index in range(4):
			state.pickup_stone(index)
		state.player = Vector2(2, 0)
		state.deposit(state.player)

func test_mining() -> void:
	var a := State.new()
	var b := State.new()
	expect(a.begin_mining(-1) == false, "invalid mining selection is harmless")
	expect(not a.begin_mining(0) and not a.mining_unlocked(), "mining cannot begin below the delivered-stone gate")
	a.tick(100000)
	expect(a.mountains[0]["work"] == 0 and a.total_generated == 0, "waiting before unlocking never mines or produces stone")
	earn_mining_unlock(a)
	earn_mining_unlock(b)
	expect(a.total_delivered == 128 and a.mountains[0]["started"], "four starter loads automatically unlock the smallest mountain")
	expect(not a.begin_mining(1), "larger mountain cannot bypass the single-worker queue")
	a.tick(1)
	b.tick(1)
	expect(a.mountains[0]["work"] == 24 and a.mountains[1]["work"] == 0, "only one mountain receives work")
	expect(not a.begin_mining(0), "mine cannot be started twice")
	a.tick(900)
	for step in range(9000):
		b.tick(0.1)
	expect(a.artifacts.has("seal"), "tick-size comparison crosses the mining-rate relic")
	var equivalent := a.artifacts == b.artifacts
	for index in range(3):
		equivalent = equivalent and is_equal_approx(float(a.mountains[index]["work"]), float(b.mountains[index]["work"]))
	expect(equivalent, "sequential mining, transitions and rate relic are independent of tick size")
	a.tick(100000)
	expect(a.artifacts.size() == 3 and a.mountains[0]["settled"] and int(a.mountains[0]["stock"]) == 1024, "three mountains reveal relics and settle entire reserves")
	var before: int = a.total_generated
	a.tick(100000)
	expect(a.total_generated == before, "settled mountains never duplicate stock")
	expect(a.next_mountain() == -1 and a.mountains[-1]["settled"], "worker automatically completes the entire queue and then rests")
	var gathered := 0
	while a.carried < a.capacity():
		a.pickup_pile(0)
		gathered += 1
	expect(gathered >= 3 and gathered <= 4, "mountain stock uses the same gathering rule")
	expect(State.from_snapshot(a.snapshot()) != null and a.remaining_stones() == a.total_generated, "mining and relic progress persist with valid balances")
	while int(a.mountains[0]["stock"]) > 0:
		a.player = Vector2(2, 0)
		a.deposit(a.player)
		for action in range(4):
			a.pickup_pile(0)
	a.tick(1000)
	expect(a.pickup_pile(0) == 0 and not a.begin_mining(0), "empty mine cannot be collected or restarted")
	expect(a.clear_of_mountains(a.mountain_position(0)) == false, "old quarry footprint remains reserved against scatter respawns")
	var resume := State.new()
	earn_mining_unlock(resume)
	resume.tick(1.23456)
	var restored := State.from_snapshot(JSON.parse_string(JSON.stringify(resume.snapshot(), "", true, true)))
	expect(restored != null, "partial floating-point mining saves")
	if restored != null:
		resume.tick(600)
		restored.tick(600)
		expect(is_equal_approx(resume.mountains[2]["work"], restored.mountains[2]["work"]) and resume.artifacts == restored.artifacts, "reload continues the same mining timeline")

	var old := State.new().snapshot()
	# Simulate a valid pre-change v3 save with two parallel mines below the new gate.
	old["mountains"][0]["started"] = true
	old["mountains"][0]["work"] = 100.0
	old["mountains"][1]["started"] = true
	old["mountains"][1]["work"] = 120.0
	var legacy := State.from_snapshot(old)
	expect(legacy != null and legacy.mining_unlocked(), "existing mining unlock survives below the new threshold")
	if legacy != null:
		legacy.tick(1)
		expect(legacy.mountains[0]["work"] == 124 and legacy.mountains[1]["work"] == 120, "legacy parallel work is preserved but only the smallest mine advances")
		legacy.tick(900.0 / legacy.mining_rate())
		expect(legacy.mountains[0]["settled"] and legacy.next_mountain() == 1 and legacy.mountains[1]["work"] == 120, "exact completion moves worker without granting extra work")
		legacy.tick(1)
		expect(legacy.mountains[1]["work"] == 144 and State.from_snapshot(legacy.snapshot()) != null, "next mine resumes its preserved partial work and saves")
	var shuffled := State.new()
	earn_mining_unlock(shuffled)
	var smallest: Dictionary = shuffled.mountains[0]
	shuffled.mountains[0] = shuffled.mountains[3]
	shuffled.mountains[3] = smallest
	shuffled.tick(1)
	expect(shuffled.next_mountain() == 3 and shuffled.mountains[3]["work"] == 24 and shuffled.mountains[0]["work"] == 0, "worker chooses by reserves rather than array position")

func test_deposits() -> void:
	var state := State.new()
	for count in range(4):
		state.pickup_stone(count)
	var cargo: int = state.carried
	var land := state.cell_at(Vector2(-2, 2))
	expect(state.deposit(state.cell_center(land)) == cargo and state.cultivation == 0 and state.total_trips == 0, "land throws create stock without earning cultivation")
	expect(state.closest_drop(state.cell_center(land)) == land, "land stock can be located")
	for count in range(4):
		state.pickup_drop(land)
	expect(state.carried == cargo and state.land_piles.is_empty(), "land stock is fully recoverable")
	expect(state.deposit(Vector2(INF, 0)) == 0 and state.deposit(Vector2(10000, 0)) == 0 and state.carried == cargo, "invalid throws preserve cargo")
	var deep: int = state.sea_indices[-1]
	state.player = state.cell_center(deep)
	expect(state.deposit(state.cell_center(deep)) == cargo and state.sea_fill[deep] == cargo, "deep sea accepts a selected distant target")
	expect(state.cultivation == cargo and state.total_trips == 1 and state.remaining_stones() == state.total_generated, "sea throws reward only delivered stones")
	# Controlled resource fixture isolates overflow behaviour without thousands of collection actions.
	var remaining := state.target_stones - state.total_delivered
	state.carried = remaining + 17
	state.total_generated += state.carried
	state.player = Vector2(2, 0)
	expect(state.deposit(Vector2(2, 0)) == remaining and state.carried == 17, "BFS spreads to all sea cells and keeps final surplus")
	expect(state.won and state.filled_count == state.sea_indices.size(), "whole-map completion includes every depth")
	expect(state.deposit(Vector2(2, 0)) == 0 and state.carried == 17, "completed sea never consumes more stones")
	expect(state.remaining_stones() == state.total_generated, "overflow preserves resource ledger")

func test_growth() -> void:
	for level in [0, 1, 5, 9]:
		for first in ["bag", "mining"]:
			var state := State.new()
			state.upgrades["bag"] = level
			state.upgrades["mining"] = level
			var old_capacity := state.capacity()
			var old_power := state.gather_power()
			var trips := 0
			while int(state.upgrades["bag"]) == level or int(state.upgrades["mining"]) == level:
				state.cultivation += state.capacity()
				trips += 1
				for kind in [first, "mining" if first == "bag" else "bag"]:
					if int(state.upgrades[kind]) == level and state.cultivation >= state.upgrade_cost(kind):
						state.buy_upgrade(kind)
			expect(trips >= (5 if level < 2 else 18) and trips <= (10 if level < 2 else 24), "doubling cycle level %d order %s = %d trips" % [level, first, trips])
			expect(state.capacity() == old_capacity * 2 and float(state.gather_power()) / old_power >= 1.8, "paired upgrade approximately doubles delivery throughput")
			print("GROWTH level %d / %s first: %d trips" % [level, first, trips])
	var speed := State.new()
	var base := speed.move_speed()
	speed.upgrades["speed"] = 6
	expect(is_equal_approx(speed.move_speed() / base, 1.48), "six flight upgrades add 48 percent")
	expect(speed.upgrade_cost("speed") == -1 and not speed.buy_upgrade("unknown"), "upgrade caps and invalid names are safe")

func test_snapshots() -> void:
	var state := State.new()
	state.pickup_stone(0)
	state.deposit(Vector2(-2, 2))
	expect(State.from_snapshot(state.snapshot()) != null, "land stock persists")
	var valid := state.snapshot()
	for key in ["cultivation", "carried", "total_generated"]:
		var broken: Dictionary = valid.duplicate(true)
		broken[key] = int(broken[key]) + 1
		expect(State.from_snapshot(broken) == null, "reject mismatched " + key)
	for key in ["mountains", "sea_capacity", "stone_positions", "artifact_plan"]:
		var broken: Dictionary = valid.duplicate(true)
		broken[key] = []
		expect(State.from_snapshot(broken) == null, "reject malformed " + key)
	var fractional := valid.duplicate(true)
	fractional["carried"] = 0.5
	expect(State.from_snapshot(fractional) == null, "reject fractional stone balances")
	var bad_target := valid.duplicate(true)
	bad_target["target"] = 123
	expect(State.from_snapshot(bad_target) == null, "reject unknown world profile")
	var bad_relic := valid.duplicate(true)
	bad_relic["artifacts"] = ["seal"]
	expect(State.from_snapshot(bad_relic) == null, "reject unearned relic")
	var bad_cells := valid.duplicate(true)
	bad_cells["sea_capacity"][state.sea_indices[0]] += 1
	expect(State.from_snapshot(bad_cells) == null, "reject altered map total")

func test_disk() -> void:
	var path := "res://artifacts/qa-profile/state-test-%d.json" % Time.get_ticks_usec()
	var state := State.new(100000000)
	expect(Store.save_game(path, state) == OK, "largest world fits save limit")
	earn_mining_unlock(state)
	state.tick(10)
	expect(Store.save_game(path, state) == OK, "atomic save creates valid previous backup")
	var loaded: Dictionary = Store.load_game(path)
	expect(loaded["status"] == "loaded" and loaded["state"].snapshot() == state.snapshot(), "current save loads precisely")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{corrupt")
	file.close()
	var recovered: Dictionary = Store.load_game(path)
	expect(recovered["status"] == "recovered" and not recovered["state"].mountains[0]["started"], "corrupt primary recovers valid previous save")
	expect(Store.save_game(path, state) == OK and Store.load_game(path)["status"] == "loaded", "resaving recovered game preserves good backup")
	var invalid := State.new()
	invalid.cultivation = 99
	expect(Store.save_game(path, invalid) == ERR_INVALID_DATA and Store.load_game(path)["state"].target_stones == 100000000, "invalid state cannot overwrite valid save")

func test_complete_journeys() -> void:
	for target in [100000, 100000000]:
		var state := State.new(target)
		earn_mining_unlock(state)
		state.tick(10000000)
		var trips := 0
		var mine := 0
		while not state.won and trips < 2000:
			while state.carried < state.capacity() and mine < state.mountains.size():
				if state.pickup_pile(mine) == 0:
					mine += 1
			if state.carried == 0:
				break
			state.player = Vector2(2, 0)
			state.deposit(Vector2(2, 0))
			trips += 1
			for kind in ["bag", "mining"]:
				if int(state.upgrades[kind]) <= int(state.upgrades["mining" if kind == "bag" else "bag"]):
					state.buy_upgrade(kind)
		expect(state.won and state.total_delivered == target, "real mining, gather, throw and upgrade loop completes %d" % target)
		expect(state.remaining_stones() == state.total_generated and state.filled_count == state.sea_indices.size(), "completed journey keeps all stones accounted for")
		expect(State.from_snapshot(state.snapshot()) != null, "completed journey saves with valid upgrade spending")
		print("JOURNEY %d: %d trips, bag %d / mining %d, %d surplus carried" % [target, trips, state.upgrades["bag"], state.upgrades["mining"], state.carried])


func test_throw_range() -> void:
	for profile in State.PROFILES:
		var state := State.new(int(profile["target"]))
		state.pickup_stone(0)
		state.player = Vector2(-5, 0)
		expect(state.throw_distance() == 4 and not state.can_throw(Vector2(0.1, 0)), "starter range cannot reach sea from inland")
		var carried: int = state.carried
		expect(state.deposit(Vector2(0.1, 0)) == 0 and state.carried == carried, "data layer rejects distant throws without charging cargo")
		state.upgrades["throw"] = 2
		expect(state.can_throw(Vector2(0.1, 0)) and state.deposit(Vector2(0.1, 0)) == carried, "upgraded range reaches previously inaccessible sea")
		var limit := state.upgrade_limit("throw")
		state.upgrades["throw"] = limit
		expect(state.upgrade_cost("throw") == -1 and state.throw_distance() <= state.map_side * 0.22, "map-dependent cap keeps travel meaningful")
	var boundary := State.new()
	boundary.player = Vector2(-2, 0)
	expect(boundary.can_throw(Vector2(2, 0)) and not boundary.can_throw(Vector2(2.01, 0)), "range edge is inclusive with small numeric tolerance")
	boundary.player = boundary.map_origin + Vector2(0.1, 0.1)
	expect(not boundary.can_throw(boundary.map_origin - Vector2(0.1, 0)), "fogged out-of-bounds point stays forbidden even within range")
	var buying := State.new()
	buying.player = Vector2(2, 0)
	for cycle in range(4):
		for index in range(4):
			buying.pickup_stone(index)
		buying.deposit(buying.player)
		buying.tick(14)
	expect(buying.buy_upgrade("throw") and buying.throw_distance() == 5, "real cultivation buys range upgrade")
	expect(State.from_snapshot(buying.snapshot()) != null, "range spending and level survive validated saves")

func test_legacy_migration() -> void:
	# Fixture generated by the actual version 2 implementation at commit 6c72000.
	var actual_legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/coast_v2.json"))
	var migrated := State.from_snapshot(actual_legacy)
	expect(migrated != null, "real committed version 2 fixture migrates")
	if migrated != null:
		expect(migrated.total_delivered == int(actual_legacy["total_delivered"]) and migrated.carried == int(actual_legacy["carried"]) and migrated.cultivation == int(actual_legacy["cultivation"]), "real old save retains delivered, carried and cultivation balances")
		expect(migrated.mountains[0]["stock"] == int(actual_legacy["mountains"][0]["stock"]) and migrated.artifacts == actual_legacy["artifacts"], "real old save retains mined inventory and artifacts")
		expect(migrated.upgrades["bag"] == int(actual_legacy["upgrades"]["bag"]) and migrated.remaining_stones() == migrated.total_generated, "real old upgrades and inventory conservation remain valid")
	var state := State.new()
	earn_mining_unlock(state)
	state.tick(10)
	for index in range(4):
		state.pickup_stone(index)
	state.player = Vector2(2, 0)
	state.deposit(state.player)
	var legacy := state.snapshot()
	legacy["version"] = 2
	legacy["upgrades"].erase("throw")
	for mountain in legacy["mountains"]:
		mountain.erase("shape")
		mountain.erase("yaw")
	var unpicked := 0
	for index in range(legacy["stone_amounts"].size()):
		var available := int(legacy["stone_amounts"][index]) > 0
		legacy["stone_base"][index] = 64
		legacy["stone_amounts"][index] = 64 if available else 0
		unpicked += int(legacy["stone_amounts"][index])
	legacy["total_generated"] += unpicked
	var restored := State.from_snapshot(legacy)
	expect(restored != null, "version 2 world migrates automatically")
	if restored != null:
		expect(restored.total_delivered == state.total_delivered and restored.cultivation == state.cultivation and restored.sea_fill == state.sea_fill, "migration preserves sea and cultivation progress")
		expect(restored.mountains[0]["work"] == state.mountains[0]["work"] and restored.upgrades["throw"] == 0, "migration preserves mining and adds starter throw level")
		expect(restored.remaining_stones() == restored.total_generated and State.from_snapshot(restored.snapshot()) != null, "migration produces a valid version 3 roundtrip")
		var protected_layout := true
		for point in restored.stone_positions:
			protected_layout = protected_layout and restored.clear_of_mountains(point)
		expect(protected_layout, "migrated scatters avoid enlarged and depleted mountain footprints")
	var broken := legacy.duplicate(true)
	broken["total_generated"] += 1
	expect(State.from_snapshot(broken) == null, "migration does not hide broken old inventory ledgers")
	var obstructed := legacy.duplicate(true)
	var old_point := state.mountain_position(state.mountains.size() - 1)
	var old_cell := state.cell_at(old_point)
	obstructed["player"] = [old_point.x, old_point.y]
	obstructed["land_piles"] = {str(old_cell): 1}
	obstructed["total_generated"] += 1
	var relocated := State.from_snapshot(obstructed)
	expect(relocated != null, "migration relocates a player and ground cache covered by a larger mountain")
	if relocated != null:
		expect(relocated.clear_of_mountains(relocated.player) and not relocated.land_piles.has(str(old_cell)), "relocated player and cache are outside the new mountain")
		expect(relocated.land_piles.values() == [1] and relocated.remaining_stones() == relocated.total_generated, "relocated cache keeps all its stones")
