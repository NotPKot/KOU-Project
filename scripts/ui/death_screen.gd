extends CanvasLayer

func _ready() -> void:
	hide()
	%ReviveBtn.pressed.connect(_on_revive_pressed)
	process_mode = PROCESS_MODE_ALWAYS


func show_death_screen() -> void:
	show()
	get_tree().paused = true


func _on_revive_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
