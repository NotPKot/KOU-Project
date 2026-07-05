extends CharacterBody3D

enum State { CHASE, WINDUP, DASH, RECOVERY }

@export_group("Movement")
@export var walk_speed: float = 3.5
@export var acceleration: float = 10.0

@export_group("Attack")
@export var windup_duration: float = 0.7
@export var dash_duration: float = 0.2
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

@export var max_hp: int = 50

var hp: int
var _state: State = State.CHASE
var _state_elapsed: float = 0.0
var _can_see_cache: bool = false
var _can_see_frame: int = -1
var _effects: Dictionary = {}
var _locked_dir: Vector3 = Vector3.FORWARD
var _smooth_dir: Vector3 = Vector3.FORWARD
var _nav_map_ready: bool = false
var _hit_dealt: bool = false

var _target: Node3D = null
var _left_fist_material: StandardMaterial3D = null
var _right_fist_material: StandardMaterial3D = null
var _body_fist_material: StandardMaterial3D = null

var _vision_query: PhysicsRayQueryParameters3D = null

@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _left_fist: MeshInstance3D = $Visual/LeftFist
@onready var _right_fist: MeshInstance3D = $Visual/RightFist
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")

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
	_process_effects(delta)
	_update_fsm(delta)
	_update_visual(delta)
	_state_elapsed += delta


func _process_effects(delta: float) -> void:
	var expired: Array[String] = []
	for name in _effects:
		var e: StatusEffect = _effects[name]
		if e.tick(delta):
			expired.append(name)
			e.remove()
	for name in expired:
		_effects.erase(name)


func _update_fsm(delta: float) -> void:
	if _target == null:
		return

	var dist_sq := global_position.distance_squared_to(_target.global_position)

	match _state:
		State.CHASE:
			if dist_sq <= dash_trigger_range * dash_trigger_range:
				_change_state(State.WINDUP)

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


func _update_visual(delta: float) -> void:
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
	_set_velocity_for_state(delta)
	_apply_gravity(delta)
	move_and_slide()


func _set_velocity_for_state(delta: float) -> void:
	match _state:
		State.CHASE:
			_set_chase_velocity(delta)
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

	_nav_agent.target_position = _target.global_position

	if _nav_agent.is_navigation_finished():
		var dir := (_target.global_position - global_position)
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			dir = dir.normalized()
			velocity.x = move_toward(velocity.x, dir.x * walk_speed, acceleration * delta)
			velocity.z = move_toward(velocity.z, dir.z * walk_speed, acceleration * delta)
			_visual.look_at(global_position + dir, Vector3.UP)
		else:
			_set_stop_velocity(delta)
		return

	var next_point := _nav_agent.get_next_path_position()
	var dir := next_point - global_position
	dir.y = 0.0

	if dir.length_squared() > 0.001:
		dir = dir.normalized()
		if is_on_wall():
			var wall_n := get_wall_normal()
			var along := wall_n.cross(Vector3.UP).normalized()
			dir = (dir + along * sign(dir.dot(along)) * 0.8).normalized()
		var avoid := _avoid_allies(2.0)
		var blended := dir + avoid * 3.0
		if blended.length_squared() > 0.001:
			blended = blended.normalized()
		else:
			blended = dir
		var turn_rate := 4.0
		_smooth_dir = _smooth_dir.lerp(blended, turn_rate * delta).normalized()
		velocity.x = _smooth_dir.x * walk_speed
		velocity.z = _smooth_dir.z * walk_speed
		_visual.look_at(global_position + _smooth_dir, Vector3.UP)
	else:
		_set_stop_velocity(delta)


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
		if dist < min_dist and dist > 0.01:
			var strength: float = (min_dist - dist) / min_dist
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


func apply_effect(effect: StatusEffect) -> void:
	if _effects.has(effect.effect_name):
		_effects[effect.effect_name].remaining = effect.duration
		return
	effect.apply(self)
	_effects[effect.effect_name] = effect


func has_effect(name: String) -> bool:
	return _effects.has(name)


func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()
