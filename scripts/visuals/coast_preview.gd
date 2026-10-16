extends "res://scripts/main.gd"
## Playable fixed coast sample with ordinary controls and no player-save access.
func _ready() -> void:
	save_enabled = false
	await super._ready()
	selection_pending = false
	hud.hide_modal()
