extends CharacterBody3D

enum State { CHASE, WINDUP, DASH, RECOVERY, RETREATING, HIDING }

@export_group("Movement")
@export var walk_speed: float = 8.0
@export var acceleration: float = 10.0
@export var min_speed_mult: float = 0.15

@export_group("Steering")
@export var max_turn_speed: float = 720.0
@export var slow_radius: float = 2.0

@export_group("Crowd Steering")
@export var approach_offset_radius: float = 1.75
@export var ally_separation_radius: float = 2.0
@export var ally_separation_weight: float = 2.4

@export_group("Pursuit Boost")
@export var pursuit_boost_rate: float = 0.025
@export var pursuit_boost_max: float = 3.0

@export_group("Attack")
@export var windup_duration: float = 0.7
@export var dash_duration: float = 0.5
@export var dash_speed: float = 12.0
@export var recovery_duration: float = 0.8
@export var attack_damage: int = 10
@export var attack_range: float = 3.0
@export var windup_blink_rate: float = 9.0

@export_group("Detection")
@export var aggro_range: float = 16.0
@export var dash_trigger_range: float = 3.0
@export var vision_range: float = 40.0
@export var vision_angle: float = 120.0
@export var lose_sight_time: float = 3.0

@export_group("Physics")
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0

@export_group("Retreat")
@export var retreat_y_threshold: float = 1.5
@export var retreat_max_horiz_dist: float = 20.0
@export var hide_timeout: float = 15.0

@export var max_hp: int = 50

var hp: int
var _state: State = State.CHASE
var _state_elapsed: float = 0.0
var _can_see_cache: bool = false
var _can_see_frame: int = -1
var _locked_dir: Vector3 = Vector3.FORWARD
var _smooth_dir: Vector3 = Vector3.FORWARD
var _nav_map_ready: bool = false
var _hit_dealt: bool = false
var _approach_angle: float = 0.0

var _knockback: Vector3 = Vector3.ZERO
var _target: Node3D = null
var _retreat_spot: HidingSpot = null
var _hiding_sight_lost: float = 0.0
var _left_fist_material: StandardMaterial3D = null
var _right_fist_material: StandardMaterial3D = null
var _body_fist_material: StandardMaterial3D = null

var _vision_query: PhysicsRayQueryParameters3D = null

@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _left_fist: MeshInstance3D = $Visual/LeftFist
@onready var _right_fist: MeshInstance3D = $Visual/RightFist
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _status: StatusEffectController = $StatusEffectController


func _exit_tree() -> void:
	if _retreat_spot != null:
		_retreat_spot.occupied = false
		_retreat_spot = null


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	# Cada enemigo conserva un punto distinto en el anillo del jugador. Esto
	# evita que todos intenten ocupar el mismo metro cuadrado sin perder el
	# camino optimo que calcula el NavigationAgent.
	_approach_angle = fposmod(float(get_instance_id() % 10000) * 2.3999632, TAU)

	NavigationServer3D.map_changed.connect(_on_nav_map_changed)
	_nav_map_ready = false

	_nav_agent.path_desired_distance = 0.5
	_nav_agent.target_desired_distance = 0.5
	_nav_agent.radius = 0.3
	_nav_agent.height = 1.8
	_nav_agent.max_speed = walk_speed
	_nav_agent.neighbor_distance = 5.0
	_nav_agent.time_horizon = 2.0
	_nav_agent.avoidance_enabled = false

	floor_block_on_wall = false


func _process(delta: float) -> void:
	_update_fsm(delta)
	_update_visual(delta)
	_state_elapsed += delta


func _update_fsm(_delta: float) -> void:
	if _target == null:
		return

	var dist_sq := global_position.distance_squared_to(_target.global_position)

	match _state:
		State.CHASE:
			if dist_sq <= dash_trigger_range * dash_trigger_range:
				_change_state(State.WINDUP)
			elif _cannot_reach_player():
				_on_cannot_reach_player()

		State.RETREATING:
			if dist_sq <= dash_trigger_range * dash_trigger_range:
				_change_state(State.WINDUP)
			elif _nav_agent.is_navigation_finished():
				_change_state(State.HIDING)

		State.HIDING:
			if dist_sq <= dash_trigger_range * dash_trigger_range:
				_change_state(State.WINDUP)
			elif _can_chase_player():
				_change_state(State.CHASE)
			else:
				_hiding_sight_lost += _delta
				if _hiding_sight_lost >= hide_timeout:
					_change_state(State.CHASE)

		State.WINDUP:
			if _state_elapsed >= windup_duration:
				_change_state(State.DASH)

		State.DASH:
			if _state_elapsed >= dash_duration:
				_change_state(State.RECOVERY)

		State.RECOVERY:
			if _state_elapsed >= recovery_duration:
				_change_state(State.CHASE)


