class_name Katana
extends Node

const PARRY_DURATION: float = 1.0
const PARRY_COOLDOWN: float = 2.0
const ARC_SEGMENTS: int = 10
const HIT_IMPACT_SCENE := preload("res://scenes/effects/combat/HitImpact.tscn")
const CLEAVE_DAMAGE_MULTIPLIER: float = 0.7
const SWING_IDLE: int = 0
const SWING_SAMPLING: int = 1
const SWING_ACTIVE: int = 2
const SWING_RECOVERING: int = 3

@export_group("Expansion Tech")
@export var max_camera_vel_deg_per_sec: float = 180.0
@export var sample_window_ms: float = 110.0

@export_group("Swing")
@export var swing_damage: int = 8
@export var swing_cooldown: float = 0.32
@export var active_hit_window_ms: float = 90.0
@export var recovery_window_ms: float = 110.0
@export var arc_degrees_rest: float = 65.0
@export var arc_degrees_max: float = 130.0
@export var arc_range_rest: float = 2.4
@export var arc_range_max: float = 2.7
@export var arc_inner_radius: float = 0.72
@export var vertical_tilt_degrees: float = -5.0
@export var katana_debug_enabled: bool = false

var is_parrying: bool = false
var _player: CharacterBody3D = null
var _parry_cooldown: float = 0.0
var _katana_mesh: MeshInstance3D = null
var _swing_cooldown: float = 0.0
var _mesh_mat: StandardMaterial3D = null

var _last_camera_basis: Basis
var _velocity_samples: Array[Dictionary] = []
var _swing_state: int = SWING_IDLE
var _swing_start_msec: float = 0.0
var _active_start_msec: float = 0.0
var _swing_slash_arc: Node3D = null
var _hitbox_container: Node3D = null
var _hitbox_area: Area3D = null
var _hitbox_shape: CollisionShape3D = null
var _hitbox_box_shape: BoxShape3D = null
var _base_hitbox_scale: Vector3
var _camera: Camera3D = null
var _camera_pivot: Node3D = null
var _hit_bodies: Array[Node] = []
var _cleave_active: bool = false


func unequip() -> void:
	if _katana_mesh != null and _katana_mesh.get_parent() != null:
		_katana_mesh.queue_free()
		_katana_mesh = null
	if _hitbox_container != null and _hitbox_container.get_parent() != null:
		_hitbox_container.queue_free()
		_hitbox_container = null


func equip(player: CharacterBody3D) -> void:
	_player = player
	_camera = player.get_node("CameraPivot/Camera3D") as Camera3D
	_camera_pivot = player.get_node("CameraPivot") as Node3D
	_build_visual()
	_build_hitbox()


func _build_hitbox() -> void:
	_hitbox_container = Node3D.new()
	_hitbox_container.name = "HitboxPivot"
	_camera_pivot.add_child(_hitbox_container)

	_hitbox_area = Area3D.new()
	_hitbox_area.name = "HitboxArea"
	_hitbox_area.collision_mask = 2
	_hitbox_area.monitoring = false
	_hitbox_area.position = Vector3(0, 0, -1.4)
	_hitbox_container.add_child(_hitbox_area)

	_hitbox_shape = CollisionShape3D.new()
	_hitbox_shape.name = "HitShape"
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.0, 2.0)
	_hitbox_box_shape = box
	_hitbox_shape.shape = box
	_hitbox_area.add_child(_hitbox_shape)

	_hitbox_area.body_entered.connect(_on_hitbox_entered)

	_base_hitbox_scale = _hitbox_container.scale


func _build_visual() -> void:
	_mesh_mat = StandardMaterial3D.new()
	_mesh_mat.albedo_color = Color(0.9, 0.85, 0.7, 1.0)
	_mesh_mat.metallic = 0.6
	_mesh_mat.roughness = 0.3

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 1.8, 0.03)

	_katana_mesh = MeshInstance3D.new()
	_katana_mesh.mesh = mesh
	_katana_mesh.material_override = _mesh_mat
	_katana_mesh.position = Vector3(0.35, -0.25, -1.2)
	_katana_mesh.rotation.x = deg_to_rad(-45)
	_camera_pivot.add_child(_katana_mesh)


