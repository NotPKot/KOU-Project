extends CharacterBody3D

enum State { IDLE, CHASING, CHARGING, ATTACKING, DAZED, STUNNED }

@export var walk_speed: float = 3.5
@export var acceleration: float = 10.0
@export var aggro_range: float = 16.0
@export var attack_range: float = 2.8
@export var charge_duration: float = 1.0
@export var attack_duration: float = 0.4
@export var attack_lunge: float = 2.5
@export var dazed_duration: float = 1.0
@export var attack_damage: int = 10
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0
@export var max_hp: int = 50
@export var vision_range: float = 40.0
@export var vision_angle: float = 120.0
@export var lose_sight_time: float = 3.0
@export var charge_blink_rate: float = 9.0

var hp: int
var _state: State = State.IDLE
var _state_elapsed: float = 0.0
var _tension_registered: bool = false
var _sight_loss_timer: float = 0.0
var _can_see_cache: bool = false
var _can_see_frame: int = -1
var _effects: Dictionary = {}
var _locked_attack_dir: Vector3 = Vector3.FORWARD

var _left_fist_material: StandardMaterial3D = null
var _right_fist_material: StandardMaterial3D = null
var _body_material: StandardMaterial3D = null

var _player: Node3D = null
var _player_search_done: bool = false

var _vision_query: PhysicsRayQueryParameters3D = null

@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _left_fist: MeshInstance3D = $Visual/LeftFist
@onready var _right_fist: MeshInstance3D = $Visual/RightFist


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")


func _process(delta: float) -> void:
	_process_effects(delta)
	_update_vision(delta)
	_update_fsm(delta)


func _process_effects(delta: float) -> void:
	var expired: Array[String] = []
	for name in _effects:
		var e: StatusEffect = _effects[name]
		if e.tick(delta):
			expired.append(name)
			e.remove()
	for name in expired:
		_effects.erase(name)


func _update_vision(delta: float) -> void:
	var player := _get_player()
	if player == null:
		return

	var can_see := _can_see_player_cached()

	if can_see:
		_sight_loss_timer = 0.0
		if not _tension_registered:
			_tension_registered = true
			MusicManager.register_threat(self)
	else:
		_sight_loss_timer += delta
		if _tension_registered and _sight_loss_timer >= lose_sight_time:
			_tension_registered = false
			MusicManager.unregister_threat(self)


func _update_fsm(delta: float) -> void:
	_state_elapsed += delta
	_check_transitions()

	match _state:
		State.CHASING:
			_chase(delta)
		State.CHARGING:
			_stand_still(delta)
			_process_charge()
		State.ATTACKING:
			_process_attack()
		State.DAZED:
			_stand_still(delta)
		State.STUNNED:
			_stand_still(0.0)
		_:
			_stand_still(delta)


func _check_transitions() -> void:
	var player := _get_player()
	if player == null:
		return

	var dist := global_position.distance_to(player.global_position)

	match _state:
		State.IDLE:
			if _can_see_player_cached():
				_change_state(State.CHASING)

		State.CHASING:
			if not _can_see_player_cached() and _sight_loss_timer >= lose_sight_time:
				_change_state(State.IDLE)
			elif dist < attack_range:
				_change_state(State.CHARGING)

		State.CHARGING:
			if _state_elapsed >= charge_duration:
				_change_state(State.ATTACKING)

		State.ATTACKING:
			if _state_elapsed >= attack_duration:
				_change_state(State.DAZED)

		State.DAZED:
			if _state_elapsed >= dazed_duration:
				_change_state(State.CHASING)

		State.STUNNED:
			if not has_effect("stun"):
				_change_state(State.IDLE)


func _chase(delta: float) -> void:
	var player := _get_player()
	if player == null:
		return

	var dir := (player.global_position - global_position).normalized()
	dir.y = 0.0

	velocity.x = move_toward(velocity.x, dir.x * walk_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * walk_speed, acceleration * delta)

	if dir.length_squared() > 0.001:
		_visual.look_at(global_position + dir, Vector3.UP)


