extends CharacterBody3D

signal died

@export_group("Movement")
@export var max_speed: float = 8.0
@export var air_max_speed: float = 8.0
@export var ground_accel: float = 60.0
@export var air_accel: float = 8.0
@export var air_soft_cap_speed: float = 20.0
@export var air_soft_cap_drag: float = 4.0
@export var ground_friction: float = 6.0
@export var ground_stop_speed: float = 2.0
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0
@export var floor_snap_length_value: float = 0.35
@export var safe_margin_value: float = 0.04
@export var temporal_impulse_velocity: float = 12.0
@export var temporal_impulse_air_control_time: float = 2.8
@export var temporal_impulse_air_acceleration: float = 14.0
@export var temporal_impulse_gravity_scale: float = 0.45
@export var movement_debug_enabled: bool = false
@export var movement_debug_interval: float = 0.35

@export_group("Floor")
@export var floor_max_angle_degrees: float = 45.0

@export_group("Wall Slide")
@export var wall_friction: float = 0.8
@export var slide_gravity_multiplier: float = 1.5

# -- TRIMPING TUNING: la velocidad se proyecta sobre el plano de una rampa, como en Source.
@export_group("Trimping")
@export var trimp_enabled: bool = true
@export var trimp_min_speed: float = 12.0
@export var trimp_min_slope_degrees: float = 12.0
@export var trimp_max_slope_degrees: float = 65.0
@export var trimp_min_impact_speed: float = 2.0
@export var trimp_min_launch_speed: float = 1.5
@export var trimp_cooldown: float = 0.14
@export_range(0.0, 1.0, 0.01) var trimp_velocity_retention: float = 1.0

@export_group("Jump")
@export var jump_velocity: float = 8.5

@export_group("Combat")
@export var max_hp: int = 100

@export_group("Camera")
@export_range(0.0005, 0.01, 0.0005) var mouse_sensitivity: float = 0.003
@export var min_pitch_degrees: float = -65.0
@export var max_pitch_degrees: float = 55.0

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
var _jump_held: bool = false
var _lifesteal_ratio: float = 0.0
var _potion_heal_amount: int = 0
var _potion_cooldown: float = 0.0
var _potion_cooldown_timer: float = 0.0
var _has_regen: bool = false
var _clean_time: float = 0.0
var _is_regen_active: bool = false
var hp: int
var _trimp_cooldown_timer: float = 0.0
var _movement_debug_timer: float = 0.0

const CLEAN_TIME_THRESHOLD: float = 10.0
const REGEN_HPS: float = 16.0
var _parry_window: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_velocity: Vector2 = Vector2.ZERO
const SHAKE_IMPULSE: float = 9.0
const SHAKE_SPRING: float = 180.0
const SHAKE_DAMPING: float = 24.0
const SHAKE_MAX_OFFSET: float = 0.18

var _was_on_floor: bool = true
var _squash_tween: Tween = null
const JUMP_STRETCH_SCALE: Vector3 = Vector3(0.9, 1.15, 0.9)
const JUMP_STRETCH_DURATION: float = 0.3
const LAND_SQUASH_SCALE: Vector3 = Vector3(1.15, 0.8, 1.15)
const LAND_SQUASH_DURATION: float = 0.08
const LAND_RECOVER_DURATION: float = 0.15


func _ready() -> void:
	hp = max_hp
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_min_pitch_rad = deg_to_rad(min_pitch_degrees)
	_max_pitch_rad = deg_to_rad(max_pitch_degrees)
	floor_max_angle = deg_to_rad(floor_max_angle_degrees)
	floor_snap_length = floor_snap_length_value
	safe_margin = safe_margin_value
	floor_stop_on_slope = true
	floor_block_on_wall = false
	_apply_camera_rotation()


