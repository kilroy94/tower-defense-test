extends Node3D

@export var keyboard_pan_speed: float = 24.0
@export var edge_pan_speed: float = 18.0
@export var drag_pan_speed: float = 0.08
@export var edge_margin_pixels: int = 24
@export var camera_arc_scroll_impulse: float = 1.2
@export var camera_arc_scroll_damping: float = 8.0
@export var camera_arc_max_scroll_speed: float = 1.2
@export var camera_arc_smoothing: float = 9.0
@export var far_camera_offset := Vector3(0.0, 50.0, 65.0)
@export var close_camera_offset := Vector3(0.0, 10.0, 16.0)
@export var far_tilt_degrees: float = -55.0
@export var close_tilt_degrees: float = -28.0
@export var min_tilt_degrees: float = -72.0
@export var max_tilt_degrees: float = -28.0
@export var map_limit: float = 55.0

@onready var camera: Camera3D = $Camera3D

var _window_active := true
var _dragging := false
var _arc_position := 0.0
var _arc_target := 0.0
var _arc_scroll_velocity := 0.0


func _ready() -> void:
	_apply_camera_arc(1.0)
	_confine_mouse_to_window()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_active = true
		_confine_mouse_to_window()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_active = false
		_dragging = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var keyboard_pan_direction := _get_keyboard_pan_direction()
	var edge_pan_direction := _get_edge_pan_direction()
	var pan_direction := keyboard_pan_direction + edge_pan_direction
	if pan_direction.length_squared() > 1.0:
		pan_direction = pan_direction.normalized()

	var speed := keyboard_pan_speed
	if keyboard_pan_direction.is_zero_approx() and not edge_pan_direction.is_zero_approx():
		speed = edge_pan_speed

	_move_on_ground(pan_direction * speed * delta)
	_update_camera_arc(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _dragging else Input.MOUSE_MODE_CONFINED
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_push_camera_arc_scroll(camera_arc_scroll_impulse)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_push_camera_arc_scroll(-camera_arc_scroll_impulse)

	if event is InputEventMouseMotion and _dragging:
		var drag_motion := _screen_motion_to_ground_motion(event.relative)
		_move_on_ground(drag_motion)


func _get_keyboard_pan_direction() -> Vector3:
	var input := Input.get_vector("pan_left", "pan_right", "pan_forward", "pan_back")
	return _screen_motion_to_ground_direction(input)


func _get_edge_pan_direction() -> Vector3:
	if not _window_active:
		return Vector3.ZERO

	var viewport := get_viewport()
	var mouse_position := viewport.get_mouse_position()
	var viewport_size := viewport.get_visible_rect().size
	var edge_input := Vector2.ZERO
	if (
		mouse_position.x < 0.0
		or mouse_position.y < 0.0
		or mouse_position.x > viewport_size.x
		or mouse_position.y > viewport_size.y
	):
		return Vector3.ZERO

	if mouse_position.x <= edge_margin_pixels:
		edge_input.x -= 1.0
	elif mouse_position.x >= viewport_size.x - edge_margin_pixels:
		edge_input.x += 1.0

	if mouse_position.y <= edge_margin_pixels:
		edge_input.y -= 1.0
	elif mouse_position.y >= viewport_size.y - edge_margin_pixels:
		edge_input.y += 1.0

	return _screen_motion_to_ground_direction(edge_input)


func _screen_motion_to_ground_direction(screen_direction: Vector2) -> Vector3:
	if screen_direction.is_zero_approx():
		return Vector3.ZERO

	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()

	return (right * screen_direction.x + forward * -screen_direction.y).normalized()


func _screen_motion_to_ground_motion(relative_motion: Vector2) -> Vector3:
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()

	return (-right * relative_motion.x + forward * relative_motion.y) * drag_pan_speed


func _move_on_ground(motion: Vector3) -> void:
	if motion.is_zero_approx():
		return

	global_position.x = clampf(global_position.x + motion.x, -map_limit, map_limit)
	global_position.z = clampf(global_position.z + motion.z, -map_limit, map_limit)


func center_on_world_position(world_position: Vector3) -> void:
	global_position.x = clampf(world_position.x, -map_limit, map_limit)
	global_position.z = clampf(world_position.z, -map_limit, map_limit)


func _update_camera_arc(delta: float) -> void:
	_update_camera_arc_scroll_velocity(delta)
	_apply_camera_arc(1.0 - exp(-camera_arc_smoothing * delta))


func _apply_camera_arc(weight: float) -> void:
	_arc_position = lerpf(_arc_position, _arc_target, weight)

	var arc_blend := smoothstep(0.0, 1.0, _arc_position)
	camera.position = camera.position.lerp(
		far_camera_offset.lerp(close_camera_offset, arc_blend),
		weight
	)
	camera.rotation_degrees.x = clampf(
		lerpf(far_tilt_degrees, close_tilt_degrees, arc_blend),
		min_tilt_degrees,
		max_tilt_degrees
	)


func _update_camera_arc_scroll_velocity(delta: float) -> void:
	if not is_zero_approx(_arc_scroll_velocity):
		_arc_target = clampf(_arc_target + _arc_scroll_velocity * delta, 0.0, 1.0)

	var damping_weight := 1.0 - exp(-camera_arc_scroll_damping * delta)
	_arc_scroll_velocity = lerpf(_arc_scroll_velocity, 0.0, damping_weight)


func _push_camera_arc_scroll(impulse: float) -> void:
	_arc_scroll_velocity = clampf(
		_arc_scroll_velocity + impulse,
		-camera_arc_max_scroll_speed,
		camera_arc_max_scroll_speed
	)


func _confine_mouse_to_window() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
