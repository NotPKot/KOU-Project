class_name GrapplingHook
extends Node

signal hooked(hook_point: Vector3)
signal released(reason: String)

@export var max_rope_length: float = 45.0
@export var passive_reel_speed: float = 2.0
@export var active_reel_speed: float = 22.0
@export var spring_constant: float = 10.0
@export var spring_force_max: float = 25.0
@export var tangential_damping: float = 0.05
@export var swing_strength: float = 35.0
@export var pump_strength: float = 10.0
@export var max_tangential_speed: float = 40.0
@export var release_boost: float = 1.15
@export var cooldown: float = 0.8
@export var min_release_dist: float = 2.0
@export var slack_enabled: bool = true

var is_attached: bool = false
var anchor: Vector3 = Vector3.ZERO
var rest_length: float = 0.0

var _player: CharacterBody3D = null
var _input_dir: Vector2 = Vector2.ZERO
var _cool_timer: float = 0.0
var _line: MeshInstance3D = null
var _line_mesh: ImmediateMesh = null
var _camera: Camera3D = null


func setup(player: CharacterBody3D, camera: Camera3D = null) -> void:
	_player = player
	_camera = camera
	_build_rope_visual()


func _build_rope_visual() -> void:
	_line_mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	_line.material_override = mat
	_line.visible = false
	add_child(_line)


func fire(aim_pos: Vector3) -> void:
	if _cool_timer > 0.0 or is_attached or _player == null:
		return
	var dist: float = _player.global_position.distance_to(aim_pos)
	if dist > max_rope_length:
		return
	is_attached = true
	anchor = aim_pos
	rest_length = dist
	_line.visible = true
	hooked.emit(aim_pos)


func release(reason: String = "manual") -> void:
	if not is_attached:
		return
	var boost: Vector3 = _player.velocity * release_boost
	is_attached = false
	_line.visible = false
	_cool_timer = cooldown
	_player.velocity = boost
	released.emit(reason)


func set_input(dir: Vector2) -> void:
	_input_dir = dir


func _process(delta: float) -> void:
	_cool_timer = maxf(_cool_timer - delta, 0.0)
	if _line.visible:
		_draw_rope()


func physics_tick(delta: float) -> bool:
	if not is_attached:
		return false
	_tick_swing(delta)
	return true


func _tick_swing(delta: float) -> void:
	var to_anchor: Vector3 = anchor - _player.global_position
	var dist: float = to_anchor.length()

	if dist < 0.05:
		return

	var dir: Vector3 = to_anchor / dist

	if dist > max_rope_length * 1.5:
		release("too_far")
		return

	if dist < min_release_dist:
		release("too_close")
		return

	var pulling: bool = _input_dir.y < 0.0
	var pull_amount: float = absf(_input_dir.y) if pulling else 0.0

	var reel_speed: float = passive_reel_speed + active_reel_speed * pull_amount
	rest_length = maxf(rest_length - reel_speed * delta, 0.5)

	var vel: Vector3 = _player.velocity
	var radial_speed: float = vel.dot(dir)
	var radial_vel: Vector3 = dir * radial_speed
	var tangential_vel: Vector3 = vel - radial_vel

	var diff: float = dist - rest_length
	if diff > 0.0 or not slack_enabled:
		var spring_force: float = diff * spring_constant
		spring_force = clampf(spring_force, -spring_force_max, spring_force_max)
		radial_speed += spring_force * delta
		radial_vel = dir * radial_speed

	tangential_vel *= (1.0 - tangential_damping)

	var swing_input: Vector3 = _get_swing_input_dir(dir)
	tangential_vel += swing_input * swing_strength * delta

	if pulling:
		var forward_pump: Vector3 = _get_forward_tangent(dir)
		tangential_vel += forward_pump * pump_strength * pull_amount * delta

	tangential_vel = tangential_vel.limit_length(max_tangential_speed)

	_player.velocity = radial_vel + tangential_vel

	var gravity: float = absf(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_player.velocity += Vector3.DOWN * gravity * delta

	_player.move_and_slide()


func _get_swing_input_dir(radial_dir: Vector3) -> Vector3:
	var right: Vector3
	if _camera != null:
		right = _camera.global_transform.basis.x
	else:
		right = _player.global_transform.basis.x

	right -= right.dot(radial_dir) * radial_dir
	if right.length() < 0.001:
		return Vector3.ZERO
	right = right.normalized()

	return right * _input_dir.x


func _get_forward_tangent(radial_dir: Vector3) -> Vector3:
	var forward: Vector3
	if _camera != null:
		forward = -_camera.global_transform.basis.z
	else:
		forward = -_player.global_transform.basis.z

	forward -= forward.dot(radial_dir) * radial_dir
	if forward.length() < 0.001:
		return Vector3.ZERO
	return forward.normalized()


func _draw_rope() -> void:
	if _line_mesh == null or _player == null:
		return
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_line_mesh.surface_add_vertex(anchor)
	_line_mesh.surface_add_vertex(_player.global_position + Vector3.UP * 0.5)
	_line_mesh.surface_end()