func _process(delta: float) -> void:
	if _parry_cooldown > 0.0:
		_parry_cooldown = maxf(_parry_cooldown - delta, 0.0)
	if _swing_cooldown > 0.0:
		_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)

	match _swing_state:
		SWING_SAMPLING:
			_sample_camera_velocity(delta)
			if Time.get_ticks_msec() - _swing_start_msec >= sample_window_ms:
				_execute_cut()
		SWING_ACTIVE:
			if Time.get_ticks_msec() - _active_start_msec >= active_hit_window_ms:
				_begin_recovery()
		SWING_RECOVERING:
			if Time.get_ticks_msec() - _active_start_msec >= active_hit_window_ms + recovery_window_ms:
				_reset_swing()


func _sample_camera_velocity(delta: float) -> void:
	var current: Basis = _camera.global_transform.basis
	var angle_rad: float = _last_camera_basis.get_rotation_quaternion().angle_to(
		current.get_rotation_quaternion()
	)
	_last_camera_basis = current

	if delta > 0.0:
		var vel_deg: float = rad_to_deg(angle_rad) / delta
		_velocity_samples.append({"time": Time.get_ticks_msec(), "velocity": vel_deg})
	_trim_old_samples()


func _trim_old_samples() -> void:
	var now: float = Time.get_ticks_msec()
	while _velocity_samples.size() > 0 and (now - _velocity_samples[0]["time"]) > sample_window_ms:
		_velocity_samples.pop_front()


func _average_sampled_velocity() -> float:
	if _velocity_samples.is_empty():
		return 0.0
	var sum: float = 0.0
	for s in _velocity_samples:
		sum += s["velocity"]
	return sum / _velocity_samples.size()


func _compute_normalized_camera_speed(velocity: float) -> float:
	return clampf(velocity / max_camera_vel_deg_per_sec, 0.0, 1.0)


func on_mouse_button(button: int) -> bool:
	match button:
		MOUSE_BUTTON_LEFT:
			_basic_attack()
			return true
		MOUSE_BUTTON_RIGHT:
			_activate_parry()
			return true
		_:
			return false


func _basic_attack() -> void:
	if _swing_cooldown > 0.0 or _swing_state != SWING_IDLE:
		return

	_swing_cooldown = swing_cooldown

	_hitbox_container.scale = _base_hitbox_scale
	_hitbox_area.monitoring = false

	_velocity_samples.clear()
	_last_camera_basis = _camera.global_transform.basis
	_hit_bodies.clear()

	_swing_start_msec = Time.get_ticks_msec()
	_swing_state = SWING_SAMPLING

	if _swing_slash_arc != null and is_instance_valid(_swing_slash_arc):
		_swing_slash_arc.queue_free()

	var swing_mat := StandardMaterial3D.new()
	swing_mat.albedo_color = Color(0.95, 0.9, 0.75, 1.0)
	swing_mat.metallic = 0.7
	swing_mat.roughness = 0.2

	if _katana_mesh != null and is_instance_valid(_katana_mesh):
		_katana_mesh.material_override = swing_mat
		var swing_tween := create_tween().set_parallel(true)
		swing_tween.tween_property(_katana_mesh, "rotation:x", deg_to_rad(-72), sample_window_ms * 0.001).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		swing_tween.tween_property(_katana_mesh, "rotation:z", deg_to_rad(-22), sample_window_ms * 0.001).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		swing_tween.tween_property(swing_mat, "albedo_color:g", 0.6, 0.04)


