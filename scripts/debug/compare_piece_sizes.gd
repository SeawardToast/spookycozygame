extends Node
## Compare hallway piece sizes to diagnose scale issues

func _ready() -> void:
	print("\n=== HALLWAY PIECE SIZE COMPARISON ===\n")

	_analyze_piece("hallway_straight", "res://scenes/buildings/hallway_straight.tscn")
	_analyze_piece("hallway_L", "res://scenes/buildings/hallway_L.tscn")
	_analyze_piece("hallway_L_inverted", "res://scenes/buildings/hallway_L_inverted.tscn")

	print("=================================\n")


func _analyze_piece(piece_name: String, scene_path: String) -> void:
	print("Analyzing: %s" % piece_name)

	var scene: PackedScene = load(scene_path)
	if not scene:
		print("  ERROR: Could not load scene\n")
		return

	var instance: Node2D = scene.instantiate()
	add_child(instance)

	var cells: Array[Vector2i] = _get_tilemap_cells(instance)

	if cells.is_empty():
		print("  No tiles found\n")
		instance.queue_free()
		return

	# Calculate bounds
	var min_x: int = cells[0].x
	var max_x: int = cells[0].x
	var min_y: int = cells[0].y
	var max_y: int = cells[0].y

	for cell: Vector2i in cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)

	var width: int = max_x - min_x + 1
	var height: int = max_y - min_y + 1
	var tile_count: int = cells.size()

	# Get registry data
	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(piece_name)
	var reg_size: Vector2i = piece_data.size if piece_data else Vector2i(-1, -1)

	print("  Tile count: %d" % tile_count)
	print("  Bounds: X[%d to %d], Y[%d to %d]" % [min_x, max_x, min_y, max_y])
	print("  Dimensions: %dx%d tiles" % [width, height])
	print("  Registry size: %s" % reg_size)

	if width > 5 or height > 5:
		print("  ⚠️  WARNING: This piece is very large (%dx%d)" % [width, height])
		print("     Straight hallway should be ~4x13 for reference")
		print("     L-turn should be similar or slightly larger")
		print("     If this seems wrong, check tile scale in scene")

	print()
	instance.queue_free()


func _get_tilemap_cells(instance: Node) -> Array[Vector2i]:
	var all_cells: Array[Vector2i] = []

	if instance is TileMapLayer:
		var tilemap: TileMapLayer = instance as TileMapLayer
		all_cells.append_array(tilemap.get_used_cells())

	for child in instance.get_children():
		all_cells.append_array(_get_tilemap_cells(child))

	return all_cells
