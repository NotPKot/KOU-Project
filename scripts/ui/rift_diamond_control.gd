extends Control

const CENTER_DEADZONE := 28.0

var highlighted_direction: String = ""
var selected_sequence: PackedStringArray = PackedStringArray()
var cursor_offset: Vector2 = Vector2.ZERO
var _font: Font
var _arrow_font_size: int = 34
var _seq_font_size: int = 22


func _ready() -> void:
	custom_minimum_size = Vector2(320, 320)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func set_rift_state(direction: String, sequence: PackedStringArray, offset: Vector2) -> void:
	highlighted_direction = direction
	selected_sequence = sequence
	cursor_offset = offset
	queue_redraw()


func clear() -> void:
	highlighted_direction = ""
	selected_sequence = PackedStringArray()
	cursor_offset = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var center: Vector2 = rect.get_center()
	var radius: float = minf(size.x, size.y) * 0.43
	var top: Vector2 = center + Vector2(0.0, -radius)
	var right: Vector2 = center + Vector2(radius, 0.0)
	var bottom: Vector2 = center + Vector2(0.0, radius)
	var left: Vector2 = center + Vector2(-radius, 0.0)
	var top_right_mid: Vector2 = (top + right) * 0.5
	var bottom_right_mid: Vector2 = (right + bottom) * 0.5
	var bottom_left_mid: Vector2 = (bottom + left) * 0.5
	var top_left_mid: Vector2 = (left + top) * 0.5
	var inner_radius: float = CENTER_DEADZONE

	var base_color: Color = Color(0.06, 0.08, 0.1, 0.86)
	var line_color: Color = Color(0.5, 0.82, 0.92, 0.95)
	var glow_color: Color = Color(0.38, 0.88, 1.0, 0.72)

	_draw_sector("up", PackedVector2Array([top, top_right_mid, center, top_left_mid]), base_color, glow_color)
	_draw_sector("right", PackedVector2Array([right, bottom_right_mid, center, top_right_mid]), base_color, glow_color)
	_draw_sector("down", PackedVector2Array([bottom, bottom_left_mid, center, bottom_right_mid]), base_color, glow_color)
	_draw_sector("left", PackedVector2Array([left, top_left_mid, center, bottom_left_mid]), base_color, glow_color)

	draw_polyline(PackedVector2Array([top, right, bottom, left, top]), line_color, 3.0, true)
	draw_line(top_left_mid, bottom_right_mid, Color(0.5, 0.82, 0.92, 0.42), 2.0)
	draw_line(top_right_mid, bottom_left_mid, Color(0.5, 0.82, 0.92, 0.42), 2.0)

	draw_circle(center, inner_radius, Color(0.01, 0.015, 0.02, 0.92))
	draw_arc(center, inner_radius, 0.0, TAU, 32, line_color, 2.0)
	draw_circle(center + cursor_offset, 6.0, Color(0.93, 0.98, 1.0, 1.0))

	_draw_arrow("^", center + Vector2(0.0, -radius * 0.53))
	_draw_arrow(">", center + Vector2(radius * 0.53, 0.0))
	_draw_arrow("v", center + Vector2(0.0, radius * 0.53))
	_draw_arrow("<", center + Vector2(-radius * 0.53, 0.0))
	_draw_sequence(center + Vector2(0.0, radius + 24.0))


func _draw_sector(direction: String, points: PackedVector2Array, base_color: Color, glow_color: Color) -> void:
	var color: Color = glow_color if highlighted_direction == direction else base_color
	draw_colored_polygon(points, color)


func _draw_arrow(text: String, position: Vector2) -> void:
	var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _arrow_font_size)
	var color: Color = Color(0.88, 0.96, 1.0, 1.0)
	draw_string(_font, position - text_size * 0.5, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _arrow_font_size, color)


func _draw_sequence(position: Vector2) -> void:
	var text: String = _sequence_to_arrows(selected_sequence)
	if text.is_empty():
		text = "RIFT"

	var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _seq_font_size)
	draw_string(_font, position - Vector2(text_size.x * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _seq_font_size, Color(0.7, 0.95, 1.0, 1.0))


func _sequence_to_arrows(sequence: PackedStringArray) -> String:
	var output := PackedStringArray()
	for direction in sequence:
		match direction:
			"up":
				output.append("^")
			"down":
				output.append("v")
			"left":
				output.append("<")
			"right":
				output.append(">")
	return " ".join(output)
