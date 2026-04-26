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
const COMMAND_MAP_GEOMETRY_PREFIX := "map_geometry:"
const COMMAND_MAP_TAG_PREFIX := "map_tag:"
const BUILDINGS_MENU_ID := "buildings"
const MAP_GEOMETRY_MENU_ID := "map_geometry"
const MAP_TAG_MENU_ID := "map_tags"
const QUIET_CONSTRUCTION_LOOP_VOLUME_DB := -18.0
const DESTROY_MARKER_META := "destroy_marker"
const DOUBLE_TAP_WINDOW_MSEC := 350
const BUILD_MENU_BACK_SLOT := Vector2i(2, 2)
const MAX_BUILD_MENU_BUILDINGS := 8
const ACTOR_TYPE_UNIT := "unit"
const ACTOR_TYPE_ENEMY := "enemy"
const COLLISION_LAYER_BLOCKS_UNITS := 1 << 1
const COLLISION_LAYER_BLOCKS_ENEMIES := 1 << 2
const MAINTENANCE_INTERVAL := 0.1
const DEBUG_TEST_DUMMY_DATA_PATH := "res://data/enemies/test_dummy.json"
const ATTACK_RANGE_RING_HEIGHT := 0.1
const MapGeometrySceneScript = preload("res://scripts/systems/map_geometry.gd")
const MAP_TAG_SPAWNER := "spawner"
const MAP_TAG_END_POINT := "end_point"
const MAP_TAG_ACTION_REMOVE_SPAWNER := "remove_spawner"
const MAP_TAG_ACTION_REMOVE_END_POINT := "remove_end_point"
const MAP_TAG_ACTION_CLEAR := "clear"
const HISTORY_ACTION_PLACE_GEOMETRY := "place_geometry"
const HISTORY_ACTION_DELETE_GEOMETRY := "delete_geometry"
const HISTORY_ACTION_TAG_GEOMETRY := "tag_geometry"
const HISTORY_ACTION_BATCH := "batch"

@export var grid_path: NodePath
@export var camera_rig_path: NodePath
@export var preview_path: NodePath
@export var selection_panel_path: NodePath
@export var command_grid_path: NodePath
@export var buildings_root_path: NodePath
@export var map_geometry_root_path: NodePath
@export var enemies_root_path: NodePath
@export var building_data_directory := "res://data/buildings"
@export var map_geometry_data_directory := "res://data/map_geometry"

@onready var map_grid: MapGrid = get_node(grid_path)
@onready var camera_rig: Node = get_node(camera_rig_path)
@onready var placement_preview: GridPlacementPreview = get_node(preview_path)
@onready var selection_panel: SelectionPanel = get_node(selection_panel_path)
@onready var command_grid: CommandGrid = get_node(command_grid_path)
@onready var buildings_root: Node3D = get_node(buildings_root_path)
@onready var map_geometry_root: Node3D = get_node(map_geometry_root_path)
@onready var enemies_root: Node3D = get_node(enemies_root_path)

const SELECTION_RING_SEGMENTS := 96

enum InteractionState {
	SELECTING,
	BUILDING,
	MAPPING,
	TAGGING,
	DESTROYING
}

var _building_options: Array[Dictionary] = []
var _selected_index := 0
var _selected_placed_building: Node = null
var _selected_map_geometry: Node = null
var _selected_unit: RtsUnit = null
var _selected_enemy: RtsEnemy = null
var _selection_ring: MeshInstance3D
var _attack_range_ring: MeshInstance3D
var _tag_hover_ring: MeshInstance3D
var _interface_audio_player: AudioStreamPlayer
var _interaction_state := InteractionState.SELECTING
var _queued_buildings_root: Node3D
var _building_audio_rng := RandomNumberGenerator.new()
var _last_scout_hotkey_msec := 0
var _queue_display_unit: RtsUnit = null
var _all_building_options: Array[Dictionary] = []
var _map_geometry_options: Array[Dictionary] = []
var _selected_map_geometry_index := 0
var _selected_map_tag_action := ""
var _last_painted_map_geometry_cell := Vector2i(-1, -1)
var _active_paint_history_actions: Array[Dictionary] = []
var _mapping_undo_stack: Array[Dictionary] = []
var _mapping_redo_stack: Array[Dictionary] = []
var _maintenance_timer := 0.0


func _ready() -> void:
	_building_audio_rng.randomize()
	_load_building_data()
	_load_map_geometry_data()
	_create_interface_audio_player()
	_create_selection_ring()
	_create_attack_range_ring()
	_create_tag_hover_ring()
	_create_queued_buildings_root()
	command_grid.command_pressed.connect(_on_command_pressed)
	selection_panel.portrait_double_clicked.connect(_on_selection_portrait_double_clicked)
	command_grid.set_commands([])
	_sync_building_command_menu()
	_sync_map_geometry_command_menu()
	_sync_map_tag_command_menu()
	_apply_selected_building()
	_set_interaction_state(InteractionState.SELECTING)


func _process(delta: float) -> void:
	if _selected_unit != null or _selected_enemy != null or _selected_map_geometry != null:
		_update_selection_ring()
	_update_attack_range_ring()
	_update_tag_hover_ring()

	_maintenance_timer -= delta
	if _maintenance_timer > 0.0:
		return

	_maintenance_timer = MAINTENANCE_INTERVAL
	_remove_destroyed_buildings()
	_refresh_selection_health_display()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _is_mapping_history_hotkey_enabled() and event.ctrl_pressed and event.keycode == KEY_Z:
			if event.shift_pressed:
				_redo_mapping_action()
			else:
				_undo_mapping_action()
			return

		match event.keycode:
			KEY_B:
				if _interaction_state == InteractionState.BUILDING:
					_set_interaction_state(InteractionState.SELECTING)
					return
			KEY_V:
				if _interaction_state == InteractionState.DESTROYING:
					_set_interaction_state(InteractionState.SELECTING)
					return
			KEY_F1:
				_select_scout_unit_from_hotkey()
				return
			KEY_F2:
				_spawn_test_dummy_at_mouse()
				return
			KEY_ESCAPE:
				_set_interaction_state(InteractionState.SELECTING)
				return

		if command_grid.handle_key_event(event):
			return

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		_last_painted_map_geometry_cell = Vector2i(-1, -1)
		_active_paint_history_actions.clear()
		_handle_left_click()

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and not event.pressed:
		_last_painted_map_geometry_cell = Vector2i(-1, -1)
		_commit_active_paint_history()

	if event is InputEventMouseMotion \
		and _interaction_state == InteractionState.MAPPING \
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		and Input.is_key_pressed(KEY_SHIFT):
		_try_paint_map_geometry()

	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_RIGHT \
		and event.pressed:
		_handle_right_click()


