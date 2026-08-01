extends Node

signal world_seed_changed(seed: int)
signal region_loaded(region_x: int, region_z: int, data: Dictionary)
signal cell_changed(chunk_x: int, chunk_z: int, data: Dictionary)
signal registry_changed

const WORLD_REGISTRY_PATH: String = "user://world/world_registry.json"

const REGION_TYPES: Array[String] = [
	"plain",
	"forest",
	"coastal",
	"hills",
	"mountain",
	"desert",
	"wetlands",
	"rocky"
]

var world_seed: int = 424242
var region_size_chunks: int = 4
var cell_size_meters: float = 500.0

var region_overrides: Dictionary = {}
var cell_overrides: Dictionary = {}
var loaded_regions: Dictionary = {}
var loaded_cells: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_directory()
	if not load_registry():
		reset_defaults(world_seed)

	func reset_defaults(p_seed: int = 424242) -> void:
		world_seed = p_seed
		region_size_chunks = 4
		cell_size_meters = 500.0
		region_overrides.clear()
		cell_overrides.clear()
		loaded_regions.clear()
		loaded_cells.clear()
		
		# Professional City Integration: Set chunk (0,0) as a city
		register_cell_override(Vector2i(0, 0), {
			"theme": "city",
			"flattening": 1.0,
			"vegetation_density": 0.0
		})
		
		world_seed_changed.emit(world_seed)
		registry_changed.emit()

func set_world_seed(p_seed: int) -> void:
	if world_seed == p_seed:
		return
	world_seed = p_seed
	world_seed_changed.emit(world_seed)
	registry_changed.emit()

func set_region_size_chunks(value: int) -> void:
	region_size_chunks = maxi(1, value)
	registry_changed.emit()

func set_cell_size_meters(value: float) -> void:
	cell_size_meters = maxf(1.0, value)
	registry_changed.emit()

func region_from_chunk(chunk: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(chunk.x) / float(region_size_chunks)),
		floori(float(chunk.y) / float(region_size_chunks))
	)

func region_key(region: Vector2i) -> String:
	return "%d:%d" % [region.x, region.y]

func cell_key(chunk: Vector2i) -> String:
	return "%d:%d" % [chunk.x, chunk.y]

func set_region_loaded(region: Vector2i, loaded: bool) -> void:
	var key := region_key(region)
	if loaded:
		loaded_regions[key] = true
	else:
		loaded_regions.erase(key)
	region_loaded.emit(region.x, region.y, get_region_data(region))
	registry_changed.emit()

func set_chunk_loaded(chunk: Vector2i, loaded: bool) -> void:
	var key := cell_key(chunk)
	if loaded:
		loaded_cells[key] = true
	else:
		loaded_cells.erase(key)
	cell_changed.emit(chunk.x, chunk.y, get_cell_data(chunk))
	registry_changed.emit()

func is_region_loaded(region: Vector2i) -> bool:
	return loaded_regions.has(region_key(region))

func is_chunk_loaded(chunk: Vector2i) -> bool:
	return loaded_cells.has(cell_key(chunk))

func build_snapshot() -> Dictionary:
	return {
		"world_seed": world_seed,
		"region_size_chunks": region_size_chunks,
		"cell_size_meters": cell_size_meters,
		"loaded_regions": loaded_regions.duplicate(true),
		"loaded_cells": loaded_cells.duplicate(true),
		"region_overrides": region_overrides.duplicate(true),
		"cell_overrides": cell_overrides.duplicate(true)
	}

func apply_snapshot(data: Dictionary) -> void:
	world_seed = int(data.get("world_seed", world_seed))
	region_size_chunks = maxi(1, int(data.get("region_size_chunks", region_size_chunks)))
	cell_size_meters = maxf(1.0, float(data.get("cell_size_meters", cell_size_meters)))

	loaded_regions.clear()
	loaded_cells.clear()
	region_overrides.clear()
	cell_overrides.clear()

	var region_loaded_data: Variant = data.get("loaded_regions", {})
	if typeof(region_loaded_data) == TYPE_DICTIONARY:
		loaded_regions = (region_loaded_data as Dictionary).duplicate(true)

	var cell_loaded_data: Variant = data.get("loaded_cells", {})
	if typeof(cell_loaded_data) == TYPE_DICTIONARY:
		loaded_cells = (cell_loaded_data as Dictionary).duplicate(true)

	var region_data: Variant = data.get("region_overrides", {})
	if typeof(region_data) == TYPE_DICTIONARY:
		region_overrides = (region_data as Dictionary).duplicate(true)

	var cell_data: Variant = data.get("cell_overrides", {})
	if typeof(cell_data) == TYPE_DICTIONARY:
		cell_overrides = (cell_data as Dictionary).duplicate(true)

	world_seed_changed.emit(world_seed)
	registry_changed.emit()

