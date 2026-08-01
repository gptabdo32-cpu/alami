class_name PlayerController
extends CharacterBody3D

@export var walk_speed := 6.0
@export var sprint_speed := 10.25
@export var crouch_speed := 3.35
@export var jump_velocity := 4.5
@export var acceleration := 18.0
@export var deceleration := 24.0
@export var gravity_scale := 1.0
@export var standing_camera_height := 1.6
@export var crouching_camera_height := 1.15
@export var headbob_amplitude := 0.03
@export var headbob_frequency := 8.5

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var gravity_value := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var camera_pitch := 0.0
var target_pitch := 0.0
var target_yaw := 0.0
var controls: Node = null
var state_sync_accumulator := 0.0
var gameplay_enabled := true
var is_crouched := false
var headbob_time := 0.0
var touch_look_buffer := Vector2.ZERO
var camera_smoothing := 14.0

func _ready() -> void:
    add_to_group("player")
    camera.current = true
    target_yaw = rotation.y
    camera_pivot.position.y = standing_camera_height
    spring_arm.spring_length = 4.0
    camera_smoothing = SettingsSystem.camera_smoothing
    if not EventBus.settings_changed.is_connected(_on_settings_changed):
        EventBus.settings_changed.connect(_on_settings_changed)

func apply_persisted_state(position: Vector3, yaw: float, pitch: float) -> void:
    global_position = position
    rotation.y = yaw
    target_yaw = yaw
    camera_pitch = clampf(pitch, deg_to_rad(-75.0), deg_to_rad(75.0))
    target_pitch = camera_pitch
    camera_pivot.rotation.x = camera_pitch
    _apply_camera_height(true)

func set_gameplay_enabled(enabled: bool) -> void:
    gameplay_enabled = enabled
    if not enabled:
        velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _queue_look_delta(event.relative, SettingsSystem.mouse_sensitivity)

func _physics_process(delta: float) -> void:
    if not gameplay_enabled:
        velocity = Vector3.ZERO
        return

    if controls == null or not is_instance_valid(controls):
        controls = get_tree().get_first_node_in_group("mobile_controls")

    _apply_look(delta)
    _apply_movement(delta)
    _apply_posture(delta)
    _sync_state(delta)

func _apply_look(delta: float) -> void:
    if controls != null and controls.has_method("consume_look_delta"):
        var raw: Vector2 = controls.consume_look_delta()
        if raw != Vector2.ZERO:
            var size := get_viewport().get_visible_rect().size
            var diagonal := maxf(sqrt(size.x * size.x + size.y * size.y), 1.0)
            var normalized := raw / diagonal
            var target := normalized * SettingsSystem.touch_sensitivity * 8.0
            touch_look_buffer = touch_look_buffer.lerp(target, clampf(camera_smoothing * delta, 0.0, 1.0))
        else:
            touch_look_buffer = touch_look_buffer.lerp(Vector2.ZERO, clampf(8.0 * delta, 0.0, 1.0))
        _queue_look_delta(touch_look_buffer, 1.0)

    rotation.y = lerp_angle(rotation.y, target_yaw, clampf(camera_smoothing * delta, 0.0, 1.0))
    camera_pitch = lerpf(camera_pitch, target_pitch, clampf(camera_smoothing * delta, 0.0, 1.0))
    camera_pivot.rotation.x = camera_pitch

func _queue_look_delta(delta_vector: Vector2, sensitivity: float) -> void:
    target_yaw -= delta_vector.x * sensitivity
    target_pitch = clampf(target_pitch - delta_vector.y * sensitivity, deg_to_rad(-75.0), deg_to_rad(75.0))

func _apply_movement(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity_value * gravity_scale * delta

    var wants_jump := Input.is_action_just_pressed("jump")
    if controls != null and controls.has_method("consume_jump"):
        wants_jump = wants_jump or bool(controls.consume_jump())
    if is_on_floor() and wants_jump:
        velocity.y = jump_velocity

    var wants_crouch := Input.is_action_pressed("crouch")
    if controls != null and controls.has_method("consume_crouch"):
        wants_crouch = wants_crouch or bool(controls.consume_crouch())
    is_crouched = wants_crouch and is_on_floor()

    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
    if controls != null and controls.has_method("consume_move_vector"):
        var mobile_dir: Vector2 = controls.consume_move_vector()
        if mobile_dir.length() > input_dir.length():
            input_dir = mobile_dir

    var forward := -global_transform.basis.z
    var right := global_transform.basis.x
    forward.y = 0.0
    right.y = 0.0
    var direction := (right.normalized() * input_dir.x + forward.normalized() * -input_dir.y).normalized()

    var wants_sprint := Input.is_action_pressed("sprint")
    if controls != null and controls.has_method("consume_sprint"):
        wants_sprint = wants_sprint or bool(controls.consume_sprint())

    var speed := walk_speed
    if is_crouched:
        speed = crouch_speed
        wants_sprint = false
    elif wants_sprint:
        speed = sprint_speed

    var rate := acceleration if direction != Vector3.ZERO else deceleration
    velocity.x = move_toward(velocity.x, direction.x * speed, rate * delta)
    velocity.z = move_toward(velocity.z, direction.z * speed, rate * delta)

    if is_on_floor() and direction != Vector3.ZERO:
        headbob_time += delta * (headbob_frequency if not is_crouched else headbob_frequency * 0.7)
    else:
        headbob_time = lerpf(headbob_time, 0.0, clampf(8.0 * delta, 0.0, 1.0))

    move_and_slide()

func _apply_posture(delta: float) -> void:
    var target_height := crouching_camera_height if is_crouched else standing_camera_height
    camera_pivot.position.y = lerpf(camera_pivot.position.y, target_height, clampf(10.0 * delta, 0.0, 1.0))
    var bob := 0.0
    if is_on_floor() and velocity.length() > 0.3:
        bob = sin(headbob_time) * headbob_amplitude
    camera.position.y = bob

func _sync_state(delta: float) -> void:
    state_sync_accumulator += delta
    if state_sync_accumulator >= 0.10:
        state_sync_accumulator = 0.0
        GameState.player_is_crouched = is_crouched
        GameState.set_player_state_silent(global_position, rotation.y, camera_pitch)
        EventBus.player_position_changed.emit(global_position)

func _apply_camera_height(immediate: bool = false) -> void:
    var target_height := crouching_camera_height if GameState.player_is_crouched else standing_camera_height
    if immediate:
        camera_pivot.position.y = target_height
    else:
        camera_pivot.position.y = lerpf(camera_pivot.position.y, target_height, 1.0)
    is_crouched = GameState.player_is_crouched

func _on_settings_changed() -> void:
    camera_smoothing = SettingsSystem.camera_smoothing
