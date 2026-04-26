class_name RtsEnemy
extends CharacterBody3D

enum EnemyState {
	IDLE,
	MOVING_TO_GOAL,
	REACHED_GOAL
}

const COLLISION_LAYER_WORLD := 1 << 0
const COLLISION_LAYER_BLOCKS_ENEMIES := 1 << 2
const MAP_GEOMETRY_TAG_END_POINT := "end_point"
const CombatUtilsRef = preload("res://scripts/systems/combat_utils.gd")
const MOVEMENT_TYPE_GROUND := "ground"
const MOVEMENT_TYPE_FLYING := "flying"
const FLIGHT_SHADOW_HEIGHT := 0.045
const FLIGHT_SHADOW_ALPHA := 0.36
const DAMAGE_ROLLING_WINDOW_SECONDS := 10.0
const DEBUG_PATH_LINE_HEIGHT_OFFSET := 0.14
const DEFAULT_TURN_ALIGNMENT_DEGREES := 11.5
const DEFAULT_TURN_ACCELERATION_TIME := 0.03

@export var grid_path: NodePath
@export var enemy_id := "grunt"
@export var enemy_data_path := "res://data/enemies/grunt.json"
@export var enemy_name := "Enemy"
@export var movement_type := MOVEMENT_TYPE_GROUND
@export var move_speed := 7.0
@export var turn_speed := 1080.0
@export var turn_alignment_degrees := DEFAULT_TURN_ALIGNMENT_DEGREES
@export var turn_acceleration_time := DEFAULT_TURN_ACCELERATION_TIME
@export var body_color: Color = Color(0.75, 0.18, 0.18, 1.0)
@export var marker_color: Color = Color(0.12, 0.02, 0.02, 1.0)
@export var arrival_distance := 0.2
@export var max_health := 100
@export var health_regen_per_second := 0.0
@export var damage := 5
@export var armor := 0
@export var attack_type := "melee"
@export var attack_speed := 1.0
@export var attack_range := 1.0
@export var attack_cooldown := 1.5
@export var projectile_id := ""
@export var collision_radius := 0.45
@export var collision_height := 1.7
@export var flight_height := 3.0
@export var portrait_camera_offset: Vector3 = Vector3(0.0, 1.45, 4.0)
@export var portrait_camera_target: Vector3 = Vector3(0.0, 0.8, 0.0)
@export var portrait_camera_fov := 36.0
@export var ai_poll_interval := 0.5
@export var death_sound_path := ""
@export var show_damage_debug := false
@export var damage_debug_font_size := 72
@export var damage_debug_height_offset := 1.05
@export var damage_debug_outline_size := 12
@export var show_path_debug := true

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
var _attack_target_building: Node3D = null
var _ai_poll_timer := 0.0
var _attack_cooldown_remaining := 0.0
var _attack_reroute_timer := 0.0
var _is_dying := false
var _flight_shadow: MeshInstance3D = null
var _health_regen_remainder := 0.0
var _damage_events: Array[Dictionary] = []
var _last_damage_taken := 0
var _damage_debug_label: Label3D = null
var _pathing_system: Node = null
var _debug_path_line: MeshInstance3D = null
var _current_turn_speed := 0.0
var _last_turn_sign := 0.0


func _ready() -> void:
	_apply_enemy_data()
	_pathing_system = _find_pathing_system()
	_ai_poll_timer = randf() * ai_poll_interval
	collision_mask = _get_collision_mask_for_movement_type()
	add_to_group("rts_enemies")
	if is_flying():
		global_position.y = flight_height
	current_health = -1 if max_health < 0 else max_health
	set_meta("enemy_id", enemy_id)
	set_meta("enemy_name", enemy_name)
	set_meta("movement_type", movement_type)
	set_meta("turn_speed", turn_speed)
	set_meta("turn_alignment_degrees", turn_alignment_degrees)
	set_meta("turn_acceleration_time", turn_acceleration_time)
	set_meta("stats", _get_runtime_stats())
	set_meta("max_health", max_health)
	set_meta("current_health", current_health)
	set_meta("health_regen_per_second", health_regen_per_second)
	set_meta("damage", damage)
	set_meta("armor", armor)
	set_meta("attack_type", attack_type)
	set_meta("attack_speed", attack_speed)
	set_meta("attack_range", attack_range)
	set_meta("attack_cooldown", attack_cooldown)
	set_meta("projectile_id", projectile_id)
	set_meta("death_sound_path", death_sound_path)
	set_meta("portrait_camera_offset", portrait_camera_offset)
	set_meta("portrait_camera_target", portrait_camera_target)
	set_meta("portrait_camera_fov", portrait_camera_fov)
	_create_visuals()
	_create_flight_shadow()
	_create_damage_debug_label()
	_create_debug_path_line()


