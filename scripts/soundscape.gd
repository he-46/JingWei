extends Node

# Separate pools keep a burst of stone impacts from stealing a discovery's tail.
const ACTION_VOICES := 6
const ACCENT_VOICES := 2
const CUES := {
	"gather": {"count": 3, "gain": -17.0, "gap": 0.09},
	"throw": {"count": 3, "gain": -19.0, "gap": 0.12},
	"water": {"count": 3, "gain": -16.0, "gap": 0.12},
	"land": {"count": 3, "gain": -17.0, "gap": 0.12},
	"fill": {"gain": -19.0, "gap": 0.6, "priority": 1},
	"upgrade": {"gain": -16.0, "gap": 0.15, "priority": 2},
	"unlock": {"gain": -17.0, "gap": 1.0, "priority": 2},
	"mined": {"gain": -19.0, "gap": 0.8},
	"relic": {"gain": -15.0, "gap": 1.5, "priority": 3},
	"complete": {"gain": -15.0, "gap": 4.0, "priority": 4},
}

var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var ambience: AudioStreamPlayer
var muted := false
var epoch := 0
var clock := 0.0
var next_allowed: Dictionary = {}
var last_variant: Dictionary = {}
var rng := RandomNumberGenerator.new()
var ambience_target := -60.0
var volume_level := 1.0
const BUS := "Jingwei"

func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
	set_volume(volume_level)
	rng.randomize()
	for cue in CUES:
		var bank: Array[AudioStream] = []
		var count := int(CUES[cue].get("count", 1))
		for index in range(count):
			var filename: String = "%s_%d" % [cue, index] if count > 1 else cue
			bank.append(load("res://assets/audio/%s.wav" % filename))
		streams[cue] = bank
	for index in range(ACTION_VOICES + ACCENT_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS
		add_child(voice)
		voices.append(voice)
	ambience = AudioStreamPlayer.new()
	ambience.bus = BUS
	var surf: AudioStreamWAV = load("res://assets/audio/surf.wav").duplicate()
	surf.loop_mode = AudioStreamWAV.LOOP_FORWARD
	surf.loop_begin = 0
	surf.loop_end = int(surf.get_length() * surf.mix_rate)
	ambience.stream = surf
	ambience.volume_db = -60
	add_child(ambience)

func _process(delta: float) -> void:
	clock += delta
	if muted or volume_level <= 0:
		return
	ambience.volume_db = move_toward(ambience.volume_db, ambience_target, delta * 12)
	if ambience_target > -60 and not ambience.playing:
		ambience.play()
	elif ambience_target <= -60 and ambience.volume_db <= -60:
		ambience.stop()

func set_context(player_x: float, paused: bool, selecting: bool) -> void:
	# Surf is strongest at the shoreline, softer inland and in the open sea.
	var inland := clampf(-player_x / 35.0, 0, 1)
	var offshore := clampf(player_x / 100.0, 0, 1)
	ambience_target = -60 if selecting else -27.0 - 13.0 * inland - 5.0 * offshore - (10.0 if paused else 0.0)

func reset() -> void:
	epoch += 1
	for voice in voices:
		voice.stop()
	if ambience != null:
		ambience.stop()
		ambience.volume_db = -60
	next_allowed.clear()
	last_variant.clear()

func _exit_tree() -> void:
	reset()

func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	reset() # Also invalidates delayed landing sounds from before the mute/restart.

func set_volume(value: float) -> void:
	var level := clampf(value, 0, 1)
	if level <= 0 and volume_level > 0:
		reset()
	volume_level = level
	var index := AudioServer.get_bus_index(BUS)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, .001)))
		AudioServer.set_bus_mute(index, level <= 0)

func play(cue: String, strength: float = 1.0) -> bool:
	if muted or volume_level <= 0 or not CUES.has(cue) or clock < float(next_allowed.get(cue, -1.0)):
		return false
	var config: Dictionary = CUES[cue]
	var priority := int(config.get("priority", 0))
	var first := ACTION_VOICES if priority > 0 else 0
	var limit := voices.size() if priority > 0 else ACTION_VOICES
	var chosen: AudioStreamPlayer = null
	for index in range(first, limit):
		var voice := voices[index]
		if not voice.playing:
			chosen = voice
			break
		if int(voice.get_meta("priority", 0)) > priority:
			continue
		if chosen == null or float(voice.get_meta("started", 0.0)) < float(chosen.get_meta("started", 0.0)):
			chosen = voice
	if chosen == null:
		return false
	var bank: Array = streams[cue]
	var variant := rng.randi_range(0, bank.size() - 1)
	if bank.size() > 1 and variant == int(last_variant.get(cue, -1)):
		variant = (variant + rng.randi_range(1, bank.size() - 1)) % bank.size()
	last_variant[cue] = variant
	next_allowed[cue] = clock + float(config["gap"])
	chosen.stop()
	chosen.stream = bank[variant]
	chosen.pitch_scale = rng.randf_range(0.96, 1.04) if bank.size() > 1 else 1.0
	chosen.volume_db = float(config["gain"]) + linear_to_db(clampf(strength, 0.15, 1.0))
	chosen.set_meta("priority", priority)
	chosen.set_meta("started", clock)
	chosen.play()
	return true
