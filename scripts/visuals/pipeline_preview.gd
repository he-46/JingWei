extends "res://scripts/main.gd"
## A complete playable journey using diagnostic imports, with saving disabled.
func _ready() -> void:
	save_enabled = false
	super._ready()