func _change_state(new_state: State) -> void:
	_state = new_state
	_state_elapsed = 0.0
	_hit_dealt = false

	match new_state:
		State.CHASE:
			if _retreat_spot != null:
				_retreat_spot.occupied = false
				_retreat_spot = null

		State.WINDUP:
			if _target != null:
				var to_player := _target.global_position - global_position
				to_player.y = 0.0
				if to_player.length_squared() > 0.0001:
					_locked_dir = to_player.normalized()
				_visual.look_at(global_position + _locked_dir, Vector3.UP)

		State.DASH:
			if _target != null:
				var dist_sq := global_position.distance_squared_to(_target.global_position)
				if dist_sq <= attack_range * attack_range:
					if _target.has_method("take_damage"):
						_target.take_damage(attack_damage, self)
						_hit_dealt = true

		State.HIDING:
			_set_stop_velocity(0.0)
			_hiding_sight_lost = 0.0


func _update_visual(_delta: float) -> void:
	match _state:
		State.WINDUP:
			var blink_on := fmod(_state_elapsed * windup_blink_rate, 1.0) < 0.5
			var c := Color(1.0, 0.1, 0.1) if blink_on else Color(0.55, 0.27, 0.07)
			_get_fist_material(0).albedo_color = c
			_get_fist_material(1).albedo_color = c
			_get_body_material().albedo_color = c

		State.DASH:
			_get_fist_material(0).albedo_color = Color.WHITE
			_get_fist_material(1).albedo_color = Color.WHITE

		State.RECOVERY:
			var dim := Color(0.3, 0.15, 0.05)
			_get_fist_material(0).albedo_color = dim
			_get_fist_material(1).albedo_color = dim
			_get_body_material().albedo_color = dim

		State.RETREATING:
			var dim := Color(0.55, 0.35, 0.55)
			_get_fist_material(0).albedo_color = dim
			_get_fist_material(1).albedo_color = dim
			_get_body_material().albedo_color = dim

		State.HIDING:
			var dark := Color(0.2, 0.1, 0.2)
			_get_fist_material(0).albedo_color = dark
			_get_fist_material(1).albedo_color = dark
			_get_body_material().albedo_color = dark

		State.CHASE:
			_reset_visual()


func _reset_visual() -> void:
	_get_fist_material(0).albedo_color = Color(0.9, 0.75, 0.7)
	_get_fist_material(1).albedo_color = Color(0.9, 0.75, 0.7)
	_get_body_material().albedo_color = Color(0.55, 0.27, 0.07)


func _get_fist_material(idx: int) -> StandardMaterial3D:
	if idx == 0:
		if _left_fist_material == null:
			_left_fist_material = StandardMaterial3D.new()
			_left_fist_material.albedo_color = Color(0.9, 0.75, 0.7)
			_left_fist.material_override = _left_fist_material
		return _left_fist_material
	else:
		if _right_fist_material == null:
			_right_fist_material = StandardMaterial3D.new()
			_right_fist_material.albedo_color = Color(0.9, 0.75, 0.7)
			_right_fist.material_override = _right_fist_material
		return _right_fist_material


func _get_body_material() -> StandardMaterial3D:
	if _body_fist_material == null:
		_body_fist_material = StandardMaterial3D.new()
		_body_fist_material.albedo_color = Color(0.55, 0.27, 0.07)
		_body_fist_material.roughness = 0.85
		_body_mesh.material_override = _body_fist_material
	return _body_fist_material


func _physics_process(delta: float) -> void:
	if _status.is_stunned:
		_set_stop_velocity(delta)
	else:
		_set_velocity_for_state(delta)
	velocity += _knockback
	_apply_gravity(delta)
	move_and_slide()
	_knockback = _knockback.move_toward(Vector3.ZERO, 50.0 * delta)


