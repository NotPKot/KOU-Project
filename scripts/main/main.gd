extends Node3D

const HOOK_BLOCK_PATH := "res://scenes/worlds/hook_blocks/HookBlock.tscn"


func _ready() -> void:
	var hook_scene := load(HOOK_BLOCK_PATH) as PackedScene
	if hook_scene == null:
		push_error("Failed to load HookBlock scene")
		return

	var positions := [
		Vector3(5, 2.5, 0),
		Vector3(10, 2.5, 5),
		Vector3(15, 3.5, 0),
		Vector3(0, 3, -5),
		Vector3(-5, 4, 0),
	]
	for p in positions:
		var block := hook_scene.instantiate()
		block.position = p
		add_child(block)