func _physics_process(delta: float) -> void:
	_update_flight_shadow()
	_update_health_regeneration(delta)
	_update_damage_debug_display(delta)
	_update_default_ai(delta)
	_update_attack_cooldown(delta)
	_update_attack_reroute_timer(delta)
	if _try_attack_building_in_range():
		return

	if _state == EnemyState.MOVING_TO_GOAL:
		_follow_path(delta)


func issue_goal_order(target_world_position: Vector3) -> bool:
	_goal_building = null
	_attack_target_building = null
	_target_world_position = _with_enemy_height(target_world_position)
	_target_cell = map_grid.world_to_cell(_target_world_position)
	_rebuild_path_to_target()
	if _path.is_empty():
		_state = EnemyState.IDLE
		_refresh_debug_path_line()
		return false

	_state = EnemyState.MOVING_TO_GOAL
	_refresh_debug_path_line()
	return true


func clear_goal_order() -> void:
	_goal_building = null
	_attack_target_building = null
	_path.clear()
	_cell_path.clear()
	_path_index = 0
	velocity = Vector3.ZERO
	_state = EnemyState.IDLE
	_refresh_debug_path_line()


func get_current_cell() -> Vector2i:
	return map_grid.world_to_cell(global_position)


func get_state() -> int:
	return _state


func get_health() -> int:
	return current_health


func get_max_health() -> int:
	return max_health


func set_health(new_health: int) -> void:
	var previous_health := current_health
	current_health = -1 if max_health < 0 else clampi(new_health, 0, max_health)
	_sync_runtime_stats_meta()
	if previous_health > 0 and current_health <= 0:
		_die()


func get_attack_range() -> float:
	return attack_range


func can_attack_target(target: Node) -> bool:
	return CombatUtilsRef.is_target_valid(self, target)


func is_target_in_attack_range(target: Node3D) -> bool:
	return CombatUtilsRef.is_target_in_attack_range(self, target)


func get_distance_to_attack_target(target: Node3D) -> float:
	return CombatUtilsRef.get_horizontal_distance_to_target(self, target)


func try_melee_attack(target: Node3D) -> Dictionary:
	return CombatUtilsRef.perform_melee_attack(self, target)


func record_damage_taken(amount: int) -> void:
	var applied_damage := maxi(amount, 0)
	if applied_damage <= 0:
		return

	_last_damage_taken = applied_damage
	_damage_events.append({
		"damage": applied_damage,
		"age": 0.0
	})
	_update_damage_debug_label_text()


func is_flying() -> bool:
	return movement_type == MOVEMENT_TYPE_FLYING


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
	movement_type = String(movement.get("type", movement_type))
	move_speed = float(movement.get("move_speed", move_speed))
	turn_speed = float(movement.get("turn_speed", turn_speed))
	turn_alignment_degrees = float(movement.get("turn_alignment_degrees", turn_alignment_degrees))
	turn_acceleration_time = float(movement.get("turn_acceleration_time", turn_acceleration_time))
	arrival_distance = float(movement.get("arrival_distance", arrival_distance))
	flight_height = float(movement.get("flight_height", flight_height))

	var stats: Dictionary = definition.get("stats", {})
	max_health = int(stats.get("max_health", max_health))
	health_regen_per_second = maxf(float(stats.get("health_regen_per_second", health_regen_per_second)), 0.0)
	damage = int(stats.get("damage", damage))
	armor = int(stats.get("armor", armor))
	attack_type = String(stats.get("attack_type", attack_type))
	attack_speed = float(stats.get("attack_speed", attack_speed))
	attack_range = float(stats.get("attack_range", attack_range))
	attack_cooldown = float(stats.get("attack_cooldown", attack_cooldown))
	projectile_id = String(stats.get("projectile_id", projectile_id))

	var collision: Dictionary = definition.get("collision", {})
	collision_radius = float(collision.get("radius", collision_radius))
	collision_height = float(collision.get("height", collision_height))

	var portrait_camera: Dictionary = definition.get("portrait_camera", {})
	portrait_camera_offset = portrait_camera.get("offset", portrait_camera_offset)
	portrait_camera_target = portrait_camera.get("target", portrait_camera_target)
	portrait_camera_fov = float(portrait_camera.get("fov", portrait_camera_fov))

	var audio: Dictionary = definition.get("audio", {})
	death_sound_path = String(audio.get("death", death_sound_path))

	var debug: Dictionary = definition.get("debug", {})
	show_damage_debug = bool(debug.get("damage_display", show_damage_debug))
	damage_debug_font_size = maxi(int(debug.get("damage_display_font_size", damage_debug_font_size)), 1)
	damage_debug_height_offset = maxf(float(debug.get("damage_display_height_offset", damage_debug_height_offset)), 0.0)
	damage_debug_outline_size = maxi(int(debug.get("damage_display_outline_size", damage_debug_outline_size)), 0)

	var ai: Dictionary = definition.get("ai", {})
	ai_poll_interval = float(ai.get("poll_interval", ai_poll_interval))


