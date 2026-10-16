extends RefCounted
## Device preferences are deliberately independent of the resource/save ledger.
const DEFAULTS := {"version": 1, "quality": "standard", "fullscreen": false, "volume": 1.0, "muted": false}
const LIMIT := 8192

static func sanitize(data: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	if data.get("version") != 1:
		return result
	if data.get("quality") in ["standard", "smooth"]:
		result.quality = data.quality
	for key in ["fullscreen", "muted"]:
		if data.get(key) is bool:
			result[key] = data[key]
	var volume: Variant = data.get("volume")
	if (volume is float or volume is int) and is_finite(float(volume)):
		result.volume = clampf(float(volume), 0, 1)
	return result

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
