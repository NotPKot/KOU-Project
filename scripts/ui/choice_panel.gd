extends CanvasLayer

signal choice_selected(choice_id: StringName)

@onready var _option_buttons: Array[Button] = [
	$Blocker/CenterContainer/Options/Option0 as Button,
	$Blocker/CenterContainer/Options/Option1 as Button,
	$Blocker/CenterContainer/Options/Option2 as Button,
]

var _choices: Array[Dictionary] = []
var _target: Node = null


func _ready() -> void:
	for index in range(_option_buttons.size()):
		_option_buttons[index].pressed.connect(_select_choice.bind(index))


func open(choices: Array[Dictionary], target: Node) -> void:
	_choices = choices
	_target = target
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	for index in range(_option_buttons.size()):
		var button := _option_buttons[index]
		var has_choice := index < _choices.size()
		button.visible = has_choice
		button.disabled = not has_choice

		if has_choice:
			button.text = str(_choices[index].get("label", _choices[index].get("id", "Choice")))
			button.tooltip_text = str(_choices[index].get("description", ""))


func _select_choice(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return

	var choice_id := StringName(str(_choices[index].get("id", "")))
	choice_selected.emit(choice_id)
	queue_free()