func _stand_still(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _process_charge() -> void:
	var blink_on := fmod(_state_elapsed * charge_blink_rate, 1.0) < 0.5
	var fist_color := Color(1.0, 0.05, 0.05, 1.0) if blink_on else Color(0.9, 0.75, 0.7, 1.0)
	_get_left_fist_material().albedo_color = fist_color
	_get_right_fist_material().albedo_color = fist_color

	var body_color := Color(1.0, 0.2, 0.2, 1.0) if blink_on else Color(0.55, 0.27, 0.07, 1.0)
	_get_body_material().albedo_color = body_color


func _process_attack() -> void:
	velocity.x = _locked_attack_dir.x * attack_lunge
	velocity.z = _locked_attack_dir.z * attack_lunge

	if _state_elapsed < 0.1:
		var player := _get_player()
		if player != null:
			var dist := global_position.distance_to(player.global_position)
			if dist < attack_range + 1.0:
				if player.has_method("take_damage"):
					player.take_damage(attack_damage, self)

	_get_left_fist_material().albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_get_right_fist_material().albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_get_body_material().albedo_color = Color(1.0, 0.9, 0.9, 1.0)


func _change_state(new_state: State) -> void:
	_state = new_state
	_state_elapsed = 0.0

	if new_state == State.CHARGING:
		var player := _get_player()
		if player != null:
			var to_player := player.global_position - global_position
			to_player.y = 0.0
			if to_player.length_squared() > 0.0001:
				_locked_attack_dir = to_player.normalized()
			_visual.look_at(global_position + _locked_attack_dir, Vector3.UP)

	if new_state == State.DAZED:
		_get_left_fist_material().albedo_color = Color(0.45, 0.35, 0.35, 1.0)
		_get_right_fist_material().albedo_color = Color(0.45, 0.35, 0.35, 1.0)
		_get_body_material().albedo_color = Color(0.3, 0.2, 0.1, 1.0)

	if new_state not in [State.DAZED, State.CHARGING]:
		_reset_colors()


func _reset_colors() -> void:
	_get_left_fist_material().albedo_color = Color(0.9, 0.75, 0.7, 1.0)
	_get_right_fist_material().albedo_color = Color(0.9, 0.75, 0.7, 1.0)
	_get_body_material().albedo_color = Color(0.55, 0.27, 0.07, 1.0)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = max(velocity.y - gravity * delta, -terminal_velocity)
	elif velocity.y < 0.0:
		velocity.y = -0.1


func _get_player() -> Node3D:
	if _player == null and not _player_search_done:
		_player_search_done = true
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _get_vision_query() -> PhysicsRayQueryParameters3D:
	if _vision_query == null:
		_vision_query = PhysicsRayQueryParameters3D.new()
		_vision_query.collision_mask = 1
	return _vision_query


func _can_see_player_cached() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _can_see_frame:
		return _can_see_cache
	_can_see_frame = frame
	_can_see_cache = _can_see_player()
	return _can_see_cache


func _can_see_player() -> bool:
	var player := _get_player()
	if player == null:
		return false

	var to_player := player.global_position - global_position
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

	var query := _get_vision_query()
	query.from = global_position + Vector3.UP * 0.5
	query.to = player.global_position + Vector3.UP * 0.5
	query.exclude = [get_rid(), player.get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


func _get_left_fist_material() -> StandardMaterial3D:
	if _left_fist_material == null:
		_left_fist_material = StandardMaterial3D.new()
		_left_fist_material.albedo_color = Color(0.9, 0.75, 0.7, 1.0)
		_left_fist.material_override = _left_fist_material
	return _left_fist_material


func _get_right_fist_material() -> StandardMaterial3D:
	if _right_fist_material == null:
		_right_fist_material = StandardMaterial3D.new()
		_right_fist_material.albedo_color = Color(0.9, 0.75, 0.7, 1.0)
		_right_fist.material_override = _right_fist_material
	return _right_fist_material


func _get_body_material() -> StandardMaterial3D:
	if _body_material == null:
		_body_material = StandardMaterial3D.new()
		_body_material.albedo_color = Color(0.55, 0.27, 0.07, 1.0)
		_body_material.roughness = 0.85
		_body_mesh.material_override = _body_material
	return _body_material


func apply_effect(effect: StatusEffect) -> void:
	if _effects.has(effect.effect_name):
		_effects[effect.effect_name].remaining = effect.duration
		return
	effect.apply(self)
	_effects[effect.effect_name] = effect
	if effect.effect_name == "stun":
		_change_state(State.STUNNED)


func has_effect(name: String) -> bool:
	return _effects.has(name)


func take_damage(amount: int) -> void:
	hp -= amount
	_modulate_damage()
	if hp <= 0:
		queue_free()


func _modulate_damage() -> void:
	_get_body_material().albedo_color = Color.WHITE
	await get_tree().create_timer(0.08).timeout
	if is_queued_for_deletion():
		return
	_get_body_material().albedo_color = Color(0.55, 0.27, 0.07, 1.0)
