extends Node

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "preferences"

var screen_shake_enabled: bool = true
var screen_shake_intensity: float = 1.0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	screen_shake_enabled = cfg.get_value(SECTION, "screen_shake_enabled", true)
	screen_shake_intensity = cfg.get_value(SECTION, "screen_shake_intensity", 1.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "screen_shake_enabled", screen_shake_enabled)
	cfg.set_value(SECTION, "screen_shake_intensity", screen_shake_intensity)
	cfg.save(SETTINGS_PATH)
