extends CharacterBody3D

enum State { CHASE, TELEGRAPH, SUBMERGE, TRAVEL, ATTACK, RECOVERY }

@export_group("Movement")
@export var walk_speed: float = 8.0
@export var acceleration: float = 10.0
@export var travel_speed: float = 6.0
@export var turn_rate: float = 4.0
@export var min_speed_mult: float = 0.15

@export_group("Crowd Steering")
@export var approach_offset_radius: float = 2.0
@export var ally_separation_radius: float = 2.2
@export var ally_separation_weight: float = 2.0

@export_group("Pursuit Boost")
@export var pursuit_boost_rate: float = 0.025
@export var pursuit_boost_max: float = 3.0

@export_group("Dash")
@export var fixed_dash_distance: float = 16.0
@export var min_dash_distance: float = 3.0

@export_group("Timing")
@export var telegraph_duration: float = 1.0
@export var submerge_duration: float = 0.3
@export var attack_duration: float = 0.15
@export var dome_grace_duration: float = 0.35
@export var recovery_duration: float = 2.0

@export_group("Combat")
@export var attack_damage: int = 15
@export var indicator_radius: float = 2.5

@export_group("Detection")
@export var aggro_range: float = 16.0
@export var vision_range: float = 40.0
@export var vision_angle: float = 120.0
@export var lose_sight_time: float = 3.0

@export_group("Physics")
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0

@export var max_hp: int = 20

var hp: int
var _state: State = State.CHASE
var _state_elapsed: float = 0.0
var _can_see_cache: bool = false
var _can_see_frame: int = -1
var _smooth_dir: Vector3 = Vector3.FORWARD

var _origin: Vector3 = Vector3.ZERO
var _destination: Vector3 = Vector3.ZERO
var _travel_progress: float = 0.0
var _triggered_by_player: bool = false
var _hit_dealt: bool = false
var _approach_angle: float = 0.0

var _knockback: Vector3 = Vector3.ZERO
var _target: Node3D = null

var _vision_query: PhysicsRayQueryParameters3D = null

var _dome: Node3D = null
var _dome_mesh: MeshInstance3D = null
var _dome_area: Area3D = null
var _dome_damage_dealt: bool = false

@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _indicator: MeshInstance3D = $Indicator
@onready var _direction_line: MeshInstance3D = $DirectionLine
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _status: StatusEffectController = $StatusEffectController


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	_approach_angle = fposmod(float(get_instance_id() % 10000) * 2.3999632, TAU)

	NavigationServer3D.map_changed.connect(_on_nav_map_changed)

	_nav_agent.path_desired_distance = 0.5
	_nav_agent.target_desired_distance = 0.5
	_nav_agent.radius = 0.3
	_nav_agent.height = 1.8
	_nav_agent.max_speed = walk_speed
	_nav_agent.neighbor_distance = 5.0
	_nav_agent.time_horizon = 2.0
	_nav_agent.avoidance_enabled = false

	floor_block_on_wall = false

	_indicator.visible = false
	_direction_line.visible = false


func _process(delta: float) -> void:
	_update_fsm(delta)
	_state_elapsed += delta


