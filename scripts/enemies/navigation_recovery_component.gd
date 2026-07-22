extends Node

@export var nav_agent_path: NodePath
@export var player_path: NodePath

@export var target_update_interval: float = 0.35
@export var max_short_hop_duration: float = 1.2
@export var max_short_hop_distance: float = 6.0

@export var stuck_check_interval: float = 0.5
@export var stuck_distance_threshold: float = 0.15
@export var stuck_time_to_trigger: float = 1.2
@export var good_position_sample_interval: float = 0.4
@export var recovery_speed: float = 3.5
@export var recovery_arrival_threshold: float = 0.3
@export var recovery_timeout: float = 4.0

signal recovery_started
signal recovery_finished(success: bool)

enum State { NORMAL, RECOVERING }

var _nav_agent: NavigationAgent3D
var _player: Node3D
var _body: CharacterBody3D

var _state: State = State.NORMAL
var _clock: float = 0.0
var _target_update_accum: float = 0.0
var _last_known_grounded_player_pos: Vector3
var _player_was_grounded: bool = true
var _flight_start_time: float = 0.0
var _flight_start_pos: Vector3

var _stuck_check_accum: float = 0.0
var _stuck_timer_accum: float = 0.0
var _last_check_pos: Vector3
var _good_pos_accum: float = 0.0
var _last_good_position: Vector3
var _recovery_target: Vector3
var _recovery_elapsed: float = 0.0


func _ready() -> void:
	_nav_agent = get_node(nav_agent_path) as NavigationAgent3D
	_player = _find_player_by_path_or_group()
	_body = get_parent() as CharacterBody3D
	_last_known_grounded_player_pos = _get_player_pos_or_zero()
	_last_check_pos = _body.global_position
	_last_good_position = _body.global_position


func set_player(p: Node3D) -> void:
	_player = p
	_last_known_grounded_player_pos = _player.global_position


func _find_player_by_path_or_group() -> Node3D:
	if player_path:
		return get_node(player_path) as Node3D
	return get_tree().get_first_node_in_group("player") as Node3D


func _get_player_pos_or_zero() -> Vector3:
	return _player.global_position if _player != null else Vector3.ZERO


func _process(delta: float) -> void:
	_clock += delta
	if _state == State.NORMAL:
		_process_flight_tracking(delta)
		_track_good_position(delta)
		_process_stuck_watchdog(delta)


func process_recovery(delta: float) -> void:
	if _state != State.RECOVERING:
		return
	_recovery_elapsed += delta
	var to_target: Vector3 = _recovery_target - _body.global_position
	to_target.y = 0.0
	var arrived: bool = to_target.length() <= recovery_arrival_threshold
	var timed_out: bool = _recovery_elapsed >= recovery_timeout
	if arrived or timed_out:
		_finish_recovery(arrived)
		return
	var dir: Vector3 = to_target.normalized()
	_body.velocity.x = dir.x * recovery_speed
	_body.velocity.z = dir.z * recovery_speed


func is_recovering() -> bool:
	return _state == State.RECOVERING


func get_effective_target() -> Vector3:
	if _player == null:
		return _body.global_position
	if _is_player_grounded():
		return _player.global_position
	var short_hop := _is_short_hop()
	if short_hop:
		return _project_to_navmesh(_player.global_position)
	return _player.global_position


func is_in_short_hop() -> bool:
	if _player == null or _is_player_grounded():
		return false
	return _is_short_hop()


func _is_short_hop() -> bool:
	var flight_elapsed: float = _clock - _flight_start_time
	var flight_distance: float = _flight_start_pos.distance_to(_player.global_position)
	return flight_elapsed <= max_short_hop_duration and flight_distance <= max_short_hop_distance


func _project_to_navmesh(pos: Vector3) -> Vector3:
	var map := _nav_agent.get_navigation_map()
	if map.is_valid():
		return NavigationServer3D.map_get_closest_point(map, pos)
	return pos


func _process_flight_tracking(delta: float) -> void:
	if _player == null:
		return
	var grounded: bool = _is_player_grounded()

	if grounded and not _player_was_grounded:
		_player_was_grounded = true
		_last_known_grounded_player_pos = _player.global_position
		_target_update_accum = 0.0
		return

	elif not grounded and _player_was_grounded:
		_player_was_grounded = false
		_flight_start_time = _clock
		_flight_start_pos = _player.global_position

	_target_update_accum += delta
	if _target_update_accum < target_update_interval:
		return
	_target_update_accum = 0.0

	if grounded:
		_last_known_grounded_player_pos = _player.global_position


func _is_player_grounded() -> bool:
	if _player.has_method("is_on_floor"):
		return _player.is_on_floor()
	return true


func _track_good_position(delta: float) -> void:
	_good_pos_accum += delta
	if _good_pos_accum < good_position_sample_interval:
		return
	_good_pos_accum = 0.0
	if _body.global_position.distance_to(_last_good_position) > stuck_distance_threshold:
		_last_good_position = _body.global_position


func _process_stuck_watchdog(delta: float) -> void:
	_stuck_check_accum += delta
	if _stuck_check_accum < stuck_check_interval:
		return
	var moved: float = _body.global_position.distance_to(_last_check_pos)
	var has_active_target: bool = not _nav_agent.is_navigation_finished()
	if has_active_target and moved < stuck_distance_threshold:
		_stuck_timer_accum += _stuck_check_accum
	else:
		_stuck_timer_accum = 0.0
	_last_check_pos = _body.global_position
	_stuck_check_accum = 0.0
	if _stuck_timer_accum >= stuck_time_to_trigger:
		_start_recovery()


func _start_recovery() -> void:
	_stuck_timer_accum = 0.0
	_state = State.RECOVERING
	_recovery_elapsed = 0.0
	_recovery_target = _last_good_position
	emit_signal("recovery_started")


func _finish_recovery(success: bool) -> void:
	_state = State.NORMAL
	_target_update_accum = target_update_interval
	_stuck_timer_accum = 0.0
	_last_check_pos = _body.global_position
	_last_good_position = _body.global_position
	emit_signal("recovery_finished", success)
