extends CharacterBody3D

const BROKEN_STOPWATCH_SCENE := preload("res://scenes/weapons/BrokenStopwatch.tscn")

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var ground_acceleration: float = 18.0
@export var ground_deceleration: float = 22.0
@export var air_acceleration: float = 7.0
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0
@export var temporal_impulse_velocity: float = 12.0
@export var temporal_impulse_air_control_time: float = 2.8
@export var temporal_impulse_air_acceleration: float = 14.0
@export var temporal_impulse_gravity_scale: float = 0.45

@export_group("Jump")
@export var jump_velocity: float = 8.5

@export_group("Camera")
@export_range(0.0005, 0.01, 0.0005) var mouse_sensitivity: float = 0.003
@export var min_pitch_degrees: float = -55.0
@export var max_pitch_degrees: float = 18.0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _visual: Node3D = $Visual

var mouse_weapon_id: StringName = &""
var _camera_yaw: float = 0.0
var _camera_pitch: float = deg_to_rad(-14.0)
var _input_locked: bool = false
var _aim_locked: bool = false
var _mouse_weapon: Node = null
var _air_control_timer: float = 0.0
var _music_bpm: float = 0.0
var _can_jump: bool = false


func _ready() -> void:
	add_to_group("player")
	add_to_group("saveable")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_apply_camera_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if _input_locked:
		return

	if event.is_action_pressed("ui_cancel"):
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)
		return

	if _aim_locked:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw -= event.relative.x * mouse_sensitivity
		_camera_pitch = clamp(
			_camera_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
		_apply_camera_rotation()


func _physics_process(delta: float) -> void:
	if _input_locked:
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)

		if is_on_floor() and velocity.y < 0.0:
			velocity.y = -0.1
		else:
			velocity.y = max(velocity.y - gravity * delta, -terminal_velocity)

		move_and_slide()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_direction := _get_camera_relative_direction(input_vector)
	var target_xz := move_direction * walk_speed
	if _air_control_timer > 0.0:
		_air_control_timer = max(_air_control_timer - delta, 0.0)

	var current_air_acceleration := temporal_impulse_air_acceleration if _air_control_timer > 0.0 else air_acceleration
	var acceleration := ground_acceleration if is_on_floor() else current_air_acceleration

	if input_vector.is_zero_approx() and is_on_floor():
		acceleration = ground_deceleration

	velocity.x = move_toward(velocity.x, target_xz.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_xz.z, acceleration * delta)

	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.1
	else:
		var gravity_scale := temporal_impulse_gravity_scale if _air_control_timer > 0.0 and velocity.y < 0.0 else 1.0
		velocity.y = max(velocity.y - gravity * gravity_scale * delta, -terminal_velocity)

	if _can_jump and is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	move_and_slide()
	_face_motion_direction(delta)


func _apply_camera_rotation() -> void:
	_camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)


func _get_camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector.is_zero_approx():
		return Vector3.ZERO

	var basis := _camera_pivot.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	return (right * input_vector.x + forward * -input_vector.y).normalized()


func _face_motion_direction(delta: float) -> void:
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if flat_velocity.length_squared() < 0.01:
		return

	var target_yaw := atan2(-flat_velocity.x, -flat_velocity.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, min(14.0 * delta, 1.0))


func set_input_locked(is_locked: bool) -> void:
	_input_locked = is_locked


func is_input_locked() -> bool:
	return _input_locked


func set_aim_locked(is_locked: bool) -> void:
	_aim_locked = is_locked


func set_mouse_weapon(weapon_id: StringName) -> void:
	mouse_weapon_id = weapon_id
	_equip_mouse_weapon(weapon_id)
	print("Mouse weapon selected: ", mouse_weapon_id)


func set_music_bpm(bpm: float) -> void:
	_music_bpm = bpm
	if _mouse_weapon != null and _mouse_weapon.has_method("set_music_bpm"):
		_mouse_weapon.set_music_bpm(bpm)


func enable_jump() -> void:
	_can_jump = true


func apply_temporal_impulse() -> void:
	velocity.y = max(velocity.y, temporal_impulse_velocity)
	_air_control_timer = temporal_impulse_air_control_time


func get_save_data() -> Dictionary:
	return {
		"global_position": _vector3_to_array(global_position),
		"camera_yaw": _camera_yaw,
		"camera_pitch": _camera_pitch,
		"mouse_weapon_id": String(mouse_weapon_id),
		"music_bpm": _music_bpm,
	}


func apply_save_data(data: Dictionary) -> void:
	if data.has("global_position"):
		global_position = _array_to_vector3(data["global_position"], global_position)

	_camera_yaw = float(data.get("camera_yaw", _camera_yaw))
	_camera_pitch = float(data.get("camera_pitch", _camera_pitch))
	_apply_camera_rotation()

	var saved_weapon := StringName(str(data.get("mouse_weapon_id", "")))
	if saved_weapon != &"":
		set_mouse_weapon(saved_weapon)

	_music_bpm = float(data.get("music_bpm", _music_bpm))
	if _music_bpm > 0.0 and _mouse_weapon != null and _mouse_weapon.has_method("set_music_bpm"):
		_mouse_weapon.set_music_bpm(_music_bpm)


func _equip_mouse_weapon(weapon_id: StringName) -> void:
	if _mouse_weapon != null:
		if _mouse_weapon.has_method("unequip"):
			_mouse_weapon.unequip()
		_mouse_weapon.queue_free()
		_mouse_weapon = null

	match weapon_id:
		&"broken_stopwatch":
			_mouse_weapon = BROKEN_STOPWATCH_SCENE.instantiate()
			add_child(_mouse_weapon)
			_mouse_weapon.equip(self)
			if _music_bpm > 0.0 and _mouse_weapon.has_method("set_music_bpm"):
				_mouse_weapon.set_music_bpm(_music_bpm)
		_:
			print("Mouse weapon pending implementation: ", weapon_id)


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_ARRAY:
		return fallback

	var array := value as Array
	if array.size() < 3:
		return fallback

	return Vector3(float(array[0]), float(array[1]), float(array[2]))
