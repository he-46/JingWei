extends RefCounted
## Save IDs are families, never new gameplay types. First member of each family
## retains the previous meaning; alternate members are deterministic visual only.
const MOUNTAINS := ["strata_mountain", "spire_mountain", "twin_mountain", "ridge_mountain", "mesa_mountain", "needle_mountain", "split_mountain", "crag_mountain"]
const STONES := ["quarry_stone", "scatter_stone_1", "scatter_stone_2", "scatter_stone_3", "scatter_stone_4", "scatter_stone_5"]
const TREES := ["coast_tree", "coast_pine", "coast_wind_tree"]
const SHRUBS := ["coast_shrub", "coast_scrub"]
const GRASSES := ["coast_grass", "coast_low_grass"]
const TREE_CROWNS := [Vector2(2.4, 1.05), Vector2(2.3, 1.4), Vector2(2.3, 1.55)]
const Visual = preload("res://scripts/visuals/mountain_visual.gd")

static func mountain_variant(save_id: int, index: int) -> int:
	return save_id + 4 if save_id in [1, 2, 3] and (index / 5) % 2 == 1 else save_id

static func scenes(names: Array, suffix: String = "") -> Array[PackedScene]:
	var result: Array[PackedScene] = []
	for name in names:
		result.append(load("res://assets/models/environment/%s%s.glb" % [name, suffix]))
	return result

static func meshes(names: Array, suffix: String = "") -> Array[Mesh]:
	var result: Array[Mesh] = []
	for scene in scenes(names, suffix):
		result.append(Visual.imported_mesh(scene))
	return result

static func regional_variant(point: Vector3, variants: int, index: int) -> int:
	# Small coherent groves/stone fields instead of a checkerboard of every asset.
	return posmod(floori(point.x / 12) * 7 + floori(point.z / 12) * 3 + index / 5, variants)

static func quarry_transform(visual, part: int, layout: int) -> Transform3D:
	var result: Transform3D = Visual.pile_transform(visual, part)
	if result.origin.y < -10:
		return result
	var tier := 0 if part < 16 else (1 if part < 26 else 2)
	var start: int = [0, 16, 26][tier]
	var count: int = [16, 10, 6][tier]
	var angle := float(part - start) / count * TAU + tier * .35
	var spread: float = minf(2.5, visual.radius * .82)
	var radial: float = spread * [0.76, .48, .20][tier]
	var offset := Vector3(cos(angle) * radial, .02 + tier * .24 * minf(1, visual.radius / 2.2), sin(angle) * radial)
	# Elliptic ridge and two-lobed field fit inside the same reserved quarry disk.
	if layout == 1:
		offset.z *= .48
		offset.y *= .75
	else:
		offset.x *= .65
		offset.z = offset.z * .55 + (.55 if part % 2 else -.55) * minf(1, visual.radius / 2.2)
	result.origin = visual.transform.origin + offset
	return result