func _input(event: InputEvent) -> void:
	if _input_locked or _aim_locked:
		return

	var key_event: InputEventKey = event as InputEventKey
	if key_event != null:
		if key_event.keycode == KEY_SHIFT or key_event.physical_keycode == KEY_SHIFT:
			if key_event.pressed:
				_on_mobility_pressed()
			else:
				_on_mobility_released()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_E and key_event.pressed:
			_use_potion()
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
	if not Input.is_action_pressed("ui_accept"):
		_jump_held = false

	var was_on_floor_before := _was_on_floor

	if _trimp_cooldown_timer > 0.0:
		_trimp_cooldown_timer = maxf(_trimp_cooldown_timer - delta, 0.0)

	if _input_locked:
		velocity.x = move_toward(velocity.x, 0.0, ground_accel * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_accel * delta)

		if is_on_floor() and velocity.y < 0.0:
			velocity.y = -0.1
		else:
			velocity.y = max(velocity.y - gravity * delta, -terminal_velocity)

		move_and_slide()
		_was_on_floor = is_on_floor()
		return

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if _hook != null:
		_hook.set_input(input_vector)

	if _dash != null and _dash.is_dashing:
		input_vector = Vector2.ZERO
		if _teleport != null and _teleport.is_charging:
			var cam_basis: Basis = _camera.global_transform.basis
			_teleport.update_aim(_camera.global_position, -cam_basis.z)

	if _hook != null and _hook.is_attached:
		if Input.is_action_just_pressed("ui_accept"):
			_hook.release("jump_cancel")
			if _teleport != null and _teleport.is_charging:
				var cam_basis: Basis = _camera.global_transform.basis
				_teleport.update_aim(_camera.global_position, -cam_basis.z)
		elif _hook.physics_tick(delta):
			_finish_special_motion(delta, false)
			if _teleport != null and _teleport.is_charging:
				var cam_basis: Basis = _camera.global_transform.basis
				_teleport.update_aim(_camera.global_position, -cam_basis.z)
			_was_on_floor = is_on_floor()
			return

	var wish_dir: Vector3 = _get_camera_relative_direction(input_vector)
	if _air_control_timer > 0.0:
		_air_control_timer = max(_air_control_timer - delta, 0.0)

	var current_air_accel: float = temporal_impulse_air_acceleration if _air_control_timer > 0.0 else air_accel

	var on_steep_wall: bool = false
	var wall_normal: Vector3 = Vector3.UP
	if is_on_wall():
		wall_normal = get_wall_normal()
		var wall_angle: float = rad_to_deg(wall_normal.angle_to(Vector3.UP))
		on_steep_wall = wall_angle > floor_max_angle_degrees and wall_angle <= 100.0

	if is_on_floor():
		if _can_jump and Input.is_action_pressed("ui_accept") and not _jump_held:
			velocity.y = jump_velocity
			_jump_held = true
			_trigger_jump_stretch()
		elif _dash != null and _dash.is_dashing:
			pass
		else:
			_apply_ground_friction(delta)
			if not wish_dir.is_zero_approx():
				apply_ground_acceleration(wish_dir, max_speed, ground_accel, delta)

		if velocity.y < 0.0:
			velocity.y = -0.1

	elif on_steep_wall:
		apply_acceleration(wish_dir, air_max_speed, current_air_accel, delta)
		var wall_drag: float = 1.0
		if not (_dash != null and _dash.is_dashing):
			wall_drag = clampf(1.0 - wall_friction * delta, 0.0, 1.0)
		velocity.x *= wall_drag
		velocity.z *= wall_drag
		_projected_gravity(delta, wall_normal, slide_gravity_multiplier)

	else:
		apply_acceleration(wish_dir, air_max_speed, current_air_accel, delta)
		_apply_air_speed_soft_cap(delta)
		var gravity_scale: float = temporal_impulse_gravity_scale if _air_control_timer > 0.0 and velocity.y < 0.0 else 1.0
		velocity.y = max(velocity.y - gravity * gravity_scale * delta, -terminal_velocity)

	_print_movement_debug(delta, wish_dir)
	_move_and_slide_with_trimp(velocity)

	if not was_on_floor_before and is_on_floor():
		_trigger_land_squash()
	_was_on_floor = is_on_floor()

	if _teleport != null and _teleport.is_charging:
		var cam_basis: Basis = _camera.global_transform.basis
		_teleport.update_aim(_camera.global_position, -cam_basis.z)

	_face_motion_direction(delta)


