extends SceneTree
## Runtime dependency and font audit. Diagnostic assets are deliberately excluded.
const Catalog = preload("res://scripts/visuals/asset_catalog.gd")
var checks := 0
var failures := 0
var seen: Dictionary = {}
var records: Array = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func dependencies(path: String) -> void:
	if seen.has(path):
		return
	seen[path] = true
	expect(ResourceLoader.exists(path), "formal dependency exists: " + path)
	expect(not path.contains("pipeline_examples") and not path.contains("example_jingwei") and not path.contains("example_pangolin"), "formal graph excludes diagnostic models: " + path)
	for dependency in ResourceLoader.get_dependencies(path):
		var target: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
		if target.begins_with("res://"):
			dependencies(target)

func files(folder: String, extension: String) -> Array[String]:
	var result: Array[String] = []
	for name in DirAccess.get_files_at(folder):
		if name.get_extension() == extension:
			result.append(folder.path_join(name))
	for directory in DirAccess.get_directories_at(folder):
		result.append_array(files(folder.path_join(directory), extension))
	return result

func inspect_model(path: String) -> void:
	dependencies(path)
	var scene: PackedScene = load(path)
	var model := scene.instantiate()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	expect(not meshes.is_empty(), "formal GLB has renderable geometry: " + path)
	var triangles := 0
	var valid := true
	for node in meshes:
		var mesh: Mesh = node.mesh
		valid = valid and mesh != null and mesh.get_surface_count() > 0
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			valid = valid and arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size()
			triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	expect(valid, "formal GLB surfaces retain UVs: " + path)
	var clips: Array[String] = []
	for player in model.find_children("*", "AnimationPlayer", true, false):
		for clip in player.get_animation_list():
			clips.append(clip)
	records.append({"path": path, "mesh_nodes": meshes.size(), "all_mesh_triangles_including_hidden_cargo": triangles, "clips": clips})
	model.free()

func run() -> void:
	dependencies("res://scenes/main.tscn")
	dependencies("res://scenes/actors/jingwei.tscn")
	dependencies("res://scenes/actors/pangolin.tscn")
	var models := files("res://assets/models/characters", "glb")
	models.append_array(files("res://assets/models/environment", "glb"))
	models.append_array(files("res://assets/models/relics", "glb"))
	models.sort()
	expect(models.size() == 36, "release contains 36 formal GLBs, excluding three diagnostic examples")
	for path in models:
		inspect_model(path)
	for path in files("res://assets/materials", "tres"):
		dependencies(path)
		expect(load(path) is Material, "formal material loads: " + path)
	var textures := files("res://assets/textures", "png")
	textures.append_array(files("res://assets/icons", "png"))
	for path in textures:
		dependencies(path)
		var texture: Texture2D = load(path)
		expect(texture.get_width() > 0 and texture.get_height() > 0, "texture decodes: " + path)
		expect(texture.get_image().has_mipmaps() or path.contains("/icons/"), "runtime surface texture has mipmaps: " + path)
	var audio := files("res://assets/audio", "wav")
	expect(audio.size() == 19, "all nineteen original sound files are present")
	for path in audio:
		dependencies(path)
		var stream: AudioStream = load(path)
		expect(stream.get_length() > 0, "sound imports and has duration: " + path)
	for pair in [["jingwei", ["idle", "fly", "carry_fly", "gather", "throw", "turn_left", "turn_right"]], ["pangolin", ["idle", "locked", "walk", "dig", "complete", "finished"]]]:
		var actor = load("res://scenes/actors/%s.tscn" % pair[0]).instantiate()
		root.add_child(actor)
		expect(actor.model_scene.resource_path == "res://assets/models/characters/%s.glb" % pair[0], "formal actor has no procedural fallback")
		for name in pair[1]:
			expect(actor.animation_player != null and actor.animation_player.has_animation(name), "declared actor action exists: " + name)
		actor.queue_free()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "SimHei"])
	var codepoints: Dictionary = {}
	for path in ["res://scripts/hud.gd", "res://scripts/main.gd", "res://scripts/state.gd"]:
		var source := FileAccess.get_file_as_string(path)
		for i in range(source.length()):
			var code := source.unicode_at(i)
			if code >= 0x4e00 and code <= 0x9fff:
				codepoints[code] = true
	for i in "×→…·%0123456789".length():
		codepoints["×→…·%0123456789".unicode_at(i)] = true
	var missing := ""
	for code in codepoints:
		if not font.has_char(code):
			missing += String.chr(code)
	expect(missing.is_empty(), "system font covers UI Chinese and symbols; missing: " + missing)
	var output := "res://artifacts/art/art09-audit"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output.path_join("runtime-assets.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "formal_models": records,
		"dependency_count": seen.size(), "textures": textures, "audio_count": audio.size(), "font_name": font.get_font_name(),
		"font_codepoints_checked": codepoints.size(), "missing_glyphs": missing, "engine": Engine.get_version_info().string}, "\t"))
	await process_frame
	print("RELEASE ASSET TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
