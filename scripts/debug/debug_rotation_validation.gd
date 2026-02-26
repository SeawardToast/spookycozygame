extends Node
## Debug rotation-dependent validation issues
## Enhanced to work with neighbor-based validation

@export var piece_id: String = "hallway_L"
@export var test_grid_pos: Vector2i = Vector2i(80, 8)

func _ready() -> void:
	print("\n╔══════════════════════════════════════╗")
	print("║  ROTATION VALIDATION DEBUG TOOL      ║")
	print("╚══════════════════════════════════════╝\n")
	print("Testing piece: %s" % piece_id)
	print("At position: %s\n" % test_grid_pos)

	# Test all 4 rotations at the same position
	var results: Array[Dictionary] = []
	for rot in range(4):
		var result: Dictionary = _test_rotation(piece_id, test_grid_pos, rot)
		results.append(result)

	# Summary comparison
	_print_summary(results)


func _test_rotation(p_id: String, grid_pos: Vector2i, rotation: int) -> Dictionary:
	print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("  ROTATION %d (%d°)" % [rotation, rotation * 90])
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

	var result: Dictionary = {
		"rotation": rotation,
		"valid": false,
		"nav_tiles": 0,
		"boundary_nav": 0,
		"connected_boundary": 0,
		"unconnected": []
	}

	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(p_id)
	if not piece_data:
		print("  ❌ ERROR: Piece not found\n")
		return result

	# Get cells
	var scene: PackedScene = load(piece_data.scene_path)
	if not scene:
		print("  ❌ ERROR: Could not load scene\n")
		return result

	var temp_instance: Node2D = scene.instantiate()
	var local_cells: Array[Vector2i] = BuildingLayoutData._get_tilemap_cells_from_instance(temp_instance)
	temp_instance.queue_free()

	if local_cells.is_empty():
		print("  ❌ ERROR: No cells found\n")
		return result

	var global_cells: Array[Vector2i] = BuildingLayoutData._transform_cells_for_placement(local_cells, grid_pos, rotation)
	print("  Occupied cells: %d" % global_cells.size())
	print("  Bounds: %s to %s" % [_get_min_cell(global_cells), _get_max_cell(global_cells)])

	# Get nav tiles
	var nav_tiles: Array[Vector2i] = BuildingLayoutData._get_rotated_nav_tiles(p_id, grid_pos, rotation)
	result["nav_tiles"] = nav_tiles.size()
	print("  Nav tiles: %d total" % nav_tiles.size())

	if nav_tiles.is_empty():
		print("  ❌ FAIL: No nav tiles\n")
		return result

	# Build valid adjacent nav set (same logic as validation)
	var valid_adjacent_nav: Dictionary = {}

	# From constructions
	var checked_pieces: Dictionary = {}
	for cell: Vector2i in global_cells:
		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var adj_cell: Vector2i = cell + dir
			if adj_cell in global_cells:
				continue

			if BuildingLayoutData.is_construction_at(adj_cell):
				var placed: BuildingLayoutData.PlacedPiece = BuildingLayoutData.get_construction_at(adj_cell)
				if placed.grid_pos in checked_pieces:
					continue
				checked_pieces[placed.grid_pos] = true

				var adj_nav: Array[Vector2i] = BuildingLayoutData._get_rotated_nav_tiles(
					placed.piece_id, placed.grid_pos, placed.rotation
				)
				for nav_pos: Vector2i in adj_nav:
					valid_adjacent_nav[nav_pos] = true

	# From connectable tiles
	var connectable_layers: Array[Node] = get_tree().get_nodes_in_group("construction_connectable")
	var checked_cells: Dictionary = {}
	for cell: Vector2i in global_cells:
		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var adj_cell: Vector2i = cell + dir
			if adj_cell in global_cells or adj_cell in checked_cells:
				continue
			checked_cells[adj_cell] = true

			for node in connectable_layers:
				if not node is TileMapLayer:
					continue
				var tilemap: TileMapLayer = node as TileMapLayer
				var tile_data: TileData = tilemap.get_cell_tile_data(adj_cell)
				if tile_data and tile_data.get_navigation_polygon(0):
					valid_adjacent_nav[adj_cell] = true
					break

	print("  Adjacent nav tiles: %d" % valid_adjacent_nav.size())

	if valid_adjacent_nav.is_empty():
		print("  ❌ FAIL: No adjacent nav tiles to connect to\n")
		return result

	# Find which edges are touching
	var touching_edges: Dictionary = {}
	for cell: Vector2i in global_cells:
		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var adj_cell: Vector2i = cell + dir
			if adj_cell in global_cells:
				continue

			if BuildingLayoutData.is_construction_at(adj_cell):
				touching_edges[dir] = true
			else:
				for node in connectable_layers:
					if not node is TileMapLayer:
						continue
					var tilemap: TileMapLayer = node as TileMapLayer
					var tile_data: TileData = tilemap.get_cell_tile_data(adj_cell)
					if tile_data and tile_data.get_navigation_polygon(0):
						touching_edges[dir] = true
						break

	print("  Touching edges: %s" % [_dirs_to_string(touching_edges.keys())])

	# Get nav tiles on touching edges only
	var edge_nav_tiles: Array[Vector2i] = []
	for nav_tile: Vector2i in nav_tiles:
		for dir: Vector2i in touching_edges.keys():
			var adj: Vector2i = nav_tile + dir
			if adj not in nav_tiles:
				edge_nav_tiles.append(nav_tile)
				break

	result["boundary_nav"] = edge_nav_tiles.size()
	print("  Nav tiles on touching edges: %d" % edge_nav_tiles.size())

	# Check connections
	var unconnected_tiles: Array[Vector2i] = []
	var connected_count: int = 0

	for nav_tile: Vector2i in edge_nav_tiles:
		var has_connection: bool = false
		var connection_dirs: Array[String] = []

		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var adj: Vector2i = nav_tile + dir
			if adj in valid_adjacent_nav:
				has_connection = true
				connection_dirs.append(_dir_name(dir))

		if has_connection:
			connected_count += 1
			if connected_count <= 3:  # Show first 3 connections
				print("    ✓ %s connects via %s" % [nav_tile, ", ".join(connection_dirs)])
		else:
			unconnected_tiles.append(nav_tile)

	result["connected_boundary"] = connected_count
	result["unconnected"] = unconnected_tiles

	# Show status
	print("")
	if unconnected_tiles.size() > 0:
		print("  ❌ VALIDATION FAILED")
		print("  %d/%d boundary nav tiles unconnected:" % [unconnected_tiles.size(), boundary_nav_tiles.size()])
		for tile in unconnected_tiles:
			print("    - %s" % tile)
		result["valid"] = false
	else:
		print("  ✅ VALIDATION PASSED")
		print("  All %d boundary nav tiles connected!" % boundary_nav_tiles.size())
		result["valid"] = true

	print("")
	return result