func _handle_left_click() -> void:
	if _interaction_state == InteractionState.BUILDING:
		_try_issue_build_order()
		return

	if _interaction_state == InteractionState.MAPPING:
		_try_place_map_geometry()
		return

	if _interaction_state == InteractionState.TAGGING:
		_try_apply_map_geometry_tag()
		return

	if _interaction_state == InteractionState.DESTROYING:
		_try_issue_destroy_order()
		return

	var hovered_building := _get_building_on_current_cell()
	if hovered_building != null:
		_select_placed_building(hovered_building)
		return

	var hovered_map_geometry := _get_map_geometry_on_current_cell()
	if hovered_map_geometry != null:
		_select_map_geometry_node(hovered_map_geometry)
		return

	var hovered_unit := _get_unit_on_current_cell()
	if hovered_unit != null:
		_select_unit(hovered_unit)
		return

	var hovered_enemy := _get_enemy_on_current_cell()
	if hovered_enemy != null:
		_select_enemy(hovered_enemy)
		return

	_clear_selection()


func _handle_right_click() -> void:
	if _selected_unit != null:
		_issue_selected_unit_move_order()


func _set_interaction_state(new_state: int) -> void:
	if new_state == InteractionState.BUILDING and _building_options.is_empty():
		_play_invalid_order_feedback()
		new_state = InteractionState.SELECTING

	if new_state == InteractionState.MAPPING and _map_geometry_options.is_empty():
		_play_invalid_order_feedback()
		new_state = InteractionState.SELECTING

	if new_state == InteractionState.TAGGING and _selected_map_tag_action.is_empty():
		_play_invalid_order_feedback()
		new_state = InteractionState.SELECTING

	_interaction_state = new_state as InteractionState
	placement_preview.set_display_enabled(
		_interaction_state == InteractionState.BUILDING
		or _interaction_state == InteractionState.MAPPING
	)
	placement_preview.set_allows_map_geometry_stack(_interaction_state == InteractionState.MAPPING)
	if _selected_unit != null:
		if _interaction_state == InteractionState.BUILDING:
			command_grid.show_menu(BUILDINGS_MENU_ID)
			command_grid.set_selected_command(_get_building_command_id(_selected_index))
		elif _interaction_state == InteractionState.MAPPING:
			command_grid.show_menu(MAP_GEOMETRY_MENU_ID)
			command_grid.set_selected_command(_get_map_geometry_command_id(_selected_map_geometry_index))
		elif _interaction_state == InteractionState.TAGGING:
			command_grid.show_menu(MAP_TAG_MENU_ID)
			command_grid.set_selected_command(_get_map_tag_command_id(_selected_map_tag_action))
		elif _interaction_state == InteractionState.DESTROYING:
			command_grid.show_menu(CommandGrid.ROOT_MENU_ID)
			command_grid.set_selected_command(COMMAND_DESTROY)
		else:
			command_grid.show_menu(CommandGrid.ROOT_MENU_ID)
			command_grid.set_selected_command("")


func _toggle_building_mode() -> void:
	if _interaction_state == InteractionState.BUILDING or _interaction_state == InteractionState.MAPPING:
		_set_interaction_state(InteractionState.SELECTING)
	else:
		_try_enter_building_mode()


func _try_enter_building_mode() -> void:
	if _selected_unit != null:
		_set_interaction_state(InteractionState.BUILDING)
	else:
		_play_invalid_order_feedback()


func _try_enter_mapping_mode() -> void:
	if _selected_unit != null:
		_set_interaction_state(InteractionState.MAPPING)
	else:
		_play_invalid_order_feedback()


func _is_mapping_history_hotkey_enabled() -> bool:
	return _selected_unit != null \
		and (
			_interaction_state == InteractionState.MAPPING
			or _interaction_state == InteractionState.TAGGING
		)


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


func _select_map_geometry(index: int) -> void:
	if index < 0 or index >= _map_geometry_options.size():
		return

	_selected_map_geometry_index = index
	_apply_selected_map_geometry()
	command_grid.set_selected_command(_get_map_geometry_command_id(_selected_map_geometry_index))


func _apply_selected_building() -> void:
	if _building_options.is_empty():
		placement_preview.set_display_enabled(false)
		return

	var building: Dictionary = _get_selected_building()
	var footprint: Vector2i = building["footprint"]
	var size: Vector3 = building["size"]
	var color: Color = building["color"]
	placement_preview.set_footprint(footprint)
	placement_preview.set_building_preview(size, color)


func _apply_selected_map_geometry() -> void:
	if _map_geometry_options.is_empty():
		placement_preview.set_display_enabled(false)
		return

	var geometry: Dictionary = _get_selected_map_geometry()
	placement_preview.set_footprint(geometry["footprint"])
	placement_preview.set_building_preview(geometry["size"], geometry["color"], String(geometry.get("shape", "box")))


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

	var worker_target_position := _get_worker_target_position(building, anchor_cell, footprint, worker_target_cell)
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
	if building_node == null:
		var map_geometry := _get_map_geometry_on_current_cell()
		if map_geometry != null \
			and map_geometry.has_meta("grid_anchor_cell") \
			and map_geometry.has_meta("grid_footprint"):
			_delete_map_geometry(
				map_geometry,
				map_geometry.get_meta("grid_anchor_cell"),
				map_geometry.get_meta("grid_footprint"),
				true
			)
			return

		_play_invalid_order_feedback()
		return

	if not building_node.has_meta("grid_anchor_cell") \
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


