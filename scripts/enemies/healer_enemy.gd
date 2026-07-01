extends CharacterBody3D

# ============================================================
# FUNCIONALIDAD
# ============================================================

@export var walk_speed: float = 2.5
@export var acceleration: float = 12.0
@export var gravity: float = 18.0
@export var terminal_velocity: float = 42.0
@export var max_hp: int = 60
@export var vision_range: float = 40.0
@export var vision_angle: float = 120.0
@export var lose_sight_time: float = 2.5

@export var heal_detection_range: float = 20.0
@export var heal_range: float = 3.0
@export var heal_amount: int = 30
@export var heal_grab_duration: float = 0.6
@export var heal_cooldown_duration: float = 4.0

@export var flee_duration: float = 3.0
@export var flee_speed_mult: float = 1.3

@export var cover_scan_range: float = 16.0
@export var cover_scan_rays: int = 12

@export_group("Tensión")
@export var tension_max_distance: float = 16.0  # mas alla de esto, la distancia no aporta tensión
@export var tension_rise_distance_rate: float = 7.0  # por segundo, a distancia minima
@export var tension_rise_vision_rate: float = 10.0  # por segundo, si el JUGADOR ve al healer
@export var tension_hit_spike: float = 45.0  # salto inmediato al recibir un golpe
@export var tension_decay_rate: float = 20.0  # por segundo, cuando ninguna condicion se cumple
@export var tension_medium_threshold: float = 30.0
@export var tension_high_threshold: float = 65.0
@export var panic_detect_range: float = 4.0  # si el jugador esta mas cerca que esto y visible, el healer huye al instante

var _healer_tension: float = 0.0

const ALLY_HP_RATIO_THRESHOLD: float = 0.8
const COVER_MIN_DIST: float = 3.0

var hp: int

var _player: Node3D = null
var _player_search_done: bool = false

var _sight_loss_timer: float = 0.0
var _tension_registered: bool = false
var _can_see_cache: bool = false
var _can_see_frame: int = -1
var _last_seen_time: float = -999.0

var _vision_query: PhysicsRayQueryParameters3D = null
var _cover_query: PhysicsRayQueryParameters3D = null

var _effects: Dictionary = {}

var _cover_target: Vector3 = Vector3.ZERO
var _cover_recalc_cooldown: float = 0.0
const COVER_RECALC_INTERVAL: float = 0.3

var _known_covers: Array[Vector3] = []
var _cover_memory_scan_timer: float = 0.0
const COVER_MEMORY_SCAN_INTERVAL: float = 10.0
const MAX_KNOWN_COVERS: int = 8

var _last_hit_time: float = -999.0
var _flee_target: Vector3 = Vector3.ZERO
var _flee_triggered_at: float = -999.0

var _target_ally: Node3D = null
var _heal_cooldown_timer: float = 0.0
var _grab_timer: float = 0.0
var _grabbing: bool = false

var _body_material: StandardMaterial3D
var _head_material: StandardMaterial3D
var _body_base_color: Color
var _head_base_color: Color

@onready var _visual_node: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _head_mesh: MeshInstance3D = $Visual/Head
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")

	_body_material = StandardMaterial3D.new()
	_body_base_color = Color(0.15, 0.65, 0.55, 1.0)
	_body_material.albedo_color = _body_base_color
	_body_material.roughness = 0.6
	_body_material.metallic = 0.3
	_body_mesh.material_override = _body_material

	_head_material = StandardMaterial3D.new()
	_head_base_color = Color(0.2, 0.75, 0.65, 1.0)
	_head_material.albedo_color = _head_base_color
	_head_material.roughness = 0.5
	_head_material.metallic = 0.2
	_head_mesh.material_override = _head_material

	_nav_agent.path_desired_distance = 1.0
	_nav_agent.target_desired_distance = 1.0
	_nav_agent.radius = 0.4
	_nav_agent.max_speed = walk_speed * flee_speed_mult
	_nav_agent.avoidance_enabled = false

	# evita que el healer se quede atascado al rozar una pared: sin esto,
	# move_and_slide() puede detenerlo completamente si topa contra una
	# pared mientras está en el suelo, en vez de deslizarse a lo largo de ella.
	floor_block_on_wall = false


