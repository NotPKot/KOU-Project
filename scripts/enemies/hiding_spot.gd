extends Marker3D
class_name HidingSpot

@export var radius: float = 2.0

var occupied: bool = false

func _ready() -> void:
	add_to_group("hiding_spots")