func _try_place_map_geometry() -> void:
	if _interaction_state != InteractionState.MAPPING:
		return

	if Input.is_key_pressed(KEY_SHIFT):
		_try_paint_map_geometry()
		return

	_place_selected_map_geometry_at_current_cell()


func _try_paint_map_geometry() -> void:
	if _interaction_state != InteractionState.MAPPING:
		return

	if placement_preview.current_cell == _last_painted_map_geometry_cell:
		return

	var placed_action := _place_selected_map_geometry_at_current_cell(false, false)
	if not placed_action.is_empty():
		_active_paint_history_actions.append(placed_action)
		_last_painted_map_geometry_cell = placement_preview.current_cell


func _place_selected_map_geometry_at_current_cell(play_invalid_feedback: bool = true, record_history: bool = true) -> Dictionary:
	if _map_geometry_options.is_empty():
		if play_invalid_feedback:
			_play_invalid_order_feedback()
		return {}

	var geometry := _get_selected_map_geometry()
	var anchor_cell := placement_preview.current_cell
	var footprint: Vector2i = geometry["footprint"]
	if not _can_place_map_geometry(anchor_cell, footprint):
		if play_invalid_feedback:
			_play_invalid_order_feedback()
		return {}

	var map_geometry := _place_map_geometry(geometry, anchor_cell, _get_map_geometry_stack_height(anchor_cell, footprint))
	var action := {
		"type": HISTORY_ACTION_PLACE_GEOMETRY,
		"state": _capture_map_geometry_state(map_geometry)
	}
	if record_history:
		_push_mapping_history(action)
	_play_one_shot_sound(BUILDING_PLACEMENT_SOUND)
	return action


func _try_apply_map_geometry_tag() -> void:
	if _interaction_state != InteractionState.TAGGING:
		return

	var map_geometry := _get_map_geometry_on_current_cell()
	if map_geometry == null:
		_play_invalid_order_feedback(false)
		return

	var before_state := _capture_map_geometry_state(map_geometry)
	var before_tags := PackedStringArray(map_geometry.get_meta("geometry_tags", []))
	match _selected_map_tag_action:
		MAP_TAG_SPAWNER:
			if map_geometry.has_method("add_tag"):
				map_geometry.call("add_tag", MAP_TAG_SPAWNER)
		MAP_TAG_END_POINT:
			if map_geometry.has_method("add_tag"):
				map_geometry.call("add_tag", MAP_TAG_END_POINT)
		MAP_TAG_ACTION_REMOVE_SPAWNER:
			if map_geometry.has_method("remove_tag"):
				map_geometry.call("remove_tag", MAP_TAG_SPAWNER)
		MAP_TAG_ACTION_REMOVE_END_POINT:
			if map_geometry.has_method("remove_tag"):
				map_geometry.call("remove_tag", MAP_TAG_END_POINT)
		MAP_TAG_ACTION_CLEAR:
			if map_geometry.has_method("clear_tags"):
				map_geometry.call("clear_tags")
		_:
			_play_invalid_order_feedback(false)
			return

	var after_tags := PackedStringArray(map_geometry.get_meta("geometry_tags", []))
	if before_tags != after_tags:
		_push_mapping_history({
			"type": HISTORY_ACTION_TAG_GEOMETRY,
			"target_state": before_state,
			"before_tags": before_tags,
			"after_tags": after_tags
		})

	if map_geometry == _selected_map_geometry:
		selection_panel.show_map_geometry(map_geometry)

	_update_tag_hover_ring()


func _place_map_geometry(geometry: Dictionary, anchor_cell: Vector2i, base_height: float = 0.0) -> Node:
	var map_geometry := MapGeometrySceneScript.new()
	map_geometry.name = String(geometry["name"]).to_pascal_case()
	map_geometry.grid_path = NodePath("../../Grid")
	map_geometry.geometry_id = String(geometry.get("id", ""))
	map_geometry.display_name = String(geometry["name"])
	map_geometry.shape = String(geometry.get("shape", "box"))
	map_geometry.tags = PackedStringArray(geometry.get("tags", []))
	map_geometry.metadata = geometry.get("metadata", {})
	map_geometry.anchor_cell = anchor_cell
	map_geometry.footprint = geometry["footprint"]
	map_geometry.pathable = bool(geometry.get("pathable", false))
	map_geometry.size = geometry["size"]
	map_geometry.color = geometry["color"]
	map_geometry.rotation_steps = int(geometry.get("rotation_steps", 0))
	map_geometry.base_height = base_height
	map_geometry.registers_grid_occupancy = is_zero_approx(base_height)
	map_geometry_root.add_child(map_geometry)
	return map_geometry


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
	var building_id := String(building.get("id", building_name.to_snake_case()))
	var building_stats: Dictionary = building.get("stats", {})
	var max_health := int(building_stats.get("max_health", 0))
	building_body.add_to_group("rts_buildings")
	building_body.add_to_group("rts_building_%s" % building_id)
	building_body.set_meta("building_id", building_id)
	building_body.set_meta("building_name", building_name)
	building_body.set_meta("cost", building.get("cost", {}))
	building_body.set_meta("stats", building.get("stats", {}))
	building_body.set_meta("max_health", max_health)
	building_body.set_meta("current_health", max_health)
	building_body.set_meta("damage", int(building_stats.get("damage", 0)))
	building_body.set_meta("armor", int(building_stats.get("armor", 0)))
	building_body.set_meta("attack_type", String(building_stats.get("attack_type", "melee")))
	building_body.set_meta("attack_speed", float(building_stats.get("attack_speed", 0.0)))
	building_body.set_meta("attack_range", float(building_stats.get("attack_range", 0.0)))
	building_body.set_meta("attack_cooldown", float(building_stats.get("attack_cooldown", 0.0)))
	building_body.set_meta("projectile_id", String(building_stats.get("projectile_id", "")))
	building_body.set_meta("commands", building.get("commands", []))
	building_body.set_meta("pathable", bool(building.get("pathable", false)))
	building_body.set_meta("walkable_by", building.get("walkable_by", []))
	building_body.set_meta("building_size", size)
	building_body.set_meta("building_color", building["color"])
	building_body.set_meta("portrait_camera_offset", building["portrait_camera_offset"])
	building_body.set_meta("portrait_camera_target", building["portrait_camera_target"])
	building_body.set_meta("portrait_camera_fov", building["portrait_camera_fov"])
	building_body.set_meta("death_sound_path", String((building.get("audio", {}) as Dictionary).get("death", "")))
	building_body.set_meta("grid_anchor_cell", anchor_cell)
	building_body.set_meta("grid_footprint", footprint)
	building_body.position = map_grid.footprint_to_world_center(
		anchor_cell,
		footprint,
		size.y * 0.5
	)
	buildings_root.add_child(building_body)
	map_grid.occupy(anchor_cell, footprint, building_body, not bool(building.get("pathable", false)))
	_update_selection_ring()


