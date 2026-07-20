class_name StatusEffectController
extends Node

signal stun_started
signal stun_ended
signal effect_changed(effect_name: String)

var is_stunned: bool = false
var speed_multiplier: float = 1.0
var is_burning: bool = false

var _timers: Dictionary = {}


func apply_effect(effect_name: String, duration: float, value: float = 1.0) -> void:
	match effect_name:
		"stun":
			if is_stunned:
				_timers[effect_name] = maxf(_timers.get(effect_name, 0.0), duration)
				return
			is_stunned = true
			stun_started.emit()
		"slow":
			speed_multiplier = value
		"burn":
			if is_burning:
				_timers[effect_name] = maxf(_timers.get(effect_name, 0.0), duration)
				return
			is_burning = true

	if _timers.has(effect_name):
		_timers[effect_name] = maxf(_timers[effect_name], duration)
	else:
		_timers[effect_name] = duration
	effect_changed.emit(effect_name)


func remove_effect(effect_name: String) -> void:
	if not _timers.has(effect_name):
		return
	_clear_effect(effect_name)


func _process(delta: float) -> void:
	if _timers.is_empty():
		return

	for effect_name in _timers.keys():
		_timers[effect_name] -= delta
		if _timers[effect_name] <= 0.0:
			_clear_effect(effect_name)


func _clear_effect(effect_name: String) -> void:
	match effect_name:
		"stun":
			is_stunned = false
			stun_ended.emit()
		"slow":
			speed_multiplier = 1.0
		"burn":
			is_burning = false
	_timers.erase(effect_name)
	effect_changed.emit(effect_name)
