extends Area3D

signal combat_started
signal wave_changed(wave: int)
signal combat_ended

enum Role { PRESSURE, CONTROL, SUPPORT }

class EnemyData:
	var scene: PackedScene
	var role: Role
	var cost: int
	var weight: int
	var name: String

	func _init(s: PackedScene, r: Role, c: int, w: int, n: String):
		scene = s; role = r; cost = c; weight = w; name = n

@export_group("Spawn")
@export var wave_duration: float = 12.0
@export var wave_budget_start: int = 15
@export var wave_budget_per_wave: int = 15
@export var spawn_radius: float = 8.0
@export var spawn_min_distance: float = 3.0
@export var spawn_cooldown: float = 0.8
@export var healer_weight: int = 8

@export_group("Waves")
@export var intermission_duration: float = 6.5
@export var max_waves: int = 0 # 0 = oleadas infinitas

@export_group("Roles Base")
@export var base_max_pressure: int = 3
@export var base_max_control: int = 2
@export var base_max_support: int = 1
@export var min_pressure: int = 1
@export var min_offensive_for_support: int = 1

@export_group("Role Scaling (per N waves)")
@export var pressure_scale_interval: int = 3
@export var control_scale_interval: int = 4
@export var support_scale_interval: int = 5

@export_group("Audio")
@export var slash_sfx: AudioStream

var _activated: bool = false
var _elapsed: float = 0.0
var _alive_entries: Array[Dictionary] = []
var _current_wave: int = 1
var _wave_total_budget: float = 0.0
var _wave_budget_spent: float = 0.0
var _accrued_spawn_value: float = 0.0
var _spawn_pause_timer: float = 0.0
var _waiting_for_wave_clear: bool = false

var _enemies: Array[EnemyData] = []
var _last_spawn_time: float = -INF


func _ready() -> void:
	_enemies = [
		EnemyData.new(preload("res://scenes/enemies/BasicEnemy.tscn"), Role.PRESSURE, 1, 60, "Basic"),
		EnemyData.new(preload("res://scenes/enemies/CalmyrEnemy.tscn"), Role.CONTROL, 2, 25, "Calmyr"),
		EnemyData.new(preload("res://scenes/enemies/HealerEnemy.tscn"), Role.SUPPORT,    2, healer_weight, "Healer"),
	]
	add_to_group("combat_button")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _activated:
		return
	if not body.is_in_group("player"):
		return
	activate()


func activate() -> void:
	if _activated:
		return
	_activated = true
	_current_wave = 1
	_wave_total_budget = wave_budget_start
	_wave_budget_spent = 0.0
	_accrued_spawn_value = 0.0
	_spawn_pause_timer = intermission_duration
	_waiting_for_wave_clear = false
	_play_slash()
	combat_started.emit()


func _play_slash() -> void:
	if slash_sfx == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = slash_sfx
	p.bus = "SFX"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _get_max_pressure() -> int:
	return base_max_pressure + int(float(_current_wave - 1) / pressure_scale_interval)


func _get_max_control() -> int:
	return base_max_control + int(float(_current_wave - 1) / control_scale_interval)


func _get_max_support() -> int:
	return base_max_support + int(float(_current_wave - 1) / support_scale_interval)


func _count_role(role: Role) -> int:
	var n := 0
	for d in _alive_entries:
		if d.role == role:
			n += 1
	return n


func _total_offensive() -> int:
	return _count_role(Role.PRESSURE) + _count_role(Role.CONTROL)


func _can_spawn(ed: EnemyData) -> bool:
	match ed.role:
		Role.PRESSURE:
			return _count_role(Role.PRESSURE) < _get_max_pressure()
		Role.CONTROL:
			return _count_role(Role.CONTROL) < _get_max_control() and _count_role(Role.PRESSURE) >= min_pressure
		Role.SUPPORT:
			if _count_role(Role.SUPPORT) >= _get_max_support():
				return false
			if _total_offensive() < min_offensive_for_support:
				return false
			if _alive_entries.is_empty():
				return false
			var has_ally := false
			for d in _alive_entries:
				if d.role != Role.SUPPORT:
					has_ally = true
					break
			if not has_ally:
				return false
			return true
	return true


