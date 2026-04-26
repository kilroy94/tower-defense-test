class_name CommandGrid
extends GridContainer

signal command_pressed(command_id: String)

const GRID_COLUMNS := 3
const SLOT_COUNT := GRID_COLUMNS * GRID_COLUMNS
const ROOT_MENU_ID := "root"

var _buttons: Array[Button] = []
var _slot_commands: Array[Dictionary] = []
var _viewport_containers: Array[SubViewportContainer] = []
var _portrait_roots: Array[Node3D] = []
var _portrait_cameras: Array[Camera3D] = []
var _menus: Dictionary = {}
var _current_menu_id := ROOT_MENU_ID
var _selected_command_id := ""


func _ready() -> void:
	columns = GRID_COLUMNS
	_ensure_buttons()
	set_commands([])


func set_commands(commands: Array[Dictionary]) -> void:
	set_menu(ROOT_MENU_ID, commands)
	show_menu(ROOT_MENU_ID)


func set_menu(menu_id: String, commands: Array[Dictionary]) -> void:
	_menus[menu_id] = commands
	if _current_menu_id == menu_id:
		_render_current_menu()


func show_menu(menu_id: String) -> void:
	if not _menus.has(menu_id):
		return

	_current_menu_id = menu_id
	_render_current_menu()


func set_selected_command(command_id: String) -> void:
	_selected_command_id = command_id
	_render_current_menu()


func handle_key_event(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false

	var slot_index := _get_slot_index_for_keycode(event.keycode)
	if slot_index >= 0:
		return _press_slot(slot_index)

	var command_id := _get_command_id_for_keycode(event.keycode)
	if command_id.is_empty():
		return false

	_activate_command(command_id)
	return true


func _render_current_menu() -> void:
	_ensure_buttons()

	for index in range(SLOT_COUNT):
		_slot_commands[index] = {}
		_configure_empty_button(_buttons[index])

	var commands: Array = _menus.get(_current_menu_id, [])
	for command in commands:
		var slot_index := _get_slot_index(command.get("slot", 0))
		if slot_index < 0 or slot_index >= SLOT_COUNT:
			continue

		_slot_commands[slot_index] = command

	for slot_index in range(SLOT_COUNT):
		var command := _slot_commands[slot_index]
		if command.is_empty():
			continue

		var button := _buttons[slot_index]
		var command_id := String(command.get("id", ""))
		button.tooltip_text = _get_command_tooltip(command)
		button.disabled = command_id.is_empty() and not command.has("menu")
		_apply_button_style(button, command_id == _selected_command_id)
		_apply_command_display(slot_index, command)


func _ensure_buttons() -> void:
	if _buttons.size() == SLOT_COUNT and _slot_commands.size() == SLOT_COUNT:
		return

	_create_buttons()


func _create_buttons() -> void:
	for child in get_children():
		child.queue_free()

	_buttons.clear()
	_slot_commands.clear()
	_viewport_containers.clear()
	_portrait_roots.clear()
	_portrait_cameras.clear()

	for index in range(SLOT_COUNT):
		var button := Button.new()
		button.custom_minimum_size = Vector2(52.0, 52.0)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_button_pressed.bind(index))
		button.add_theme_stylebox_override("hover", _create_button_style(Color(0.12, 0.13, 0.105, 0.98), Color(0.72, 0.64, 0.34, 1.0)))
		button.add_theme_stylebox_override("pressed", _create_button_style(Color(0.18, 0.17, 0.12, 1.0), Color(0.95, 0.78, 0.28, 1.0)))
		button.add_theme_stylebox_override("disabled", _create_button_style(Color(0.025, 0.027, 0.024, 0.86), Color(0.18, 0.18, 0.16, 1.0)))
		button.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72, 1.0))
		button.add_theme_color_override("font_disabled_color", Color(0.42, 0.42, 0.36, 1.0))
		button.add_theme_font_size_override("font_size", 14)
		add_child(button)

		var portrait_container := SubViewportContainer.new()
		portrait_container.name = "PortraitContainer"
		portrait_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		portrait_container.offset_left = 5.0
		portrait_container.offset_top = 5.0
		portrait_container.offset_right = -5.0
		portrait_container.offset_bottom = -5.0
		portrait_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_container.stretch = true
		portrait_container.visible = false
		button.add_child(portrait_container)

		var viewport := SubViewport.new()
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.size = Vector2i(48, 48)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		portrait_container.add_child(viewport)

		var portrait_root := Node3D.new()
		portrait_root.name = "PortraitRoot"
		viewport.add_child(portrait_root)

		var portrait_light := DirectionalLight3D.new()
		portrait_light.name = "PortraitLight"
		portrait_light.light_energy = 2.25
		portrait_light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
		viewport.add_child(portrait_light)

		var portrait_camera := Camera3D.new()
		portrait_camera.name = "PortraitCamera"
		portrait_camera.current = true
		viewport.add_child(portrait_camera)

		_buttons.append(button)
		_slot_commands.append({})
		_viewport_containers.append(portrait_container)
		_portrait_roots.append(portrait_root)
		_portrait_cameras.append(portrait_camera)
		_apply_button_style(button, false)


