extends CanvasLayer

const ALERTA_SFX := preload("res://assets/audio/SFX/ALERT.wav")

const FLASH_TIMESTAMPS: Array[float] = [0.087, 1.79, 3.52, 5.24]

@onready var tinte: ColorRect = $Tinte
@onready var texto_superior: Label = $TextoSuperior
@onready var texto_inferior: Label = $TextoInferior


func _ready() -> void:
	visible = false
	tinte.color.a = 0.0
	call_deferred("_connect_combat_button")


func _connect_combat_button() -> void:
	var button := get_tree().get_first_node_in_group("combat_button")
	if button == null:
		return
	if button.has_signal("wave_changed"):
		button.wave_changed.connect(mostrar_oleada)
	if button.has_signal("combat_started"):
		button.combat_started.connect(_on_combat_started)


func _on_combat_started() -> void:
	mostrar_oleada(1)


func mostrar_oleada(numero_oleada: int) -> void:
	texto_superior.text = "ZONA DE PRUEBAS, OLEADA %d" % numero_oleada
	texto_inferior.text = "¡SE ACERCAN MÁS ENEMIGOS!"
	visible = true
	_parpadeo()


func _parpadeo() -> void:
	_play_alerta()

	var tween := create_tween()

	var prev: float = 0.0
	for t in FLASH_TIMESTAMPS:
		var gap := t - prev
		if gap > 0.0:
			tween.tween_interval(gap)
		tween.tween_property(tinte, "color:a", 0.35, 0.08)
		tween.tween_property(tinte, "color:a", 0.05, 0.12)
		prev = t + 0.2

	tween.tween_interval(0.3)
	tween.tween_callback(_desvanecer)


func _play_alerta() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = ALERTA_SFX
	player.bus = "SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _desvanecer() -> void:
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(tinte, "color:a", 0.0, 0.5)
	fade.tween_property(texto_superior, "modulate:a", 0.0, 0.5)
	fade.tween_property(texto_inferior, "modulate:a", 0.0, 0.5)
	fade.tween_callback(func():
		visible = false
		tinte.color.a = 0.0
		texto_superior.modulate.a = 1.0
		texto_inferior.modulate.a = 1.0
	).set_delay(0.5)