func _get_runtime_stats() -> Dictionary:
	return {
		"max_health": max_health,
		"current_health": current_health,
		"health_regen_per_second": health_regen_per_second,
		"damage": damage,
		"armor": armor,
		"attack_type": attack_type,
		"attack_speed": attack_speed,
		"attack_range": attack_range,
		"attack_cooldown": attack_cooldown,
		"projectile_id": projectile_id
	}


func _sync_runtime_stats_meta() -> void:
	set_meta("stats", _get_runtime_stats())
	set_meta("current_health", current_health)
	set_meta("health_regen_per_second", health_regen_per_second)


func _update_health_regeneration(delta: float) -> void:
	if health_regen_per_second <= 0.0 or max_health < 0 or current_health <= 0 or current_health >= max_health:
		return

	_health_regen_remainder += health_regen_per_second * delta
	var regen_amount := floori(_health_regen_remainder)
	if regen_amount <= 0:
		return

	_health_regen_remainder -= float(regen_amount)
	set_health(mini(current_health + regen_amount, max_health))


func _update_damage_debug_display(delta: float) -> void:
	if not show_damage_debug:
		return

	var changed := false
	for event in _damage_events:
		event["age"] = float(event.get("age", 0.0)) + delta

	for index in range(_damage_events.size() - 1, -1, -1):
		if float(_damage_events[index].get("age", 0.0)) > DAMAGE_ROLLING_WINDOW_SECONDS:
			_damage_events.remove_at(index)
			changed = true

	if changed:
		_update_damage_debug_label_text()


func _die() -> void:
	if _is_dying:
		return

	_is_dying = true
	velocity = Vector3.ZERO
	if _debug_path_line != null and is_instance_valid(_debug_path_line):
		_debug_path_line.visible = false
	_play_death_sound()
	queue_free()


func _play_death_sound() -> void:
	if death_sound_path.is_empty():
		return

	var death_sound := GameData.load_audio_stream(death_sound_path)
	if death_sound == null:
		return

	AudioUtils.play_world_sound(self, global_position, death_sound)


func _update_default_ai(delta: float) -> void:
	if not _should_path_to_exit():
		return

	_ai_poll_timer -= delta
	_clear_invalid_cached_targets()
	if _ai_poll_timer > 0.0:
		return

	_ai_poll_timer = ai_poll_interval
	if _state == EnemyState.MOVING_TO_GOAL and not _is_goal_building_valid():
		clear_goal_order()

	var end_point := _find_end_point()
	if end_point == null:
		if _state == EnemyState.MOVING_TO_GOAL:
			clear_goal_order()
		return

	if is_flying():
		_fly_to_end_point(end_point)
		return

	if _state == EnemyState.MOVING_TO_GOAL \
		and _goal_building == end_point \
		and _attack_target_building == null:
		if _is_remaining_path_walkable():
			return

		if _try_path_to_end_point(end_point):
			return

	if _try_path_to_end_point(end_point):
		return

	_try_path_to_blocking_building(end_point)


func _update_attack_cooldown(delta: float) -> void:
	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)


func _update_attack_reroute_timer(delta: float) -> void:
	_attack_reroute_timer = maxf(_attack_reroute_timer - delta, 0.0)


func _try_attack_building_in_range() -> bool:
	if attack_type != "melee":
		return false

	var target_building := _get_active_attack_target()
	if target_building == null:
		return false

	if not is_target_in_attack_range(target_building):
		return false

	if _try_reroute_before_building_attack():
		return false

	_face_attack_target(target_building)
	velocity = Vector3.ZERO
	if _attack_cooldown_remaining > 0.0:
		return true

	var attack_result := try_melee_attack(target_building)
	if bool(attack_result.get("success", false)):
		_attack_cooldown_remaining = attack_cooldown

	return true


func _try_reroute_before_building_attack() -> bool:
	if _attack_reroute_timer > 0.0:
		return false

	_attack_reroute_timer = ai_poll_interval
	var end_point := _find_end_point()
	if end_point == null:
		return false

	if _goal_building == end_point and _is_remaining_path_walkable():
		_attack_target_building = null
		return true

	return _try_path_to_end_point(end_point)


