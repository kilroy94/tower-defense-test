extends Node

@export var camera_path: NodePath
@export var grid_path: NodePath
@export var popup_label_path: NodePath
@export var hover_delay_seconds: float = 0.5
@export var popup_offset: Vector2 = Vector2(18.0, 18.0)

@onready var camera: Camera3D = get_node(camera_path)
@onready var map_grid: MapGrid = get_node(grid_path)
@onready var popup_label: Label = get_node(popup_label_path)

var _hovered_building: Node = null
var _hover_time := 0.0


func _ready() -> void:
	popup_label.visible = false


func _process(delta: float) -> void:
	var building := _get_building_on_hovered_cell()
	if building != _hovered_building:
		_hovered_building = building
		_hover_time = 0.0
		popup_label.visible = false

	if _hovered_building == null:
		return

	_hover_time += delta
	if _hover_time >= hover_delay_seconds:
		_show_popup(_hovered_building)


func _get_building_on_hovered_cell() -> Node:
	var ground_point := _get_mouse_world_point()
	var hovered_cell := map_grid.world_to_cell(ground_point)
	if not map_grid.is_cell_in_bounds(hovered_cell):
		return null

	var occupant: Variant = map_grid.get_occupant(hovered_cell)
	if occupant != null and occupant is Node and occupant.has_meta("building_name"):
		return occupant

	return null


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


func _show_popup(building: Node) -> void:
	popup_label.text = String(building.get_meta("building_name"))
	popup_label.visible = true

	var viewport_size := get_viewport().get_visible_rect().size
	var label_size := popup_label.get_combined_minimum_size()
	var desired_position := get_viewport().get_mouse_position() + popup_offset
	popup_label.position = Vector2(
		clampf(desired_position.x, 0.0, maxf(0.0, viewport_size.x - label_size.x)),
		clampf(desired_position.y, 0.0, maxf(0.0, viewport_size.y - label_size.y))
	)
