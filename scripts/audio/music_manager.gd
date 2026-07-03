extends Node

# ═══════════════════════════════════════════════════════════════════════════════
# MusicManager — Sistema adaptativo de música
# Inspirado en Breath of the Wild, basado en amenaza acumulativa con histéresis.
# ═══════════════════════════════════════════════════════════════════════════════
#  CÓMO INSTALARLO:
#  Project Settings > Autoload > agregar este script con el nombre "MusicManager".
#
#  FILOSOFÍA (inspirada en BOTW y sistemas de adaptive music):
#    1. No reaccionamos a EVENTOS puntuales (matar un enemigo, detectar uno).
#       Reaccionamos a un ACUMULADOR de amenaza que sube y baja de forma continua.
#    2. Subir de intensidad es rápido. Bajar es lento (histéresis).
#    3. Cada estado tiene un TIEMPO MÍNIMO antes de poder bajar de intensidad.
#    4. Los umbrales de SUBIDA y de BAJADA son distintos.
#    5. Jefe y Evento Especial son estados de PRIORIDAD ABSOLUTA.
#    6. SIGILO: al acercarse a enemigos no detectados, el volumen de la música
#       se reduce gradualmente (ducking) sin cambiar de pista ni estado.
# ═══════════════════════════════════════════════════════════════════════════════
#  NUEVA API:                        VIEJA API (compatibilidad):
#  enemigo_agresivo(node, elite, threat)  register_threat(node)
#    PASIVO: no llamar                  unregister_threat(node)
#    SOSPECHA: enemigo_agresivo(e, f, 5)
#    ALERTA: enemigo_agresivo(e, f)     force_boss_music(node)
#  enemigo_calmado(node)               release_boss_music(node)
#  enemigo_muerto(node)
#  jugador_recibio_dano()              force_special_event(node)
#  jugador_golpeo()                    release_special_event(node)
#  iniciar_pelea_jefe(stream)
#  terminar_pelea_jefe()
#  iniciar_evento_especial(stream)
#  terminar_evento_especial()
#  undetected_enemy_nearby()
#  undetected_enemy_left()
#
#  get_state_name() / get_current_state() / get_threat_debug()
#
#  enum EMusicState { CALM, TENSION, COMBAT, BOSS, SPECIAL_EVENT }
#  signal music_state_changed(new, old)
# ═══════════════════════════════════════════════════════════════════════════════

# ---------------------------------------------------------------------------
# ESTADOS
# ---------------------------------------------------------------------------
enum EMusicState { CALM, TENSION, COMBAT, BOSS, SPECIAL_EVENT }

signal music_state_changed(new_state: EMusicState, old_state: EMusicState)

const STATE_NAMES := ["CALM", "TENSION", "COMBAT", "BOSS", "SPECIAL_EVENT"]

# ---------------------------------------------------------------------------
# PISTAS DE AUDIO
# ---------------------------------------------------------------------------
@export_group("Tracks")
@export var track_calma: AudioStream
@export var track_tension: AudioStream
@export var track_combate: AudioStream
@export var track_jefe: AudioStream

# ---------------------------------------------------------------------------
# BALANCE
# ---------------------------------------------------------------------------
@export_group("Threat contribution")
@export var threat_normal_enemy: float = 18.0
@export var threat_elite_enemy: float = 32.0
@export var threat_damage_received: float = 25.0
@export var threat_hit_landed: float = 12.0

@export var memory_damage_sec: float = 3.0
@export var memory_hit_sec: float = 3.0
@export var fight_grace_period: float = 4.0

# ---------------------------------------------------------------------------
# UMBRALES (histéresis)
# ---------------------------------------------------------------------------
@export_group("Thresholds (hysteresis)")
@export var up_tension: float = 15.0
@export var down_tension: float = 0.0
@export var up_combat: float = 55.0
@export var down_combat: float = 35.0

@export_group("Smoothing")
@export var vel_rise: float = 40.0
@export var vel_fall: float = 10.0