func load_registry() -> bool:
	if not FileAccess.file_exists(WORLD_REGISTRY_PATH):
		return false

	var file := FileAccess.open(WORLD_REGISTRY_PATH, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	apply_snapshot(parsed)
	return true

func save_registry() -> bool:
	_ensure_directory()
	var file := FileAccess.open(WORLD_REGISTRY_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(build_snapshot(), "\t"))
	file.close()
	return true

func register_region_override(region: Vector2i, data: Dictionary) -> void:
	region_overrides[region_key(region)] = data.duplicate(true)
	region_loaded.emit(region.x, region.y, get_region_data(region))
	registry_changed.emit()

func clear_region_override(region: Vector2i) -> void:
	region_overrides.erase(region_key(region))
	registry_changed.emit()

func register_cell_override(chunk: Vector2i, data: Dictionary) -> void:
	cell_overrides[cell_key(chunk)] = data.duplicate(true)
	cell_changed.emit(chunk.x, chunk.y, get_cell_data(chunk))
	registry_changed.emit()

func clear_cell_override(chunk: Vector2i) -> void:
	cell_overrides.erase(cell_key(chunk))
	registry_changed.emit()

func get_region_data(region: Vector2i) -> Dictionary:
	var key := region_key(region)
	if region_overrides.has(key) and typeof(region_overrides[key]) == TYPE_DICTIONARY:
		var override_data: Dictionary = region_overrides[key]
		return _normalize_region_record(region, override_data.duplicate(true))

	var archetype := _type_for_region(region)
	var biome_mix := _biome_mix_for_type(archetype)
	var seed_offset := int((key + ":" + str(world_seed)).hash()) & 0x7fffffff
	var record := {
		"name": "Region %d,%d" % [region.x, region.y],
		"type": archetype,
		"coordinates": [region.x, region.y],
		"contains": _contains_for_type(archetype),
		"loaded": is_region_loaded(region),
		"seed": world_seed + seed_offset,
		"biome_mix": biome_mix,
		"road_density": _road_density_for_type(archetype),
		"traffic_density": _traffic_density_for_type(archetype),
		"vegetation_density": _vegetation_density_for_type(archetype),
		"landmark_strength": _landmark_strength_for_type(archetype),
		"spawn_profile": _spawn_profile_for_type(archetype),
		"flattening": _flattening_for_type(archetype),
		"theme": archetype
	}
	return record

func get_cell_data(chunk: Vector2i) -> Dictionary:
	var key := cell_key(chunk)
	if cell_overrides.has(key) and typeof(cell_overrides[key]) == TYPE_DICTIONARY:
		var override_data: Dictionary = cell_overrides[key]
		return _normalize_cell_record(chunk, override_data.duplicate(true))

	var region := region_from_chunk(chunk)
	var region_data := get_region_data(region)
	var archetype := str(region_data.get("type", "plain"))
	var local_noise := _cell_noise(chunk)

	var record := {
		"chunk": [chunk.x, chunk.y],
		"region": [region.x, region.y],
		"ground": {
			"height_bias": _height_bias_for_type(archetype),
			"flattening": float(region_data.get("flattening", 0.8)),
			"walkable": archetype != "mountain"
		},
		"static_elements": _static_elements_for_type(archetype),
		"savable_elements": [],
		"contains": region_data.get("contains", []),
		"loaded": is_chunk_loaded(chunk),
		"type": archetype,
		"theme": archetype,
		"biome_mix": region_data.get("biome_mix", {}),
		"road_density": float(region_data.get("road_density", 0.15)),
		"traffic_density": float(region_data.get("traffic_density", 0.10)),
		"vegetation_density": float(region_data.get("vegetation_density", 0.70)),
		"landmark_strength": float(region_data.get("landmark_strength", 0.25)),
		"spawn_profile": region_data.get("spawn_profile", "neutral"),
		"flattening": float(region_data.get("flattening", 0.8)),
		"noise": local_noise,
		"cell_size_meters": cell_size_meters
	}
	return record

func get_region_summary_for_chunk(chunk: Vector2i) -> Dictionary:
	var region := region_from_chunk(chunk)
	var region_data := get_region_data(region)
	return {
		"name": region_data.get("name", "Region"),
		"type": region_data.get("type", "plain"),
		"coordinates": region_data.get("coordinates", [region.x, region.y]),
		"contains": region_data.get("contains", []),
		"loaded": region_data.get("loaded", false)
	}

func get_region_record(region: Vector2i) -> Dictionary:
	return get_region_data(region)

func get_chunk_record(chunk: Vector2i) -> Dictionary:
	return get_cell_data(chunk)

func _ensure_directory() -> void:
	var directory := WORLD_REGISTRY_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)

