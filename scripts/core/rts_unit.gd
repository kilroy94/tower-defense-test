class_name RtsUnit
extends CharacterBody3D

signal action_queue_changed(queue: Array[Dictionary])

const CombatUtilsRef = preload("res://scripts/systems/combat_utils.gd")
const VOICE_TYPE_NONE := ""
const VOICE_TYPE_SELECTION := "selection"
const VOICE_TYPE_MOVE_ORDER := "move_order"
const VOICE_TYPE_ANGRY := "angry"
const VOICE_TYPE_WARNING := "warning"
const SELECTION_SPAM_THRESHOLD := 10
const SELECTION_SPAM_WINDOW_SECONDS := 5
const MAX_ACTION_QUEUE_SIZE := 6
const COLLISION_LAYER_WORLD := 1 << 0
const COLLISION_LAYER_BLOCKS_UNITS := 1 << 1
const MOVEMENT_TYPE_GROUND := "ground"
const MOVEMENT_TYPE_FLYING := "flying"
const FLIGHT_SHADOW_HEIGHT := 0.045
const FLIGHT_SHADOW_ALPHA := 0.36
const DEFAULT_TURN_ALIGNMENT_DEGREES := 11.5
const DEFAULT_TURN_ACCELERATION_TIME := 0.03

@export var grid_path: NodePath
@export var unit_id := "scout"
@export var unit_data_path := "res://data/units/scout.json"
@export var unit_name := "Scout"
@export var movement_type := MOVEMENT_TYPE_GROUND
@export var move_speed: float = 10.0
@export var turn_speed: float = 1080.0
@export var turn_alignment_degrees := DEFAULT_TURN_ALIGNMENT_DEGREES
@export var turn_acceleration_time := DEFAULT_TURN_ACCELERATION_TIME
@export var body_color: Color = Color(0.18, 0.78, 0.9, 1.0)
@export var arrival_distance: float = 0.2
@export var flight_height := 3.0
@export var max_health := 220
@export var damage := 8
@export var armor := 0
@export var attack_type := "melee"
@export var attack_speed := 1.0
@export var attack_range := 1.2
@export var attack_cooldown := 1.4
@export var projectile_id := ""
@export var portrait_camera_offset: Vector3 = Vector3(0.0, 1.45, 4.0)
@export var portrait_camera_target: Vector3 = Vector3(0.0, 0.8, 0.0)
@export var portrait_camera_fov: float = 36.0
@export var command_definitions: Array[Dictionary] = [
	{
		"id": "build_menu",
		"label": "Build",
		"slot": Vector2i(0, 2),
		"menu": "buildings",
		"tooltip": "Build"
	},
	{
		"id": "destroy",
		"label": "Destroy",
		"slot": Vector2i(1, 2),
		"tooltip": "Destroy"
	}
]

@onready var map_grid: MapGrid = get_node(grid_path)

var current_health := 220
var _path: Array[Vector3] = []
var _cell_path: Array[Vector2i] = []
var _path_index := 0
var _target_cell := Vector2i.ZERO
var _target_world_position := Vector3.ZERO
var _has_move_order := false
var _arrival_callback: Callable
var _active_action: Dictionary = {}
var _queued_actions: Array[Dictionary] = []
var _voice_player: AudioStreamPlayer
var _voice_rng := RandomNumberGenerator.new()
var _current_voice_type := VOICE_TYPE_NONE
var _selection_spam_count := 0
var _last_selection_voice_time_msec := 0
var _cost: Dictionary = {}
var _selection_voice_lines: Array[AudioStream] = []
var _move_order_voice_lines: Array[AudioStream] = []
var _angry_voice_lines: Array[AudioStream] = []
var _cannot_build_voice_line: AudioStream = null
var _available_building_ids: Array[String] = []
var _flight_shadow: MeshInstance3D = null
var _current_turn_speed := 0.0
var _last_turn_sign := 0.0


func _ready() -> void:
	_apply_unit_data()
	collision_mask = _get_collision_mask_for_movement_type()
	add_to_group("rts_units")
	if is_flying():
		global_position.y = flight_height
	current_health = -1 if max_health < 0 else max_health
	set_meta("unit_name", unit_name)
	set_meta("unit_id", unit_id)
	set_meta("movement_type", movement_type)
	set_meta("turn_speed", turn_speed)
	set_meta("turn_alignment_degrees", turn_alignment_degrees)
	set_meta("turn_acceleration_time", turn_acceleration_time)
	set_meta("cost", _cost)
	set_meta("stats", _get_runtime_stats())
	set_meta("max_health", max_health)
	set_meta("current_health", current_health)
	set_meta("damage", damage)
	set_meta("armor", armor)
	set_meta("attack_type", attack_type)
	set_meta("attack_speed", attack_speed)
	set_meta("attack_range", attack_range)
	set_meta("attack_cooldown", attack_cooldown)
	set_meta("projectile_id", projectile_id)
	_voice_rng.randomize()
	_create_visuals()
	_create_flight_shadow()
	_create_voice_player()


