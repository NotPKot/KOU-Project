class_name Katana
extends Node

const PARRY_DURATION: float = 1.0
const PARRY_COOLDOWN: float = 2.0
const STUN_EFFECT := preload("res://scripts/status_effects/stun_effect.gd")

var is_parrying: bool = false
var _player: CharacterBody3D = null
var _parry_cooldown: float = 0.0
var _katana_mesh: MeshInstance3D = null


func equip(player: CharacterBody3D) -> void:
	_player = player
	_build_visual()


func _build_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.85, 0.7, 1.0)
	mat.metallic = 0.6
	mat.roughness = 0.3

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.7, 0.02)

	_katana_mesh = MeshInstance3D.new()
	_katana_mesh.mesh = mesh
	_katana_mesh.material_override = mat
	_katana_mesh.position = Vector3(0.4, -0.3, -0.6)
	add_child(_katana_mesh)


func _process(delta: float) -> void:
	if _parry_cooldown > 0.0:
		_parry_cooldown = maxf(_parry_cooldown - delta, 0.0)


func on_mouse_button(button: int) -> bool:
	match button:
		MOUSE_BUTTON_RIGHT:
			_activate_parry()
			return true
		_:
			return false


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
		var stun := STUN_EFFECT.new(2.0)
		hitter.apply_effect(stun)

	if _katana_mesh != null and is_instance_valid(_katana_mesh):
		_katana_mesh.material_override.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		await get_tree().create_timer(0.12).timeout
		if is_instance_valid(_katana_mesh):
			_katana_mesh.material_override.albedo_color = Color(0.9, 0.85, 0.7, 1.0)
