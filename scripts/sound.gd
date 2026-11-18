extends Node

const AUDIO := "res://assets/audio/"
const EFFECT_FILES := {
	"gather": ["drop_002.ogg", "impactWood_light_000.ogg"],
	"craft": ["confirmation_002.ogg"],
	"hit": ["impactPunch_medium_000.ogg", "impactPunch_medium_002.ogg"],
	"mine": ["impactMining_000.ogg", "impactMining_002.ogg"],
	"alchemy": ["glass_003.ogg", "confirmation_002.ogg"],
	"select": ["click_002.ogg"],
	"error": ["error_004.ogg"]
}
const STEP_FILES := [
	"footstep_grass_000.ogg", "footstep_grass_001.ogg",
	"footstep_grass_002.ogg", "footstep_grass_003.ogg"
]

var ambient: AudioStreamPlayer
var effects: AudioStreamPlayer
var steps: AudioStreamPlayer
var _night_ambient: AudioStreamPlayer
var _effect_pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _step_timer: float = 0.0
var _effect_cursor: int = 0
var _last_step: int = -1
var _night: bool = false


func _ready() -> void:
	ambient = _player(-21.0)
	ambient.name = "DayForestBirds"
	ambient.stream = _loop("day_forest_birds.mp3")
	ambient.play()
	_night_ambient = _player(-60.0)
	_night_ambient.name = "NightCrickets"
	_night_ambient.stream = _loop("night_crickets.mp3")
	steps = _player(-20.0)
	steps.name = "GrassFootsteps"
	for i in 4:
		var player: AudioStreamPlayer = _player(-16.0)
		player.name = "ActionSound_%d" % i
		_effect_pool.append(player)
	effects = _effect_pool[0]
	for files: Array in EFFECT_FILES.values():
		for file: String in files:
			_stream(file)
	for file: String in STEP_FILES:
		_stream(file)
	if _night:
		set_night(true)


func _player(volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = volume
	add_child(player)
	return player


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		_streams[file] = load(AUDIO + file) as AudioStream
	return _streams[file]


func _loop(file: String) -> AudioStreamMP3:
	var stream: AudioStreamMP3 = (load(AUDIO + file) as AudioStreamMP3).duplicate()
	stream.loop = true
	stream.loop_offset = 0.0
	return stream


func set_night(value: bool) -> void:
	_night = value
	if not is_instance_valid(ambient):
		return
	var target: AudioStreamPlayer = _night_ambient if _night else ambient
	if not target.playing:
		target.play()


func _process(delta: float) -> void:
	# Crossfade the field recordings without restarting them on each clock update.
	var day_target: float = -60.0 if _night else -21.0
	var night_target: float = -23.0 if _night else -60.0
	ambient.volume_db = move_toward(ambient.volume_db, day_target, delta * 10.0)
	_night_ambient.volume_db = move_toward(_night_ambient.volume_db, night_target, delta * 10.0)
	if _night and ambient.volume_db <= -59.9 and ambient.playing:
		ambient.stop()
	if not _night and _night_ambient.volume_db <= -59.9 and _night_ambient.playing:
		_night_ambient.stop()


func effect(kind: String) -> void:
	if _effect_pool.is_empty():
		return
	var files: Array = EFFECT_FILES.get(kind, EFFECT_FILES["select"])
	var file: String = files[randi_range(0, files.size() - 1)]
	var player: AudioStreamPlayer = _effect_pool[_effect_cursor]
	_effect_cursor = (_effect_cursor + 1) % _effect_pool.size()
	player.stop()
	player.stream = _stream(file)
	player.volume_db = -18.0 if kind in ["gather", "select"] else -14.0
	player.pitch_scale = randf_range(0.94, 1.06)
	player.play()
	effects = player


func movement(delta: float, moving: bool) -> void:
	if not is_instance_valid(steps):
		return
	if not moving:
		_step_timer = minf(_step_timer, 0.12)
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = 0.37
	var choice: int = randi_range(0, STEP_FILES.size() - 2)
	if choice >= _last_step:
		choice += 1
	_last_step = choice
	steps.stream = _stream(STEP_FILES[choice])
	steps.pitch_scale = randf_range(0.92, 1.08)
	steps.play()


func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			var player: AudioStreamPlayer = child as AudioStreamPlayer
			player.stop()
			player.stream = null
	_streams.clear()
