extends Node3D

@export var grid_path: NodePath
@export var footprint: Vector2i = Vector2i.ONE

@onready var map_grid: MapGrid = get_node(grid_path)

var anchor_cell: Vector2i = Vector2i.ZERO
var _is_occupying := false


func _ready() -> void:
	anchor_cell = map_grid.world_to_anchor_cell(global_position, footprint)
	_is_occupying = map_grid.occupy(anchor_cell, footprint, self)

	if not _is_occupying:
		push_warning("%s could not reserve grid cells at %s." % [name, anchor_cell])


func _exit_tree() -> void:
	if _is_occupying and is_instance_valid(map_grid):
		map_grid.release(anchor_cell, footprint)