func _configure_empty_button(button: Button) -> void:
	button.text = ""
	button.tooltip_text = ""
	button.disabled = true
	var slot_index := _buttons.find(button)
	if slot_index >= 0:
		_clear_model_preview(slot_index)
	_apply_button_style(button, false)


func _get_slot_index(slot: Variant) -> int:
	if slot is Vector2i:
		return slot.y * GRID_COLUMNS + slot.x

	return int(slot)


func _on_button_pressed(slot_index: int) -> void:
	_press_slot(slot_index)


func _press_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _slot_commands.size():
		return false

	var command := _slot_commands[slot_index]
	if command.is_empty():
		return false

	if command.has("menu"):
		show_menu(String(command["menu"]))
		return true

	var command_id := String(command.get("id", ""))
	if command_id.is_empty():
		return false

	command_pressed.emit(command_id)
	return true


func _activate_command(command_id: String) -> void:
	for command in _slot_commands:
		if String(command.get("id", "")) != command_id:
			continue

		if command.has("menu"):
			show_menu(String(command["menu"]))
		else:
			command_pressed.emit(command_id)
		return


func _get_slot_index_for_keycode(keycode: int) -> int:
	match keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		KEY_6:
			return 5
		KEY_7:
			return 6
		KEY_8:
			return 7
		KEY_9:
			return 8

	return -1


func _get_command_id_for_keycode(keycode: int) -> String:
	var pressed_key := _normalize_hotkey(OS.get_keycode_string(keycode))
	if pressed_key.is_empty():
		return ""

	var hotkey_to_command_id := _get_current_hotkey_map()
	return String(hotkey_to_command_id.get(pressed_key, ""))


func _get_current_hotkey_map() -> Dictionary:
	var primary_counts: Dictionary = {}
	for command in _slot_commands:
		var primary_hotkey := _normalize_hotkey(command.get("hotkey", ""))
		if primary_hotkey.is_empty():
			continue

		primary_counts[primary_hotkey] = int(primary_counts.get(primary_hotkey, 0)) + 1

	var hotkey_to_command_id: Dictionary = {}
	var commands_needing_fallback: Array[Dictionary] = []
	for command in _slot_commands:
		var primary_hotkey := _normalize_hotkey(command.get("hotkey", ""))
		var command_id := String(command.get("id", ""))
		if primary_hotkey.is_empty() or command_id.is_empty():
			continue

		if int(primary_counts.get(primary_hotkey, 0)) == 1:
			hotkey_to_command_id[primary_hotkey] = command_id
		else:
			commands_needing_fallback.append(command)

	for command in commands_needing_fallback:
		var fallback_hotkey := _normalize_hotkey(command.get("fallback_hotkey", ""))
		var command_id := String(command.get("id", ""))
		if fallback_hotkey.is_empty() or command_id.is_empty() or hotkey_to_command_id.has(fallback_hotkey):
			continue

		hotkey_to_command_id[fallback_hotkey] = command_id

	return hotkey_to_command_id


func _get_command_tooltip(command: Dictionary) -> String:
	var tooltip := String(command.get("tooltip", command.get("label", "")))
	var hotkey := _get_effective_hotkey_for_command(command)
	if hotkey.is_empty():
		return tooltip

	if tooltip.is_empty():
		return "Hotkey: %s" % hotkey

	return "%s (%s)" % [tooltip, hotkey]


func _get_effective_hotkey_for_command(target_command: Dictionary) -> String:
	var hotkey_map := _get_current_hotkey_map()
	var command_id := String(target_command.get("id", ""))
	for hotkey in hotkey_map:
		if String(hotkey_map[hotkey]) == command_id:
			return String(hotkey)

	return ""


