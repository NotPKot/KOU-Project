extends Area3D

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

@export_group("Budget")
@export var budget_start: int = 4
@export var budget_max: int = 8
@export var budget_ramp: float = 60.0

@export_group("Roles")
@export var max_pressure: int = 3
@export var min_pressure: int = 1
@export var max_control: int = 2
@export var max_support: int = 1
@export var min_offensive_for_support: int = 2

@export_group("Audio")
@export var slash_sfx: AudioStream

var _activated: bool = false
var _elapsed: float = 0.0
var _spawn_timer: float = 0.0
var _alive_entries: Array[Dictionary] = []

var _enemies: Array[EnemyData] = []


func _ready() -> void:
	_enemies = [
		EnemyData.new(preload("res://scenes/enemies/BasicEnemy.tscn"), Role.PRESSURE, 1, 60, "Basic"),
		EnemyData.new(preload("res://scenes/enemies/CalmyrEnemy.tscn"), Role.CONTROL, 2, 25, "Calmyr"),
		EnemyData.new(preload("res://scenes/enemies/HealerEnemy.tscn"), Role.SUPPORT,    2, 15, "Healer"),
	]
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
	_play_slash()
	MusicManager.set_state(MusicManager.EMusicState.COMBAT)


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
	var t := minf(_elapsed / budget_ramp, 1.0)
	return roundi(lerpf(float(budget_start), float(budget_max), t))


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
			return _count_role(Role.PRESSURE) < max_pressure
		Role.CONTROL:
			return _count_role(Role.CONTROL) < max_control and _count_role(Role.PRESSURE) >= min_pressure
		Role.SUPPORT:
			return _count_role(Role.SUPPORT) < max_support and _total_offensive() >= min_offensive_for_support
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
	enemy.global_position = global_position + Vector3(cos(angle), 0.0, sin(angle)) * dist
	get_tree().current_scene.add_child(enemy)
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

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _get_spawn_interval()

	_spawn_cycle()
