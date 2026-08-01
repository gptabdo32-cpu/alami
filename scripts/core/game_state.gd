extends Node

signal state_changed
signal save_requested
signal load_requested

const APP_VERSION: String = "1.0.0"
const BUILD_LABEL: String = "Stage 1 Foundation"
const SAVE_SCHEMA_VERSION: int = 5

var version: String = APP_VERSION
var save_slot: String = "01"

var player_position: Vector3 = Vector3.ZERO
var player_rotation_y: float = 0.0
var camera_pitch: float = 0.0
var player_is_crouched: bool = false

var current_chunk_x: int = 0
var current_chunk_z: int = 0

var time_of_day_minutes: float = 8.0 * 60.0
var day_index: int = 1

var world_seed: int = 424242
var debug_enabled: bool = true

func reset_defaults(p_seed: int = 424242) -> void:
    version = APP_VERSION
    save_slot = "01"
    player_position = Vector3(0.0, 12.0, 0.0)
    player_rotation_y = 0.0
    camera_pitch = 0.0
    player_is_crouched = false
    current_chunk_x = 0
    current_chunk_z = 0
    time_of_day_minutes = 8.0 * 60.0
    day_index = 1
    world_seed = p_seed
    debug_enabled = true
    _emit_state_changed()

func set_player_state(p_position: Vector3, rotation_y: float, pitch: float) -> void:
    set_player_state_silent(p_position, rotation_y, pitch)
    _emit_state_changed()

func set_player_state_silent(p_position: Vector3, rotation_y: float, pitch: float) -> void:
    player_position = p_position
    player_rotation_y = rotation_y
    camera_pitch = pitch

func set_chunk(chunk_x: int, chunk_z: int) -> void:
    current_chunk_x = chunk_x
    current_chunk_z = chunk_z
    _emit_state_changed()

func set_time_minutes(minutes: float, day: int, notify: bool = false) -> void:
    time_of_day_minutes = clampf(minutes, 0.0, 1439.999)
    day_index = maxi(day, 1)
    if notify:
        _emit_state_changed()

func set_time_hours(hours: float, day: int) -> void:
    set_time_minutes(hours * 60.0, day)

func set_world_seed(p_seed: int) -> void:
    world_seed = p_seed
    _emit_state_changed()

func set_debug_enabled(enabled: bool) -> void:
    debug_enabled = enabled
    _emit_state_changed()

func request_save() -> void:
    emit_signal("save_requested")

func request_load() -> void:
    emit_signal("load_requested")

func build_snapshot() -> Dictionary:
    return {
        "schema_version": SAVE_SCHEMA_VERSION,
        "app_version": version,
        "build_label": BUILD_LABEL,
        "save_slot": save_slot,
        "debug_enabled": debug_enabled,
        "player": {
            "position": [player_position.x, player_position.y, player_position.z],
            "rotation_y": player_rotation_y,
            "camera_pitch": camera_pitch,
            "is_crouched": player_is_crouched
        },
        "world": {
            "seed": world_seed,
            "chunk_x": current_chunk_x,
            "chunk_z": current_chunk_z
        },
        "time": {
            "minutes": time_of_day_minutes,
            "day_index": day_index
        }
    }

func apply_snapshot(data: Dictionary) -> void:
    version = str(data.get("app_version", version))
    save_slot = str(data.get("save_slot", save_slot))
    debug_enabled = bool(data.get("debug_enabled", debug_enabled))

    var player_data: Variant = data.get("player", {})
    if typeof(player_data) == TYPE_DICTIONARY:
        var p: Dictionary = player_data
        if p.has("position") and typeof(p["position"]) == TYPE_ARRAY:
            var pos: Array = p["position"]
            if pos.size() >= 3:
                player_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
        elif data.has("player_position") and typeof(data["player_position"]) == TYPE_ARRAY:
            var legacy_pos: Array = data["player_position"]
            if legacy_pos.size() >= 3:
                player_position = Vector3(float(legacy_pos[0]), float(legacy_pos[1]), float(legacy_pos[2]))

        player_rotation_y = float(p.get("rotation_y", data.get("player_rotation_y", player_rotation_y)))
        camera_pitch = float(p.get("camera_pitch", data.get("camera_pitch", camera_pitch)))
        player_is_crouched = bool(p.get("is_crouched", data.get("player_is_crouched", player_is_crouched)))
    else:
        if data.has("player_position") and typeof(data["player_position"]) == TYPE_ARRAY:
            var legacy_position: Array = data["player_position"]
            if legacy_position.size() >= 3:
                player_position = Vector3(float(legacy_position[0]), float(legacy_position[1]), float(legacy_position[2]))
        player_rotation_y = float(data.get("player_rotation_y", player_rotation_y))
        camera_pitch = float(data.get("camera_pitch", camera_pitch))
        player_is_crouched = bool(data.get("player_is_crouched", player_is_crouched))

    var world_data: Variant = data.get("world", {})
    if typeof(world_data) == TYPE_DICTIONARY:
        var w: Dictionary = world_data
        world_seed = int(w.get("seed", data.get("world_seed", world_seed)))
        current_chunk_x = int(w.get("chunk_x", data.get("current_chunk_x", current_chunk_x)))
        current_chunk_z = int(w.get("chunk_z", data.get("current_chunk_z", current_chunk_z)))
    else:
        world_seed = int(data.get("world_seed", world_seed))
        current_chunk_x = int(data.get("current_chunk_x", current_chunk_x))
        current_chunk_z = int(data.get("current_chunk_z", current_chunk_z))

    var time_data: Variant = data.get("time", {})
    if typeof(time_data) == TYPE_DICTIONARY:
        var t: Dictionary = time_data
        if t.has("minutes"):
            time_of_day_minutes = float(t["minutes"])
        elif t.has("hours"):
            time_of_day_minutes = float(t["hours"]) * 60.0
        day_index = int(t.get("day_index", day_index))
    else:
        if data.has("time_of_day_minutes"):
            time_of_day_minutes = float(data["time_of_day_minutes"])
        elif data.has("time_of_day_hours"):
            time_of_day_minutes = float(data["time_of_day_hours"]) * 60.0
        day_index = int(data.get("day_index", day_index))

    time_of_day_minutes = clampf(time_of_day_minutes, 0.0, 1439.999)
    day_index = maxi(day_index, 1)
    _emit_state_changed()

func _emit_state_changed() -> void:
    emit_signal("state_changed")
