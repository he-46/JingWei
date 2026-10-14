class_name JWState
extends RefCounted

const SAVE_VERSION := 3
const CELL_SIZE := 4.0
const RESPAWN_SECONDS := 14.0
const MINING_UNLOCK_STONES := 128
const MAX_LEVEL := 24
const THROW_DISTANCES := [4.0, 5.0, 6.5, 8.0, 10.0, 12.5, 16.0, 20.0, 24.0, 30.0, 36.0]
const PROFILES := [
	{"target": 100000, "grid": 12, "land": 5, "bands": [3, 3, 1], "mountains": 6, "name": "十万石 · 初愿"},
	{"target": 1000000, "grid": 24, "land": 10, "bands": [4, 6, 4], "mountains": 18, "name": "百万石 · 长行"},
	{"target": 10000000, "grid": 48, "land": 19, "bands": [7, 10, 12], "mountains": 60, "name": "千万石 · 山海"},
	{"target": 100000000, "grid": 96, "land": 38, "bands": [12, 20, 26], "mountains": 180, "name": "一亿石 · 无尽志"},
]
const DEPTH_NAMES := ["浅海", "远海", "深海"]
const DEPTH_MIN := [10, 100, 5000]
const DEPTH_MAX := [100, 5000, 50000]
const ARTIFACT_CATALOG := [
	{"id": "basket", "name": "神农石篓", "effect": "负重与采集量 +20%"},
	{"id": "feather", "name": "乘风羽", "effect": "飞行速度 +15%"},
	{"id": "seal", "name": "开山印", "effect": "开山速度 +25%"},
]
const MOUNTAIN_NAMES := ["青岚", "松隐", "云屏", "栖霞", "望舒", "苍梧", "叠翠", "白鹿", "长风", "玄石"]

var target_stones: int = 100000
var world_seed: int = 10213
var grid_size: int = 12
var land_cols: int = 5
var bands: Array = [3, 3, 1]
var map_side: float = 48.0
var map_origin := Vector2(-20, -24)
var player := Vector2(-2.5, 3.0)
var carried: int = 0
var cultivation: int = 0
var total_delivered: int = 0
var total_generated: int = 0
var total_trips: int = 0
var elapsed: float = 0.0
var won: bool = false
var upgrades: Dictionary = {"bag": 0, "mining": 0, "speed": 0, "throw": 0}
var artifacts: Array[String] = []
var artifact_plan: Array[Dictionary] = []
var mountains: Array[Dictionary] = []
var mountain_radii: Array[float] = []
var stone_positions: Array[Vector2] = []
var stone_base: Array[int] = []
var stone_amounts: Array[int] = []
var stone_cooldowns: Array[float] = []
var land_piles: Dictionary = {}
var sea_fill: Array[int] = []
var sea_capacity: Array[int] = []
var sea_depth: Array[int] = []
var sea_indices: Array[int] = []
var messages: Array[String] = []
var sea_dirty: Dictionary = {}
var stone_dirty: Dictionary = {}
var piles_dirty: bool = true
var filled_count: int = 0
var stone_buckets: Dictionary = {}
var migrated_from: int = 0

func _init(target_value: int = 100000, seed_value: int = 10213, generate: bool = true) -> void:
	target_stones = target_value if profile_for(target_value) != null else 100000
	world_seed = seed_value
	var profile: Dictionary = profile_for(target_stones)
	grid_size = int(profile["grid"])
	land_cols = int(profile["land"])
	bands = profile["bands"].duplicate()
	map_side = grid_size * CELL_SIZE
	map_origin = Vector2(-land_cols * CELL_SIZE, -map_side * 0.5)
	if generate:
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed
		_generate_sea(rng)
		_generate_mountains(rng, int(profile["mountains"]))
		_generate_scatter(rng)
		for index in range(ARTIFACT_CATALOG.size()):
			var item: Dictionary = ARTIFACT_CATALOG[index].duplicate(true)
			item["mountain"] = index
			item["threshold"] = float(rng.randi_range(300, 800)) / 1024.0
			artifact_plan.append(item)

