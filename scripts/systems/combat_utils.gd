class_name CombatUtils
extends RefCounted

const DEFAULT_COMBAT_RADIUS := 0.45


static func is_combatant(node: Node) -> bool:
	return is_instance_valid(node) \
		and node.is_inside_tree() \
		and _has_health_data(node)


static func is_target_valid(attacker: Node, target: Node) -> bool:
	if not is_combatant(attacker) or not is_combatant(target):
		return false

	if attacker == target:
		return false

	if is_invincible(target):
		return false

	return get_current_health(target) > 0


static func get_attack_range(attacker: Node) -> float:
	return maxf(_get_float_value(attacker, "attack_range", 0.0), 0.0)


static func is_target_in_attack_range(attacker: Node3D, target: Node3D, override_range: float = -1.0) -> bool:
	if not is_target_valid(attacker, target):
		return false

	var attack_range := override_range
	if attack_range < 0.0:
		attack_range = get_attack_range(attacker)

	return get_horizontal_distance_to_target(attacker, target) <= attack_range


static func perform_melee_attack(attacker: Node3D, target: Node3D) -> Dictionary:
	if not is_target_valid(attacker, target):
		return {
			"success": false,
			"reason": "invalid_target"
		}

	if not is_target_in_attack_range(attacker, target):
		return {
			"success": false,
			"reason": "out_of_range"
		}

	var damage: int = maxi(_get_int_value(attacker, "damage", 0), 0)
	if damage <= 0:
		return {
			"success": false,
			"reason": "no_damage"
		}

	var damage_result: Dictionary = apply_damage(target, damage)
	damage_result["success"] = damage_result.get("applied", false)
	damage_result["reason"] = "ok" if damage_result["success"] else "no_effect"
	damage_result["damage"] = damage
	return damage_result


static func get_horizontal_distance_to_target(attacker: Node3D, target: Node3D) -> float:
	var attacker_position := _to_horizontal_vector(attacker.global_position)
	var closest_target_position := _get_closest_target_horizontal_point(target, attacker_position)
	return attacker_position.distance_to(closest_target_position)


static func apply_damage(target: Node, raw_damage: int) -> Dictionary:
	if not is_combatant(target):
		return {
			"applied": false,
			"reason": "invalid_target"
		}

	if is_invincible(target):
		return {
			"applied": false,
			"reason": "invincible",
			"previous_health": get_current_health(target),
			"current_health": get_current_health(target),
			"max_health": get_max_health(target),
			"is_dead": false
		}

	var damage := maxi(raw_damage, 0)
	var previous_health := get_current_health(target)
	var next_health := maxi(previous_health - damage, 0)
	if next_health == previous_health:
		return {
			"applied": false,
			"reason": "no_health_change",
			"previous_health": previous_health,
			"current_health": previous_health,
			"max_health": get_max_health(target),
			"is_dead": previous_health <= 0
		}

	if target.has_method("set_health"):
		target.call("set_health", next_health)
	else:
		_set_node_health(target, next_health)

	return {
		"applied": true,
		"reason": "ok",
		"previous_health": previous_health,
		"current_health": get_current_health(target),
		"max_health": get_max_health(target),
		"is_dead": get_current_health(target) <= 0
	}


static func get_current_health(node: Node) -> int:
	if node.has_method("get_health"):
		return int(node.call("get_health"))

	return int(node.get_meta("current_health", 0))


static func get_max_health(node: Node) -> int:
	if node.has_method("get_max_health"):
		return int(node.call("get_max_health"))

	return int(node.get_meta("max_health", 0))


static func is_invincible(node: Node) -> bool:
	return get_max_health(node) < 0


static func _has_health_data(node: Node) -> bool:
	return node.has_method("get_health") \
		or (node.has_meta("current_health") and node.has_meta("max_health"))


static func _set_node_health(node: Node, current_health: int) -> void:
	var max_health := get_max_health(node)
	if max_health < 0:
		node.set_meta("current_health", -1)
		if node.has_meta("stats"):
			var invincible_stats: Dictionary = node.get_meta("stats", {})
			invincible_stats["current_health"] = -1
			node.set_meta("stats", invincible_stats)
		return

	var clamped_health := clampi(current_health, 0, max_health)
	node.set_meta("current_health", clamped_health)

	if node.has_meta("stats"):
		var stats: Dictionary = node.get_meta("stats", {})
		stats["current_health"] = clamped_health
		node.set_meta("stats", stats)


static func _get_closest_target_horizontal_point(target: Node3D, attacker_position: Vector2) -> Vector2:
	if target.has_meta("building_size"):
		var building_size: Vector3 = target.get_meta("building_size", Vector3.ONE)
		var center := _to_horizontal_vector(target.global_position)
		return Vector2(
			clampf(attacker_position.x, center.x - (building_size.x * 0.5), center.x + (building_size.x * 0.5)),
			clampf(attacker_position.y, center.y - (building_size.z * 0.5), center.y + (building_size.z * 0.5))
		)

	var target_center := _to_horizontal_vector(target.global_position)
	var target_radius := _get_combat_radius(target)
	var to_attacker := attacker_position - target_center
	if is_zero_approx(to_attacker.length_squared()):
		return target_center

	return target_center + to_attacker.normalized() * target_radius


static func _get_combat_radius(target: Node) -> float:
	if _has_property(target, "collision_radius"):
		return maxf(float(target.get("collision_radius")), 0.0)

	return maxf(_get_float_value(target, "combat_radius", DEFAULT_COMBAT_RADIUS), DEFAULT_COMBAT_RADIUS)


static func _get_float_value(node: Node, property_name: String, fallback: float) -> float:
	if _has_property(node, property_name):
		return float(node.get(property_name))

	if node.has_meta(property_name):
		return float(node.get_meta(property_name))

	return fallback


static func _get_int_value(node: Node, property_name: String, fallback: int) -> int:
	if _has_property(node, property_name):
		return int(node.get(property_name))

	if node.has_meta(property_name):
		return int(node.get_meta(property_name))

	return fallback


static func _has_property(node: Object, property_name: String) -> bool:
	for property_info in node.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true

	return false


static func _to_horizontal_vector(world_position: Vector3) -> Vector2:
	return Vector2(world_position.x, world_position.z)
