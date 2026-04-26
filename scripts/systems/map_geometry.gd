class_name MapGeometry
extends Node3D

const TAG_SPAWNER := "spawner"
const TAG_END_POINT := "end_point"
const TAG_COLOR_SPAWNER := Color(0.44, 0.12, 0.72, 0.72)
const TAG_COLOR_END_POINT := Color(0.08, 0.86, 0.58, 0.72)

@export var grid_path: NodePath
@export var geometry_id := ""
@export var display_name := "Map Geometry"
@export var shape := "box"
@export var tags: PackedStringArray = []
@export var metadata: Dictionary = {}
@export var anchor_cell := Vector2i.ZERO
@export var footprint := Vector2i(1, 1)
@export var pathable := false
@export var size := Vector3(2.0, 0.5, 2.0)
@export var color := Color(0.42, 0.52, 0.62, 0.55)
@export var rotation_steps := 0
@export var base_height := 0.0
@export var registers_grid_occupancy := true

@onready var map_grid: MapGrid = get_node(grid_path)

var _registered_with_grid := false
var _registered_with_geometry_grid := false
var _visual_material: StandardMaterial3D
var _registered_tag_groups: Array[String] = []


func _ready() -> void:
	_register_metadata()
	_create_placeholder_visual()
	_snap_to_grid()
	_register_map_geometry_grid()
	_register_grid_occupancy()
	_refresh_grid_occupancy()


func _exit_tree() -> void:
	if _registered_with_geometry_grid and is_instance_valid(map_grid):
		map_grid.unregister_map_geometry(self, anchor_cell, footprint)

	if _registered_with_grid and is_instance_valid(map_grid):
		map_grid.release(anchor_cell, footprint)


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func add_tag(tag: String) -> void:
	if not tags.has(tag):
		tags.append(tag)
	_apply_tags()


func remove_tag(tag: String) -> void:
	var tag_index := tags.find(tag)
	if tag_index >= 0:
		tags.remove_at(tag_index)
	_apply_tags()


func clear_tags() -> void:
	if tags.is_empty():
		return

	tags.clear()
	_apply_tags()


func set_tags(new_tags: PackedStringArray) -> void:
	tags.clear()
	for tag in new_tags:
		if not tags.has(tag):
			tags.append(tag)
	_apply_tags()


func _register_metadata() -> void:
	add_to_group("rts_map_geometry")

	set_meta("geometry_id", geometry_id)
	set_meta("geometry_name", display_name)
	set_meta("geometry_shape", shape)
	set_meta("geometry_rotation_steps", _get_normalized_rotation_steps())
	set_meta("geometry_metadata", metadata)
	set_meta("grid_anchor_cell", anchor_cell)
	set_meta("grid_footprint", footprint)
	set_meta("pathable", pathable)
	set_meta("geometry_size", size)
	set_meta("geometry_base_height", base_height)
	set_meta("registers_grid_occupancy", registers_grid_occupancy)
	_apply_tags()


func _create_placeholder_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PlaceholderVisual"
	_visual_material = _create_material()
	mesh_instance.mesh = _create_visual_mesh()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if color.a < 1.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)
	_apply_visual_color()


func _snap_to_grid() -> void:
	position = map_grid.footprint_to_world_center(anchor_cell, footprint, base_height + (size.y * 0.5))
	rotation_degrees.y = float(_get_normalized_rotation_steps()) * 90.0


func _register_grid_occupancy() -> void:
	if not registers_grid_occupancy:
		return

	if not map_grid.is_footprint_in_bounds(anchor_cell, footprint):
		push_warning("Map geometry '%s' has an out-of-bounds footprint at %s." % [display_name, anchor_cell])
		return

	if not map_grid.occupy(anchor_cell, footprint, self, not _is_runtime_pathable()):
		push_warning("Map geometry '%s' could not register grid occupancy at %s." % [display_name, anchor_cell])
		return

	_registered_with_grid = true


func _register_map_geometry_grid() -> void:
	if not map_grid.is_footprint_in_bounds(anchor_cell, footprint):
		return

	map_grid.register_map_geometry(self, anchor_cell, footprint)
	_registered_with_geometry_grid = true


func _create_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
	material.albedo_color = color
	material.roughness = 0.75
	return material


func _create_visual_mesh() -> Mesh:
	if shape == "ramp":
		return _create_ramp_mesh()

	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _visual_material
	return box_mesh


func _create_ramp_mesh() -> ArrayMesh:
	var half_x := size.x * 0.5
	var half_y := size.y * 0.5
	var half_z := size.z * 0.5
	var mesh := ArrayMesh.new()
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
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _visual_material)
	return mesh


func _apply_tags() -> void:
	for group_name in _registered_tag_groups:
		remove_from_group(group_name)
	_registered_tag_groups.clear()

	for tag in tags:
		var group_name := "rts_map_geometry_tag_%s" % String(tag)
		add_to_group(group_name)
		_registered_tag_groups.append(group_name)

	set_meta("geometry_tags", tags)
	set_meta("pathable", _is_runtime_pathable())
	if is_node_ready() and is_instance_valid(map_grid):
		map_grid.notify_pathing_changed()
	_apply_visual_color()
	_refresh_grid_occupancy()


func _apply_visual_color() -> void:
	var display_color := _get_display_color()
	set_meta("geometry_color", display_color)
	if _visual_material != null:
		if display_color.a < 1.0:
			_visual_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_visual_material.no_depth_test = true
		_visual_material.albedo_color = display_color


func _get_display_color() -> Color:
	if tags.has(TAG_END_POINT):
		return TAG_COLOR_END_POINT

	if tags.has(TAG_SPAWNER):
		return TAG_COLOR_SPAWNER

	return color


func _get_normalized_rotation_steps() -> int:
	return posmod(rotation_steps, 4)


func _is_runtime_pathable() -> bool:
	return pathable or tags.has(TAG_END_POINT)


func _refresh_grid_occupancy() -> void:
	if not registers_grid_occupancy or not is_node_ready() or not is_instance_valid(map_grid):
		return

	if _registered_with_grid:
		map_grid.release(anchor_cell, footprint)
		_registered_with_grid = false

	_register_grid_occupancy()