static func profile_for(target: int) -> Variant:
	for profile in PROFILES:
		if int(profile["target"]) == target:
			return profile
	return null

static func number(value: int) -> String:
	if value >= 100000000:
		return "%.2f亿" % (value / 100000000.0)
	if value >= 10000:
		return "%.2f万" % (value / 10000.0)
	return str(value)

func _generate_sea(rng: RandomNumberGenerator) -> void:
	var weights: Array[float] = []
	for row in range(grid_size):
		for col in range(grid_size):
			var index := row * grid_size + col
			var depth := depth_for_col(col)
			sea_depth.append(depth)
			sea_fill.append(0)
			sea_capacity.append(0)
			weights.append(0.0)
			if depth < 0:
				continue
			sea_indices.append(index)
			var band_start := land_cols
			for earlier in range(depth):
				band_start += int(bands[earlier])
			var t := float(col - band_start + 0.5) / int(bands[depth])
			weights[index] = (0.18 + 0.82 * pow(t, 1.5)) * rng.randf_range(0.72, 1.28)
	# Bounded allocation preserves depth ranges and exactly matches the chosen total.
	var low := 0.0
	var high := 16.0
	for iteration in range(52):
		var factor := (low + high) * 0.5
		var total := 0
		for index in sea_indices:
			var depth := sea_depth[index]
			total += mini(DEPTH_MAX[depth], int(floor(DEPTH_MIN[depth] + (DEPTH_MAX[depth] - DEPTH_MIN[depth]) * weights[index] * factor)))
		if total <= target_stones:
			low = factor
		else:
			high = factor
	var allocated := 0
	for index in sea_indices:
		var depth := sea_depth[index]
		sea_capacity[index] = mini(DEPTH_MAX[depth], int(floor(DEPTH_MIN[depth] + (DEPTH_MAX[depth] - DEPTH_MIN[depth]) * weights[index] * low)))
		allocated += sea_capacity[index]
	var cursor := rng.randi_range(0, sea_indices.size() - 1)
	while allocated < target_stones:
		var index := sea_indices[cursor % sea_indices.size()]
		if sea_capacity[index] < DEPTH_MAX[sea_depth[index]]:
			sea_capacity[index] += 1
			allocated += 1
		cursor += 1

func _generate_mountains(rng: RandomNumberGenerator, count: int) -> void:
	# Generous plots bound the largest possible footprint, not only mountain centres.
	var usable_width := absf(map_origin.x) - 7.0
	var columns := maxi(1, floori(sqrt(count * usable_width / map_side)))
	var rows := ceili(float(count) / columns)
	var step := Vector2(usable_width / columns, map_side / rows)
	var points: Array[Vector2] = []
	for row in range(rows):
		for col in range(columns):
			var point := Vector2(-7.0 - (col + 0.5) * step.x, map_origin.y + (row + 0.5) * step.y)
			point += Vector2(rng.randf_range(-0.04, 0.04) * step.x, rng.randf_range(-0.04, 0.04) * step.y)
			points.append(point)
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(player) < b.distance_squared_to(player))
	var budget := int(target_stones * 1.2)
	var weight_total := 0.0
	for index in range(count):
		weight_total += index * index
	var allocated := 0
	for index in range(count):
		var stock := 1024 + int(floor((budget - count * 1024) * float(index * index) / weight_total))
		allocated += stock
		mountains.append({"x": points[index].x, "z": points[index].y, "yield": stock, "work": 0.0,
			"started": false, "settled": false, "stock": 0, "shape": index % 5, "yaw": rng.randi_range(0, 6433) / 1024.0})
	mountains[-1]["yield"] = int(mountains[-1]["yield"]) + budget - allocated

func mountain_radius(index: int) -> float:
	if mountain_radii.size() != mountains.size():
		mountain_radii.clear()
		var count := mountains.size()
		var width := absf(map_origin.x) - 7.0
		var columns := maxi(1, floori(sqrt(count * width / map_side)))
		var rows := ceili(float(count) / columns)
		var limit := minf(width / columns, map_side / rows) * 0.39
		for mountain in mountains:
			mountain_radii.append(minf(1.7 * pow(float(mountain["yield"]) / 1024.0, 0.18), limit))
	return mountain_radii[index]

