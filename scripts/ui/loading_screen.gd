class_name LoadingScreen
extends CanvasLayer

var panel: ColorRect
var label: Label
var progress: ProgressBar

func _ready() -> void:
    layer = 100
    process_mode = Node.PROCESS_MODE_ALWAYS
    panel = ColorRect.new()
    panel.color = Color(0.015, 0.025, 0.045, 1.0)
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(panel)
    var center := VBoxContainer.new()
    center.set_anchors_preset(Control.PRESET_CENTER)
    center.position = Vector2(-220, -60)
    center.size = Vector2(440, 120)
    panel.add_child(center)
    label = Label.new()
    label.text = "OPEN WORLD FOUNDATION PRO %s\nPreparing the initial world cell..." % GameState.BUILD_LABEL
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    center.add_child(label)
    progress = ProgressBar.new()
    progress.indeterminate = true
    progress.custom_minimum_size = Vector2(440, 16)
    center.add_child(progress)

func set_status(text: String) -> void:
    if label != null:
        label.text = "OPEN WORLD FOUNDATION PRO %s\n" % GameState.BUILD_LABEL + text

func finish() -> void:
    var tween := create_tween()
    tween.tween_property(panel, "modulate:a", 0.0, 0.35)
    await tween.finished
    queue_free()
