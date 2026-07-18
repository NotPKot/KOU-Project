extends Node

enum EMusicState { CALM, COMBAT }

signal music_state_changed(new_state: EMusicState, old_state: EMusicState)

const STATE_NAMES := ["CALM", "COMBAT"]

var current_state: EMusicState = EMusicState.CALM


func set_state(new_state: EMusicState) -> void:
	if new_state == current_state:
		return
	var old_state := current_state
	current_state = new_state
	music_state_changed.emit(new_state, old_state)


func get_state_name() -> String:
	return STATE_NAMES[current_state]