func mountain_height(index: int) -> float:
	return mountain_radius(index) * 2.25

func high_flight_height() -> float:
	var height := 8.2
	for index in range(mountains.size()):
		height = maxf(height, mountain_height(index) + 2.0)
	return height

func clear_of_mountains(point: Vector2, margin: float = 0.7) -> bool:
	for index in range(mountains.size()):
		if point.distance_to(mountain_position(index)) < mountain_radius(index) + margin:
			return false
	return true

func _generate_scatter(rng: RandomNumberGenerator) -> void:
	var count := clampi(int(grid_size * grid_size / 3), 50, 1500)
	var starting_points := [Vector2(-2.5, 3), Vector2(-4.5, 4.5), Vector2(-5.5, 1.5), Vector2(-2.5, 0)]
	for index in range(count):
		var point: Vector2 = starting_points[index] if index < 4 else Vector2(-2.5, 3)
		if index >= 4:
			var found := false
			for attempt in range(200):
				point = Vector2(rng.randf_range(map_origin.x + 1, -1.5), rng.randf_range(map_origin.y + 1, -map_origin.y - 1))
				if clear_of_mountains(point):
					found = true
					break
			if not found:
				# The reserved coastal lane is always outside every mining footprint.
				point = Vector2(-2.5, rng.randf_range(map_origin.y + 1, -map_origin.y - 1))
		stone_positions.append(point)
		# A scatter is one available gathering action, not a finite multi-action stockpile.
		stone_base.append(1)
		stone_amounts.append(1)
		stone_cooldowns.append(0.0)
		stone_dirty[index] = true
	_rebuild_buckets()

func _rebuild_buckets() -> void:
	stone_buckets.clear()
	for index in range(stone_positions.size()):
		var key := Vector2i(floori(stone_positions[index].x / 8.0), floori(stone_positions[index].y / 8.0))
		if not stone_buckets.has(key):
			stone_buckets[key] = []
		stone_buckets[key].append(index)

func relic_factor() -> float:
	return 1.2 if artifacts.has("basket") else 1.0

func capacity() -> int:
	return int(floor(32 * pow(2.0, int(upgrades["bag"])) * relic_factor()))

func gather_power() -> int:
	return int(ceil(32 * pow(2.0, int(upgrades["mining"])) * relic_factor() / 3.5))

func move_speed() -> float:
	return 5.5 * sqrt(map_side / 48.0) * (1.0 + 0.08 * int(upgrades["speed"])) * (1.15 if artifacts.has("feather") else 1.0)

func mining_rate() -> float:
	return 24.0 * pow(2.0, int(upgrades["mining"])) * (1.25 if artifacts.has("seal") else 1.0)

static func cycle_trips(level: int) -> int:
	return [6, 8, 10, 14, 18][level] if level < 5 else 20

static func cost_at(kind: String, level: int) -> int:
	if kind == "speed":
		return int(128 * pow(4.0, level))
	if kind == "throw":
		return int(ceil(96 * pow(2.2, level)))
	return int(ceil(32 * pow(2.0, level) * cycle_trips(level) * 0.6))

func upgrade_limit(kind: String) -> int:
	if kind == "throw":
		return {100000: 4, 1000000: 6, 10000000: 8, 100000000: 10}[target_stones]
	return 6 if kind == "speed" else MAX_LEVEL

func throw_distance() -> float:
	return THROW_DISTANCES[int(upgrades["throw"])]

func can_throw(point: Vector2) -> bool:
	return cell_at(point) >= 0 and player.distance_to(point) <= throw_distance() + 0.00001

func upgrade_cost(kind: String) -> int:
	if not upgrades.has(kind) or int(upgrades[kind]) >= upgrade_limit(kind):
		return -1
	return cost_at(kind, int(upgrades[kind]))

func buy_upgrade(kind: String) -> bool:
	var price := upgrade_cost(kind)
	if price < 0 or cultivation < price:
		return false
	cultivation -= price
	upgrades[kind] = int(upgrades[kind]) + 1
	return true

func mountain_position(index: int) -> Vector2:
	return Vector2(mountains[index]["x"], mountains[index]["z"])

