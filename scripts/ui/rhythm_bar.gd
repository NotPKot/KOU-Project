class_name RhythmBar
extends Control

signal beat_landed

@export var bar_color: Color = Color(0.9, 0.9, 0.95, 0.85)
@export var dot_color: Color = Color(1.0, 0.6, 0.0)
@export var perfect_color: Color = Color(0.3, 1.0, 0.3)
@export var miss_color: Color = Color(1.0, 0.2, 0.2)
@export var bar_width: float = 80.0
@export var bar_height: float = 18.0
@export var dot_radius: float = 6.0

var beat_period: float = 0.5

var _phase: float = 0.0
var _running: bool = false
var _flash_color: Color = Color.TRANSPARENT
var _flash_duration: float = 0.0
var _flash_elapsed: float = 0.0
var _pulse_scale: float = 1.0


func start(period: float) -> void:
	beat_period = maxf(period, 0.05)
	_phase = 0.0
	_running = true
	_flash_color = Color.TRANSPARENT
	queue_redraw()


func stop() -> void:
	_running = false


func flash_hit(is_perfect: bool) -> void:
	_flash_color = perfect_color if is_perfect else miss_color
	_flash_duration = 0.15
	_flash_elapsed = 0.0


func _process(delta: float) -> void:
	if not _running:
		return

	_phase += delta / beat_period
	if _phase >= 1.0:
		_phase -= 1.0
		_pulse_scale = 1.6
		beat_landed.emit()

	_pulse_scale = lerp(_pulse_scale, 1.0, delta * 12.0)

	if _flash_elapsed < _flash_duration:
		_flash_elapsed += delta
		if _flash_elapsed >= _flash_duration:
			_flash_color = Color.TRANSPARENT

	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = w / 2.0
	var cy: float = h / 2.0
	var progress: float = _phase
	var half_h: float = bar_height / 2.0

	var draw_color: Color = bar_color
	if _flash_color.a > 0.0:
		var t: float = _flash_elapsed / _flash_duration
		draw_color = draw_color.lerp(_flash_color, 1.0 - t * t)

	var left_x: float = lerp(0.0, cx - bar_width, progress)
	var right_x: float = lerp(w - bar_width, cx, progress)

	draw_rect(Rect2(left_x, cy - half_h, bar_width, bar_height), draw_color)
	draw_rect(Rect2(right_x, cy - half_h, bar_width, bar_height), draw_color)

	var dot_actual_radius: float = dot_radius * _pulse_scale
	draw_circle(Vector2(cx, cy), dot_actual_radius, dot_color)
