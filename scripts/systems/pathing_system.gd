class_name PathingSystem
extends Node

const MAP_GEOMETRY_TAG_END_POINT := "end_point"
const MAP_GEOMETRY_SHAPE_BOX := "box"
const MAP_GEOMETRY_SHAPE_RAMP := "ramp"
const GROUND_HEIGHT := 0.0
const MOVEMENT_TYPE_GROUND := "ground"

@export var grid_path: NodePath
@export var rebuild_cells_per_frame := 240

@onready var map_grid: MapGrid = get_node(grid_path)

var _active_flow_fields_by_request: Dictionary = {}
var _known_flow_requests: Dictionary = {}
var _pending_rebuild_request_keys: Array[String] = []
var _active_rebuild_job: Dictionary = {}
var _last_pathing_revision := -1
var _map_geometry_walkable_cache: Dictionary = {}
var _map_geometry_top_cache: Dictionary = {}
var _terrain_height_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("rts_pathing_system")
	_last_pathing_revision = map_grid.get_pathing_revision()
	_register_current_endpoint_requests()


func _process(_delta: float) -> void:
	var current_revision := map_grid.get_pathing_revision()
	if current_revision == _last_pathing_revision:
		_process_rebuild_work()
		return

	_last_pathing_revision = current_revision
	_register_current_endpoint_requests()
	_enqueue_all_known_rebuilds()
	_process_rebuild_work()


func get_path_to_any_cell(start_cell: Vector2i, target_cells: Array[Vector2i], movement_type := MOVEMENT_TYPE_GROUND) -> Array[Vector2i]:
	var cell_path: Array[Vector2i] = []
	var target_lookup := _get_target_lookup(target_cells)
	if target_lookup.is_empty():
		return cell_path

	var flow_field := _get_flow_field(target_lookup, movement_type)
	var next_cell_by_cell: Dictionary = flow_field.get("next_cell_by_cell", {})
	if not target_lookup.has(start_cell) and not next_cell_by_cell.has(start_cell):
		return cell_path

	var current_cell := start_cell
	var max_steps := map_grid.map_size_cells.x * map_grid.map_size_cells.y
	while not target_lookup.has(current_cell) and cell_path.size() < max_steps:
		if not next_cell_by_cell.has(current_cell):
			cell_path.clear()
			return cell_path

		current_cell = next_cell_by_cell[current_cell]
		cell_path.append(current_cell)

	return cell_path


func get_goal_cells_for_node(goal_node: Node, movement_type := MOVEMENT_TYPE_GROUND) -> Array[Vector2i]:
	var target_cells: Array[Vector2i] = []
	if not goal_node.has_meta("grid_anchor_cell") or not goal_node.has_meta("grid_footprint"):
		return target_cells

	var anchor_cell: Vector2i = goal_node.get_meta("grid_anchor_cell")
	var footprint: Vector2i = goal_node.get_meta("grid_footprint")
	if bool(goal_node.get_meta("pathable", false)):
		for cell in map_grid.get_footprint_cells(anchor_cell, footprint):
			if is_cell_walkable_for_movement(cell, movement_type):
				target_cells.append(cell)
	else:
		for cell in _get_neighboring_cells(anchor_cell, footprint):
			if is_cell_walkable_for_movement(cell, movement_type):
				target_cells.append(cell)

	return target_cells


func is_cell_walkable_for_movement(cell: Vector2i, movement_type := MOVEMENT_TYPE_GROUND) -> bool:
	if movement_type != MOVEMENT_TYPE_GROUND:
		return map_grid.is_cell_in_bounds(cell)

	if not map_grid.is_cell_in_bounds(cell):
		return false

	var occupant: Variant = map_grid.get_occupant(cell)
	if occupant == null:
		return map_grid.is_cell_walkable(cell)

	if occupant is Node and _is_end_point_geometry(occupant):
		return true

	if occupant is Node and _is_map_geometry_cell_walkable(cell):
		return true

	return false


func get_terrain_height_for_cell(cell: Vector2i, movement_type := MOVEMENT_TYPE_GROUND) -> float:
	if movement_type != MOVEMENT_TYPE_GROUND:
		return GROUND_HEIGHT

	if _terrain_height_cache.has(cell):
		return float(_terrain_height_cache[cell])

	var height := _compute_terrain_height_for_cell(cell)
	_terrain_height_cache[cell] = height
	return height


