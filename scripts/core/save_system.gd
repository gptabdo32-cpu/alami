extends Node

const SAVE_DIR: String = "user://saves"
const SAVE_PREFIX: String = "slot_"
const SAVE_SUFFIX: String = ".json"
const SAVE_TMP_SUFFIX: String = ".tmp"

func _ready() -> void:
    _ensure_directory()

func _ensure_directory() -> void:
    if not DirAccess.dir_exists_absolute(SAVE_DIR):
        DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func get_save_path(slot: String) -> String:
    var safe_slot := slot.strip_edges()
    if safe_slot.is_empty():
        safe_slot = "01"
    return "%s/%s%s%s" % [SAVE_DIR, SAVE_PREFIX, safe_slot, SAVE_SUFFIX]

func get_temp_save_path(slot: String) -> String:
    return "%s/%s%s%s" % [SAVE_DIR, SAVE_PREFIX, slot.strip_edges(), SAVE_TMP_SUFFIX]

func has_save(slot: String = "01") -> bool:
    return FileAccess.file_exists(get_save_path(slot))

func build_save_data() -> Dictionary:
    return {
        "schema_version": GameState.SAVE_SCHEMA_VERSION,
        "app_version": GameState.version,
        "build_label": GameState.BUILD_LABEL,
        "save_format": "json",
        "saved_at_unix": Time.get_unix_time_from_system(),
        "save_slot": GameState.save_slot,
        "debug_enabled": GameState.debug_enabled,
        "player": {
            "position": [
                GameState.player_position.x,
                GameState.player_position.y,
                GameState.player_position.z
            ],
            "rotation_y": GameState.player_rotation_y,
            "camera_pitch": GameState.camera_pitch,
            "is_crouched": GameState.player_is_crouched
        },
        "world": {
            "seed": GameState.world_seed,
            "chunk_x": GameState.current_chunk_x,
            "chunk_z": GameState.current_chunk_z
        },
        "world_data": WorldDataSystem.build_snapshot(),
        "time": {
            "minutes": GameState.time_of_day_minutes,
            "day_index": GameState.day_index
        },
        "settings": SettingsSystem.build_snapshot()
    }

func migrate_save(data: Dictionary) -> Dictionary:
    var migrated := data.duplicate(true)
    var schema := int(migrated.get("schema_version", 1))
    if schema < 3:
        migrated["schema_version"] = 3
    if schema < 4:
        migrated["schema_version"] = 4
    if schema < 5:
        migrated["schema_version"] = 5
    if not migrated.has("world_data"):
        migrated["world_data"] = WorldDataSystem.build_snapshot()
    if not migrated.has("save_format"):
        migrated["save_format"] = "json"
    if not migrated.has("build_label"):
        migrated["build_label"] = GameState.BUILD_LABEL
    return migrated

func apply_save_data(data: Dictionary) -> void:
    var migrated := migrate_save(data)

    var world_data: Variant = migrated.get("world_data", {})
    if typeof(world_data) == TYPE_DICTIONARY:
        WorldDataSystem.apply_snapshot(world_data)

    GameState.apply_snapshot(migrated)

    var settings_data: Variant = migrated.get("settings", {})
    if typeof(settings_data) == TYPE_DICTIONARY:
        SettingsSystem.apply_snapshot(settings_data)

func _write_text_atomic(path: String, text: String) -> bool:
    var temp_path := path + SAVE_TMP_SUFFIX
    var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
    if temp_file == null:
        return false
    temp_file.store_string(text)
    temp_file.close()

    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)
    var rename_result := DirAccess.rename_absolute(temp_path, path)
    return rename_result == OK

func save_game(slot: String = "01") -> bool:
    _ensure_directory()
    GameState.save_slot = slot

    var payload := JSON.stringify(build_save_data(), "	")
    var path := get_save_path(slot)
    if not _write_text_atomic(path, payload):
        EventBus.emit_debug("Save failed: atomic write error.")
        return false

    EventBus.game_saved.emit(slot)
    EventBus.emit_debug("Saved game slot: %s" % slot)
    return true

func load_game(slot: String = "01") -> bool:
    var path := get_save_path(slot)
    if not FileAccess.file_exists(path):
        EventBus.emit_debug("Load skipped: no save file found.")
        return false

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        EventBus.emit_debug("Load failed: file open error.")
        return false

    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        EventBus.emit_debug("Load failed: invalid save format.")
        return false

    apply_save_data(parsed)
    GameState.save_slot = slot

    EventBus.game_loaded.emit(slot)
    EventBus.emit_debug("Loaded game slot: %s" % slot)
    return true