func _print_summary(results: Array[Dictionary]) -> void:
	print("\n╔══════════════════════════════════════╗")
	print("║           SUMMARY TABLE              ║")
	print("╚══════════════════════════════════════╝\n")

	print("Rot | Degrees | Nav | Boundary | Connected | Status")
	print("━━━━┼━━━━━━━━━┼━━━━━┼━━━━━━━━━━┼━━━━━━━━━━━┼━━━━━━━━")

	for result in results:
		var rot: int = result["rotation"]
		var deg: int = rot * 90
		var nav: int = result["nav_tiles"]
		var boundary: int = result["boundary_nav"]
		var connected: int = result["connected_boundary"]
		var status: String = "✅ PASS" if result["valid"] else "❌ FAIL"

		print(" %d  │  %3d°   │ %3d │    %3d   │    %3d    │ %s" % [rot, deg, nav, boundary, connected, status])

	# Check for rotation inconsistencies
	print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

	var all_pass: bool = true
	var any_pass: bool = false
	for result in results:
		if result["valid"]:
			any_pass = true
		else:
			all_pass = false

	if all_pass:
		print("✅ ALL ROTATIONS PASS - Piece works perfectly!")
	elif any_pass:
		print("⚠️  ROTATION INCONSISTENCY DETECTED")
		print("Some rotations pass while others fail.")
		print("This indicates asymmetric nav tile coverage")
		print("that doesn't align properly after rotation.")
	else:
		print("❌ ALL ROTATIONS FAIL")
		print("Check if connectable tiles exist adjacent to test position,")
		print("or if nav tiles are missing from the piece.")

	print("")


func _get_min_cell(cells: Array[Vector2i]) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var min_pos: Vector2i = cells[0]
	for cell in cells:
		min_pos.x = mini(min_pos.x, cell.x)
		min_pos.y = mini(min_pos.y, cell.y)
	return min_pos


func _get_max_cell(cells: Array[Vector2i]) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var max_pos: Vector2i = cells[0]
	for cell in cells:
		max_pos.x = maxi(max_pos.x, cell.x)
		max_pos.y = maxi(max_pos.y, cell.y)
	return max_pos


func _dir_name(dir: Vector2i) -> String:
	if dir == Vector2i.UP:
		return "UP"
	elif dir == Vector2i.DOWN:
		return "DOWN"
	elif dir == Vector2i.LEFT:
		return "LEFT"
	elif dir == Vector2i.RIGHT:
		return "RIGHT"
	else:
		return str(dir)


func _dirs_to_string(dirs: Array) -> String:
	var names: Array[String] = []
	for dir in dirs:
		names.append(_dir_name(dir))
	return ", ".join(names) if names.size() > 0 else "none"
