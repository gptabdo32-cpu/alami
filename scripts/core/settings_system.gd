extends Node

signal settings_changed

const SETTINGS_PATH: String = "user://settings.json"

var quality_preset: String = "balanced"
var max_fps: int = 60
var show_fps: bool = true
var touch_sensitivity: float = 0.95
var joystick_scale: float = 1.08
var joystick_deadzone: float = 0.15
var joystick_curve: float = 1.25
var button_opacity: float = 0.90
var button_scale: float = 1.00
var mouse_sensitivity: float = 0.0025
var camera_smoothing: float = 14.0
var master_volume_db: float = 0.0
var music_volume_db: float = -3.0
var sfx_volume_db: float = 0.0
var vsync_enabled: bool = true
var render_scale: float = 0.90
var vegetation_density: float = 0.70

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func is_mobile_runtime() -> bool:
    return OS.has_feature("mobile") or OS.has_feature("handheld")

func reset_defaults() -> void:
    _apply_runtime_defaults()
    _apply_settings()

func _apply_runtime_defaults() -> void:
    if is_mobile_runtime():
        quality_preset = "balanced"
        max_fps = 60
        show_fps = true
        touch_sensitivity = 1.05
        joystick_scale = 1.12
        joystick_deadzone = 0.16
        joystick_curve = 1.28
        button_opacity = 0.92
        button_scale = 1.00
        mouse_sensitivity = 0.0025
        camera_smoothing = 15.0
        master_volume_db = 0.0
        music_volume_db = -3.0
        sfx_volume_db = 0.0
        vsync_enabled = true
        render_scale = 0.90
        vegetation_density = 0.70
    else:
        quality_preset = "balanced"
        max_fps = 60
        show_fps = true
        touch_sensitivity = 0.70
        joystick_scale = 1.0
        joystick_deadzone = 0.14
        joystick_curve = 1.20
        button_opacity = 0.90
        button_scale = 1.00
        mouse_sensitivity = 0.0025
        camera_smoothing = 14.0
        master_volume_db = 0.0
        music_volume_db = -3.0
        sfx_volume_db = 0.0
        vsync_enabled = true
        render_scale = 0.85
        vegetation_density = 0.70

func build_snapshot() -> Dictionary:
    return {
        "quality_preset": quality_preset,
        "max_fps": max_fps,
        "show_fps": show_fps,
        "touch_sensitivity": touch_sensitivity,
        "joystick_scale": joystick_scale,
        "joystick_deadzone": joystick_deadzone,
        "joystick_curve": joystick_curve,
        "button_opacity": button_opacity,
        "button_scale": button_scale,
        "mouse_sensitivity": mouse_sensitivity,
        "camera_smoothing": camera_smoothing,
        "master_volume_db": master_volume_db,
        "music_volume_db": music_volume_db,
        "sfx_volume_db": sfx_volume_db,
        "vsync_enabled": vsync_enabled,
        "render_scale": render_scale,
        "vegetation_density": vegetation_density
    }

func apply_snapshot(data: Dictionary) -> void:
    quality_preset = str(data.get("quality_preset", quality_preset))
    max_fps = int(data.get("max_fps", max_fps))
    show_fps = bool(data.get("show_fps", show_fps))
    touch_sensitivity = clampf(float(data.get("touch_sensitivity", touch_sensitivity)), 0.15, 3.00)
    joystick_scale = clampf(float(data.get("joystick_scale", joystick_scale)), 0.75, 1.50)
    joystick_deadzone = clampf(float(data.get("joystick_deadzone", joystick_deadzone)), 0.05, 0.30)
    joystick_curve = clampf(float(data.get("joystick_curve", joystick_curve)), 0.80, 2.00)
    button_opacity = clampf(float(data.get("button_opacity", button_opacity)), 0.35, 1.0)
    button_scale = clampf(float(data.get("button_scale", button_scale)), 0.75, 1.35)
    mouse_sensitivity = clampf(float(data.get("mouse_sensitivity", mouse_sensitivity)), 0.0005, 0.02)
    camera_smoothing = clampf(float(data.get("camera_smoothing", camera_smoothing)), 4.0, 30.0)
    master_volume_db = clampf(float(data.get("master_volume_db", master_volume_db)), -80.0, 12.0)
    music_volume_db = clampf(float(data.get("music_volume_db", music_volume_db)), -80.0, 12.0)
    sfx_volume_db = clampf(float(data.get("sfx_volume_db", sfx_volume_db)), -80.0, 12.0)
    vsync_enabled = bool(data.get("vsync_enabled", vsync_enabled))
    render_scale = clampf(float(data.get("render_scale", render_scale)), 0.5, 1.0)
    vegetation_density = clampf(float(data.get("vegetation_density", vegetation_density)), 0.2, 1.0)
    _sanitize_quality()
    _apply_settings()