func _process(delta: float) -> void:
	_process_effects(delta)
	_update_vision(delta)
	_update_tension(delta)
	_tick_timers(delta)
	_evaluate_goap(delta)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()


func _get_player() -> Node3D:
	if _player == null and not _player_search_done:
		_player_search_done = true
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _get_vision_query() -> PhysicsRayQueryParameters3D:
	if _vision_query == null:
		_vision_query = PhysicsRayQueryParameters3D.new()
		_vision_query.collision_mask = 1
	return _vision_query


func _can_see_player_cached() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _can_see_frame:
		return _can_see_cache
	_can_see_frame = frame
	_can_see_cache = _can_see_player()
	return _can_see_cache


func _update_tension(delta: float) -> void:
	# sistema de Tensión: en vez de calcular un punto geometrico "ideal" de
	# escudo respecto a un aliado (que producía el efecto de "perro con
	# correa" orbitando en el radio máximo), el healer ahora reacciona a un
	# valor escalar de amenaza. Esto es mas parecido a cómo enemigos de
	# soporte en juegos de acción reales (ej. el Wyvern de Destiny, que
	# proyecta su escudo en vez de perseguir un ángulo perfecto) deciden
	# CUANDO acercarse o alejarse, dejando que el movimiento normal
	# (NavigationAgent3D + cobertura)(o eso quisiera) resuelva el COMO llegar ahí.
	# (esta wea es del sistema viejo, que no me guste y borre asi)
	var player := _get_player()
	if player == null:
		_healer_tension = maxf(_healer_tension - tension_decay_rate * delta, 0.0)
		return

	var rose := false

	# factor 1: distancia al jugador — solo si lo hemos visto en los
	# ultimos 5 segundos. Sin esto, la tensión subia por proximidad aunque
	# hubiera una pared de por medio, haciendo que el healer huyera chocando con las paredes.
	var now := Time.get_ticks_msec() * 0.001
	var dist := global_position.distance_to(player.global_position)
	if dist < tension_max_distance and now - _last_seen_time < 5.0:
		var proximity := 1.0 - clampf(dist / tension_max_distance, 0.0, 1.0)
		_healer_tension += tension_rise_distance_rate * proximity * delta
		rose = true

	# factor 2: el JUGADOR tiene línea de visión directa hacia el healer
	# (exposicion real) — NO confundir con que el healer vea al jugador
	# (eso es solo percepcion propia, no significa estar expuesto). Antes
	# este factor usaba _can_see_player_cached(), que mide lo contrario
	# (healer -> jugador, basado en el cono de visión/orientación del
	# healer) — eso disparaba tension solo porque el healer "notaba" al
	# jugador, sin que el jugador lo viera a el, haciendo que huyera por
	# simplemente estar cerca y mirando hacia ahí.
	var space := get_world_3d().direct_space_state
	if space != null and not _is_position_hidden_from_player(global_position, player, space):
		_healer_tension += tension_rise_vision_rate * delta
		rose = true

	# factor 3: ataque activo — un golpe reciente da un salto inmediato,
	# no solo una subida gradual (reutiliza _last_hit_time, ya actualizado
	# por take_damage en otra parte del script).
	if now - _last_hit_time < 0.15:
		_healer_tension = maxf(_healer_tension, tension_hit_spike)
		rose = true

	if not rose:
		_healer_tension = maxf(_healer_tension - tension_decay_rate * delta, 0.0)

	_healer_tension = clampf(_healer_tension, 0.0, 100.0)


func _tension_is_high() -> bool:
	return _healer_tension >= tension_high_threshold


func _tension_is_medium_or_above() -> bool:
	return _healer_tension >= tension_medium_threshold


func _update_vision(delta: float) -> void:
	var player := _get_player()
	if player == null:
		return

	var can_see := _can_see_player_cached()

	if can_see:
		_sight_loss_timer = 0.0
		_last_seen_time = Time.get_ticks_msec() * 0.001
		if not _tension_registered:
			_tension_registered = true
			MusicManager.register_threat(self)
	else:
		_sight_loss_timer += delta
		if _tension_registered and _sight_loss_timer >= lose_sight_time:
			_tension_registered = false
			MusicManager.unregister_threat(self)


