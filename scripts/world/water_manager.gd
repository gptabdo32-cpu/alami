class_name WaterManager
extends MeshInstance3D

@export var water_level := -1.5
@export var follow_grid_size := 256.0
@export var ocean_size := 6144.0
var player: Node3D

func _ready() -> void:
    var plane := PlaneMesh.new()
    plane.size = Vector2(ocean_size, ocean_size)
    plane.subdivide_width = 1
    plane.subdivide_depth = 1
    mesh = plane
    position.y = water_level
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.03, 0.20, 0.34, 0.82)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.roughness = 0.12
    material.metallic = 0.02
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material_override = material
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_delta: float) -> void:
    if player == null or not is_instance_valid(player):
        player = get_tree().get_first_node_in_group("player") as Node3D
    if player == null: return
    position.x = snappedf(player.global_position.x, follow_grid_size)
    position.z = snappedf(player.global_position.z, follow_grid_size)
