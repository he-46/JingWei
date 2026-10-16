extends SceneTree
## The editor test harness mounts the actual shipping PCK from an isolated folder.
var checks := 0
var failures := 0

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	expect(ProjectSettings.get_setting("application/config/custom_user_dir_name") == "AzVGames/Jingwei", "source and standalone share save location")
	for path in ["res://tests", "res://tools", "res://docs", "res://art_source", "res://Godot", "res://scenes/art", "res://assets/models/pipeline_examples"]:
		expect(not DirAccess.dir_exists_absolute(path), "authoring and diagnostics excluded: " + path)
	var files: Array[String] = []
	collect("res://", files)
	var models := 0
	var audio := 0
	for path in files:
		expect(not path.ends_with(".blend") and not path.ends_with(".zip") and not path.ends_with(".ps1") and not path.ends_with(".json"), "no source bundles or saves: " + path)
		if path.ends_with(".glb"):
			models += 1
			var scene = load(path)
			expect(scene is PackedScene, "dynamic model resolves: " + path)
			if scene is PackedScene:
				var instance = scene.instantiate()
				expect(instance is Node3D, "exported model instantiates: " + path)
				instance.free()
		if path.ends_with(".wav"):
			audio += 1
			expect(load(path) is AudioStream, "dynamic sound resolves: " + path)
	expect(models == 36, "all 36 formal dynamic GLBs included")
	expect(audio == 19, "all 19 runtime sounds included")
	for path in ["res://assets/ui/app_icon.svg", "res://assets/icons/relics/basket.png", "res://assets/icons/relics/feather.png", "res://assets/icons/relics/seal.png"]:
		expect(load(path) is Texture2D, "runtime icon resolves: " + path)
	print("WINDOWS PACK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func collect(folder: String, files: Array[String]) -> void:
	for name in DirAccess.get_files_at(folder):
		var path := folder.path_join(name.trim_suffix(".remap").trim_suffix(".import"))
		if not files.has(path):
			files.append(path)
	for name in DirAccess.get_directories_at(folder):
		# The import cache contains remapped binary resources; only walk virtual assets.
		if not name.begins_with("."):
			collect(folder.path_join(name), files)
