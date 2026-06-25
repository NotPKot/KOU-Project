extends Node

enum EMusicState { CALM, TENSION, COMBAT, BOSS, SPECIAL_EVENT }

signal music_state_changed(new_state: EMusicState, old_state: EMusicState)

var current_state: EMusicState = EMusicState.CALM

@export var tension_to_combat_time: float = 3.0
@export var combat_exit_time: float = 5.0

var _state_enter_time: float = 0.0
var _active_sources: Dictionary = {}
var _escalation_timer: Timer
var _exit_timer: Timer

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
	_escalation_timer = Timer.new()
	_escalation_timer.name = "EscalationTimer"
	_escalation_timer.one_shot = true
	_escalation_timer.timeout.connect(_on_escalation_timeout)
	add_child(_escalation_timer)

	_exit_timer = Timer.new()
	_exit_timer.name = "CombatExitTimer"
	_exit_timer.one_shot = true
	_exit_timer.timeout.connect(_on_exit_timeout)
	add_child(_exit_timer)


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
		_maybe_start_escalation(state)
		if state == EMusicState.COMBAT and _exit_timer.is_stopped() == false:
			_exit_timer.stop()


func unregister_source(source: Node, state: EMusicState) -> void:
	if _active_sources.has(state):
		_active_sources[state].erase(source)
		if _active_sources[state].is_empty():
			_active_sources.erase(state)
			if state == EMusicState.TENSION:
				_escalation_timer.stop()
			if state == EMusicState.COMBAT or (state == EMusicState.TENSION and current_state == EMusicState.COMBAT and not _has_combat_sources()):
				_exit_timer.start(combat_exit_time)
				if current_state != EMusicState.TENSION:
					_change_state(EMusicState.TENSION)
			_evaluate_downgrade()


func _change_state(new_state: EMusicState) -> void:
	var old := current_state
	current_state = new_state
	_state_enter_time = Time.get_ticks_msec() / 1000.0
	music_state_changed.emit(new_state, old)

	if new_state == EMusicState.TENSION and _active_sources.has(EMusicState.TENSION) and not _active_sources[EMusicState.TENSION].is_empty():
		_escalation_timer.start(tension_to_combat_time)
	elif new_state == EMusicState.CALM:
		_escalation_timer.stop()


func _evaluate_downgrade() -> void:
	var highest := EMusicState.CALM
	for state in _active_sources.keys():
		var s := state as int
		if s > highest:
			highest = s

	if highest == EMusicState.CALM:
		if _exit_timer.is_stopped() == false:
			var has_tension_src := _active_sources.has(EMusicState.TENSION) and not _active_sources[EMusicState.TENSION].is_empty()
			if has_tension_src or _escalation_timer.is_stopped() == false:
				return
			if current_state != EMusicState.TENSION:
				_change_state(EMusicState.TENSION)
			return
		elif current_state == EMusicState.TENSION:
			_change_state(EMusicState.CALM)
			return

	var elapsed := (Time.get_ticks_msec() / 1000.0) - _state_enter_time
	if STATE_PRIORITY.get(current_state, 0) > STATE_PRIORITY.get(highest, 0) and elapsed >= MIN_STATE_DURATION.get(current_state, 0.0):
		_change_state(highest)


func _maybe_start_escalation(state: EMusicState) -> void:
	if state != EMusicState.TENSION:
		return
	if STATE_PRIORITY.get(current_state, 0) >= STATE_PRIORITY.get(EMusicState.COMBAT, 0):
		return
	if _escalation_timer.is_stopped():
		_escalation_timer.start(tension_to_combat_time)


func _on_escalation_timeout() -> void:
	if STATE_PRIORITY.get(current_state, 0) < STATE_PRIORITY.get(EMusicState.COMBAT, 0):
		_change_state(EMusicState.COMBAT)


func _on_exit_timeout() -> void:
	if _has_combat_sources():
		return
	var has_tension := _active_sources.has(EMusicState.TENSION) and not _active_sources[EMusicState.TENSION].is_empty()
	if has_tension:
		return
	_change_state(EMusicState.CALM)


func _has_combat_sources() -> bool:
	return _active_sources.has(EMusicState.COMBAT) and not _active_sources[EMusicState.COMBAT].is_empty()
