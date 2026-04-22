extends Node

const ERROR_SOUND: AudioStream = preload("res://assets/audio/sfx/vo/Interface/Error.wav")
const BUILDING_PLACEMENT_SOUND: AudioStream = preload("res://assets/audio/sfx/vo/Miscellaneous/Buildings/Shared/BuildingPlacement.wav")
const BUILDING_CONSTRUCTION_SOUND: AudioStream = preload("res://assets/audio/sfx/vo/Miscellaneous/Buildings/Shared/BuildingConstruction.wav")
const BUILDING_COMPLETE_SOUND: AudioStream = preload("res://assets/audio/sfx/vo/Miscellaneous/Buildings/Human/PeasantBuildingComplete1.wav")
const CONSTRUCTION_LOOP_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/vo/Miscellaneous/Buildings/Shared/ConstructionLoop1.wav"),
	preload("res://assets/audio/sfx/vo/Miscellaneous/Buildings/Shared/ConstructionLoop2.wav")
]
const COMMAND_BUILD := "build"
const COMMAND_DESTROY := "destroy"
const COMMAND_BUILDING_PREFIX := "build:"
const BUILDINGS_MENU_ID := "buildings"
const QUIET_CONSTRUCTION_LOOP_VOLUME_DB := -18.0
const DESTROY_MARKER_META := "destroy_marker"
const DOUBLE_TAP_WINDOW_MSEC := 350
const BUILD_MENU_BACK_SLOT := Vector2i(2, 2)
const MAX_BUILD_MENU_BUILDINGS := 8

@export var grid_path: NodePath
@export var camera_rig_path: NodePath
@export var preview_path: NodePath
@export var hud_label_path: NodePath
@export var selection_panel_path: NodePath
@export var command_grid_path: NodePath
@export var buildings_root_path: NodePath
@export var building_data_directory := "res://data/buildings"

@onready var map_grid: MapGrid = get_node(grid_path)
@onready var camera_rig: Node = get_node(camera_rig_path)
@onready var placement_preview: GridPlacementPreview = get_node(preview_path)
@onready var hud_label: Label = get_node(hud_label_path)
@onready var selection_panel: SelectionPanel = get_node(selection_panel_path)
@onready var command_grid: CommandGrid = get_node(command_grid_path)
@onready var buildings_root: Node3D = get_node(buildings_root_path)

const SELECTION_RING_SEGMENTS := 96

enum InteractionState {
	SELECTING,
	BUILDING,
	DESTROYING
}

var _building_options: Array[Dictionary] = []
var _selected_index := 0
var _selected_placed_building: Node = null
var _selected_unit: RtsUnit = null
var _selection_ring: MeshInstance3D
var _interface_audio_player: AudioStreamPlayer
var _interaction_state := InteractionState.SELECTING
var _queued_buildings_root: Node3D
var _building_audio_rng := RandomNumberGenerator.new()
var _last_scout_hotkey_msec := 0
var _queue_display_unit: RtsUnit = null
var _all_building_options: Array[Dictionary] = []


func _ready() -> void:
	_building_audio_rng.randomize()
	_load_building_data()
	_create_interface_audio_player()
	_create_selection_ring()
	_create_queued_buildings_root()
	command_grid.command_pressed.connect(_on_command_pressed)
	selection_panel.portrait_double_clicked.connect(_on_selection_portrait_double_clicked)
	command_grid.set_commands([])
	_sync_building_command_menu()
	_apply_selected_building()
	_set_interaction_state(InteractionState.SELECTING)


func _process(_delta: float) -> void:
	if _selected_unit != null:
		_update_selection_ring()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B:
				_toggle_building_mode()
			KEY_V:
				_toggle_destroy_mode()
			KEY_F1:
				_select_scout_unit_from_hotkey()
			KEY_ESCAPE:
				_set_interaction_state(InteractionState.SELECTING)
			KEY_1:
				if _interaction_state == InteractionState.BUILDING:
					_select_building(0)
			KEY_2:
				if _interaction_state == InteractionState.BUILDING:
					_select_building(1)
			KEY_3:
				if _interaction_state == InteractionState.BUILDING:
					_select_building(2)

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		_handle_left_click()

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_RIGHT \
		and event.pressed:
		_handle_right_click()


