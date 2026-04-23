class_name RtsEnemy
extends CharacterBody3D

enum EnemyState {
	IDLE,
	MOVING_TO_GOAL,
	REACHED_GOAL
}

const COLLISION_LAYER_WORLD := 1 << 0
const COLLISION_LAYER_BLOCKS_ENEMIES := 1 << 2
const ACTION_EXIT_ENEMY := "exit_enemy"

@export var grid_path: NodePath
@export var enemy_id := "grunt"
@export var enemy_data_path := "res://data/enemies/grunt.json"
@export var enemy_name := "Enemy"
@export var move_speed := 7.0
@export var body_color: Color = Color(0.75, 0.18, 0.18, 1.0)
@export var marker_color: Color = Color(0.12, 0.02, 0.02, 1.0)
@export var arrival_distance := 0.2
@export var max_health := 100
@export var damage := 5
@export var armor := 0
@export var attack_range := 1.0
@export var attack_cooldown := 1.5
@export var collision_radius := 0.45
@export var collision_height := 1.7
@export var portrait_camera_offset: Vector3 = Vector3(0.0, 1.45, 4.0)
@export var portrait_camera_target: Vector3 = Vector3(0.0, 0.8, 0.0)
@export var portrait_camera_fov := 36.0
@export var ai_poll_interval := 0.5

@onready var map_grid: MapGrid = get_node(grid_path)

var current_health := 100
var bounty: Dictionary = {}
var ai_profile: Dictionary = {}
var _path: Array[Vector3] = []
var _cell_path: Array[Vector2i] = []
var _path_index := 0
var _target_cell := Vector2i.ZERO
var _target_world_position := Vector3.ZERO
var _state := EnemyState.IDLE
var _goal_building: Node = null
var _ai_poll_timer := 0.0


func _ready() -> void:
	_apply_enemy_data()
	collision_mask = COLLISION_LAYER_WORLD | COLLISION_LAYER_BLOCKS_ENEMIES
	add_to_group("rts_enemies")
	set_meta("enemy_id", enemy_id)
	set_meta("enemy_name", enemy_name)
	set_meta("max_health", max_health)
	set_meta("damage", damage)
	set_meta("armor", armor)
	set_meta("attack_range", attack_range)
	set_meta("attack_cooldown", attack_cooldown)
	set_meta("portrait_camera_offset", portrait_camera_offset)
	set_meta("portrait_camera_target", portrait_camera_target)
	set_meta("portrait_camera_fov", portrait_camera_fov)
	current_health = max_health
	_create_visuals()


func _physics_process(delta: float) -> void:
	_update_default_ai(delta)
	if _state == EnemyState.MOVING_TO_GOAL:
		_follow_path(delta)


func issue_goal_order(target_world_position: Vector3) -> bool:
	_goal_building = null
	_target_world_position = _with_enemy_height(target_world_position)
	_target_cell = map_grid.world_to_cell(_target_world_position)
	_rebuild_path_to_target()
	if _path.is_empty():
		_state = EnemyState.IDLE
		return false

	_state = EnemyState.MOVING_TO_GOAL
	return true


func clear_goal_order() -> void:
	_goal_building = null
	_path.clear()
	_cell_path.clear()
	_path_index = 0
	velocity = Vector3.ZERO
	_state = EnemyState.IDLE


func get_current_cell() -> Vector2i:
	return map_grid.world_to_cell(global_position)


func get_state() -> int:
	return _state


func _apply_enemy_data() -> void:
	var definition := GameData.load_enemy_definition(enemy_data_path)
	if definition.is_empty():
		return

	enemy_id = String(definition.get("id", enemy_id))
	enemy_name = String(definition.get("name", enemy_name))
	body_color = definition.get("body_color", body_color)
	marker_color = definition.get("marker_color", marker_color)
	bounty = definition.get("bounty", bounty)
	ai_profile = definition.get("ai", ai_profile)

	var movement: Dictionary = definition.get("movement", {})
	move_speed = float(movement.get("move_speed", move_speed))
	arrival_distance = float(movement.get("arrival_distance", arrival_distance))

	var stats: Dictionary = definition.get("stats", {})
	max_health = int(stats.get("max_health", max_health))
	damage = int(stats.get("damage", damage))
	armor = int(stats.get("armor", armor))
	attack_range = float(stats.get("attack_range", attack_range))
	attack_cooldown = float(stats.get("attack_cooldown", attack_cooldown))

	var collision: Dictionary = definition.get("collision", {})
	collision_radius = float(collision.get("radius", collision_radius))
	collision_height = float(collision.get("height", collision_height))

	var portrait_camera: Dictionary = definition.get("portrait_camera", {})
	portrait_camera_offset = portrait_camera.get("offset", portrait_camera_offset)
	portrait_camera_target = portrait_camera.get("target", portrait_camera_target)
	portrait_camera_fov = float(portrait_camera.get("fov", portrait_camera_fov))

	var ai: Dictionary = definition.get("ai", {})
	ai_poll_interval = float(ai.get("poll_interval", ai_poll_interval))