func _finish_special_motion(delta: float, apply_extra_gravity: bool) -> void:
	if apply_extra_gravity and not is_on_floor():
		velocity.y = max(velocity.y - gravity * delta, -terminal_velocity)
	velocity.y = max(velocity.y, -terminal_velocity)
	_move_and_slide_with_trimp(velocity)
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -0.1
	_face_motion_direction(delta)


func _process(delta: float) -> void:
	if _parry_window > 0.0:
		_parry_window = maxf(_parry_window - delta, 0.0)

	if _potion_cooldown_timer > 0.0:
		_potion_cooldown_timer = maxf(_potion_cooldown_timer - delta, 0.0)

	if _has_regen:
		_clean_time += delta
		if _clean_time >= CLEAN_TIME_THRESHOLD and not _is_regen_active:
			_is_regen_active = true

		if _is_regen_active:
			heal(ceili(REGEN_HPS * delta))

	_update_screen_shake(delta)


func _use_potion() -> void:
	if _input_locked or _aim_locked or _potion_heal_amount <= 0 or _potion_cooldown_timer > 0.0:
		return

	heal(_potion_heal_amount)
	_potion_cooldown_timer = _potion_cooldown


func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)


func take_damage(amount: int, hitter: Node = null) -> void:
	if _parry_window > 0.0 and _mouse_weapon != null and _mouse_weapon.has_method("on_parry_hit"):
		_mouse_weapon.on_parry_hit(hitter)
		return

	_trigger_hit_shake(hitter)
	if hitter != null and hitter is Node3D:
		var hitter_node := hitter as Node3D
		var dir: Vector3 = (global_position - hitter_node.global_position).normalized()
		dir.y = 0.3
		velocity += dir * 6.0
	hp -= amount
	if _has_regen:
		_clean_time = 0.0
		_is_regen_active = false
	if hp <= 0:
		die()


func apply_knockback(direction: Vector3, force: float) -> void:
	velocity += direction * force


func _trigger_hit_shake(hitter: Node) -> void:
	if not Settings.screen_shake_enabled:
		return

	var screen_direction := Vector2(0.0, 0.35)
	if hitter is Node3D:
		var impact_direction: Vector3 = global_position - (hitter as Node3D).global_position
		if impact_direction.length_squared() > 0.0001:
			impact_direction = impact_direction.normalized()
			var camera_basis := _camera.global_transform.basis
			screen_direction = Vector2(
				impact_direction.dot(camera_basis.x),
				impact_direction.dot(camera_basis.y) + 0.25
			)

	if screen_direction.length_squared() > 0.0001:
		screen_direction = screen_direction.normalized()

	_shake_velocity += screen_direction * SHAKE_IMPULSE * Settings.screen_shake_intensity
	_shake_velocity = _shake_velocity.limit_length(SHAKE_IMPULSE * 1.5 * Settings.screen_shake_intensity)


func _update_screen_shake(delta: float) -> void:
	if not Settings.screen_shake_enabled:
		_shake_offset = Vector2.ZERO
		_shake_velocity = Vector2.ZERO
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return

	if _shake_offset.is_zero_approx() and _shake_velocity.is_zero_approx():
		return

	# Resorte amortiguado: genera un golpe corto y continuo, en vez de saltar
	# entre posiciones aleatorias cada frame.
	_shake_velocity += -_shake_offset * SHAKE_SPRING * delta
	_shake_velocity *= exp(-SHAKE_DAMPING * delta)
	_shake_offset += _shake_velocity * delta
	_shake_offset = _shake_offset.limit_length(SHAKE_MAX_OFFSET)

	_camera.h_offset = _shake_offset.x
	_camera.v_offset = _shake_offset.y

	if _shake_offset.length_squared() < 0.000001 and _shake_velocity.length_squared() < 0.0001:
		_shake_offset = Vector2.ZERO
		_shake_velocity = Vector2.ZERO
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


