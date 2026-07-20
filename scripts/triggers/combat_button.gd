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
@export var spawn_interval_start: float = 2.5
@export var spawn_interval_min: float = 1.6
@export var ramp_time: float = 90.0
@export var spawn_radius: float = 8.0
@export var spawn_min_distance: float = 3.0

@export_group("Waves")
@export var wave_interval: float = 15.0
@export var budget_start: int = 4
@export var budget_per_wave: int = 5

@export_group("Roles Base")
@export var base_max_pressure: int = 3
@export var base_max_control: int = 2
@export var base_max_support: int = 1
@export var min_pressure: int = 1
@export var min_offensive_for_support: int = 2

@export_group("Role Scaling (per N waves)")
@export var pressure_scale_interval: int = 3
@export var control_scale_interval: int = 4
@export var support_scale_interval: int = 5

@export_group("Audio")
@export var slash_sfx: AudioStream

var _activated: bool = false
var _elapsed: float = 0.0
var _spawn_timer: float = 0.0
var _alive_entries: Array[Dictionary] = []
var _current_wave: int = 1

var _enemies: Array[EnemyData] = []


func _ready() -> void:
	_enemies = [
		EnemyData.new(preload("res://scenes/enemies/BasicEnemy.tscn"), Role.PRESSURE, 1, 60, "Basic"),
		EnemyData.new(preload("res://scenes/enemies/CalmyrEnemy.tscn"), Role.CONTROL, 2, 25, "Calmyr"),
		EnemyData.new(preload("res://scenes/enemies/HealerEnemy.tscn"), Role.SUPPORT,    2, 15, "Healer"),
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
	_spawn_timer = 1.0
	_current_wave = 1
	_play_slash()
	MusicManager.set_state(MusicManager.EMusicState.COMBAT)
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


func _get_spawn_interval() -> float:
	var t := minf(_elapsed / ramp_time, 1.0)
	return lerpf(spawn_interval_start, spawn_interval_min, t)


func _get_budget() -> int:
	return budget_start + (_current_wave - 1) * budget_per_wave


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
			return _count_role(Role.SUPPORT) < _get_max_support() and _total_offensive() >= min_offensive_for_support
	return true


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


func _spawn_cycle() -> void:
	var budget := _get_budget()
	while budget > 0:
		var valid: Array[EnemyData] = []
		for ed in _enemies:
			if ed.cost <= budget and _can_spawn(ed):
				valid.append(ed)
		if valid.is_empty():
			break
		var pick := _pick(valid)
		if pick.is_empty():
			break
		var ed: EnemyData = pick.data
		_place_enemy(ed)
		budget -= ed.cost


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

	var new_wave := int(_elapsed / wave_interval) + 1
	if new_wave != _current_wave:
		_current_wave = new_wave
		wave_changed.emit(_current_wave)

	_alive_entries = _alive_entries.filter(func(d): return is_instance_valid(d.node))

	if _alive_entries.is_empty() and _current_wave > 1:
		combat_ended.emit()
		_activated = false
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _get_spawn_interval()

	_spawn_cycle()
