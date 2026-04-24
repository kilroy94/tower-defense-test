class_name GameData
extends RefCounted


static func load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Data file does not exist: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open data file: %s" % path)
		return {}

	var parse_result: Variant = JSON.parse_string(file.get_as_text())
	if parse_result == null or not (parse_result is Dictionary):
		push_warning("Could not parse data file as a JSON object: %s" % path)
		return {}

	return parse_result


static func load_unit_definition(path: String) -> Dictionary:
	var definition := load_json_file(path)
	if definition.is_empty() or _is_template_definition(definition):
		return {}

	return _normalize_unit_definition(definition)


static func load_enemy_definition(path: String) -> Dictionary:
	var definition := load_json_file(path)
	if definition.is_empty() or _is_template_definition(definition):
		return {}

	return _normalize_enemy_definition(definition)


static func load_building_definitions(directory_path: String) -> Array[Dictionary]:
	var buildings: Array[Dictionary] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_warning("Could not open building data directory: %s" % directory_path)
		return buildings

	var file_names := directory.get_files()
	file_names.sort()
	for file_name in file_names:
		if not file_name.ends_with(".json"):
			continue

		var definition_path := directory_path.path_join(file_name)
		var definition := load_json_file(definition_path)
		if definition.is_empty() or _is_template_definition(definition):
			continue

		buildings.append(_normalize_building_definition(definition))

	return buildings


static func _normalize_unit_definition(raw_definition: Dictionary) -> Dictionary:
	var definition := raw_definition.duplicate(true)
	definition["body_color"] = color_from_json(definition.get("body_color", [0.18, 0.78, 0.9, 1.0]))
	definition["stats"] = _normalize_stats_definition(definition.get("stats", {}), {
		"max_health": 100,
		"damage": 0,
		"armor": 0,
		"attack_type": "melee",
		"attack_speed": 1.0,
		"attack_range": 1.2,
		"attack_cooldown": 1.4,
		"projectile_id": ""
	})

	var portrait_camera: Dictionary = definition.get("portrait_camera", {})
	portrait_camera["offset"] = vector3_from_json(portrait_camera.get("offset", [0.0, 1.45, 4.0]))
	portrait_camera["target"] = vector3_from_json(portrait_camera.get("target", [0.0, 0.8, 0.0]))
	portrait_camera["fov"] = float(portrait_camera.get("fov", 36.0))
	definition["portrait_camera"] = portrait_camera

	var audio: Dictionary = definition.get("audio", {})
	audio["death"] = String(audio.get("death", ""))
	definition["audio"] = audio

	var commands: Array[Dictionary] = []
	for raw_command in definition.get("commands", []):
		if raw_command is Dictionary:
			commands.append(_normalize_command_definition(raw_command))
	definition["commands"] = commands

	return definition


static func _normalize_enemy_definition(raw_definition: Dictionary) -> Dictionary:
	var definition := raw_definition.duplicate(true)
	definition["body_color"] = color_from_json(definition.get("body_color", [0.75, 0.18, 0.18, 1.0]))
	definition["marker_color"] = color_from_json(definition.get("marker_color", [0.12, 0.02, 0.02, 1.0]))
	definition["stats"] = _normalize_stats_definition(definition.get("stats", {}), {
		"max_health": 100,
		"damage": 0,
		"armor": 0,
		"attack_type": "melee",
		"attack_speed": 1.0,
		"attack_range": 1.0,
		"attack_cooldown": 1.5,
		"projectile_id": ""
	})

	var collision: Dictionary = definition.get("collision", {})
	collision["radius"] = float(collision.get("radius", 0.45))
	collision["height"] = float(collision.get("height", 1.7))
	definition["collision"] = collision

	var movement: Dictionary = definition.get("movement", {})
	movement["move_speed"] = float(movement.get("move_speed", 7.0))
	movement["arrival_distance"] = float(movement.get("arrival_distance", 0.2))
	definition["movement"] = movement

	var portrait_camera: Dictionary = definition.get("portrait_camera", {})
	portrait_camera["offset"] = vector3_from_json(portrait_camera.get("offset", [0.0, 1.45, 4.0]))
	portrait_camera["target"] = vector3_from_json(portrait_camera.get("target", [0.0, 0.8, 0.0]))
	portrait_camera["fov"] = float(portrait_camera.get("fov", 36.0))
	definition["portrait_camera"] = portrait_camera

	var audio: Dictionary = definition.get("audio", {})
	audio["death"] = String(audio.get("death", ""))
	definition["audio"] = audio

	return definition


static func _is_template_definition(definition: Dictionary) -> bool:
	return bool(definition.get("template", false))