func _type_for_region(region: Vector2i) -> String:
	var key := region_key(region)
	if region_overrides.has(key):
		var override_data: Variant = region_overrides[key]
		if typeof(override_data) == TYPE_DICTIONARY:
			var d: Dictionary = override_data
			if d.has("type"):
				return str(d["type"])
			if d.has("theme"):
				return str(d["theme"])

	var noise := _region_noise(key)
	var index := clampi(int(floor(noise * float(REGION_TYPES.size()))), 0, REGION_TYPES.size() - 1)
	return REGION_TYPES[index]

func _contains_for_type(kind: String) -> Array[String]:
	match kind:
		"forest":
			return ["trees", "brush", "wildlife"]
		"coastal":
			return ["sand", "shoreline", "water_edge"]
		"hills":
			return ["slopes", "paths", "rocks"]
		"mountain":
			return ["cliffs", "rock", "snow_caps"]
		"desert":
			return ["sand", "dunes", "dry_streams"]
		"wetlands":
			return ["water", "reeds", "mud_flats"]
		"rocky":
			return ["stone", "outcrops", "gravel"]
		_:
			return ["grass", "open_ground", "light_props"]

func _normalize_region_record(region: Vector2i, data: Dictionary) -> Dictionary:
	var normalized := data.duplicate(true)
	if not normalized.has("name"):
		normalized["name"] = "Region %d,%d" % [region.x, region.y]
	if not normalized.has("type"):
		normalized["type"] = str(normalized.get("theme", "plain"))
	if not normalized.has("coordinates"):
		normalized["coordinates"] = [region.x, region.y]
	if not normalized.has("contains"):
		normalized["contains"] = _contains_for_type(str(normalized.get("type", "plain")))
	if not normalized.has("loaded"):
		normalized["loaded"] = is_region_loaded(region)
	if not normalized.has("theme"):
		normalized["theme"] = normalized.get("type", "plain")
	return normalized

func _normalize_cell_record(chunk: Vector2i, data: Dictionary) -> Dictionary:
	var normalized := data.duplicate(true)
	if not normalized.has("chunk"):
		normalized["chunk"] = [chunk.x, chunk.y]
	if not normalized.has("region"):
		var r := region_from_chunk(chunk)
		normalized["region"] = [r.x, r.y]
	if not normalized.has("ground"):
		normalized["ground"] = {
			"height_bias": 0.0,
			"flattening": 0.8,
			"walkable": true
		}
	if not normalized.has("static_elements"):
		normalized["static_elements"] = []
	if not normalized.has("savable_elements"):
		normalized["savable_elements"] = []
	if not normalized.has("contains"):
		normalized["contains"] = []
	if not normalized.has("loaded"):
		normalized["loaded"] = is_chunk_loaded(chunk)
	if not normalized.has("type"):
		normalized["type"] = "plain"
	if not normalized.has("theme"):
		normalized["theme"] = normalized.get("type", "plain")
	if not normalized.has("biome_mix"):
		normalized["biome_mix"] = {}
	if not normalized.has("road_density"):
		normalized["road_density"] = 0.15
	if not normalized.has("traffic_density"):
		normalized["traffic_density"] = 0.10
	if not normalized.has("vegetation_density"):
		normalized["vegetation_density"] = 0.70
	if not normalized.has("landmark_strength"):
		normalized["landmark_strength"] = 0.25
	if not normalized.has("spawn_profile"):
		normalized["spawn_profile"] = "neutral"
	if not normalized.has("flattening"):
		normalized["flattening"] = 0.8
	if not normalized.has("noise"):
		normalized["noise"] = _cell_noise(chunk)
	if not normalized.has("cell_size_meters"):
		normalized["cell_size_meters"] = cell_size_meters
	return normalized

func _region_noise(key: String) -> float:
	var hash_value := int(("%s:%d" % [key, world_seed]).hash()) & 0x7fffffff
	return float(hash_value % 1000000) / 1000000.0