func _update_fsm(delta: float) -> void:
	if _target == null:
		return

	var dist_sq := global_position.distance_squared_to(_target.global_position)

	match _state:
		State.CHASE:
			if _can_see_player_cached() and dist_sq <= aggro_range * aggro_range:
				_change_state(State.TELEGRAPH)

		State.TELEGRAPH:
			_update_telegraph_indicator()
			if _state_elapsed >= telegraph_duration:
				_change_state(State.SUBMERGE)

		State.SUBMERGE:
			if _state_elapsed >= submerge_duration:
				_change_state(State.TRAVEL)

		State.TRAVEL:
			var travel_dist := _origin.distance_to(_destination)
			var speed := travel_speed * delta / maxf(travel_dist, 0.001)
			_travel_progress = minf(_travel_progress + speed, 1.0)
			var pos := _origin.lerp(_destination, _travel_progress)
			global_position = pos
			_update_indicator(pos)

			if _state_elapsed >= 0.5:
				var player_pos := _target.global_position
				player_pos.y = 0.0
				var circle_pos := pos
				circle_pos.y = 0.0
				if circle_pos.distance_squared_to(player_pos) <= indicator_radius * indicator_radius:
					if not _triggered_by_player:
						_triggered_by_player = true
				if _triggered_by_player:
					_change_state(State.ATTACK)

			if _travel_progress >= 1.0:
				_triggered_by_player = false
				_change_state(State.ATTACK)

		State.ATTACK:
			var emerge_t := minf(_state_elapsed / attack_duration, 1.0)
			if _dome_mesh != null:
				_dome_mesh.scale = Vector3(emerge_t, emerge_t, emerge_t)

			if not _dome_damage_dealt and _target != null:
				var current_radius := indicator_radius * emerge_t
				if _target is Node3D:
					var player_node := _target as Node3D
					var player_dist_sq := global_position.distance_squared_to(player_node.global_position)
					if player_dist_sq <= current_radius * current_radius:
						_dome_damage_dealt = true
						if player_node.has_method("take_damage"):
							player_node.take_damage(attack_damage)
						if player_node.has_method("apply_knockback"):
							var knock_dir := player_node.global_position - global_position
							knock_dir.y = 0.0
							if knock_dir.length_squared() > 0.001:
								knock_dir = knock_dir.normalized()
							else:
								knock_dir = Vector3.FORWARD
							knock_dir.y = 0.375
							player_node.apply_knockback(knock_dir, 28.0)
						_hit_dealt = true

			if _state_elapsed >= attack_duration and _state_elapsed < attack_duration + dome_grace_duration:
				var pulse := sin(_state_elapsed * 24.0) * 0.5 + 0.5
				var mat := _dome_mesh.material_override as StandardMaterial3D
				if mat != null:
					mat.albedo_color.a = 0.15 + pulse * 0.5

			if _state_elapsed >= attack_duration + dome_grace_duration:
				_change_state(State.RECOVERY)

		State.RECOVERY:
			if _state_elapsed >= recovery_duration:
				_change_state(State.CHASE)


func _calculate_destination() -> void:
	_origin = global_position
	var dir := (_get_approach_target() - _origin)
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var dash_dist := maxf(fixed_dash_distance, min_dash_distance)
	_destination = _origin + dir * dash_dist
	_destination.y = _origin.y


func _change_state(new_state: State) -> void:
	_state = new_state
	_state_elapsed = 0.0
	_hit_dealt = false

	match new_state:
		State.TELEGRAPH:
			_calculate_destination()
			_indicator.visible = true
			_direction_line.visible = true

		State.SUBMERGE:
			_visual.visible = false
			_body_mesh.visible = false
			_set_collision_enabled(false)
			global_position = _origin

		State.TRAVEL:
			_travel_progress = 0.0
			_triggered_by_player = false
			global_position = _origin
			_update_indicator(_origin)
			_indicator.visible = true
			_direction_line.visible = true

		State.ATTACK:
			_visual.visible = true
			_body_mesh.visible = true
			_set_collision_enabled(true)
			_dome_damage_dealt = false
			_create_dome()

		State.RECOVERY:
			_indicator.visible = false
			_direction_line.visible = false
			_set_collision_enabled(true)
			_destroy_dome()

		State.CHASE:
			_visual.visible = true
			_body_mesh.visible = true
			_set_collision_enabled(true)
			_indicator.visible = false
			_direction_line.visible = false


func _update_telegraph_indicator() -> void:
	var dest_ground := Vector3(_destination.x, 0.0, _destination.z)
	_indicator.global_position = dest_ground

	var origin_ground := Vector3(_origin.x, 0.0, _origin.z)
	var line_dir := dest_ground - origin_ground
	var line_dist := line_dir.length()
	if line_dist > 0.01:
		var mid := origin_ground + line_dir * 0.5
		_direction_line.global_position = Vector3(mid.x, 0.02, mid.z)
		_direction_line.scale = Vector3(1.0, 1.0, line_dist)
		_direction_line.look_at(dest_ground, Vector3.UP)
	_direction_line.visible = line_dist > 0.1