func _update_attack_target() -> void:
	if _attack_target_building != null:
		if _is_attack_target_valid(_attack_target_building):
			return

		_attack_target_building = null

	_attack_target_building = _find_attackable_building_in_range()


func _get_active_attack_target() -> Node3D:
	if _attack_target_building != null and _is_attack_target_valid(_attack_target_building):
		return _attack_target_building

	_attack_target_building = null
	return null


func _is_attack_target_valid(target: Node3D) -> bool:
	return is_instance_valid(target) and can_attack_target(target)


func _clear_invalid_cached_targets() -> void:
	if _goal_building != null and not is_instance_valid(_goal_building):
		_goal_building = null

	if _attack_target_building != null and not is_instance_valid(_attack_target_building):
		_attack_target_building = null


func _should_path_to_exit() -> bool:
	return String(ai_profile.get("role", "path_to_exit")) == "path_to_exit"


func _try_path_to_end_point(end_point: Node = null) -> bool:
	if end_point == null:
		end_point = _find_end_point()

	if end_point == null:
		if _state == EnemyState.MOVING_TO_GOAL:
			clear_goal_order()
		return false

	var exit_path_result := _get_path_result_to_goal_building(end_point)
	if exit_path_result.is_empty():
		return false

	_goal_building = end_point
	_target_world_position = exit_path_result["target_world_position"]
	_target_cell = exit_path_result["target_cell"]
	_cell_path = exit_path_result["cell_path"]
	_path = exit_path_result["path"]
	_path_index = 0
	_attack_target_building = null
	_state = EnemyState.MOVING_TO_GOAL
	_refresh_debug_path_line()
	return true


func _fly_to_end_point(end_point: Node) -> void:
	if not is_instance_valid(end_point) or not (end_point is Node3D):
		clear_goal_order()
		return

	_goal_building = end_point
	_attack_target_building = null
	_target_world_position = _with_enemy_height(_get_building_center_world_position(end_point))
	_target_cell = map_grid.world_to_cell(_target_world_position)
	_path = [_target_world_position]
	_cell_path.clear()
	if map_grid.is_cell_in_bounds(_target_cell):
		_cell_path.append(_target_cell)
	_path_index = 0
	_state = EnemyState.MOVING_TO_GOAL
	_refresh_debug_path_line()


func _try_path_to_blocking_building(goal_building: Node) -> void:
	if not _has_attackable_buildings():
		_attack_target_building = null
		_state = EnemyState.IDLE
		return

	var obstruction_result := _find_blocking_building_to_attack(goal_building)
	if obstruction_result.is_empty():
		_attack_target_building = _find_attackable_building_in_range()
		if _attack_target_building == null:
			_state = EnemyState.IDLE
		return

	_goal_building = obstruction_result["building"]
	_attack_target_building = obstruction_result["building"]
	_target_cell = obstruction_result["cell"]
	_target_world_position = _get_attack_world_position_for_cell(_attack_target_building, _target_cell)
	_rebuild_path_to_target()
	if _path.is_empty():
		if is_target_in_attack_range(_attack_target_building):
			_state = EnemyState.IDLE
		else:
			_attack_target_building = _find_attackable_building_in_range()
			_state = EnemyState.IDLE
		_refresh_debug_path_line()
		return

	_state = EnemyState.MOVING_TO_GOAL
	_refresh_debug_path_line()


func _find_blocking_building_to_attack(goal_building: Node) -> Dictionary:
	if not goal_building.has_meta("grid_anchor_cell") or not goal_building.has_meta("grid_footprint"):
		return {}

	var start_cell := get_current_cell()
	var frontier: Array[Vector2i] = [start_cell]
	var visited: Dictionary = {start_cell: true}
	var best_building: Node3D = null
	var best_attack_cell := Vector2i.ZERO
	var best_goal_distance := INF
	var best_enemy_distance := INF
	var goal_anchor: Vector2i = goal_building.get_meta("grid_anchor_cell")
	var goal_footprint: Vector2i = goal_building.get_meta("grid_footprint")

	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for neighbor in _get_cardinal_neighbor_cells(cell):
			if _can_enemy_traverse_between_cells(cell, neighbor):
				if not visited.has(neighbor):
					visited[neighbor] = true
					frontier.append(neighbor)
				continue

			var occupant: Variant = map_grid.get_occupant(neighbor)
			if not (occupant is Node3D):
				continue

			if not can_attack_target(occupant):
				continue

			var occupant_goal_distance := _get_building_distance_to_goal(occupant, goal_anchor, goal_footprint)
			var occupant_enemy_distance := float(abs(cell.x - start_cell.x) + abs(cell.y - start_cell.y))
			if occupant_goal_distance < best_goal_distance \
				or (is_equal_approx(occupant_goal_distance, best_goal_distance) and occupant_enemy_distance < best_enemy_distance):
				best_goal_distance = occupant_goal_distance
				best_enemy_distance = occupant_enemy_distance
				best_building = occupant
				best_attack_cell = cell

	if best_building == null:
		return {}

	return {
		"building": best_building,
		"cell": best_attack_cell
	}