func _try_spawn() -> bool:
	if _elapsed - _last_spawn_time < spawn_cooldown:
		return false

	var valid_all := _get_valid_enemies()
	if valid_all.is_empty():
		return false

	var pick := _pick(valid_all)
	if pick.is_empty():
		return false

	var ed: EnemyData = pick.data
	if _accrued_spawn_value < ed.cost:
		return false

	_accrued_spawn_value -= ed.cost
	_wave_budget_spent += ed.cost
	_place_enemy(ed)
	_last_spawn_time = _elapsed
	return true


func _get_valid_enemies() -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	var budget_remaining := _wave_total_budget - _wave_budget_spent
	for ed in _enemies:
		if ed.cost > _accrued_spawn_value:
			continue
		if ed.cost > budget_remaining:
			continue
		if not _can_spawn(ed):
			continue
		result.append(ed)
	return result


func get_wave_progress() -> float:
	if _wave_total_budget <= 0.0:
		return 0.0
	return clampf(_wave_budget_spent / _wave_total_budget, 0.0, 1.0)


func is_in_intermission() -> bool:
	return _spawn_pause_timer > 0.0 or _waiting_for_wave_clear


func _pick(candidates: Array) -> Dictionary:
	var total := 0
	for c in candidates:
		total += c.weight
	if total == 0:
		return {}
	var roll := randi() % total
	var acc := 0
	for c in candidates:
		acc += c.weight
		if roll < acc:
			return {"data": c, "cost": c.cost}
	return {}


func _place_enemy(ed: EnemyData) -> void:
	var enemy := ed.scene.instantiate()
	var angle := randf() * TAU
	var dist := spawn_min_distance + randf() * (spawn_radius - spawn_min_distance)
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = global_position + Vector3(cos(angle), 0.0, sin(angle)) * dist
	if enemy.has_method("set_target"):
		var player := get_tree().get_first_node_in_group("player")
		if player != null:
			enemy.set_target(player)
	_alive_entries.append({"node": enemy, "role": ed.role})


func _process(delta: float) -> void:
	if not _activated:
		return

	_elapsed += delta
	_alive_entries = _alive_entries.filter(func(d): return is_instance_valid(d.node))

	# Una oleada termina al gastar su presupuesto, pero la siguiente no comienza
	# hasta que el jugador haya limpiado a todos los enemigos que quedan.
	if _waiting_for_wave_clear:
		if not _alive_entries.is_empty():
			return

		if max_waves > 0 and _current_wave >= max_waves:
			combat_ended.emit()
			_activated = false
			return

		_begin_intermission()
		return

	if _spawn_pause_timer > 0.0:
		_spawn_pause_timer = maxf(_spawn_pause_timer - delta, 0.0)
		if _spawn_pause_timer <= 0.0:
			MusicManager.set_state(MusicManager.EMusicState.COMBAT)
		return

	var budget_remaining := _wave_total_budget - _wave_budget_spent
	if budget_remaining > 0.0:
		_accrued_spawn_value += (_wave_total_budget / wave_duration) * delta
		_accrued_spawn_value = minf(_accrued_spawn_value, budget_remaining)

		var attempts := 3
		while attempts > 0:
			if not _try_spawn():
				break
			attempts -= 1

	if _wave_budget_spent >= _wave_total_budget:
		_waiting_for_wave_clear = true


func _begin_intermission() -> void:
	_current_wave += 1
	_wave_total_budget = wave_budget_start + (_current_wave - 1) * wave_budget_per_wave
	_wave_budget_spent = 0.0
	_accrued_spawn_value = 0.0
	_spawn_pause_timer = intermission_duration
	_waiting_for_wave_clear = false
	wave_changed.emit(_current_wave)
