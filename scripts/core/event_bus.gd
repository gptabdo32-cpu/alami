extends Node

signal game_saved(slot: String)
signal game_loaded(slot: String)
signal player_entered_chunk(chunk_x: int, chunk_z: int)
signal player_position_changed(position: Vector3)
signal time_changed(hours: float, day_index: int)
signal settings_changed
signal debug_message(message: String)

func emit_debug(message: String) -> void:
    emit_signal("debug_message", message)