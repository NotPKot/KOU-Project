extends CanvasLayer

@onready var _resume_btn: Button = %ResumeBtn
@onready var _options_btn: Button = %OptionsBtn
@onready var _menu_btn: Button = %MenuBtn


func _ready() -> void:
	process_mode = PROCESS_MODE_WHEN_PAUSED
	visible = false
	_resume_btn.pressed.connect(_on_resume_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	visible = paused
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED)


func _on_resume_pressed() -> void:
	_toggle_pause()
