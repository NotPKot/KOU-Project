class_name Dash
extends Node

signal dashed
signal dash_ended

@export var dash_speed: float = 33.25
@export var dash_duration: float = 0.2
@export var cooldown: float = 2.5

var is_dashing: bool = false
var _player: CharacterBody3D = null
var _timer: float = 0.0
var _cool_timer: float = 0.0


func setup(player: CharacterBody3D) -> void:
	_player = player


func fire(camera_forward: Vector3) -> void:
	if _cool_timer > 0.0 or is_dashing or _player == null:
		return

	var dir := camera_forward
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = -_player.global_transform.basis.z
		dir.y = 0.0
	dir = dir.normalized()

	_player.velocity = dir * dash_speed
	_player.velocity.y = 0.0

	is_dashing = true
	_timer = dash_duration
	dashed.emit()


func _process(delta: float) -> void:
	_cool_timer = maxf(_cool_timer - delta, 0.0)
	if is_dashing:
		_timer -= delta
		if _timer <= 0.0:
			is_dashing = false
			_cool_timer = cooldown
			dash_ended.emit()
