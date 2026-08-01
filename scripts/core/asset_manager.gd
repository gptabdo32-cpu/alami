extends Node

signal scene_registered(key: StringName)
signal material_registered(key: StringName)
signal asset_cache_cleared

const DEFAULT_SCENE_PATHS := {
	&"world_chunk": "res://scenes/world/chunk.tscn",
	&"city_model": "res://assets/models/city/city_model.fbx"
}

var scene_cache: Dictionary = {}
var material_cache: Dictionary = {}
var mesh_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_default_scenes()
	_register_default_materials()

func _register_default_scenes() -> void:
	for key in DEFAULT_SCENE_PATHS.keys():
		register_scene(key, DEFAULT_SCENE_PATHS[key])

func _register_default_materials() -> void:
	if not material_cache.has(&"terrain"):
		material_cache[&"terrain"] = _make_terrain_material()
		material_registered.emit(&"terrain")
	if not material_cache.has(&"trunk"):
		material_cache[&"trunk"] = _solid_material(Color(0.34, 0.23, 0.12), 0.97)
		material_registered.emit(&"trunk")
	if not material_cache.has(&"leaf"):
		material_cache[&"leaf"] = _solid_material(Color(0.17, 0.40, 0.18), 0.96)
		material_registered.emit(&"leaf")
	if not material_cache.has(&"rock"):
		material_cache[&"rock"] = _solid_material(Color(0.53, 0.53, 0.55), 0.99)
		material_registered.emit(&"rock")
	if not material_cache.has(&"bush"):
		material_cache[&"bush"] = _solid_material(Color(0.20, 0.42, 0.17), 0.95)
		material_registered.emit(&"bush")

func register_scene(key: StringName, source: Variant) -> void:
	var packed: PackedScene = null
	if source is PackedScene:
		packed = source
	elif source is String or source is StringName:
		var path := str(source)
		if ResourceLoader.exists(path):
			packed = load(path) as PackedScene
	if packed == null:
		return
	scene_cache[key] = packed
	scene_registered.emit(key)

func get_scene(key: StringName) -> PackedScene:
	var scene: Variant = scene_cache.get(key, null)
	if scene is PackedScene:
		return scene
	if DEFAULT_SCENE_PATHS.has(key):
		register_scene(key, DEFAULT_SCENE_PATHS[key])
		scene = scene_cache.get(key, null)
		if scene is PackedScene:
			return scene
	return null

func instantiate_scene(key: StringName) -> Node:
	var scene := get_scene(key)
	if scene == null:
		return null
	return scene.instantiate()

func register_material(key: StringName, material: Material) -> void:
	if material == null:
		return
	material_cache[key] = material
	material_registered.emit(key)

func get_material(key: StringName) -> Material:
	var material: Variant = material_cache.get(key, null)
	if material is Material:
		return material
	return null

func get_terrain_material() -> ShaderMaterial:
	var material := get_material(&"terrain")
	if material is ShaderMaterial:
		return material
	return _make_terrain_material()

func get_trunk_material() -> StandardMaterial3D:
	var material := get_material(&"trunk")
	if material is StandardMaterial3D:
		return material
	var fallback := _solid_material(Color(0.34, 0.23, 0.12), 0.97)
	material_cache[&"trunk"] = fallback
	return fallback

func get_leaf_material() -> StandardMaterial3D:
	var material := get_material(&"leaf")
	if material is StandardMaterial3D:
		return material
	var fallback := _solid_material(Color(0.17, 0.40, 0.18), 0.96)
	material_cache[&"leaf"] = fallback
	return fallback

func get_rock_material() -> StandardMaterial3D:
	var material := get_material(&"rock")
	if material is StandardMaterial3D:
		return material
	var fallback := _solid_material(Color(0.53, 0.53, 0.55), 0.99)
	material_cache[&"rock"] = fallback
	return fallback

func get_bush_material() -> StandardMaterial3D:
	var material := get_material(&"bush")
	if material is StandardMaterial3D:
		return material
	var fallback := _solid_material(Color(0.20, 0.42, 0.17), 0.95)
	material_cache[&"bush"] = fallback
	return fallback

func register_mesh(key: StringName, mesh: Mesh) -> void:
	if mesh == null:
		return
	mesh_cache[key] = mesh

func get_mesh(key: StringName) -> Mesh:
	var mesh: Variant = mesh_cache.get(key, null)
	if mesh is Mesh:
		return mesh
	return null

func clear_caches() -> void:
	scene_cache.clear()
	material_cache.clear()
	mesh_cache.clear()
	_register_default_scenes()
	_register_default_materials()
	asset_cache_cleared.emit()

func _make_terrain_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, specular_schlick_ggx, diffuse_burley;

uniform vec4 terrain_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 world_pos;
varying float slope_amount;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope_amount = clamp(1.0 - NORMAL.y, 0.0, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float grid_noise = hash(floor(world_pos.xz * 0.55));
	c *= 0.95 + grid_noise * 0.08;
	c = mix(c, vec3(0.46, 0.48, 0.50), smoothstep(0.46, 0.95, slope_amount) * 0.62);
	float height_factor = clamp((world_pos.y + 16.0) / 60.0, 0.0, 1.0);
	c = mix(c * 0.88, c, height_factor);
	ALBEDO = c * terrain_tint.rgb;
	ROUGHNESS = 0.98;
	SPECULAR = 0.03;
}
"""
	material.shader = shader
	material.set_shader_parameter("terrain_tint", Color(1.0, 1.0, 1.0, 1.0))
	return material

func _solid_material(color: Color, roughness: float = 0.95) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material
