extends RefCounted
## One immutable snapshot and one writer. The scene coalesces later requests.
const Store = preload("res://scripts/save_store.gd")
var thread: Thread

func busy() -> bool:
	return thread != null

func start(path: String, snapshot: Dictionary) -> Error:
	if busy():
		return ERR_BUSY
	thread = Thread.new()
	var error := thread.start(Store.save_snapshot.bind(path, snapshot))
	if error != OK:
		thread = null
	return error

func ready() -> bool:
	return busy() and not thread.is_alive()

func finish() -> Error:
	if not busy():
		return OK
	var result: Error = thread.wait_to_finish()
	thread = null
	return result