func _get_attack_world_position_for_cell(target_building: Node3D, attack_cell: Vector2i) -> Vector3:
	var attack_position := map_grid.cell_to_world(attack_cell, global_position.y)
	var direction_to_building := target_building.global_position - attack_position
	direction_to_building.y = 0.0
	if direction_to_building.length_squared() <= 0.0001:
		return _with_enemy_height(attack_position)

	var max_offset := maxf((map_grid.cell_size * 0.5) - 0.05, 0.0)
	var adjusted_position := attack_position + (direction_to_building.normalized() * max_offset)
	return _with_enemy_height(adjusted_position)


func _get_building_distance_to_goal(building: Node, goal_anchor: Vector2i, goal_footprint: Vector2i) -> float:
	if not building.has_meta("grid_anchor_cell") or not building.has_meta("grid_footprint"):
		return INF

	var building_anchor: Vector2i = building.get_meta("grid_anchor_cell")
	var building_footprint: Vector2i = building.get_meta("grid_footprint")
	var best_distance := INF
	for building_cell in map_grid.get_footprint_cells(building_anchor, building_footprint):
		for goal_cell in map_grid.get_footprint_cells(goal_anchor, goal_footprint):
			var distance := float(abs(building_cell.x - goal_cell.x) + abs(building_cell.y - goal_cell.y))
			if distance < best_distance:
				best_distance = distance

	return best_distance


func _find_attackable_building_in_range() -> Node3D:
	var preferred_target := _get_preferred_attack_target()
	if preferred_target != null:
		return preferred_target

	var best_target: Node3D = null
	var best_distance := INF
	for building in get_tree().get_nodes_in_group("rts_buildings"):
		if not (building is Node3D):
			continue

		if not can_attack_target(building):
			continue

		if not is_target_in_attack_range(building):
			continue

		var distance := get_distance_to_attack_target(building)
		if distance < best_distance:
			best_distance = distance
			best_target = building

	return best_target


func _has_attackable_buildings() -> bool:
	for building in get_tree().get_nodes_in_group("rts_buildings"):
		if building is Node and can_attack_target(building):
			return true

	return false


func _get_preferred_attack_target() -> Node3D:
	if _goal_building == null or not is_instance_valid(_goal_building):
		return null

	if _goal_building is Node3D and can_attack_target(_goal_building) and is_target_in_attack_range(_goal_building):
		return _goal_building

	return null


func _face_attack_target(target: Node3D) -> void:
	var direction := target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return

	look_at(global_position + direction.normalized(), Vector3.UP)


func _find_end_point() -> Node:
	for map_geometry in get_tree().get_nodes_in_group("rts_map_geometry_tag_%s" % MAP_GEOMETRY_TAG_END_POINT):
		if map_geometry is Node:
			return map_geometry

	return null


func _get_building_center_world_position(building: Node) -> Vector3:
	if building.has_meta("grid_anchor_cell") and building.has_meta("grid_footprint"):
		var anchor_cell: Vector2i = building.get_meta("grid_anchor_cell")
		var footprint: Vector2i = building.get_meta("grid_footprint")
		return map_grid.footprint_to_world_center(anchor_cell, footprint, global_position.y)

	if building is Node3D:
		return (building as Node3D).global_position

	return global_position


func _is_goal_building_valid() -> bool:
	return _goal_building != null and is_instance_valid(_goal_building) and _goal_building.is_inside_tree()


func _get_path_result_to_goal_building(building: Node) -> Dictionary:
	var target_cells := _get_goal_cells_for_building(building)
	if target_cells.is_empty():
		return {}

	return _get_path_result_to_any_cell(target_cells)


