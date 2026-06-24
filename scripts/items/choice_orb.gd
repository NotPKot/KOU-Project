extends Area3D

@export var choice_panel_scene: PackedScene
@export var choices: Array[Dictionary] = [
	{"id": "katana", "label": "Katana", "description": "Arma rapida de corte."},
	{"id": "hammer", "label": "Martillo", "description": "Golpes pesados y contundentes."},
	{"id": "broken_stopwatch", "label": "Cronometro roto", "description": "Manipulacion inestable del tiempo."},
]
@export var consume_after_choice: bool = true
@export var hover_height: float = 0.18
@export var hover_speed: float = 2.2
@export var spin_speed: float = 1.4

@onready var _visual: Node3D = $Visual

var _is_open: bool = false
var _base_visual_y: float = 0.0
var _time: float = 0.0
var _target: Node = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_base_visual_y = _visual.position.y


func _process(delta: float) -> void:
	_time += delta
	_visual.position.y = _base_visual_y + sin(_time * hover_speed) * hover_height
	_visual.rotate_y(spin_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if _is_open or choice_panel_scene == null:
		return

	if not body.has_method("set_mouse_weapon"):
		return

	_is_open = true
	_target = body
	monitoring = false

	if body.has_method("set_input_locked"):
		body.set_input_locked(true)

	var panel := choice_panel_scene.instantiate()
	get_tree().current_scene.add_child(panel)
	panel.choice_selected.connect(_on_choice_selected)
	panel.open(choices, body)


func _on_choice_selected(_choice_id: StringName) -> void:
	if _target != null and _target.has_method("set_input_locked"):
		_target.set_input_locked(false)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if consume_after_choice:
		queue_free()
	else:
		_is_open = false
		monitoring = true
