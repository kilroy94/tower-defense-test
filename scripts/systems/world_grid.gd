class_name MapGrid
extends MeshInstance3D

@export var map_size_cells: Vector2i = Vector2i(30, 30)
@export var cell_size: float = 4.0
@export var major_line_every: int = 5
@export var minor_line_color: Color = Color(0.38, 0.46, 0.4, 0.5)
@export var major_line_color: Color = Color(0.56, 0.64, 0.58, 0.8)

var _occupied_cells: Dictionary = {}


func _ready() -> void:
	_rebuild_grid_mesh()


func world_to_cell(world_position: Vector3) -> Vector2i:
	var local_position := to_local(world_position)
	var half_extents := get_half_extents()
	var cell_x := floori((local_position.x + half_extents.x) / cell_size)
	var cell_y := floori((local_position.z + half_extents.y) / cell_size)
	return Vector2i(cell_x, cell_y)


func cell_to_world(cell: Vector2i, height: float = 0.0) -> Vector3:
	var half_extents := get_half_extents()
	var local_position := Vector3(
		-half_extents.x + (float(cell.x) + 0.5) * cell_size,
		height,
		-half_extents.y + (float(cell.y) + 0.5) * cell_size
	)
	return to_global(local_position)


func footprint_to_world_center(anchor_cell: Vector2i, footprint: Vector2i, height: float = 0.0) -> Vector3:
	var half_extents := get_half_extents()
	var local_position := Vector3(
		-half_extents.x + (float(anchor_cell.x) + float(footprint.x) * 0.5) * cell_size,
		height,
		-half_extents.y + (float(anchor_cell.y) + float(footprint.y) * 0.5) * cell_size
	)
	return to_global(local_position)


func world_to_anchor_cell(world_position: Vector3, footprint: Vector2i = Vector2i.ONE) -> Vector2i:
	var center_cell := world_to_cell(world_position)
	return center_cell - Vector2i(floori(float(footprint.x) * 0.5), floori(float(footprint.y) * 0.5))


func snap_world_to_cell_center(world_position: Vector3, height: float = 0.0) -> Vector3:
	return cell_to_world(world_to_cell(world_position), height)


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size_cells.x and cell.y < map_size_cells.y


func is_footprint_in_bounds(anchor_cell: Vector2i, footprint: Vector2i) -> bool:
	return anchor_cell.x >= 0 \
		and anchor_cell.y >= 0 \
		and anchor_cell.x + footprint.x <= map_size_cells.x \
		and anchor_cell.y + footprint.y <= map_size_cells.y


func get_footprint_cells(anchor_cell: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(anchor_cell.y, anchor_cell.y + footprint.y):
		for x in range(anchor_cell.x, anchor_cell.x + footprint.x):
			cells.append(Vector2i(x, y))
	return cells


func can_place(anchor_cell: Vector2i, footprint: Vector2i = Vector2i.ONE) -> bool:
	if not is_footprint_in_bounds(anchor_cell, footprint):
		return false

	for cell in get_footprint_cells(anchor_cell, footprint):
		if _occupied_cells.has(cell):
			return false

	return true


func is_cell_walkable(cell: Vector2i) -> bool:
	return is_cell_in_bounds(cell) and not _occupied_cells.has(cell)


func find_path(start_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not is_cell_walkable(start_cell) or not is_cell_walkable(target_cell):
		return path

	var frontier: Array[Vector2i] = [start_cell]
	var came_from: Dictionary = {start_cell: start_cell}
	var cost_so_far: Dictionary = {start_cell: 0}

	while not frontier.is_empty():
		var current := _pop_lowest_priority_cell(frontier, cost_so_far, target_cell)
		if current == target_cell:
			break

		for neighbor in _get_walkable_neighbors(current):
			var new_cost := int(cost_so_far[current]) + 1
			if not cost_so_far.has(neighbor) or new_cost < int(cost_so_far[neighbor]):
				cost_so_far[neighbor] = new_cost
				came_from[neighbor] = current
				frontier.append(neighbor)

	if not came_from.has(target_cell):
		return path

	var current_cell := target_cell
	while current_cell != start_cell:
		path.push_front(current_cell)
		current_cell = came_from[current_cell]

	return path


func is_world_segment_walkable(from: Vector3, to: Vector3) -> bool:
	var distance := Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))
	var sample_count := maxi(2, ceili(distance / (cell_size * 0.25)))
	for index in range(sample_count + 1):
		var weight := float(index) / float(sample_count)
		var point := from.lerp(to, weight)
		if not is_cell_walkable(world_to_cell(point)):
			return false

	return true


func occupy(anchor_cell: Vector2i, footprint: Vector2i = Vector2i.ONE, occupant: Variant = true) -> bool:
	if not can_place(anchor_cell, footprint):
		return false

	for cell in get_footprint_cells(anchor_cell, footprint):
		_occupied_cells[cell] = occupant

	return true


func release(anchor_cell: Vector2i, footprint: Vector2i = Vector2i.ONE) -> void:
	for cell in get_footprint_cells(anchor_cell, footprint):
		_occupied_cells.erase(cell)


func clear_occupancy() -> void:
	_occupied_cells.clear()


func get_occupant(cell: Vector2i) -> Variant:
	return _occupied_cells.get(cell)


func get_half_extents() -> Vector2:
	return Vector2(float(map_size_cells.x), float(map_size_cells.y)) * cell_size * 0.5


func _rebuild_grid_mesh() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var immediate_mesh := ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var half_extents := get_half_extents()
	for x in range(map_size_cells.x + 1):
		var world_x := -half_extents.x + float(x) * cell_size
		_add_line(
			immediate_mesh,
			Vector3(world_x, 0.03, -half_extents.y),
			Vector3(world_x, 0.03, half_extents.y),
			_get_line_color(x)
		)

	for y in range(map_size_cells.y + 1):
		var world_z := -half_extents.y + float(y) * cell_size
		_add_line(
			immediate_mesh,
			Vector3(-half_extents.x, 0.03, world_z),
			Vector3(half_extents.x, 0.03, world_z),
			_get_line_color(y)
		)

	immediate_mesh.surface_end()
	mesh = immediate_mesh


func _add_line(immediate_mesh: ImmediateMesh, start_point: Vector3, end_point: Vector3, color: Color) -> void:
	immediate_mesh.surface_set_color(color)
	immediate_mesh.surface_add_vertex(start_point)
	immediate_mesh.surface_add_vertex(end_point)


func _get_line_color(line_index: int) -> Color:
	if major_line_every > 0 and line_index % major_line_every == 0:
		return major_line_color

	return minor_line_color


func _pop_lowest_priority_cell(frontier: Array[Vector2i], cost_so_far: Dictionary, target_cell: Vector2i) -> Vector2i:
	var best_index := 0
	var best_priority := INF
	for index in range(frontier.size()):
		var cell := frontier[index]
		var priority := float(cost_so_far[cell]) + _get_manhattan_distance(cell, target_cell)
		if priority < best_priority:
			best_priority = priority
			best_index = index

	return frontier.pop_at(best_index)


func _get_walkable_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	for offset in offsets:
		var neighbor := cell + offset
		if is_cell_walkable(neighbor):
			neighbors.append(neighbor)

	return neighbors


func _get_manhattan_distance(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))