func _create_queued_building_ghost(building: Dictionary, anchor_cell: Vector2i) -> Node3D:
	var footprint: Vector2i = building["footprint"]
	var size: Vector3 = building["size"]
	var ghost := Node3D.new()
	ghost.name = "%s Queued" % String(building["name"])
	ghost.set_meta("queued_building_name", String(building["name"]))
	ghost.set_meta("grid_anchor_cell", anchor_cell)
	ghost.set_meta("grid_footprint", footprint)
	ghost.position = map_grid.footprint_to_world_center(anchor_cell, footprint, size.y * 0.5)

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
	if _selected_unit != null and _selected_unit.is_flying():
		return anchor_cell + Vector2i(floori(float(footprint.x) * 0.5), floori(float(footprint.y) * 0.5))

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


func _get_worker_target_position(_building: Dictionary, anchor_cell: Vector2i, footprint: Vector2i, worker_target_cell: Vector2i) -> Vector3:
	if _selected_unit != null and _selected_unit.is_flying():
		return map_grid.footprint_to_world_center(anchor_cell, footprint, _selected_unit.global_position.y)

	return map_grid.cell_to_world(worker_target_cell, _selected_unit.global_position.y)


func _issue_selected_unit_move_order() -> void:
	var target_cell := placement_preview.current_cell
	if _selected_unit.can_move_to_cell(target_cell):
		_selected_unit.issue_move_order(placement_preview.current_world_point)
	else:
		_play_invalid_order_feedback(false)


func _delete_building(building_node: Node, anchor_cell: Vector2i, footprint: Vector2i) -> void:
	if building_node is Node3D:
		_play_actor_death_sound(building_node)

	if building_node == _selected_placed_building:
		_selected_placed_building = null
		selection_panel.clear_selection()

	_remove_destroy_marker(building_node)
	map_grid.release(anchor_cell, footprint)
	building_node.queue_free()
	_update_selection_ring()


func _delete_map_geometry(map_geometry: Node, anchor_cell: Vector2i, footprint: Vector2i, record_history: bool = false) -> void:
	var state := _capture_map_geometry_state(map_geometry) if record_history else {}
	if map_geometry == _selected_map_geometry:
		_selected_map_geometry = null
		selection_panel.clear_selection()

	if bool(map_geometry.get_meta("registers_grid_occupancy", true)):
		map_grid.release(anchor_cell, footprint)
	map_geometry.queue_free()
	if record_history and not state.is_empty():
		_push_mapping_history({
			"type": HISTORY_ACTION_DELETE_GEOMETRY,
			"state": state
		})
	_update_selection_ring()


func _play_actor_death_sound(actor: Node3D) -> void:
	var death_sound_path := String(actor.get_meta("death_sound_path", ""))
	if death_sound_path.is_empty():
		return

	var death_sound := GameData.load_audio_stream(death_sound_path)
	if death_sound == null:
		return

	AudioUtils.play_world_sound(self, actor.global_position, death_sound)


func _remove_destroyed_buildings() -> void:
	for building in get_tree().get_nodes_in_group("rts_buildings"):
		if not (building is Node):
			continue

		var max_health := int(building.get_meta("max_health", 0))
		var current_health := int(building.get_meta("current_health", 0))
		if max_health < 0 or current_health > 0:
			continue

		if not building.has_meta("grid_anchor_cell") or not building.has_meta("grid_footprint"):
			continue

		var anchor_cell: Vector2i = building.get_meta("grid_anchor_cell")
		var footprint: Vector2i = building.get_meta("grid_footprint")
		_delete_building(building, anchor_cell, footprint)


func _refresh_selection_health_display() -> void:
	if _selected_unit != null and is_instance_valid(_selected_unit):
		selection_panel.refresh_health_display(_selected_unit)
		return

	if _selected_enemy != null and is_instance_valid(_selected_enemy):
		selection_panel.refresh_health_display(_selected_enemy)
		return

	if _selected_placed_building != null and is_instance_valid(_selected_placed_building):
		selection_panel.refresh_health_display(_selected_placed_building)


func _get_building_on_current_cell() -> Node:
	var occupant: Variant = map_grid.get_occupant(placement_preview.current_cell)
	if occupant != null and occupant is Node and occupant.has_meta("building_name"):
		return occupant

	return null


func _get_map_geometry_on_current_cell() -> Node:
	var best_geometry: Node = null
	var best_height := -INF
	for map_geometry in get_tree().get_nodes_in_group("rts_map_geometry"):
		if not (map_geometry is Node):
			continue

		if not _is_cell_inside_node_footprint(map_geometry, placement_preview.current_cell):
			continue

		var top_height := _get_map_geometry_top_height(map_geometry)
		if top_height > best_height:
			best_height = top_height
			best_geometry = map_geometry

	return best_geometry


func _is_cell_inside_node_footprint(node: Node, cell: Vector2i) -> bool:
	if not node.has_meta("grid_anchor_cell") or not node.has_meta("grid_footprint"):
		return false

	var anchor_cell: Vector2i = node.get_meta("grid_anchor_cell")
	var footprint: Vector2i = node.get_meta("grid_footprint")
	return cell.x >= anchor_cell.x \
		and cell.y >= anchor_cell.y \
		and cell.x < anchor_cell.x + footprint.x \
		and cell.y < anchor_cell.y + footprint.y


