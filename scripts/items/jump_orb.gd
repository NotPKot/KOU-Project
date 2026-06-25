extends Area3D

@export var hover_height: float = 0.18
@export var hover_speed: float = 2.2
@export var spin_speed: float = 1.4
@export var respawn_time: float = 3.0

@onready var _visual: Node3D = $Visual

var _base_visual_y: float = 0.0
var _time: float = 0.0
var _cooldown: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_base_visual_y = _visual.position.y


func _process(delta: float) -> void:
	_time += delta
	_visual.position.y = _base_visual_y + sin(_time * hover_speed) * hover_height
	_visual.rotate_y(spin_speed * delta)

	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0:
			monitoring = true
			_visual.visible = true


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("apply_temporal_impulse"):
		return

	body.apply_temporal_impulse()
	monitoring = false
	_visual.visible = false
	_cooldown = respawn_time
