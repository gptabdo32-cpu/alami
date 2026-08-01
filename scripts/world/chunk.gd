class_name WorldChunk
extends Node3D

signal activated(coordinates: Vector2i)

enum State { QUEUED, GENERATING, DATA_READY, BUILDING, ACTIVE, SLEEPING, UNLOADING }

var coordinates := Vector2i.ZERO
var lod_level := 0
var state := State.QUEUED
var collision_enabled := false
var chunk_size := 256.0
var terrain_mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var props_root: Node3D

static var terrain_material: ShaderMaterial
static var trunk_material: StandardMaterial3D
static var leaf_material: StandardMaterial3D
static var rock_material: StandardMaterial3D
static var bush_material: StandardMaterial3D

func configure(c: Vector2i, size: float, lod: int) -> void:
	coordinates = c
	chunk_size = size
	lod_level = lod
	name = "Chunk_%d_%d_LOD%d" % [c.x, c.y, lod]

func build_from_data(data: Dictionary, with_collision: bool) -> void:
	reset_content()
	state = State.BUILDING
	_ensure_materials()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	terrain_mesh_instance = MeshInstance3D.new()
	terrain_mesh_instance.name = "Terrain"
	terrain_mesh_instance.mesh = mesh
	terrain_mesh_instance.material_override = terrain_material
	terrain_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod_level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain_mesh_instance)

	_build_props(data)
	set_collision_enabled(with_collision, data)
	state = State.ACTIVE
	activated.emit(coordinates)

func reset_content() -> void:
	collision_enabled = false
	terrain_mesh_instance = null
	collision_body = null
	props_root = null
	for child in get_children():
		child.free()

func set_collision_enabled(enabled: bool, data: Dictionary = {}) -> void:
	if collision_enabled == enabled:
		return
	collision_enabled = enabled
	if not enabled:
		if is_instance_valid(collision_body):
			collision_body.queue_free()
		collision_body = null
		return
	if data.is_empty() or not data.has("heights"):
		return

	var shape := HeightMapShape3D.new()
	shape.map_width = int(data["resolution"]) + 1
	shape.map_depth = int(data["resolution"]) + 1
	shape.map_data = data["heights"]

	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var horizontal_scale := chunk_size / float(data["resolution"])
	shape_node.scale = Vector3(horizontal_scale, 1.0, horizontal_scale)

	collision_body = StaticBody3D.new()
	collision_body.name = "TerrainCollision"
	collision_body.add_child(shape_node)
	add_child(collision_body)

func set_sleeping(value: bool) -> void:
	state = State.SLEEPING if value else State.ACTIVE
	visible = not value
	process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT

func _build_props(data: Dictionary) -> void:
	if lod_level >= 2:
		return
	props_root = Node3D.new()
	props_root.name = "Props"
	add_child(props_root)
	_create_tree_multimesh(data.get("tree_transforms", []))
	_create_bush_multimesh(data.get("bush_transforms", []))
	_create_rock_multimesh(data.get("rock_transforms", []))

func _create_tree_multimesh(transforms: Array) -> void:
	if transforms.is_empty():
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 2.45
	var leaves := SphereMesh.new()
	leaves.radius = 1.18
	leaves.height = 2.15
	var trunk_mm := _make_multimesh(trunk, transforms, Vector3(0, 1.18, 0), trunk_material)
	var leaf_mm := _make_multimesh(leaves, transforms, Vector3(0, 3.0, 0), leaf_material)
	trunk_mm.visibility_range_end = 240.0
	leaf_mm.visibility_range_end = 260.0
	props_root.add_child(trunk_mm)
	props_root.add_child(leaf_mm)

func _create_bush_multimesh(transforms: Array) -> void:
	if transforms.is_empty():
		return
	var bush := SphereMesh.new()
	bush.radius = 0.48
	bush.height = 0.82
	var mm := _make_multimesh(bush, transforms, Vector3(0, 0.25, 0), bush_material)
	mm.visibility_range_end = 150.0
	props_root.add_child(mm)

func _create_rock_multimesh(transforms: Array) -> void:
	if transforms.is_empty():
		return
	var rock := SphereMesh.new()
	rock.radius = 0.7
	rock.height = 1.0
	var mm := _make_multimesh(rock, transforms, Vector3(0, 0.35, 0), rock_material)
	mm.visibility_range_end = 180.0
	props_root.add_child(mm)

func _make_multimesh(mesh: Mesh, transforms: Array, offset: Vector3, material: Material) -> MultiMeshInstance3D:
	mesh.surface_set_material(0, material)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		var t: Transform3D = transforms[i]
		t.origin += offset
		multi.set_instance_transform(i, t)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod_level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

static func _ensure_materials() -> void:
	if terrain_material != null:
		return
	terrain_material = AssetManager.get_terrain_material()
	trunk_material = AssetManager.get_trunk_material()
	leaf_material = AssetManager.get_leaf_material()
	rock_material = AssetManager.get_rock_material()
	bush_material = AssetManager.get_bush_material()
