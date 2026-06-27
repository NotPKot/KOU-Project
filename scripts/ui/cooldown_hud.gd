extends Control

@onready var _hbox: HBoxContainer = $HBox

var _player: Node = null
var _icons: Dictionary = {}
var _order: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
	if _player == null or not _player.has_method("get_cooldowns"):
		return

	var current := _player.get_cooldowns() as Array[Dictionary]
	var current_ids: Array[String] = []
	for cd in current:
		var sid: String = str(cd.get("id", ""))
		current_ids.append(sid)

		var total: float = float(cd.get("total", 0.0))
		var remaining: float = float(cd.get("remaining", 0.0))

		if not _icons.has(sid):
			_add_icon(sid)

		_icons[sid].set_cooldown(total, remaining)

	_remove_stale_icons(current_ids)


func _add_icon(sid: String) -> void:
	var icon := preload("res://scenes/ui/CooldownIcon.tscn").instantiate()
	icon.skill_id = sid
	_hbox.add_child(icon)
	_icons[sid] = icon
	_order.append(sid)


func _remove_stale_icons(current_ids: Array[String]) -> void:
	var stale: Array[String] = []
	for sid in _icons.keys():
		if sid not in current_ids:
			stale.append(sid)

	for sid in stale:
		var icon := _icons[sid] as Control
		if icon != null:
			icon.queue_free()
		_icons.erase(sid)
		_order.erase(sid)
