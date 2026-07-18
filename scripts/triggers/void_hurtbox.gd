extends Area3D

@export var damage_ratio: float = 0.4
@export var respawn_position: Vector3 = Vector3(0, 1, 0)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if not body.has_method("take_damage"):
		return

	var max_hp: int = body.get("max_hp")
	if max_hp <= 0:
		return

	var damage: int = ceili(float(max_hp) * damage_ratio)
	body.take_damage(damage)
	body.global_position = respawn_position
	body.velocity = Vector3.ZERO
