class_name WorldStreamer
extends Node3D

signal initial_chunk_ready
signal statistics_changed(stats: Dictionary)

@export var chunk_scene: PackedScene
@export var chunk_size := 256.0
@export var world_seed := 424242
@export var predictive_seconds := 1.8
@export var physics_radius := 1
@export var max_cached_chunks := 8

enum ChunkState { QUEUED, GENERATING, DATA_READY, BUILDING, ACTIVE, SLEEPING, UNLOADING }

var player_node: CharacterBody3D
var target_chunk := Vector2i(999999, 999999)
var predictive_chunk := Vector2i.ZERO
var last_stream_center := Vector2i(999999, 999999)
var view_radius := 2
var unload_radius := 3
var lod_resolutions := [48, 24, 12]
var jobs: Dictionary = {}
var active_chunks: Dictionary = {}
var generation_queue: Array[Vector2i] = []
var generation_thread := Thread.new()
var data_generator := ChunkDataGenerator.new()
var running_job_key := ""
var running_job_config: Dictionary = {}
var running_job_result: Dictionary = {}
var initial_emitted := false
var last_build_ms := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if chunk_scene == null:
		chunk_scene = AssetManager.get_scene(&"world_chunk")
	if chunk_scene != null:
		ObjectPool.register_scene_pool(&"world_chunk", chunk_scene, maxi(2, int(max_cached_chunks / 2.0)), max_cached_chunks, self)
	if not EventBus.settings_changed.is_connected(_on_settings_changed):
		EventBus.settings_changed.connect(_on_settings_changed)
	if not WorldDataSystem.registry_changed.is_connected(_on_world_registry_changed):
		WorldDataSystem.registry_changed.connect(_on_world_registry_changed)
	_apply_quality()

func _exit_tree() -> void:
	if generation_thread.is_started():
		generation_thread.wait_to_finish()

func _process(_delta: float) -> void:
	_refresh_player()
	if player_node == null:
		return

	var predicted_position := player_node.global_position + player_node.velocity * predictive_seconds
	var current := world_to_chunk(player_node.global_position)
	predictive_chunk = world_to_chunk(predicted_position)
	var stream_center_changed := predictive_chunk != last_stream_center
	if stream_center_changed:
		last_stream_center = predictive_chunk

	if current != target_chunk:
		target_chunk = current
		GameState.set_chunk(current.x, current.y)
		EventBus.player_entered_chunk.emit(current.x, current.y)
		_rebuild_wanted_set()
	elif stream_center_changed:
		_rebuild_wanted_set()
	elif generation_queue.is_empty() and jobs.is_empty():
		_rebuild_wanted_set()

	_poll_generation()
	_update_collision_bands()
	_emit_statistics()

func sync_from_state() -> void:
	world_seed = GameState.world_seed
	WorldDataSystem.set_world_seed(world_seed)
	_refresh_player()
	target_chunk = world_to_chunk(player_node.global_position) if player_node != null else Vector2i(GameState.current_chunk_x, GameState.current_chunk_z)
	predictive_chunk = target_chunk
	last_stream_center = predictive_chunk
	initial_emitted = false
	clear_chunks()
	_rebuild_wanted_set()

func world_to_chunk(p_position: Vector3) -> Vector2i:
	return Vector2i(floori((p_position.x + chunk_size * 0.5) / chunk_size), floori((p_position.z + chunk_size * 0.5) / chunk_size))

func get_height_at(world_position: Vector3) -> float:
	return ChunkDataGenerator.sample_world_height(world_position.x, world_position.z, world_seed)

func is_initial_area_ready() -> bool:
	return active_chunks.has(_key(target_chunk))

