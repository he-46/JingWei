extends Control
## Keep the first frame independent of imported 3D scenes and their scripts.
const GAME := "res://scenes/main.tscn"
const BUNDLE := "res://assets/startup_bundle.tres"
var progress: ProgressBar
var message: Label
var closing := false
var resource_requested := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("e1e7dd")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 360
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	message = Label.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "SimHei"])
	message.add_theme_font_override("font", font)
	message.add_theme_font_size_override("font_size", 22)
	message.add_theme_color_override("font_color", Color("29413b"))
	message.text = "准备旅程"
	box.add_child(message)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12
	for part in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("547b61") if part == "fill" else Color("dce3d7")
		style.set_corner_radius_all(2)
		progress.add_theme_stylebox_override(part, style)
	box.add_child(progress)
	# A process_frame alone resumes before drawing; submit the actual waiting UI.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await get_tree().process_frame
	if not closing:
		_load_game()

func _load_game() -> void:
	# Native imported assets are safe to load off-thread. Instantiate/compile the
	# gameplay script on the main thread after its heavy asset dependencies arrive.
	var error := ResourceLoader.load_threaded_request(BUNDLE)
	if error != OK:
		_failed()
		return
	resource_requested = true
	while not closing:
		var values: Array = []
		var status := ResourceLoader.load_threaded_get_status(BUNDLE, values)
		if not values.is_empty():
			progress.value = float(values[0]) * 100
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			resource_requested = false
			var bundle: Resource = ResourceLoader.load_threaded_get(BUNDLE)
			if bundle == null:
				_failed()
				return
			# Keep the bundle alive until Main's preloads acquire their references.
			var scene: PackedScene = load(GAME)
			if get_tree().change_scene_to_packed(scene) != OK:
				_failed()
			return
		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_failed()
			return
		await get_tree().process_frame

func _failed() -> void:
	message.text = "资源读取失败，请重新启动游戏。"
	progress.hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		closing = true
		_finish_request()
		get_tree().quit()

func _finish_request() -> void:
	if resource_requested:
		resource_requested = false
		# Consume and join the native resource job even when its scene is abandoned.
		var pending: Resource = ResourceLoader.load_threaded_get(BUNDLE)
		pending = null

func _exit_tree() -> void:
	closing = true
	_finish_request()
