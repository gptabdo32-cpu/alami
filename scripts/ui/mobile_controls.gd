extends CanvasLayer

signal menu_pressed

@onready var safe_area: Control = $SafeArea
@onready var move_pad: Control = $SafeArea/MovePad
@onready var move_knob: Control = $SafeArea/MovePad/Knob
@onready var move_base: Control = $SafeArea/MovePad/Base
@onready var look_zone: Control = $SafeArea/LookZone
@onready var jump_button: Button = $SafeArea/Buttons/JumpButton
@onready var sprint_button: Button = $SafeArea/Buttons/SprintButton
@onready var interact_button: Button = $SafeArea/Buttons/InteractButton
@onready var crouch_button: Button = $SafeArea/Buttons/CrouchButton
@onready var menu_button: Button = $SafeArea/Buttons/MenuButton

var screen_size: Vector2 = Vector2.ZERO
var screen_dpi: float = 160.0
var move_touch_id: int = -1
var look_touch_id: int = -1
var move_start_pos: Vector2 = Vector2.ZERO
var move_current_pos: Vector2 = Vector2.ZERO
var move_visual_vector: Vector2 = Vector2.ZERO
var move_vector: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO

var joystick_radius: float = 120.0
var movement_deadzone: float = 0.15
var button_opacity: float = 0.7
var button_scale: float = 1.0
var pressed_scale: float = 0.9
var safe_padding: float = 32.0

var jump_requested: bool = false
var interact_requested: bool = false
var menu_requested: bool = false
var sprint_held: bool = false
var crouch_held: bool = false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    add_to_group("mobile_controls")

    safe_area.visible = SettingsSystem.is_mobile_runtime()
    visible = safe_area.visible
    if not safe_area.visible:
        return

    _update_screen_metrics()
    _apply_safe_area()
    _setup_visuals()
    
    # Initial state: Joystick hidden or dimmed until touch
    move_pad.modulate.a = 0.3
    
    if get_viewport() != null:
        get_viewport().size_changed.connect(_on_viewport_size_changed)

    if not EventBus.settings_changed.is_connected(_on_settings_changed):
        EventBus.settings_changed.connect(_on_settings_changed)

    jump_button.pressed.connect(_on_jump_pressed)
    sprint_button.button_down.connect(_on_sprint_down)
    sprint_button.button_up.connect(_on_sprint_up)
    interact_button.pressed.connect(_on_interact_pressed)
    crouch_button.button_down.connect(_on_crouch_down)
    crouch_button.button_up.connect(_on_crouch_up)
    menu_button.pressed.connect(_on_menu_pressed)

    _update_move_visual()

func _setup_visuals() -> void:
    # Create a professional look using StyleBoxFlat
    var button_style = StyleBoxFlat.new()
    button_style.set_corner_radius_all(100) # Circular buttons
    button_style.bg_color = Color(1, 1, 1, 0.15)
    button_style.border_width_all = 2
    button_style.border_color = Color(1, 1, 1, 0.4)
    button_style.set_expand_margin_all(4)
    
    var pressed_style = button_style.duplicate()
    pressed_style.bg_color = Color(1, 1, 1, 0.4)
    pressed_style.border_color = Color(1, 1, 1, 0.8)
    
    var buttons = [jump_button, sprint_button, interact_button, crouch_button, menu_button]
    for btn in buttons:
        btn.add_theme_stylebox_override("normal", button_style)
        btn.add_theme_stylebox_override("hover", button_style)
        btn.add_theme_stylebox_override("pressed", pressed_style)
        btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
        btn.pivot_offset = btn.size / 2
        
    # Style the Joystick
    var base_style = StyleBoxFlat.new()
    base_style.set_corner_radius_all(1000)
    base_style.bg_color = Color(0, 0, 0, 0.2)
    base_style.border_width_all = 3
    base_style.border_color = Color(1, 1, 1, 0.2)
    move_base.add_theme_stylebox_override("panel", base_style)
    
    var knob_style = StyleBoxFlat.new()
    knob_style.set_corner_radius_all(1000)
    knob_style.bg_color = Color(1, 1, 1, 0.6)
    knob_style.border_width_all = 2
    knob_style.border_color = Color(1, 1, 1, 0.8)
    knob_style.shadow_color = Color(0, 0, 0, 0.3)
    knob_style.shadow_size = 8
    move_knob.add_theme_stylebox_override("panel", knob_style)
    
    _apply_settings()

