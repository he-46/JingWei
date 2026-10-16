extends SceneTree

const Soundscape = preload("res://scripts/soundscape.gd")
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
	var audio := Soundscape.new()
	root.add_child(audio)
	expect(audio.voices.size() == 8, "fixed eight-voice pool")
	var resources_ok := true
	var max_peak := 0.0
	for bank in audio.streams.values():
		for clip in bank:
			resources_ok = resources_ok and clip is AudioStreamWAV and clip.get_length() > 0.1
			var pcm: PackedByteArray = clip.data
			var peak := 0.0
			for index in range(0, pcm.size(), 2):
				peak = maxf(peak, absf(pcm.decode_s16(index) / 32768.0))
			max_peak = maxf(max_peak, peak)
			resources_ok = resources_ok and peak > 0.1 and peak < 0.63
			resources_ok = resources_ok and pcm.decode_s16(0) == 0 and pcm.decode_s16(pcm.size() - 2) == 0
	expect(resources_ok, "every imported cue has audible PCM, headroom and zero endpoints")
	# Conservative bound even if all voice peaks align at their loudest configured gain.
	expect(6 * max_peak * db_to_linear(-16) + 2 * max_peak * db_to_linear(-15) + .28 * db_to_linear(-27) < 1.0, "worst-case layered gain retains output headroom")
	expect(audio.ambience.stream.stereo and audio.ambience.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "surf is a stereo loop")
	audio.set_context(0, false, false)
	var shoreline: float = audio.ambience_target
	audio.set_context(-50, false, false)
	expect(audio.ambience_target < shoreline, "surf grows quieter inland")
	audio.set_context(0, true, false)
	expect(audio.ambience_target < shoreline, "dialogue and pause reduce surf")
	audio.set_context(0, false, true)
	expect(audio.ambience_target == -60, "scale selection has no surf")
	expect(audio.play("gather") and not audio.play("gather"), "rapid repeated gathers are rate limited")
	var variant: int = audio.last_variant["gather"]
	audio.clock += .1
	audio.play("gather")
	expect(audio.last_variant["gather"] != variant, "successive gathers select different recordings")
	for index in range(30):
		audio.clock += .2
		audio.play("water")
	expect(audio.get_child_count() == 9, "bursting effects never allocate more players")
	audio.play("complete")
	audio.play("relic")
	expect(not audio.play("fill"), "ordinary progress cannot interrupt discovery and completion")
	var epoch: int = audio.epoch
	audio.set_muted(true)
	expect(audio.epoch > epoch and not audio.play("upgrade"), "mute invalidates pending effects and blocks new sounds")
	var stopped := not audio.ambience.playing
	for voice in audio.voices:
		stopped = stopped and not voice.playing
	expect(stopped, "mute immediately stops active effects and surf")
	audio.set_muted(false)
	expect(audio.play("upgrade"), "unmute restores new sounds")
	audio.queue_free()
	await process_frame

	# Exercise real game entry points and the 0.48-second projectile callback.
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game.wait_until_ready()
	await process_frame
	game.choose_world(100000)
	await game.wait_until_ready()
	game.set_physics_process(false)
	game.soundscape.set_muted(false)
	game.interact()
	expect(game.soundscape.last_variant.has("gather"), "successful game collection plays stone sound")
	game.state.player = Vector2(-1, 3)
	var point := Vector2(2, 3)
	game.deposit_at(point)
	expect(game.soundscape.last_variant.has("throw") and not game.soundscape.last_variant.has("water"), "throw begins with whoosh and no early splash")
	await create_timer(.6).timeout
	expect(game.soundscape.last_variant.has("water"), "splash plays when projectile lands")
	game.soundscape.reset()
	game.state.pickup_stone(1)
	game.deposit_at(Vector2(-1, 3))
	await create_timer(.6).timeout
	expect(game.soundscape.last_variant.has("land") and not game.soundscape.last_variant.has("water"), "land deposit uses stone impact, not splash")
	game.soundscape.reset()
	game.state.pickup_stone(2)
	game.deposit_at(point)
	game.soundscape.set_muted(true)
	game.soundscape.set_muted(false)
	await create_timer(.6).timeout
	expect(not game.soundscape.last_variant.has("water"), "unmuting never revives a pending pre-mute splash")
	game.state.pickup_stone(3)
	game.deposit_at(point)
	game.choose_world(100000)
	await game.wait_until_ready()
	await create_timer(.6).timeout
	expect(not game.soundscape.last_variant.has("water"), "new world cannot receive old journey's landing sounds")
	game.soundscape.reset()
	game.state.player = Vector2(2, 3)
	for trip in range(4):
		game.state.tick(14)
		for index in range(4):
			game.state.pickup_stone(index)
		game.deposit_at(point)
	expect(game.soundscape.last_variant.has("unlock"), "128 actual delivered stones trigger opening cue")
	game._advance_world(50)
	expect(game.soundscape.last_variant.has("relic") and game.soundscape.last_variant.has("mined"), "simulation events distinguish relic discovery and quarry completion")
	game.soundscape.reset()
	game.buy_upgrade("bag")
	expect(game.soundscape.last_variant.has("upgrade"), "successful upgrade uses its own cue")
	game.soundscape.reset()
	game._drain_messages()
	expect(game.soundscape.last_variant.is_empty(), "draining notification text cannot duplicate mining audio")
	await create_timer(1.2).timeout
	game.queue_free()
	# Let the audio mixer release stopped playback references before engine shutdown.
	await create_timer(.1).timeout
	print("AUDIO TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