func _handle_left_click() -> void:
	if _interaction_state == InteractionState.BUILDING:
		_try_issue_build_order()
		return

	if _interaction_state == InteractionState.DESTROYING:
		_try_issue_destroy_order()
		return

	var hovered_building := _get_building_on_current_cell()
	if hovered_building != null:
		_select_placed_building(hovered_building)
		return

	var hovered_unit := _get_unit_on_current_cell()
	if hovered_unit != null:
		_select_unit(hovered_unit)
		return

	_clear_selection()


func _handle_right_click() -> void:
	if _selected_unit != null:
		_issue_selected_unit_move_order()


func _set_interaction_state(new_state: int) -> void:
	if new_state == InteractionState.BUILDING and _building_options.is_empty():
		_play_invalid_order_feedback()
		new_state = InteractionState.SELECTING

	_interaction_state = new_state
	placement_preview.set_display_enabled(_interaction_state == InteractionState.BUILDING)
	if _selected_unit != null:
		if _interaction_state == InteractionState.BUILDING:
			command_grid.show_menu(BUILDINGS_MENU_ID)
			command_grid.set_selected_command(_get_building_command_id(_selected_index))
		elif _interaction_state == InteractionState.DESTROYING:
			command_grid.show_menu(CommandGrid.ROOT_MENU_ID)
			command_grid.set_selected_command(COMMAND_DESTROY)
		else:
			command_grid.show_menu(CommandGrid.ROOT_MENU_ID)
			command_grid.set_selected_command("")
	_update_hud()


func _toggle_building_mode() -> void:
	if _interaction_state == InteractionState.BUILDING:
		_set_interaction_state(InteractionState.SELECTING)
	else:
		_try_enter_building_mode()


func _try_enter_building_mode() -> void:
	if _selected_unit != null:
		_set_interaction_state(InteractionState.BUILDING)
	else:
		_play_invalid_order_feedback()


func _toggle_destroy_mode() -> void:
	if _interaction_state == InteractionState.DESTROYING:
		_set_interaction_state(InteractionState.SELECTING)
	else:
		_try_enter_destroy_mode()


func _try_enter_destroy_mode() -> void:
	if _selected_unit != null:
		_set_interaction_state(InteractionState.DESTROYING)
	else:
		_play_invalid_order_feedback()


func _select_building(index: int) -> void:
	if index < 0 or index >= _building_options.size():
		return

	_selected_index = index
	_apply_selected_building()
	command_grid.set_selected_command(_get_building_command_id(_selected_index))


func _apply_selected_building() -> void:
	if _building_options.is_empty():
		placement_preview.set_display_enabled(false)
		_update_hud()
		return

	var building: Dictionary = _get_selected_building()
	var footprint: Vector2i = building["footprint"]
	var size: Vector3 = building["size"]
	var color: Color = building["color"]
	placement_preview.set_footprint(footprint)
	placement_preview.set_building_preview(size, color)
	_update_hud()


func _try_issue_build_order() -> void:
	if _interaction_state != InteractionState.BUILDING:
		return

	if _building_options.is_empty():
		_play_invalid_order_feedback()
		return

	if _selected_unit == null:
		_play_invalid_order_feedback()
		return

	var building: Dictionary = _get_selected_building()
	var anchor_cell := placement_preview.current_cell
	var footprint: Vector2i = building["footprint"]
	var should_queue := Input.is_key_pressed(KEY_SHIFT)
	if should_queue and _selected_unit.get_action_queue_size() >= RtsUnit.MAX_ACTION_QUEUE_SIZE:
		_play_invalid_order_feedback()
		return

	if not map_grid.can_place(anchor_cell, footprint):
		_play_invalid_order_feedback()
		return

	var worker_target_cell := _find_worker_target_cell(anchor_cell, footprint)
	if not map_grid.is_cell_in_bounds(worker_target_cell):
		_play_invalid_order_feedback()
		return

	var queued_ghost: Node3D = _create_queued_building_ghost(building, anchor_cell)
	if not map_grid.occupy(anchor_cell, footprint, queued_ghost):
		queued_ghost.queue_free()
		_play_invalid_order_feedback()
		return

	_play_one_shot_sound(BUILDING_PLACEMENT_SOUND)

	var build_order := func() -> void:
		_complete_build_order(building, anchor_cell, queued_ghost)

	var cancel_build_order := func() -> void:
		_cancel_queued_building(anchor_cell, footprint, queued_ghost)
	var action_model := _get_building_model_data(building)

	var worker_target_position := map_grid.cell_to_world(worker_target_cell, _selected_unit.global_position.y)
	if not _selected_unit.issue_move_order_with_callback(
		worker_target_position,
		build_order,
		should_queue,
		String(building["name"]),
		building["color"],
		cancel_build_order,
		action_model
	):
		map_grid.release(anchor_cell, footprint)
		queued_ghost.queue_free()
		_play_invalid_order_feedback()


