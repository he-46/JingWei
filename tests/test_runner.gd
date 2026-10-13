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
			var accessible := true
			for point in state.stone_positions:
				for index in range(state.mountains.size()):
					accessible = accessible and point.distance_to(state.mountain_position(index)) >= 4.0
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
	var count := 0
	while state.carried < state.capacity():
		state.pickup_stone(0)
		count += 1
	expect(count == 4 and state.carried == 32, "four starter actions fill the bag")
	var stock: int = state.stone_amounts[0]
	expect(state.pickup_stone(0) == 0 and state.stone_amounts[0] == stock, "full bag never deletes stock")
	while state.stone_amounts[0] > 0:
		state.deposit(Vector2(2, 0))
		for action in range(4):
			state.pickup_stone(0)
	var generated: int = state.total_generated
	state.tick(13.9)
	expect(state.stone_amounts[0] == 0, "depleted scatter waits for cooldown")
	state.tick(0.2)
	expect(state.stone_amounts[0] == maxi(state.stone_base[0], state.gather_power() * 8) and state.total_generated > generated, "scatter replenishes once")
	expect(state.remaining_stones() == state.total_generated, "pickup, deposit and respawn conserve stock")
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

func test_mining() -> void:
	var a := State.new()
	var b := State.new()
	expect(a.begin_mining(-1) == false, "invalid mining selection is harmless")
	for index in range(3):
		a.begin_mining(index)
		b.begin_mining(index)
	expect(not a.begin_mining(0), "mine cannot be started twice")
	a.tick(230)
	for step in range(2300):
		b.tick(0.1)
	var equivalent := a.artifacts == b.artifacts
	for index in range(3):
		equivalent = equivalent and is_equal_approx(float(a.mountains[index]["work"]), float(b.mountains[index]["work"]))
	expect(equivalent, "parallel mining and rate relic are independent of tick size")
	a.tick(100000)
	expect(a.artifacts.size() == 3 and a.mountains[0]["settled"] and int(a.mountains[0]["stock"]) == 1024, "three mountains reveal relics and settle entire reserves")
	var before: int = a.total_generated
	a.tick(100000)
	expect(a.total_generated == before, "settled mountains never duplicate stock")
	var unstarted: Dictionary = a.mountains[3]
	expect(float(unstarted["work"]) == 0 and not unstarted["settled"], "unrequested mountain stays untouched")
	var gathered := 0
	while a.carried < a.capacity():
		a.pickup_pile(0)
		gathered += 1
	expect(gathered >= 3 and gathered <= 4, "mountain stock uses the same gathering rule")
	expect(State.from_snapshot(a.snapshot()) != null and a.remaining_stones() == a.total_generated, "mining and relic progress persist with valid balances")
	var resume := State.new()
	resume.begin_mining(2)
	resume.tick(1.23456)
	var restored := State.from_snapshot(JSON.parse_string(JSON.stringify(resume.snapshot(), "", true, true)))
	expect(restored != null, "partial floating-point mining saves")
	if restored != null:
		resume.tick(600)
		restored.tick(600)
		expect(is_equal_approx(resume.mountains[2]["work"], restored.mountains[2]["work"]) and resume.artifacts == restored.artifacts, "reload continues the same mining timeline")

func test_deposits() -> void:
	var state := State.new()
	for count in range(4):
		state.pickup_stone(0)
	var cargo: int = state.carried
	var land := state.cell_at(Vector2(-2, 2))
	expect(state.deposit(state.cell_center(land)) == cargo and state.cultivation == 0 and state.total_trips == 0, "land throws create stock without earning cultivation")
	expect(state.closest_drop(state.cell_center(land)) == land, "land stock can be located")
	for count in range(4):
		state.pickup_drop(land)
	expect(state.carried == cargo and state.land_piles.is_empty(), "land stock is fully recoverable")
	expect(state.deposit(Vector2(INF, 0)) == 0 and state.deposit(Vector2(10000, 0)) == 0 and state.carried == cargo, "invalid throws preserve cargo")
	var deep: int = state.sea_indices[-1]
	expect(state.deposit(state.cell_center(deep)) == cargo and state.sea_fill[deep] == cargo, "deep sea accepts a selected distant target")
	expect(state.cultivation == cargo and state.total_trips == 1 and state.remaining_stones() == state.total_generated, "sea throws reward only delivered stones")
	# Controlled resource fixture isolates overflow behaviour without thousands of collection actions.
	var remaining := state.target_stones - state.total_delivered
	state.carried = remaining + 17
	state.total_generated += state.carried
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
	state.begin_mining(0)
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
		for index in range(state.mountains.size()):
			state.begin_mining(index)
		state.tick(10000000)
		var trips := 0
		var mine := 0
		while not state.won and trips < 2000:
			while state.carried < state.capacity() and mine < state.mountains.size():
				if state.pickup_pile(mine) == 0:
					mine += 1
			if state.carried == 0:
				break
			state.deposit(Vector2(2, 0))
			trips += 1
			for kind in ["bag", "mining"]:
				if int(state.upgrades[kind]) <= int(state.upgrades["mining" if kind == "bag" else "bag"]):
					state.buy_upgrade(kind)
		expect(state.won and state.total_delivered == target, "real mining, gather, throw and upgrade loop completes %d" % target)
		expect(state.remaining_stones() == state.total_generated and state.filled_count == state.sea_indices.size(), "completed journey keeps all stones accounted for")
		expect(State.from_snapshot(state.snapshot()) != null, "completed journey saves with valid upgrade spending")
		print("JOURNEY %d: %d trips, bag %d / mining %d, %d surplus carried" % [target, trips, state.upgrades["bag"], state.upgrades["mining"], state.carried])
