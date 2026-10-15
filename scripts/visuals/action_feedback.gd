extends Node3D
## Presentation only. All resource settlement has already happened in JWState.
signal landed(sea: bool, formed_land: bool, completed: bool, audio_epoch: int)

const Models = preload("res://scripts/models.gd")
const FLIGHT_SECONDS := 0.48
const FLIGHT_LIMIT := 12
const BURST_LIMIT := 24
const CHIP_COUNT := 8
const RELIC_SECONDS := 2.2
const RELICS := {
	"basket": preload("res://assets/models/relics/basket.glb"),
	"feather": preload("res://assets/models/relics/feather.glb"),
	"seal": preload("res://assets/models/relics/seal.glb"),
}
const COLORS := {"gather": Color("e4cf9c"), "throw": Color("dccaaa"),
	"water": Color("d6f5ef"), "land": Color("c5ad83"), "fill": Color("f1d184"),
	"mined": Color("c6b99d"), "relic": Color("edd798")}
var flights: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var relics: Dictionary = {}
var events: Dictionary = {}
var suppressed_flights := 0
var serial := 0
var detail_origin := Vector3.ZERO
var overview := false

func set_detail(origin: Vector3, map_view: bool) -> void:
	detail_origin = origin
	overview = map_view

func detail_visible(point: Vector3) -> bool:
	return not overview and Vector2(point.x - detail_origin.x, point.z - detail_origin.z).length_squared() < 70 * 70

func _ready() -> void:
	var rock := Models.rock_mesh(2)
	var stone := Models.material(Color("d9ceb3"))
	var ring := TorusMesh.new()
	ring.inner_radius = .84
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 6
	for index in range(FLIGHT_LIMIT):
		var node := Models.mesh_part(self, rock, stone, Vector3.ZERO, Vector3.ONE * .27)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.hide()
		flights.append({"node": node, "active": false, "age": 0.0})
	for index in range(BURST_LIMIT):
		var holder := Node3D.new()
		add_child(holder)
		var mat := Models.material(Color.WHITE)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var circle := Models.mesh_part(holder, ring, mat, Vector3.ZERO)
		circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var chips := MultiMeshInstance3D.new()
		chips.multimesh = MultiMesh.new()
		chips.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		chips.multimesh.mesh = rock
		chips.multimesh.instance_count = CHIP_COUNT
		chips.material_override = mat
		chips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(chips)
		holder.hide()
		bursts.append({"node": holder, "ring": circle, "chips": chips.multimesh,
			"material": mat, "active": false, "age": 0.0, "serial": 0})
	for id in RELICS:
		var model: Node3D = RELICS[id].instantiate()
		add_child(model)
		model.hide()
		relics[id] = {"node": model, "active": false, "age": 0.0}

func count_event(kind: String) -> void:
	events[kind] = int(events.get(kind, 0)) + 1

func throw_stone(start: Vector3, end: Vector3, sea: bool, formed_land: bool, completed: bool, audio_epoch: int) -> bool:
	count_event("launch")
	var chosen: Dictionary = {}
	for slot in flights:
		if not slot.active:
			chosen = slot
			break
	# Excess ordinary flights are omitted. Important formation/completion may replace
	# an ordinary flight; never rush an impact or suppress the final completion cue.
	if chosen.is_empty() and (formed_land or completed):
		for slot in flights:
			if not slot.completed and (completed or not slot.formed):
				if chosen.is_empty() or float(slot.age) > float(chosen.age):
					chosen = slot
	if chosen.is_empty():
		suppressed_flights += 1
		return false
	if chosen.active:
		suppressed_flights += 1
	chosen.merge({"active": true, "age": 0.0, "start": start, "end": end,
		"sea": sea, "formed": formed_land, "completed": completed, "epoch": audio_epoch}, true)
	chosen.node.position = start
	chosen.node.show()
	burst("throw", start)
	return true

func burst(kind: String, point: Vector3, target: Vector3 = Vector3.ZERO, radius: float = 1.0) -> Dictionary:
	count_event(kind)
	var chosen: Dictionary = bursts[0]
	for slot in bursts:
		if not slot.active:
			chosen = slot
			break
		if int(slot.serial) < int(chosen.serial):
			chosen = slot
	serial += 1
	chosen.merge({"active": true, "age": 0.0, "serial": serial, "kind": kind,
		"duration": .42 if kind == "gather" else (.24 if kind == "throw" else (1.15 if kind in ["fill", "mined", "relic"] else .65)),
		"point": point, "target": target, "radius": radius}, true)
	chosen.node.position = point
	chosen.node.show()
	_update_burst(chosen)
	return chosen

