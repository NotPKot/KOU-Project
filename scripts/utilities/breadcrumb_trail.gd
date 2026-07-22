extends Node

@export var record_interval: float = 0.2
@export var max_points: int = 40
@export var min_step: float = 1.5

var trail: Array[Vector3] = []
var _timer: float = 0.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer < record_interval:
		return
	_timer = 0.0

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	if not player.has_method("is_on_floor") or not player.is_on_floor():
		return

	var pos := player.global_position
	if trail.is_empty() or trail[-1].distance_squared_to(pos) > min_step * min_step:
		trail.append(pos)
		if trail.size() > max_points:
			trail.pop_front()


func get_target(from_pos: Vector3, to_pos: Vector3) -> Vector3:
	if trail.is_empty():
		return to_pos

	var best: Vector3 = to_pos
	var best_score := INF

	for p in trail:
		var dist_from := p.distance_squared_to(from_pos)
		var dist_to := p.distance_squared_to(to_pos)
		var score := dist_to + dist_from * 0.5
		if score < best_score:
			best_score = score
			best = p

	return best