func die() -> void:
	hp = 0
	died.emit()
	set_physics_process(false)


func apply_acceleration(wish_dir: Vector3, target_speed: float, accel: float, delta: float) -> void:
	var current_speed: float = velocity.dot(wish_dir)
	var add_speed: float = clampf(target_speed - current_speed, 0.0, accel * delta)
	velocity += wish_dir * add_speed


func apply_ground_acceleration(wish_dir: Vector3, target_speed: float, accel: float, delta: float) -> void:
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var current_speed: float = horizontal_velocity.dot(wish_dir)
	var add_speed: float = minf(target_speed - current_speed, accel * delta)
	if add_speed <= 0.0:
		return

	horizontal_velocity += wish_dir * add_speed
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z


func _apply_ground_friction(delta: float) -> void:
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var speed: float = horizontal_velocity.length()
	if speed <= 0.0:
		return

	# Quake aplica friccion gradualmente y nunca recorta el vector a max_speed.
	# Esto deja que un salto del gancho conserve su inercia al aterrizar.
	var control: float = maxf(speed, ground_stop_speed)
	var new_speed: float = maxf(speed - control * ground_friction * delta, 0.0)
	horizontal_velocity *= new_speed / speed
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z


func _projected_gravity(delta: float, normal: Vector3, multiplier: float) -> void:
	var gravity_vec: Vector3 = Vector3.DOWN * gravity * delta
	var into_wall: Vector3 = normal * gravity_vec.dot(normal)
	var along_wall: Vector3 = gravity_vec - into_wall
	velocity += along_wall * multiplier


func _move_and_slide_with_trimp(pre_slide_velocity: Vector3) -> void:
	move_and_slide()
	_try_apply_trimp(pre_slide_velocity)


func _apply_air_speed_soft_cap(delta: float) -> void:
	if air_soft_cap_speed <= 0.0:
		return
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if h_speed > air_soft_cap_speed:
		var excess := h_speed - air_soft_cap_speed
		var reduction := excess * air_soft_cap_drag * delta
		var new_h_speed := maxf(h_speed - reduction, air_soft_cap_speed)
		var ratio := new_h_speed / h_speed
		velocity.x *= ratio
		velocity.z *= ratio


func _try_apply_trimp(pre_slide_velocity: Vector3) -> void:
	if not trimp_enabled or _trimp_cooldown_timer > 0.0:
		return

	var horizontal_velocity: Vector3 = Vector3(pre_slide_velocity.x, 0.0, pre_slide_velocity.z)
	var horizontal_speed: float = horizontal_velocity.length()
	if horizontal_speed < trimp_min_speed:
		return

	var best_launch_velocity: Vector3 = Vector3.ZERO
	var best_launch_speed: float = 0.0

	for index in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(index)
		if collision == null:
			continue

		var normal: Vector3 = collision.get_normal()
		if normal.y <= 0.0:
			continue

		var slope_angle: float = rad_to_deg(normal.angle_to(Vector3.UP))
		if slope_angle < trimp_min_slope_degrees or slope_angle > trimp_max_slope_degrees:
			continue

		var impact_speed: float = -pre_slide_velocity.dot(normal)
		if impact_speed < trimp_min_impact_speed:
			continue

		# Conserva la componente paralela a la rampa. La componente vertical del
		# resultado nace de la geometria del impacto, no de un impulso adicional.
		var projected_velocity: Vector3 = pre_slide_velocity.slide(normal) * trimp_velocity_retention
		if projected_velocity.y < trimp_min_launch_speed:
			continue

		if projected_velocity.y > best_launch_speed:
			best_launch_speed = projected_velocity.y
			best_launch_velocity = projected_velocity

	if best_launch_speed <= 0.0:
		return

	velocity = best_launch_velocity
	_trimp_cooldown_timer = trimp_cooldown