func _set_velocity_for_state(delta: float) -> void:
	match _state:
		State.CHASE:
			_set_chase_velocity(delta)
		State.RETREATING:
			_set_retreat_velocity(delta)
		State.HIDING:
			_set_hiding_velocity(delta)
		State.WINDUP:
			_set_stop_velocity(delta)
		State.DASH:
			_set_dash_velocity()
		State.RECOVERY:
			_set_stop_velocity(delta)


func _set_chase_velocity(delta: float) -> void:
	if _target == null:
		_set_stop_velocity(delta)
		return

	var approach_target := _get_approach_target()
	_nav_agent.target_position = approach_target

	var dir: Vector3
	if _nav_agent.is_navigation_finished():
		dir = approach_target - global_position
		dir.y = 0.0
	else:
		dir = _get_chase_direction()

	if dir.length_squared() > 0.001:
		_move_in_chase_direction(dir.normalized(), delta, approach_target)
	else:
		_set_stop_velocity(delta)
		_try_look_at_healer()


func _try_look_at_healer() -> bool:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e == self or not is_instance_valid(e):
			continue
		if not e.has_method("get_current_action"):
			continue
		if e.get_current_action() == "HEAL":
			var healer_pos := (e as Node3D).global_position
			if global_position.distance_squared_to(healer_pos) < 64.0:
				_visual.look_at(healer_pos, Vector3.UP)
				return true
	return false


func _move_in_chase_direction(dir: Vector3, delta: float, target_pos: Vector3) -> void:
	if is_on_wall():
		var wall_n := get_wall_normal()
		var along := wall_n.cross(Vector3.UP).normalized()
		dir = (dir + along * sign(dir.dot(along)) * 0.8).normalized()

	var blended := dir + _avoid_allies(ally_separation_radius) * ally_separation_weight
	if blended.length_squared() > 0.001:
		blended = blended.normalized()
	else:
		blended = dir

	var speed := _get_pursuit_speed()
	speed = minf(speed, _apply_arrival(speed, target_pos))

	var turn_step := deg_to_rad(max_turn_speed) * delta
	_smooth_dir = _rotate_toward_dir(_smooth_dir, blended, turn_step)

	var alignment := _smooth_dir.dot(blended)
	var speed_mult := clampf(remap(alignment, -1.0, 1.0, min_speed_mult, 1.0), min_speed_mult, 1.0)
	velocity.x = _smooth_dir.x * speed * speed_mult
	velocity.z = _smooth_dir.z * speed * speed_mult
	_visual.look_at(global_position + _smooth_dir, Vector3.UP)


func _get_pursuit_speed() -> float:
	if _target == null:
		return walk_speed
	var dist := global_position.distance_to(_target.global_position)
	var boost := 1.0 + dist * pursuit_boost_rate
	return walk_speed * minf(boost, pursuit_boost_max)


func _get_approach_target() -> Vector3:
	if _target == null:
		return global_position

	var ring_offset := Vector3(cos(_approach_angle), 0.0, sin(_approach_angle)) * approach_offset_radius
	return _target.global_position + ring_offset


func _cannot_reach_player() -> bool:
	if _target == null:
		return false
	if not _target.is_on_floor():
		return false
	if _target.global_position.y - global_position.y <= retreat_y_threshold:
		return false
	var horiz_dist := Vector3(global_position.x, 0.0, global_position.z).distance_to(
		Vector3(_target.global_position.x, 0.0, _target.global_position.z)
	)
	if horiz_dist > retreat_max_horiz_dist:
		return false
	return _nav_agent.is_navigation_finished()


func _can_chase_player() -> bool:
	if _target == null:
		return true
	return _target.global_position.y - global_position.y <= retreat_y_threshold


func _on_cannot_reach_player() -> void:
	var spot := _find_nearest_free_hiding_spot()
	if spot != null:
		spot.occupied = true
		_retreat_spot = spot
		_change_state(State.RETREATING)
		_nav_agent.target_position = spot.global_position
	else:
		_change_state(State.HIDING)


func _find_nearest_free_hiding_spot() -> HidingSpot:
	var spots: Array[HidingSpot] = []
	for s in get_tree().get_nodes_in_group("hiding_spots"):
		if not s.occupied:
			spots.append(s)
	if spots.is_empty():
		return null
	spots.sort_custom(func(a: HidingSpot, b: HidingSpot) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)
	)
	return spots[0]


