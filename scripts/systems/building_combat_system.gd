class_name BuildingCombatSystem
extends Node

const CombatUtilsRef = preload("res://scripts/systems/combat_utils.gd")
const ATTACK_TYPE_MELEE := "melee"
const ATTACK_TYPE_RANGED := "ranged"

@export var projectiles_root_path: NodePath
@export var projectile_data_directory := "res://data/projectiles"

@onready var projectiles_root: Node3D = get_node(projectiles_root_path)

var _projectile_definitions: Dictionary = {}
var _attack_cooldowns: Dictionary = {}


func _ready() -> void:
	_load_projectile_data()


func _process(delta: float) -> void:
	for building in get_tree().get_nodes_in_group("rts_buildings"):
		if not (building is Node3D):
			continue

		_tick_building_attack(building, delta)

	_cleanup_cooldowns()


func _load_projectile_data() -> void:
	_projectile_definitions = GameData.load_projectile_definitions(projectile_data_directory)
	if _projectile_definitions.is_empty():
		push_warning("No projectile definitions were loaded from %s." % projectile_data_directory)


func _tick_building_attack(building: Node3D, delta: float) -> void:
	if not _can_building_attack(building):
		return

	var timer_key := building.get_instance_id()
	var remaining_cooldown := maxf(float(_attack_cooldowns.get(timer_key, 0.0)) - delta, 0.0)
	_attack_cooldowns[timer_key] = remaining_cooldown
	if remaining_cooldown > 0.0:
		return

	var target := _find_target_for_building(building)
	if target == null:
		return

	if _perform_building_attack(building, target):
		_attack_cooldowns[timer_key] = maxf(float(building.get_meta("attack_cooldown", 0.0)), 0.0)


func _can_building_attack(building: Node3D) -> bool:
	if int(building.get_meta("damage", 0)) <= 0:
		return false

	if float(building.get_meta("attack_range", 0.0)) <= 0.0:
		return false

	match String(building.get_meta("attack_type", "")):
		ATTACK_TYPE_MELEE:
			return true
		ATTACK_TYPE_RANGED:
			var projectile_id := String(building.get_meta("projectile_id", ""))
			return not projectile_id.is_empty() and _projectile_definitions.has(projectile_id)

	return false


func _find_target_for_building(building: Node3D) -> Node3D:
	var best_target: Node3D = null
	var best_distance := INF
	for enemy in get_tree().get_nodes_in_group("rts_enemies"):
		if not (enemy is Node3D):
			continue

		if not CombatUtilsRef.is_target_in_attack_range(building, enemy):
			continue

		var distance := CombatUtilsRef.get_horizontal_distance_to_target(building, enemy)
		if distance < best_distance:
			best_distance = distance
			best_target = enemy

	return best_target


func _perform_building_attack(building: Node3D, target: Node3D) -> bool:
	match String(building.get_meta("attack_type", "")):
		ATTACK_TYPE_MELEE:
			return bool(CombatUtilsRef.perform_melee_attack(building, target).get("success", false))
		ATTACK_TYPE_RANGED:
			return _launch_projectile(building, target)

	return false


func _launch_projectile(building: Node3D, target: Node3D) -> bool:
	var projectile_id := String(building.get_meta("projectile_id", ""))
	if not _projectile_definitions.has(projectile_id):
		push_warning("Building '%s' requested unknown projectile '%s'." % [building.name, projectile_id])
		return false

	var projectile_definition: Dictionary = _projectile_definitions[projectile_id]
	var projectile := RtsProjectile.new()
	var launch_height := float(projectile_definition.get("launch_height", 2.8))
	var start_position := building.global_position + Vector3.UP * launch_height
	projectiles_root.add_child(projectile)
	projectile.setup(
		projectile_definition,
		building,
		target,
		int(building.get_meta("damage", 0)),
		start_position
	)
	return true


func _cleanup_cooldowns() -> void:
	for timer_key in _attack_cooldowns.keys():
		if not is_instance_id_valid(int(timer_key)):
			_attack_cooldowns.erase(timer_key)
