extends Control

@export var crosshair_color: Color = Color.WHITE
@export var gap: float = 4.0
@export var length: float = 10.0
@export var thickness: float = 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	var half := thickness / 2.0

	var top_rect := Rect2(c.x - half, c.y - gap - length, thickness, length)
	var bottom_rect := Rect2(c.x - half, c.y + gap, thickness, length)
	var left_rect := Rect2(c.x - gap - length, c.y - half, length, thickness)
	var right_rect := Rect2(c.x + gap, c.y - half, length, thickness)

	draw_rect(top_rect, crosshair_color)
	draw_rect(bottom_rect, crosshair_color)
	draw_rect(left_rect, crosshair_color)
	draw_rect(right_rect, crosshair_color)

	draw_circle(c, 1.5, crosshair_color)