func discover(id: String, point: Vector3) -> void:
	if not relics.has(id):
		return
	var slot: Dictionary = relics[id]
	slot.merge({"active": true, "age": 0.0, "point": point}, true)
	slot.node.position = point
	slot.node.scale = Vector3.ONE * .15
	slot.node.show()
	burst("relic", point - Vector3.UP * .35, Vector3.ZERO, 1.2)
	count_event("discover")

func advance(delta: float) -> void:
	# Called once by the owner during unpaused frames. No Tween/timer can outlive a world.
	for slot in bursts:
		if slot.active:
			slot.node.visible = detail_visible(slot.point)
			_advance_burst(slot, delta)
	for slot in flights:
		if not slot.active:
			continue
		slot.age += delta
		slot.node.visible = detail_visible(slot.end)
		var t := minf(float(slot.age) / FLIGHT_SECONDS, 1.0)
		slot.node.position = slot.start.lerp(slot.end, t) + Vector3.UP * sin(t * PI) * 1.5
		slot.node.rotation = Vector3(t * 6, t * 9, t * 3)
		if t >= 1.0:
			slot.active = false
			slot.node.hide()
			var impact := burst("water" if slot.sea else "land", slot.end)
			_advance_burst(impact, float(slot.age) - FLIGHT_SECONDS)
			if slot.formed:
				var formation := burst("fill", slot.end, Vector3.ZERO, 1.6)
				_advance_burst(formation, float(slot.age) - FLIGHT_SECONDS)
			landed.emit(slot.sea, slot.formed, slot.completed, slot.epoch)
	for id in relics:
		var slot: Dictionary = relics[id]
		if not slot.active:
			continue
		slot.age += delta
		var t := clampf(float(slot.age) / RELIC_SECONDS, 0, 1)
		slot.node.visible = detail_visible(slot.point)
		slot.node.position = slot.point + Vector3.UP * (t * .85 + sin(t * PI) * .16)
		slot.node.rotation.y = t * TAU * .6
		var sizing := minf(t * 8, 1) * minf((1 - t) * 5, 1)
		slot.node.scale = Vector3.ONE * maxf(.001, sizing * 1.2)
		if t >= 1.0:
			slot.active = false
			slot.node.hide()

func _advance_burst(slot: Dictionary, delta: float) -> void:
	slot.age += delta
	if float(slot.age) >= float(slot.duration):
		slot.active = false
		slot.node.hide()
	else:
		_update_burst(slot)

func _update_burst(slot: Dictionary) -> void:
	slot.node.visible = detail_visible(slot.point)
	if not slot.node.visible:
		return
	var t := clampf(float(slot.age) / float(slot.duration), 0, 1)
	var color: Color = COLORS[slot.kind]
	color.a = (1 - t) * .80
	slot.material.albedo_color = color
	var radius: float = float(slot.radius) * (.16 + t * 1.1)
	slot.ring.scale = Vector3(radius, .3, radius)
	slot.ring.visible = slot.kind != "mined"
	for chip in range(CHIP_COUNT):
		var a := float(chip) / CHIP_COUNT * TAU + .17 * (chip % 3)
		var offset := Vector3(cos(a), 0, sin(a)) * radius * (.45 + .08 * (chip % 4))
		offset.y = sin(t * PI) * (.3 if slot.kind == "land" else .8) + .03
		var size := (.25 if slot.kind == "mined" else (.18 if slot.kind == "water" else .12)) * (1 - t)
		var proportions := Vector3(1, 1.7, 1) if slot.kind == "water" else Vector3.ONE
		if slot.kind == "gather":
			offset = (slot.target - slot.point) * t + offset * (1 - t)
		if slot.kind == "throw":
			size *= .5
		var transform := Transform3D(Basis.from_euler(Vector3(a, t * 3, a)).scaled(proportions * maxf(size, .001)), offset)
		slot.chips.set_instance_transform(chip, transform)

func active_counts() -> Vector3i:
	var counts := Vector3i.ZERO
	for slot in flights:
		counts.x += int(slot.active)
	for slot in bursts:
		counts.y += int(slot.active)
	for id in relics:
		counts.z += int(relics[id].active)
	return counts

func completion_pending() -> bool:
	for slot in flights:
		if slot.active and slot.completed:
			return true
	return false
