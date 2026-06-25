class_name Dash
extends Node

signal dashed
signal dash_ended

@export var dash_speed: float = 25.0
@export var dash_duration: float = 0.2
@export var cooldown: float = 2.5

var is_dashing: bool = false
var _player: CharacterBody3D = null
var _timer: float = 0.0
var _cool_timer: float = 0.0
var _direction: Vector3 = Vector3.ZERO


func setup(player: CharacterBody3D) -> void:
	_player = player


func fire(camera_forward: Vector3) -> void:
	if _cool_timer > 0.0 or is_dashing or _player == null:
		return

	_direction = camera_forward.normalized()
	if _direction.length_squared() < 0.001:
		_direction = _player.global_transform.basis.z.normalized()

	is_dashing = true
	_timer = dash_duration
	dashed.emit()


func _process(delta: float) -> void:
	_cool_timer = maxf(_cool_timer - delta, 0.0)


func physics_tick(delta: float) -> bool:
	if not is_dashing or _player == null:
		return false

	_timer -= delta
	if _timer <= 0.0:
		is_dashing = false
		_player.velocity = Vector3.ZERO
		dash_ended.emit()
		_cool_timer = cooldown
		return false

	_player.velocity = _direction * dash_speed
	_player.move_and_slide()
	return true
