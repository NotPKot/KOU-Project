extends Node

const RIFT_DIAMOND_CONTROL := preload("res://scripts/ui/rift_diamond_control.gd")
const SLASH_EFFECT_SCENE := preload("res://scenes/effects/combat/SlashEffect.tscn")

signal rift_cast(rift_id: StringName)
signal sequence_failed(sequence: PackedStringArray)

const MAX_RIFT_CHARGES := 3
const MAX_SEQUENCE_LENGTH := 4
const RIFT_TIME_SCALE := 0.28
const RIFT_CURSOR_RADIUS := 120.0
const RIFT_CENTER_DEADZONE := 28.0
const BASE_SLASH_DAMAGE := 10.0

const RIFTS := {
	"up,down": {"id": &"temporal_impulse", "cost": 1, "name": "Impulso Temporal"},
	"left,right,up": {"id": &"kinetic_fragment", "cost": 1, "name": "Fragmento Cinetico"},
	"up,right,down,left": {"id": &"temporal_bubble", "cost": 1, "name": "Burbuja Temporal"},
	"right,left": {"id": &"universal_slash", "cost": 1, "name": "Tajo Universal"},
	"down,up,down,up": {"id": &"kinetic_overload", "cost": 3, "name": "Sobrecarga Cinetica"},
}

@export var damage_per_charge: float = 30.0
@export var attack_cooldown_msec: int = 400
@export var rift_cancel_cooldown: float = 4.0

# -- CRONOMETRO SLASH TUNING
@export var slash_spawn_height: float = 1.25
@export var slash_forward_offset: float = 0.75
@export var slash_base_range: float = 1.55
@export var slash_scale: float = 1.0
@export var slash_variant_cycle: bool = true
@export var slash_random_variants: bool = false

const SLASH_VARIANTS := [
	{"yaw": 0.0, "roll": -22.0, "range": 1.0},
	{"yaw": -14.0, "roll": 18.0, "range": 0.92},
	{"yaw": 16.0, "roll": 0.0, "range": 1.12},
]

var _owner_player: CharacterBody3D = null
var _camera_pivot: Node3D = null
var _enabled := false
var _rift_charges := 0
var _accumulated_damage: float = 0.0
var _hud_dirty: bool = true
var _rift_open := false
var _rift_cooldown_until_msec := 0
var _mouse_mode_before_rift := Input.MOUSE_MODE_CAPTURED
var _sequence := PackedStringArray()
var _rift_cursor_offset := Vector2.ZERO
var _hovered_direction := ""
var _hud: CanvasLayer = null
var _charge_label: Label = null
var _rift_panel: Control = null
var _rift_diamond: Control = null
var _status_label: Label = null
var _slash_index := 0
var _last_attack_msec: int = 0


func equip(owner_player: CharacterBody3D) -> void:
	_owner_player = owner_player
	_camera_pivot = _owner_player.get_node("CameraPivot") as Node3D
	_enabled = true
	_build_hud()
	_hud_dirty = true


func unequip() -> void:
	_close_rift(false)
	_enabled = false
	if _hud != null:
		_hud.queue_free()


func _exit_tree() -> void:
	if _rift_open:
		Engine.time_scale = 1.0


func _process(_delta: float) -> void:
	if not _enabled:
		return
	if _hud_dirty:
		_update_hud()
		_hud_dirty = false


func _input(event: InputEvent) -> void:
	if not _enabled:
		return

	if _owner_player != null and _owner_player.has_method("is_input_locked") and _owner_player.is_input_locked():
		return

	var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
	if mouse_motion != null and _rift_open:
		_read_rift_direction(mouse_motion.position)
		get_viewport().set_input_as_handled()
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null:
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed and not _rift_open:
			var now: int = Time.get_ticks_msec()
			if now - _last_attack_msec < attack_cooldown_msec:
				return
			_last_attack_msec = now
			_basic_attack()
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_button.pressed:
				_try_open_rift()
			else:
				_release_rift()
			get_viewport().set_input_as_handled()


func _basic_attack() -> void:
	_spawn_basic_slash()
	_status_label.text = "Golpe"


