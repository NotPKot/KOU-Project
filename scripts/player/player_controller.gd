extends CharacterBody3D


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

@export_group("Combat")
@export var max_hp: int = 100

@export_group("Camera")
@export_range(0.0005, 0.01, 0.0005) var mouse_sensitivity: float = 0.003
@export var min_pitch_degrees: float = -55.0
@export var max_pitch_degrees: float = 18.0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _visual: Node3D = $Visual

var mouse_weapon_id: StringName = &""
var mobility_skill_id: StringName = &""
var _camera_yaw: float = 0.0
var _camera_pitch: float = deg_to_rad(-14.0)
var _min_pitch_rad: float
var _max_pitch_rad: float
var _input_locked: bool = false
var _aim_locked: bool = false
var _mouse_weapon: Node = null
var _dash: Dash = null
var _hook: GrapplingHook = null
var _teleport: Teleport = null
var _air_control_timer: float = 0.0
var _can_jump: bool = false
var hp: int
var _parry_window: float = 0.0
var _last_hit_msec: int = -20000
var _regen_timer: float = 0.0


func _ready() -> void:
	hp = max_hp
	add_to_group("player")
	add_to_group("saveable")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_min_pitch_rad = deg_to_rad(min_pitch_degrees)
	_max_pitch_rad = deg_to_rad(max_pitch_degrees)
	_apply_camera_rotation()


func _input(event: InputEvent) -> void:
	if _input_locked or _aim_locked:
		return

	var key_event: InputEventKey = event as InputEventKey
	if key_event != null and (key_event.keycode == KEY_SHIFT or key_event.physical_keycode == KEY_SHIFT):
		if key_event.pressed:
			_on_mobility_pressed()
		else:
			_on_mobility_released()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _input_locked:
		return

	if _aim_locked:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw -= event.relative.x * mouse_sensitivity
		_camera_pitch = clamp(
			_camera_pitch - event.relative.y * mouse_sensitivity,
			_min_pitch_rad,
			_max_pitch_rad
		)
		_apply_camera_rotation()

	if _mouse_weapon == null or not _mouse_weapon.has_method("on_mouse_button"):
		return

	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed:
		if _mouse_weapon.on_mouse_button(mb.button_index):
			get_viewport().set_input_as_handled()


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

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if _hook != null:
		_hook.set_input(input_vector)

	if _dash != null and _dash.physics_tick(delta):
		if _teleport != null and _teleport.is_charging:
			var cam_basis := _camera_pivot.global_transform.basis
			_teleport.update_aim(_camera_pivot.global_position, -cam_basis.z)
		return

	if _hook != null and _hook.physics_tick(delta):
		if _teleport != null and _teleport.is_charging:
			var cam_basis := _camera_pivot.global_transform.basis
			_teleport.update_aim(_camera_pivot.global_position, -cam_basis.z)
		return

	var move_direction: Vector3 = _get_camera_relative_direction(input_vector)
	var target_xz: Vector3 = move_direction * walk_speed
	if _air_control_timer > 0.0:
		_air_control_timer = max(_air_control_timer - delta, 0.0)

	var current_air_acceleration: float = temporal_impulse_air_acceleration if _air_control_timer > 0.0 else air_acceleration
	var acceleration: float = ground_acceleration if is_on_floor() else current_air_acceleration

	if input_vector.is_zero_approx() and is_on_floor():
		acceleration = ground_deceleration

	velocity.x = move_toward(velocity.x, target_xz.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_xz.z, acceleration * delta)

	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.1
	else:
		var gravity_scale: float = temporal_impulse_gravity_scale if _air_control_timer > 0.0 and velocity.y < 0.0 else 1.0
		velocity.y = max(velocity.y - gravity * gravity_scale * delta, -terminal_velocity)

	if _can_jump and is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	move_and_slide()

	if _teleport != null and _teleport.is_charging:
		var cam_basis := _camera_pivot.global_transform.basis
		_teleport.update_aim(_camera_pivot.global_position, -cam_basis.z)

	_face_motion_direction(delta)


func _process(delta: float) -> void:
	if _parry_window > 0.0:
		_parry_window = maxf(_parry_window - delta, 0.0)

	if hp < max_hp and (Time.get_ticks_msec() - _last_hit_msec) >= 10000:
		_regen_timer += delta
		if _regen_timer >= 5.0:
			_regen_timer = 0.0
			hp = mini(hp + 10, max_hp)