static func _normalize_building_definition(raw_definition: Dictionary) -> Dictionary:
	var definition := raw_definition.duplicate(true)
	definition["footprint"] = vector2i_from_json(definition.get("footprint", [1, 1]))
	definition["size"] = vector3_from_json(definition.get("size", [2.0, 2.0, 2.0]))
	definition["color"] = color_from_json(definition.get("color", [0.6, 0.6, 0.55, 1.0]))
	definition["stats"] = _normalize_stats_definition(definition.get("stats", {}), {
		"max_health": 500,
		"damage": 0,
		"armor": 0,
		"attack_type": "melee",
		"attack_speed": 0.0,
		"attack_range": 0.0,
		"attack_cooldown": 0.0,
		"projectile_id": ""
	})
	definition["pathable"] = bool(definition.get("pathable", false))
	definition["hotkey"] = String(definition.get("hotkey", ""))
	definition["fallback_hotkey"] = String(definition.get("fallback_hotkey", ""))

	var walkable_by: Array[String] = []
	for actor_type in definition.get("walkable_by", []):
		walkable_by.append(String(actor_type))
	definition["walkable_by"] = walkable_by

	var portrait_camera: Dictionary = definition.get("portrait_camera", {})
	definition["portrait_camera_offset"] = vector3_from_json(portrait_camera.get("offset", [0.0, 2.2, 5.2]))
	definition["portrait_camera_target"] = vector3_from_json(portrait_camera.get("target", [0.0, 1.0, 0.0]))
	definition["portrait_camera_fov"] = float(portrait_camera.get("fov", 42.0))
	definition.erase("portrait_camera")

	var audio: Dictionary = definition.get("audio", {})
	audio["death"] = String(audio.get("death", ""))
	definition["audio"] = audio

	var commands: Array[Dictionary] = []
	for raw_command in definition.get("commands", []):
		if raw_command is Dictionary:
			commands.append(_normalize_command_definition(raw_command))
	definition["commands"] = commands

	return definition


static func _normalize_command_definition(raw_definition: Dictionary) -> Dictionary:
	var definition := raw_definition.duplicate(true)
	if definition.has("slot"):
		definition["slot"] = vector2i_from_json(definition["slot"])

	definition["hotkey"] = String(definition.get("hotkey", ""))
	definition["fallback_hotkey"] = String(definition.get("fallback_hotkey", ""))

	return definition


static func _normalize_stats_definition(raw_stats: Variant, defaults: Dictionary) -> Dictionary:
	var stats: Dictionary = {}
	if raw_stats is Dictionary:
		stats = (raw_stats as Dictionary).duplicate(true)

	var normalized_defaults := defaults.duplicate(true)
	for key in normalized_defaults.keys():
		if not stats.has(key):
			stats[key] = normalized_defaults[key]

	stats["max_health"] = int(stats.get("max_health", normalized_defaults.get("max_health", 100)))
	stats["damage"] = int(stats.get("damage", normalized_defaults.get("damage", 0)))
	stats["armor"] = int(stats.get("armor", normalized_defaults.get("armor", 0)))
	stats["attack_type"] = String(stats.get("attack_type", normalized_defaults.get("attack_type", "melee")))
	stats["attack_speed"] = float(stats.get("attack_speed", normalized_defaults.get("attack_speed", 0.0)))
	stats["attack_range"] = float(stats.get("attack_range", normalized_defaults.get("attack_range", 0.0)))
	stats["attack_cooldown"] = float(stats.get("attack_cooldown", normalized_defaults.get("attack_cooldown", 0.0)))
	stats["projectile_id"] = String(stats.get("projectile_id", normalized_defaults.get("projectile_id", "")))
	return stats


static func vector2i_from_json(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value

	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))

	return Vector2i.ZERO


static func vector3_from_json(value: Variant) -> Vector3:
	if value is Vector3:
		return value

	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))

	return Vector3.ZERO


static func color_from_json(value: Variant) -> Color:
	if value is Color:
		return value

	if value is String:
		return Color.html(value)

	if value is Array and value.size() >= 3:
		var alpha := 1.0
		if value.size() >= 4:
			alpha = float(value[3])
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)

	return Color.WHITE


static func load_audio_streams(paths: Array) -> Array[AudioStream]:
	var audio_streams: Array[AudioStream] = []
	for path in paths:
		var audio_stream := load(String(path))
		if audio_stream is AudioStream:
			audio_streams.append(audio_stream)
		else:
			push_warning("Could not load audio stream: %s" % String(path))

	return audio_streams


static func load_audio_stream(path: String) -> AudioStream:
	var audio_stream := load(path)
	if audio_stream is AudioStream:
		return audio_stream

	push_warning("Could not load audio stream: %s" % path)
	return null