func load_settings() -> bool:
    if not FileAccess.file_exists(SETTINGS_PATH):
        reset_defaults()
        return false

    var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
    if file == null:
        reset_defaults()
        return false

    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        reset_defaults()
        return false

    apply_snapshot(parsed)
    return true

func save_settings() -> bool:
    var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(build_snapshot(), "\t"))
    file.close()
    emit_signal("settings_changed")
    return true

func set_quality_preset(preset: String) -> void:
    quality_preset = preset
    _sanitize_quality()
    _apply_settings()

func set_touch_sensitivity(value: float) -> void:
    touch_sensitivity = clampf(value, 0.15, 3.00)
    _apply_settings()

func set_joystick_scale(value: float) -> void:
    joystick_scale = clampf(value, 0.75, 1.50)
    _apply_settings()

func set_joystick_deadzone(value: float) -> void:
    joystick_deadzone = clampf(value, 0.05, 0.30)
    _apply_settings()

func set_joystick_curve(value: float) -> void:
    joystick_curve = clampf(value, 0.80, 2.00)
    _apply_settings()

func set_button_opacity(value: float) -> void:
    button_opacity = clampf(value, 0.35, 1.0)
    _apply_settings()

func set_button_scale(value: float) -> void:
    button_scale = clampf(value, 0.75, 1.35)
    _apply_settings()

func set_mouse_sensitivity(value: float) -> void:
    mouse_sensitivity = clampf(value, 0.0005, 0.02)
    _apply_settings()

func set_camera_smoothing(value: float) -> void:
    camera_smoothing = clampf(value, 4.0, 30.0)
    _apply_settings()

func set_show_fps(value: bool) -> void:
    show_fps = value
    _apply_settings()

func set_master_volume_db(value: float) -> void:
    master_volume_db = clampf(value, -80.0, 12.0)
    _apply_settings()

func set_music_volume_db(value: float) -> void:
    music_volume_db = clampf(value, -80.0, 12.0)
    _apply_settings()

func set_sfx_volume_db(value: float) -> void:
    sfx_volume_db = clampf(value, -80.0, 12.0)
    _apply_settings()

func _sanitize_quality() -> void:
    match quality_preset:
        "performance":
            max_fps = 45
            vsync_enabled = false
            render_scale = 0.70
            vegetation_density = 0.40
        "balanced":
            max_fps = 60
            vsync_enabled = true
            render_scale = 0.90
            vegetation_density = 0.70
        "quality":
            max_fps = 60
            vsync_enabled = true
            render_scale = 1.0
            vegetation_density = 1.0
        _:
            quality_preset = "balanced"
            max_fps = 60
            vsync_enabled = true

func _apply_settings() -> void:
    Engine.max_fps = max_fps
    var viewport := get_viewport()
    if viewport != null:
        viewport.scaling_3d_scale = render_scale

    DisplayServer.window_set_vsync_mode(
            DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
    )

    var master_bus := AudioServer.get_bus_index("Master")
    if master_bus >= 0:
        AudioServer.set_bus_volume_db(master_bus, master_volume_db)

    var music_bus := AudioServer.get_bus_index("Music")
    if music_bus >= 0:
        AudioServer.set_bus_volume_db(music_bus, music_volume_db)

    var sfx_bus := AudioServer.get_bus_index("SFX")
    if sfx_bus >= 0:
        AudioServer.set_bus_volume_db(sfx_bus, sfx_volume_db)

    emit_signal("settings_changed")
    EventBus.emit_signal("settings_changed")
