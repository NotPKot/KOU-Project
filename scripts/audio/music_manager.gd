extends Node

enum EMusicState { CALM, TENSION, COMBAT, BOSS, SPECIAL_EVENT }

signal music_state_changed(new_state: EMusicState, old_state: EMusicState)

## Tiempo que debe persistir una amenaza en Tension antes de escalar a Combat.
@export var combat_start_delay: float = 3.0
## Tiempo que se permanece en Tension tras perder todas las amenazas
## antes de volver a Calm.
@export var combat_end_delay: float = 10.0

var current_state: EMusicState = EMusicState.CALM
var _threat_sources: Dictionary = {} # Node -> true
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
# API publica: eventos que envían enemigos / triggers / jefes
# ---------------------------------------------------------------------------

func register_threat(source: Node) -> void:
	if source == null or _threat_sources.has(source):
		return
	_threat_sources[source] = true
	_on_threat_registered()


func unregister_threat(source: Node) -> void:
	if source == null or not _threat_sources.has(source):
		return
	_threat_sources.erase(source)
	_on_threat_unregistered()


func force_boss_music(source: Node) -> void:
	if source == null or source in _boss_sources:
		return
	_boss_sources.append(source)
	_refresh_forced_state()


func release_boss_music(source: Node) -> void:
	_boss_sources.erase(source)
	_refresh_forced_state()

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
# logica interna de amenazas (Calm / Tension / Combat)
# ---------------------------------------------------------------------------

func _on_threat_registered() -> void:
	if _is_forced_state():
		return

	if current_state == EMusicState.COMBAT:
		_combat_end_timer.stop()
		return

	if current_state == EMusicState.TENSION:
		_combat_end_timer.stop()

		if _combat_start_timer.is_stopped():
			_combat_start_timer.start(combat_start_delay)
		return

	_set_state(EMusicState.TENSION)
	_combat_start_timer.start(combat_start_delay)


func _on_threat_unregistered() -> void:
	if _is_forced_state():
		return

	if not _threat_sources.is_empty():
		return

	_combat_start_timer.stop()

	match current_state:
		EMusicState.TENSION:
			
			_set_state(EMusicState.CALM)
		EMusicState.COMBAT:
			
			_set_state(EMusicState.TENSION)
			_combat_end_timer.start(combat_end_delay)
		_:
			pass


func _on_combat_start_timeout() -> void:
	if _is_forced_state():
		return

	if current_state == EMusicState.TENSION and not _threat_sources.is_empty():
		_set_state(EMusicState.COMBAT)


func _on_combat_end_timeout() -> void:
	if _is_forced_state():
		return

	if current_state == EMusicState.TENSION and _threat_sources.is_empty():
		_set_state(EMusicState.CALM)


# ---------------------------------------------------------------------------
# logica de estados forzados (Boss / SpecialEvent)
# ---------------------------------------------------------------------------

func _is_forced_state() -> bool:
	return current_state == EMusicState.BOSS or current_state == EMusicState.SPECIAL_EVENT


func _refresh_forced_state() -> void:
	if not _special_event_sources.is_empty():
		# prioridad maxima.
		_set_state(EMusicState.SPECIAL_EVENT)
		return

	if not _boss_sources.is_empty():
		_set_state(EMusicState.BOSS)
		return

	if current_state == EMusicState.BOSS or current_state == EMusicState.SPECIAL_EVENT:
		_resume_threat_based_state()



func _resume_threat_based_state() -> void:
	if _threat_sources.is_empty():
		_set_state(EMusicState.CALM)
		return

	_set_state(EMusicState.TENSION)
	_combat_start_timer.start(combat_start_delay)


# ---------------------------------------------------------------------------
# utilidades
# ---------------------------------------------------------------------------

func _set_state(new_state: EMusicState) -> void:
	if new_state == current_state:
		return
	var old_state: EMusicState = current_state
	current_state = new_state
	music_state_changed.emit(new_state, old_state)


const STATE_NAMES := ["CALM", "TENSION", "COMBAT", "BOSS", "SPECIAL_EVENT"]

## itil para debug / UI.
func get_state_name() -> String:
	return STATE_NAMES[current_state]