func _execute_cut() -> void:
	_swing_state = SWING_ACTIVE
	_active_start_msec = Time.get_ticks_msec()

	var avg_vel: float = _average_sampled_velocity()
	var t: float = _compute_normalized_camera_speed(avg_vel)

	var arc_deg: float = lerpf(arc_degrees_rest, arc_degrees_max, t)
	var arc_range: float = lerpf(arc_range_rest, arc_range_max, t)
	_hitbox_area.position.z = lerpf(-1.4, -1.7, t)
	var half_rad: float = deg_to_rad(arc_deg * 0.5)
	var arc_width: float = 2.0 * arc_range * sin(half_rad)
	_hitbox_box_shape.size.x = arc_width
	_hitbox_box_shape.size.z = arc_range
	_hitbox_area.monitoring = true
	_cleave_active = t > 0.01
	_hit_bodies.clear()

	if _katana_mesh != null and is_instance_valid(_katana_mesh):
		var mesh_scale: float = lerpf(1.0, arc_range / arc_range_rest, t)
		_katana_mesh.scale = Vector3(1, 1, 1) * mesh_scale
		var cut_tween := create_tween().set_parallel(true)
		cut_tween.tween_property(_katana_mesh, "rotation:x", deg_to_rad(18), 0.045).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		cut_tween.tween_property(_katana_mesh, "rotation:z", deg_to_rad(36), 0.045).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	_swing_slash_arc = _spawn_slash_arc(arc_deg, arc_range)
	var fade_tween := create_tween().set_parallel(true)
	fade_tween.tween_property(_swing_slash_arc, "scale", Vector3.ONE * 1.1, 0.12).set_trans(Tween.TRANS_SINE)
	var mat := _swing_slash_arc.get_node("ArcMesh").material_override as StandardMaterial3D
	if mat != null:
		fade_tween.tween_property(mat, "albedo_color:a", 0.0, 0.16)
	fade_tween.tween_callback(_free_current_slash_arc).set_delay(0.2)

	if t > 0.05 and is_instance_valid(_mesh_mat):
		var c: Color = Color(0.85, 0.7, 0.5, 1.0).lerp(Color(0.95, 0.5, 0.2, 1.0), t * 0.4)
		_mesh_mat.albedo_color = c

	_print_katana_debug("cut", avg_vel, t)
	call_deferred("_damage_current_overlaps")


func _begin_recovery() -> void:
	_swing_state = SWING_RECOVERING
	_hitbox_area.monitoring = false

	if _katana_mesh != null and is_instance_valid(_katana_mesh):
		var reset := create_tween().set_parallel(true)
		reset.tween_property(_katana_mesh, "rotation:x", deg_to_rad(-45), recovery_window_ms * 0.001).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		reset.tween_property(_katana_mesh, "rotation:z", 0.0, recovery_window_ms * 0.001).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		reset.tween_property(_katana_mesh, "material_override:albedo_color", Color(0.9, 0.85, 0.7, 1.0), 0.08)


func _reset_swing() -> void:
	_swing_state = SWING_IDLE
	_hitbox_container.scale = _base_hitbox_scale
	if _katana_mesh != null and is_instance_valid(_katana_mesh):
		_katana_mesh.scale = Vector3.ONE


func _free_current_slash_arc() -> void:
	if _swing_slash_arc != null and is_instance_valid(_swing_slash_arc):
		_swing_slash_arc.queue_free()
	_swing_slash_arc = null


func _spawn_slash_arc(degrees: float, outer_radius: float) -> Node3D:
	var container := Node3D.new()
	container.name = "SlashArc"
	var arc_mesh := MeshInstance3D.new()
	arc_mesh.name = "ArcMesh"

	var inner: float = arc_inner_radius * (outer_radius / arc_range_rest)
	var outer: float = outer_radius
	arc_mesh.mesh = _build_arc_mesh(inner, outer, degrees, ARC_SEGMENTS)

	var color := Color(0.95, 0.85, 0.6, 0.7)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.emission_energy_multiplier = 0.6
	arc_mesh.material_override = mat

	container.add_child(arc_mesh)
	container.position = Vector3(0, -0.15, -1.2)
	container.rotation.x = deg_to_rad(vertical_tilt_degrees)
	_camera_pivot.add_child(container)
	return container


