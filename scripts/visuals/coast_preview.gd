extends "res://scripts/main.gd"
## Playable fixed coast sample with ordinary controls and no player-save access.
func _ready() -> void:
	save_enabled = false
	super._ready()
	choose_world(100000)
