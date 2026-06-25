class_name Teleport
extends Node

signal teleported(position: Vector3)
signal cancelled

@export var max_distance: float = 14.0
@export var cooldown: float = 8.0

var is_charging: bool = false
var is_on_cooldown: bool = false
var target_position: Vector3 = Vector3.ZERO

var _player: CharacterBody3D = null
var _cool_timer: float = 0.0
var _indicator: Node3D = null
var _ring_material: StandardMaterial3D = null


func setup(player: CharacterBody3D) -> void:
	_player = player
	_build_indicator()


func _build_indicator() -> void:
	_ring_material = StandardMaterial3D.new()
	_ring_material.albedo_color = Color(0.2, 0.6, 1.0, 0.4)
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_indicator = Node3D.new()
	_indicator.name = "TeleportIndicator"
	_indicator.visible = false
	add_child(_indicator)

	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.8
	ring_mesh.bottom_radius = 0.8
	ring_mesh.height = 0.05
	ring.mesh = ring_mesh
	ring.material_override = _ring_material
	_indicator.add_child(ring)

	var arrow := MeshInstance3D.new()
	arrow.name = "Arrow"
	var arrow_mesh := BoxMesh.new()
	arrow_mesh.size = Vector3(0.4, 0.05, 0.6)
	arrow.mesh = arrow_mesh
	arrow.material_override = _ring_material
	arrow.position.z = 0.8
	_indicator.add_child(arrow)


func fire(camera_position: Vector3, camera_forward: Vector3) -> void:
	if _cool_timer > 0.0 or is_charging or _player == null:
		return

	is_charging = true
	_indicator.visible = true
	_update_target(camera_position, camera_forward)


func _update_target(cam_pos: Vector3, cam_fwd: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	if space == null:
		return

	var from: Vector3 = cam_pos
	var to: Vector3 = from + cam_fwd * max_distance

	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1
	query.hit_from_inside = true

	var result: Dictionary = space.intersect_ray(query)

	var flat_fwd: Vector3 = Vector3(cam_fwd.x, 0.0, cam_fwd.z).normalized()
	if result.is_empty():
		target_position = from + cam_fwd * max_distance
	else:
		target_position = result["position"] + Vector3.UP * 0.5
		if target_position.distance_squared_to(_player.global_position) < 0.25:
			target_position = _player.global_position + flat_fwd * 2.0

	_indicator.global_position = target_position
	_indicator.global_basis = Basis.looking_at(flat_fwd, Vector3.UP)


func release() -> void:
	if not is_charging or _player == null:
		return

	is_charging = false
	_indicator.visible = false

	_player.global_position = target_position
	_player.velocity = Vector3.ZERO
	_cool_timer = cooldown
	is_on_cooldown = true
	teleported.emit(target_position)


func cancel() -> void:
	if not is_charging:
		return
	is_charging = false
	_indicator.visible = false
	cancelled.emit()


func _process(delta: float) -> void:
	if _cool_timer > 0.0:
		_cool_timer -= delta
		if _cool_timer <= 0.0:
			is_on_cooldown = false
