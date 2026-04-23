class_name SelectionPanel
extends PanelContainer

signal portrait_double_clicked

@export var portrait_viewport_path: NodePath
@export var portrait_root_path: NodePath
@export var portrait_camera_path: NodePath
@export var name_label_path: NodePath

@onready var portrait_viewport: SubViewport = get_node(portrait_viewport_path)
@onready var portrait_click_target: Control = portrait_viewport.get_parent()
@onready var portrait_root: Node3D = get_node(portrait_root_path)
@onready var portrait_camera: Camera3D = get_node(portrait_camera_path)
@onready var name_label: Label = get_node(name_label_path)

var _queue_strip: HBoxContainer
var _queue_cells: Array[PanelContainer] = []
var _queue_viewport_containers: Array[SubViewportContainer] = []
var _queue_roots: Array[Node3D] = []
var _queue_cameras: Array[Camera3D] = []


func _ready() -> void:
	portrait_click_target.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait_click_target.gui_input.connect(_on_portrait_gui_input)
	_create_queue_strip()
	clear_selection()


func show_unit(unit: RtsUnit) -> void:
	_clear_portrait()
	name_label.text = unit.unit_name
	show_action_queue(unit.get_action_queue())

	var capsule := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	capsule_mesh.height = 1.4
	capsule_mesh.material = _create_material(unit.body_color)
	capsule.mesh = capsule_mesh
	capsule.position.y = 0.7
	portrait_root.add_child(capsule)
	_apply_portrait_camera(unit.portrait_camera_offset, unit.portrait_camera_target, unit.portrait_camera_fov)


func show_enemy(enemy: RtsEnemy) -> void:
	_clear_portrait()
	name_label.text = enemy.enemy_name
	show_action_queue([])

	var capsule := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = enemy.collision_radius + 0.08
	capsule_mesh.height = enemy.collision_height
	capsule_mesh.material = _create_material(enemy.body_color)
	capsule.mesh = capsule_mesh
	capsule.position.y = enemy.collision_height * 0.5
	portrait_root.add_child(capsule)
	_apply_portrait_camera(enemy.portrait_camera_offset, enemy.portrait_camera_target, enemy.portrait_camera_fov)


func show_building(building: Node) -> void:
	_clear_portrait()
	name_label.text = String(building.get_meta("building_name", "Building"))
	show_action_queue([])

	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = _get_building_size(building)
	box_mesh.material = _create_material(_get_building_color(building))
	box.mesh = box_mesh
	box.position.y = box_mesh.size.y * 0.5
	portrait_root.add_child(box)
	_apply_portrait_camera(
		_get_portrait_camera_offset(building),
		_get_portrait_camera_target(building),
		_get_portrait_camera_fov(building)
	)


func clear_selection() -> void:
	_clear_portrait()
	name_label.text = "No selection"
	show_action_queue([])
	_apply_portrait_camera(Vector3(0.0, 1.45, 4.0), Vector3(0.0, 0.8, 0.0), 36.0)


func show_action_queue(action_queue: Array[Dictionary]) -> void:
	if _queue_strip == null:
		return

	var waiting_actions: Array = action_queue.slice(1)
	_queue_strip.visible = not waiting_actions.is_empty()
	for index in range(_queue_cells.size()):
		var cell := _queue_cells[index]
		if index < waiting_actions.size():
			var action: Dictionary = waiting_actions[index]
			cell.visible = true
			cell.tooltip_text = String(action.get("label", "Queued action"))
			var label: Label = cell.get_node("Label")
			if action.has("model") and not (action["model"] as Dictionary).is_empty():
				label.text = ""
				_show_queue_model(index, action["model"] as Dictionary)
			else:
				_clear_queue_model(index)
				label.text = _get_queue_label(String(action.get("label", "")))
			cell.add_theme_stylebox_override("panel", _create_queue_cell_style(action.get("color", Color(0.8, 0.75, 0.42, 1.0))))
		else:
			_clear_queue_model(index)
			cell.visible = false


func _clear_portrait() -> void:
	for child in portrait_root.get_children():
		child.queue_free()


func _get_building_size(building: Node) -> Vector3:
	if building.has_meta("building_size"):
		return building.get_meta("building_size")

	return Vector3(2.0, 2.0, 2.0)


func _get_building_color(building: Node) -> Color:
	if building.has_meta("building_color"):
		return building.get_meta("building_color")

	return Color(0.6, 0.6, 0.55, 1.0)


func _get_portrait_camera_offset(node: Node) -> Vector3:
	if node.has_meta("portrait_camera_offset"):
		return node.get_meta("portrait_camera_offset")

	return Vector3(0.0, 2.2, 5.2)