func _cell_noise(chunk: Vector2i) -> float:
	var hash_value := int(("%d:%d:%d" % [chunk.x, chunk.y, world_seed]).hash()) & 0x7fffffff
	return float(hash_value % 1000000) / 1000000.0

func _biome_mix_for_type(kind: String) -> Dictionary:
	match kind:
		"forest":
			return {"grass": 0.35, "trees": 0.95, "rocks": 0.10}
		"coastal":
			return {"sand": 0.70, "water": 0.55, "grass": 0.15}
		"hills":
			return {"grass": 0.55, "rocks": 0.45, "trees": 0.30}
		"mountain":
			return {"rock": 0.90, "snow": 0.35, "grass": 0.05}
		"desert":
			return {"sand": 0.95, "rock": 0.30, "water": 0.05}
		"wetlands":
			return {"water": 0.75, "grass": 0.35, "mud": 0.60}
		"rocky":
			return {"rock": 0.95, "dust": 0.35, "grass": 0.08}
		_:
			return {"grass": 0.80, "trees": 0.30, "rocks": 0.15}

func _road_density_for_type(kind: String) -> float:
	match kind:
		"coastal": return 0.18
		"hills": return 0.12
		"mountain": return 0.08
		"desert": return 0.10
		"wetlands": return 0.05
		"rocky": return 0.06
		"forest": return 0.10
		_: return 0.08

func _traffic_density_for_type(kind: String) -> float:
	match kind:
		"coastal": return 0.06
		"hills": return 0.04
		"mountain": return 0.02
		"desert": return 0.03
		"wetlands": return 0.01
		"rocky": return 0.02
		"forest": return 0.03
		_: return 0.02

func _vegetation_density_for_type(kind: String) -> float:
	match kind:
		"forest": return 0.95
		"coastal": return 0.52
		"hills": return 0.65
		"mountain": return 0.28
		"desert": return 0.10
		"wetlands": return 0.78
		"rocky": return 0.14
		_: return 0.70

func _landmark_strength_for_type(kind: String) -> float:
	match kind:
		"forest": return 0.28
		"coastal": return 0.44
		"hills": return 0.38
		"mountain": return 0.58
		"desert": return 0.22
		"wetlands": return 0.35
		"rocky": return 0.30
		_: return 0.20

func _spawn_profile_for_type(kind: String) -> String:
	match kind:
		"forest": return "wild"
		"coastal": return "shore"
		"hills": return "upland"
		"mountain": return "alpine"
		"desert": return "arid"
		"wetlands": return "marsh"
		"rocky": return "stony"
		_: return "neutral"

func _flattening_for_type(kind: String) -> float:
	match kind:
		"forest": return 0.85
		"coastal": return 0.50
		"hills": return 0.70
		"mountain": return 1.25
		"desert": return 0.60
		"wetlands": return 0.45
		"rocky": return 0.95
		_: return 0.80

func _height_bias_for_type(kind: String) -> float:
	match kind:
		"forest": return 0.15
		"coastal": return -1.10
		"hills": return 2.50
		"mountain": return 8.00
		"desert": return -0.35
		"wetlands": return -1.80
		"rocky": return 3.50
		_: return 0.0

func _static_elements_for_type(kind: String) -> Array[Dictionary]:
	match kind:
		"forest":
			return [
				{"id": "tree_cluster", "count_hint": 6},
				{"id": "brush_patch", "count_hint": 4}
			]
		"coastal":
			return [
				{"id": "shore_rock", "count_hint": 3},
				{"id": "driftwood", "count_hint": 2}
			]
		"hills":
			return [
				{"id": "rock_outcrop", "count_hint": 4},
				{"id": "slope_path", "count_hint": 2}
			]
		"mountain":
			return [
				{"id": "cliff_segment", "count_hint": 2},
				{"id": "boulder_field", "count_hint": 5}
			]
		"desert":
			return [
				{"id": "dune_ripple", "count_hint": 4},
				{"id": "dry_shrub", "count_hint": 3}
			]
		"wetlands":
			return [
				{"id": "reed_bed", "count_hint": 5},
				{"id": "mud_bank", "count_hint": 2}
			]
		"rocky":
			return [
				{"id": "stone_field", "count_hint": 6},
				{"id": "gravel_patch", "count_hint": 4}
			]
		_:
			return [
				{"id": "grass_patch", "count_hint": 6},
				{"id": "stone", "count_hint": 2}
			]