func _try_issue_destroy_order() -> void:
	if _interaction_state != InteractionState.DESTROYING:
		return

	if _selected_unit == null:
		_play_invalid_order_feedback()
		return

	var building_node := _get_building_on_current_cell()
	if building_node == null \
		or not building_node.has_meta("grid_anchor_cell") \
		or not building_node.has_meta("grid_footprint"):
		_play_invalid_order_feedback()
		return

	var anchor_cell: Vector2i = building_node.get_meta("grid_anchor_cell")
	var footprint: Vector2i = building_node.get_meta("grid_footprint")
	var worker_target_cell := _find_worker_target_cell(anchor_cell, footprint)
	if not map_grid.is_cell_in_bounds(worker_target_cell):
		_play_invalid_order_feedback()
		return

	_add_destroy_marker(building_node)

	var destroy_order := func() -> void:
		_complete_destroy_order(building_node, anchor_cell, footprint)

	var worker_target_position := map_grid.cell_to_world(worker_target_cell, _selected_unit.global_position.y)
	if _selected_unit.issue_move_order_with_callback(worker_target_position, destroy_order):
		_set_interaction_state(InteractionState.SELECTING)
	else:
		_remove_destroy_marker(building_node)
		_play_invalid_order_feedback()


func _complete_build_order(building: Dictionary, anchor_cell: Vector2i, queued_ghost: Node3D) -> void:
	var footprint: Vector2i = building["footprint"]
	map_grid.release(anchor_cell, footprint)

	_play_one_shot_sound(BUILDING_CONSTRUCTION_SOUND)
	_start_construction_loop(queued_ghost)

	if is_instance_valid(queued_ghost):
		queued_ghost.queue_free()

	if not map_grid.can_place(anchor_cell, footprint):
		if _selected_unit != null:
			_play_invalid_order_feedback()
		return

	_place_building(building, anchor_cell)
	_play_one_shot_sound(BUILDING_COMPLETE_SOUND)


func _cancel_queued_building(anchor_cell: Vector2i, footprint: Vector2i, queued_ghost: Node3D) -> void:
	map_grid.release(anchor_cell, footprint)
	if is_instance_valid(queued_ghost):
		queued_ghost.queue_free()


func _complete_destroy_order(building_node: Node, anchor_cell: Vector2i, footprint: Vector2i) -> void:
	if not is_instance_valid(building_node):
		return

	if building_node.has_meta("grid_anchor_cell") and building_node.get_meta("grid_anchor_cell") != anchor_cell:
		return

	_delete_building(building_node, anchor_cell, footprint)


func _place_building(building: Dictionary, anchor_cell: Vector2i) -> void:
	var footprint: Vector2i = building["footprint"]
	var size: Vector3 = building["size"]
	var building_body := _create_building_body(building)
	var building_name := String(building["name"])
	building_body.set_meta("building_id", String(building.get("id", building_name.to_snake_case())))
	building_body.set_meta("building_name", building_name)
	building_body.set_meta("cost", building.get("cost", {}))
	building_body.set_meta("stats", building.get("stats", {}))
	building_body.set_meta("building_size", size)
	building_body.set_meta("building_color", building["color"])
	building_body.set_meta("portrait_camera_offset", building["portrait_camera_offset"])
	building_body.set_meta("portrait_camera_target", building["portrait_camera_target"])
	building_body.set_meta("portrait_camera_fov", building["portrait_camera_fov"])
	building_body.set_meta("grid_anchor_cell", anchor_cell)
	building_body.set_meta("grid_footprint", footprint)
	building_body.global_position = map_grid.footprint_to_world_center(
		anchor_cell,
		footprint,
		size.y * 0.5
	)
	buildings_root.add_child(building_body)
	map_grid.occupy(anchor_cell, footprint, building_body)
	_update_selection_ring()
	_update_hud()