@export_group("Anti-flicker")
@export var min_tension_state: float = 6.0
@export var min_combat_state: float = 6.0

@export_group("Crossfade")
@export var fade_duration: float = 1.8

# ---------------------------------------------------------------------------
# SIGILO — ducking de volumen por proximidad a enemigos no detectados
# ---------------------------------------------------------------------------
@export_group("Stealth ducking")
## Reducción de volumen del bus "Music" cuando hay enemigos no detectados cerca (dB).
@export var stealth_volume_db: float = -18.0
## Velocidad de transición del ducking (dB/s).
@export var stealth_fade_speed: float = 12.0

# ---------------------------------------------------------------------------
# ESTADO INTERNO
# ---------------------------------------------------------------------------
var _state: EMusicState = EMusicState.CALM
var _time_in_state: float = 0.0
var _threat: float = 0.0
var _threat_target: float = 0.0

var _enemigos_activos: Dictionary = {}   # Node -> { "elite": bool, "threat": float }
var _timer_memoria_dano: float = 0.0
var _timer_memoria_golpe: float = 0.0
var _timer_gracia: float = 0.0
var _hubo_combate_reciente: bool = false

var _locked_by_override: bool = false

# Sigilo
var _stealth_count: int = 0
var _stealth_current_db: float = 0.0
var _music_bus_idx: int = -1

var _players: Array[AudioStreamPlayer] = []
var _active_player_idx: int = 0
var _fade_tween: Tween

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Crear dos reproductores para crossfade.
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Channel_" + str(i)
		p.bus = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"
		p.volume_db = -80
		add_child(p)
		_players.append(p)

	# Iniciar con la pista de calma.
	_players[_active_player_idx].stream = track_calma
	_players[_active_player_idx].volume_db = 0
	if track_calma:
		_players[_active_player_idx].play()

	# Bus de música para ducking de sigilo.
	_music_bus_idx = AudioServer.get_bus_index("Music")

# ---------------------------------------------------------------------------
# PROCESS
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time_in_state += delta

	# Si está bloqueado por un override (jefe o evento especial), no hacemos nada.
	if _locked_by_override:
		return

	_actualizar_memoria(delta)
	_calcular_amenaza_objetivo()
	_suavizar_amenaza(delta)
	_evaluar_transicion()

	_actualizar_sigilo(delta)

# ---------------------------------------------------------------------------
# API PÚBLICA — nuevo estilo
# ---------------------------------------------------------------------------

## Llamar cuando un enemigo detecta/agrede/sospecha del jugador.
## - threat_value: si se pasa (>=0), se usa ese valor exacto en lugar del default por rareza.
##   Util para SOSPECHA (5-8) vs ALERTA (18-32).
func enemigo_agresivo(enemigo: Node, es_elite: bool = false, threat_value: float = -1.0) -> void:
	if enemigo == null:
		return
	var real_threat := threat_value if threat_value >= 0.0 else (threat_elite_enemy if es_elite else threat_normal_enemy)
	_enemigos_activos[enemigo] = { "elite": es_elite, "threat": real_threat }
	_hubo_combate_reciente = true
	_timer_gracia = fight_grace_period

## Llamar cuando un enemigo pierde de vista al jugador o vuelve a estado pasivo.
func enemigo_calmado(enemigo: Node) -> void:
	if enemigo == null:
		return
	_enemigos_activos.erase(enemigo)

## Llamar cuando un enemigo muere.
func enemigo_muerto(enemigo: Node) -> void:
	enemigo_calmado(enemigo)

## Llamar cuando el jugador recibe daño.
func jugador_recibio_dano() -> void:
	_timer_memoria_dano = memory_damage_sec
	_timer_gracia = fight_grace_period
	_hubo_combate_reciente = true

## Llamar cuando el jugador conecta un golpe (opcional, pero suma sensación de pelea real).
func jugador_golpeo() -> void:
	_timer_memoria_golpe = memory_hit_sec
	_timer_gracia = fight_grace_period
	_hubo_combate_reciente = true