func clear_chunks() -> void:
	generation_queue.clear()
	jobs.clear()
	running_job_key = ""
	running_job_result.clear()
	if generation_thread.is_started():
		generation_thread.wait_to_finish()

	var regions_to_clear: Dictionary = {}
	for chunk in active_chunks.values():
		if is_instance_valid(chunk):
			WorldDataSystem.set_chunk_loaded(chunk.coordinates, false)
			regions_to_clear[WorldDataSystem.region_key(WorldDataSystem.region_from_chunk(chunk.coordinates))] = WorldDataSystem.region_from_chunk(chunk.coordinates)
			ObjectPool.release(chunk, &"world_chunk")
	active_chunks.clear()

	for region in regions_to_clear.values():
		WorldDataSystem.set_region_loaded(region, false)

func _refresh_player() -> void:
	if player_node == null or not is_instance_valid(player_node):
		player_node = get_tree().get_first_node_in_group("player") as CharacterBody3D

func _apply_quality() -> void:
	match SettingsSystem.quality_preset:
		"performance":
			view_radius = 1
			unload_radius = 2
			lod_resolutions = [32, 16, 8]
		"quality":
			view_radius = 3
			unload_radius = 4
			lod_resolutions = [64, 32, 16]
		_:
			view_radius = 2
			unload_radius = 3
			lod_resolutions = [48, 24, 12]

func _on_settings_changed() -> void:
	_apply_quality()
	_rebuild_wanted_set()

func _on_world_registry_changed() -> void:
	_rebuild_wanted_set()

func _rebuild_wanted_set() -> void:
	var wanted: Array[Vector2i] = []
	for x in range(predictive_chunk.x - view_radius, predictive_chunk.x + view_radius + 1):
		for z in range(predictive_chunk.y - view_radius, predictive_chunk.y + view_radius + 1):
			wanted.append(Vector2i(x, z))
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(predictive_chunk) < b.distance_squared_to(predictive_chunk)
	)

	for c in wanted:
		var key := _key(c)
		if active_chunks.has(key) or jobs.has(key) or key == running_job_key:
			continue
		jobs[key] = {"state": ChunkState.QUEUED, "coords": c}
		generation_queue.append(c)

	_unload_far_chunks()
	_start_next_generation()

func _start_next_generation() -> void:
	if generation_thread.is_started() or generation_queue.is_empty():
		return

	var c: Vector2i = generation_queue.pop_front()
	var key := _key(c)
	if not jobs.has(key):
		_start_next_generation()
		return

	var lod := _lod_for(c)
	var cell_data: Dictionary = WorldDataSystem.get_cell_data(c)
	running_job_key = key
	running_job_config = {
		"chunk_x": c.x,
		"chunk_z": c.y,
		"chunk_size": chunk_size,
		"resolution": lod_resolutions[lod],
		"seed": world_seed,
		"vegetation_density": SettingsSystem.vegetation_density * float(cell_data.get("vegetation_density", 1.0)),
		"include_props": lod < 2,
		"cell_data": cell_data,
		"theme": str(cell_data.get("theme", "rural")),
		"flattening": float(cell_data.get("flattening", 0.8)),
		"road_density": float(cell_data.get("road_density", 0.18))
	}
	jobs[key]["state"] = ChunkState.GENERATING
	generation_thread.start(data_generator.generate.bind(running_job_config))

func _poll_generation() -> void:
	if not generation_thread.is_started():
		_start_next_generation()
		return
	if generation_thread.is_alive():
		return

	var started := Time.get_ticks_usec()
	running_job_result = generation_thread.wait_to_finish()
	var key := running_job_key
	running_job_key = ""

	if jobs.has(key) and not running_job_result.is_empty():
		jobs[key]["state"] = ChunkState.DATA_READY
		_build_chunk(key, running_job_config, running_job_result)

	last_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	running_job_result = {}
	_start_next_generation()

