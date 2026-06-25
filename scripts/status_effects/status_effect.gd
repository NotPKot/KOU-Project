class_name StatusEffect
extends RefCounted

var effect_name: String
var duration: float
var remaining: float
var target: Node


func _init(p_name: String, p_duration: float):
	effect_name = p_name
	duration = p_duration
	remaining = p_duration


func apply(node: Node) -> void:
	target = node


func tick(delta: float) -> bool:
	remaining -= delta
	return remaining <= 0.0


func remove() -> void:
	pass