# ---------------------------------------------------------------------------
# API DE SIGILO
# ---------------------------------------------------------------------------

## Llamar cuando el jugador está cerca de un enemigo que NO lo ha detectado.
func undetected_enemy_nearby() -> void:
	_stealth_count += 1

## Llamar cuando el jugador se aleja de un enemigo no detectado.
func undetected_enemy_left() -> void:
	_stealth_count = max(0, _stealth_count - 1)

## Activa el estado de jefe. Prioridad absoluta, bloquea el cálculo automático.
func iniciar_pelea_jefe(stream: AudioStream = null) -> void:
	_locked_by_override = true
	_stealth_count = 0
	var s := stream if stream else track_jefe
	_cambiar_estado(EMusicState.BOSS, s, true)

## Termina la pelea de jefe y vuelve al cálculo automático, respetando la desescalada.
func terminar_pelea_jefe() -> void:
	_locked_by_override = false
	_enemigos_activos.clear()
	_hubo_combate_reciente = true
	_timer_gracia = fight_grace_period
	# No reseteamos _threat, dejamos que baje suavemente.
	var fallback := _get_fallback_stream([track_combate, track_tension, track_calma])
	_cambiar_estado(EMusicState.COMBAT, fallback, true)

## Activa un evento especial (cutscene, puzzle, etc.) con música propia.
func iniciar_evento_especial(stream: AudioStream) -> void:
	_locked_by_override = true
	_cambiar_estado(EMusicState.SPECIAL_EVENT, stream, true)

## Termina el evento especial y vuelve al cálculo automático.
func terminar_evento_especial() -> void:
	_locked_by_override = false
	_enemigos_activos.clear()
	_hubo_combate_reciente = true
	_timer_gracia = fight_grace_period
	var fallback := _get_fallback_stream([track_tension, track_calma])
	_cambiar_estado(EMusicState.TENSION, fallback, true)

# ---------------------------------------------------------------------------
# VIEJA API (wrappers de compatibilidad)
# ---------------------------------------------------------------------------

func register_threat(node: Node) -> void:
	enemigo_agresivo(node)

func unregister_threat(node: Node) -> void:
	enemigo_calmado(node)

func force_boss_music(_node: Node) -> void:
	iniciar_pelea_jefe()

func release_boss_music(_node: Node) -> void:
	terminar_pelea_jefe()

func force_special_event(_node: Node) -> void:
	# No implementado, usa iniciar_evento_especial(stream)
	pass

func release_special_event(_node: Node) -> void:
	pass

# ---------------------------------------------------------------------------
# DEBUG / INFO
# ---------------------------------------------------------------------------

func get_state_name() -> String:
	return STATE_NAMES[_state]

func get_current_state() -> EMusicState:
	return _state

func get_threat_debug() -> Dictionary:
	return {
		"threat": _threat,
		"target": _threat_target,
		"enemies": _enemigos_activos.size(),
		"state": STATE_NAMES[_state],
		"time_in_state": _time_in_state,
		"stealth_count": _stealth_count,
		"stealth_volume_db": _stealth_current_db,
	}

# ---------------------------------------------------------------------------
# LÓGICA INTERNA
# ---------------------------------------------------------------------------

func _actualizar_sigilo(delta: float) -> void:
	var target_db := stealth_volume_db if _stealth_count > 0 else 0.0
	_stealth_current_db = move_toward(_stealth_current_db, target_db, stealth_fade_speed * delta)
	if _music_bus_idx >= 0:
		AudioServer.set_bus_volume_db(_music_bus_idx, _stealth_current_db)


func _exit_tree() -> void:
	if _music_bus_idx >= 0:
		AudioServer.set_bus_volume_db(_music_bus_idx, 0.0)


func _actualizar_memoria(delta: float) -> void:
	_timer_memoria_dano = max(0.0, _timer_memoria_dano - delta)
	_timer_memoria_golpe = max(0.0, _timer_memoria_golpe - delta)

	if _enemigos_activos.is_empty():
		if _timer_gracia > 0.0:
			_timer_gracia -= delta
		else:
			_hubo_combate_reciente = false
	else:
		_timer_gracia = fight_grace_period