func _build_chunk(key: String, config: Dictionary, data: Dictionary) -> void:
	if not jobs.has(key):
		return

	var c: Vector2i = jobs[key]["coords"]
	var chunk: WorldChunk = ObjectPool.acquire(&"world_chunk", self) as WorldChunk
	if chunk == null:
		if chunk_scene == null:
			return
		chunk = chunk_scene.instantiate() as WorldChunk
		add_child(chunk)

	var lod := _lod_for(c)
	chunk.configure(c, chunk_size, lod)
	chunk.position = Vector3(c.x * chunk_size, 0.0, c.y * chunk_size)
	chunk.build_from_data(data, _within_physics_radius(c))
	chunk.set_meta("source_data", data)
	chunk.set_meta("cell_data", config.get("cell_data", {}))
	active_chunks[key] = chunk
	WorldDataSystem.set_chunk_loaded(c, true)
	WorldDataSystem.set_region_loaded(WorldDataSystem.region_from_chunk(c), true)
	jobs.erase(key)

	if c == target_chunk and not initial_emitted:
		initial_emitted = true
		initial_chunk_ready.emit()

func _update_collision_bands() -> void:
	for key in active_chunks.keys():
		var chunk: WorldChunk = active_chunks[key]
		var should_enable := _within_physics_radius(chunk.coordinates)
		if should_enable != chunk.collision_enabled:
			chunk.set_collision_enabled(should_enable, chunk.get_meta("source_data", {}))

func _unload_far_chunks() -> void:
	var remove: Array[String] = []
	for key in active_chunks.keys():
		var chunk: WorldChunk = active_chunks[key]
		if absi(chunk.coordinates.x - predictive_chunk.x) > unload_radius or absi(chunk.coordinates.y - predictive_chunk.y) > unload_radius:
			remove.append(key)

	for key in remove:
		var chunk: WorldChunk = active_chunks[key]
		active_chunks.erase(key)
		chunk.set_collision_enabled(false)
		WorldDataSystem.set_chunk_loaded(chunk.coordinates, false)
		var region: Vector2i = WorldDataSystem.region_from_chunk(chunk.coordinates)
		ObjectPool.release(chunk, &"world_chunk")
		if not _region_has_active_chunks(region):
			WorldDataSystem.set_region_loaded(region, false)

	var cancel: Array[String] = []
	for key in jobs.keys():
		var c: Vector2i = jobs[key]["coords"]
		if absi(c.x - predictive_chunk.x) > unload_radius or absi(c.y - predictive_chunk.y) > unload_radius:
			cancel.append(key)

	for key in cancel:
		jobs.erase(key)
	generation_queue = generation_queue.filter(func(c: Vector2i) -> bool:
		return jobs.has(_key(c))
	)

func _lod_for(c: Vector2i) -> int:
	var ring := maxi(absi(c.x - predictive_chunk.x), absi(c.y - predictive_chunk.y))
	if ring <= 1:
		return 0
	if ring <= 2:
		return 1
	return 2

func _within_physics_radius(c: Vector2i) -> bool:
	return maxi(absi(c.x - target_chunk.x), absi(c.y - target_chunk.y)) <= physics_radius

func _key(c: Vector2i) -> String:
	return "%d:%d" % [c.x, c.y]

func _region_has_active_chunks(region: Vector2i) -> bool:
	for chunk in active_chunks.values():
		if is_instance_valid(chunk) and WorldDataSystem.region_from_chunk(chunk.coordinates) == region:
			return true
	return false

func _emit_statistics() -> void:
	statistics_changed.emit({
		"active": active_chunks.size(),
		"queued": generation_queue.size(),
		"jobs": jobs.size(),
		"cached": ObjectPool.get_available_count(&"world_chunk"),
		"last_build_ms": last_build_ms,
		"generating": 1 if generation_thread.is_started() else 0,
		"view_radius": view_radius,
		"unload_radius": unload_radius,
		"physics_radius": physics_radius,
		"chunk_size": chunk_size,
		"seed": world_seed,
		"target_x": target_chunk.x,
		"target_y": target_chunk.y,
		"predictive_x": predictive_chunk.x,
		"predictive_y": predictive_chunk.y,
		"region": WorldDataSystem.region_key(WorldDataSystem.region_from_chunk(target_chunk)),
		"theme": WorldDataSystem.get_region_data(WorldDataSystem.region_from_chunk(target_chunk)).get("theme", "rural")
	})
