class_name BuildingActionSystem
extends Node

const MAP_GEOMETRY_TAG_SPAWNER := "spawner"
const MAP_GEOMETRY_TAG_END_POINT := "end_point"
const DEFAULT_SPAWN_INTERVAL := 5.0
const DEFAULT_EXIT_INTERVAL := 0.1
const DEFAULT_ENEMY_DATA_PATH := "res://data/enemies/grunt.json"
const DEFAULT_ENEMY_ID := "grunt"

@export var grid_path: NodePath
@export var enemies_root_path: NodePath

@onready var map_grid: MapGrid = get_node(grid_path)
@onready var enemies_root: Node3D = get_node(enemies_root_path)

var _passive_timers: Dictionary = {}


func _process(delta: float) -> void:
	for spawner in get_tree().get_nodes_in_group("rts_map_geometry_tag_%s" % MAP_GEOMETRY_TAG_SPAWNER):
		if spawner is Node3D:
			_tick_spawner_geometry(spawner, delta)

	for end_point in get_tree().get_nodes_in_group("rts_map_geometry_tag_%s" % MAP_GEOMETRY_TAG_END_POINT):
		if end_point is Node3D:
			_tick_end_point_geometry(end_point, delta)

	_cleanup_timers()


func _get_south_spawn_cell(building: Node) -> Vector2i:
	if not building.has_meta("grid_anchor_cell") or not building.has_meta("grid_footprint"):
		return Vector2i(-1, -1)

	var anchor_cell: Vector2i = building.get_meta("grid_anchor_cell")
	var footprint: Vector2i = building.get_meta("grid_footprint")
	var south_y := anchor_cell.y + footprint.y
	var center_x := anchor_cell.x + floori(float(footprint.x) * 0.5)
	var preferred_cell := Vector2i(center_x, south_y)
	if map_grid.is_cell_walkable(preferred_cell):
		return preferred_cell

	for x in range(anchor_cell.x, anchor_cell.x + footprint.x):
		var candidate_cell := Vector2i(x, south_y)
		if map_grid.is_cell_walkable(candidate_cell):
			return candidate_cell

	return Vector2i(-1, -1)


func _exit_enemies_inside_building(building: Node) -> void:
	if not (building is Node3D):
		return

	for enemy in get_tree().get_nodes_in_group("rts_enemies"):
		if not (enemy is RtsEnemy) or not is_instance_valid(enemy):
			continue

		if _is_enemy_inside_exit_area(building, enemy):
			enemy.queue_free()


func _tick_end_point_geometry(end_point: Node3D, delta: float) -> void:
	var timer_key := "%d:map_geometry_exit" % end_point.get_instance_id()
	var remaining_time := float(_passive_timers.get(timer_key, DEFAULT_EXIT_INTERVAL))
	remaining_time -= delta
	if remaining_time > 0.0:
		_passive_timers[timer_key] = remaining_time
		return

	_passive_timers[timer_key] = DEFAULT_EXIT_INTERVAL
	_exit_enemies_inside_building(end_point)


func _tick_spawner_geometry(spawner: Node3D, delta: float) -> void:
	var metadata: Dictionary = spawner.get_meta("geometry_metadata", {})
	var interval := float(metadata.get("spawn_interval", DEFAULT_SPAWN_INTERVAL))
	var timer_key := "%d:map_geometry_spawn" % spawner.get_instance_id()
	var remaining_time := float(_passive_timers.get(timer_key, interval))
	remaining_time -= delta
	if remaining_time > 0.0:
		_passive_timers[timer_key] = remaining_time
		return

	_passive_timers[timer_key] = interval
	_create_enemy_from_geometry(spawner, metadata)


func _create_enemy_from_geometry(spawner: Node3D, metadata: Dictionary) -> void:
	var spawn_cell := _get_south_spawn_cell(spawner)
	if not map_grid.is_cell_in_bounds(spawn_cell):
		return

	var enemy_id := String(metadata.get("enemy_id", DEFAULT_ENEMY_ID))
	var enemy := RtsEnemy.new()
	enemy.name = enemy_id.to_pascal_case()
	enemy.grid_path = NodePath("../../Grid")
	enemy.enemy_id = enemy_id
	enemy.enemy_data_path = String(metadata.get("enemy_data_path", DEFAULT_ENEMY_DATA_PATH))
	enemy.position = map_grid.cell_to_world(spawn_cell, 0.0)
	enemies_root.add_child(enemy)


func _is_enemy_inside_exit_area(building: Node3D, enemy: RtsEnemy) -> bool:
	if building.has_meta("grid_anchor_cell") and building.has_meta("grid_footprint"):
		var anchor_cell: Vector2i = building.get_meta("grid_anchor_cell")
		var footprint: Vector2i = building.get_meta("grid_footprint")
		var enemy_cell := enemy.get_current_cell()
		return enemy_cell.x >= anchor_cell.x \
			and enemy_cell.y >= anchor_cell.y \
			and enemy_cell.x < anchor_cell.x + footprint.x \
			and enemy_cell.y < anchor_cell.y + footprint.y

	if not building.has_meta("building_size"):
		return false

	var building_size: Vector3 = building.get_meta("building_size")
	var half_extents := building_size * 0.5
	var local_position := building.to_local(enemy.global_position)
	return absf(local_position.x) <= half_extents.x \
		and absf(local_position.z) <= half_extents.z


func _cleanup_timers() -> void:
	for timer_key in _passive_timers.keys():
		var instance_id := int(String(timer_key).split(":", false, 1)[0])
		if not is_instance_id_valid(instance_id):
			_passive_timers.erase(timer_key)