func npc_position(index: int) -> Vector2:
	return mountain_position(index) + Vector2(mountain_radius(index) + 1.5, 0.0)

func pile_position(index: int) -> Vector2:
	return mountain_position(index)

func mountain_name(index: int) -> String:
	return MOUNTAIN_NAMES[index % MOUNTAIN_NAMES.size()] + "山" + (" · %d" % (index + 1) if index >= MOUNTAIN_NAMES.size() else "")

func next_mountain() -> int:
	var best := -1
	for index in range(mountains.size()):
		if not mountains[index]["settled"] and (best < 0 or int(mountains[index]["yield"]) < int(mountains[best]["yield"])):
			best = index
	return best

func mining_unlocked() -> bool:
	if total_delivered >= MINING_UNLOCK_STONES:
		return true
	# Older saves could start several mines before the new threshold. Keep that unlock,
	# but only advance the smallest unfinished mountain; other partial work is retained.
	for mountain in mountains:
		if mountain["started"]:
			return true
	return false

func pangolin_mountain() -> int:
	var next := next_mountain()
	if next >= 0:
		return next
	var largest := 0
	for index in range(mountains.size()):
		if int(mountains[index]["yield"]) > int(mountains[largest]["yield"]):
			largest = index
	return largest

func nearby_mountain(point: Vector2, radius: float = INF, npc: bool = false) -> int:
	if npc:
		var index := pangolin_mountain()
		return index if point.distance_to(npc_position(index)) < radius else -1
	var best := -1
	var distance := radius
	for index in range(mountains.size()):
		var at := npc_position(index) if npc else mountain_position(index)
		var candidate := point.distance_to(at)
		if candidate < distance:
			best = index
			distance = candidate
	return best

func nearby_pile(point: Vector2, radius: float = 3.1) -> int:
	var best := -1
	var distance := radius
	for index in range(mountains.size()):
		if not mountains[index]["settled"] or int(mountains[index]["stock"]) <= 0:
			continue
		var candidate := point.distance_to(pile_position(index))
		if candidate < distance:
			best = index
			distance = candidate
	return best

func begin_mining(index: int) -> bool:
	if not mining_unlocked() or index < 0 or index != next_mountain() or mountains[index]["started"]:
		return false
	mountains[index]["started"] = true
	messages.append("开始开采%s。" % mountain_name(index))
	return true

func tick(seconds: float) -> void:
	if seconds <= 0 or not is_finite(seconds):
		return
	elapsed += seconds
	for index in range(stone_amounts.size()):
		if stone_amounts[index] > 0:
			continue
		stone_cooldowns[index] = maxf(0, stone_cooldowns[index] - seconds)
		if stone_cooldowns[index] <= 0:
			stone_amounts[index] = 1
			stone_dirty[index] = true
	# One worker, one timeline. Split at both relic discoveries and mountain completion
	# so a long tick carries its remaining time into the next (smallest) mountain.
	var remaining := seconds
	while remaining > 0.000001 and mining_unlocked():
		var index := next_mountain()
		if index < 0:
			break
		begin_mining(index)
		var mountain: Dictionary = mountains[index]
		var rate := mining_rate()
		var step := minf(remaining, maxf(0, float(mountain["yield"]) - float(mountain["work"])) / rate)
		for item in artifact_plan:
			if int(item["mountain"]) == index and not artifacts.has(String(item["id"])):
				step = minf(step, maxf(0, float(mountain["yield"]) * float(item["threshold"]) - float(mountain["work"])) / rate)
		mountain["work"] = minf(float(mountain["yield"]), float(mountain["work"]) + step * rate)
		remaining -= step
		for item in artifact_plan:
			if int(item["mountain"]) == index and not artifacts.has(String(item["id"])) and float(mountain["work"]) + 0.00001 >= float(mountain["yield"]) * float(item["threshold"]):
				artifacts.append(String(item["id"]))
				messages.append("神器出土 · %s：%s" % [item["name"], item["effect"]])
		if float(mountain["work"]) + 0.00001 >= float(mountain["yield"]):
			mountain["work"] = float(mountain["yield"])
			mountain["settled"] = true
			mountain["stock"] = int(mountain["yield"])
			total_generated += int(mountain["yield"])
			messages.append("%s开尽，留下%s石。" % [mountain_name(index), number(int(mountain["stock"]))])
			begin_mining(next_mountain())