func _update_indicator(current: Vector3) -> void:
	var ground_pos := Vector3(current.x, 0.0, current.z)
	_indicator.global_position = ground_pos

	var line_to := _destination
	line_to.y = 0.0
	var line_from := ground_pos
	var line_dir := line_to - line_from
	var line_dist := line_dir.length()
	if line_dist > 0.01:
		var mid := line_from + line_dir * 0.5
		_direction_line.global_position = Vector3(mid.x, 0.02, mid.z)
		_direction_line.scale = Vector3(1.0, 1.0, line_dist)
		_direction_line.look_at(Vector3(line_to.x, 0.02, line_to.z), Vector3.UP)
	_direction_line.visible = line_dist > 0.1


func _create_dome() -> void:
	_dome = Node3D.new()
	_dome.name = "Dome"
	add_child(_dome)

	_dome_mesh = MeshInstance3D.new()
	_dome_mesh.name = "DomeMesh"
	var sphere := SphereMesh.new()
	sphere.radius = indicator_radius
	sphere.height = indicator_radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.12, 0.02, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(1, 0.08, 0.0)
	mat.emission_energy_multiplier = 1.5
	_dome_mesh.material_override = mat
	_dome_mesh.mesh = sphere
	_dome_mesh.position = Vector3(0, 0, 0)
	_dome_mesh.scale = Vector3.ZERO
	_dome.add_child(_dome_mesh)

	_dome_area = Area3D.new()
	_dome_area.name = "DomeArea"
	_dome_area.collision_mask = 1
	_dome_area.monitoring = false
	var shape_node := CollisionShape3D.new()
	shape_node.name = "DomeShape"
	var cyl := CylinderShape3D.new()
	cyl.radius = indicator_radius
	cyl.height = 1.0
	shape_node.shape = cyl
	_dome_area.add_child(shape_node)
	_dome.add_child(_dome_area)
	_dome_area.body_entered.connect(_on_dome_entered)


func _destroy_dome() -> void:
	if _dome != null and is_instance_valid(_dome):
		_dome.queue_free()
	_dome = null
	_dome_mesh = null
	_dome_area = null


func _on_dome_entered(body: Node) -> void:
	if _dome_damage_dealt:
		return
	if body == _target and body.has_method("take_damage"):
		body.take_damage(attack_damage)
		_hit_dealt = true


func _deal_dome_damage() -> void:
	if _target == null:
		return
	var dist_sq := global_position.distance_squared_to(_target.global_position)
	if dist_sq <= indicator_radius * indicator_radius:
		if _target.has_method("take_damage"):
			_target.take_damage(attack_damage)
			_hit_dealt = true


func _set_collision_enabled(enabled: bool) -> void:
	if enabled:
		collision_layer = 2
		collision_mask = 1
	else:
		collision_layer = 0
		collision_mask = 0


func _physics_process(delta: float) -> void:
	if _status.is_stunned:
		_set_stop_velocity(delta)
	else:
		match _state:
			State.CHASE:
				_chase(delta)
			State.RECOVERY:
				_set_stop_velocity(delta)
			_:
				_set_stop_velocity(delta)
	velocity += _knockback
	_apply_gravity(delta)
	move_and_slide()
	_knockback = _knockback.move_toward(Vector3.ZERO, 50.0 * delta)


func _chase(delta: float) -> void:
	if _target == null:
		_set_stop_velocity(delta)
		return

	var approach_target := _get_approach_target()
	_nav_agent.target_position = approach_target

	if _nav_agent.is_navigation_finished():
		var t_dir := approach_target - global_position
		t_dir.y = 0.0
		if t_dir.length_squared() > 0.001:
			_move_in_chase_direction(t_dir.normalized(), delta)
		else:
			_set_stop_velocity(delta)
			_try_look_at_healer()
		return

	var next_point := _nav_agent.get_next_path_position()
	var dir := next_point - global_position
	dir.y = 0.0

	if dir.length_squared() > 0.001:
		dir = dir.normalized()
		_move_in_chase_direction(dir, delta)
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


func _move_in_chase_direction(dir: Vector3, delta: float) -> void:
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
	_smooth_dir = _smooth_dir.lerp(blended, turn_rate * delta).normalized()
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
		pass


func apply_effect(effect_name: String, duration: float, value: float = 1.0) -> void:
	_status.apply_effect(effect_name, duration, value)


func apply_knockback(direction: Vector3, force: float) -> void:
	_knockback += direction * force


func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()
