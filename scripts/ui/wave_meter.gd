extends Control

@export var wave_label: Label
@export var progress_bar: TextureProgressBar
@export var time_label: Label

var _elapsed: float = 0.0
var _wave: int = 1
var _wave_interval: float = 15.0
var _visible: bool = false


func _ready() -> void:
	hide()
	var button := get_tree().get_first_node_in_group("combat_button")
	if button != null and button.has_signal("combat_started"):
		button.combat_started.connect(_on_combat_started)
		button.wave_changed.connect(_on_wave_changed)
		button.combat_ended.connect(_on_combat_ended)


func _on_combat_started() -> void:
	_elapsed = 0.0
	_wave = 1
	_visible = true
	show()
	_update_display()


func _on_wave_changed(wave: int) -> void:
	_wave = wave


func _on_combat_ended() -> void:
	_visible = false
	hide()


func _process(delta: float) -> void:
	if not _visible:
		return
	_elapsed += delta
	_update_display()


func _update_display() -> void:
	if wave_label != null:
		wave_label.text = "WAVE " + str(_wave)

	if progress_bar != null:
		var progress := fmod(_elapsed, _wave_interval) / _wave_interval
		progress_bar.value = progress * progress_bar.max_value

	if time_label != null:
		var total := int(_elapsed)
		var mins := int(total / 60.0)
		var secs := total % 60
		time_label.text = "%02d:%02d" % [mins, secs]
