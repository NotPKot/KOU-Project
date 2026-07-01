extends Node3D


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("EnemiesManager: no se encontró un nodo en el grupo 'player'")
		return

	for child in get_children():
		if child.has_method("set_target"):
			child.set_target(player)
