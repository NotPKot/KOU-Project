extends ProgressBar

var _player: Node = null


func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
	if _player == null:
		return
	value = _player.hp
	max_value = _player.max_hp
