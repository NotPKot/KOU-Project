extends Node

@export var crossfade_duration: float = 2.0
@export var fade_in_duration: float = 3.0

var _channels: Array[AudioStreamPlayer] = []
var _active_channel: int = 0
var _tween: Tween
var _current_stream: AudioStream = null

var _calm_tracks: Array[AudioStream] = []
var _tension_tracks: Array[AudioStream] = []
var _combat_tracks: Array[AudioStream] = []


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Channel" + str(i)
		p.volume_db = -80.0
		add_child(p)
		_channels.append(p)

	MusicManager.music_state_changed.connect(_on_music_state_changed)

	_load_all_tracks()
	if not _calm_tracks.is_empty():
		_start_calm_fade_in()


func _load_all_tracks() -> void:
	_calm_tracks = _load_tracks_from("res://placeholder/audio/music/chill/")
	_tension_tracks = _load_tracks_from("res://placeholder/audio/music/tension/")
	_combat_tracks = _load_tracks_from("res://placeholder/audio/music/fight/")


static func _load_tracks_from(dir: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for entry in _get_ogg_files(dir):
		var s := load(dir.path_join(entry)) as AudioStream
		if s != null:
			if s is AudioStreamOggVorbis:
				s.loop = true
			out.append(s)
	return out


static func _get_ogg_files(dir: String) -> PackedStringArray:
	var known: Dictionary = {
		"res://placeholder/audio/music/chill/": [
			"DELTARUNE-Paradise_-Paradise-N64-Zelda-Majora_s-Mask-Style-Cover.ogg",
		],
		"res://placeholder/audio/music/tension/": [
			"YTMP3GG_YouTube_Inscryption-OST-11-The-Temple-of-Beasts_Media_OlYqw4Kkvj8_006_128k.ogg",
			"YTMP3GG_YouTube_Brutal-Orchestra-OST-The-Far-Shore-Area-_Media_20DCCVX-PGg_009_128k.ogg",
		],
		"res://placeholder/audio/music/fight/": [
			"Rift-of-the-NecroDancer-OST-Matriarch-by-Jules-Conroy_1_.ogg",
			"froghorn.exe.ogg",
			"running-through-the-garden-without-a-car_Media_K9Pk68tPoW8_009_128k.ogg",
		],
	}
	return known.get(dir, [])


func _start_calm_fade_in() -> void:
	var stream := _calm_tracks[randi() % _calm_tracks.size()]
	var player := _channels[0]
	player.stream = stream
	player.volume_db = -80.0
	player.play()

	_tween = create_tween()
	_tween.tween_property(player, "volume_db", 0.0, fade_in_duration)
	_current_stream = stream
	_active_channel = 0


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

	var stream := pool[randi() % pool.size()]
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