func _get_portrait_camera_target(node: Node) -> Vector3:
	if node.has_meta("portrait_camera_target"):
		return node.get_meta("portrait_camera_target")

	return Vector3(0.0, 1.0, 0.0)


func _get_portrait_camera_fov(node: Node) -> float:
	if node.has_meta("portrait_camera_fov"):
		return float(node.get_meta("portrait_camera_fov"))

	return 42.0


func _apply_portrait_camera(offset: Vector3, target: Vector3, fov: float) -> void:
	var stage_origin := portrait_root.global_position
	portrait_camera.global_position = stage_origin + offset
	portrait_camera.look_at(stage_origin + target, Vector3.UP)
	portrait_camera.fov = fov


func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.roughness = 0.65
	return material


func _create_queue_strip() -> void:
	_queue_strip = HBoxContainer.new()
	_queue_strip.name = "ActionQueue"
	_queue_strip.add_theme_constant_override("separation", 5)
	_queue_strip.visible = false
	name_label.get_parent().add_child(_queue_strip)

	for index in range(5):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(42.0, 34.0)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP

		var label := Label.new()
		label.name = "Label"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(0.94, 0.9, 0.72, 1.0))
		cell.add_child(label)

		var viewport_container := SubViewportContainer.new()
		viewport_container.name = "PortraitContainer"
		viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		viewport_container.offset_left = 3.0
		viewport_container.offset_top = 3.0
		viewport_container.offset_right = -3.0
		viewport_container.offset_bottom = -3.0
		viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport_container.stretch = true
		viewport_container.visible = false
		cell.add_child(viewport_container)

		var viewport := SubViewport.new()
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.size = Vector2i(42, 34)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport_container.add_child(viewport)

		var root := Node3D.new()
		root.name = "PortraitRoot"
		viewport.add_child(root)

		var light := DirectionalLight3D.new()
		light.name = "PortraitLight"
		light.light_energy = 2.25
		light.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
		viewport.add_child(light)

		var camera := Camera3D.new()
		camera.name = "PortraitCamera"
		camera.current = true
		viewport.add_child(camera)

		_queue_strip.add_child(cell)
		_queue_cells.append(cell)
		_queue_viewport_containers.append(viewport_container)
		_queue_roots.append(root)
		_queue_cameras.append(camera)


func _create_queue_cell_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r * 0.28, color.g * 0.28, color.b * 0.28, 0.95)
	style.border_color = Color(color.r, color.g, color.b, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 4.0
	style.content_margin_top = 3.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 3.0
	return style


func _get_queue_label(action_label: String) -> String:
	var words := action_label.split(" ", false)
	if words.size() >= 2:
		return "%s%s" % [String(words[0]).substr(0, 1), String(words[1]).substr(0, 1)]

	return action_label.substr(0, 2)


func _show_queue_model(index: int, model_data: Dictionary) -> void:
	_clear_queue_model(index)
	_queue_viewport_containers[index].visible = true

	var mesh_instance := MeshInstance3D.new()
	var model_type := String(model_data.get("type", "box"))
	if model_type == "capsule":
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = float(model_data.get("radius", 0.45))
		capsule_mesh.height = float(model_data.get("height", 1.4))
		capsule_mesh.material = _create_material(model_data.get("color", Color(0.6, 0.7, 0.8, 1.0)))
		mesh_instance.mesh = capsule_mesh
		mesh_instance.position.y = capsule_mesh.height * 0.5
	else:
		var box_mesh := BoxMesh.new()
		box_mesh.size = model_data.get("size", Vector3.ONE)
		box_mesh.material = _create_material(model_data.get("color", Color(0.6, 0.6, 0.55, 1.0)))
		mesh_instance.mesh = box_mesh
		mesh_instance.position.y = box_mesh.size.y * 0.5

	_queue_roots[index].add_child(mesh_instance)
	_apply_queue_model_camera(index, model_data)


func _clear_queue_model(index: int) -> void:
	if index < 0 or index >= _queue_roots.size():
		return

	_queue_viewport_containers[index].visible = false
	for child in _queue_roots[index].get_children():
		child.queue_free()


func _apply_queue_model_camera(index: int, model_data: Dictionary) -> void:
	var offset: Vector3 = model_data.get("camera_offset", Vector3(0.0, 2.2, 5.2))
	var target: Vector3 = model_data.get("camera_target", Vector3(0.0, 1.0, 0.0))
	var fov := float(model_data.get("camera_fov", 42.0))
	var camera := _queue_cameras[index]
	camera.position = offset
	camera.look_at(target, Vector3.UP)
	camera.fov = fov


func _on_portrait_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed \
		and event.double_click:
		portrait_double_clicked.emit()
