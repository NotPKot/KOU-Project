extends RefCounted

const DEFAULT_CACHE_PATH = "res://data/audio_bpm_cache.json"

var _entries: Dictionary = {}


func load_cache(path: String = DEFAULT_CACHE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("BPM cache not found: " + path)
		return false

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Unable to open BPM cache: " + path)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid BPM cache JSON: " + path)
		return false

	_entries = parsed
	return true


func get_bpm(resource_path: String, fallback_bpm: float = 120.0) -> float:
	if _entries.has(resource_path):
		return float(_entries[resource_path].get("bpm", fallback_bpm))

	return fallback_bpm


func get_beat_period(resource_path: String, fallback_period: float = 0.5) -> float:
	if _entries.has(resource_path):
		return float(_entries[resource_path].get("beat_period", fallback_period))

	return fallback_period
