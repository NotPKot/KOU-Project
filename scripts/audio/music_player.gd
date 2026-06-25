extends Node

@export var crossfade_duration: float = 2.0

var _channels: Array[AudioStreamPlayer] = []
var _active_channel: int = 0
var _tween: Tween
var _current_stream: AudioStream = null

var _calm_tracks: Array[AudioStream] = []
var _tension_tracks: Array[AudioStream] = []
var _combat_tracks: Array[AudioStream] = []

const CALM_DIR := "res://placeholder/audio/music/chill/"
const TENSION_DIR := "res://placeholder/audio/music/tension/"
const COMBAT_DIR := "res://placeholder/audio/music/fight/"


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Channel" + str(i)
		p.volume_db = -80.0
		add_child(p)
		_channels.append(p)

	MusicManager.music_state_changed.connect(_on_music_state_changed)
	_load_tracks()
	_play_state(MusicManager.EMusicState.CALM)


func _load_tracks() -> void:
	_calm_tracks = _load_ogg_dir(CALM_DIR)
	_tension_tracks = _load_ogg_dir(TENSION_DIR)
	_combat_tracks = _load_ogg_dir(COMBAT_DIR)


static func _load_ogg_dir(dir_path: String) -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".ogg") and not file.ends_with(".ogg.import"):
			var stream := load(dir_path.path_join(file)) as AudioStream
			if stream != null:
				if stream is AudioStreamOggVorbis:
					stream.loop = true
				result.append(stream)
		file = dir.get_next()
	dir.list_dir_end()
	return result


func _on_music_state_changed(new_state: MusicManager.EMusicState, _old_state: MusicManager.EMusicState) -> void:
	_play_state(new_state)


func _play_state(state: MusicManager.EMusicState) -> void:
	var pool: Array[AudioStream]
	match state:
		MusicManager.EMusicState.CALM:
			pool = _calm_tracks
		MusicManager.EMusicState.TENSION:
			pool = _tension_tracks
		MusicManager.EMusicState.COMBAT, MusicManager.EMusicState.BOSS, MusicManager.EMusicState.SPECIAL_EVENT:
			pool = _combat_tracks

	if pool.is_empty():
		return

	var stream: AudioStream = pool[randi() % pool.size()]
	if stream == _current_stream:
		return

	_crossfade(stream)


func _crossfade(new_stream: AudioStream) -> void:
	var next := (_active_channel + 1) % 2
	var next_player := _channels[next]
	var active_player := _channels[_active_channel]

	if _tween != null and _tween.is_valid():
		_tween.kill()

	next_player.stream = new_stream
	next_player.volume_db = -80.0
	next_player.play()

	_tween = create_tween().set_parallel()
	_tween.tween_property(active_player, "volume_db", -80.0, crossfade_duration)
	_tween.tween_property(next_player, "volume_db", 0.0, crossfade_duration)

	_active_channel = next
	_current_stream = new_stream
