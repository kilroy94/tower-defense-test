class_name RtsProjectile
extends Node3D

const CombatUtilsRef = preload("res://scripts/systems/combat_utils.gd")

@export var projectile_id := ""
@export var projectile_name := "Projectile"
@export var travel_speed := 18.0
@export var turn_rate := 0.0
@export var impact_radius := 0.35
@export var lifetime := 4.0
@export var target_height := 0.9
@export var damage := 0

var source: Node3D = null
var target: Node3D = null
var _velocity := Vector3.ZERO
var _age := 0.0


func setup(definition: Dictionary, source_node: Node3D, target_node: Node3D, raw_damage: int, start_position: Vector3) -> void:
	source = source_node
	target = target_node
	damage = maxi(raw_damage, 0)
	global_position = start_position
	_apply_projectile_data(definition)
	_create_visual(definition.get("visual", {}))
	_initialize_velocity()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	if not _is_target_damageable():
		queue_free()
		return

	var target_position := _get_target_position()
	var to_target := target_position - global_position
	if to_target.length() <= impact_radius:
		_impact_target()
		return

	_update_velocity(to_target, delta)
	global_position += _velocity * delta
	if _velocity.length_squared() > 0.0001:
		look_at(global_position + _velocity.normalized(), Vector3.UP)


func _apply_projectile_data(definition: Dictionary) -> void:
	projectile_id = String(definition.get("id", projectile_id))
	projectile_name = String(definition.get("name", projectile_name))
	travel_speed = maxf(float(definition.get("travel_speed", travel_speed)), 0.01)
	turn_rate = maxf(float(definition.get("turn_rate", turn_rate)), 0.0)
	impact_radius = maxf(float(definition.get("impact_radius", impact_radius)), 0.01)
	lifetime = maxf(float(definition.get("lifetime", lifetime)), 0.01)
	target_height = float(definition.get("target_height", target_height))
	name = projectile_name


func _initialize_velocity() -> void:
	if not is_instance_valid(target):
		_velocity = -global_transform.basis.z * travel_speed
		return

	var to_target := _get_target_position() - global_position
	if to_target.length_squared() <= 0.0001:
		_velocity = -global_transform.basis.z * travel_speed
	else:
		_velocity = to_target.normalized() * travel_speed


func _update_velocity(to_target: Vector3, delta: float) -> void:
	var desired_velocity := to_target.normalized() * travel_speed
	if turn_rate <= 0.0 or _velocity.length_squared() <= 0.0001:
		_velocity = desired_velocity
		return

	var current_direction := _velocity.normalized()
	var desired_direction := desired_velocity.normalized()
	var max_turn := turn_rate * delta
	var next_direction := current_direction.slerp(desired_direction, clampf(max_turn, 0.0, 1.0)).normalized()
	_velocity = next_direction * travel_speed


func _impact_target() -> void:
	if _is_target_damageable() and damage > 0:
		CombatUtilsRef.apply_damage(target, damage)

	queue_free()


func _is_target_damageable() -> bool:
	return is_instance_valid(target) \
		and target.is_inside_tree() \
		and CombatUtilsRef.is_combatant(target) \
		and not CombatUtilsRef.is_invincible(target) \
		and CombatUtilsRef.get_current_health(target) > 0


func _get_target_position() -> Vector3:
	return target.global_position + Vector3.UP * target_height


func _create_visual(visual: Dictionary) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.mesh = _create_visual_mesh(visual)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


func _create_visual_mesh(visual: Dictionary) -> Mesh:
	var shape := String(visual.get("shape", "box"))
	var color: Color = visual.get("color", Color(0.85, 0.62, 0.28, 1.0))
	var size: Vector3 = visual.get("size", Vector3(0.16, 0.16, 0.75))
	var material := _create_material(color)

	if shape == "sphere":
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = maxf(size.x * 0.5, 0.01)
		sphere_mesh.height = maxf(size.y, 0.01)
		sphere_mesh.material = material
		return sphere_mesh

	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material
	return box_mesh


func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	return material