func _get_goal_cells_for_building(building: Node) -> Array[Vector2i]:
	var pathing_system: Node = _get_pathing_system()
	if pathing_system != null:
		return pathing_system.get_goal_cells_for_node(building, movement_type)

	var target_cells: Array[Vector2i] = []
	if not building.has_meta("grid_anchor_cell") or not building.has_meta("grid_footprint"):
		return target_cells

	var anchor_cell: Vector2i = building.get_meta("grid_anchor_cell")
	var footprint: Vector2i = building.get_meta("grid_footprint")
	if bool(building.get_meta("pathable", false)):
		for cell in map_grid.get_footprint_cells(anchor_cell, footprint):
			if _is_enemy_cell_walkable(cell):
				target_cells.append(cell)
	else:
		for cell in _get_neighboring_cells(anchor_cell, footprint):
			if _is_enemy_cell_walkable(cell):
				target_cells.append(cell)

	return target_cells


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
	if is_flying():
		_path = [_target_world_position]
		_cell_path.clear()
		if map_grid.is_cell_in_bounds(_target_cell):
			_cell_path.append(_target_cell)
		_path_index = 0
		return

	var path_result := _get_path_result_to_world_position(_target_world_position)
	_cell_path = path_result.get("cell_path", [])
	_path = path_result.get("path", [])
	_path_index = 0
	_refresh_debug_path_line()


func _get_path_result_to_world_position(target_world_position: Vector3) -> Dictionary:
	var start_cell := get_current_cell()
	var target_cell := map_grid.world_to_cell(target_world_position)
	target_world_position.y = _get_terrain_height_for_cell(target_cell)
	var target_lookup: Dictionary = {}
	target_lookup[target_cell] = true
	var cell_path := _find_enemy_cell_path_to_any(start_cell, target_lookup)
	var path: Array[Vector3] = []
	if start_cell == target_cell:
		path.append(target_world_position)
		return {
			"target_cell": target_cell,
			"cell_path": cell_path,
			"path": path
		}

	if cell_path.is_empty():
		return {}

	var raw_path: Array[Vector3] = []
	for index in range(cell_path.size()):
		var cell := cell_path[index]
		if index == cell_path.size() - 1:
			raw_path.append(target_world_position)
		else:
			raw_path.append(map_grid.cell_to_world(cell, _get_terrain_height_for_cell(cell)))

	return {
		"target_cell": target_cell,
		"cell_path": cell_path,
		"path": _smooth_path(raw_path)
	}


func _get_path_result_to_any_cell(target_cells: Array[Vector2i]) -> Dictionary:
	var start_cell := get_current_cell()
	var target_lookup: Dictionary = {}
	for target_cell in target_cells:
		if map_grid.is_cell_in_bounds(target_cell):
			target_lookup[target_cell] = true

	if target_lookup.is_empty():
		return {}

	var cell_path := _find_enemy_cell_path_to_any(start_cell, target_lookup)
	if cell_path.is_empty() and not target_lookup.has(start_cell):
		return {}

	var reached_cell := start_cell
	if not cell_path.is_empty():
		reached_cell = cell_path[cell_path.size() - 1]

	var target_world_position := map_grid.cell_to_world(reached_cell, global_position.y)
	target_world_position.y = _get_terrain_height_for_cell(reached_cell)
	var path: Array[Vector3] = []
	if start_cell == reached_cell:
		path.append(target_world_position)
	else:
		var raw_path: Array[Vector3] = []
		for index in range(cell_path.size()):
			var cell := cell_path[index]
			if index == cell_path.size() - 1:
				raw_path.append(target_world_position)
			else:
				raw_path.append(map_grid.cell_to_world(cell, _get_terrain_height_for_cell(cell)))

		path = _smooth_path(raw_path)

	return {
		"target_cell": reached_cell,
		"target_world_position": target_world_position,
		"cell_path": cell_path,
		"path": path
	}


func _find_enemy_cell_path_to_any(start_cell: Vector2i, target_lookup: Dictionary) -> Array[Vector2i]:
	var pathing_system: Node = _get_pathing_system()
	if pathing_system == null:
		push_warning("RtsEnemy requires PathingSystem for enemy path queries.")
		return []

	var target_cells: Array[Vector2i] = []
	for target_cell in target_lookup.keys():
		if target_cell is Vector2i:
			target_cells.append(target_cell)

	return pathing_system.get_path_to_any_cell(start_cell, target_cells, movement_type)


func _follow_path(_delta: float) -> void:
	if _path_index >= _path.size():
		_complete_goal_order()
		return

	if _is_current_waypoint_blocked():
		if _is_goal_building_valid() and _is_end_point_geometry(_goal_building):
			_try_path_to_end_point(_goal_building)
		else:
			_rebuild_path_to_target()

		if _path_index >= _path.size():
			_state = EnemyState.IDLE
			_refresh_debug_path_line()
			return

	var target := _path[_path_index]
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() > arrival_distance:
		var move_direction := to_target.normalized()
		if _turn_toward_direction(move_direction, _delta):
			velocity = move_direction * move_speed
			move_and_slide()
			if not is_flying():
				_snap_to_current_terrain_height()
		else:
			velocity = Vector3.ZERO
	else:
		velocity = Vector3.ZERO
		if not is_flying():
			_snap_to_current_terrain_height()

	if Vector2(global_position.x, global_position.z).distance_to(Vector2(target.x, target.z)) <= arrival_distance:
		_path_index += 1
		_refresh_debug_path_line()
	else:
		_refresh_debug_path_line()


