class_name GridPlacementPreview
extends MeshInstance3D

@export var camera_path: NodePath
@export var grid_path: NodePath
@export var footprint: Vector2i = Vector2i.ONE
@export var valid_color: Color = Color(0.18, 0.8, 0.45, 0.38)
@export var blocked_color: Color = Color(0.95, 0.22, 0.18, 0.38)

@onready var camera: Camera3D = get_node(camera_path)
@onready var map_grid: MapGrid = get_node(grid_path)

var current_cell: Vector2i = Vector2i.ZERO
var current_world_point: Vector3 = Vector3.ZERO
var is_current_cell_valid := false
var display_enabled := true
var _preview_material: StandardMaterial3D
var _ghost_mesh_instance: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _ghost_base_color := Color.WHITE


func _ready() -> void:
	_preview_material = StandardMaterial3D.new()
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_create_ghost()
	_rebuild_preview_mesh()


func set_building_preview(size: Vector3, color: Color) -> void:
	if _ghost_mesh_instance == null:
		return

	var ghost_mesh := BoxMesh.new()
	ghost_mesh.size = size
	ghost_mesh.material = _ghost_material
	_ghost_mesh_instance.mesh = ghost_mesh
	_ghost_mesh_instance.position.y = size.y * 0.5

	_ghost_base_color = color
	_ghost_material.albedo_color = Color(color.r, color.g, color.b, 0.34)


func set_footprint(new_footprint: Vector2i) -> void:
	footprint = new_footprint
	if is_node_ready():
		_rebuild_preview_mesh()


func set_display_enabled(is_enabled: bool) -> void:
	display_enabled = is_enabled
	if not display_enabled:
		visible = false
		_ghost_mesh_instance.visible = false


func _rebuild_preview_mesh() -> void:
	var preview_mesh := PlaneMesh.new()
	preview_mesh.size = Vector2(
		float(footprint.x) * map_grid.cell_size,
		float(footprint.y) * map_grid.cell_size
	)
	preview_mesh.material = _preview_material
	mesh = preview_mesh


func _create_ghost() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.5, 0.85, 0.5, 0.34)
	_ghost_material.roughness = 0.8
	_ghost_material.no_depth_test = true

	_ghost_mesh_instance = MeshInstance3D.new()
	_ghost_mesh_instance.name = "GhostBuilding"
	_ghost_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost_mesh_instance)


func _process(_delta: float) -> void:
	current_world_point = _get_mouse_world_point()
	current_cell = map_grid.world_to_cell(current_world_point)
	is_current_cell_valid = map_grid.can_place(current_cell, footprint)
	visible = display_enabled and map_grid.is_footprint_in_bounds(current_cell, footprint)

	if not visible:
		_ghost_mesh_instance.visible = false
		return

	global_position = map_grid.footprint_to_world_center(current_cell, footprint, 0.08)
	_preview_material.albedo_color = valid_color if is_current_cell_valid else blocked_color
	if is_current_cell_valid:
		_ghost_material.albedo_color = Color(_ghost_base_color.r, _ghost_base_color.g, _ghost_base_color.b, 0.34)
	else:
		_ghost_material.albedo_color = Color(blocked_color.r, blocked_color.g, blocked_color.b, 0.34)
	_ghost_mesh_instance.visible = true


func _get_mouse_world_point() -> Vector3:
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	var ray_target := ray_origin + ray_direction * 1000.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.has("position"):
		return hit.position as Vector3

	var ground_plane := Plane(Vector3.UP, 0.0)
	var ground_hit: Variant = ground_plane.intersects_ray(ray_origin, ray_direction)
	if ground_hit is Vector3:
		return ground_hit

	return ray_origin + ray_direction * 100.0