func _create_queued_building_ghost(building: Dictionary, anchor_cell: Vector2i) -> Node3D:
	var footprint: Vector2i = building["footprint"]
	var size: Vector3 = building["size"]
	var ghost := Node3D.new()
	ghost.name = "%s Queued" % String(building["name"])
	ghost.set_meta("queued_building_name", String(building["name"]))
	ghost.set_meta("grid_anchor_cell", anchor_cell)
	ghost.set_meta("grid_footprint", footprint)
	ghost.global_position = map_grid.footprint_to_world_center(anchor_cell, footprint, size.y * 0.5)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _create_queued_building_material(building["color"])
	mesh_instance.mesh = box_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(mesh_instance)

	_queued_buildings_root.add_child(ghost)
	return ghost


func _start_construction_loop(queued_ghost: Node3D) -> void:
	if not is_instance_valid(queued_ghost) or CONSTRUCTION_LOOP_SOUNDS.is_empty():
		return

	var loop_player := AudioStreamPlayer.new()
	loop_player.name = "ConstructionLoopPlayer"
	loop_player.stream = CONSTRUCTION_LOOP_SOUNDS[_building_audio_rng.randi_range(0, CONSTRUCTION_LOOP_SOUNDS.size() - 1)]
	loop_player.volume_db = QUIET_CONSTRUCTION_LOOP_VOLUME_DB
	loop_player.finished.connect(_on_construction_loop_finished.bind(loop_player))
	queued_ghost.add_child(loop_player)
	loop_player.play()


func _on_construction_loop_finished(loop_player: AudioStreamPlayer) -> void:
	if is_instance_valid(loop_player):
		loop_player.play()


func _find_worker_target_cell(anchor_cell: Vector2i, footprint: Vector2i) -> Vector2i:
	var candidate_cells: Array[Vector2i] = []
	for x in range(anchor_cell.x, anchor_cell.x + footprint.x):
		candidate_cells.append(Vector2i(x, anchor_cell.y - 1))
		candidate_cells.append(Vector2i(x, anchor_cell.y + footprint.y))

	for y in range(anchor_cell.y, anchor_cell.y + footprint.y):
		candidate_cells.append(Vector2i(anchor_cell.x - 1, y))
		candidate_cells.append(Vector2i(anchor_cell.x + footprint.x, y))

	var unit_cell := _selected_unit.get_current_cell()
	var best_cell := Vector2i(-1, -1)
	var best_path_length := INF
	for candidate_cell in candidate_cells:
		if not map_grid.is_cell_walkable(candidate_cell):
			continue

		var path := map_grid.find_path(unit_cell, candidate_cell)
		if path.is_empty() and unit_cell != candidate_cell:
			continue

		var path_length := float(path.size())
		if path_length < best_path_length:
			best_path_length = path_length
			best_cell = candidate_cell

	return best_cell


func _issue_selected_unit_move_order() -> void:
	var target_cell := placement_preview.current_cell
	if map_grid.is_cell_walkable(target_cell):
		_selected_unit.issue_move_order(placement_preview.current_world_point)
	else:
		_play_invalid_order_feedback(false)


func _delete_building(building_node: Node, anchor_cell: Vector2i, footprint: Vector2i) -> void:
	if building_node == _selected_placed_building:
		_selected_placed_building = null
		selection_panel.clear_selection()

	_remove_destroy_marker(building_node)
	map_grid.release(anchor_cell, footprint)
	building_node.queue_free()
	_update_selection_ring()
	_update_hud()


func _get_building_on_current_cell() -> Node:
	var occupant: Variant = map_grid.get_occupant(placement_preview.current_cell)
	if occupant != null and occupant is Node and occupant.has_meta("building_name"):
		return occupant

	return null


func _get_unit_on_current_cell() -> RtsUnit:
	for unit in get_tree().get_nodes_in_group("rts_units"):
		if unit is RtsUnit and unit.get_current_cell() == placement_preview.current_cell:
			return unit

	return null