func _print_movement_debug(delta: float, wish_dir: Vector3) -> void:
	if not movement_debug_enabled:
		return

	_movement_debug_timer -= delta
	if _movement_debug_timer > 0.0:
		return

	_movement_debug_timer = movement_debug_interval
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	print(
		"[MOVEMENT_DEBUG] ",
		"floor=", is_on_floor(),
		" wall=", is_on_wall(),
		" speed=", snappedf(horizontal_velocity.length(), 0.001),
		" velocity=", horizontal_velocity,
		" wish_dir=", wish_dir,
		" dot=", snappedf(horizontal_velocity.dot(wish_dir), 0.001),
		" max_speed=", max_speed
	)


func _apply_camera_rotation() -> void:
	_camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)


func _get_camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector.is_zero_approx():
		return Vector3.ZERO

	var cam_basis := _camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
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


func _trigger_jump_stretch() -> void:
	if _squash_tween:
		_squash_tween.kill()
	_visual.scale = Vector3.ONE
	_squash_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	_squash_tween.tween_property(_visual, "scale", JUMP_STRETCH_SCALE, JUMP_STRETCH_DURATION * 0.4)
	_squash_tween.tween_property(_visual, "scale", Vector3.ONE, JUMP_STRETCH_DURATION * 0.6)


func _trigger_land_squash() -> void:
	if _squash_tween:
		_squash_tween.kill()
	_visual.scale = Vector3.ONE
	_squash_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	_squash_tween.tween_property(_visual, "scale", LAND_SQUASH_SCALE, LAND_SQUASH_DURATION)
	_squash_tween.tween_property(_visual, "scale", Vector3.ONE, LAND_RECOVER_DURATION)


func set_input_locked(is_locked: bool) -> void:
	_input_locked = is_locked


func is_input_locked() -> bool:
	return _input_locked


func set_aim_locked(is_locked: bool) -> void:
	_aim_locked = is_locked


func set_parry_window(duration: float) -> void:
	_parry_window = duration


func set_healing_mechanic(mechanic_id: StringName) -> void:
	match mechanic_id:
		&"lifesteal":
			_lifesteal_ratio = 0.10
		&"potion":
			_potion_heal_amount = 35
			_potion_cooldown = 7.0
		&"regen":
			_has_regen = true
		_:
			print("Healing mechanic pending: ", mechanic_id)


func on_dealt_damage(amount: float) -> void:
	if _lifesteal_ratio > 0.0:
		heal(ceili(amount * _lifesteal_ratio))


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

	var cam_basis := _camera.global_transform.basis
	var cam_fwd: Vector3 = -cam_basis.z
	var cam_pos: Vector3 = _camera.global_position

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
	query.to = from + forward * max_dist
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


func get_cooldowns() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if _potion_heal_amount > 0 and _potion_cooldown_timer > 0.0:
		result.append({"id": "potion", "total": _potion_cooldown, "remaining": _potion_cooldown_timer})

	if _dash != null and _dash._cool_timer > 0.0:
		result.append({"id": "dash", "total": _dash.cooldown, "remaining": _dash._cool_timer})

	if _hook != null and _hook._cool_timer > 0.0:
		result.append({"id": "hook", "total": _hook.cooldown, "remaining": _hook._cool_timer})

	if _teleport != null and _teleport._cool_timer > 0.0:
		result.append({"id": "teleport", "total": _teleport.cooldown, "remaining": _teleport._cool_timer})

	return result


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