func take_damage(amount: int, hitter: Node = null) -> void:
	if _parry_window > 0.0 and _mouse_weapon != null and _mouse_weapon.has_method("on_parry_hit"):
		_mouse_weapon.on_parry_hit(hitter)
		return

	hp -= amount
	_last_hit_msec = Time.get_ticks_msec()
	_regen_timer = 0.0
	if hp <= 0:
		hp = 0


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


func set_parry_window(duration: float) -> void:
	_parry_window = duration


func set_mouse_weapon(weapon_id: StringName) -> void:
	mouse_weapon_id = weapon_id
	_equip_mouse_weapon(weapon_id)
	print("Mouse weapon selected: ", mouse_weapon_id)


func set_mobility_skill(skill_id: StringName) -> void:
	_clear_mobility_skill()
	mobility_skill_id = skill_id

	match skill_id:
		&"dash":
			_dash = load("res://scripts/player/dash.gd").new()
			_dash.setup(self)
			add_child(_dash)
		&"grappling_hook":
			_hook = load("res://scripts/player/grappling_hook.gd").new()
			_hook.setup(self, _camera)
			add_child(_hook)
		&"teleport":
			_teleport = load("res://scripts/player/teleport.gd").new()
			_teleport.setup(self)
			add_child(_teleport)

	print("Mobility skill selected: ", mobility_skill_id)


func _clear_mobility_skill() -> void:
	if _dash != null:
		_dash.queue_free()
		_dash = null
	if _hook != null:
		_hook.queue_free()
		_hook = null
	if _teleport != null:
		_teleport.queue_free()
		_teleport = null
	mobility_skill_id = &""


func _on_mobility_pressed() -> void:
	if _input_locked or _aim_locked:
		return

	var cam_basis := _camera_pivot.global_transform.basis
	var cam_fwd: Vector3 = -cam_basis.z
	var cam_pos: Vector3 = _camera_pivot.global_position

	if _dash != null:
		_dash.fire(cam_fwd)
	elif _hook != null:
		var hit := _raycast_aim(cam_pos, cam_fwd, _hook.max_rope_length)
		_hook.fire(hit)
	elif _teleport != null:
		_teleport.fire(cam_pos, cam_fwd)


func _on_mobility_released() -> void:
	if _hook != null and _hook.is_attached:
		_hook.release()
	elif _teleport != null and _teleport.is_charging:
		_teleport.release()


func _raycast_aim(from: Vector3, forward: Vector3, max_dist: float) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return from + forward * max_dist

	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = global_position + forward * max_dist
	query.collision_mask = 1 | 4
	query.hit_from_inside = true
	query.exclude = [get_rid()]

	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return from + forward * max_dist

	return result["position"]


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
		"mobility_skill_id": String(mobility_skill_id),
	}


func apply_save_data(data: Dictionary) -> void:
	var pos_data = data.get("global_position")
	if pos_data != null:
		global_position = _array_to_vector3(pos_data, global_position)

	_camera_yaw = float(data.get("camera_yaw", _camera_yaw))
	_camera_pitch = float(data.get("camera_pitch", _camera_pitch))
	_apply_camera_rotation()

	var saved_weapon := StringName(str(data.get("mouse_weapon_id", "")))
	if saved_weapon != &"":
		set_mouse_weapon(saved_weapon)

	var saved_mobility := StringName(str(data.get("mobility_skill_id", "")))
	if saved_mobility != &"":
		set_mobility_skill(saved_mobility)



func _equip_mouse_weapon(weapon_id: StringName) -> void:
	if _mouse_weapon != null:
		if _mouse_weapon.has_method("unequip"):
			_mouse_weapon.unequip()
		_mouse_weapon.queue_free()
		_mouse_weapon = null

	match weapon_id:
		&"broken_stopwatch":
			_mouse_weapon = load("res://scenes/weapons/BrokenStopwatch.tscn").instantiate()
			add_child(_mouse_weapon)
			_mouse_weapon.equip(self)
		&"katana":
			_mouse_weapon = load("res://scripts/weapons/katana.gd").new()
			add_child(_mouse_weapon)
			_mouse_weapon.equip(self)
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
