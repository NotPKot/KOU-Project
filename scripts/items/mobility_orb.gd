extends Area3D

@export var consume_after_choice: bool = true
@export var hover_height: float = 0.18
@export var hover_speed: float = 2.2
@export var spin_speed: float = 1.4

@onready var _visual: Node3D = $Visual

var _is_open: bool = false
var _base_visual_y: float = 0.0
var _time: float = 0.0
var _target: Node = null

const CHOICES: Array[Dictionary] = [
	{"id": "dash", "label": "Dash", "description": "Desplazamiento rapido en la direccion que miras. Cooldown 2.5s."},
	{"id": "grappling_hook", "label": "Gancho", "description": "Balanceo con curva y pendulo. Dominio avanzado."},
	{"id": "teleport", "label": "Teletransporte", "description": "Marca destino mientras sostienes Shift, tp al soltar. Cooldown 8s."},
]

const CHOICE_PANEL_SCENE := preload("res://scenes/ui/ChoicePanel.tscn")


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_base_visual_y = _visual.position.y


func _process(delta: float) -> void:
	_time += delta
	_visual.position.y = _base_visual_y + sin(_time * hover_speed) * hover_height
	_visual.rotate_y(spin_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if _is_open:
		return

	if not body.has_method("set_mobility_skill"):
		return

	_is_open = true
	_target = body
	monitoring = false

	if body.has_method("set_input_locked"):
		body.set_input_locked(true)

	var panel := CHOICE_PANEL_SCENE.instantiate()
	get_tree().current_scene.add_child(panel)
	panel.choice_selected.connect(_on_choice_selected)
	panel.open(CHOICES, body)


func _on_choice_selected(choice_id: StringName) -> void:
	if _target != null:
		if _target.has_method("set_mobility_skill"):
			_target.set_mobility_skill(choice_id)
		if _target.has_method("set_input_locked"):
			_target.set_input_locked(false)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if consume_after_choice:
		queue_free()
	else:
		_is_open = false
		monitoring = true
