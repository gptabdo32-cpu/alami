extends CanvasLayer

signal save_requested
signal load_requested
signal closed
signal reset_requested

@onready var safe_area: Control = $SafeArea
@onready var quality_option: OptionButton = $SafeArea/PanelContainer/VBoxContainer/QualityRow/QualityOption
@onready var fps_toggle: CheckButton = $SafeArea/PanelContainer/VBoxContainer/FpsRow/FpsToggle
@onready var touch_slider: HSlider = $SafeArea/PanelContainer/VBoxContainer/TouchRow/TouchSlider
@onready var joystick_slider: HSlider = $SafeArea/PanelContainer/VBoxContainer/JoystickRow/JoystickSlider
@onready var opacity_slider: HSlider = $SafeArea/PanelContainer/VBoxContainer/OpacityRow/OpacitySlider
@onready var volume_slider: HSlider = $SafeArea/PanelContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var close_button: Button = $SafeArea/PanelContainer/VBoxContainer/ButtonsRow/CloseButton
@onready var save_button: Button = $SafeArea/PanelContainer/VBoxContainer/ButtonsRow/SaveButton
@onready var load_button: Button = $SafeArea/PanelContainer/VBoxContainer/ButtonsRow/LoadButton
@onready var reset_button: Button = $SafeArea/PanelContainer/VBoxContainer/ButtonsRow/ResetButton

func is_menu_open() -> bool:
    return safe_area != null and safe_area.visible

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    safe_area.visible = false

    quality_option.clear()
    quality_option.add_item("Performance")
    quality_option.add_item("Balanced")
    quality_option.add_item("Quality")
    quality_option.item_selected.connect(_on_quality_selected)

    fps_toggle.toggled.connect(_on_fps_toggled)

    touch_slider.min_value = 0.15
    touch_slider.max_value = 3.00
    touch_slider.step = 0.01
    touch_slider.value_changed.connect(_on_touch_sensitivity_changed)

    joystick_slider.min_value = 0.75
    joystick_slider.max_value = 1.50
    joystick_slider.step = 0.01
    joystick_slider.value_changed.connect(_on_joystick_scale_changed)

    opacity_slider.min_value = 0.35
    opacity_slider.max_value = 1.0
    opacity_slider.step = 0.01
    opacity_slider.value_changed.connect(_on_button_opacity_changed)

    volume_slider.min_value = -80.0
    volume_slider.max_value = 12.0
    volume_slider.step = 0.5
    volume_slider.value_changed.connect(_on_master_volume_changed)

    close_button.pressed.connect(_on_close_pressed)
    save_button.pressed.connect(func(): save_requested.emit())
    load_button.pressed.connect(func(): load_requested.emit())
    reset_button.pressed.connect(_on_reset_pressed)

    _sync_controls()

func open_menu() -> void:
    if is_menu_open():
        return
    safe_area.visible = true
    get_tree().paused = true
    TimeSystem.pause_time(true)
    _sync_controls()

func close_menu() -> void:
    if not is_menu_open():
        return
    safe_area.visible = false
    get_tree().paused = false
    TimeSystem.pause_time(false)
    closed.emit()

func toggle_menu() -> void:
    if is_menu_open():
        close_menu()
    else:
        open_menu()

func _sync_controls() -> void:
    match SettingsSystem.quality_preset:
        "performance":
            quality_option.select(0)
        "balanced":
            quality_option.select(1)
        "quality":
            quality_option.select(2)
        _:
            quality_option.select(1)

    fps_toggle.button_pressed = SettingsSystem.show_fps
    touch_slider.value = SettingsSystem.touch_sensitivity
    joystick_slider.value = SettingsSystem.joystick_scale
    opacity_slider.value = SettingsSystem.button_opacity
    volume_slider.value = SettingsSystem.master_volume_db

func _on_quality_selected(index: int) -> void:
    match index:
        0:
            SettingsSystem.set_quality_preset("performance")
        1:
            SettingsSystem.set_quality_preset("balanced")
        2:
            SettingsSystem.set_quality_preset("quality")
    SettingsSystem.save_settings()

func _on_fps_toggled(pressed: bool) -> void:
    SettingsSystem.set_show_fps(pressed)
    SettingsSystem.save_settings()

func _on_touch_sensitivity_changed(value: float) -> void:
    SettingsSystem.set_touch_sensitivity(value)
    SettingsSystem.save_settings()

func _on_joystick_scale_changed(value: float) -> void:
    SettingsSystem.set_joystick_scale(value)
    SettingsSystem.save_settings()

func _on_button_opacity_changed(value: float) -> void:
    SettingsSystem.set_button_opacity(value)
    SettingsSystem.save_settings()

func _on_master_volume_changed(value: float) -> void:
    SettingsSystem.set_master_volume_db(value)
    SettingsSystem.save_settings()

func _on_reset_pressed() -> void:
    SettingsSystem.reset_defaults()
    SettingsSystem.save_settings()
    _sync_controls()
    reset_requested.emit()

func _on_close_pressed() -> void:
    close_menu()