func _set_retreat_velocity(delta: float) -> void:
	if _retreat_spot == null or _nav_agent.is_navigation_finished():
		_set_stop_velocity(delta)
		return

	var next_point := _nav_agent.get_next_path_position()
	var dir := next_point - global_position
	dir.y = 0.0

	if dir.length_squared() > 0.001:
		var turn_step := deg_to_rad(max_turn_speed) * delta
		_smooth_dir = _rotate_toward_dir(_smooth_dir, dir.normalized(), turn_step)
		var alignment := _smooth_dir.dot(dir.normalized())
		var speed_mult := clampf(remap(alignment, -1.0, 1.0, min_speed_mult, 1.0), min_speed_mult, 1.0)
		velocity.x = _smooth_dir.x * walk_speed * speed_mult
		velocity.z = _smooth_dir.z * walk_speed * speed_mult
		_visual.look_at(global_position + _smooth_dir, Vector3.UP)
	else:
		_set_stop_velocity(delta)


func _set_hiding_velocity(_delta: float) -> void:
	_set_stop_velocity(_delta)


func _rotate_toward_dir(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var from_angle := atan2(from.x, -from.z)
	var to_angle := atan2(to.x, -to.z)
	var result_angle := rotate_toward(from_angle, to_angle, max_angle)
	return Vector3(sin(result_angle), 0.0, -cos(result_angle)).normalized()


func _apply_arrival(speed: float, target_pos: Vector3) -> float:
	var dist := global_position.distance_to(target_pos)
	if dist < slow_radius:
		return speed * (dist / slow_radius)
	return speed


func _get_chase_direction() -> Vector3:
	var path := _nav_agent.get_current_navigation_path()
	var path_idx := _nav_agent.get_current_navigation_path_index()

	var look_idx := mini(path_idx + 1, path.size() - 1)
	var target_pos := path[look_idx] if path_idx < path.size() else global_position

	var dir := target_pos - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		return dir.normalized()
	return Vector3.ZERO


func _set_dash_velocity() -> void:
	velocity.x = _locked_dir.x * dash_speed
	velocity.z = _locked_dir.z * dash_speed


func _set_stop_velocity(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 200.0 * delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = max(velocity.y - gravity * delta, -terminal_velocity)
	elif velocity.y < 0.0:
		velocity.y = -0.1


func _avoid_allies(min_dist: float) -> Vector3:
	var result := Vector3.ZERO
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	for e: Node in enemies:
		if e == self or not is_instance_valid(e):
			continue
		var offset: Vector3 = global_position - e.global_position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist < min_dist:
			if dist <= 0.01:
				offset = Vector3(cos(_approach_angle), 0.0, sin(_approach_angle))
				dist = 0.01
			var strength: float = pow((min_dist - dist) / min_dist, 2.0)
			result += offset.normalized() * strength
	return result


func set_target(p: Node3D) -> void:
	_target = p


func _can_see_player_cached() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _can_see_frame:
		return _can_see_cache
	_can_see_frame = frame
	_can_see_cache = _can_see_player()
	return _can_see_cache


func _can_see_player() -> bool:
	if _target == null:
		return false

	var to_player := _target.global_position - global_position
	var dist := to_player.length()
	if dist > vision_range:
		return false
	if dist < 0.01:
		return true

	var dir := to_player / dist
	var forward := -_visual.global_transform.basis.z
	if forward.dot(dir) < cos(deg_to_rad(vision_angle * 0.5)):
		return false

	var space := get_world_3d().direct_space_state
	if space == null:
		return true

	var vision_query := _get_vision_query()
	vision_query.from = global_position + Vector3.UP * 0.5
	vision_query.to = _target.global_position + Vector3.UP * 0.5
	vision_query.exclude = [get_rid(), _target.get_rid()]
	var result := space.intersect_ray(vision_query)
	return result.is_empty()


func _get_vision_query() -> PhysicsRayQueryParameters3D:
	if _vision_query == null:
		_vision_query = PhysicsRayQueryParameters3D.new()
		_vision_query.collision_mask = 1
	return _vision_query


func _on_nav_map_changed(map_rid: RID) -> void:
	if map_rid == _nav_agent.get_navigation_map():
		_nav_map_ready = true


func apply_effect(effect_name: String, duration: float, value: float = 1.0) -> void:
	_status.apply_effect(effect_name, duration, value)


func apply_knockback(direction: Vector3, force: float) -> void:
	_knockback += direction * force


func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()
