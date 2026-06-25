class_name Teleport
extends Node

signal teleported(position: Vector3)
signal cancelled

@export var max_distance: float = 30.0
@export var cooldown: float = 8.0
@export var player_capsule_radius: float = 0.4
@export var player_capsule_height: float = 1.8
@export var player_origin_y_offset: float = 0.0
@export var color_valid:   Color = Color(0.25, 0.70, 1.00, 0.40)
@export var color_invalid: Color = Color(1.00, 0.30, 0.20, 0.35)

var is_charging: bool     = false
var is_on_cooldown: bool  = false
var target_position: Vector3 = Vector3.ZERO

var _player: CharacterBody3D     = null
var _cool_timer: float           = 0.0
var _has_valid_target: bool      = false

var _indicator: Node3D           = null
var _ghost: MeshInstance3D       = null
var _ring: MeshInstance3D        = null
var _mat_ghost: StandardMaterial3D = null
var _mat_ring: StandardMaterial3D  = null
var _aim_query: PhysicsRayQueryParameters3D
var _floor_query: PhysicsRayQueryParameters3D


func setup(player: CharacterBody3D) -> void:
	_player = player
	_aim_query = PhysicsRayQueryParameters3D.new()
	_floor_query = PhysicsRayQueryParameters3D.new()
	_build_indicator()


func fire(camera_position: Vector3, camera_forward: Vector3) -> void:
	if _cool_timer > 0.0 or is_charging or _player == null:
		return
	is_charging = true
	_indicator.visible = true
	update_aim(camera_position, camera_forward)


func update_aim(cam_pos: Vector3, cam_fwd: Vector3) -> void:
	if _player == null:
		return
	var space := _player.get_world_3d().direct_space_state
	if space == null:
		return

	var found_pos: Vector3
	var valid: bool

	_aim_query.from           = cam_pos
	_aim_query.to             = cam_pos + cam_fwd * max_distance
	_aim_query.collision_mask = 1
	_aim_query.exclude        = [_player.get_rid()]
	var hit := space.intersect_ray(_aim_query)

	if hit.is_empty():
		found_pos = _find_floor(cam_pos + cam_fwd * max_distance, space)
		valid     = found_pos != Vector3.ZERO
		if not valid:
			found_pos = cam_pos + cam_fwd * max_distance

	else:
		var normal: Vector3 = hit["normal"]
		var pos: Vector3    = hit["position"]

		if normal.dot(Vector3.UP) > 0.5:
			found_pos = pos
			valid     = true
		else:
			found_pos = _find_floor(pos, space)
			valid     = found_pos != Vector3.ZERO
			if not valid:
				found_pos = pos + normal * (player_capsule_radius + 0.05)

	if valid and found_pos.distance_squared_to(_player.global_position) < 1.0:
		valid = false

	target_position   = found_pos
	_has_valid_target = valid

	_indicator.global_position = target_position
	_set_indicator_colors(valid)


func release() -> void:
	if not is_charging or _player == null:
		return
	is_charging = false
	_indicator.visible = false

	if _has_valid_target:
		_player.global_position = target_position + Vector3.UP * player_origin_y_offset
		_player.velocity        = Vector3.ZERO
		_cool_timer             = cooldown
		is_on_cooldown          = true
		teleported.emit(target_position)
	else:
		cancelled.emit()


func cancel() -> void:
	if not is_charging:
		return
	is_charging = false
	_indicator.visible = false
	cancelled.emit()


func get_cooldown_ratio() -> float:
	return clampf(1.0 - (_cool_timer / cooldown), 0.0, 1.0)


func _process(delta: float) -> void:
	if _cool_timer > 0.0:
		_cool_timer = maxf(_cool_timer - delta, 0.0)
		if _cool_timer == 0.0:
			is_on_cooldown = false


func _find_floor(from_pos: Vector3, space: PhysicsDirectSpaceState3D) -> Vector3:
	_floor_query.from           = from_pos + Vector3.UP * 0.5
	_floor_query.to             = from_pos + Vector3.DOWN * 8.0
	_floor_query.collision_mask = 1
	_floor_query.exclude        = [_player.get_rid()]
	var r := space.intersect_ray(_floor_query)
	if r.is_empty():
		return Vector3.ZERO
	if (r["normal"] as Vector3).dot(Vector3.UP) < 0.5:
		return Vector3.ZERO
	return r["position"]


func _build_indicator() -> void:
	_indicator          = Node3D.new()
	_indicator.name     = "TeleportIndicator"
	_indicator.visible  = false
	add_child(_indicator)

	_mat_ghost                  = StandardMaterial3D.new()
	_mat_ghost.albedo_color     = color_valid
	_mat_ghost.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ghost.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_ghost.cull_mode        = BaseMaterial3D.CULL_DISABLED
	_mat_ghost.depth_draw_mode  = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	_ghost               = MeshInstance3D.new()
	_ghost.name          = "Ghost"
	var capsule          := CapsuleMesh.new()
	capsule.radius        = player_capsule_radius
	capsule.height        = player_capsule_height
	_ghost.mesh           = capsule
	_ghost.material_override = _mat_ghost
	_ghost.position = Vector3(0.0, player_capsule_height * 0.5, 0.0)
	_indicator.add_child(_ghost)

	_mat_ring                  = StandardMaterial3D.new()
	_mat_ring.albedo_color     = color_valid
	_mat_ring.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ring.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_ring.depth_draw_mode  = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	_ring                = MeshInstance3D.new()
	_ring.name           = "Ring"
	var disk             := CylinderMesh.new()
	disk.top_radius       = player_capsule_radius + 0.18
	disk.bottom_radius    = player_capsule_radius + 0.18
	disk.height           = 0.04
	disk.radial_segments  = 32
	disk.rings            = 1
	_ring.mesh            = disk
	_ring.material_override = _mat_ring
	_ring.position = Vector3(0.0, 0.025, 0.0)
	_indicator.add_child(_ring)


func _set_indicator_colors(valid: bool) -> void:
	var c := color_valid if valid else color_invalid
	_mat_ghost.albedo_color = c
	_mat_ring.albedo_color  = Color(c.r, c.g, c.b, minf(c.a * 1.6, 1.0))