func _get_unit_on_current_cell() -> RtsUnit:
	for unit in get_tree().get_nodes_in_group("rts_units"):
		if unit is RtsUnit and unit.get_current_cell() == placement_preview.current_cell:
			return unit

	return null


func _get_enemy_on_current_cell() -> RtsEnemy:
	for enemy in get_tree().get_nodes_in_group("rts_enemies"):
		if enemy is RtsEnemy and enemy.get_current_cell() == placement_preview.current_cell:
			return enemy

	return null


func _select_placed_building(building_node: Node) -> void:
	_disconnect_queue_display_unit()
	_selected_placed_building = building_node
	_selected_map_geometry = null
	_selected_unit = null
	_selected_enemy = null
	var commands: Array[Dictionary] = []
	for command in building_node.get_meta("commands", []):
		if command is Dictionary:
			commands.append(command)
	command_grid.set_commands(commands)
	command_grid.set_selected_command("")
	if _interaction_state == InteractionState.BUILDING:
		_set_interaction_state(InteractionState.SELECTING)
	_update_selection_ring()
	selection_panel.show_building(building_node)


func _select_map_geometry_node(map_geometry: Node) -> void:
	_disconnect_queue_display_unit()
	_selected_map_geometry = map_geometry
	_selected_placed_building = null
	_selected_unit = null
	_selected_enemy = null
	command_grid.set_commands([])
	command_grid.set_selected_command("")
	if _interaction_state == InteractionState.BUILDING or _interaction_state == InteractionState.MAPPING:
		_set_interaction_state(InteractionState.SELECTING)
	_update_selection_ring()
	selection_panel.show_map_geometry(map_geometry)


func _select_unit(unit: RtsUnit) -> void:
	_disconnect_queue_display_unit()
	_selected_unit = unit
	_selected_placed_building = null
	_selected_map_geometry = null
	_selected_enemy = null
	_queue_display_unit = unit
	_queue_display_unit.action_queue_changed.connect(_on_selected_unit_action_queue_changed)
	command_grid.set_commands(unit.get_command_definitions())
	_filter_building_options_for_unit(unit)
	_sync_building_command_menu()
	_sync_map_geometry_command_menu()
	_sync_map_tag_command_menu()
	command_grid.set_selected_command("")
	_update_selection_ring()
	selection_panel.show_unit(unit)
	selection_panel.show_action_queue(unit.get_action_queue())
	unit.play_selection_voice()


func _select_enemy(enemy: RtsEnemy) -> void:
	_disconnect_queue_display_unit()
	_selected_enemy = enemy
	_selected_unit = null
	_selected_placed_building = null
	_selected_map_geometry = null
	_building_options.clear()
	command_grid.set_commands([])
	command_grid.set_selected_command("")
	if _interaction_state != InteractionState.SELECTING:
		_set_interaction_state(InteractionState.SELECTING)
	_update_selection_ring()
	selection_panel.show_enemy(enemy)


func _spawn_test_dummy_at_mouse() -> void:
	var spawn_cell := placement_preview.current_cell
	if not map_grid.is_cell_in_bounds(spawn_cell):
		_play_invalid_order_feedback(false)
		return

	var dummy := RtsEnemy.new()
	dummy.name = "TestDummy"
	dummy.grid_path = NodePath("../../Grid")
	dummy.enemy_id = "test_dummy"
	dummy.enemy_data_path = DEBUG_TEST_DUMMY_DATA_PATH
	dummy.position = map_grid.cell_to_world(spawn_cell, 0.0)
	enemies_root.add_child(dummy)
	_select_enemy(dummy)


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
		_focus_camera_on_node(scout)


func _get_unit_by_name(unit_name: String) -> RtsUnit:
	for unit in get_tree().get_nodes_in_group("rts_units"):
		if unit is RtsUnit and unit.unit_name == unit_name:
			return unit

	return null


func _on_selection_portrait_double_clicked() -> void:
	if _selected_unit != null:
		_focus_camera_on_node(_selected_unit)
	elif _selected_enemy != null:
		_focus_camera_on_node(_selected_enemy)


func _focus_camera_on_node(node: Node3D) -> void:
	if camera_rig.has_method("center_on_world_position"):
		camera_rig.call("center_on_world_position", node.global_position)


func _clear_selection() -> void:
	_disconnect_queue_display_unit()
	_selected_placed_building = null
	_selected_map_geometry = null
	_selected_unit = null
	_selected_enemy = null
	_building_options.clear()
	command_grid.set_commands([])
	command_grid.set_selected_command("")
	_selection_ring.visible = false
	_attack_range_ring.visible = false
	_tag_hover_ring.visible = false
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

	if command_id.begins_with(COMMAND_MAP_GEOMETRY_PREFIX):
		_select_map_geometry(int(command_id.trim_prefix(COMMAND_MAP_GEOMETRY_PREFIX)))
		_try_enter_mapping_mode()
		return

	if command_id.begins_with(COMMAND_MAP_TAG_PREFIX):
		_selected_map_tag_action = command_id.trim_prefix(COMMAND_MAP_TAG_PREFIX)
		_set_interaction_state(InteractionState.TAGGING)
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
			"hotkey": String(building.get("hotkey", "")),
			"fallback_hotkey": String(building.get("fallback_hotkey", "")),
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


func _sync_map_geometry_command_menu() -> void:
	var commands: Array[Dictionary] = []
	var visible_geometry_count := mini(_map_geometry_options.size(), MAX_BUILD_MENU_BUILDINGS - 1)
	for index in range(visible_geometry_count):
		var geometry: Dictionary = _map_geometry_options[index]
		commands.append({
			"id": _get_map_geometry_command_id(index),
			"label": "",
			"slot": index,
			"hotkey": String(geometry.get("hotkey", "")),
			"fallback_hotkey": String(geometry.get("fallback_hotkey", "")),
			"tooltip": String(geometry["name"]),
			"model": _get_map_geometry_model_data(geometry)
		})

	commands.append({
		"id": "tagging_menu",
		"label": "Tags",
		"slot": Vector2i(1, 2),
		"hotkey": "T",
		"fallback_hotkey": "",
		"menu": MAP_TAG_MENU_ID,
		"tooltip": "Tags"
	})

	commands.append({
		"id": "back",
		"label": "Back",
		"slot": BUILD_MENU_BACK_SLOT,
		"menu": CommandGrid.ROOT_MENU_ID,
		"tooltip": "Back"
	})
	command_grid.set_menu(MAP_GEOMETRY_MENU_ID, commands)