func _physics_process(delta: float) -> void:
	_update_flight_shadow()
	_follow_path(delta)


func issue_move_order(target_world_position: Vector3) -> void:
	_clear_action_queue()
	if _start_action(_create_action(target_world_position, Callable(), "Move", Color(0.36, 0.62, 0.95, 1.0))):
		play_move_order_voice()


func issue_move_order_with_callback(
	target_world_position: Vector3,
	arrival_callback: Callable,
	should_queue: bool = false,
	action_label: String = "Order",
	action_color: Color = Color(0.8, 0.75, 0.42, 1.0),
	cancel_callback: Callable = Callable(),
	action_model: Dictionary = {}
) -> bool:
	var action: Dictionary = _create_action(target_world_position, arrival_callback, action_label, action_color, cancel_callback, action_model)
	if should_queue and _has_active_or_queued_action():
		if get_action_queue_size() >= MAX_ACTION_QUEUE_SIZE:
			return false

		_queued_actions.append(action)
		_emit_action_queue_changed()
		play_move_order_voice()
		return true

	_clear_action_queue()
	if not _start_action(action):
		return false

	play_move_order_voice()
	return true


func get_action_queue() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not _active_action.is_empty():
		actions.append(_active_action)

	actions.append_array(_queued_actions)
	return actions


func get_action_queue_size() -> int:
	return get_action_queue().size()


func get_current_cell() -> Vector2i:
	return map_grid.world_to_cell(global_position)


func get_command_definitions() -> Array[Dictionary]:
	return command_definitions


func get_cost() -> Dictionary:
	return _cost


func get_health() -> int:
	return current_health


func get_max_health() -> int:
	return max_health


func set_health(new_health: int) -> void:
	current_health = -1 if max_health < 0 else clampi(new_health, 0, max_health)
	_sync_runtime_stats_meta()


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


func get_available_building_ids() -> Array[String]:
	return _available_building_ids


func is_flying() -> bool:
	return movement_type == MOVEMENT_TYPE_FLYING


func can_move_to_cell(cell: Vector2i) -> bool:
	if is_flying():
		return map_grid.is_cell_in_bounds(cell)

	return map_grid.is_cell_walkable(cell)


func play_selection_voice() -> void:
	_track_selection_spam()
	if _selection_spam_count >= SELECTION_SPAM_THRESHOLD:
		if not _is_selection_or_angry_voice_playing():
			_selection_spam_count = 0
			_play_random_voice(_angry_voice_lines, VOICE_TYPE_ANGRY, false)
		return

	if _is_selection_or_angry_voice_playing():
		return

	_play_random_voice(_selection_voice_lines, VOICE_TYPE_SELECTION, true)


func play_move_order_voice() -> void:
	_selection_spam_count = 0
	_play_random_voice(_move_order_voice_lines, VOICE_TYPE_MOVE_ORDER, false)


func play_cannot_build_there_voice() -> void:
	_play_voice(_cannot_build_voice_line, VOICE_TYPE_WARNING, false)


func _rebuild_path_to_target() -> void:
	if is_flying():
		_path = [_target_world_position]
		_cell_path.clear()
		if map_grid.is_cell_in_bounds(_target_cell):
			_cell_path.append(_target_cell)
		_path_index = 0
		return

	var start_cell := get_current_cell()
	_cell_path = map_grid.find_path(start_cell, _target_cell)
	_path.clear()
	_path_index = 0

	if start_cell == _target_cell:
		_path.append(_target_world_position)
		return

	if _cell_path.is_empty():
		_has_move_order = false
		return

	var raw_path: Array[Vector3] = []
	for index in range(_cell_path.size()):
		var cell := _cell_path[index]
		if index == _cell_path.size() - 1:
			raw_path.append(_target_world_position)
		else:
			raw_path.append(map_grid.cell_to_world(cell, global_position.y))

	_path = _smooth_path(raw_path)


