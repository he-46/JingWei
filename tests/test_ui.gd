extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.choose_world(100000)
	await process_frame
	var hud: CanvasLayer = game.hud
	expect(hud.drawer.visible and not hud.relic_page.visible and not hud.overview_panel.visible, "default HUD shows upgrades without map or artifact panels")
	var viewport: Rect2 = hud.root.get_global_rect()
	expect(viewport.encloses(hud.interact_button.get_global_rect()) and viewport.encloses(hud.throw_button.get_global_rect()), "bottom action buttons stay inside the viewport")
	hud.select_tab("relics")
	await process_frame
	await process_frame
	expect(hud.drawer.size.y < 360, "artifact drawer shrinks to its content without a tall empty panel")
	expect(hud.relic_page.visible and not hud.upgrade_page.visible, "artifact tab replaces upgrades instead of stacking another panel")
	hud.toggle_drawer()
	expect(not hud.drawer.visible, "sidebar can be fully collapsed")
	game.toggle_overview()
	expect(hud.overview_panel.visible and not hud.drawer.visible, "map details appear only in overview")
	game.toggle_overview()
	expect(not hud.drawer.visible, "leaving overview respects the user's collapsed sidebar")
	var event := InputEventAction.new()
	event.action = "jw_upgrades"
	event.pressed = true
	game._unhandled_input(event)
	expect(hud.drawer.visible and hud.relic_page.visible, "U restores the selected sidebar tab")
	hud.select_tab("upgrades")
	hud.notice_panel.visible = false
	hud.notification_time = 0
	game.interact()
	expect(game.state.carried > 0 and not hud.notice_panel.visible, "ordinary gathering updates counts without a toast")
	hud.notify("检查提示")
	hud._process(3.5)
	expect(not hud.notice_panel.visible and hud.notification_time == 0, "temporary notifications expire and release screen space")
	game.show_help()
	expect(hud.modal_open and hud.modal_text.text.contains("WASD") and hud.modal_text.text.contains("U"), "help retains discoverable controls removed from permanent HUD")
	hud.toggle_drawer()
	expect(hud.drawer.visible, "modal blocks sidebar toggles")
	game._modal_action("resume")
	game.show_menu()
	game._modal_action("help")
	expect(hud.modal_open and hud.modal_title.text == "操作", "pause menu routes to help")
	game._modal_action("resume")
	# Extreme progression values must not collide with purchase prices.
	game.state.upgrades["bag"] = 20
	game.state.upgrades["mining"] = 20
	game._refresh()
	await process_frame
	for kind in ["bag", "mining"]:
		var detail: Dictionary = hud.upgrade_details[kind]
		expect(detail["value"].get_global_rect().end.x <= detail["cost"].get_global_rect().position.x, "late-game upgrade value and price remain separate")
	game.world.bird_body.position.y = 5
	game._refresh()
	expect(hud.interact_button.disabled, "high-flight context does not offer unusable ground interactions")
	game.queue_free()
	await process_frame
	print("UI TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
