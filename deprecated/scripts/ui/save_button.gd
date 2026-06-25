extends Button

@export var saved_text_duration: float = 1.5

var _default_text: String = ""
var _message_timer: float = 0.0


func _ready() -> void:
	_default_text = text
	pressed.connect(_on_pressed)
	if SaveManager.has_signal("save_finished"):
		SaveManager.save_finished.connect(_on_save_finished)


func _process(delta: float) -> void:
	if _message_timer <= 0.0:
		return

	_message_timer -= delta
	if _message_timer <= 0.0:
		text = _default_text


func _on_pressed() -> void:
	disabled = true
	SaveManager.save_game(&"manual")


func _on_save_finished(_reason: StringName, success: bool) -> void:
	disabled = false
	text = "Guardado" if success else "Error"
	_message_timer = saved_text_duration
