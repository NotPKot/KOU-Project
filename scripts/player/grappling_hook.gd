class_name GrapplingHook
extends Node

signal hooked(hook_point: Vector3)
signal released(reason: String)

@export var hook_speed: float = 45.0
@export var max_rope_length: float = 22.0
@export var min_rope_length: float = 2.5
@export var rope_stiffness: float = 12.0
@export var swing_strength: float = 10.0
@export var lateral_curve: float = 20.0
@export var release_boost: float = 1.2
@export var cooldown: float = 0.4

var is_attached: bool = false
var is_flying: bool = false
var anchor: Vector3 = Vector3.ZERO
var rope_len: float = 0.0

var _player: CharacterBody3D = null
var _input_dir: Vector2 = Vector2.ZERO
var _cool_timer: float = 0.0

var _fly_progress: float = 0.0
var _fly_start: Vector3 = Vector3.ZERO
var _fly_target: Vector3 = Vector3.ZERO
var _fly_curve: Vector3 = Vector3.ZERO

var _line: MeshInstance3D = null
var _line_mesh: ImmediateMesh = null


func setup(player: CharacterBody3D) -> void:
	_player = player
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
	if _cool_timer > 0.0 or is_attached or is_flying or _player == null:
		return

	var start: Vector3 = _player.global_position + Vector3.UP * 1.0
	var dir: Vector3 = (aim_pos - start).normalized()
	var dist: float = start.distance_to(aim_pos)

	_fly_start = start
	_fly_target = start + dir * minf(dist, max_rope_length)
	_fly_curve = Vector3.ZERO
	_fly_progress = 0.0
	is_flying = true


func release(reason: String = "manual") -> void:
	if not is_attached:
		return

	var boost: Vector3 = _player.velocity * release_boost
	is_attached = false
	_line.visible = false
	_cool_timer = cooldown
	_player.velocity = boost
	released.emit(reason)


func cancel_flight() -> void:
	if not is_flying:
		return
	is_flying = false
	_cool_timer = cooldown * 0.5


func set_input(dir: Vector2) -> void:
	_input_dir = dir


func _process(delta: float) -> void:
	_cool_timer = maxf(_cool_timer - delta, 0.0)

	if is_flying:
		_tick_flight(delta)

	if is_attached:
		_tick_pendulum(delta)

	if _line.visible:
		_draw_rope()


func _physics_process(_delta: float) -> void:
	if not is_flying:
		return

	var space := _player.get_world_3d().direct_space_state
	if space == null:
		return

	var query := PhysicsRayQueryParameters3D.new()
	query.from = _fly_start + _fly_curve
	query.to = _fly_target + _fly_curve
	query.collision_mask = 1
	query.hit_from_inside = true

	var result := space.intersect_ray(query)
	if result.is_empty():
		return

	var hit: Vector3 = result["position"]
	is_flying = false
	is_attached = true
	anchor = hit
	rope_len = _player.global_position.distance_to(hit)
	_line.visible = true
	hooked.emit(hit)


func _tick_flight(delta: float) -> void:
	var dist: float = _fly_start.distance_to(_fly_target)
	if dist <= 0.001:
		return

	_fly_progress += delta * hook_speed / dist

	if _fly_progress >= 1.0:
		is_flying = false
		_on_hook_reach_target()
		return

	var lateral := Vector3(_input_dir.x, 0.0, _input_dir.y) * lateral_curve
	_fly_curve += lateral * delta


func _on_hook_reach_target() -> void:
	var target: Vector3 = _fly_target + _fly_curve
	is_attached = true
	anchor = target
	rope_len = _player.global_position.distance_to(target)
	_line.visible = true
	hooked.emit(target)


func _tick_pendulum(delta: float) -> void:
	var to_anchor: Vector3 = anchor - _player.global_position
	var dist: float = to_anchor.length()
	var dir: Vector3 = to_anchor / dist

	if dist < min_rope_length:
		release("too_close")
		return

	if dist > max_rope_length * 1.1:
		release("too_far")
		return

	var diff: float = dist - rope_len
	_player.velocity += dir * diff * rope_stiffness * delta

	var gravity: float = absf(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_player.velocity += Vector3.DOWN * gravity * delta

	var lateral := Vector3(_input_dir.x, 0.0, _input_dir.y) * swing_strength
	lateral -= lateral.dot(dir) * dir
	_player.velocity += lateral * delta

	_player.move_and_slide()

	to_anchor = anchor - _player.global_position
	dist = to_anchor.length()
	if dist > rope_len:
		_player.global_position = anchor - to_anchor.normalized() * rope_len


func _draw_rope() -> void:
	if _line_mesh == null or _player == null:
		return

	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_line_mesh.surface_add_vertex(anchor)
	_line_mesh.surface_add_vertex(_player.global_position + Vector3.UP * 0.5)
	_line_mesh.surface_end()
