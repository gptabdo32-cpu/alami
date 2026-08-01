extends CanvasLayer

signal menu_pressed

@onready var safe_area: Control = $SafeArea
@onready var move_pad: Control = $SafeArea/MovePad
@onready var move_knob: Control = $SafeArea/MovePad/Knob
@onready var look_zone: Control = $SafeArea/LookZone
@onready var jump_button: Button = $SafeArea/Buttons/JumpButton
@onready var sprint_button: Button = $SafeArea/Buttons/SprintButton
@onready var interact_button: Button = $SafeArea/Buttons/InteractButton
@onready var menu_button: Button = $SafeArea/Buttons/MenuButton

var screen_size: Vector2 = Vector2.ZERO
var screen_dpi: float = 160.0
var move_touch_id: int = -1
var look_touch_id: int = -1
var move_position: Vector2 = Vector2.ZERO
var move_visual_vector: Vector2 = Vector2.ZERO
var move_vector: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO

var joystick_radius: float = 108.0
var movement_deadzone: float = 0.14
var button_opacity: float = 0.90
var button_scale: float = 1.00
var pressed_scale: float = 0.94
var safe_padding: float = 24.0

var jump_requested: bool = false
var interact_requested: bool = false
var menu_requested: bool = false
var sprint_held: bool = false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    add_to_group("mobile_controls")

    safe_area.visible = SettingsSystem.is_mobile_runtime()
    visible = safe_area.visible
    if not safe_area.visible:
        return

    _update_screen_metrics()
    _apply_safe_area()
    _apply_settings()

    if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
        get_viewport().size_changed.connect(_on_viewport_size_changed)

    if not EventBus.settings_changed.is_connected(_on_settings_changed):
        EventBus.settings_changed.connect(_on_settings_changed)

    jump_button.pressed.connect(_on_jump_pressed)
    sprint_button.button_down.connect(_on_sprint_down)
    sprint_button.button_up.connect(_on_sprint_up)
    interact_button.pressed.connect(_on_interact_pressed)
    menu_button.pressed.connect(_on_menu_pressed)

    _set_button_feedback(jump_button, false)
    _set_button_feedback(sprint_button, false)
    _set_button_feedback(interact_button, false)
    _set_button_feedback(menu_button, false)
    _update_move_visual()

func _process(delta: float) -> void:
    if safe_area == null or not safe_area.visible:
        return

    _update_move_visual()

    # Very small release decay helps touch feel less sticky on some devices.
    if look_delta != Vector2.ZERO:
        look_delta = look_delta.limit_length(420.0)
        look_delta = look_delta.lerp(Vector2.ZERO, clampf(5.0 * delta, 0.0, 1.0))

func _input(event: InputEvent) -> void:
    if safe_area == null or not safe_area.visible:
        return

    if event is InputEventScreenTouch:
        var touch: InputEventScreenTouch = event
        if touch.pressed:
            _handle_touch_pressed(touch.index, touch.position)
        else:
            _handle_touch_released(touch.index)
    elif event is InputEventScreenDrag:
        var drag: InputEventScreenDrag = event
        if drag.index == move_touch_id:
            move_position = drag.position
            _update_move_vector()
        elif drag.index == look_touch_id:
            look_delta += drag.relative

func _on_viewport_size_changed() -> void:
    _update_screen_metrics()
    _apply_safe_area()

func _on_settings_changed() -> void:
    _apply_settings()

func _apply_settings() -> void:
    var min_dimension: float = maxf(1.0, minf(screen_size.x, screen_size.y))
    var dpi_factor: float = clampf(screen_dpi / 320.0, 0.80, 1.35)

    movement_deadzone = clampf(SettingsSystem.joystick_deadzone, 0.05, 0.30)
    joystick_radius = clampf(min_dimension * 0.115 * dpi_factor, 92.0, 164.0) * SettingsSystem.joystick_scale
    button_scale = clampf(SettingsSystem.button_scale, 0.75, 1.35)
    button_opacity = clampf(SettingsSystem.button_opacity, 0.35, 1.0)
    safe_padding = clampf(min_dimension * 0.022, 18.0, 32.0)

    var pad_size := joystick_radius * 2.55
    move_pad.size = Vector2(pad_size, pad_size)
    move_pad.position = Vector2(safe_padding, screen_size.y - pad_size - safe_padding)

    var knob_size := joystick_radius * 0.72
    move_knob.size = Vector2(knob_size, knob_size)

    _layout_action_buttons(min_dimension, dpi_factor)
    _set_button_alpha(jump_button, button_opacity)
    _set_button_alpha(sprint_button, button_opacity)
    _set_button_alpha(interact_button, button_opacity)
    _set_button_alpha(menu_button, button_opacity)

    _update_move_visual()

func _layout_action_buttons(min_dimension: float, dpi_factor: float) -> void:
    var action_size := clampf(min_dimension * 0.085 * dpi_factor * button_scale, 74.0, 134.0)
    var action_height := action_size * 0.82
    var gap := clampf(action_size * 0.18, 8.0, 16.0)
    var top_margin := safe_padding
    var bottom_margin := safe_padding + 4.0

    menu_button.size = Vector2(action_size, action_height)
    menu_button.position = Vector2(screen_size.x - action_size - safe_padding, top_margin)

    jump_button.size = Vector2(action_size, action_height)
    sprint_button.size = Vector2(action_size, action_height)
    interact_button.size = Vector2(action_size, action_height)

    jump_button.position = Vector2(screen_size.x - action_size - safe_padding, screen_size.y - action_height - bottom_margin)
    sprint_button.position = Vector2(jump_button.position.x - action_size - gap, jump_button.position.y)
    interact_button.position = Vector2(sprint_button.position.x - action_size - gap, jump_button.position.y)