func closest_stone(point: Vector2, radius: float = 2.2) -> int:
	var bucket := Vector2i(floori(point.x / 8.0), floori(point.y / 8.0))
	var reach := ceili(radius / 8.0)
	var best := -1
	var distance := radius
	for x in range(-reach, reach + 1):
		for z in range(-reach, reach + 1):
			for index in stone_buckets.get(bucket + Vector2i(x, z), []):
				if stone_amounts[index] <= 0:
					continue
				var candidate := point.distance_to(stone_positions[index])
				if candidate < distance:
					best = index
					distance = candidate
	return best

func pickup_stone(index: int) -> int:
	if index < 0 or index >= stone_amounts.size() or stone_amounts[index] == 0 or carried >= capacity():
		return 0
	var amount := mini(gather_power(), capacity() - carried)
	stone_amounts[index] = 0
	carried += amount
	total_generated += amount
	stone_dirty[index] = true
	stone_cooldowns[index] = RESPAWN_SECONDS
	return amount

func pickup_pile(index: int) -> int:
	if index < 0 or index >= mountains.size() or not mountains[index]["settled"] or int(mountains[index]["stock"]) <= 0:
		return 0
	var amount := mini(gather_power(), mini(capacity() - carried, int(mountains[index]["stock"])))
	mountains[index]["stock"] = int(mountains[index]["stock"]) - amount
	carried += amount
	return amount

func closest_drop(point: Vector2, radius: float = 2.8) -> int:
	var best := -1
	var distance := radius
	for key in land_piles:
		var index := int(key)
		var candidate := point.distance_to(cell_center(index))
		if candidate < distance:
			best = index
			distance = candidate
	return best

func pickup_drop(index: int) -> int:
	var key := str(index)
	var amount := mini(gather_power(), mini(capacity() - carried, int(land_piles.get(key, 0))))
	if amount > 0:
		land_piles[key] = int(land_piles[key]) - amount
		if int(land_piles[key]) == 0:
			land_piles.erase(key)
		carried += amount
		piles_dirty = true
	return amount

func depth_for_col(col: int) -> int:
	if col < land_cols:
		return -1
	if col < land_cols + int(bands[0]):
		return 0
	return 1 if col < land_cols + int(bands[0]) + int(bands[1]) else 2

func cell_at(point: Vector2) -> int:
	if not point.is_finite():
		return -1
	var local := point - map_origin
	var col := floori(local.x / CELL_SIZE)
	var row := floori(local.y / CELL_SIZE)
	return row * grid_size + col if col >= 0 and col < grid_size and row >= 0 and row < grid_size else -1

func cell_center(index: int) -> Vector2:
	return map_origin + Vector2((index % grid_size + 0.5) * CELL_SIZE, (index / grid_size + 0.5) * CELL_SIZE)

func deposit(point: Vector2) -> int:
	var start := cell_at(point)
	if start < 0 or carried <= 0 or not can_throw(point):
		return 0
	if sea_depth[start] < 0:
		var amount := carried
		land_piles[str(start)] = int(land_piles.get(str(start), 0)) + amount
		carried = 0
		piles_dirty = true
		return amount
	var queue: Array[int] = [start]
	var visited: Dictionary = {start: true}
	var cursor := 0
	var delivered := 0
	while cursor < queue.size() and carried > 0:
		var index := queue[cursor]
		cursor += 1
		var amount := mini(carried, sea_capacity[index] - sea_fill[index])
		if amount > 0:
			sea_fill[index] += amount
			carried -= amount
			delivered += amount
			sea_dirty[index] = true
			if sea_fill[index] == sea_capacity[index]:
				filled_count += 1
		var col := index % grid_size
		var row := index / grid_size
		for offset in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0)]:
			var x: int = col + offset.x
			var y: int = row + offset.y
			if x < land_cols or x >= grid_size or y < 0 or y >= grid_size:
				continue
			var neighbor: int = y * grid_size + x
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	cultivation += delivered
	total_delivered += delivered
	if mining_unlocked():
		begin_mining(next_mountain())
	if delivered > 0:
		total_trips += 1
	if not won and total_delivered == target_stones:
		won = true
		messages.append("%s石落定。精卫终于完成了自己的心愿。" % number(target_stones))
	return delivered