func _spawn_basic_slash() -> void:
	if _owner_player == null:
		return

	var variant: Dictionary = _get_next_slash_variant()
	var cam_basis: Basis = _camera_pivot.global_transform.basis
	var forward: Vector3 = Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()

	var slash: Node3D = SLASH_EFFECT_SCENE.instantiate() as Node3D
	if slash == null:
		return

	slash.damage = BASE_SLASH_DAMAGE
	slash.global_position = _owner_player.global_position + forward * slash_forward_offset
	var yaw: float = atan2(-forward.x, -forward.z) + deg_to_rad(float(variant["yaw"]))
	var roll: float = deg_to_rad(float(variant["roll"]))
	var range_value: float = slash_base_range * float(variant["range"])

	if slash.has_method("setup"):
		slash.setup(range_value, slash_spawn_height, yaw, roll, slash_scale)

	get_tree().current_scene.add_child(slash)

	var hitbox: Area3D = slash.get_node("Hitbox")
	if hitbox != null:
		hitbox.body_entered.connect(_on_slash_hit.bind(slash.damage))


func _get_next_slash_variant() -> Dictionary:
	if slash_random_variants:
		return SLASH_VARIANTS[randi() % SLASH_VARIANTS.size()]

	var variant: Dictionary = SLASH_VARIANTS[_slash_index]
	if slash_variant_cycle:
		_slash_index = (_slash_index + 1) % SLASH_VARIANTS.size()

	return variant


func _on_slash_hit(body: Node, damage: int) -> void:
	if body.has_method("take_damage"):
		_add_damage(damage)


func _add_damage(amount: float) -> void:
	_accumulated_damage += amount
	while _accumulated_damage >= damage_per_charge:
		_accumulated_damage -= damage_per_charge
		_rift_charges = min(_rift_charges + 1, MAX_RIFT_CHARGES)
		_hud_dirty = true
		_status_label.text = "Carga RIFT +1"


func _try_open_rift() -> void:
	if _rift_open:
		return

	var now_msec := Time.get_ticks_msec()
	if now_msec < _rift_cooldown_until_msec:
		_status_label.text = "Rift en cooldown"
		return

	if _rift_charges <= 0:
		_status_label.text = "Sin cargas Rift"
		return

	_sequence.clear()
	_rift_cursor_offset = Vector2.ZERO
	_hovered_direction = ""
	_rift_open = true
	Engine.time_scale = RIFT_TIME_SCALE
	_mouse_mode_before_rift = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	_rift_panel.visible = true
	_status_label.text = "Rift abierto"
	_update_rift_diamond()
	call_deferred("_center_rift_mouse")

	if _owner_player != null and _owner_player.has_method("set_aim_locked"):
		_owner_player.set_aim_locked(true)


func _release_rift() -> void:
	if not _rift_open:
		return

	if _sequence.is_empty():
		_rift_cooldown_until_msec = Time.get_ticks_msec() + int(rift_cancel_cooldown * 1000.0)
		_status_label.text = "Rift cancelado"
		_close_rift(false)
		return

	_execute_sequence()


func _execute_sequence() -> void:
	var key := ",".join(_sequence)
	if not RIFTS.has(key):
		_apply_sequence_failure()
		_close_rift(true)
		return

	var rift: Dictionary = RIFTS[key]
	var cost := int(rift["cost"])
	if _rift_charges < cost:
		_status_label.text = "Carga insuficiente"
		_close_rift(true)
		return

	_rift_charges -= cost
	_hud_dirty = true
	_status_label.text = str(rift["name"])
	var rift_id: StringName = rift["id"]
	_apply_rift_effect(rift_id)
	rift_cast.emit(rift_id)
	_close_rift(true)


func _apply_sequence_failure() -> void:
	if _rift_charges > 0:
		_rift_charges -= 1
		_hud_dirty = true

	_status_label.text = "Falla critica"
	sequence_failed.emit(_sequence)
	print("Cronometro Roto: falla critica. Dano al usuario pendiente: 25% vida maxima.")


func _apply_rift_effect(rift_id: StringName) -> void:
	match rift_id:
		&"temporal_impulse":
			if _owner_player != null and _owner_player.has_method("apply_temporal_impulse"):
				_owner_player.apply_temporal_impulse()
		&"kinetic_fragment":
			print("Cronometro Roto: disparar proyectil Fragmento Cinetico.")
		&"temporal_bubble":
			print("Cronometro Roto: crear Burbuja Temporal.")
		&"universal_slash":
			print("Cronometro Roto: emitir Tajo Universal.")
		&"kinetic_overload":
			print("Cronometro Roto: ejecutar Sobrecarga Cinetica.")


