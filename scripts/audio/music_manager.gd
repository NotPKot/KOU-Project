extends Node
## Music Manager centralizado.
##
## Los enemigos, jefes y triggers NUNCA cambian la música directamente.
## Solo llaman a estas funciones públicas:
##   register_threat(source) / unregister_threat(source)
##   force_boss_music(source) / release_boss_music(source)
##   force_special_event(source) / release_special_event(source)
##
## El Music Manager decide internamente en qué EMusicState está el juego.

enum EMusicState { CALM, TENSION, COMBAT, BOSS, SPECIAL_EVENT }

signal music_state_changed(new_state: EMusicState, old_state: EMusicState)

## Tiempo que debe persistir una amenaza en Tension antes de escalar a Combat.
@export var combat_start_delay: float = 3.0
## Tiempo que se permanece en Tension tras perder todas las amenazas
## antes de volver a Calm.
@export var combat_end_delay: float = 10.0

var current_state: EMusicState = EMusicState.CALM

# Conjuntos de fuentes (enemigos/triggers) que mantienen viva cada amenaza.
# Solo se usan para CALM/TENSION/COMBAT. Boss y SpecialEvent se manejan
# como pilas de overrides independientes (ver más abajo), porque son
# estados forzados, no derivados de amenazas.
var _threat_sources: Dictionary = {} # Node -> true

# Pilas de quién está forzando Boss / SpecialEvent. Se usa una pila (array)
# en vez de un booleano para soportar múltiples triggers solapados sin que
# uno cancele la música del otro por error (p.ej. dos triggers de boss).
var _boss_sources: Array = []
var _special_event_sources: Array = []

var _combat_start_timer: Timer
var _combat_end_timer: Timer


func _ready() -> void:
	_combat_start_timer = Timer.new()
	_combat_start_timer.name = "CombatStartTimer"
	_combat_start_timer.one_shot = true
	_combat_start_timer.timeout.connect(_on_combat_start_timeout)
	add_child(_combat_start_timer)

	_combat_end_timer = Timer.new()
	_combat_end_timer.name = "CombatEndTimer"
	_combat_end_timer.one_shot = true
	_combat_end_timer.timeout.connect(_on_combat_end_timeout)
	add_child(_combat_end_timer)


# ---------------------------------------------------------------------------
# API pública: eventos que envían enemigos / triggers / jefes
# ---------------------------------------------------------------------------

## Una amenaza aparece o sigue activa (ej: un enemigo detecta al jugador).
func register_threat(source: Node) -> void:
	if source == null or _threat_sources.has(source):
		return
	_threat_sources[source] = true
	_on_threat_registered()


## Una amenaza deja de existir (ej: el enemigo muere o pierde al jugador).
func unregister_threat(source: Node) -> void:
	if source == null or not _threat_sources.has(source):
		return
	_threat_sources.erase(source)
	_on_threat_unregistered()


## Fuerza el estado Boss. Tiene prioridad sobre Calm/Tension/Combat.
func force_boss_music(source: Node) -> void:
	if source == null or source in _boss_sources:
		return
	_boss_sources.append(source)
	_refresh_forced_state()


## Libera el Boss. La música solo deja de forzarse cuando NINGÚN source
## lo está reteniendo (soporta varios triggers de boss simultáneos).
func release_boss_music(source: Node) -> void:
	_boss_sources.erase(source)
	_refresh_forced_state()


## Fuerza el estado SpecialEvent (cinemáticas, persecuciones, etc).
## Tiene la prioridad máxima, por encima incluso de Boss.
func force_special_event(source: Node) -> void:
	if source == null or source in _special_event_sources:
		return
	_special_event_sources.append(source)
	_refresh_forced_state()


## Libera el SpecialEvent.
func release_special_event(source: Node) -> void:
	_special_event_sources.erase(source)
	_refresh_forced_state()


# ---------------------------------------------------------------------------
# Lógica interna de amenazas (Calm / Tension / Combat)
# ---------------------------------------------------------------------------

