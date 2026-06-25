extends Node3D

@export_group("Slash Visual")
@export var lifetime: float = 0.18
@export var arc_degrees: float = 96.0
@export var segment_count: int = 8
@export var inner_radius: float = 0.45
@export var outer_radius: float = 1.55
@export var vertical_tilt_degrees: float = -8.0
@export var slash_color: Color = Color(0.58, 0.95, 1.0, 0.86)
@export var core_color: Color = Color(1.0, 1.0, 1.0, 0.95)

@export_group("Damage")
@export var damage: int = 10

@export_group("Particles And Flash")
@export var particle_amount: int = 14
@export var flash_energy: float = 1.8
@export var flash_range: float = 2.4

@onready var _arc_mesh: MeshInstance3D = $ArcMesh
@onready var _core_mesh: MeshInstance3D = $CoreMesh
@onready var _particles: GPUParticles3D = $SlashParticles
@onready var _flash: OmniLight3D = $Flash
@onready var _hitbox: Area3D = $Hitbox

var _age: float = 0.0
var _base_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	_base_scale = scale
	_build_arc_meshes()
	_configure_particles()
	_flash.light_energy = flash_energy
	_flash.omni_range = flash_range
	_hitbox.body_entered.connect(_on_hit)


func setup(slash_range: float, height: float, yaw_radians: float, roll_radians: float, scale_multiplier: float) -> void:
	position.y += height
	rotation = Vector3(deg_to_rad(vertical_tilt_degrees), yaw_radians, roll_radians)
	scale = Vector3.ONE * scale_multiplier
	_base_scale = scale
	outer_radius = slash_range
	inner_radius = slash_range * 0.34

	if is_node_ready():
		_build_arc_meshes()


func _process(delta: float) -> void:
	_age += delta
	var progress: float = clampf(_age / lifetime, 0.0, 1.0)
	var fade: float = 1.0 - progress
	scale = _base_scale * (1.0 + progress * 0.18)
	_flash.light_energy = flash_energy * fade
	_set_material_alpha(_arc_mesh, slash_color.a * fade)
	_set_material_alpha(_core_mesh, core_color.a * fade)

	if _age >= lifetime:
		queue_free()


func _build_arc_meshes() -> void:
	_arc_mesh.mesh = _build_arc_mesh(inner_radius, outer_radius, arc_degrees, segment_count)
	_core_mesh.mesh = _build_arc_mesh(inner_radius * 1.35, outer_radius * 0.92, arc_degrees * 0.72, maxi(4, segment_count - 2))
	_arc_mesh.material_override = _make_material(slash_color)
	_core_mesh.material_override = _make_material(core_color)


func _build_arc_mesh(inner: float, outer: float, degrees: float, segments: int) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var half_angle: float = deg_to_rad(degrees) * 0.5

	for index in range(segments + 1):
		var t: float = float(index) / float(segments)
		var angle: float = lerpf(-half_angle, half_angle, t)
		var direction: Vector3 = Vector3(sin(angle), 0.0, -cos(angle))
		vertices.append(direction * inner)
		vertices.append(direction * outer)

	for index in range(segments):
		var base: int = index * 2
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.85
	return material


func _set_material_alpha(mesh_instance: MeshInstance3D, alpha: float) -> void:
	var material := mesh_instance.material_override as StandardMaterial3D
	if material == null:
		return

	var color: Color = material.albedo_color
	color.a = alpha
	material.albedo_color = color


func _configure_particles() -> void:
	_particles.amount = particle_amount
	_particles.lifetime = lifetime * 1.35
	_particles.one_shot = true
	_particles.explosiveness = 0.85
	_particles.emitting = true


func _on_hit(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
