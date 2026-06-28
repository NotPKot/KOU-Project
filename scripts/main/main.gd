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

	_setup_navmesh()


func _setup_navmesh() -> void:
	var nav_region := $NavigationRegion3D as NavigationRegion3D
	if nav_region == null:
		return

	var nav_mesh := NavigationMesh.new()
	var half := 60.0
	nav_mesh.vertices = PackedVector3Array([
		Vector3(-half, 0, -half),
		Vector3( half, 0, -half),
		Vector3( half, 0,  half),
		Vector3(-half, 0,  half),
	])
	nav_mesh.set("_polygons", [
		PackedInt32Array([0, 1, 2]),
		PackedInt32Array([0, 2, 3]),
	])
	nav_region.navmesh = nav_mesh
