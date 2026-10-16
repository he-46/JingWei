extends RefCounted

const State = preload("res://scripts/state.gd")
const LIMIT := 1024 * 1024

static func _read(path: String) -> JWState:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > LIMIT:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	var data: Variant = parser.data
	if not data is Dictionary:
		return null
	return State.from_snapshot(data)

static func load_game(path: String) -> Dictionary:
	var state: JWState = _read(path)
	if state != null:
		return {"state": state, "status": "loaded"}
	state = _read(path + ".bak")
	if state != null:
		return {"state": state, "status": "recovered"}
	var exists := FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")
	return {"state": null, "status": "invalid" if exists else "new"}

static func save_game(path: String, state: JWState) -> Error:
	return save_snapshot(path, state.snapshot())

static func save_snapshot(path: String, snapshot: Dictionary) -> Error:
	if State.from_snapshot(snapshot) == null:
		return ERR_INVALID_DATA
	var parent := ProjectSettings.globalize_path(path).get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(parent)
	if error != OK:
		return error
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot, "", true, true))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	# Keep a known-good previous save; never replace it with corrupt input.
	if _read(path) != null:
		var backup := FileAccess.open(path + ".bak.tmp", FileAccess.WRITE)
		if backup == null:
			return FileAccess.get_open_error()
		backup.store_buffer(FileAccess.get_file_as_bytes(path))
		backup.flush()
		error = backup.get_error()
		backup.close()
		if error != OK:
			return error
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".bak.tmp"), ProjectSettings.globalize_path(path + ".bak"))
		if error != OK:
			return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
