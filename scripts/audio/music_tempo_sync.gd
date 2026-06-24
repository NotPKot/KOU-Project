extends Node

const BpmDatabase = preload("res://scripts/audio/bpm_database.gd")

@export var audio_player_path: NodePath
@export var target_path: NodePath
@export var bpm_cache_path: String = "res://data/audio_bpm_cache.json"
@export var fallback_bpm: float = 120.0
@export var apply_on_ready: bool = true

var _database = BpmDatabase.new()


func _ready() -> void:
	_database.load_cache(bpm_cache_path)
	if apply_on_ready:
		apply_current_song_bpm()


func apply_current_song_bpm() -> void:
	var player: Node = get_node_or_null(audio_player_path)
	var target: Node = get_node_or_null(target_path)
	if player == null or target == null:
		return

	var stream := player.get("stream") as Resource
	if stream == null:
		return

	var resource_path: String = stream.resource_path
	var bpm: float = _database.get_bpm(resource_path, fallback_bpm)
	if target.has_method("set_music_bpm"):
		target.set_music_bpm(bpm)
