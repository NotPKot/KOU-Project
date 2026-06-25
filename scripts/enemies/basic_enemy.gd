extends CharacterBody3D

enum State { IDLE, CHASING, CHARGING, ATTACKING, COOLDOWN }

@export var walk_speed: float = 3.5
@export var acceleration: float = 10.0
@export var aggro_range: float = 16.0
@export var attack_range: float = 2.8
@export var charge_duration: float = 1.0
@export var attack_duration: float = 0.4
@export var attack_lunge: float = 6.0
@export var attack_cooldown: float = 1.5
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0
@export var max_hp: int = 50

var hp: int
var _state: State = State.IDLE
var _state_elapsed: float = 0.0
var _player: Node3D = null
var _left_fist_material: StandardMaterial3D
var _right_fist_material: StandardMaterial3D
var _body_material: StandardMaterial3D
var _fist_idle_color: Color = Color(0.9, 0.75, 0.7, 1.0)
var _body_base_color: Color = Color(0.55, 0.27, 0.07, 1.0)

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
	_update_fsm(delta)
	move_and_slide()


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
		_:
			_stand_still(delta)


func _check_transitions() -> void:
	if _player == null:
		return

	var dist := global_position.distance_to(_player.global_position)

	match _state:
		State.IDLE:
			if dist < aggro_range:
				_change_state(State.CHASING)

		State.CHASING:
			if dist > aggro_range * 1.5:
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


func _change_state(new_state: State) -> void:
	_state = new_state
	_state_elapsed = 0.0


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
