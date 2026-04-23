class_name BuildingActionSystem
extends Node

const ACTION_SPAWN_ENEMY := "spawn_enemy"
const ACTION_EXIT_ENEMY := "exit_enemy"
const DEFAULT_SPAWN_INTERVAL := 5.0
const DEFAULT_EXIT_INTERVAL := 0.1
const DEFAULT_ENEMY_DATA_PATH := "res://data/enemies/grunt.json"

@export var grid_path: NodePath
@export var enemies_root_path: NodePath

@onready var map_grid: MapGrid = get_node(grid_path)
@onready var enemies_root: Node3D = get_node(enemies_root_path)

var _passive_timers: Dictionary = {}


func _process(delta: float) -> void:
	for building in get_tree().get_nodes_in_group("rts_buildings"):
		if not (building is Node):
			continue

		for command in _get_building_commands(building):
			if not bool(command.get("passive", false)):
				continue

			_tick_passive_command(building, command, delta)

	_cleanup_timers()


func _get_building_commands(building: Node) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	for command in building.get_meta("commands", []):
		if command is Dictionary:
			commands.append(command)

	return commands


func _tick_passive_command(building: Node, command: Dictionary, delta: float) -> void:
	var timer_key := _get_timer_key(building, command)
	var remaining_time := float(_passive_timers.get(timer_key, _get_default_interval(command)))
	remaining_time -= delta
	if remaining_time > 0.0:
		_passive_timers[timer_key] = remaining_time
		return

	_passive_timers[timer_key] = float(command.get("interval", _get_default_interval(command)))
	match String(command.get("action", "")):
		ACTION_SPAWN_ENEMY:
			_spawn_enemy_from_building(building, command)
		ACTION_EXIT_ENEMY:
			_exit_enemies_inside_building(building)


func _get_default_interval(command: Dictionary) -> float:
	if String(command.get("action", "")) == ACTION_EXIT_ENEMY:
		return DEFAULT_EXIT_INTERVAL

	return DEFAULT_SPAWN_INTERVAL


func _spawn_enemy_from_building(building: Node, command: Dictionary) -> void:
	var spawn_cell := _get_south_spawn_cell(building)
	if not map_grid.is_cell_in_bounds(spawn_cell):
		return

	var enemy := RtsEnemy.new()
	enemy.name = String(command.get("enemy_id", "grunt")).to_pascal_case()
	enemy.grid_path = NodePath("../../Grid")
	enemy.enemy_id = String(command.get("enemy_id", "grunt"))
	enemy.enemy_data_path = String(command.get("enemy_data_path", DEFAULT_ENEMY_DATA_PATH))
	enemies_root.add_child(enemy)
	enemy.global_position = map_grid.cell_to_world(spawn_cell, 0.0)


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
	if not building.has_meta("building_size"):
		return

	var building_size: Vector3 = building.get_meta("building_size")
	var half_extents := building_size * 0.5
	for enemy in get_tree().get_nodes_in_group("rts_enemies"):
		if not (enemy is RtsEnemy) or not is_instance_valid(enemy):
			continue

		var local_position := (building as Node3D).to_local(enemy.global_position)
		if absf(local_position.x) <= half_extents.x \
			and absf(local_position.z) <= half_extents.z \
			and local_position.y >= -half_extents.y \
			and local_position.y <= half_extents.y:
			enemy.queue_free()


func _get_timer_key(building: Node, command: Dictionary) -> String:
	return "%d:%s" % [building.get_instance_id(), String(command.get("id", ""))]


func _cleanup_timers() -> void:
	for timer_key in _passive_timers.keys():
		var instance_id := int(String(timer_key).split(":", false, 1)[0])
		if not is_instance_id_valid(instance_id):
			_passive_timers.erase(timer_key)