func _process(delta: float) -> void:
    if not visible: return
    
    _update_move_visual()
    
    # Smooth decay for look delta
    if look_delta != Vector2.ZERO:
        look_delta = look_delta.lerp(Vector2.ZERO, 15.0 * delta)

func _input(event: InputEvent) -> void:
    if not visible: return

    if event is InputEventScreenTouch:
        if event.pressed:
            _handle_touch_pressed(event.index, event.position)
        else:
            _handle_touch_released(event.index)
    elif event is InputEventScreenDrag:
        if event.index == move_touch_id:
            move_current_pos = event.position
            _update_move_vector()
        elif event.index == look_touch_id:
            look_delta += event.relative

func _handle_touch_pressed(index: int, pos: Vector2) -> void:
    # 1. Check Buttons first
    if _touch_hits_action_button(pos):
        return

    # 2. Check Left side for Joystick (Floating)
    if pos.x < screen_size.x * 0.45 and move_touch_id == -1:
        move_touch_id = index
        move_start_pos = pos
        move_current_pos = pos
        
        # Position the joystick base where the finger touched
        move_pad.global_position = pos - (move_pad.size / 2)
        move_pad.modulate.a = 0.8 # Make it visible
        
        var tween = create_tween()
        tween.tween_property(move_pad, "scale", Vector2.ONE, 0.1).from(Vector2.ONE * 0.8)
        
        _update_move_vector()
        return

    # 3. Rest is Look Zone
    if look_touch_id == -1:
        look_touch_id = index

func _handle_touch_released(index: int) -> void:
    if index == move_touch_id:
        move_touch_id = -1
        move_vector = Vector2.ZERO
        move_visual_vector = Vector2.ZERO
        
        var tween = create_tween()
        tween.tween_property(move_pad, "modulate:a", 0.3, 0.2)
        tween.parallel().tween_property(move_pad, "scale", Vector2.ONE * 0.9, 0.2)
        
        # Reset to default position optionally, or stay at last pos
        _update_move_visual()

    if index == look_touch_id:
        look_touch_id = -1

func _update_move_vector() -> void:
    var diff = move_current_pos - move_start_pos
    var length = diff.length()
    
    if length > joystick_radius:
        # Optional: Move the base to follow the finger if it goes too far
        # move_start_pos += diff.normalized() * (length - joystick_radius)
        # move_pad.global_position = move_start_pos - (move_pad.size / 2)
        diff = diff.limit_length(joystick_radius)
    
    move_visual_vector = diff / joystick_radius
    
    var normalized_len = move_visual_vector.length()
    if normalized_len < movement_deadzone:
        move_vector = Vector2.ZERO
    else:
        var mapped = (normalized_len - movement_deadzone) / (1.0 - movement_deadzone)
        move_vector = move_visual_vector.normalized() * clampf(mapped, 0.0, 1.0)

func _update_move_visual() -> void:
    if move_knob == null: return
    move_knob.position = (move_pad.size / 2) + (move_visual_vector * joystick_radius) - (move_knob.size / 2)

func _touch_hits_action_button(pos: Vector2) -> bool:
    for btn in [jump_button, sprint_button, interact_button, crouch_button, menu_button]:
        if btn.get_global_rect().has_point(pos):
            return true
    return false

func _apply_settings() -> void:
    var min_dim = minf(screen_size.x, screen_size.y)
    var dpi_scale = screen_dpi / 160.0
    
    joystick_radius = (min_dim * 0.12) * SettingsSystem.joystick_scale
    var pad_size = joystick_radius * 2.4
    move_pad.size = Vector2(pad_size, pad_size)
    move_pad.pivot_offset = move_pad.size / 2
    
    var knob_size = joystick_radius * 0.8
    move_knob.size = Vector2(knob_size, knob_size)
    
    _layout_buttons()