func _close_rift(successful_cast: bool) -> void:
	_rift_open = false
	Engine.time_scale = 1.0
	Input.set_mouse_mode(_mouse_mode_before_rift)

	if _rift_panel != null:
		_rift_panel.visible = false

	if _owner_player != null and _owner_player.has_method("set_aim_locked"):
		_owner_player.set_aim_locked(false)


func _read_rift_direction(mouse_position: Vector2) -> void:
	_rift_cursor_offset = mouse_position - _get_rift_center_screen_position()
	_rift_cursor_offset = _rift_cursor_offset.limit_length(RIFT_CURSOR_RADIUS)
	_update_hovered_direction()
	_update_rift_diamond()

	if _hovered_direction.is_empty():
		return

	if _sequence.size() > 0 and _sequence[_sequence.size() - 1] == _hovered_direction:
		return

	if _sequence.size() >= MAX_SEQUENCE_LENGTH:
		return

	_sequence.append(_hovered_direction)
	_update_rift_diamond()


func _update_hovered_direction() -> void:
	if _rift_cursor_offset.length_squared() < RIFT_CENTER_DEADZONE * RIFT_CENTER_DEADZONE:
		_hovered_direction = ""
		return

	_hovered_direction = _direction_from_vector(_rift_cursor_offset)


func _update_rift_diamond() -> void:
	if _rift_diamond != null and _rift_diamond.has_method("set_rift_state"):
		_rift_diamond.set_rift_state(_hovered_direction, _sequence, _rift_cursor_offset)


func _center_rift_mouse() -> void:
	if not _rift_open:
		return

	get_viewport().warp_mouse(_get_rift_center_screen_position())


func _get_rift_center_screen_position() -> Vector2:
	if _rift_diamond == null:
		return get_viewport().get_visible_rect().size * 0.5

	return _rift_diamond.get_global_rect().get_center()


func _direction_from_vector(vector: Vector2) -> String:
	if absf(vector.x) > absf(vector.y):
		return "right" if vector.x > 0.0 else "left"

	return "down" if vector.y > 0.0 else "up"


func _update_hud() -> void:
	if _hud == null:
		return

	_charge_label.text = "RIFT " + str(_rift_charges) + "/" + str(MAX_RIFT_CHARGES)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "BrokenStopwatchHUD"
	_hud.layer = 12
	add_child(_hud)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	_charge_label = Label.new()
	_charge_label.name = "ChargeLabel"
	_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_label.add_theme_font_size_override("font_size", 16)
	_charge_label.anchor_left = 0.5
	_charge_label.anchor_top = 1.0
	_charge_label.anchor_right = 0.5
	_charge_label.anchor_bottom = 1.0
	_charge_label.offset_left = -60.0
	_charge_label.offset_top = -26.0
	_charge_label.offset_right = 60.0
	_charge_label.offset_bottom = -6.0
	root.add_child(_charge_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.anchor_left = 0.5
	_status_label.anchor_top = 0.0
	_status_label.anchor_right = 0.5
	_status_label.anchor_bottom = 0.0
	_status_label.offset_left = -160.0
	_status_label.offset_top = 10.0
	_status_label.offset_right = 160.0
	_status_label.offset_bottom = 34.0
	root.add_child(_status_label)

	_build_rift_panel(root)


func _build_rift_panel(root: Control) -> void:
	_rift_panel = PanelContainer.new()
	_rift_panel.name = "RiftPanel"
	_rift_panel.visible = false
	_rift_panel.anchor_left = 0.5
	_rift_panel.anchor_top = 0.5
	_rift_panel.anchor_right = 0.5
	_rift_panel.anchor_bottom = 0.5
	_rift_panel.offset_left = -180
	_rift_panel.offset_top = -180
	_rift_panel.offset_right = 180
	_rift_panel.offset_bottom = 180
	root.add_child(_rift_panel)

	_rift_diamond = Control.new()
	_rift_diamond.set_script(RIFT_DIAMOND_CONTROL)
	_rift_diamond.custom_minimum_size = Vector2(320, 320)
	_rift_panel.add_child(_rift_diamond)