func can_traverse_between_cells(from_cell: Vector2i, to_cell: Vector2i, movement_type := MOVEMENT_TYPE_GROUND) -> bool:
	if movement_type != MOVEMENT_TYPE_GROUND:
		return map_grid.is_cell_in_bounds(to_cell)

	if not is_cell_walkable_for_movement(to_cell, movement_type):
		return false

	var from_height := get_terrain_height_for_cell(from_cell, movement_type)
	var to_height := get_terrain_height_for_cell(to_cell, movement_type)
	if is_equal_approx(from_height, to_height):
		return _is_valid_same_height_transition(from_cell, to_cell)

	return _is_valid_ramp_transition(from_cell, to_cell, from_height, to_height)


func _register_current_endpoint_requests() -> void:
	for end_point in get_tree().get_nodes_in_group("rts_map_geometry_tag_%s" % MAP_GEOMETRY_TAG_END_POINT):
		if not (end_point is Node):
			continue

		var target_cells := get_goal_cells_for_node(end_point, MOVEMENT_TYPE_GROUND)
		if target_cells.is_empty():
			continue

		_register_flow_request(_get_target_lookup(target_cells), MOVEMENT_TYPE_GROUND)


func _rebuild_known_flow_fields() -> void:
	_enqueue_all_known_rebuilds()


func _enqueue_all_known_rebuilds() -> void:
	for request_key in _known_flow_requests.keys():
		_enqueue_rebuild_request(String(request_key))


func _get_flow_field(target_lookup: Dictionary, movement_type: String) -> Dictionary:
	_register_flow_request(target_lookup, movement_type)
	var request_key := _get_flow_request_key(target_lookup, movement_type)
	var active_flow_field: Dictionary = _active_flow_fields_by_request.get(request_key, {})
	if not active_flow_field.is_empty():
		if int(active_flow_field.get("revision", -1)) != map_grid.get_pathing_revision():
			_enqueue_rebuild_request(request_key)
		return active_flow_field

	var flow_field := _build_flow_field(target_lookup, movement_type)
	flow_field["revision"] = map_grid.get_pathing_revision()
	_active_flow_fields_by_request[request_key] = flow_field
	return flow_field


func _build_flow_field(target_lookup: Dictionary, movement_type: String) -> Dictionary:
	_map_geometry_walkable_cache.clear()
	_map_geometry_top_cache.clear()
	_terrain_height_cache.clear()

	var frontier: Array[Vector2i] = []
	var visited: Dictionary = {}
	var next_cell_by_cell: Dictionary = {}
	for target_cell in target_lookup.keys():
		if not (target_cell is Vector2i):
			continue

		if not is_cell_walkable_for_movement(target_cell, movement_type):
			continue

		frontier.append(target_cell)
		visited[target_cell] = true

	while not frontier.is_empty():
		var current_cell: Vector2i = frontier.pop_front()
		for neighbor_cell in _get_cardinal_neighbor_cells(current_cell):
			if visited.has(neighbor_cell):
				continue

			if not can_traverse_between_cells(neighbor_cell, current_cell, movement_type):
				continue

			visited[neighbor_cell] = true
			next_cell_by_cell[neighbor_cell] = current_cell
			frontier.append(neighbor_cell)

	return {
		"next_cell_by_cell": next_cell_by_cell
	}


func _enqueue_rebuild_request(request_key: String) -> void:
	if not _known_flow_requests.has(request_key):
		return

	if _pending_rebuild_request_keys.has(request_key):
		return

	if not _active_rebuild_job.is_empty() and String(_active_rebuild_job.get("request_key", "")) == request_key:
		return

	_pending_rebuild_request_keys.append(request_key)


func _process_rebuild_work() -> void:
	var remaining_budget := maxi(rebuild_cells_per_frame, 1)
	while remaining_budget > 0:
		if _active_rebuild_job.is_empty():
			if _pending_rebuild_request_keys.is_empty():
				return

			var request_key := String(_pending_rebuild_request_keys.pop_front())
			_active_rebuild_job = _create_rebuild_job(request_key)
			if _active_rebuild_job.is_empty():
				continue

		var processed_cells := _process_active_rebuild_job(remaining_budget)
		remaining_budget -= maxi(processed_cells, 1)


func _create_rebuild_job(request_key: String) -> Dictionary:
	if not _known_flow_requests.has(request_key):
		return {}

	var request: Dictionary = _known_flow_requests[request_key]
	var target_lookup: Dictionary = request.get("target_lookup", {})
	var movement_type := String(request.get("movement_type", MOVEMENT_TYPE_GROUND))
	var frontier: Array[Vector2i] = []
	var visited: Dictionary = {}
	var next_cell_by_cell: Dictionary = {}

	_map_geometry_walkable_cache.clear()
	_map_geometry_top_cache.clear()
	_terrain_height_cache.clear()

	for target_cell in target_lookup.keys():
		if not (target_cell is Vector2i):
			continue

		if not is_cell_walkable_for_movement(target_cell, movement_type):
			continue

		frontier.append(target_cell)
		visited[target_cell] = true

	return {
		"request_key": request_key,
		"target_lookup": target_lookup,
		"movement_type": movement_type,
		"frontier": frontier,
		"visited": visited,
		"next_cell_by_cell": next_cell_by_cell,
		"revision": map_grid.get_pathing_revision()
	}