func _can_see_player() -> bool:
	var player := _get_player()
	if player == null:
		return false

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist > vision_range:
		return false
	if dist < 0.01:
		return true

	var dir := to_player / dist
	var forward := -_visual_node.global_transform.basis.z
	if forward.dot(dir) < cos(deg_to_rad(vision_angle * 0.5)):
		return false

	var space := get_world_3d().direct_space_state
	if space == null:
		return true

	var query := _get_vision_query()
	query.from = global_position + Vector3.UP * 0.5
	query.to = player.global_position + Vector3.UP * 0.5
	query.exclude = [get_rid(), player.get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = max(velocity.y - gravity * delta, -terminal_velocity)
	elif velocity.y < 0.0:
		velocity.y = -0.1


func _chase_toward(target: Vector3, speed: float, delta: float) -> void:
	# seguimiento directo del path del NavigationAgent3D (sin RVO). El RVO
	# estaba causando que el healer chocara contra las paredes porque el
	# sistema de avoidance solo separa agentes entre sí, no esquiva
	# obstaculos estáticos — y la velocidad calculada llegaba con retraso
	# (un frame de desfase), haciendo que las correcciones antichoque no
	# se aplicaran a tiempo en el move_and_slide().
	_nav_agent.target_position = target
	var next_point := _nav_agent.get_next_path_position()

	var to_next := next_point - global_position
	to_next.y = 0.0
	var dist_to_next := to_next.length_squared()

	var dir: Vector3
	if dist_to_next < 0.04:
		var to_target := target - global_position
		to_target.y = 0.0
		dir = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.ZERO
	else:
		dir = to_next.normalized()

	if dir.length_squared() > 0.001:
		velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
		_visual_node.look_at(global_position + dir, Vector3.UP)




func _stand_still(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _tick_timers(delta: float) -> void:
	if _heal_cooldown_timer > 0.0:
		_heal_cooldown_timer = maxf(_heal_cooldown_timer - delta, 0.0)

	if _grabbing:
		_grab_timer -= delta
		if _grab_timer <= 0.0:
			_apply_heal()


func take_damage(amount: int) -> void:
	hp -= amount
	_last_hit_time = Time.get_ticks_msec() * 0.001
	_modulate_damage()
	if hp <= 0:
		queue_free()


func _modulate_damage() -> void:
	_body_material.albedo_color = Color.WHITE
	_head_material.albedo_color = Color.WHITE
	await get_tree().create_timer(0.08).timeout
	if is_queued_for_deletion():
		return
	_body_material.albedo_color = _body_base_color
	_head_material.albedo_color = _head_base_color


func apply_effect(effect: StatusEffect) -> void:
	if _effects.has(effect.effect_name):
		_effects[effect.effect_name].remaining = effect.duration
		return
	effect.apply(self)
	_effects[effect.effect_name] = effect


func has_effect(effect_name: String) -> bool:
	return _effects.has(effect_name)


func _process_effects(delta: float) -> void:
	var expired: Array[String] = []
	for key in _effects:
		var e: StatusEffect = _effects[key]
		if e.tick(delta):
			expired.append(key)
			e.remove()
	for key in expired:
		_effects.erase(key)


func _apply_heal() -> void:
	_grabbing = false
	_heal_cooldown_timer = heal_cooldown_duration

	if _target_ally == null or not is_instance_valid(_target_ally):
		_target_ally = null
		return

	if _target_ally.has_method("take_damage"):
		_target_ally.hp = mini(_target_ally.hp + heal_amount, _target_ally.max_hp)

	_target_ally = null


func _reset_material_colors() -> void:
	_body_material.albedo_color = _body_base_color
	_head_material.albedo_color = _head_base_color


func _find_injured_allies() -> Array:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var result: Array = []
	for e in enemies:
		if e == self:
			continue
		if not is_instance_valid(e):
			continue
		if not e.has_method("take_damage"):
			continue
		if e.hp >= e.max_hp * ALLY_HP_RATIO_THRESHOLD:
			continue
		result.append(e)
	return result


func _find_nearest_injured_ally() -> Node3D:
	var allies := _find_injured_allies()
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for a in allies:
		var d := global_position.distance_squared_to(a.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = a
	return nearest


func _find_nearest_ally() -> Node3D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for e in enemies:
		if e == self:
			continue
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_squared_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest


func _get_cover_query() -> PhysicsRayQueryParameters3D:
	if _cover_query == null:
		_cover_query = PhysicsRayQueryParameters3D.new()
		_cover_query.collision_mask = 1
	return _cover_query


func _is_position_hidden_from_player(pos: Vector3, player: Node3D, space: PhysicsDirectSpaceState3D) -> bool:
	var query := _get_cover_query()
	query.from = player.global_position + Vector3.UP * 0.5
	query.to = pos + Vector3.UP * 0.5
	query.exclude = [get_rid(), player.get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return false
	# el obstaculo debe estar mas cerca del healer que del jugador.
	# Si esta mas cerca del jugador, es el jugador quien esta tras la pared,
	# no el healer — y el healer NO está realmente escondido.
	var hit_pos := result["position"] as Vector3
	var dist_to_healer_sq := hit_pos.distance_squared_to(pos)
	var dist_to_player_sq := hit_pos.distance_squared_to(player.global_position)
	return dist_to_healer_sq < dist_to_player_sq


func _find_idle_position() -> Vector3:
	# el healer prefiere estar cerca de sus aliados. busca un punto cerca
	# del aliado mas proximo, y solo recurre a cobertura si no hay aliados
	# o si la posicion junto al aliado está expuesta al jugador.
	var nearest_ally := _find_nearest_ally()
	if nearest_ally != null:
		var player := _get_player()
		var space := get_world_3d().direct_space_state
		if space != null:
			var ally_pos := nearest_ally.global_position
			# intentar ponerse al lado del aliado (a 3m de distancia)
			var dir_from_ally := global_position - ally_pos
			dir_from_ally.y = 0.0
			if dir_from_ally.length_squared() < 0.01:
				dir_from_ally = Vector3.RIGHT
			var pos_near_ally := ally_pos + dir_from_ally.normalized() * 3.0
			# solo si esa posicion no esta expuesta
			if player == null or _is_position_hidden_from_player(pos_near_ally, player, space):
				return pos_near_ally
			# si esta expuesta, buscar cobertura cerca del aliado
			var cover := _find_cover_near(ally_pos)
			if cover.distance_squared_to(global_position) > 0.5:
				return cover
	# fallback: cobertura normal
	return _find_nearest_cover()


func _find_cover_near(origin: Vector3) -> Vector3:
	# busca cobertura cerca de un punto dado (sin escanear desde cero,
	# reusa la memoria de coberturas conocidas).
	#esto evita que el NPC vaya por una ruta optima a un lugar que jamas a visitado
	#quitando asi la imagen de que fuera omniprescente, esto lo hace mas natural a la hora del gameplay
	var player := _get_player()
	var space := get_world_3d().direct_space_state
	if space == null or player == null:
		return global_position
	
	var best_pos := global_position
	var best_dist := INF
	for cover in _known_covers:
		if _is_position_hidden_from_player(cover, player, space):
			var d := origin.distance_squared_to(cover)
			if d < best_dist:
				best_dist = d
				best_pos = cover
	if best_dist < INF:
		return best_pos
	return _find_nearest_cover()


func _find_nearest_cover() -> Vector3:
	var player := _get_player()
	var space := get_world_3d().direct_space_state
	if space == null or player == null:
		return global_position

	var mem_best := _find_best_remembered_cover(player, space)
	if mem_best != global_position:
		return mem_best

	var scan_result := _full_cover_scan(player, space)
	if scan_result != global_position:
		_remember_cover(scan_result)
	return scan_result


func _full_cover_scan(player: Node3D, space: PhysicsDirectSpaceState3D) -> Vector3:
	var best_pos := global_position
	var best_dist := INF
	var found_any := false
	var TAU := 6.28318

	for i in range(cover_scan_rays):
		var angle := (float(i) / float(cover_scan_rays)) * TAU
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var target_pos := global_position + dir * cover_scan_range

		var probe_query := _get_cover_query()
		probe_query.from = global_position + Vector3.UP * 0.3
		probe_query.to = target_pos + Vector3.UP * 0.3
		probe_query.exclude = [get_rid()]

		var probe_result := space.intersect_ray(probe_query)
		if probe_result.is_empty():
			continue

		var hit_pos := probe_result["position"] as Vector3
		var hit_normal := (probe_result["normal"] as Vector3).normalized()

		var cover_pos := hit_pos + hit_normal * COVER_MIN_DIST
		cover_pos.y = global_position.y

		if not _is_position_hidden_from_player(cover_pos, player, space):
			continue

		var d := global_position.distance_squared_to(cover_pos)
		if d < best_dist:
			best_dist = d
			best_pos = cover_pos
			found_any = true

	if found_any:
		return best_pos
	return global_position


func _refresh_cover_memory(player: Node3D, space: PhysicsDirectSpaceState3D) -> void:
	var result := _full_cover_scan(player, space)
	if result != global_position:
		_remember_cover(result)


func _find_best_remembered_cover(player: Node3D, space: PhysicsDirectSpaceState3D) -> Vector3:
	var best_pos := global_position
	var best_dist := INF
	var to_remove: Array[int] = []
	for idx in range(_known_covers.size()):
		var cover := _known_covers[idx]
		if not _is_position_hidden_from_player(cover, player, space):
			to_remove.append(idx)
			continue
		var d := global_position.distance_squared_to(cover)
		if d < best_dist:
			best_dist = d
			best_pos = cover
	to_remove.reverse()
	for idx in to_remove:
		_known_covers.remove_at(idx)
	return best_pos


func _remember_cover(pos: Vector3) -> void:
	for existing in _known_covers:
		if existing.distance_squared_to(pos) < 1.0:
			return
	_known_covers.append(pos)
	if _known_covers.size() > MAX_KNOWN_COVERS:
		_known_covers.pop_front()


func _get_flee_target_from_player() -> Vector3:
	# la huida ahora apunta directo a un punto de cobertura real (mismo
	# escaneo que usa IDLE). Si no hay ninguno disponible cerca, cae al
	# comportamiento anterior de alejarse del jugador en línea recta —
	# _has_reached_safety() ya cubre ese caso con safe_distance_fallback.
	var cover := _find_nearest_cover()
	if cover.distance_squared_to(global_position) > 0.5:
		return cover

	var player := _get_player()
	if player == null:
		return global_position + Vector3.RIGHT * 10.0

	var away := global_position - player.global_position
	away.y = 0.0
	if away.length_squared() > 0.01:
		return global_position + away.normalized() * 15.0
	return global_position + Vector3.RIGHT * 10.0


# ============================================================
# COMPORTAMIENTO GOAP
# ============================================================

enum GoapActionId { HEAL_ALLY, FLEE, RECOVER, WINDED, IDLE }

var _current_action: GoapActionId = GoapActionId.IDLE
var _action_elapsed: float = 0.0
var _in_grab: bool = false

@export var recover_duration: float = 10.0
@export var winded_duration: float = 4.5
@export var flee_sprint_duration: float = 10.0

var _winded_timer: float = 0.0
@export var safe_distance_fallback: float = 10.0

var _recover_timer: float = 0.0


func _evaluate_goap(delta: float) -> void:
	_action_elapsed += delta

	var selected: GoapActionId = _evaluate_best_action()

	if selected != _current_action:
		_exit_action(_current_action)
		_current_action = selected
		_action_elapsed = 0.0
		_enter_action(_current_action)

	_execute_action(_current_action, delta)


func _is_flee_urgent() -> bool:
	# solo interrumpir curación si:
	# 1. acaban de golpearnos (ventana de huida por daño directo)
	# 2. el jugador está en rango de pánico (distancia muy corta)
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_hit_time < flee_duration:
		return true
	return _is_player_in_panic_range()


func _evaluate_best_action() -> GoapActionId:
	# Si estamos actualmente en FLEE, decidir si toca salir y hacia dónde.
	if _current_action == GoapActionId.FLEE:
		var exit_reason := _get_flee_exit_reason()
		match exit_reason:
			FleeExit.REAL_COVER:
				return GoapActionId.RECOVER
			FleeExit.SPRINT_TIMEOUT:
				return GoapActionId.WINDED
			FleeExit.NONE:
				return GoapActionId.FLEE

	# si esta curando activamente, NO interrumpir a menos que sea urgente
	# (golpe directo o pánico extremo). el healer debe priorizar su rol de
	# soporte sobre huir por cualquier amenaza leve.
	#es un healer, no un cobarde xd
	if _current_action == GoapActionId.HEAL_ALLY:
		if _is_flee_urgent():
			return GoapActionId.FLEE
		if _can_heal_ally():
			return GoapActionId.HEAL_ALLY
		_target_ally = null

	# panico: solo desde IDLE. El healer ya no huye en pánico mientras esta
	# curando (se maneja arriba con _is_flee_urgent), permitiendo que termine
	# la cura antes de evaluar huida.
	if _current_action == GoapActionId.IDLE and _is_player_in_panic_range():
		return GoapActionId.FLEE

	# si nos golpean en cualquier otro estado (incluyendo RECOVER o WINDED),
	# _can_flee() vuelve a true por la ventana de flee_duration y entra a FLEE.
	if _can_flee():
		return GoapActionId.FLEE

	# RECOVER: descanso largo tras cobertura real, se mantiene hasta agotar
	# su timer.
	if _current_action == GoapActionId.RECOVER and _recover_timer > 0.0:
		return GoapActionId.RECOVER

	# WINDED: descanso corto tras un tramo de sprint sin cobertura.
	if _current_action == GoapActionId.WINDED:
		if _winded_timer > 0.0:
			return GoapActionId.WINDED
		var player := _get_player()
		if player != null:
			var dist := global_position.distance_to(player.global_position)
			if dist < safe_distance_fallback:
				return GoapActionId.FLEE

	# curar aliados heridos tiene prioridad sobre deambular.
	if _can_heal_ally():
		_target_ally = _find_nearest_injured_ally()
		return GoapActionId.HEAL_ALLY

	# IDLE: mantenerse cerca de aliados en vez de aislarse en cobertura.
	return GoapActionId.IDLE


func _enter_action(action: GoapActionId) -> void:
	match action:
		GoapActionId.HEAL_ALLY:
			_enter_heal_ally()
		GoapActionId.FLEE:
			_enter_flee()
		GoapActionId.RECOVER:
			_enter_recover()
		GoapActionId.WINDED:
			_enter_winded()
		GoapActionId.IDLE:
			_enter_idle()


func _exit_action(action: GoapActionId) -> void:
	match action:
		GoapActionId.HEAL_ALLY:
			if _grabbing:
				_grabbing = false
			_target_ally = null
			_reset_material_colors()
		GoapActionId.FLEE:
			pass
		GoapActionId.RECOVER:
			pass
		GoapActionId.WINDED:
			pass
		GoapActionId.IDLE:
			pass


func _execute_action(action: GoapActionId, delta: float) -> void:
	match action:
		GoapActionId.HEAL_ALLY:
			_execute_heal_ally(delta)
		GoapActionId.FLEE:
			_execute_flee(delta)
		GoapActionId.RECOVER:
			_execute_recover(delta)
		GoapActionId.WINDED:
			_execute_winded(delta)
		GoapActionId.IDLE:
			_execute_idle(delta)


# --- HEAL ALLY ---

func _can_heal_ally() -> bool:
	if _heal_cooldown_timer > 0.0:
		return false

	var ally := _find_nearest_injured_ally()
	if ally == null:
		return false

	return true


func _enter_heal_ally() -> void:
	_grab_timer = 0.0
	_in_grab = false


func _execute_heal_ally(delta: float) -> void:
	if _target_ally == null or not is_instance_valid(_target_ally):
		_target_ally = _find_nearest_injured_ally()
		if _target_ally == null:
			return

	var dist := global_position.distance_to(_target_ally.global_position)

	if dist > heal_range:
		_chase_toward(_target_ally.global_position, walk_speed, delta)
		_body_material.albedo_color = Color(0.3, 0.85, 0.75, 1.0)
		_head_material.albedo_color = Color(0.35, 0.9, 0.8, 1.0)
	else:
		_stand_still(delta)
		_body_material.albedo_color = Color(0.6, 1.0, 0.9, 1.0)
		_head_material.albedo_color = Color(0.7, 1.0, 0.95, 1.0)

		if not _grabbing:
			_grabbing = true
			_grab_timer = heal_grab_duration

		if not _grabbing and _grab_timer <= 0.0:
			pass


# --- FLEE ---

func _is_player_in_panic_range() -> bool:
	var player := _get_player()
	if player == null:
		return false
	var dist := global_position.distance_to(player.global_position)
	return dist < panic_detect_range and _can_see_player_cached()


func _can_flee() -> bool:
	var now := Time.get_ticks_msec() * 0.001

	# trigger: el golpe mas reciente marca el inicio de la ventana de huida.
	if _last_hit_time > _flee_triggered_at:
		_flee_triggered_at = _last_hit_time

	if (now - _flee_triggered_at) < flee_duration:
		return true

	# trigger adicional: tensión alta (jugador muy cerca y/o con linea de
	# vision directa, sostenido en el tiempo) tambien fuerza huida, sin
	# necesidad de haber recibido un golpe directo todavía.
	return _tension_is_high()


enum FleeExit { NONE, REAL_COVER, SPRINT_TIMEOUT }

func _get_flee_exit_reason() -> FleeExit:
	# llamar SOLO mientras _current_action == FLEE: _action_elapsed se
	# interpreta aquí como "tiempo corrido en este tramo de sprint".

	# eviter la oscilación FLEE ↔ RECOVER frame a frame: huir al menos 1s
	# antes de evaluar si llegamos a destino.
	if _action_elapsed < 1.0:
		return FleeExit.NONE

	# si el healer está cerca del flee_target, considera que llegó a destino
	# (cobertura real o punto de huida) y pasa a recuperarse.
	var dist_sq := global_position.distance_squared_to(_flee_target)
	if dist_sq < 9.0:
		return FleeExit.REAL_COVER

	# sin cobertura real todavía: si ya corrio flee_sprint_duration segundos
	# en este tramo, toca un descanso corto (WINDED) y luego reevaluar, en
	# vez de seguir huyendo indefinidamente. (actualmente esta corriendo en linea recta, no se pq mierda)
	if _action_elapsed >= flee_sprint_duration:
		return FleeExit.SPRINT_TIMEOUT

	return FleeExit.NONE


func _enter_flee() -> void:
	_flee_target = _get_flee_target_from_player()
	_body_material.albedo_color = Color(0.9, 0.3, 0.3, 1.0)
	_head_material.albedo_color = Color(1.0, 0.4, 0.4, 1.0)


func _execute_flee(delta: float) -> void:
	var dist_to_target := global_position.distance_to(_flee_target)
	if dist_to_target < 2.0:
		# recalculos posteriores: alejarse del jugador en línea recta, sin
		# volver a atarse a la posición de un aliado.
		_flee_target = _get_flee_target_from_player()

	# _chase_toward ya orienta visualmente al healer hacia la dirección REAL
	# de movimiento (la que da el NavigationAgent3D, que puede rodear una
	# pared)(o eso deberia pero todo el sistema de navigation esta medio roto XD ).
	# antes habia aca una segunda rotación forzando "mirar en línea
	# recta lejos del jugador" sin importar hacia dónde se movía el cuerpo
	# realmente, pero si el path rodeaba un obstaculo, el personaje terminaba
	# movierndose hacia un lado mientras visualmente miraba hacia otro
	# (caminando "de espaldas" respecto a su propia orientación). Se quito:
	# la rotación de _chase_toward ya es la correcta en todos los casos.
	_chase_toward(_flee_target, walk_speed * flee_speed_mult, delta)


# --- RECOVER ---
# se entra aquí justo después de FLEE, una vez que _has_reached_safety() dio
# true (encontró cobertura real o ya está a safe_distance_fallback delj ugador).
# el healer se queda quieto "recuperando aliento" durante
# recover_duration segundos antes de volver a evaluar curar/cobertura. Si lo
# golpean durante este tiempo, _can_flee() vuelve a true y _evaluate_best_action
# saca de RECOVER de inmediato en la próxima evaluación.

func _enter_recover() -> void:
	_recover_timer = recover_duration
	_target_ally = null
	_body_material.albedo_color = Color(0.5, 0.5, 0.55, 1.0)
	_head_material.albedo_color = Color(0.55, 0.55, 0.6, 1.0)


func _execute_recover(delta: float) -> void:
	_recover_timer = maxf(_recover_timer - delta, 0.0)
	_stand_still(delta)


# --- Winded ---
# Distinto de RECOVER: aquí el healer no encontró cobertura real, solo
# agoto un tramo de sprint (flee_sprint_duration) huyendo en linea recta.
# Se detiene exhausto, sin esconderse de verdad — el jugador puede seguir
# cerca. es una pausa corta y tensa (winded_duration, 4-5s), no un respiro
# seguro. Aal terminar, _evaluate_best_action revisa si el jugador sigue
# cerca: vuelve a FLEE para otro tramo de sprint; si no, pasa a evaluación normal.
#actualmente esta es la unica wea que hace, creo que es algo con el pathing y por eso no detecta nada

func _enter_winded() -> void:
	_winded_timer = winded_duration
	_target_ally = null
	_body_material.albedo_color = Color(0.7, 0.55, 0.3, 1.0)
	_head_material.albedo_color = Color(0.75, 0.6, 0.35, 1.0)


func _execute_winded(delta: float) -> void:
	_winded_timer = maxf(_winded_timer - delta, 0.0)
	_stand_still(delta)


# --- Idle ---
# el healer debe mantenerse cerca de sus aliados para poder curarlos, no
# aislarse en cobertura como un enemigo cualquiera. en IDLE busca una
# posición cerca del aliado más cercano (o cobertura si no hay aliados).
# la huida y el pánico viven en el sistema de Tensión, no en IDLE.

func _enter_idle() -> void:
	_cover_target = _find_idle_position()
	_cover_recalc_cooldown = COVER_RECALC_INTERVAL


func _execute_idle(delta: float) -> void:
	_execute_static_cover(delta)


func _execute_static_cover(delta: float) -> void:
	if _cover_recalc_cooldown > 0.0:
		_cover_recalc_cooldown = maxf(_cover_recalc_cooldown - delta, 0.0)

	_cover_memory_scan_timer -= delta
	if _cover_memory_scan_timer <= 0.0:
		_cover_memory_scan_timer = COVER_MEMORY_SCAN_INTERVAL
		var player := _get_player()
		var space := get_world_3d().direct_space_state
		if player != null and space != null:
			_refresh_cover_memory(player, space)

	var dist_to_cover := global_position.distance_to(_cover_target)
	var reached_cover := dist_to_cover < 1.0
	var stale_timer := _action_elapsed > 5.0

	# el cooldown evita que
	# esto dispare cover_scan_rays raycasts en cada frame mientras camino
	# expuesto hacia el punto destino.
	var exposed := false
	if _cover_recalc_cooldown <= 0.0:
		var player := _get_player()
		var space := get_world_3d().direct_space_state
		if player != null and space != null:
			exposed = not _is_position_hidden_from_player(global_position, player, space)

	if reached_cover or stale_timer or exposed:
		_cover_target = _find_idle_position()
		_action_elapsed = 0.0
		_cover_recalc_cooldown = COVER_RECALC_INTERVAL

	if _cover_target.distance_squared_to(global_position) > 0.01:
		_chase_toward(_cover_target, walk_speed * 0.6, delta)
	else:
		_stand_still(delta)
	_reset_material_colors()
