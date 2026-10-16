extends RefCounted
## Device preferences are deliberately independent of the resource/save ledger.
const DEFAULTS := {"version": 1, "quality": "standard", "fullscreen": false, "volume": 1.0, "muted": false, "first_person": false, "view_key": KEY_V}
const LIMIT := 8192

static func sanitize(data: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	if data.get("version") != 1:
		return result
	if data.get("quality") in ["standard", "smooth"]:
		result.quality = data.quality
	for key in ["fullscreen", "muted", "first_person"]:
		if data.get(key) is bool:
			result[key] = data[key]
	var volume: Variant = data.get("volume")
	if (volume is float or volume is int) and is_finite(float(volume)):
		result.volume = clampf(float(volume), 0, 1)
	var view_key: Variant = data.get("view_key")
	if (view_key is int or view_key is float) and is_finite(float(view_key)) and float(view_key) == int(view_key) and valid_view_key(int(view_key)):
		result.view_key = int(view_key)
	return result

static func valid_view_key(key: int) -> bool:
	# Single physical keys; reserve all existing controls and OS modifier keys.
	return ((key >= KEY_A and key <= KEY_Z) or (key >= KEY_F2 and key <= KEY_F12)) and key not in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_E, KEY_Q, KEY_U, KEY_M, KEY_F4]

static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > LIMIT:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var data: Variant = parser.data
	return data if data is Dictionary and data.get("version") == 1 else {}

static func load_preferences(path: String) -> Dictionary:
	var data := read(path)
	if data.is_empty():
		data = read(path + ".bak")
	return sanitize(data)

static func save_preferences(path: String, data: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		return error
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(sanitize(data)))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	if not read(path).is_empty():
		error = DirAccess.copy_absolute(absolute, absolute + ".bak")
		if error != OK:
			return error
	return DirAccess.rename_absolute(absolute + ".tmp", absolute)