func _update_screen_metrics() -> void:
    if get_viewport() != null:
        screen_size = get_viewport().get_visible_rect().size
    else:
        screen_size = Vector2.ZERO

    var dpi := 160.0
    if DisplayServer.get_name() != "headless":
        dpi = float(DisplayServer.screen_get_dpi())
    screen_dpi = clampf(dpi, 96.0, 640.0)

func is_enabled() -> bool:
    return safe_area != null and safe_area.visible

func _apply_safe_area() -> void:
    if safe_area == null:
        return
    var rect := DisplayServer.get_display_safe_area()
    if rect.size.x <= 0 or rect.size.y <= 0:
        safe_area.position = Vector2.ZERO
        safe_area.size = screen_size
        return
    var window_size := DisplayServer.window_get_size()
    var sx := screen_size.x / maxf(float(window_size.x), 1.0)
    var sy := screen_size.y / maxf(float(window_size.y), 1.0)
    safe_area.position = Vector2(rect.position.x * sx, rect.position.y * sy)
    safe_area.size = Vector2(rect.size.x * sx, rect.size.y * sy)

func _handle_touch_pressed(index: int, position: Vector2) -> void:
    if move_pad != null and move_pad.get_global_rect().has_point(position) and move_touch_id == -1:
        move_touch_id = index
        move_position = position
        _update_move_vector()
        return

    if _touch_hits_action_button(position):
        return

    if _is_in_look_zone(position) and look_touch_id == -1:
        look_touch_id = index
        return

func _handle_touch_released(index: int) -> void:
    if index == move_touch_id:
        move_touch_id = -1
        move_vector = Vector2.ZERO
        move_visual_vector = Vector2.ZERO
        _update_move_visual()

    if index == look_touch_id:
        look_touch_id = -1

func _touch_hits_action_button(position: Vector2) -> bool:
    if jump_button != null and jump_button.get_global_rect().has_point(position):
        return true
    if sprint_button != null and sprint_button.get_global_rect().has_point(position):
        return true
    if interact_button != null and interact_button.get_global_rect().has_point(position):
        return true
    if menu_button != null and menu_button.get_global_rect().has_point(position):
        return true
    return false

func _is_in_look_zone(position: Vector2) -> bool:
    if look_zone != null:
        var rect: Rect2 = look_zone.get_global_rect()
        if rect.size.x > 16.0 and rect.size.y > 16.0:
            return rect.has_point(position)
    if screen_size == Vector2.ZERO:
        return false
    return position.x >= screen_size.x * 0.36

func _update_move_vector() -> void:
    if move_pad == null:
        return

    var pad_rect: Rect2 = move_pad.get_global_rect()
    var center: Vector2 = pad_rect.get_center()

    var raw: Vector2 = move_position - center
    var clamped_raw: Vector2 = raw.limit_length(joystick_radius)

    move_visual_vector = clamped_raw / joystick_radius

    var normalized_length: float = move_visual_vector.length()
    if normalized_length <= movement_deadzone:
        move_vector = Vector2.ZERO
    else:
        var mapped_length: float = (normalized_length - movement_deadzone) / (1.0 - movement_deadzone)
        mapped_length = clampf(mapped_length, 0.0, 1.0)
        move_vector = move_visual_vector.normalized() * pow(mapped_length, SettingsSystem.joystick_curve)

func _update_move_visual() -> void:
    if move_pad == null or move_knob == null:
        return

    var pad_rect: Rect2 = move_pad.get_global_rect()
    var center: Vector2 = pad_rect.get_center()
    var knob_size: Vector2 = move_knob.size
    var knob_position: Vector2 = center + (move_visual_vector * joystick_radius) - (knob_size * 0.5)
    move_knob.global_position = knob_position

func _set_button_alpha(button: Button, alpha: float) -> void:
    if button == null:
        return
    var tint: Color = button.modulate
    tint.a = alpha
    button.modulate = tint

func _set_button_feedback(button: Button, pressed: bool) -> void:
    if button == null:
        return
    var scale_factor := pressed_scale if pressed else 1.0
    button.scale = Vector2.ONE * scale_factor

func consume_move_vector() -> Vector2:
    return move_vector

func consume_look_delta() -> Vector2:
    var delta: Vector2 = look_delta
    look_delta = Vector2.ZERO
    return delta

func consume_jump() -> bool:
    var value: bool = jump_requested
    jump_requested = false
    return value

func consume_sprint() -> bool:
    return sprint_held

func consume_crouch() -> bool:
    return false

func consume_interact() -> bool:
    var value: bool = interact_requested
    interact_requested = false
    return value

func consume_menu() -> bool:
    var value: bool = menu_requested
    menu_requested = false
    return value

func _on_jump_pressed() -> void:
    jump_requested = true
    _set_button_feedback(jump_button, true)
    await get_tree().process_frame
    _set_button_feedback(jump_button, false)

func _on_sprint_down() -> void:
    sprint_held = true
    _set_button_feedback(sprint_button, true)

func _on_sprint_up() -> void:
    sprint_held = false
    _set_button_feedback(sprint_button, false)

func _on_interact_pressed() -> void:
    interact_requested = true
    _set_button_feedback(interact_button, true)
    await get_tree().process_frame
    _set_button_feedback(interact_button, false)

func _on_menu_pressed() -> void:
    menu_requested = true
    _set_button_feedback(menu_button, true)
    emit_signal("menu_pressed")
    await get_tree().process_frame
    _set_button_feedback(menu_button, false)