func _sync_map_tag_command_menu() -> void:
	var commands: Array[Dictionary] = [
		{
			"id": _get_map_tag_command_id(MAP_TAG_SPAWNER),
			"label": "Spawn",
			"slot": Vector2i(0, 0),
			"hotkey": "S",
			"fallback_hotkey": "P",
			"tooltip": "Apply Spawn Tag"
		},
		{
			"id": _get_map_tag_command_id(MAP_TAG_END_POINT),
			"label": "Exit",
			"slot": Vector2i(1, 0),
			"hotkey": "E",
			"fallback_hotkey": "X",
			"tooltip": "Apply End Point Tag"
		},
		{
			"id": _get_map_tag_command_id(MAP_TAG_ACTION_REMOVE_SPAWNER),
			"label": "-Spawn",
			"slot": Vector2i(0, 1),
			"hotkey": "R",
			"fallback_hotkey": "",
			"tooltip": "Remove Spawn Tag"
		},
		{
			"id": _get_map_tag_command_id(MAP_TAG_ACTION_REMOVE_END_POINT),
			"label": "-Exit",
			"slot": Vector2i(1, 1),
			"hotkey": "D",
			"fallback_hotkey": "",
			"tooltip": "Remove End Point Tag"
		},
		{
			"id": _get_map_tag_command_id(MAP_TAG_ACTION_CLEAR),
			"label": "Clear",
			"slot": Vector2i(2, 1),
			"hotkey": "C",
			"fallback_hotkey": "R",
			"tooltip": "Clear Tags"
		},
		{
			"id": "back",
			"label": "Back",
			"slot": BUILD_MENU_BACK_SLOT,
			"menu": MAP_GEOMETRY_MENU_ID,
			"tooltip": "Back"
		}
	]
	command_grid.set_menu(MAP_TAG_MENU_ID, commands)


func _load_building_data() -> void:
	var loaded_buildings := GameData.load_building_definitions(building_data_directory)
	if loaded_buildings.is_empty():
		push_warning("No building definitions were loaded from %s." % building_data_directory)
		return

	_all_building_options = loaded_buildings
	_building_options.clear()
	_selected_index = 0


func _load_map_geometry_data() -> void:
	var loaded_geometries := GameData.load_map_geometry_definitions(map_geometry_data_directory)
	if loaded_geometries.is_empty():
		push_warning("No map geometry definitions were loaded from %s." % map_geometry_data_directory)
		return

	_map_geometry_options = loaded_geometries
	_selected_map_geometry_index = 0


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


func _get_map_geometry_command_id(index: int) -> String:
	return "%s%d" % [COMMAND_MAP_GEOMETRY_PREFIX, index]


func _get_map_tag_command_id(tag_action: String) -> String:
	return "%s%s" % [COMMAND_MAP_TAG_PREFIX, tag_action]


func _get_building_model_data(building: Dictionary) -> Dictionary:
	return {
		"type": "box",
		"size": building["size"],
		"color": building["color"],
		"camera_offset": building["portrait_camera_offset"],
		"camera_target": building["portrait_camera_target"],
		"camera_fov": building["portrait_camera_fov"]
	}


func _get_map_geometry_model_data(geometry: Dictionary) -> Dictionary:
	return {
		"type": String(geometry.get("shape", "box")),
		"size": geometry["size"],
		"color": geometry["color"],
		"camera_offset": geometry["portrait_camera_offset"],
		"camera_target": geometry["portrait_camera_target"],
		"camera_fov": geometry["portrait_camera_fov"]
	}


func _can_place_map_geometry(anchor_cell: Vector2i, footprint: Vector2i) -> bool:
	if not map_grid.is_footprint_in_bounds(anchor_cell, footprint):
		return false

	for cell in map_grid.get_footprint_cells(anchor_cell, footprint):
		var occupant: Variant = map_grid.get_occupant(cell)
		if occupant != null and not _is_map_geometry_node(occupant):
			return false

	return true


func _get_map_geometry_stack_height(anchor_cell: Vector2i, footprint: Vector2i) -> float:
	var stack_height := 0.0
	for cell in map_grid.get_footprint_cells(anchor_cell, footprint):
		for map_geometry in get_tree().get_nodes_in_group("rts_map_geometry"):
			if not (map_geometry is Node):
				continue

			if not _is_cell_inside_node_footprint(map_geometry, cell):
				continue

			stack_height = maxf(stack_height, _get_map_geometry_top_height(map_geometry))

	return stack_height


func _get_map_geometry_top_height(map_geometry: Node) -> float:
	var base_height := float(map_geometry.get_meta("geometry_base_height", 0.0))
	var size: Vector3 = map_geometry.get_meta("geometry_size", Vector3.ZERO)
	return base_height + size.y


func _is_map_geometry_node(value: Variant) -> bool:
	return value is Node and (value as Node).has_meta("geometry_name")