func _process_active_rebuild_job(cell_budget: int) -> int:
	if int(_active_rebuild_job.get("revision", -1)) != map_grid.get_pathing_revision():
		var request_key := String(_active_rebuild_job.get("request_key", ""))
		_active_rebuild_job.clear()
		_enqueue_rebuild_request(request_key)
		return 1

	var movement_type := String(_active_rebuild_job.get("movement_type", MOVEMENT_TYPE_GROUND))
	var frontier: Array = _active_rebuild_job.get("frontier", [])
	var visited: Dictionary = _active_rebuild_job.get("visited", {})
	var next_cell_by_cell: Dictionary = _active_rebuild_job.get("next_cell_by_cell", {})
	var processed_cells := 0

	while processed_cells < cell_budget and not frontier.is_empty():
		var current_cell: Vector2i = frontier.pop_front()
		processed_cells += 1

		for neighbor_cell in _get_cardinal_neighbor_cells(current_cell):
			if visited.has(neighbor_cell):
				continue

			if not can_traverse_between_cells(neighbor_cell, current_cell, movement_type):
				continue

			visited[neighbor_cell] = true
			next_cell_by_cell[neighbor_cell] = current_cell
			frontier.append(neighbor_cell)

	_active_rebuild_job["frontier"] = frontier
	_active_rebuild_job["visited"] = visited
	_active_rebuild_job["next_cell_by_cell"] = next_cell_by_cell

	if frontier.is_empty():
		var request_key := String(_active_rebuild_job.get("request_key", ""))
		_active_flow_fields_by_request[request_key] = {
			"revision": int(_active_rebuild_job.get("revision", -1)),
			"next_cell_by_cell": next_cell_by_cell
		}
		_active_rebuild_job.clear()

	return processed_cells


func _register_flow_request(target_lookup: Dictionary, movement_type: String) -> void:
	var request_key := _get_flow_request_key(target_lookup, movement_type)
	if _known_flow_requests.has(request_key):
		return

	_known_flow_requests[request_key] = {
		"target_lookup": target_lookup.duplicate(),
		"movement_type": movement_type
	}


func _get_target_lookup(target_cells: Array[Vector2i]) -> Dictionary:
	var target_lookup: Dictionary = {}
	for target_cell in target_cells:
		if map_grid.is_cell_in_bounds(target_cell):
			target_lookup[target_cell] = true

	return target_lookup


func _get_flow_request_key(target_lookup: Dictionary, movement_type: String) -> String:
	var target_parts: Array[String] = []
	for target_cell in target_lookup.keys():
		if target_cell is Vector2i:
			target_parts.append("%d,%d" % [target_cell.x, target_cell.y])
	target_parts.sort()

	return "%s:%s" % [
		movement_type,
		";".join(target_parts)
	]


