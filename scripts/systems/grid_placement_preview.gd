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
var allows_map_geometry_stack := false
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


func set_building_preview(preview_size: Vector3, color: Color, shape: String = "box") -> void:
	if _ghost_mesh_instance == null:
		return

	if shape == "ramp":
		_ghost_mesh_instance.mesh = _create_ramp_mesh(preview_size)
		_ghost_mesh_instance.position.y = preview_size.y * 0.5
	else:
		var ghost_mesh := BoxMesh.new()
		ghost_mesh.size = preview_size
		ghost_mesh.material = _ghost_material
		_ghost_mesh_instance.mesh = ghost_mesh
		_ghost_mesh_instance.position.y = preview_size.y * 0.5

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


func set_allows_map_geometry_stack(is_allowed: bool) -> void:
	allows_map_geometry_stack = is_allowed


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
	is_current_cell_valid = _can_place_current_footprint()
	visible = display_enabled and map_grid.is_footprint_in_bounds(current_cell, footprint)

	if not visible:
		_ghost_mesh_instance.visible = false
		return

	var preview_base_height := _get_preview_base_height()
	global_position = map_grid.footprint_to_world_center(current_cell, footprint, preview_base_height + 0.08)
	_preview_material.albedo_color = valid_color if is_current_cell_valid else blocked_color
	if is_current_cell_valid:
		_ghost_material.albedo_color = Color(_ghost_base_color.r, _ghost_base_color.g, _ghost_base_color.b, 0.34)
	else:
		_ghost_material.albedo_color = Color(blocked_color.r, blocked_color.g, blocked_color.b, 0.34)
	_ghost_mesh_instance.visible = true


func _can_place_current_footprint() -> bool:
	if not allows_map_geometry_stack:
		return map_grid.can_place(current_cell, footprint)

	if not map_grid.is_footprint_in_bounds(current_cell, footprint):
		return false

	for cell in map_grid.get_footprint_cells(current_cell, footprint):
		var occupant: Variant = map_grid.get_occupant(cell)
		if occupant != null and not _is_map_geometry_node(occupant):
			return false

	return true


func _is_map_geometry_node(value: Variant) -> bool:
	return value is Node and (value as Node).has_meta("geometry_name")


func _get_preview_base_height() -> float:
	if not allows_map_geometry_stack:
		return 0.0

	var stack_height := 0.0
	for cell in map_grid.get_footprint_cells(current_cell, footprint):
		for map_geometry in get_tree().get_nodes_in_group("rts_map_geometry"):
			if not (map_geometry is Node):
				continue

			if not _is_cell_inside_node_footprint(map_geometry, cell):
				continue

			stack_height = maxf(stack_height, _get_map_geometry_top_height(map_geometry))

	return stack_height


func _is_cell_inside_node_footprint(node: Node, cell: Vector2i) -> bool:
	if not node.has_meta("grid_anchor_cell") or not node.has_meta("grid_footprint"):
		return false

	var anchor_cell: Vector2i = node.get_meta("grid_anchor_cell")
	var node_footprint: Vector2i = node.get_meta("grid_footprint")
	return cell.x >= anchor_cell.x \
		and cell.y >= anchor_cell.y \
		and cell.x < anchor_cell.x + node_footprint.x \
		and cell.y < anchor_cell.y + node_footprint.y


func _get_map_geometry_top_height(map_geometry: Node) -> float:
	var base_height := float(map_geometry.get_meta("geometry_base_height", 0.0))
	var size: Vector3 = map_geometry.get_meta("geometry_size", Vector3.ZERO)
	return base_height + size.y


func _create_ramp_mesh(ramp_size: Vector3) -> ArrayMesh:
	var half_x := ramp_size.x * 0.5
	var half_y := ramp_size.y * 0.5
	var half_z := ramp_size.z * 0.5
	var ramp_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([
		Vector3(-half_x, -half_y, -half_z),
		Vector3(half_x, -half_y, -half_z),
		Vector3(-half_x, -half_y, half_z),
		Vector3(half_x, -half_y, half_z),
		Vector3(-half_x, half_y, half_z),
		Vector3(half_x, half_y, half_z)
	])
	var indices := PackedInt32Array([
		0, 2, 1,
		1, 2, 3,
		2, 4, 3,
		3, 4, 5,
		0, 1, 4,
		1, 5, 4,
		0, 4, 2,
		1, 3, 5
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	ramp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ramp_mesh.surface_set_material(0, _ghost_material)
	return ramp_mesh


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