func _follow_path(_delta: float) -> void:
	if _path_index >= _path.size():
		_complete_move_order()
		return

	if _is_current_waypoint_blocked():
		_rebuild_path_to_target()
		if _path_index >= _path.size():
			return

	var target := _path[_path_index]
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() > arrival_distance:
		var move_direction := to_target.normalized()
		if _turn_toward_direction(move_direction, _delta):
			velocity = move_direction * move_speed
			move_and_slide()
		else:
			velocity = Vector3.ZERO
	else:
		velocity = Vector3.ZERO

	if Vector2(global_position.x, global_position.z).distance_to(Vector2(target.x, target.z)) <= arrival_distance:
		_path_index += 1


func _complete_move_order() -> void:
	if not _has_move_order:
		return

	_has_move_order = false
	if _arrival_callback.is_valid():
		var callback := _arrival_callback
		_arrival_callback = Callable()
		callback.call()

	_active_action = {}
	_start_next_queued_action()
	_emit_action_queue_changed()


func _is_current_waypoint_blocked() -> bool:
	if not _has_move_order or _path_index >= _path.size():
		return false

	if is_flying():
		return false

	return not map_grid.is_cell_walkable(map_grid.world_to_cell(_path[_path_index]))


func _create_action(
	target_world_position: Vector3,
	arrival_callback: Callable,
	action_label: String,
	action_color: Color,
	cancel_callback: Callable = Callable(),
	action_model: Dictionary = {}
) -> Dictionary:
	return {
		"target_world_position": target_world_position,
		"arrival_callback": arrival_callback,
		"cancel_callback": cancel_callback,
		"label": action_label,
		"color": action_color,
		"model": action_model
	}


func _apply_unit_data() -> void:
	var definition := GameData.load_unit_definition(unit_data_path)
	if definition.is_empty():
		return

	unit_id = String(definition.get("id", unit_id))
	unit_name = String(definition.get("name", unit_name))
	_cost = definition.get("cost", _cost)
	body_color = definition.get("body_color", body_color)

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
	damage = int(stats.get("damage", damage))
	armor = int(stats.get("armor", armor))
	attack_type = String(stats.get("attack_type", attack_type))
	attack_speed = float(stats.get("attack_speed", attack_speed))
	attack_range = float(stats.get("attack_range", attack_range))
	attack_cooldown = float(stats.get("attack_cooldown", attack_cooldown))
	projectile_id = String(stats.get("projectile_id", projectile_id))

	var portrait_camera: Dictionary = definition.get("portrait_camera", {})
	portrait_camera_offset = portrait_camera.get("offset", portrait_camera_offset)
	portrait_camera_target = portrait_camera.get("target", portrait_camera_target)
	portrait_camera_fov = float(portrait_camera.get("fov", portrait_camera_fov))

	var loaded_commands: Array[Dictionary] = definition.get("commands", [])
	if not loaded_commands.is_empty():
		command_definitions = loaded_commands

	_available_building_ids.clear()
	for building_id in definition.get("available_buildings", []):
		_available_building_ids.append(String(building_id))

	var audio: Dictionary = definition.get("audio", {})
	_selection_voice_lines = GameData.load_audio_streams(audio.get("selection", []))
	_move_order_voice_lines = GameData.load_audio_streams(audio.get("move_order", []))
	_angry_voice_lines = GameData.load_audio_streams(audio.get("angry", []))
	if audio.has("cannot_build"):
		_cannot_build_voice_line = GameData.load_audio_stream(String(audio["cannot_build"]))