func _update_default_ai(delta: float) -> void:
	if not _should_path_to_exit():
		return

	_ai_poll_timer -= delta
	if _state == EnemyState.MOVING_TO_GOAL and _is_goal_building_valid():
		return

	if _state == EnemyState.MOVING_TO_GOAL and not _is_goal_building_valid():
		clear_goal_order()

	if _ai_poll_timer > 0.0:
		return

	_ai_poll_timer = ai_poll_interval
	_try_path_to_exit_point()


func _should_path_to_exit() -> bool:
	return String(ai_profile.get("role", "path_to_exit")) == "path_to_exit"


func _try_path_to_exit_point() -> void:
	var exit_point := _find_exit_point()
	if exit_point == null:
		if _state == EnemyState.MOVING_TO_GOAL:
			clear_goal_order()
		return

	var goal_position_result := _get_goal_position_for_building(exit_point)
	if goal_position_result.is_empty():
		return

	_goal_building = exit_point
	_target_world_position = _with_enemy_height(goal_position_result["position"])
	_target_cell = map_grid.world_to_cell(_target_world_position)
	_rebuild_path_to_target()
	if _path.is_empty():
		_state = EnemyState.IDLE
		return

	_state = EnemyState.MOVING_TO_GOAL


func _find_exit_point() -> Node:
	var target_building_id := String(ai_profile.get("target", "exit_point"))
	for building in get_tree().get_nodes_in_group("rts_buildings"):
		if building is Node and building.has_meta("building_id") and String(building.get_meta("building_id")) == target_building_id:
			return building

	return null


func _is_goal_building_valid() -> bool:
	return _goal_building != null and is_instance_valid(_goal_building) and _goal_building.is_inside_tree()


func _get_goal_position_for_building(building: Node) -> Dictionary:
	if not building.has_meta("grid_anchor_cell") or not building.has_meta("grid_footprint"):
		return {}

	var anchor_cell: Vector2i = building.get_meta("grid_anchor_cell")
	var footprint: Vector2i = building.get_meta("grid_footprint")
	if bool(building.get_meta("pathable", false)):
		return _get_goal_position_inside_building(anchor_cell, footprint)

	return _get_goal_position_near_building(anchor_cell, footprint)


func _get_goal_position_inside_building(anchor_cell: Vector2i, footprint: Vector2i) -> Dictionary:
	var current_cell := get_current_cell()
	var best_cell := Vector2i(-1, -1)
	var best_path_length := INF
	for candidate_cell in map_grid.get_footprint_cells(anchor_cell, footprint):
		if not _is_enemy_cell_walkable(candidate_cell):
			continue

		var candidate_path := map_grid.find_path_with_filter(current_cell, candidate_cell, _is_enemy_cell_walkable)
		if candidate_path.is_empty() and current_cell != candidate_cell:
			continue

		var path_length := float(candidate_path.size())
		if path_length < best_path_length:
			best_path_length = path_length
			best_cell = candidate_cell

	if not map_grid.is_cell_in_bounds(best_cell):
		return {}

	return {
		"position": map_grid.cell_to_world(best_cell, global_position.y)
	}


func _get_goal_position_near_building(anchor_cell: Vector2i, footprint: Vector2i) -> Dictionary:
	var current_cell := get_current_cell()
	var best_cell := Vector2i(-1, -1)
	var best_path_length := INF
	for candidate_cell in _get_neighboring_cells(anchor_cell, footprint):
		if not _is_enemy_cell_walkable(candidate_cell):
			continue

		var candidate_path := map_grid.find_path_with_filter(current_cell, candidate_cell, _is_enemy_cell_walkable)
		if candidate_path.is_empty() and current_cell != candidate_cell:
			continue

		var path_length := float(candidate_path.size())
		if path_length < best_path_length:
			best_path_length = path_length
			best_cell = candidate_cell

	if not map_grid.is_cell_in_bounds(best_cell):
		return {}

	return {
		"position": map_grid.cell_to_world(best_cell, global_position.y)
	}