func _get_neighboring_cells(anchor_cell: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var candidate_cells: Array[Vector2i] = []
	for x in range(anchor_cell.x, anchor_cell.x + footprint.x):
		candidate_cells.append(Vector2i(x, anchor_cell.y - 1))
		candidate_cells.append(Vector2i(x, anchor_cell.y + footprint.y))

	for y in range(anchor_cell.y, anchor_cell.y + footprint.y):
		candidate_cells.append(Vector2i(anchor_cell.x - 1, y))
		candidate_cells.append(Vector2i(anchor_cell.x + footprint.x, y))

	return candidate_cells


func _get_cardinal_neighbor_cells(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.RIGHT,
		cell + Vector2i.LEFT,
		cell + Vector2i.DOWN,
		cell + Vector2i.UP
	]


func _compute_terrain_height_for_cell(cell: Vector2i) -> float:
	var top_geometry := _get_top_map_geometry_at_cell(cell)
	if top_geometry == null:
		return GROUND_HEIGHT

	if not _is_map_geometry_cell_walkable(cell):
		return GROUND_HEIGHT

	if _is_end_point_geometry(top_geometry):
		return _get_map_geometry_base_height(top_geometry)

	return _get_map_geometry_top_height(top_geometry)


func _is_map_geometry_cell_walkable(cell: Vector2i) -> bool:
	if _map_geometry_walkable_cache.has(cell):
		return bool(_map_geometry_walkable_cache[cell])

	var is_walkable := _compute_map_geometry_cell_walkable(cell)
	_map_geometry_walkable_cache[cell] = is_walkable
	return is_walkable


func _compute_map_geometry_cell_walkable(cell: Vector2i) -> bool:
	var top_geometry := _get_top_map_geometry_at_cell(cell)
	if top_geometry == null:
		return false

	if _is_end_point_geometry(top_geometry):
		return true

	var shape := String(top_geometry.get_meta("geometry_shape", MAP_GEOMETRY_SHAPE_BOX))
	if shape == MAP_GEOMETRY_SHAPE_RAMP:
		return true

	if shape != MAP_GEOMETRY_SHAPE_BOX:
		return false

	return true


func _is_valid_same_height_transition(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var from_geometry := _get_top_map_geometry_at_cell(from_cell)
	var to_geometry := _get_top_map_geometry_at_cell(to_cell)
	var from_is_ramp := _is_ramp_geometry(from_geometry)
	var to_is_ramp := _is_ramp_geometry(to_geometry)
	if from_is_ramp and not to_is_ramp:
		return _is_ramp_high_side_neighbor(from_geometry, from_cell, to_cell)

	if to_is_ramp and not from_is_ramp:
		return _is_ramp_high_side_neighbor(to_geometry, to_cell, from_cell)

	return true


func _is_valid_ramp_transition(from_cell: Vector2i, to_cell: Vector2i, from_height: float, to_height: float) -> bool:
	var from_geometry := _get_top_map_geometry_at_cell(from_cell)
	var to_geometry := _get_top_map_geometry_at_cell(to_cell)
	if to_height > from_height:
		return _is_ramp_geometry(to_geometry) \
			and is_equal_approx(from_height, _get_map_geometry_base_height(to_geometry)) \
			and is_equal_approx(to_height, _get_map_geometry_top_height(to_geometry)) \
			and _is_ramp_low_side_neighbor(to_geometry, from_cell, to_cell)

	if from_height > to_height:
		return _is_ramp_geometry(from_geometry) \
			and is_equal_approx(from_height, _get_map_geometry_top_height(from_geometry)) \
			and is_equal_approx(to_height, _get_map_geometry_base_height(from_geometry)) \
			and _is_ramp_low_side_neighbor(from_geometry, to_cell, from_cell)

	return false


func _is_end_point_geometry(node: Node) -> bool:
	if node.has_method("has_tag") and bool(node.call("has_tag", MAP_GEOMETRY_TAG_END_POINT)):
		return true

	for tag in node.get_meta("geometry_tags", []):
		if String(tag) == MAP_GEOMETRY_TAG_END_POINT:
			return true

	return false


func _is_ramp_geometry(map_geometry: Node) -> bool:
	return map_geometry != null \
		and String(map_geometry.get_meta("geometry_shape", MAP_GEOMETRY_SHAPE_BOX)) == MAP_GEOMETRY_SHAPE_RAMP


func _is_ramp_high_side_neighbor(ramp_geometry: Node, ramp_cell: Vector2i, neighbor_cell: Vector2i) -> bool:
	return neighbor_cell == ramp_cell + _get_ramp_high_direction(ramp_geometry)


func _is_ramp_low_side_neighbor(ramp_geometry: Node, neighbor_cell: Vector2i, ramp_cell: Vector2i) -> bool:
	return neighbor_cell == ramp_cell - _get_ramp_high_direction(ramp_geometry)


func _get_ramp_high_direction(ramp_geometry: Node) -> Vector2i:
	var rotation_steps := posmod(int(ramp_geometry.get_meta("geometry_rotation_steps", 0)), 4)
	match rotation_steps:
		0:
			return Vector2i.DOWN
		1:
			return Vector2i.LEFT
		2:
			return Vector2i.UP
		3:
			return Vector2i.RIGHT

	return Vector2i.DOWN


func _get_top_map_geometry_at_cell(cell: Vector2i) -> Node:
	if _map_geometry_top_cache.has(cell):
		return _map_geometry_top_cache[cell] as Node

	var top_geometry := map_grid.get_top_map_geometry_at_cell(cell)
	_map_geometry_top_cache[cell] = top_geometry
	return top_geometry


func _get_map_geometry_top_height(map_geometry: Node) -> float:
	var size: Vector3 = map_geometry.get_meta("geometry_size", Vector3.ZERO)
	return _get_map_geometry_base_height(map_geometry) + size.y


func _get_map_geometry_base_height(map_geometry: Node) -> float:
	return float(map_geometry.get_meta("geometry_base_height", 0.0))