func _get_runtime_stats() -> Dictionary:
	return {
		"max_health": max_health,
		"current_health": current_health,
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


func _start_action(action: Dictionary) -> bool:
	_active_action = action
	_target_world_position = _with_unit_height(action["target_world_position"])
	_target_cell = map_grid.world_to_cell(_target_world_position)
	_arrival_callback = action["arrival_callback"]
	_has_move_order = true
	_rebuild_path_to_target()
	if not _has_move_order:
		_cancel_action(action)
		_active_action = {}
		_arrival_callback = Callable()
		_emit_action_queue_changed()
		return false

	_emit_action_queue_changed()
	return true


func _start_next_queued_action() -> void:
	while not _queued_actions.is_empty():
		var next_action: Dictionary = _queued_actions.pop_front()
		if _start_action(next_action):
			return


func _clear_action_queue() -> void:
	if not _active_action.is_empty():
		_cancel_action(_active_action)

	for action in _queued_actions:
		_cancel_action(action)

	_queued_actions.clear()
	_active_action = {}
	_has_move_order = false
	_arrival_callback = Callable()
	_path.clear()
	_path_index = 0
	_emit_action_queue_changed()


func _has_active_or_queued_action() -> bool:
	return _has_move_order or not _active_action.is_empty() or not _queued_actions.is_empty()


func _cancel_action(action: Dictionary) -> void:
	var cancel_callback: Callable = action.get("cancel_callback", Callable())
	if cancel_callback.is_valid():
		cancel_callback.call()


func _emit_action_queue_changed() -> void:
	action_queue_changed.emit(get_action_queue())


func _create_visuals() -> void:
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.7
	collision_shape.shape = capsule_shape
	collision_shape.position.y = 0.85
	add_child(collision_shape)

	var body_mesh_instance := MeshInstance3D.new()
	body_mesh_instance.name = "Body"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.55
	capsule_mesh.height = 1.7
	capsule_mesh.material = _create_unit_material()
	body_mesh_instance.mesh = capsule_mesh
	body_mesh_instance.position.y = 0.85
	add_child(body_mesh_instance)

	var facing_marker := MeshInstance3D.new()
	facing_marker.name = "FacingMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.28, 0.2, 0.7)
	marker_mesh.material = _create_marker_material()
	facing_marker.mesh = marker_mesh
	facing_marker.position = Vector3(0.0, 1.05, -0.62)
	add_child(facing_marker)


func _create_flight_shadow() -> void:
	if not is_flying():
		return

	_flight_shadow = MeshInstance3D.new()
	_flight_shadow.name = "FlightShadow"
	_flight_shadow.top_level = true
	_flight_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.78
	shadow_mesh.bottom_radius = 0.78
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


func _smooth_path(raw_path: Array[Vector3]) -> Array[Vector3]:
	if raw_path.size() <= 2:
		return raw_path

	var smoothed_path: Array[Vector3] = []
	var anchor_position := global_position
	var index := 0
	while index < raw_path.size():
		var farthest_reachable_index := index
		for candidate_index in range(raw_path.size() - 1, index - 1, -1):
			if map_grid.is_world_segment_walkable(anchor_position, raw_path[candidate_index]):
				farthest_reachable_index = candidate_index
				break

		var waypoint := raw_path[farthest_reachable_index]
		smoothed_path.append(waypoint)
		anchor_position = waypoint
		index = farthest_reachable_index + 1

	return smoothed_path


func _with_unit_height(world_position: Vector3) -> Vector3:
	var height := flight_height if is_flying() else global_position.y
	return Vector3(world_position.x, height, world_position.z)


func _get_collision_mask_for_movement_type() -> int:
	if is_flying():
		return 0

	return COLLISION_LAYER_WORLD | COLLISION_LAYER_BLOCKS_UNITS


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


func _create_voice_player() -> void:
	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "VoicePlayer"
	_voice_player.finished.connect(_on_voice_finished)
	add_child(_voice_player)


func _play_random_voice(voice_lines: Array[AudioStream], voice_type: String, ignore_if_same_type_is_playing: bool) -> void:
	if voice_lines.is_empty():
		return

	var voice_index := _voice_rng.randi_range(0, voice_lines.size() - 1)
	_play_voice(voice_lines[voice_index], voice_type, ignore_if_same_type_is_playing)


func _play_voice(voice_line: AudioStream, voice_type: String, ignore_if_same_type_is_playing: bool) -> void:
	if voice_line == null:
		return

	if ignore_if_same_type_is_playing \
		and _voice_player.playing \
		and _current_voice_type == voice_type:
		return

	_voice_player.stop()
	_current_voice_type = voice_type
	_voice_player.stream = voice_line
	_voice_player.play()


func _is_selection_or_angry_voice_playing() -> bool:
	return _voice_player.playing \
		and (_current_voice_type == VOICE_TYPE_SELECTION or _current_voice_type == VOICE_TYPE_ANGRY)


func _track_selection_spam() -> void:
	var now_msec := Time.get_ticks_msec()
	var elapsed_seconds := float(now_msec - _last_selection_voice_time_msec) / 1000.0
	if elapsed_seconds <= SELECTION_SPAM_WINDOW_SECONDS:
		_selection_spam_count += 1
	else:
		_selection_spam_count = 1

	_last_selection_voice_time_msec = now_msec


func _on_voice_finished() -> void:
	_current_voice_type = VOICE_TYPE_NONE


func _create_unit_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	material.roughness = 0.55
	return material


func _create_marker_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.18, 0.2, 1.0)
	material.roughness = 0.7
	return material
