extends CharacterBody3D

enum State { IDLE, CHASING, CHARGING, ATTACKING, COOLDOWN, STUNNED }

@export var walk_speed: float = 3.5
@export var acceleration: float = 10.0
@export var aggro_range: float = 16.0
@export var attack_range: float = 2.8
@export var charge_duration: float = 1.0
@export var attack_duration: float = 0.4
@export var attack_lunge: float = 6.0
@export var attack_cooldown: float = 1.5
@export var attack_damage: int = 10
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0
@export var max_hp: int = 50
@export var vision_range: float = 40.0
@export var vision_angle: float = 120.0
@export var lose_sight_time: float = 3.0

var hp: int
var _state: State = State.IDLE
var _state_elapsed: float = 0.0
var _player: Node3D = null
var _left_fist_material: StandardMaterial3D
var _right_fist_material: StandardMaterial3D
var _body_material: StandardMaterial3D
var _fist_idle_color: Color = Color(0.9, 0.75, 0.7, 1.0)
var _body_base_color: Color = Color(0.55, 0.27, 0.07, 1.0)
var _tension_registered: bool = false
var _sight_loss_timer: float = 0.0
var _can_see_cache: bool = false
var _can_see_frame: int = -1
var _effects: Dictionary = {}

@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _left_fist: MeshInstance3D = $Visual/LeftFist
@onready var _right_fist: MeshInstance3D = $Visual/RightFist


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	_player = get_tree().get_first_node_in_group("player") as Node3D

	_left_fist_material = StandardMaterial3D.new()
	_right_fist_material = StandardMaterial3D.new()
	_left_fist_material.albedo_color = _fist_idle_color
	_right_fist_material.albedo_color = _fist_idle_color
	_left_fist.material_override = _left_fist_material
	_right_fist.material_override = _right_fist_material

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = _body_base_color
	_body_material.roughness = 0.85
	_body_mesh.material_override = _body_material


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_process_effects(delta)
	_update_vision(delta)
	_update_fsm(delta)
	move_and_slide()


func _can_see_player_cached() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _can_see_frame:
		return _can_see_cache
	_can_see_frame = frame
	_can_see_cache = _can_see_player()
	return _can_see_cache


func _update_vision(delta: float) -> void:
	if _player == null:
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


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = max(velocity.y - gravity * delta, -terminal_velocity)
	elif velocity.y < 0.0:
		velocity.y = -0.1


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
		State.COOLDOWN:
			_stand_still(delta)
		State.STUNNED:
			_stand_still(0.0)
		_:
			_stand_still(delta)


func _check_transitions() -> void:
	if _player == null:
		return

	var dist := global_position.distance_to(_player.global_position)

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
				_change_state(State.COOLDOWN)

		State.COOLDOWN:
			if _state_elapsed >= attack_cooldown:
				_change_state(State.CHASING)

		State.STUNNED:
			if not has_effect("stun"):
				_change_state(State.IDLE)


func _change_state(new_state: State) -> void:
	_state = new_state
	_state_elapsed = 0.0


func _can_see_player() -> bool:
	if _player == null:
		return false

	var to_player := _player.global_position - global_position
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

	var query := PhysicsRayQueryParameters3D.new()
	query.from = global_position + Vector3.UP * 0.5
	query.to = _player.global_position + Vector3.UP * 0.5
	query.collision_mask = 1
	query.exclude = [get_rid(), _player.get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


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


func _process_effects(delta: float) -> void:
	var expired: Array[String] = []
	for name in _effects:
		var e: StatusEffect = _effects[name]
		if e.tick(delta):
			expired.append(name)
			e.remove()
	for name in expired:
		_effects.erase(name)


func _chase(delta: float) -> void:
	if _player == null:
		return

	var dir := (_player.global_position - global_position).normalized()
	dir.y = 0.0

	velocity.x = move_toward(velocity.x, dir.x * walk_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * walk_speed, acceleration * delta)

	if dir.length_squared() > 0.001:
		_visual.look_at(global_position + dir, Vector3.UP)

	_reset_fist_color()


func _stand_still(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _process_charge() -> void:
	var intensity := sin(_state_elapsed * 18.0) * 0.5 + 0.5
	var charge_color := Color(1.0, 0.2 + intensity * 0.3, 0.2 + intensity * 0.3, 1.0)
	_left_fist_material.albedo_color = charge_color
	_right_fist_material.albedo_color = charge_color


func _process_attack() -> void:
	var dir := -_visual.global_transform.basis.z
	velocity.x = dir.x * attack_lunge
	velocity.z = dir.z * attack_lunge

	if _state_elapsed < 0.1 and _player != null:
		var dist := global_position.distance_to(_player.global_position)
		if dist < attack_range + 1.0:
			if _player.has_method("take_damage"):
				_player.take_damage(attack_damage, self)

	_left_fist_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_right_fist_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)


func _reset_fist_color() -> void:
	_left_fist_material.albedo_color = _fist_idle_color
	_right_fist_material.albedo_color = _fist_idle_color


func take_damage(amount: int) -> void:
	hp -= amount
	_modulate_damage()
	if hp <= 0:
		queue_free()


func _modulate_damage() -> void:
	_body_material.albedo_color = Color.WHITE
	await get_tree().create_timer(0.08).timeout
	if is_queued_for_deletion():
		return
	_body_material.albedo_color = _body_base_color