func _complete_goal_order() -> void:
	velocity = Vector3.ZERO
	_state = EnemyState.REACHED_GOAL
	_refresh_debug_path_line()


func _is_current_waypoint_blocked() -> bool:
	if _path_index >= _path.size():
		return false

	if is_flying():
		return false

	return not _is_enemy_cell_walkable(map_grid.world_to_cell(_path[_path_index]))


func _is_remaining_path_walkable() -> bool:
	var previous_cell := get_current_cell()
	for index in range(_path_index, _path.size()):
		var cell := map_grid.world_to_cell(_path[index])
		if cell == previous_cell:
			continue

		if not _can_enemy_traverse_between_cells(previous_cell, cell):
			return false

		previous_cell = cell
	return true


func _is_enemy_cell_walkable(cell: Vector2i) -> bool:
	var pathing_system: Node = _get_pathing_system()
	return pathing_system != null and pathing_system.is_cell_walkable_for_movement(cell, movement_type)


func _can_enemy_traverse_between_cells(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var pathing_system: Node = _get_pathing_system()
	return pathing_system != null and pathing_system.can_traverse_between_cells(from_cell, to_cell, movement_type)


func _snap_to_current_terrain_height() -> void:
	var terrain_height := _get_terrain_height_for_cell(get_current_cell())
	global_position.y = terrain_height


func _get_terrain_height_for_cell(cell: Vector2i) -> float:
	var pathing_system: Node = _get_pathing_system()
	if pathing_system == null:
		return global_position.y

	return pathing_system.get_terrain_height_for_cell(cell, movement_type)


func _is_end_point_geometry(node: Node) -> bool:
	if node.has_method("has_tag") and bool(node.call("has_tag", MAP_GEOMETRY_TAG_END_POINT)):
		return true

	for tag in node.get_meta("geometry_tags", []):
		if String(tag) == MAP_GEOMETRY_TAG_END_POINT:
			return true

	return false


func _get_cardinal_neighbor_cells(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.RIGHT,
		cell + Vector2i.LEFT,
		cell + Vector2i.DOWN,
		cell + Vector2i.UP
	]


func _smooth_path(raw_path: Array[Vector3]) -> Array[Vector3]:
	return raw_path


func _with_enemy_height(world_position: Vector3) -> Vector3:
	var height := flight_height if is_flying() else global_position.y
	return Vector3(world_position.x, height, world_position.z)


func _get_collision_mask_for_movement_type() -> int:
	if is_flying():
		return 0

	return COLLISION_LAYER_WORLD | COLLISION_LAYER_BLOCKS_ENEMIES


func _turn_toward_direction(target_direction: Vector3, delta: float) -> bool:
	target_direction.y = 0.0
	if target_direction.length_squared() <= 0.0001:
		_reset_turn_ramp()
		return true

	var normalized_target := target_direction.normalized()
	if turn_speed <= 0.0:
		look_at(global_position + normalized_target, Vector3.UP)
		_reset_turn_ramp()
		return true

	var current_forward := -global_transform.basis.z
	current_forward.y = 0.0
	if current_forward.length_squared() <= 0.0001:
		look_at(global_position + normalized_target, Vector3.UP)
		_reset_turn_ramp()
		return true

	current_forward = current_forward.normalized()
	var angle := current_forward.signed_angle_to(normalized_target, Vector3.UP)
	var alignment_angle := deg_to_rad(maxf(turn_alignment_degrees, 0.0))
	var is_aligned_before_turn := absf(angle) <= alignment_angle
	if is_zero_approx(angle):
		_reset_turn_ramp()
		return true

	var max_turn := _get_turn_step(angle, delta)
	if absf(angle) <= max_turn:
		look_at(global_position + normalized_target, Vector3.UP)
		_reset_turn_ramp()
		return true

	rotate_y(clampf(angle, -max_turn, max_turn))
	return is_aligned_before_turn or absf(angle) - max_turn <= alignment_angle


func _get_turn_step(angle: float, delta: float) -> float:
	var turn_sign := signf(angle)
	if not is_equal_approx(turn_sign, _last_turn_sign):
		_current_turn_speed = 0.0
		_last_turn_sign = turn_sign

	var max_turn_speed := deg_to_rad(maxf(turn_speed, 0.0))
	if turn_acceleration_time <= 0.0:
		_current_turn_speed = max_turn_speed
	else:
		_current_turn_speed = minf(
			_current_turn_speed + (max_turn_speed / turn_acceleration_time) * delta,
			max_turn_speed
		)

	return _current_turn_speed * delta


func _reset_turn_ramp() -> void:
	_current_turn_speed = 0.0
	_last_turn_sign = 0.0


func _get_pathing_system() -> Node:
	if _pathing_system != null and is_instance_valid(_pathing_system):
		return _pathing_system

	_pathing_system = _find_pathing_system()
	return _pathing_system


func _find_pathing_system() -> Node:
	for pathing_node in get_tree().get_nodes_in_group("rts_pathing_system"):
		if pathing_node is Node and pathing_node.has_method("get_path_to_any_cell"):
			return pathing_node

	return null


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


func _create_flight_shadow() -> void:
	if not is_flying():
		return

	_flight_shadow = MeshInstance3D.new()
	_flight_shadow.name = "FlightShadow"
	_flight_shadow.top_level = true
	_flight_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shadow_radius := maxf(collision_radius * 1.8, 0.65)
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = shadow_radius
	shadow_mesh.bottom_radius = shadow_radius
	shadow_mesh.height = 0.01
	shadow_mesh.radial_segments = 48
	shadow_mesh.material = _create_flight_shadow_material()
	_flight_shadow.mesh = shadow_mesh
	add_child(_flight_shadow)
	_update_flight_shadow()


func _update_flight_shadow() -> void:
	if _flight_shadow == null or not is_instance_valid(_flight_shadow):
		return

	_flight_shadow.global_position = Vector3(global_position.x, FLIGHT_SHADOW_HEIGHT, global_position.z)


func _create_flight_shadow_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.02, 0.025, 0.02, FLIGHT_SHADOW_ALPHA)
	material.roughness = 1.0
	return material