func _layout_buttons() -> void:
    var btn_size = minf(screen_size.x, screen_size.y) * 0.11 * button_scale
    var gap = btn_size * 0.25
    
    var buttons = [jump_button, sprint_button, interact_button, crouch_button]
    for btn in buttons:
        btn.custom_minimum_size = Vector2(btn_size, btn_size)
        btn.size = btn.custom_minimum_size
        btn.pivot_offset = btn.size / 2
        
    # Arc layout for ergonomics (Right Hand)
    # Jump (Main)
    jump_button.position = Vector2(screen_size.x - btn_size - safe_padding, screen_size.y - btn_size - safe_padding - (btn_size * 0.3))
    
    # Sprint (Top-Left of Jump)
    sprint_button.position = Vector2(jump_button.position.x - btn_size * 0.6 - gap, jump_button.position.y - btn_size * 0.7 - gap)
    
    # Interact (Left of Jump)
    interact_button.position = Vector2(jump_button.position.x - btn_size - gap, jump_button.position.y + btn_size * 0.1)
    
    # Crouch (Bottom-Left of Jump)
    crouch_button.position = Vector2(jump_button.position.x - btn_size * 0.4 - gap, jump_button.position.y + btn_size * 0.9 + gap)
    
    menu_button.size = Vector2(btn_size * 0.9, btn_size * 0.5)
    menu_button.position = Vector2(screen_size.x - menu_button.size.x - safe_padding, safe_padding)

func _on_viewport_size_changed() -> void:
    _update_screen_metrics()
    _apply_safe_area()
    _apply_settings()

func _update_screen_metrics() -> void:
    screen_size = get_viewport().get_visible_rect().size
    screen_dpi = float(DisplayServer.screen_get_dpi()) if DisplayServer.get_name() != "headless" else 160.0

func _apply_safe_area() -> void:
    var rect = DisplayServer.get_display_safe_area()
    if rect.size.x > 0:
        var win_size = DisplayServer.window_get_size()
        var scale = screen_size / Vector2(win_size)
        safe_area.position = rect.position * scale
        safe_area.size = rect.size * scale
    else:
        safe_area.position = Vector2.ZERO
        safe_area.size = screen_size

# Consumables for the player controller
func consume_move_vector() -> Vector2: return move_vector
func consume_look_delta() -> Vector2:
    var d = look_delta
    look_delta = Vector2.ZERO
    return d
func consume_jump() -> bool:
    var v = jump_requested
    jump_requested = false
    return v
func consume_crouch() -> bool: return crouch_held
func consume_interact() -> bool:
    var v = interact_requested
    interact_requested = false
    return v
func consume_menu() -> bool:
    var v = menu_requested
    menu_requested = false
    return v

# Callbacks
func _on_jump_pressed() -> void:
    jump_requested = true
    _animate_press(jump_button)

func _on_sprint_down() -> void:
    sprint_held = true
    sprint_button.scale = Vector2.ONE * pressed_scale

func _on_sprint_up() -> void:
    sprint_held = false
    sprint_button.scale = Vector2.ONE

func _on_crouch_down() -> void:
    crouch_held = true
    crouch_button.scale = Vector2.ONE * pressed_scale

func _on_crouch_up() -> void:
    crouch_held = false
    crouch_button.scale = Vector2.ONE

func _on_interact_pressed() -> void:
    interact_requested = true
    _animate_press(interact_button)

func _on_menu_pressed() -> void:
    menu_requested = true
    _animate_press(menu_button)
    emit_signal("menu_pressed")

func _animate_press(btn: Button) -> void:
    var tween = create_tween()
    tween.tween_property(btn, "scale", Vector2.ONE * pressed_scale, 0.05)
    tween.tween_property(btn, "scale", Vector2.ONE, 0.1)

func _on_settings_changed() -> void:
    _apply_settings()