func remaining_stones() -> int:
	var total := carried + total_delivered
	for mountain in mountains:
		total += int(mountain["stock"])
	for amount in land_piles.values():
		total += int(amount)
	return total

func sea_total() -> int:
	return target_stones

func completed_cells() -> int:
	return filled_count

func snapshot() -> Dictionary:
	return {"version": SAVE_VERSION, "target": target_stones, "seed": str(world_seed),
		"player": [player.x, player.y], "carried": carried, "cultivation": cultivation,
		"total_delivered": total_delivered, "total_generated": total_generated, "total_trips": total_trips,
		"elapsed": elapsed, "won": won, "upgrades": upgrades.duplicate(), "artifacts": artifacts.duplicate(),
		"artifact_plan": artifact_plan.duplicate(true), "mountains": mountains.duplicate(true),
		"stone_positions": stone_positions.map(func(p: Vector2) -> Array: return [p.x, p.y]),
		"stone_base": stone_base.duplicate(), "stone_amounts": stone_amounts.duplicate(),
		"stone_cooldowns": stone_cooldowns.duplicate(), "land_piles": land_piles.duplicate(),
		"sea_capacity": sea_capacity.duplicate(), "sea_fill": sea_fill.duplicate()}

static func from_snapshot(data: Dictionary) -> JWState:
	var legacy_version := 0
	if _integer(data.get("version")) and int(data["version"]) == 2:
		legacy_version = 2
		data = _migrate_v2(data)
		if data.is_empty():
			return null
	if not _integer(data.get("version")) or int(data["version"]) != SAVE_VERSION or not _integer(data.get("target")) or profile_for(int(data["target"])) == null:
		return null
	if not data.get("seed") is String or not String(data["seed"]).is_valid_int():
		return null
	for key in ["carried", "cultivation", "total_delivered", "total_generated", "total_trips"]:
		if not _integer(data.get(key)) or int(data[key]) < 0:
			return null
	if not _number(data.get("elapsed")) or float(data["elapsed"]) < 0 or not data.get("won") is bool:
		return null
	var result := JWState.new(int(data["target"]), int(data["seed"]), false)
	result.migrated_from = legacy_version
	if not _point(data.get("player")):
		return null
	result.player = Vector2(data["player"][0], data["player"][1])
	if result.cell_at(result.player) < 0:
		return null
	if not data.get("upgrades") is Dictionary or not data.get("artifacts") is Array:
		return null
	for kind in result.upgrades:
		if not _integer(data["upgrades"].get(kind)):
			return null
		var level := int(data["upgrades"][kind])
		if level < 0 or level > result.upgrade_limit(kind):
			return null
		result.upgrades[kind] = level
	for id in data["artifacts"]:
		if not id is String or id not in ["basket", "feather", "seal"] or result.artifacts.has(id):
			return null
		result.artifacts.append(id)
	result.carried = int(data["carried"])
	result.cultivation = int(data["cultivation"])
	result.total_delivered = int(data["total_delivered"])
	result.total_generated = int(data["total_generated"])
	result.total_trips = int(data["total_trips"])
	result.elapsed = float(data["elapsed"])
	result.won = data["won"]
	if result.carried > result.capacity():
		return null
	var map_count := result.grid_size * result.grid_size
	for key in ["sea_capacity", "sea_fill"]:
		if not data.get(key) is Array or data[key].size() != map_count:
			return null
	var capacity_total := 0
	var fill_total := 0
	for index in range(map_count):
		if not _integer(data["sea_capacity"][index]) or not _integer(data["sea_fill"][index]):
			return null
		var depth := result.depth_for_col(index % result.grid_size)
		var cap := int(data["sea_capacity"][index])
		var fill := int(data["sea_fill"][index])
		if fill < 0 or fill > cap or (depth < 0 and cap != 0):
			return null
		if depth >= 0 and (cap < DEPTH_MIN[depth] or cap > DEPTH_MAX[depth]):
			return null
		result.sea_capacity.append(cap)
		result.sea_fill.append(fill)
		result.sea_depth.append(depth)
		capacity_total += cap
		fill_total += fill
		if depth >= 0:
			result.sea_indices.append(index)
			if cap == fill:
				result.filled_count += 1
			if fill > 0:
				result.sea_dirty[index] = true
	if capacity_total != result.target_stones or fill_total != result.total_delivered or result.won != (fill_total == capacity_total):
		return null
	var count := int(profile_for(result.target_stones)["mountains"])
	if not data.get("mountains") is Array or data["mountains"].size() != count:
		return null
	var mountain_total := 0
	for entry in data["mountains"]:
		if not entry is Dictionary:
			return null
		for key in ["x", "z", "work", "yaw"]:
			if not _number(entry.get(key)):
				return null
		for key in ["yield", "stock", "shape"]:
			if not _integer(entry.get(key)):
				return null
		if not entry.get("started") is bool or not entry.get("settled") is bool:
			return null
		var point := Vector2(entry["x"], entry["z"])
		var index := result.cell_at(point)
		var stock := int(entry["stock"])
		var amount := int(entry["yield"])
		var work := float(entry["work"])
		if int(entry["shape"]) < 0 or int(entry["shape"]) >= 5 or float(entry["yaw"]) < 0 or float(entry["yaw"]) > TAU:
			return null
		if index < 0 or result.sea_depth[index] >= 0 or amount < 1024 or stock < 0 or stock > amount or work < 0 or work > amount:
			return null
		if bool(entry["settled"]) != (work >= amount) or (not entry["started"] and work > 0) or (not entry["settled"] and stock != 0):
			return null
		result.mountains.append({"x": point.x, "z": point.y, "yield": amount, "work": work, "stock": stock, "started": entry["started"], "settled": entry["settled"], "shape": int(entry["shape"]), "yaw": float(entry["yaw"])})
		mountain_total += amount
	if mountain_total != int(result.target_stones * 1.2):
		return null
	if not data.get("artifact_plan") is Array or data["artifact_plan"].size() != 3:
		return null
	for index in range(3):
		var entry: Variant = data["artifact_plan"][index]
		if not entry is Dictionary or entry.get("id") != ARTIFACT_CATALOG[index]["id"] or not _integer(entry.get("mountain")) or int(entry["mountain"]) != index or not _number(entry.get("threshold")):
			return null
		var threshold := float(entry["threshold"])
		if threshold <= 0 or threshold >= 1:
			return null
		var item: Dictionary = ARTIFACT_CATALOG[index].duplicate(true)
		item["mountain"] = index
		item["threshold"] = threshold
		result.artifact_plan.append(item)
		var found := float(result.mountains[index]["work"]) + 0.00001 >= float(result.mountains[index]["yield"]) * threshold
		if result.artifacts.has(String(item["id"])) != found:
			return null
	count = clampi(int(result.grid_size * result.grid_size / 3), 50, 1500)
	for key in ["stone_positions", "stone_base", "stone_amounts", "stone_cooldowns"]:
		if not data.get(key) is Array or data[key].size() != count:
			return null
	for index in range(count):
		if not _point(data["stone_positions"][index]) or not _integer(data["stone_base"][index]) or not _integer(data["stone_amounts"][index]) or not _number(data["stone_cooldowns"][index]):
			return null
		var point := Vector2(data["stone_positions"][index][0], data["stone_positions"][index][1])
		var cell := result.cell_at(point)
		var amount := int(data["stone_amounts"][index])
		var base := int(data["stone_base"][index])
		var cooldown := float(data["stone_cooldowns"][index])
		if cell < 0 or result.sea_depth[cell] >= 0 or base != 1 or amount < 0 or amount > 1 or cooldown < 0 or cooldown > RESPAWN_SECONDS:
			return null
		if not result.clear_of_mountains(point) or (amount > 0 and cooldown != 0):
			return null
		result.stone_positions.append(point)
		result.stone_base.append(base)
		result.stone_amounts.append(amount)
		result.stone_cooldowns.append(cooldown)
		result.stone_dirty[index] = true
	if not data.get("land_piles") is Dictionary:
		return null
	for key in data["land_piles"]:
		if not key is String or not String(key).is_valid_int() or not _integer(data["land_piles"][key]):
			return null
		var index := int(key)
		var amount := int(data["land_piles"][key])
		if index < 0 or index >= map_count or result.sea_depth[index] >= 0 or amount <= 0:
			return null
		result.land_piles[key] = amount
	var spent := 0
	for kind in result.upgrades:
		for level in range(int(result.upgrades[kind])):
			spent += cost_at(kind, level)
	if result.remaining_stones() != result.total_generated or result.cultivation != result.total_delivered - spent:
		return null
	result._rebuild_buckets()
	return result

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and absf(float(value)) <= 9007199254740991.0 and float(value) == floor(float(value))

