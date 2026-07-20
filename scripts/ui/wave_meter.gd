extends Control

@export var wave_label: Label
@export var progress_bar: TextureProgressBar
@export var time_label: Label

var _elapsed: float = 0.0
var _wave: int = 1
var _visible: bool = false
var _button: Node = null


func _ready() -> void:
	hide()
	call_deferred("_connect_combat_button")


func _connect_combat_button() -> void:
	_button = get_tree().get_first_node_in_group("combat_button")
	if _button == null:
		return
	if _button.has_signal("combat_started"):
		_button.combat_started.connect(_on_combat_started)
		_button.wave_changed.connect(_on_wave_changed)
		_button.combat_ended.connect(_on_combat_ended)


func _on_combat_started() -> void:
	_elapsed = 0.0
	_wave = 1
	_visible = true
	show()
	_update_display()


func _on_wave_changed(wave: int) -> void:
	_wave = wave
	_update_display()


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

	if progress_bar != null and _button != null:
		if _button.has_method("is_in_intermission") and _button.is_in_intermission():
			progress_bar.value = progress_bar.max_value
		elif _button.has_method("get_wave_progress"):
			progress_bar.value = _button.get_wave_progress() * progress_bar.max_value

	if time_label != null:
		var total := int(_elapsed)
		var mins := int(total / 60.0)
		var secs := total % 60
		time_label.text = "%02d:%02d" % [mins, secs]
