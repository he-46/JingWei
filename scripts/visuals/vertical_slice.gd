extends "res://scripts/main.gd"
## Fixed seed 10213. Ordinary gameplay, no staged resources and no player-save access.
func _ready() -> void:
	save_enabled = false
	skip_scale_picker = true
	await super._ready()
	selection_pending = false
	hud.hide_modal()
	hud.save_label.text = "样板旅程 · 本次进度不保存"

func save_game(manual: bool = false) -> bool:
	if manual and hud != null:
		hud.notify("样板进度只保留在本次运行中。")
	return true
