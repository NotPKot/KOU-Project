extends Control

var _player: Node = null
var _hp_target: int = 100
var _hp_shown: float = 100.0
var _max_hp: int = 100
var _chunks: Array[Dictionary] = []
var _shake: Vector2 = Vector2.ZERO
var _punch: float = 1.0
var _heal_sparkles: Array[Dictionary] = []

@export var bar_color: Color = Color(0.2, 0.7, 0.2, 0.85)
@export var drain_color: Color = Color(0.12, 0.12, 0.12, 0.6)
@export var bg_color: Color = Color(0.06, 0.06, 0.06, 0.9)
@export var chunk_color: Color = Color.WHITE
@export var sparkle_color: Color = Color(0.5, 1.0, 0.5)
@export var divider_step: int = 20

var _font: Font = preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
var _font_size: int = 20


func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_hp_target = _player.hp
		_hp_shown = float(_hp_target)
		_max_hp = _player.max_hp


func _process(delta: float) -> void:
	if _player == null:
		return

	var prev_hp = _hp_target
	_hp_target = _player.hp
	_max_hp = _player.max_hp

	if _max_hp <= 0:
		return

	if _hp_target < prev_hp:
		_chunks.append({"value": maxf(_hp_shown, float(_hp_target)), "delay": 0.4})
		_shake = Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		_punch = 1.12

	if _hp_shown > _hp_target:
		_hp_shown = lerpf(_hp_shown, float(_hp_target), 6.0 * delta)
		if _hp_shown - _hp_target < 0.5:
			_hp_shown = float(_hp_target)
	elif _hp_shown < _hp_target:
		_hp_shown = minf(_hp_shown + 90.0 * delta, float(_hp_target))

	var i = 0
	while i < _chunks.size():
		var c = _chunks[i]
		c.delay -= delta
		if c.delay <= 0.0:
			c.value = lerpf(c.value, float(_hp_target), 7.0 * delta)
			if absf(c.value - _hp_target) < 0.5:
				_chunks.remove_at(i)
				continue
		i += 1

	_shake = _shake.lerp(Vector2.ZERO, 12.0 * delta)
	if _shake.length_squared() < 0.01:
		_shake = Vector2.ZERO

	_punch = lerpf(_punch, 1.0, 10.0 * delta)
	if absf(_punch - 1.0) < 0.001:
		_punch = 1.0

	if _hp_shown < _hp_target and randf() < 0.8:
		_heal_sparkles.append({
			"x": 1.0,
			"life": randf_range(0.4, 1.0),
			"y": randf_range(-0.4, 0.4),
			"speed": randf_range(0.3, 0.8)
		})

	i = 0
	while i < _heal_sparkles.size():
		var s = _heal_sparkles[i]
		s.x -= s.speed * delta
		s.life -= delta
		if s.life <= 0.0 or s.x < 0.0:
			_heal_sparkles.remove_at(i)
			continue
		i += 1

	scale = Vector2(_punch, _punch)
	queue_redraw()


func _draw() -> void:
	var w = size.x
	var h = size.y
	var ox = _shake.x
	var oy = _shake.y

	draw_set_transform(Vector2(ox, oy), 0.0, Vector2.ONE)

	var iw = w - 4
	var ih = h - 4

	draw_rect(Rect2(2, 2, iw, ih), bg_color)

	var divider_color = bar_color.darkened(0.35)
	var num_groups = float(_max_hp) / divider_step
	var tx := 0.0

	for idx in range(1, num_groups):
		var dx = 2 + (float(idx * divider_step) / _max_hp) * iw
		draw_line(Vector2(dx, 2), Vector2(dx, h - 2), divider_color, 1.0)

	for c in _chunks:
		var cx = 2 + (float(c.value) / _max_hp) * iw
		tx = 2 + (float(_hp_target) / _max_hp) * iw
		var cw = maxf(2.0, cx - tx)
		draw_rect(Rect2(tx, 2, cw, ih), chunk_color)

	if _hp_shown > _hp_target:
		var sx = 2 + (_hp_shown / _max_hp) * iw
		tx = 2 + (float(_hp_target) / _max_hp) * iw
		draw_rect(Rect2(tx, 2, sx - tx, ih), drain_color)

	var fw = (_hp_shown / _max_hp) * iw
	draw_rect(Rect2(2, 2, maxf(fw, 0.0), ih), bar_color)

	var text = "%d/%d" % [roundi(_hp_shown), _max_hp]
	var ts = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
	var ascent = _font.get_ascent(_font_size)
	var descent = _font.get_descent(_font_size)
	tx = (w - ts.x) * 0.5
	var ty = h * 0.5 + (ascent - descent) * 0.5

	draw_string(_font, Vector2(tx + 1, ty + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(0, 0, 0, 0.6))
	draw_string(_font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(0.95, 0.95, 0.95))

	for s in _heal_sparkles:
		var sx = 2 + s.x * iw
		var sy = h * 0.5 + s.y * h
		draw_circle(Vector2(sx, sy), 2.0, Color(sparkle_color.r, sparkle_color.g, sparkle_color.b, s.life))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(0, 0, w, h), Color.WHITE, false, 1.0)
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color.BLACK, false, 1.0)