func _create_damage_debug_label() -> void:
	if not show_damage_debug:
		return

	_damage_debug_label = Label3D.new()
	_damage_debug_label.name = "DamageDebugLabel"
	_damage_debug_label.position = Vector3(0.0, collision_height + damage_debug_height_offset, 0.0)
	_damage_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_damage_debug_label.no_depth_test = true
	_damage_debug_label.font_size = damage_debug_font_size
	_damage_debug_label.modulate = Color(1.0, 0.92, 0.36, 1.0)
	_damage_debug_label.outline_size = damage_debug_outline_size
	_damage_debug_label.outline_modulate = Color(0.03, 0.025, 0.02, 1.0)
	add_child(_damage_debug_label)
	_update_damage_debug_label_text()


func _create_debug_path_line() -> void:
	if not show_path_debug:
		return

	_debug_path_line = MeshInstance3D.new()
	_debug_path_line.name = "DebugPathLine"
	_debug_path_line.top_level = true
	_debug_path_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_path_line.material_override = _create_debug_path_material()
	add_child(_debug_path_line)
	_refresh_debug_path_line()


func _refresh_debug_path_line() -> void:
	if not show_path_debug:
		return

	if _debug_path_line == null or not is_instance_valid(_debug_path_line):
		return

	if _state != EnemyState.MOVING_TO_GOAL or _path_index >= _path.size():
		_debug_path_line.visible = false
		_debug_path_line.mesh = null
		return

	var path_mesh := ImmediateMesh.new()
	path_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	path_mesh.surface_add_vertex(_get_debug_path_point(global_position))
	for index in range(_path_index, _path.size()):
		path_mesh.surface_add_vertex(_get_debug_path_point(_path[index]))
	path_mesh.surface_end()

	_debug_path_line.global_transform = Transform3D.IDENTITY
	_debug_path_line.mesh = path_mesh
	_debug_path_line.visible = true


func _get_debug_path_point(world_position: Vector3) -> Vector3:
	return Vector3(
		world_position.x,
		world_position.y + DEBUG_PATH_LINE_HEIGHT_OFFSET,
		world_position.z
	)


func _create_debug_path_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.92, 0.2, 1.0)
	material.no_depth_test = true
	return material


func _update_damage_debug_label_text() -> void:
	if _damage_debug_label == null or not is_instance_valid(_damage_debug_label):
		return

	_damage_debug_label.text = "Last: %d\n10s: %d" % [_last_damage_taken, _get_rolling_damage_total()]


func _get_rolling_damage_total() -> int:
	var total := 0
	for event in _damage_events:
		total += int(event.get("damage", 0))

	return total


func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	return material
