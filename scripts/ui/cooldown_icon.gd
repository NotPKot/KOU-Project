extends Control

var skill_id: String = ""

var _overlay: ColorRect
var _shader_mat: ShaderMaterial

const _REVEAL_SHADER := preload("res://shaders/radial_reveal.gdshader")


func _ready() -> void:
	custom_minimum_size = Vector2(36, 36)
	size = Vector2(36, 36)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(0.3, 0.3, 0.35, 1.0)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var letter := Label.new()
	letter.name = "Letter"
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.anchors_preset = Control.PRESET_FULL_RECT
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter.add_theme_font_size_override("font_size", 14)
	add_child(letter)

	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = Color(0.12, 0.12, 0.14, 0.78)
	_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = _REVEAL_SHADER
	_overlay.material = _shader_mat

	add_child(_overlay)

	_setup_style(skill_id)


func set_cooldown(total: float, remaining: float) -> void:
	if total <= 0.0:
		_shader_mat.set_shader_parameter("reveal", 1.0)
		return

	var ratio := clampf(remaining / total, 0.0, 1.0)
	_shader_mat.set_shader_parameter("reveal", 1.0 - ratio)


func _setup_style(id: String) -> void:
	var bg := get_node("Bg") as ColorRect
	var letter := get_node("Letter") as Label

	match id:
		"potion":
			bg.color = Color(0.8, 0.2, 0.2, 1.0)
			letter.text = "P"
		"dash":
			bg.color = Color(0.2, 0.45, 0.9, 1.0)
			letter.text = "D"
		"hook":
			bg.color = Color(0.2, 0.75, 0.3, 1.0)
			letter.text = "G"
		"teleport":
			bg.color = Color(0.7, 0.25, 0.9, 1.0)
			letter.text = "T"
		_:
			bg.color = Color(0.35, 0.35, 0.35, 1.0)
			letter.text = "?"