func _select_placed_building(building_node: Node) -> void:
	_disconnect_queue_display_unit()
	_selected_placed_building = building_node
	_selected_unit = null
	command_grid.set_commands([])
	command_grid.set_selected_command("")
	if _interaction_state == InteractionState.BUILDING:
		_set_interaction_state(InteractionState.SELECTING)
	_update_selection_ring()
	_update_hud()
	selection_panel.show_building(building_node)


func _select_unit(unit: RtsUnit) -> void:
	_disconnect_queue_display_unit()
	_selected_unit = unit
	_selected_placed_building = null
	_queue_display_unit = unit
	_queue_display_unit.action_queue_changed.connect(_on_selected_unit_action_queue_changed)
	command_grid.set_commands(unit.get_command_definitions())
	_filter_building_options_for_unit(unit)
	_sync_building_command_menu()
	command_grid.set_selected_command("")
	_update_selection_ring()
	_update_hud()
	selection_panel.show_unit(unit)
	selection_panel.show_action_queue(unit.get_action_queue())
	unit.play_selection_voice()


func _select_scout_unit() -> void:
	var scout := _get_unit_by_name("Scout")
	if scout == null:
		_play_invalid_order_feedback(false)
		return

	_select_unit(scout)


func _select_scout_unit_from_hotkey() -> void:
	var previous_tap_msec := _last_scout_hotkey_msec
	var now_msec := Time.get_ticks_msec()
	_last_scout_hotkey_msec = now_msec

	var scout := _get_unit_by_name("Scout")
	if scout == null:
		_play_invalid_order_feedback(false)
		return

	_select_unit(scout)
	if now_msec - previous_tap_msec <= DOUBLE_TAP_WINDOW_MSEC:
		_focus_camera_on_unit(scout)


func _get_unit_by_name(unit_name: String) -> RtsUnit:
	for unit in get_tree().get_nodes_in_group("rts_units"):
		if unit is RtsUnit and unit.unit_name == unit_name:
			return unit

	return null


func _on_selection_portrait_double_clicked() -> void:
	if _selected_unit != null:
		_focus_camera_on_unit(_selected_unit)


func _focus_camera_on_unit(unit: RtsUnit) -> void:
	if camera_rig.has_method("center_on_world_position"):
		camera_rig.call("center_on_world_position", unit.global_position)


func _clear_selection() -> void:
	_disconnect_queue_display_unit()
	_selected_placed_building = null
	_selected_unit = null
	_building_options.clear()
	command_grid.set_commands([])
	command_grid.set_selected_command("")
	_selection_ring.visible = false
	_update_hud()
	selection_panel.clear_selection()


func _disconnect_queue_display_unit() -> void:
	if _queue_display_unit != null \
		and is_instance_valid(_queue_display_unit) \
		and _queue_display_unit.action_queue_changed.is_connected(_on_selected_unit_action_queue_changed):
		_queue_display_unit.action_queue_changed.disconnect(_on_selected_unit_action_queue_changed)

	_queue_display_unit = null


func _on_selected_unit_action_queue_changed(action_queue: Array[Dictionary]) -> void:
	selection_panel.show_action_queue(action_queue)


func _on_command_pressed(command_id: String) -> void:
	if command_id.begins_with(COMMAND_BUILDING_PREFIX):
		_select_building(int(command_id.trim_prefix(COMMAND_BUILDING_PREFIX)))
		_try_enter_building_mode()
		return

	if command_id == COMMAND_BUILD:
		_try_enter_building_mode()
	elif command_id == COMMAND_DESTROY:
		_try_enter_destroy_mode()


func _sync_building_command_menu() -> void:
	var commands: Array[Dictionary] = []
	var visible_building_count := mini(_building_options.size(), MAX_BUILD_MENU_BUILDINGS)
	for index in range(visible_building_count):
		var building: Dictionary = _building_options[index]
		commands.append({
			"id": _get_building_command_id(index),
			"label": "",
			"slot": index,
			"tooltip": String(building["name"]),
			"model": _get_building_model_data(building)
		})

	commands.append({
		"id": "back",
		"label": "Back",
		"slot": BUILD_MENU_BACK_SLOT,
		"menu": CommandGrid.ROOT_MENU_ID,
		"tooltip": "Back"
	})
	command_grid.set_menu(BUILDINGS_MENU_ID, commands)