func _calcular_amenaza_objetivo() -> void:
	var objetivo: float = 0.0

	# Amenaza por enemigos activos (cada uno con su propio valor de amenaza).
	for enemigo in _enemigos_activos.keys():
		objetivo += _enemigos_activos[enemigo]["threat"]

	# Amenaza por daño recibido o golpeado.
	if _timer_memoria_dano > 0.0:
		objetivo += threat_damage_received
	if _timer_memoria_golpe > 0.0:
		objetivo += threat_hit_landed

	# Gracia post-combate: mantiene la amenaza alta durante unos segundos
	# para que no caiga a 0 de golpe al eliminar al último enemigo.
	if _enemigos_activos.is_empty() and _timer_gracia > 0.0 and _hubo_combate_reciente:
		objetivo = max(objetivo, down_combat * 0.6)

	_threat_target = clamp(objetivo, 0.0, 100.0)

func _suavizar_amenaza(delta: float) -> void:
	if _threat_target > _threat:
		_threat = min(_threat_target, _threat + vel_rise * delta)
	else:
		_threat = max(_threat_target, _threat - vel_fall * delta)

func _evaluar_transicion() -> void:
	var target := _state
	var enemies_nearby := _enemigos_activos.size() > 0 or _stealth_count > 0

	match _state:
		EMusicState.CALM:
			if _threat >= up_tension:
				target = EMusicState.TENSION
			elif enemies_nearby:
				target = EMusicState.TENSION

		EMusicState.TENSION:
			if _threat >= up_combat:
				target = EMusicState.COMBAT
			elif _threat <= down_tension and _time_in_state >= min_tension_state:
				if not enemies_nearby:
					target = EMusicState.CALM

		EMusicState.COMBAT:
			if _threat <= down_combat and _time_in_state >= min_combat_state:
				target = EMusicState.TENSION

		EMusicState.BOSS, EMusicState.SPECIAL_EVENT:
			pass  # Control manual, no se evalúa automáticamente.

	if target != _state:
		var stream := _stream_para_estado(target)
		_cambiar_estado(target, stream)

func _stream_para_estado(s: EMusicState) -> AudioStream:
	match s:
		EMusicState.CALM: return track_calma
		EMusicState.TENSION: return track_tension
		EMusicState.COMBAT: return track_combate
		EMusicState.BOSS: return track_jefe
		EMusicState.SPECIAL_EVENT: return track_jefe if track_jefe else track_combate
	return null

func _cambiar_estado(nuevo: EMusicState, stream: AudioStream, force: bool = false) -> void:
	# Si es el mismo estado y la misma pista, y no forzamos, no hacemos nada.
	if not force and nuevo == _state and _players[_active_player_idx].stream == stream:
		return

	var anterior := _state
	_state = nuevo
	_time_in_state = 0.0
	music_state_changed.emit(nuevo, anterior)
	_crossfade_a(stream)

func _crossfade_a(stream: AudioStream) -> void:
	if stream == null:
		for p in _players:
			p.volume_db = -80
			p.stop()
		return

	var actual := _players[_active_player_idx]
	var siguiente_idx := 1 - _active_player_idx
	var siguiente := _players[siguiente_idx]

	# Si ya está sonando exactamente esta pista, no la reiniciamos.
	if actual.stream == stream and actual.playing:
		return

	siguiente.stream = stream
	siguiente.volume_db = -80
	siguiente.play()

	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(actual, "volume_db", -80.0, fade_duration)
	_fade_tween.tween_property(siguiente, "volume_db", 0.0, fade_duration)
	_fade_tween.chain().tween_callback(actual.stop)

	_active_player_idx = siguiente_idx

# ---------------------------------------------------------------------------
# UTILIDADES
# ---------------------------------------------------------------------------

func _get_fallback_stream(streams: Array) -> AudioStream:
	for s in streams:
		if s != null:
			return s
	return null