func _capture_map_geometry_state(map_geometry: Node) -> Dictionary:
	if map_geometry == null or not is_instance_valid(map_geometry):
		return {}

	return {
		"name": map_geometry.name,
		"geometry_id": String(map_geometry.get_meta("geometry_id", "")),
		"display_name": String(map_geometry.get_meta("geometry_name", "Map Geometry")),
		"shape": String(map_geometry.get_meta("geometry_shape", "box")),
		"rotation_steps": int(map_geometry.get_meta("geometry_rotation_steps", 0)),
		"tags": PackedStringArray(map_geometry.get_meta("geometry_tags", [])),
		"metadata": (map_geometry.get_meta("geometry_metadata", {}) as Dictionary).duplicate(true),
		"anchor_cell": map_geometry.get_meta("grid_anchor_cell", Vector2i.ZERO),
		"footprint": map_geometry.get_meta("grid_footprint", Vector2i.ONE),
		"pathable": bool(map_geometry.get_meta("pathable", false)),
		"size": map_geometry.get_meta("geometry_size", Vector3(2.0, 0.5, 2.0)),
		"color": map_geometry.get("color") if map_geometry is MapGeometry else map_geometry.get_meta("geometry_color", Color(0.6, 0.7, 0.8, 0.55)),
		"base_height": float(map_geometry.get_meta("geometry_base_height", 0.0)),
		"registers_grid_occupancy": bool(map_geometry.get_meta("registers_grid_occupancy", true))
	}


func _restore_map_geometry_from_state(state: Dictionary) -> Node:
	var map_geometry := MapGeometrySceneScript.new()
	map_geometry.name = String(state.get("name", "MapGeometry"))
	map_geometry.grid_path = NodePath("../../Grid")
	map_geometry.geometry_id = String(state.get("geometry_id", ""))
	map_geometry.display_name = String(state.get("display_name", "Map Geometry"))
	map_geometry.shape = String(state.get("shape", "box"))
	map_geometry.rotation_steps = int(state.get("rotation_steps", 0))
	map_geometry.tags = PackedStringArray(state.get("tags", []))
	map_geometry.metadata = (state.get("metadata", {}) as Dictionary).duplicate(true)
	map_geometry.anchor_cell = state.get("anchor_cell", Vector2i.ZERO)
	map_geometry.footprint = state.get("footprint", Vector2i.ONE)
	map_geometry.pathable = bool(state.get("pathable", false))
	map_geometry.size = state.get("size", Vector3(2.0, 0.5, 2.0))
	map_geometry.color = state.get("color", Color(0.6, 0.7, 0.8, 0.55))
	map_geometry.base_height = float(state.get("base_height", 0.0))
	map_geometry.registers_grid_occupancy = bool(state.get("registers_grid_occupancy", true))
	map_geometry_root.add_child(map_geometry)
	return map_geometry


func _find_map_geometry_by_state(state: Dictionary) -> Node:
	var anchor_cell: Vector2i = state.get("anchor_cell", Vector2i.ZERO)
	var footprint: Vector2i = state.get("footprint", Vector2i.ONE)
	var base_height := float(state.get("base_height", 0.0))
	var geometry_id := String(state.get("geometry_id", ""))
	for map_geometry in get_tree().get_nodes_in_group("rts_map_geometry"):
		if not (map_geometry is Node):
			continue

		if map_geometry.get_meta("grid_anchor_cell", Vector2i(-999, -999)) != anchor_cell:
			continue

		if map_geometry.get_meta("grid_footprint", Vector2i.ZERO) != footprint:
			continue

		if not is_equal_approx(float(map_geometry.get_meta("geometry_base_height", 0.0)), base_height):
			continue

		if String(map_geometry.get_meta("geometry_id", "")) != geometry_id:
			continue

		return map_geometry

	return null


func _set_map_geometry_tags(map_geometry: Node, tags: PackedStringArray) -> void:
	if map_geometry.has_method("set_tags"):
		map_geometry.call("set_tags", tags)
		if map_geometry == _selected_map_geometry:
			selection_panel.show_map_geometry(map_geometry)


func _push_mapping_history(action: Dictionary) -> void:
	_mapping_undo_stack.append(action)
	_mapping_redo_stack.clear()


func _commit_active_paint_history() -> void:
	if _active_paint_history_actions.is_empty():
		return

	_push_mapping_history({
		"type": HISTORY_ACTION_BATCH,
		"actions": _active_paint_history_actions.duplicate(true)
	})
	_active_paint_history_actions.clear()


func _undo_mapping_action() -> void:
	if _mapping_undo_stack.is_empty():
		return

	var action := _mapping_undo_stack.pop_back() as Dictionary
	_apply_mapping_history_action(action, true)
	_mapping_redo_stack.append(action)


func _redo_mapping_action() -> void:
	if _mapping_redo_stack.is_empty():
		return

	var action := _mapping_redo_stack.pop_back() as Dictionary
	_apply_mapping_history_action(action, false)
	_mapping_undo_stack.append(action)


func _apply_mapping_history_action(action: Dictionary, is_undo: bool) -> void:
	var action_type := String(action.get("type", ""))
	var state: Dictionary = action.get("state", {})
	match action_type:
		HISTORY_ACTION_BATCH:
			var actions: Array = action.get("actions", [])
			if is_undo:
				for index in range(actions.size() - 1, -1, -1):
					if actions[index] is Dictionary:
						_apply_mapping_history_action(actions[index], true)
			else:
				for child_action in actions:
					if child_action is Dictionary:
						_apply_mapping_history_action(child_action, false)
		HISTORY_ACTION_PLACE_GEOMETRY:
			if is_undo:
				var placed_geometry := _find_map_geometry_by_state(state)
				if placed_geometry != null:
					_delete_map_geometry(
						placed_geometry,
						placed_geometry.get_meta("grid_anchor_cell"),
						placed_geometry.get_meta("grid_footprint")
					)
			else:
				_restore_map_geometry_from_state(state)
		HISTORY_ACTION_DELETE_GEOMETRY:
			if is_undo:
				_restore_map_geometry_from_state(state)
			else:
				var restored_geometry := _find_map_geometry_by_state(state)
				if restored_geometry != null:
					_delete_map_geometry(
						restored_geometry,
						restored_geometry.get_meta("grid_anchor_cell"),
						restored_geometry.get_meta("grid_footprint")
					)
		HISTORY_ACTION_TAG_GEOMETRY:
			var target_state: Dictionary = action.get("target_state", {})
			var target_geometry := _find_map_geometry_by_state(target_state)
			if target_geometry == null:
				return

			var tags_to_apply := PackedStringArray(action.get("before_tags" if is_undo else "after_tags", []))
			_set_map_geometry_tags(target_geometry, tags_to_apply)


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