func _load_building_data() -> void:
	var loaded_buildings := GameData.load_building_definitions(building_data_directory)
	if loaded_buildings.is_empty():
		push_warning("No building definitions were loaded from %s." % building_data_directory)
		return

	_all_building_options = loaded_buildings
	_building_options.clear()
	_selected_index = 0


func _filter_building_options_for_unit(unit: RtsUnit) -> void:
	_building_options.clear()
	var available_building_ids := unit.get_available_building_ids()
	if available_building_ids.is_empty():
		_selected_index = 0
		return

	for building_id in available_building_ids:
		var building := _get_building_option_by_id(building_id)
		if not building.is_empty():
			_building_options.append(building)

	if _building_options.size() > MAX_BUILD_MENU_BUILDINGS:
		push_warning(
			"%s can build %d buildings, but the current 3x3 build menu only supports %d because the final slot is reserved for Back. Extra buildings are hidden until paging or categories are implemented." %
			[unit.unit_name, _building_options.size(), MAX_BUILD_MENU_BUILDINGS]
		)

	_selected_index = clampi(_selected_index, 0, max(0, _building_options.size() - 1))
	_apply_selected_building()


func _get_building_option_by_id(building_id: String) -> Dictionary:
	for building in _all_building_options:
		if String(building.get("id", "")) == building_id:
			return building

	push_warning("Building '%s' is listed by the selected unit but no matching building JSON was loaded." % building_id)
	return {}


func _get_building_command_id(index: int) -> String:
	return "%s%d" % [COMMAND_BUILDING_PREFIX, index]


func _get_building_model_data(building: Dictionary) -> Dictionary:
	return {
		"type": "box",
		"size": building["size"],
		"color": building["color"],
		"camera_offset": building["portrait_camera_offset"],
		"camera_target": building["portrait_camera_target"],
		"camera_fov": building["portrait_camera_fov"]
	}


func _create_selection_ring() -> void:
	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "BuildingSelectionRing"

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 1.0, 0.28, 1.0)
	material.no_depth_test = true
	_selection_ring.material_override = material
	_selection_ring.visible = false

	buildings_root.add_child(_selection_ring)


func _create_queued_buildings_root() -> void:
	_queued_buildings_root = Node3D.new()
	_queued_buildings_root.name = "QueuedBuildings"
	buildings_root.add_child(_queued_buildings_root)


func _add_destroy_marker(building_node: Node) -> void:
	if building_node.has_meta(DESTROY_MARKER_META):
		var existing_marker: Variant = building_node.get_meta(DESTROY_MARKER_META)
		if existing_marker is Node and is_instance_valid(existing_marker):
			return

	var marker := MeshInstance3D.new()
	marker.name = "QueuedDestroyMarker"
	marker.mesh = _create_destroy_marker_mesh()
	marker.material_override = _create_destroy_marker_material()
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.position = Vector3(0.0, _get_building_marker_height(building_node), 0.0)
	building_node.add_child(marker)
	building_node.set_meta(DESTROY_MARKER_META, marker)


func _remove_destroy_marker(building_node: Node) -> void:
	if not is_instance_valid(building_node) or not building_node.has_meta(DESTROY_MARKER_META):
		return

	var marker: Variant = building_node.get_meta(DESTROY_MARKER_META)
	building_node.remove_meta(DESTROY_MARKER_META)
	if marker is Node and is_instance_valid(marker):
		marker.queue_free()


func _get_building_marker_height(building_node: Node) -> float:
	var building_size: Vector3 = building_node.get_meta("building_size", Vector3(2.0, 2.0, 2.0))
	return (building_size.y * 0.5) + 1.1


func _create_destroy_marker_mesh() -> ImmediateMesh:
	var marker_mesh := ImmediateMesh.new()
	marker_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_marker_bar(marker_mesh, deg_to_rad(45.0))
	_add_marker_bar(marker_mesh, deg_to_rad(-45.0))

	marker_mesh.surface_end()
	return marker_mesh


