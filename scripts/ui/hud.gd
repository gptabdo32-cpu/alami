extends CanvasLayer

@onready var label: Label = $MarginContainer/VBoxContainer/InfoLabel
var streamer: WorldStreamer
var stats: Dictionary = {}

func _ready() -> void:
    call_deferred("_bind_streamer")

func _bind_streamer() -> void:
    streamer = get_tree().get_first_node_in_group("world_manager") as WorldStreamer
    if streamer == null:
        streamer = get_tree().get_first_node_in_group("world_streamer") as WorldStreamer
    if streamer != null and not streamer.statistics_changed.is_connected(_on_stats):
        streamer.statistics_changed.connect(_on_stats)

func _on_stats(value: Dictionary) -> void:
    stats = value

func _process(_delta: float) -> void:
    if label == null:
        return
    if streamer == null:
        _bind_streamer()
    var fps_text := ""
    if SettingsSystem.show_fps:
        fps_text = "\nFPS: %d | Frame: %.2f ms" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]
    var stream_text := "\nStreaming: A%d Q%d C%d | View %d | Phys %d | Unload %d | Build %.2f ms" % [
        int(stats.get("active", 0)),
        int(stats.get("queued", 0)),
        int(stats.get("cached", 0)),
        int(stats.get("view_radius", 0)),
        int(stats.get("physics_radius", 0)),
        int(stats.get("unload_radius", 0)),
        float(stats.get("last_build_ms", 0.0))
    ]
    label.text = "OPEN WORLD FOUNDATION PRO %s\nTime: %s  Day: %d\nChunk: %d, %d\nPos: %.1f, %.1f, %.1f%s%s" % [
        GameState.BUILD_LABEL,
        TimeSystem.get_time_string(),
        GameState.day_index,
        GameState.current_chunk_x,
        GameState.current_chunk_z,
        GameState.player_position.x,
        GameState.player_position.y,
        GameState.player_position.z,
        fps_text,
        stream_text
    ]