func _on_threat_registered() -> void:
	# Si estamos en un estado forzado (Boss/SpecialEvent), las amenazas
	# normales no deben tocar la música. Se evaluarán solas cuando el
	# estado forzado termine.
	if _is_forced_state():
		return

	if current_state == EMusicState.COMBAT:
		# Ya en combate: cualquier timer de salida pendiente queda obsoleto.
		_combat_end_timer.stop()
		return

	if current_state == EMusicState.TENSION:
		# Si había un timer de salida corriendo (veníamos de Combat),
		# una nueva amenaza lo cancela: seguimos en Tension normalmente.
		_combat_end_timer.stop()
		# Si no hay timer de entrada corriendo, lo arrancamos.
		if _combat_start_timer.is_stopped():
			_combat_start_timer.start(combat_start_delay)
		return

	# Desde Calm: entra primero a Tension y arranca el temporizador
	# de entrada al combate (nunca salta directo a Combat).
	_set_state(EMusicState.TENSION)
	_combat_start_timer.start(combat_start_delay)


func _on_threat_unregistered() -> void:
	if _is_forced_state():
		return

	if not _threat_sources.is_empty():
		# Aún quedan amenazas activas, no hay nada que resolver todavía.
		return

	# Ya no quedan amenazas.
	_combat_start_timer.stop()

	match current_state:
		EMusicState.TENSION:
			# La amenaza desapareció antes de escalar a combate -> Calm.
			_set_state(EMusicState.CALM)
		EMusicState.COMBAT:
			# El combate terminó: no volvemos a Calm de inmediato.
			# Pasamos a Tension y arrancamos el temporizador de salida.
			_set_state(EMusicState.TENSION)
			_combat_end_timer.start(combat_end_delay)
		_:
			pass


func _on_combat_start_timeout() -> void:
	if _is_forced_state():
		return
	# Si seguimos en Tension y la amenaza persiste, escalamos a Combat.
	if current_state == EMusicState.TENSION and not _threat_sources.is_empty():
		_set_state(EMusicState.COMBAT)


func _on_combat_end_timeout() -> void:
	if _is_forced_state():
		return
	# Si en estos 10s no apareció ninguna amenaza nueva, volvemos a Calm.
	if current_state == EMusicState.TENSION and _threat_sources.is_empty():
		_set_state(EMusicState.CALM)


# ---------------------------------------------------------------------------
# Lógica de estados forzados (Boss / SpecialEvent)
# ---------------------------------------------------------------------------

func _is_forced_state() -> bool:
	return current_state == EMusicState.BOSS or current_state == EMusicState.SPECIAL_EVENT


func _refresh_forced_state() -> void:
	if not _special_event_sources.is_empty():
		# Prioridad máxima.
		_set_state(EMusicState.SPECIAL_EVENT)
		return

	if not _boss_sources.is_empty():
		_set_state(EMusicState.BOSS)
		return

	# Ningún estado forzado activo: volvemos a evaluar según las amenazas
	# normales, exactamente como si acabáramos de llegar desde fuera.
	if current_state == EMusicState.BOSS or current_state == EMusicState.SPECIAL_EVENT:
		_resume_threat_based_state()


## Se llama al salir de Boss/SpecialEvent para recalcular el estado
## correcto en base a las amenazas que pudieran haber quedado activas
## mientras el estado forzado estaba ocurriendo.
func _resume_threat_based_state() -> void:
	if _threat_sources.is_empty():
		_set_state(EMusicState.CALM)
		return

	# Hay amenazas activas: entramos en Tension y, como ya llevan tiempo
	# activas (posiblemente desde antes del Boss/SpecialEvent), iniciamos
	# el temporizador de entrada a combate de nuevo para decidir si escala.
	_set_state(EMusicState.TENSION)
	_combat_start_timer.start(combat_start_delay)


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

func _set_state(new_state: EMusicState) -> void:
	if new_state == current_state:
		return
	var old_state: EMusicState = current_state
	current_state = new_state
	music_state_changed.emit(new_state, old_state)


const STATE_NAMES := ["CALM", "TENSION", "COMBAT", "BOSS", "SPECIAL_EVENT"]

## Útil para debug / UI.
func get_state_name() -> String:
	return STATE_NAMES[current_state]