func _add_marker_bar(marker_mesh: ImmediateMesh, angle: float) -> void:
	var half_length := 1.15
	var half_width := 0.16
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-direction.z, 0.0, direction.x)
	var points := [
		(direction * -half_length) + (side * -half_width),
		(direction * half_length) + (side * -half_width),
		(direction * half_length) + (side * half_width),
		(direction * -half_length) + (side * half_width)
	]

	marker_mesh.surface_add_vertex(points[0])
	marker_mesh.surface_add_vertex(points[1])
	marker_mesh.surface_add_vertex(points[2])
	marker_mesh.surface_add_vertex(points[0])
	marker_mesh.surface_add_vertex(points[2])
	marker_mesh.surface_add_vertex(points[3])


func _create_destroy_marker_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.08, 0.06, 1.0)
	material.no_depth_test = true
	return material


func _create_interface_audio_player() -> void:
	_interface_audio_player = AudioStreamPlayer.new()
	_interface_audio_player.name = "InterfaceAudioPlayer"
	_interface_audio_player.stream = ERROR_SOUND
	add_child(_interface_audio_player)


func _play_one_shot_sound(sound: AudioStream, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = sound
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _play_invalid_order_feedback(include_unit_warning: bool = true) -> void:
	_interface_audio_player.stop()
	_interface_audio_player.play()

	if include_unit_warning and _selected_unit != null:
		_selected_unit.play_cannot_build_there_voice()


func _update_selection_ring() -> void:
	if _selected_unit != null:
		_selection_ring.mesh = _create_selection_ring_mesh(map_grid.cell_size * 0.35)
		_selection_ring.global_position = _selected_unit.global_position + Vector3.UP * 0.12
		_selection_ring.visible = true
		return

	if _selected_placed_building == null \
		or not _selected_placed_building.has_meta("grid_anchor_cell") \
		or not _selected_placed_building.has_meta("grid_footprint"):
		_clear_selection()
		return

	var anchor_cell: Vector2i = _selected_placed_building.get_meta("grid_anchor_cell")
	var footprint: Vector2i = _selected_placed_building.get_meta("grid_footprint")
	var radius := maxf(float(footprint.x), float(footprint.y)) * map_grid.cell_size * 0.62
	_selection_ring.mesh = _create_selection_ring_mesh(radius)
	_selection_ring.global_position = map_grid.footprint_to_world_center(anchor_cell, footprint, 0.12)
	_selection_ring.visible = true


func _create_selection_ring_mesh(radius: float) -> ImmediateMesh:
	var ring_mesh := ImmediateMesh.new()
	ring_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	for index in range(SELECTION_RING_SEGMENTS + 1):
		var angle := TAU * float(index) / float(SELECTION_RING_SEGMENTS)
		ring_mesh.surface_add_vertex(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))

	ring_mesh.surface_end()
	return ring_mesh


func _create_building_body(building: Dictionary) -> StaticBody3D:
	var building_body := StaticBody3D.new()
	var building_name := String(building["name"])
	var size: Vector3 = building["size"]
	var color: Color = building["color"]
	building_body.name = building_name

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _create_building_material(color)
	mesh_instance.mesh = box_mesh
	building_body.add_child(mesh_instance)

	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision_shape.shape = box_shape
	building_body.add_child(collision_shape)

	return building_body


func _create_building_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material


func _create_queued_building_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.34)
	material.roughness = 0.8
	material.no_depth_test = true
	return material


func _update_hud() -> void:
	var building_name := "None"
	if not _building_options.is_empty():
		building_name = String(_get_selected_building()["name"])

	if _interaction_state == InteractionState.BUILDING:
		var worker_status := "Worker selected" if _selected_unit != null else "Select a worker first"
		hud_label.text = "Mode: Building  |  %s  |  Build: %s  |  LMB build  Shift+LMB queue  B/Esc selecting" % [worker_status, building_name]
	elif _interaction_state == InteractionState.DESTROYING:
		var worker_status := "Worker selected" if _selected_unit != null else "Select a worker first"
		hud_label.text = "Mode: Destroy  |  %s  |  LMB target building  V/Esc selecting" % worker_status
	else:
		hud_label.text = "Mode: Selecting  |  B building mode  V destroy mode  |  LMB select  RMB move unit"


func _get_selected_building() -> Dictionary:
	if _building_options.is_empty():
		return {}

	return _building_options[_selected_index]