static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

static func _migrate_v2(source: Dictionary) -> Dictionary:
	if not _integer(source.get("target")) or profile_for(int(source["target"])) == null:
		return {}
	if not source.get("seed") is String or not String(source["seed"]).is_valid_int() or not _point(source.get("player")):
		return {}
	if not source.get("upgrades") is Dictionary or not source.get("mountains") is Array or not source.get("land_piles") is Dictionary:
		return {}
	if not _integer(source.get("total_generated")):
		return {}
	var fresh := JWState.new(int(source["target"]), int(source["seed"]))
	if source["mountains"].size() != fresh.mountains.size():
		return {}
	var count := fresh.stone_positions.size()
	for key in ["stone_positions", "stone_base", "stone_amounts", "stone_cooldowns"]:
		if not source.get(key) is Array or source[key].size() != count:
			return {}
	var data := source.duplicate(true)
	var unharvested := 0
	for index in range(count):
		if not _integer(source["stone_amounts"][index]) or int(source["stone_amounts"][index]) < 0 or not _number(source["stone_cooldowns"][index]):
			return {}
		unharvested += int(source["stone_amounts"][index])
		data["stone_amounts"][index] = 1 if int(source["stone_amounts"][index]) > 0 else 0
		data["stone_base"][index] = 1
		if int(data["stone_amounts"][index]) > 0:
			data["stone_cooldowns"][index] = 0.0
	for index in range(fresh.mountains.size()):
		if not data["mountains"][index] is Dictionary:
			return {}
		for key in ["x", "z", "shape", "yaw"]:
			data["mountains"][index][key] = fresh.mountains[index][key]
	data["stone_positions"] = fresh.snapshot()["stone_positions"]
	data["total_generated"] = int(source["total_generated"]) - unharvested
	data["upgrades"]["throw"] = 0
	data["version"] = SAVE_VERSION
	var point := Vector2(source["player"][0], source["player"][1])
	if fresh.cell_at(point) < 0:
		return {}
	if not fresh.clear_of_mountains(point, 0.4):
		data["player"] = [fresh.player.x, fresh.player.y]
	# Old ground caches retain their stock, moving to a nearby clear land cell if necessary.
	var drops: Dictionary = {}
	for key in source["land_piles"]:
		if not key is String or not String(key).is_valid_int() or not _integer(source["land_piles"][key]):
			return {}
		var cell := int(key)
		if cell < 0 or cell >= fresh.sea_depth.size() or fresh.sea_depth[cell] >= 0 or int(source["land_piles"][key]) <= 0:
			return {}
		var at := fresh.cell_center(cell)
		if not fresh.clear_of_mountains(at):
			var nearest := INF
			for candidate in range(fresh.sea_depth.size()):
				if fresh.sea_depth[candidate] < 0 and fresh.clear_of_mountains(fresh.cell_center(candidate)):
					var distance := at.distance_squared_to(fresh.cell_center(candidate))
					if distance < nearest:
						nearest = distance
						cell = candidate
		drops[str(cell)] = int(drops.get(str(cell), 0)) + int(source["land_piles"][key])
	data["land_piles"] = drops
	return data