func _build_arc_mesh(inner: float, outer: float, degrees: float, segments: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var half_angle: float = deg_to_rad(degrees) * 0.5

	for index in range(segments + 1):
		var t: float = float(index) / float(segments)
		var angle: float = lerpf(-half_angle, half_angle, t)
		var dir: Vector3 = Vector3(sin(angle), 0.0, -cos(angle))
		vertices.append(dir * inner)
		vertices.append(dir * outer)

	for index in range(segments):
		var base: int = index * 2
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _on_hitbox_entered(body: Node) -> void:
	_damage_body(body)


func _damage_current_overlaps() -> void:
	if _hitbox_area == null or not is_instance_valid(_hitbox_area):
		return
	for body in _hitbox_area.get_overlapping_bodies():
		_damage_body(body)


func _damage_body(body: Node) -> void:
	if body == null or not body.has_method("take_damage"):
		return
	if body == _player:
		return
	if _hit_bodies.has(body):
		return

	var is_first_hit: bool = _hit_bodies.is_empty()
	_hit_bodies.append(body)

	var damage: int = swing_damage
	if not is_first_hit and _cleave_active:
		damage = max(1, roundi(swing_damage * CLEAVE_DAMAGE_MULTIPLIER))

	body.take_damage(damage)
	_print_katana_debug("hit", 0.0, float(damage))

	if body.has_method("apply_knockback"):
		var dir := (_camera.global_transform.basis * Vector3(0, 0, -1)).normalized()
		body.apply_knockback(dir * Vector3(1, 0.3, 1), 5.0)

	_spawn_hit_impact(body as Node3D)


func _spawn_hit_impact(body_node: Node3D) -> void:
	if body_node == null:
		return
	var impact := HIT_IMPACT_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(impact)
	impact.global_position = body_node.global_position + Vector3(0, 0.8, 0)
	var particles := impact.get_node("Particles") as GPUParticles3D
	if particles != null:
		particles.emitting = true
	var flash := impact.get_node("Flash") as OmniLight3D
	if flash != null:
		var tween := create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.25)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	impact.add_child(timer)
	timer.start()
	timer.timeout.connect(impact.queue_free)


func _print_katana_debug(event_name: String, sampled_velocity: float, expansion: float) -> void:
	if not katana_debug_enabled:
		return

	print(
		"[KATANA_DEBUG] ",
		"event=", event_name,
		" sampled_velocity=", snappedf(sampled_velocity, 0.01),
		" expansion=", snappedf(expansion, 0.001),
		" hits=", _hit_bodies.size(),
		" state=", _swing_state
	)


func _activate_parry() -> void:
	if _parry_cooldown > 0.0:
		return
	is_parrying = true
	_player.set_parry_window(PARRY_DURATION)
	_parry_cooldown = PARRY_COOLDOWN + PARRY_DURATION

	if _katana_mesh != null:
		_katana_mesh.material_override.albedo_color = Color(0.4, 0.8, 1.0, 1.0)

	await get_tree().create_timer(PARRY_DURATION).timeout
	is_parrying = false

	if _katana_mesh != null and is_instance_valid(_katana_mesh):
		_katana_mesh.material_override.albedo_color = Color(0.9, 0.85, 0.7, 1.0)


func on_parry_hit(hitter: Node) -> void:
	if hitter != null and hitter.has_method("apply_effect"):
		hitter.apply_effect("stun", 0.75)

	if _katana_mesh != null and is_instance_valid(_katana_mesh):
		_katana_mesh.material_override.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		await get_tree().create_timer(0.12).timeout
		if is_instance_valid(_katana_mesh):
			_katana_mesh.material_override.albedo_color = Color(0.9, 0.85, 0.7, 1.0)
