class_name PlacedRoom
extends RefCounted

var room_id: String
var instance_id: String
var grid_pos: Vector2i
var floor_number: int
var instance: Node2D
var occupied_cells: Array[Vector2i]
var door_grid_pos: Vector2i
var door_world_pos: Vector2

# Hallway wall tile we erased (for restoration)
var covered_hallway_id: String = ""
var covered_wall_cell: Vector2i
var covered_wall_tile_data: Dictionary = {}

# Room's own door-side wall is hidden
var door_side_wall_hidden: bool = false

# Runtime state
var current_quality: int = 0
var furniture_inside: Array[Vector2i] = []

# Guest assignment
var assigned_guest_id: String = ""
var is_available: bool = true


func _init(
	p_room_id: String = "",
	p_grid_pos: Vector2i = Vector2i.ZERO,
	p_floor: int = 1,
	p_instance: Node2D = null,
	p_cells: Array[Vector2i] = []
) -> void:
	room_id = p_room_id
	grid_pos = p_grid_pos
	floor_number = p_floor
	instance = p_instance
	occupied_cells = p_cells
	instance_id = "%s_%d_%d" % [room_id, grid_pos.x, grid_pos.y] if room_id else ""


func is_occupied() -> bool:
	return assigned_guest_id != ""


func to_dict() -> Dictionary:
	return {
		"room_id": room_id,
		"instance_id": instance_id,
		"grid_pos": {"x": grid_pos.x, "y": grid_pos.y},
		"floor_number": floor_number,
		"occupied_cells": _serialize_cells(occupied_cells),
		"door_grid_pos": {"x": door_grid_pos.x, "y": door_grid_pos.y},
		"door_world_pos": {"x": door_world_pos.x, "y": door_world_pos.y},
		"covered_hallway_id": covered_hallway_id,
		"covered_wall_cell": {"x": covered_wall_cell.x, "y": covered_wall_cell.y},
		"covered_wall_tile_data": covered_wall_tile_data,
		"door_side_wall_hidden": door_side_wall_hidden,
		"current_quality": current_quality,
		"furniture_inside": _serialize_cells(furniture_inside),
		"assigned_guest_id": assigned_guest_id,
		"is_available": is_available
	}


static func from_dict(data: Dictionary) -> PlacedRoom:
	var room := PlacedRoom.new()
	room.room_id = data.get("room_id", "")
	room.instance_id = data.get("instance_id", "")
	room.grid_pos = Vector2i(data["grid_pos"]["x"], data["grid_pos"]["y"])
	room.floor_number = data.get("floor_number", 1)
	room.occupied_cells = _deserialize_cells(data.get("occupied_cells", []))
	room.door_grid_pos = Vector2i(data["door_grid_pos"]["x"], data["door_grid_pos"]["y"])
	room.door_world_pos = Vector2(data["door_world_pos"]["x"], data["door_world_pos"]["y"])
	room.covered_hallway_id = data.get("covered_hallway_id", "")
	room.covered_wall_cell = Vector2i(data["covered_wall_cell"]["x"], data["covered_wall_cell"]["y"])
	room.covered_wall_tile_data = data.get("covered_wall_tile_data", {})
	room.door_side_wall_hidden = data.get("door_side_wall_hidden", false)
	room.current_quality = data.get("current_quality", 0)
	room.furniture_inside = _deserialize_cells(data.get("furniture_inside", []))
	room.assigned_guest_id = data.get("assigned_guest_id", "")
	room.is_available = data.get("is_available", true)
	return room


func _serialize_cells(cells: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell: Vector2i in cells:
		result.append({"x": cell.x, "y": cell.y})
	return result


static func _deserialize_cells(data: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item: Dictionary in data:
		result.append(Vector2i(item["x"], item["y"]))
	return result
