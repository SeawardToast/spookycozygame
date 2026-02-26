extends Node
## Debug script to visualize tile coordinates for building pieces
## Attach this to a Node in your scene and set the piece_scene_path

@export_file("*.tscn") var piece_scene_path: String = "res://scenes/buildings/hallway_L_inverted.tscn"
@export var rotation: int = 0  ## 0-3 for 0°, 90°, 180°, 270°

func _ready() -> void:
	print("\n=== DEBUG PIECE CELLS ===")
	print("Scene: %s" % piece_scene_path)
	print("Rotation: %d (%d degrees)" % [rotation, rotation * 90])

	var scene: PackedScene = load(piece_scene_path)
	if not scene:
		print("ERROR: Failed to load scene")
		return

	var instance: Node2D = scene.instantiate()
	instance.rotation_degrees = rotation * 90
	add_child(instance)

	# Get local cells from tilemap
	var local_cells: Array[Vector2i] = _get_tilemap_cells_from_instance(instance)

	print("\nLocal cells (before rotation transform):")
	print("  Count: %d" % local_cells.size())
	if local_cells.size() > 0:
		var min_x: int = local_cells[0].x
		var max_x: int = local_cells[0].x
		var min_y: int = local_cells[0].y
		var max_y: int = local_cells[0].y

		for cell: Vector2i in local_cells:
			min_x = mini(min_x, cell.x)
			max_x = maxi(max_x, cell.x)
			min_y = mini(min_y, cell.y)
			max_y = maxi(max_y, cell.y)
			print("    %s" % cell)

		print("\nBounds:")
		print("  X: [%d to %d] (width: %d)" % [min_x, max_x, max_x - min_x + 1])
		print("  Y: [%d to %d] (height: %d)" % [min_y, max_y, max_y - min_y + 1])

		if min_x < 0 or min_y < 0:
			print("\n⚠️  WARNING: Negative coordinates detected!")
			print("   This will cause placement issues.")
			print("   All tiles should start from (0, 0) or positive coordinates.")

	# Now test rotation transformation
	print("\nAfter rotation transform (as used in placement):")
	var test_origin: Vector2i = Vector2i(5, 5)  # Test placement at grid (5,5)
	var transformed_cells: Array[Vector2i] = _transform_cells_for_placement(local_cells, test_origin, rotation)

	for i in range(transformed_cells.size()):
		print("  Local %s -> Global %s" % [local_cells[i], transformed_cells[i]])

	instance.queue_free()
	print("\n=========================\n")


func _get_tilemap_cells_from_instance(instance: Node) -> Array[Vector2i]:
	"""Recursively find all TileMapLayer nodes and extract their used cells"""
	var all_cells: Array[Vector2i] = []

	if instance is TileMapLayer:
		var tilemap: TileMapLayer = instance as TileMapLayer
		var used_cells: Array[Vector2i] = tilemap.get_used_cells()
		all_cells.append_array(used_cells)

	# Recursively check children
	for child in instance.get_children():
		var child_cells: Array[Vector2i] = _get_tilemap_cells_from_instance(child)
		all_cells.append_array(child_cells)

	return all_cells


func _transform_cells_for_placement(local_cells: Array[Vector2i], origin: Vector2i, rot: int) -> Array[Vector2i]:
	"""Transform local tilemap cells to global grid coordinates with rotation applied"""
	var transformed: Array[Vector2i] = []

	for cell: Vector2i in local_cells:
		var rotated_cell: Vector2i = cell

		# Apply rotation transformation
		match rot:
			0:  # 0 degrees - no change
				rotated_cell = cell
			1:  # 90 degrees clockwise
				rotated_cell = Vector2i(-cell.y, cell.x)
			2:  # 180 degrees
				rotated_cell = Vector2i(-cell.x, -cell.y)
			3:  # 270 degrees clockwise (90 CCW)
				rotated_cell = Vector2i(cell.y, -cell.x)

		# Add origin offset to get global grid position
		transformed.append(origin + rotated_cell)

	return transformed
