class_name BuildingCombatSystem
extends Node

const CombatUtilsRef = preload("res://scripts/systems/combat_utils.gd")
const ATTACK_TYPE_MELEE := "melee"
const ATTACK_TYPE_RANGED := "ranged"
const DEFAULT_TARGET_SCAN_INTERVAL := 0.2
const DEFAULT_COMBAT_TICK_INTERVAL := 1.0 / 60.0

@export var projectiles_root_path: NodePath
@export var projectile_data_directory := "res://data/projectiles"
@export var target_scan_interval := DEFAULT_TARGET_SCAN_INTERVAL
@export var combat_tick_interval := DEFAULT_COMBAT_TICK_INTERVAL

@onready var projectiles_root: Node3D = get_node(projectiles_root_path)

var _projectile_definitions: Dictionary = {}
var _attack_cooldowns: Dictionary = {}
var _target_scan_timers: Dictionary = {}
var _building_attack_enabled: Dictionary = {}
var _combat_tick_timer := 0.0


func _ready() -> void:
	_load_projectile_data()


func _process(delta: float) -> void:
	_combat_tick_timer += delta
	var tick_interval := maxf(combat_tick_interval, 0.01)
	if _combat_tick_timer < tick_interval:
		return

	var tick_delta := _combat_tick_timer
	_combat_tick_timer = 0.0

	var enemies := get_tree().get_nodes_in_group("rts_enemies")
	for building in get_tree().get_nodes_in_group("rts_buildings"):
		if not (building is Node3D):
			continue

		_tick_building_attack(building, enemies, tick_delta)

	_cleanup_tracking()


func _load_projectile_data() -> void:
	_projectile_definitions = GameData.load_projectile_definitions(projectile_data_directory)
	if _projectile_definitions.is_empty():
		push_warning("No projectile definitions were loaded from %s." % projectile_data_directory)


func _tick_building_attack(building: Node3D, enemies: Array[Node], delta: float) -> void:
	if not _can_building_attack(building):
		return

	var timer_key := building.get_instance_id()
	var remaining_cooldown := maxf(float(_attack_cooldowns.get(timer_key, 0.0)) - delta, 0.0)
	_attack_cooldowns[timer_key] = remaining_cooldown
	if remaining_cooldown > 0.0:
		return

	if enemies.is_empty():
		return

	var remaining_scan_time := maxf(float(_target_scan_timers.get(timer_key, _get_initial_target_scan_delay(timer_key))) - delta, 0.0)
	_target_scan_timers[timer_key] = remaining_scan_time
	if remaining_scan_time > 0.0:
		return

	_target_scan_timers[timer_key] = maxf(target_scan_interval, 0.01)
	var target := _find_target_for_building(building, enemies)
	if target == null:
		return

	if _perform_building_attack(building, target):
		_attack_cooldowns[timer_key] = maxf(float(building.get_meta("attack_cooldown", 0.0)), 0.0)


func _can_building_attack(building: Node3D) -> bool:
	var building_id := building.get_instance_id()
	if _building_attack_enabled.has(building_id):
		return bool(_building_attack_enabled[building_id])

	var can_attack := _compute_can_building_attack(building)
	_building_attack_enabled[building_id] = can_attack
	return can_attack


func _compute_can_building_attack(building: Node3D) -> bool:
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


func _find_target_for_building(building: Node3D, enemies: Array[Node]) -> Node3D:
	var best_target: Node3D = null
	var best_distance := INF
	for enemy in enemies:
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


func _get_initial_target_scan_delay(instance_id: int) -> float:
	var interval := maxf(target_scan_interval, 0.01)
	return float(instance_id % 1000) / 1000.0 * interval


func _cleanup_tracking() -> void:
	for timer_key in _attack_cooldowns.keys():
		if is_instance_id_valid(int(timer_key)):
			continue

		_attack_cooldowns.erase(timer_key)
		_target_scan_timers.erase(timer_key)
		_building_attack_enabled.erase(timer_key)
