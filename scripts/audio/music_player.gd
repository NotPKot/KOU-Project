extends Node

const CALM_DIR := "res://assets/audio/music/chill/"
const COMBAT_DIR := "res://assets/audio/music/fight/"

@export var crossfade_duration: float = 2.0

var _channels: Array[AudioStreamPlayer] = []
var _active_channel: int = 0
var _tween: Tween
var _current_stream: AudioStream = null

var _calm_tracks: Array[AudioStream] = []
var _combat_tracks: Array[AudioStream] = []
var _muffled_effect: AudioEffectLowPassFilter

const MUSIC_BUS := "Music"
const MUFFLED_CUTOFF: float = 600.0
const FULL_CUTOFF: float = 22000.0


const CALM_TRACKS: Array[AudioStream] = [
]

const COMBAT_TRACKS: Array[AudioStream] = [
	preload("res://assets/audio/music/fight/hive troopers.ogg"),
]


func _ready() -> void:
	_setup_music_bus()

	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Channel" + str(i)
		p.volume_db = -80.0
		p.bus = MUSIC_BUS
		add_child(p)
		_channels.append(p)

	MusicManager.music_state_changed.connect(_on_music_state_changed)

	_calm_tracks = CALM_TRACKS.duplicate()
	_combat_tracks = COMBAT_TRACKS.duplicate()

	var scanned_calm := _load_tracks_from(CALM_DIR)
	var scanned_combat := _load_tracks_from(COMBAT_DIR)
	_calm_tracks.append_array(scanned_calm)
	_combat_tracks.append_array(scanned_combat)

	if not _calm_tracks.is_empty():
		var stream := _calm_tracks[randi() % _calm_tracks.size()]
		var player := _channels[0]
		player.stream = stream
		player.volume_db = -80.0
		player.play()
		var tween := create_tween()
		tween.tween_property(player, "volume_db", 0.0, crossfade_duration)
		_current_stream = stream


func _setup_music_bus() -> void:
	var bus_idx := AudioServer.get_bus_index(MUSIC_BUS)
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_idx, MUSIC_BUS)

	var effect := AudioEffectLowPassFilter.new()
	effect.cutoff_hz = FULL_CUTOFF
	effect.resonance = 0.3
	AudioServer.add_bus_effect(bus_idx, effect, 0)
	_muffled_effect = effect


func set_muffled(muffled: bool) -> void:
	if _muffled_effect == null:
		return
	var target := MUFFLED_CUTOFF if muffled else FULL_CUTOFF
	if is_inside_tree():
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_property(_muffled_effect, "cutoff_hz", target, 0.35)
	else:
		_muffled_effect.cutoff_hz = target


func _load_tracks_from(dir: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	var access := DirAccess.open(dir)
	if access == null:
		return out
	for entry in access.get_files():
		if not entry.ends_with(".ogg") and not entry.ends_with(".mp3") and not entry.ends_with(".wav"):
			continue
		var full := dir.path_join(entry)
		var s := load(full) as AudioStream
		if s == null:
			continue
		if s is AudioStreamOggVorbis or s is AudioStreamMP3:
			s.loop = true
		out.append(s)
	return out


func _on_music_state_changed(new_state: MusicManager.EMusicState, _old_state: MusicManager.EMusicState) -> void:
	var pool: Array[AudioStream]
	match new_state:
		MusicManager.EMusicState.CALM:
			pool = _calm_tracks
		MusicManager.EMusicState.COMBAT:
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
