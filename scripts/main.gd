extends Node3D

@onready var player: CharacterBody3D = $GameplayRoot/Player
@onready var world_manager: WorldManager = $GameplayRoot/WorldManager
@onready var settings_menu: CanvasLayer = $UIRoot/SettingsMenu
@onready var mobile_controls: CanvasLayer = $UIRoot/MobileControls
@onready var world_environment: WorldEnvironment = $EnvironmentRoot/WorldEnvironment
@onready var sun_light: DirectionalLight3D = $EnvironmentRoot/DirectionalLight3D

var boot_complete := false
var loading_screen: LoadingScreen
var mobile_runtime := OS.has_feature("mobile") or OS.has_feature("handheld")

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _setup_visual_environment()
    SettingsSystem.load_settings()
    _connect_signals()
    loading_screen = LoadingScreen.new()
    $UIRoot.add_child(loading_screen)
    loading_screen.set_status("Initializing core foundation and loading world state...")
    player.set_gameplay_enabled(false)
    _update_mouse_mode(false)
    call_deferred("_boot_game")

func _setup_visual_environment() -> void:
    if world_environment.environment != null:
        return
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color(0.16, 0.34, 0.62)
    sky_material.sky_horizon_color = Color(0.72, 0.82, 0.92)
    sky_material.ground_bottom_color = Color(0.08, 0.07, 0.06)
    sky_material.ground_horizon_color = Color(0.42, 0.40, 0.36)
    sky.sky_material = sky_material
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.glow_enabled = false
    world_environment.environment = env

func _connect_signals() -> void:
    if not GameState.save_requested.is_connected(_save_now):
        GameState.save_requested.connect(_save_now)
    if not GameState.load_requested.is_connected(_load_now):
        GameState.load_requested.connect(_load_now)
    if not settings_menu.save_requested.is_connected(_save_now):
        settings_menu.save_requested.connect(_save_now)
    if not settings_menu.load_requested.is_connected(_load_now):
        settings_menu.load_requested.connect(_load_now)
    if not settings_menu.closed.is_connected(_on_menu_closed):
        settings_menu.closed.connect(_on_menu_closed)
    if not mobile_controls.menu_pressed.is_connected(_toggle_menu):
        mobile_controls.menu_pressed.connect(_toggle_menu)
    if not world_manager.initial_chunk_ready.is_connected(_on_initial_chunk_ready):
        world_manager.initial_chunk_ready.connect(_on_initial_chunk_ready)

func _boot_game() -> void:
    if loading_screen != null:
        loading_screen.set_status("Checking save slot %s..." % GameState.save_slot)
    if not SaveSystem.load_game(GameState.save_slot):
        GameState.reset_defaults(GameState.world_seed)
        WorldDataSystem.reset_defaults(GameState.world_seed)
    else:
        WorldDataSystem.set_world_seed(GameState.world_seed)
    TimeSystem.set_time(GameState.time_of_day_minutes, GameState.day_index)
    player.apply_persisted_state(GameState.player_position, GameState.player_rotation_y, GameState.camera_pitch)
    if loading_screen != null:
        loading_screen.set_status("Streaming initial world cell...")
    _update_mouse_mode(false)
    world_manager.sync_from_state()

func _on_initial_chunk_ready() -> void:
    var ground := world_manager.get_height_at(player.global_position)
    if player.global_position.y < ground + 1.5 or player.global_position.y > ground + 80.0:
        player.global_position.y = ground + 2.2
    player.velocity = Vector3.ZERO
    player.set_gameplay_enabled(true)
    boot_complete = true
    _update_mouse_mode(false)
    if loading_screen != null:
        loading_screen.finish()

func _process(_delta: float) -> void:
    _update_day_night()
    if boot_complete and player.global_position.y < world_manager.get_height_at(player.global_position) - 40.0:
        _rescue_player()

func _rescue_player() -> void:
    var position := player.global_position
    position.y = world_manager.get_height_at(position) + 3.0
    player.global_position = position
    player.velocity = Vector3.ZERO
    EventBus.emit_debug("Player rescued from world fall.")

func _update_day_night() -> void:
    var t := TimeSystem.get_time_normalized()
    var sun_angle := t * TAU - PI * 0.5
    sun_light.rotation_degrees.x = rad_to_deg(sun_angle)
    var daylight := clampf(sin(sun_angle) * 0.5 + 0.5, 0.04, 1.0)
    sun_light.light_energy = lerpf(0.05, 1.8, daylight)
    sun_light.light_color = Color(1.0, lerpf(0.55, 0.96, daylight), lerpf(0.42, 0.88, daylight))

func _apply_state_to_scene() -> void:
    boot_complete = false
    player.set_gameplay_enabled(false)
    if settings_menu.has_method("is_menu_open") and bool(settings_menu.call("is_menu_open")):
        settings_menu.close_menu()
    player.apply_persisted_state(GameState.player_position, GameState.player_rotation_y, GameState.camera_pitch)
    _update_mouse_mode(false)
    world_manager.sync_from_state()
    if loading_screen != null:
        loading_screen.set_status("Restoring saved world cell...")

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("menu"):
        _toggle_menu()
    elif event.is_action_pressed("save_game"):
        _save_now()
    elif event.is_action_pressed("load_game"):
        _load_now()

func _toggle_menu() -> void:
    settings_menu.toggle_menu()
    _update_mouse_mode(settings_menu.is_menu_open())

func _on_menu_closed() -> void:
    TimeSystem.pause_time(false)
    _update_mouse_mode(false)

func _save_now() -> void:
    if boot_complete:
        SaveSystem.save_game(GameState.save_slot)

func _load_now() -> void:
    if loading_screen != null:
        loading_screen.set_status("Reloading save slot %s..." % GameState.save_slot)
    if SaveSystem.load_game(GameState.save_slot):
        TimeSystem.set_time(GameState.time_of_day_minutes, GameState.day_index)
        WorldDataSystem.set_world_seed(GameState.world_seed)
        _apply_state_to_scene()
    else:
        EventBus.emit_debug("Load failed: no valid save file.")

func _update_mouse_mode(menu_open: bool) -> void:
    if mobile_runtime:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        return
    if menu_open or not boot_complete:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    else:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
