extends Node

var day_length_seconds: float = 900.0
var start_hour: float = 8.0
var time_minutes: float = 8.0 * 60.0
var day_index: int = 1
var running: bool = true
var state_sync_accumulator: float = 0.0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    if day_length_seconds <= 0.0:
        day_length_seconds = 900.0
    call_deferred("sync_from_state")

func _process(delta: float) -> void:
    if not running:
        return

    time_minutes += delta * (1440.0 / day_length_seconds)
    while time_minutes >= 1440.0:
        time_minutes -= 1440.0
        day_index += 1

    state_sync_accumulator += delta
    if state_sync_accumulator >= 0.25:
        state_sync_accumulator = 0.0
        _apply_to_state()

func sync_from_state() -> void:
    time_minutes = clampf(GameState.time_of_day_minutes, 0.0, 1439.999)
    day_index = maxi(GameState.day_index, 1)

func set_time(minutes: float, day: int) -> void:
    time_minutes = clampf(minutes, 0.0, 1439.999)
    day_index = maxi(day, 1)
    _apply_to_state()

func pause_time(paused: bool) -> void:
    running = not paused

func get_time_string() -> String:
    var total_minutes := int(floor(time_minutes))
    var hours := int(total_minutes / 60) % 24
    var minutes := total_minutes % 60
    return "%02d:%02d" % [hours, minutes]

func get_time_normalized() -> float:
    return clampf(time_minutes / 1440.0, 0.0, 1.0)

func _apply_to_state() -> void:
    GameState.set_time_minutes(time_minutes, day_index, false)
    EventBus.emit_signal("time_changed", time_minutes / 60.0, day_index)