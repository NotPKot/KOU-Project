extends CharacterBody3D

enum State { IDLE, CHASING, SUBMERGING, TRACKING, EMERGING, COOLDOWN, STUNNED }

@export var walk_speed: float = 2.5
@export var acceleration: float = 8.0
@export var chase_duration: float = 3.0
@export var submerge_time: float = 0.8
@export var track_duration: float = 3.0
@export var emerge_time: float = 0.6
@export var emerge_damage: int = 10
@export var attack_cooldown: float = 3.0
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0
@export var max_hp: int = 40
@export var vision_range: float = 40.0
@export var vision_angle: float = 120.0
@export var lose_sight_time: float = 3.0
@export var indicator_radius: float = 2.5

var hp: int
var _state: State = State.IDLE
var _state_elapsed: float = 0.0
var _target: Node3D = null
var _body_material: StandardMaterial3D
var _body_base_color: Color = Color(0.6, 0.15, 0.25, 1.0)
var _tension_registered: bool = false
var _sight_loss_timer: float = 0.0
var _can_see_cache: bool = false
var _can_see_frame: int = -1
var _track_target: Vector3 = Vector3.ZERO
var _indicator_mesh: MeshInstance3D = null
var _indicator_material: StandardMaterial3D = null
var _original_visual_y: float = 0.0
var _stun_timer: float = 0.0
var _effects: Dictionary = {}
var _chase_target: Vector3 = Vector3.ZERO

@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _indicator: MeshInstance3D = $Indicator


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = _body_base_color
	_body_material.roughness = 0.8
	_body_mesh.material_override = _body_material

	_indicator_material = StandardMaterial3D.new()
	_indicator_material.albedo_color = Color(1.0, 0.2, 0.1, 0.35)
	_indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator.material_override = _indicator_material
	_indicator.visible = false

	_original_visual_y = _visual.position.y


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
	if _target == null:
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
		State.SUBMERGING:
			_process_submerge(delta)
		State.TRACKING:
			_process_tracking(delta)
		State.EMERGING:
			_process_emerge(delta)
		State.COOLDOWN:
			_stand_still(delta)
		State.STUNNED:
			_stand_still(0.0)
		_:			
			_stand_still(delta)


func _check_transitions() -> void:
	if _target == null:
		return

	match _state:
		State.IDLE:
			if _can_see_player_cached():
				_change_state(State.CHASING)

		State.CHASING:
			if not _can_see_player_cached() and _sight_loss_timer >= lose_sight_time:
				_change_state(State.IDLE)
			elif _state_elapsed >= chase_duration:
				_change_state(State.SUBMERGING)

		State.SUBMERGING:
			if _state_elapsed >= submerge_time and _target != null:
				_track_target = _target.global_position
				_indicator.global_position = Vector3(_track_target.x, 0.0, _track_target.z)
				_indicator.visible = true
				_change_state(State.TRACKING)

		State.TRACKING:
			if _target != null:
				_track_target = _target.global_position
			_indicator.global_position = _track_target

			if not _can_see_player_cached() and _sight_loss_timer >= lose_sight_time:
				_indicator.visible = false
				_change_state(State.IDLE)
			elif _state_elapsed >= track_duration:
				_indicator.visible = false
				_change_state(State.EMERGING)

		State.EMERGING:
			if _state_elapsed >= emerge_time:
				_deal_emerge_damage()
				_change_state(State.COOLDOWN)

		State.COOLDOWN:
			if _state_elapsed >= attack_cooldown:
				_change_state(State.IDLE)

		State.STUNNED:
			if not has_effect("stun"):
				_change_state(State.IDLE)


func _chase(delta: float) -> void:
	if _target == null:
		return

	_chase_target = _chase_target.lerp(_target.global_position, delta * 0.5)
	var dir := (_chase_target - global_position).normalized()
	dir.y = 0.0

	velocity.x = move_toward(velocity.x, dir.x * walk_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * walk_speed, acceleration * delta)

	if dir.length_squared() > 0.001:
		_visual.look_at(global_position + dir, Vector3.UP)


func _process_submerge(delta: float) -> void:
	var t: float = _state_elapsed / submerge_time
	_visual.position.y = lerpf(_original_visual_y, -1.5, t)
	_body_material.albedo_color.a = 1.0 - t
	_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _process_tracking(delta: float) -> void:
	global_position = global_position.lerp(_track_target, delta * 4.0)
	_indicator.global_position = Vector3(_track_target.x, 0.0, _track_target.z)
	var emerge_alert: float = track_duration - 1.0
	if _state_elapsed >= emerge_alert:
		var alpha: float = 0.25 + sin(_state_elapsed * 20.0) * 0.3
		_indicator_material.albedo_color.a = clampf(alpha, 0.0, 0.6)


func _process_emerge(delta: float) -> void:
	var t: float = _state_elapsed / emerge_time
	_visual.position.y = lerpf(-1.5, _original_visual_y, t)
	_body_material.albedo_color.a = t


func _stand_still(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _change_state(new_state: State) -> void:
	_state = new_state
	_state_elapsed = 0.0

	match _state:
		State.SUBMERGING:
			velocity = Vector3.ZERO
		State.EMERGING:
			global_position = _track_target
			_visual.position.y = -1.5
		State.COOLDOWN:
			_visual.position.y = _original_visual_y


func _deal_emerge_damage() -> void:
	if _target == null:
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= indicator_radius:
		if _target.has_method("take_damage"):
			_target.take_damage(emerge_damage)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = max(velocity.y - gravity * delta, -terminal_velocity)
	elif velocity.y < 0.0:
		velocity.y = -0.1


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

	var query := PhysicsRayQueryParameters3D.new()
	query.from = global_position + Vector3.UP * 0.5
	query.to = _target.global_position + Vector3.UP * 0.5
	query.collision_mask = 1
	query.exclude = [get_rid(), _target.get_rid()]
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
