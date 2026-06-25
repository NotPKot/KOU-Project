extends Area3D

@export var hover_height: float = 0.18
@export var hover_speed: float = 2.2
@export var spin_speed: float = 1.4

@onready var _visual: Node3D = $Visual

var _base_visual_y: float = 0.0
var _time: float = 0.0
var _consumed: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_base_visual_y = _visual.position.y


func _process(delta: float) -> void:
	if _consumed:
		return

	_time += delta
	_visual.position.y = _base_visual_y + sin(_time * hover_speed) * hover_height
	_visual.rotate_y(spin_speed * delta)


func _on_body_entered(body: Node3D) -> void:
	if _consumed:
		return

	if not body.has_method("enable_jump"):
		return

	body.enable_jump()
	_consumed = true
	_visual.visible = false
	monitoring = false
