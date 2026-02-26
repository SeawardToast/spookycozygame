extends Node2D

@onready var _door_marker: Marker2D = $DoorPosition
@onready var _interior: Area2D = $RoomInterior
@onready var _door_edge: TileMapLayer = $GameTileMap/door_edge
@onready var _door_side_wall: TileMapLayer = $GameTileMap/door_side_wall

const CELL_SIZE: int = 16


func _ready() -> void:
	RoomManager.reconnect_instance(BuildingLayoutData.world_to_grid(global_position), self)


func get_door_world_position() -> Vector2:
	return _door_marker.global_position


func get_door_grid_offset() -> Vector2i:
	var cells: Array[Vector2i] = _door_edge.get_used_cells()
	return cells[0] if cells.size() > 0 else Vector2i.ZERO


func get_interior_cells(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var collision: CollisionPolygon2D = _interior.get_node_or_null("CollisionPolygon2D")

	if not collision:
		# Fallback: use all floor tiles
		var floor_layer: TileMapLayer = get_node_or_null("GameTileMap/Floor")
		if floor_layer:
			for local_cell: Vector2i in floor_layer.get_used_cells():
				cells.append(origin + local_cell)
		return cells

	# Convert collision polygon to grid cells
	var polygon: PackedVector2Array = collision.polygon
	if polygon.is_empty():
		return cells

	# Find bounds
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF

	for point: Vector2 in polygon:
		var world_point: Vector2 = _interior.to_global(point)
		min_x = minf(min_x, world_point.x)
		max_x = maxf(max_x, world_point.x)
		min_y = minf(min_y, world_point.y)
		max_y = maxf(max_y, world_point.y)

	# Convert to grid cells
	var start_x: int = int(min_x / CELL_SIZE)
	var end_x: int = int(max_x / CELL_SIZE) + 1
	var start_y: int = int(min_y / CELL_SIZE)
	var end_y: int = int(max_y / CELL_SIZE) + 1

	for x: int in range(start_x, end_x):
		for y: int in range(start_y, end_y):
			cells.append(Vector2i(x, y))

	return cells


func hide_door_side_wall() -> void:
	if _door_side_wall:
		_door_side_wall.visible = false
		# Also send to back in case visibility doesn't work
		_door_side_wall.z_index = -10
	else:
		push_warning("door_side_wall layer not found")


func show_door_side_wall() -> void:
	if _door_side_wall:
		_door_side_wall.visible = true
		_door_side_wall.z_index = 0
