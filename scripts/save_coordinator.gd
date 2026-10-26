extends RefCounted
## Owns write ordering, coalescing and durability barriers. No scene/UI references.
signal started
signal completed(error: Error, manual: bool)
const Store = preload("res://scripts/save_store.gd")
const Worker = preload("res://scripts/save_worker.gd")
var worker = Worker.new()
var pending := false

func request(path: String, snapshot: Callable) -> void:
	if worker.busy():
		pending = true
		return
	# The caller supplies a fresh detached snapshot on the main thread.
	var error: Error = worker.start(path, snapshot.call())
	if error != OK:
		completed.emit(error, false)
	else:
		started.emit()

func poll(path: String, snapshot: Callable, allow_followup: bool) -> void:
	if not worker.ready(): return
	completed.emit(worker.finish(), false)
	if pending:
		pending = false
		if allow_followup: request(path, snapshot)

func save_now(path: String, state: JWState, manual: bool) -> bool:
	finish()
	var error := Store.save_game(path, state)
	completed.emit(error, manual)
	return error == OK

func finish() -> void:
	pending = false
	worker.finish()

static func archive_before_new(path: String, state: JWState, persist_current: bool) -> bool:
	if persist_current and Store.save_game(path, state) != OK:
		return false
	for suffix in ["", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			var archive: String = path + suffix + ".before-reset-" + str(int(Time.get_unix_time_from_system())) + "-" + str(Time.get_ticks_usec())
			if DirAccess.copy_absolute(ProjectSettings.globalize_path(path + suffix), ProjectSettings.globalize_path(archive)) != OK:
				return false
	return true
