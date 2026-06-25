class_name StatusEffect
extends RefCounted

var effect_name: String
var duration: float
var remaining: float
var _target_ref: WeakRef


func _init(p_name: String, p_duration: float):
	effect_name = p_name
	duration = p_duration
	remaining = p_duration


func apply(node: Node) -> void:
	_target_ref = weakref(node)


func get_target() -> Node:
	return _target_ref.get_ref() if _target_ref else null


func tick(delta: float) -> bool:
	remaining -= delta
	return remaining <= 0.0


func remove() -> void:
	pass
