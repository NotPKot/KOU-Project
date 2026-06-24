extends Node

signal save_started(reason: StringName)
signal save_finished(reason: StringName, success: bool)

const SAVE_PATH := "user://save_slot_01.json"
const TEMP_SAVE_PATH := "user://save_slot_01.tmp"
const BACKUP_SAVE_PATH := "user://save_slot_01.bak"
const SAVE_VERSION := 1
const EXPLORATION_AUTOSAVE_SECONDS := 15.0 * 60.0
const CRASH_SAFETY_AUTOSAVE_SECONDS := 120.0

var _seconds_since_combat: float = 0.0
var _seconds_since_safety_save: float = 0.0
var _combat_active: bool = false
var _is_saving: bool = false
var _last_save_unix_time: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_seconds_since_safety_save += delta
	if _seconds_since_safety_save >= CRASH_SAFETY_AUTOSAVE_SECONDS:
		_seconds_since_safety_save = 0.0
		save_game(&"crash_safety_timer")

	if _combat_active:
		return

	_seconds_since_combat += delta
	if _seconds_since_combat >= EXPLORATION_AUTOSAVE_SECONDS:
		_seconds_since_combat = 0.0
		save_game(&"exploration_timer")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("manual_save"):
		save_game(&"manual_hotkey")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game(&"window_close")
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		save_game(&"app_paused")


func save_game(reason: StringName = &"manual") -> bool:
	if _is_saving:
		return false

	_is_saving = true
	save_started.emit(reason)

	var payload := _build_save_payload(reason)
	var success := _write_save_payload(payload)
	if success:
		_last_save_unix_time = Time.get_unix_time_from_system()
		_seconds_since_safety_save = 0.0

	_is_saving = false
	save_finished.emit(reason, success)
	return success


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	_apply_save_payload(parsed)
	return true


func notify_combat_started() -> void:
	_combat_active = true


func notify_combat_finished() -> void:
	_combat_active = false
	_seconds_since_combat = 0.0
	save_game(&"combat_finished")


func notify_exploration_progress() -> void:
	if not _combat_active:
		_seconds_since_combat = 0.0


func get_last_save_unix_time() -> int:
	return _last_save_unix_time


func _build_save_payload(reason: StringName) -> Dictionary:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"reason": String(reason),
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "",
		"nodes": {},
	}

	for node in get_tree().get_nodes_in_group("saveable"):
		if node.has_method("get_save_data"):
			payload["nodes"][str(node.get_path())] = node.get_save_data()

	return payload


func _apply_save_payload(payload: Dictionary) -> void:
	var nodes: Dictionary = payload.get("nodes", {})
	for node_path in nodes.keys():
		var node := get_node_or_null(NodePath(str(node_path)))
		if node != null and node.has_method("apply_save_data"):
			node.apply_save_data(nodes[node_path])


func _write_save_payload(payload: Dictionary) -> bool:
	var json := JSON.stringify(payload, "\t")
	var temp_file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if temp_file == null:
		push_warning("Unable to write temp save: " + TEMP_SAVE_PATH)
		return false

	temp_file.store_string(json)
	temp_file.flush()
	temp_file.close()

	var save_path := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_path := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_path := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)

	if FileAccess.file_exists(BACKUP_SAVE_PATH):
		DirAccess.remove_absolute(backup_path)

	if FileAccess.file_exists(SAVE_PATH):
		var backup_error := DirAccess.rename_absolute(save_path, backup_path)
		if backup_error != OK:
			push_warning("Unable to create save backup.")
			return false

	var rename_error := DirAccess.rename_absolute(
		temp_path,
		save_path
	)
	if rename_error != OK:
		if FileAccess.file_exists(BACKUP_SAVE_PATH):
			DirAccess.rename_absolute(backup_path, save_path)
		push_warning("Unable to finalize save file.")
		return false

	if FileAccess.file_exists(BACKUP_SAVE_PATH):
		DirAccess.remove_absolute(backup_path)

	return true
