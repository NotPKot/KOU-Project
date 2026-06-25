extends Node

enum EMusicState { CALM, TENSION, COMBAT, BOSS, SPECIAL_EVENT }

signal music_state_changed(new_state: EMusicState, old_state: EMusicState)

var current_state: EMusicState = EMusicState.CALM

var _state_enter_time: float = 0.0
var _active_sources: Dictionary = {}

const STATE_PRIORITY := {
	EMusicState.CALM: 0,
	EMusicState.TENSION: 1,
	EMusicState.COMBAT: 2,
	EMusicState.BOSS: 3,
	EMusicState.SPECIAL_EVENT: 4,
}

const MIN_STATE_DURATION := {
	EMusicState.CALM: 0.0,
	EMusicState.TENSION: 2.0,
	EMusicState.COMBAT: 5.0,
	EMusicState.BOSS: 8.0,
	EMusicState.SPECIAL_EVENT: 3.0,
}


func _ready() -> void:
	_state_enter_time = Time.get_ticks_msec() / 1000.0


func request_state(state: EMusicState, _source: Node = null, _priority: int = 0) -> void:
	var new_prio := STATE_PRIORITY.get(state, 0)
	var current_prio := STATE_PRIORITY.get(current_state, 0)

	if new_prio > current_prio:
		_change_state(state)
	elif new_prio == current_prio:
		_state_enter_time = Time.get_ticks_msec() / 1000.0
	else:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - _state_enter_time
		if elapsed >= MIN_STATE_DURATION.get(current_state, 0.0):
			_change_state(state)


func register_source(source: Node, state: EMusicState) -> void:
	if not _active_sources.has(state):
		_active_sources[state] = []
	if source not in _active_sources[state]:
		_active_sources[state].append(source)
		request_state(state)


func unregister_source(source: Node, state: EMusicState) -> void:
	if _active_sources.has(state):
		_active_sources[state].erase(source)
		if _active_sources[state].is_empty():
			_active_sources.erase(state)
			_evaluate_downgrade()


func _change_state(new_state: EMusicState) -> void:
	var old := current_state
	current_state = new_state
	_state_enter_time = Time.get_ticks_msec() / 1000.0
	music_state_changed.emit(new_state, old)


func _evaluate_downgrade() -> void:
	var highest := EMusicState.CALM
	for state in _active_sources.keys():
		var s := state as int
		if s > highest:
			highest = s

	var elapsed := (Time.get_ticks_msec() / 1000.0) - _state_enter_time
	if STATE_PRIORITY.get(current_state, 0) > STATE_PRIORITY.get(highest, 0) and elapsed >= MIN_STATE_DURATION.get(current_state, 0.0):
		_change_state(highest)