func _get_neighboring_cells(anchor_cell: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var candidate_cells: Array[Vector2i] = []
	for x in range(anchor_cell.x, anchor_cell.x + footprint.x):
		candidate_cells.append(Vector2i(x, anchor_cell.y - 1))
		candidate_cells.append(Vector2i(x, anchor_cell.y + footprint.y))

	for y in range(anchor_cell.y, anchor_cell.y + footprint.y):
		candidate_cells.append(Vector2i(anchor_cell.x - 1, y))
		candidate_cells.append(Vector2i(anchor_cell.x + footprint.x, y))

	return candidate_cells


func _rebuild_path_to_target() -> void:
	var start_cell := get_current_cell()
	_cell_path = map_grid.find_path_with_filter(start_cell, _target_cell, _is_enemy_cell_walkable)
	_path.clear()
	_path_index = 0

	if start_cell == _target_cell:
		_path.append(_target_world_position)
		return

	if _cell_path.is_empty():
		return

	var raw_path: Array[Vector3] = []
	for index in range(_cell_path.size()):
		var cell := _cell_path[index]
		if index == _cell_path.size() - 1:
			raw_path.append(_target_world_position)
		else:
			raw_path.append(map_grid.cell_to_world(cell, global_position.y))

	_path = _smooth_path(raw_path)


func _follow_path(delta: float) -> void:
	if _path_index >= _path.size():
		_complete_goal_order()
		return

	if _is_current_waypoint_blocked():
		_rebuild_path_to_target()
		if _path_index >= _path.size():
			_state = EnemyState.IDLE
			return

	var target := _path[_path_index]
	var previous_position := global_position
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() > arrival_distance:
		velocity = to_target.normalized() * move_speed
		move_and_slide()
	else:
		velocity = Vector3.ZERO

	var travel_direction := global_position - previous_position
	if travel_direction.length_squared() > 0.0001:
		look_at(global_position + travel_direction.normalized(), Vector3.UP)

	if Vector2(global_position.x, global_position.z).distance_to(Vector2(target.x, target.z)) <= arrival_distance:
		_path_index += 1


func _complete_goal_order() -> void:
	velocity = Vector3.ZERO
	_state = EnemyState.REACHED_GOAL


func _is_current_waypoint_blocked() -> bool:
	if _path_index >= _path.size():
		return false

	return not _is_enemy_cell_walkable(map_grid.world_to_cell(_path[_path_index]))


func _is_enemy_cell_walkable(cell: Vector2i) -> bool:
	if not map_grid.is_cell_in_bounds(cell):
		return false

	var occupant: Variant = map_grid.get_occupant(cell)
	if occupant == null:
		return map_grid.is_cell_walkable(cell)

	if occupant is Node and _building_has_exit_command(occupant):
		return true

	return false


func _building_has_exit_command(building: Node) -> bool:
	for command in building.get_meta("commands", []):
		if command is Dictionary and String(command.get("action", "")) == ACTION_EXIT_ENEMY:
			return true

	return false


func _smooth_path(raw_path: Array[Vector3]) -> Array[Vector3]:
	if raw_path.size() <= 2:
		return raw_path

	var smoothed_path: Array[Vector3] = []
	var anchor_position := global_position
	var index := 0
	while index < raw_path.size():
		var farthest_reachable_index := index
		for candidate_index in range(raw_path.size() - 1, index - 1, -1):
			if map_grid.is_world_segment_walkable_with_filter(anchor_position, raw_path[candidate_index], _is_enemy_cell_walkable):
				farthest_reachable_index = candidate_index
				break

		var waypoint := raw_path[farthest_reachable_index]
		smoothed_path.append(waypoint)
		anchor_position = waypoint
		index = farthest_reachable_index + 1

	return smoothed_path


func _with_enemy_height(world_position: Vector3) -> Vector3:
	return Vector3(world_position.x, global_position.y, world_position.z)


func _create_visuals() -> void:
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = collision_radius
	capsule_shape.height = collision_height
	collision_shape.shape = capsule_shape
	collision_shape.position.y = collision_height * 0.5
	add_child(collision_shape)

	var body_mesh_instance := MeshInstance3D.new()
	body_mesh_instance.name = "Body"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = collision_radius + 0.08
	capsule_mesh.height = collision_height
	capsule_mesh.material = _create_material(body_color)
	body_mesh_instance.mesh = capsule_mesh
	body_mesh_instance.position.y = collision_height * 0.5
	add_child(body_mesh_instance)

	var facing_marker := MeshInstance3D.new()
	facing_marker.name = "FacingMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(collision_radius * 0.55, 0.18, collision_radius * 1.15)
	marker_mesh.material = _create_material(marker_color)
	facing_marker.mesh = marker_mesh
	facing_marker.position = Vector3(0.0, collision_height * 0.62, -collision_radius * 0.95)
	add_child(facing_marker)


func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	return material
