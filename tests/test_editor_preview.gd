extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	for path in ["res://scenes/actors/jingwei.tscn", "res://scenes/actors/pangolin.tscn"]:
		var actor = load(path).instantiate()
		var authored = actor.get_node("Model")
		expect(authored.find_children("*", "MeshInstance3D", true, false).size() > 0, "model exists before ready, including editor mode")
		root.add_child(actor)
		expect(actor.model == authored and actor.get_child_count() == 1, "runtime adopts existing model without doubling")
		actor.replace_model(actor.model_scene)
		await process_frame
		expect(actor.get_child_count() == 1 and is_instance_valid(actor.animation_player), "model replacement still leaves one animated model")
		actor.queue_free()
		await process_frame
	var scene = load("res://scenes/art/editor_coast.tscn").instantiate()
	expect(scene.get_script() == null, "preview geometry does not depend on a runtime builder")
	expect(scene.get_node("Coast/Sea") is MeshInstance3D and scene.get_node("Characters/Jingwei/Model") != null, "sea and actor are authored scene nodes")
	root.add_child(scene)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		for i in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/editor-coast.png")
	scene.queue_free()
	await process_frame
	print("EDITOR PREVIEW TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