func _normalize_hotkey(value: Variant) -> String:
	return String(value).strip_edges().to_upper()


func _apply_button_style(button: Button, is_selected: bool) -> void:
	if is_selected:
		button.add_theme_stylebox_override("normal", _create_button_style(Color(0.16, 0.18, 0.1, 0.98), Color(0.95, 0.8, 0.24, 1.0)))
	else:
		button.add_theme_stylebox_override("normal", _create_button_style(Color(0.055, 0.06, 0.055, 0.94), Color(0.34, 0.34, 0.28, 1.0)))


func _apply_command_display(slot_index: int, command: Dictionary) -> void:
	var button := _buttons[slot_index]
	if command.has("model"):
		button.text = ""
		_show_model_preview(slot_index, command["model"] as Dictionary)
	else:
		_clear_model_preview(slot_index)
		button.text = String(command.get("label", ""))


func _show_model_preview(slot_index: int, model_data: Dictionary) -> void:
	_clear_model_preview(slot_index)
	_viewport_containers[slot_index].visible = true

	var model_type := String(model_data.get("type", "box"))
	var mesh_instance := MeshInstance3D.new()
	if model_type == "capsule":
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = float(model_data.get("radius", 0.45))
		capsule_mesh.height = float(model_data.get("height", 1.4))
		capsule_mesh.material = _create_model_material(model_data.get("color", Color(0.6, 0.7, 0.8, 1.0)))
		mesh_instance.mesh = capsule_mesh
		mesh_instance.position.y = capsule_mesh.height * 0.5
	elif model_type == "ramp":
		mesh_instance.mesh = _create_ramp_mesh(
			model_data.get("size", Vector3.ONE),
			_create_model_material(model_data.get("color", Color(0.6, 0.6, 0.55, 1.0)))
		)
		mesh_instance.position.y = (model_data.get("size", Vector3.ONE) as Vector3).y * 0.5
	else:
		var box_mesh := BoxMesh.new()
		box_mesh.size = model_data.get("size", Vector3.ONE)
		box_mesh.material = _create_model_material(model_data.get("color", Color(0.6, 0.6, 0.55, 1.0)))
		mesh_instance.mesh = box_mesh
		mesh_instance.position.y = box_mesh.size.y * 0.5

	_portrait_roots[slot_index].add_child(mesh_instance)
	_apply_model_camera(slot_index, model_data)


func _clear_model_preview(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _portrait_roots.size():
		return

	_viewport_containers[slot_index].visible = false
	for child in _portrait_roots[slot_index].get_children():
		child.queue_free()


func _apply_model_camera(slot_index: int, model_data: Dictionary) -> void:
	var offset: Vector3 = model_data.get("camera_offset", Vector3(0.0, 2.2, 5.2))
	var target: Vector3 = model_data.get("camera_target", Vector3(0.0, 1.0, 0.0))
	var fov := float(model_data.get("camera_fov", 42.0))
	var camera := _portrait_cameras[slot_index]
	camera.position = offset
	camera.look_at(target, Vector3.UP)
	camera.fov = fov


func _create_model_material(color: Color) -> StandardMaterial3D:
	var surface_material := StandardMaterial3D.new()
	if color.a < 1.0:
		surface_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface_material.albedo_color = color
	surface_material.roughness = 0.65
	return surface_material


func _create_ramp_mesh(ramp_size: Vector3, ramp_material: Material) -> ArrayMesh:
	var half_x := ramp_size.x * 0.5
	var half_y := ramp_size.y * 0.5
	var half_z := ramp_size.z * 0.5
	var ramp_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([
		Vector3(-half_x, -half_y, -half_z),
		Vector3(half_x, -half_y, -half_z),
		Vector3(-half_x, -half_y, half_z),
		Vector3(half_x, -half_y, half_z),
		Vector3(-half_x, half_y, half_z),
		Vector3(half_x, half_y, half_z)
	])
	var indices := PackedInt32Array([
		0, 2, 1,
		1, 2, 3,
		2, 4, 3,
		3, 4, 5,
		0, 1, 4,
		1, 5, 4,
		0, 4, 2,
		1, 3, 5
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	ramp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ramp_mesh.surface_set_material(0, ramp_material)
	return ramp_mesh


func _create_button_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	return style