func _create_attack_range_ring() -> void:
	_attack_range_ring = MeshInstance3D.new()
	_attack_range_ring.name = "AttackRangeRing"
	_attack_range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attack_range_ring.material_override = _create_attack_range_material()
	_attack_range_ring.visible = false
	buildings_root.add_child(_attack_range_ring)


func _create_tag_hover_ring() -> void:
	_tag_hover_ring = MeshInstance3D.new()
	_tag_hover_ring.name = "MapTagHoverRing"
	_tag_hover_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tag_hover_ring.material_override = _create_tag_hover_material()
	_tag_hover_ring.visible = false
	map_geometry_root.add_child(_tag_hover_ring)


func _create_attack_range_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.25, 0.72, 1.0, 0.28)
	material.no_depth_test = true
	return material


func _create_tag_hover_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.88, 0.24, 0.85)
	material.no_depth_test = true
	return material


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

	if _selected_enemy != null:
		if not is_instance_valid(_selected_enemy):
			_clear_selection()
			return

		_selection_ring.mesh = _create_selection_ring_mesh(map_grid.cell_size * 0.35)
		_selection_ring.global_position = _selected_enemy.global_position + Vector3.UP * 0.12
		_selection_ring.visible = true
		return

	if _selected_map_geometry != null:
		if not is_instance_valid(_selected_map_geometry):
			_clear_selection()
			return

		if not _selected_map_geometry.has_meta("grid_anchor_cell") \
			or not _selected_map_geometry.has_meta("grid_footprint"):
			_clear_selection()
			return

		var geometry_anchor: Vector2i = _selected_map_geometry.get_meta("grid_anchor_cell")
		var geometry_footprint: Vector2i = _selected_map_geometry.get_meta("grid_footprint")
		var geometry_radius := maxf(float(geometry_footprint.x), float(geometry_footprint.y)) * map_grid.cell_size * 0.62
		_selection_ring.mesh = _create_selection_ring_mesh(geometry_radius)
		_selection_ring.global_position = map_grid.footprint_to_world_center(geometry_anchor, geometry_footprint, 0.12)
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


func _update_attack_range_ring() -> void:
	if not Input.is_key_pressed(KEY_ALT):
		_attack_range_ring.visible = false
		return

	var range_data := _get_selected_attack_range_data()
	var attack_range := float(range_data.get("attack_range", 0.0))
	if attack_range <= 0.0:
		_attack_range_ring.visible = false
		return

	_attack_range_ring.mesh = _create_attack_range_mesh(attack_range)
	_attack_range_ring.global_position = range_data.get("position", Vector3.ZERO)
	_attack_range_ring.visible = true


func _get_selected_attack_range_data() -> Dictionary:
	if _selected_unit != null and is_instance_valid(_selected_unit):
		return {
			"attack_range": _selected_unit.get_attack_range(),
			"position": Vector3(_selected_unit.global_position.x, ATTACK_RANGE_RING_HEIGHT, _selected_unit.global_position.z)
		}

	if _selected_enemy != null and is_instance_valid(_selected_enemy):
		return {
			"attack_range": _selected_enemy.get_attack_range(),
			"position": Vector3(_selected_enemy.global_position.x, ATTACK_RANGE_RING_HEIGHT, _selected_enemy.global_position.z)
		}

	if _selected_placed_building != null \
		and is_instance_valid(_selected_placed_building) \
		and _selected_placed_building is Node3D:
		var building_position := (_selected_placed_building as Node3D).global_position
		return {
			"attack_range": float(_selected_placed_building.get_meta("attack_range", 0.0)),
			"position": Vector3(building_position.x, ATTACK_RANGE_RING_HEIGHT, building_position.z)
		}

	return {}


func _update_tag_hover_ring() -> void:
	if _interaction_state != InteractionState.TAGGING:
		_tag_hover_ring.visible = false
		return

	var map_geometry := _get_map_geometry_on_current_cell()
	if map_geometry == null:
		_tag_hover_ring.visible = false
		return

	if not map_geometry.has_meta("grid_anchor_cell") or not map_geometry.has_meta("grid_footprint"):
		_tag_hover_ring.visible = false
		return

	var anchor_cell: Vector2i = map_geometry.get_meta("grid_anchor_cell")
	var footprint: Vector2i = map_geometry.get_meta("grid_footprint")
	var radius := maxf(float(footprint.x), float(footprint.y)) * map_grid.cell_size * 0.66
	var top_height := _get_map_geometry_top_height(map_geometry)
	_tag_hover_ring.mesh = _create_selection_ring_mesh(radius)
	_tag_hover_ring.global_position = map_grid.footprint_to_world_center(anchor_cell, footprint, top_height + 0.1)
	_tag_hover_ring.visible = true


func _create_attack_range_mesh(radius: float) -> ImmediateMesh:
	var range_mesh := ImmediateMesh.new()
	range_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in range(SELECTION_RING_SEGMENTS + 1):
		var angle := TAU * float(index) / float(SELECTION_RING_SEGMENTS)
		range_mesh.surface_add_vertex(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))

	range_mesh.surface_end()
	return range_mesh


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
	building_body.collision_layer = _get_building_collision_layer(building)

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


func _get_building_collision_layer(building: Dictionary) -> int:
	var collision_layer := 0
	if not _is_building_walkable_by(building, ACTOR_TYPE_UNIT):
		collision_layer |= COLLISION_LAYER_BLOCKS_UNITS

	if not _is_building_walkable_by(building, ACTOR_TYPE_ENEMY):
		collision_layer |= COLLISION_LAYER_BLOCKS_ENEMIES

	return collision_layer


func _is_building_walkable_by(building: Dictionary, actor_type: String) -> bool:
	for walkable_actor_type in building.get("walkable_by", []):
		if String(walkable_actor_type) == actor_type:
			return true

	return false


func _create_building_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
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


func _get_selected_building() -> Dictionary:
	if _building_options.is_empty():
		return {}

	return _building_options[_selected_index]


func _get_selected_map_geometry() -> Dictionary:
	if _map_geometry_options.is_empty():
		return {}

	return _map_geometry_options[_selected_map_geometry_index]
