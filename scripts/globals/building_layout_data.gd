# LayoutData.gd
# Tracks all placed building pieces and provides spatial queries
extends Node

signal layout_changed(grid_pos: Vector2i)
signal piece_added(grid_pos: Vector2i, piece_id: String)
signal piece_removed(grid_pos: Vector2i, piece_id: String)

# Grid cell size in pixels (adjust to match your tile size)
@export var cell_size: int = 16

# Debug flag for validation logging
var debug_validation: bool = false

# Layer-separated placement tracking
var construction_pieces: Dictionary = {}   # grid_pos -> PlacedPiece (CONSTRUCTION type)
var furniture_pieces: Dictionary = {}      # grid_pos -> PlacedPiece (FURNITURE type)
var construction_cells: Dictionary = {}    # grid_pos -> origin_grid_pos
var furniture_cells: Dictionary = {}       # grid_pos -> origin_grid_pos

# Pending custom_data for loaded pieces (used during load)
var pending_custom_data: Dictionary = {}  # grid_pos -> custom_data

class PlacedPiece:
	var piece_id: String
	var grid_pos: Vector2i  # Origin position
	var rotation: int  # 0-3
	var instance: Node2D  # Scene instance
	var occupied_cells: Array[Vector2i]  # All cells this piece occupies
	var building_type: DataTypes.BuildingType  # CONSTRUCTION or FURNITURE
	var custom_data: Dictionary = {}  # Piece-specific data (e.g., chest inventory IDs)

	func _init(p_id: String, p_pos: Vector2i, p_rot: int, p_instance: Node2D, p_cells: Array[Vector2i], p_type: DataTypes.BuildingType, p_custom_data: Dictionary = {}) -> void:
		piece_id = p_id
		grid_pos = p_pos
		rotation = p_rot
		instance = p_instance
		occupied_cells = p_cells
		building_type = p_type
		custom_data = p_custom_data

func _ready() -> void:
	pass


# =============================================
# PLACEMENT
# =============================================

func place_piece(piece_id: String, grid_pos: Vector2i, rotation: int, instance: Node2D) -> bool:
	"""Place a piece at the given grid position"""
	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(piece_id)
	if not piece_data:
		push_error("LayoutData: Unknown piece id: %s" % piece_id)
		return false

	# Calculate all cells this piece will occupy
	var cells: Array[Vector2i] = []

	# Try to get actual cells from TileMap
	var local_cells: Array[Vector2i] = _get_tilemap_cells_from_instance(instance)
	if local_cells.size() > 0:
		# Use actual TileMap cells with rotation applied
		cells = _transform_cells_for_placement(local_cells, grid_pos, rotation)
		print("LayoutData: Using %d TileMap cells for %s" % [cells.size(), piece_id])
	else:
		# Fallback to size-based rectangle for pieces without TileMaps
		cells = _get_occupied_cells(grid_pos, piece_data.size, rotation)
		print("LayoutData: Using size-based cells for %s (no TileMap found)" % piece_id)

	# Validate (enable debug logging for placement attempts)
	debug_validation = true
	var valid: bool = can_place_at(piece_id, grid_pos, rotation)
	debug_validation = false

	if not valid:
		push_warning("LayoutData: Cannot place %s at %s" % [piece_id, grid_pos])
		return false

	# Generate custom_data for special pieces
	var custom_data: Dictionary = {}

	# Generate persistent ID for chests
	if piece_id == "furniture_chest":
		var persistent_id: String = "chest_%d_%d" % [grid_pos.x, grid_pos.y]
		custom_data["persistent_id"] = persistent_id

		# Set persistent_id on the chest instance if it has the method
		if instance.has_method("set_persistent_id"):
			instance.set_persistent_id(persistent_id)

	# Create PlacedPiece with type and custom data
	var placed: PlacedPiece = PlacedPiece.new(
		piece_id, grid_pos, rotation, instance, cells,
		piece_data.building_type, custom_data
	)

	# Route to correct layer
	match piece_data.building_type:
		DataTypes.BuildingType.CONSTRUCTION:
			construction_pieces[grid_pos] = placed
			for cell: Vector2i in cells:
				construction_cells[cell] = grid_pos

		DataTypes.BuildingType.FURNITURE:
			furniture_pieces[grid_pos] = placed
			for cell: Vector2i in cells:
				furniture_cells[cell] = grid_pos

	piece_added.emit(grid_pos, piece_id)
	layout_changed.emit(grid_pos)

	print("LayoutData: Placed %s at %s (type: %d, rotation: %d) occupying %d cells" %
		  [piece_id, grid_pos, piece_data.building_type, rotation, cells.size()])
	return true

func remove_piece(grid_pos: Vector2i) -> bool:
	"""Remove piece at position - defaults to top layer (furniture first)"""
	# Check furniture layer first
	if grid_pos in furniture_cells:
		return remove_furniture_at(grid_pos)
	# Fall back to construction layer
	elif grid_pos in construction_cells:
		return remove_construction_at(grid_pos)
	return false


func remove_furniture_at(grid_pos: Vector2i) -> bool:
	"""Explicitly remove furniture at position"""
	var origin_pos: Vector2i = grid_pos
	if grid_pos in furniture_cells:
		origin_pos = furniture_cells[grid_pos]

	if origin_pos not in furniture_pieces:
		return false

	var placed: PlacedPiece = furniture_pieces[origin_pos]
	var piece_id: String = placed.piece_id

	# Free instance
	if placed.instance and is_instance_valid(placed.instance):
		placed.instance.queue_free()

	# Clear furniture layer cells
	for cell: Vector2i in placed.occupied_cells:
		furniture_cells.erase(cell)

	furniture_pieces.erase(origin_pos)

	piece_removed.emit(origin_pos, piece_id)
	layout_changed.emit(origin_pos)

	print("LayoutData: Removed furniture %s from %s" % [piece_id, origin_pos])
	return true


func remove_construction_at(grid_pos: Vector2i) -> bool:
	"""Explicitly remove construction at position"""
	var origin_pos: Vector2i = grid_pos
	if grid_pos in construction_cells:
		origin_pos = construction_cells[grid_pos]

	if origin_pos not in construction_pieces:
		return false

	var placed: PlacedPiece = construction_pieces[origin_pos]
	var piece_id: String = placed.piece_id

	# Check if furniture exists on top - prevent deletion
	var has_furniture_on_top: bool = false
	for cell: Vector2i in placed.occupied_cells:
		if is_furniture_at(cell):
			has_furniture_on_top = true
			break

	if has_furniture_on_top:
		push_warning("Cannot remove construction with furniture on top at %s" % origin_pos)
		return false

	# Free instance
	if placed.instance and is_instance_valid(placed.instance):
		placed.instance.queue_free()

	# Clear construction layer cells
	for cell: Vector2i in placed.occupied_cells:
		construction_cells.erase(cell)

	construction_pieces.erase(origin_pos)

	piece_removed.emit(origin_pos, piece_id)
	layout_changed.emit(origin_pos)

	print("LayoutData: Removed construction %s from %s" % [piece_id, origin_pos])
	return true

# =============================================
# QUERIES
# =============================================

func is_cell_occupied(grid_pos: Vector2i) -> bool:
	return is_construction_at(grid_pos) or is_furniture_at(grid_pos)


func get_piece_at(grid_pos: Vector2i) -> PlacedPiece:
	"""Get the piece at a grid position - returns furniture if present, otherwise construction"""
	# Check furniture layer first (top layer)
	var furniture: PlacedPiece = get_furniture_at(grid_pos)
	if furniture:
		return furniture
	# Fall back to construction layer
	return get_construction_at(grid_pos)


func is_construction_at(grid_pos: Vector2i) -> bool:
	return grid_pos in construction_cells


func is_furniture_at(grid_pos: Vector2i) -> bool:
	return grid_pos in furniture_cells


func get_construction_at(grid_pos: Vector2i) -> PlacedPiece:
	if grid_pos in construction_cells:
		var origin: Vector2i = construction_cells[grid_pos]
		return construction_pieces.get(origin)
	return null


func get_furniture_at(grid_pos: Vector2i) -> PlacedPiece:
	if grid_pos in furniture_cells:
		var origin: Vector2i = furniture_cells[grid_pos]
		return furniture_pieces.get(origin)
	return null

func get_openings_at(grid_pos: Vector2i) -> Array[Vector2i]:
	"""Get the openings/connections at a specific cell"""
	var placed: PlacedPiece = get_piece_at(grid_pos)
	if not placed:
		return []
	
	# Only single-cell pieces have openings at their position
	# Multi-cell pieces (rooms) use door_positions instead
	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(placed.piece_id)
	if not piece_data or piece_data.is_room:
		return []
	
	return BuildingPieceRegistry.get_rotated_openings(placed.piece_id, placed.rotation)

func has_opening_toward(grid_pos: Vector2i, direction: Vector2i) -> bool:
	"""Check if the piece at grid_pos has an opening in the given direction"""
	var openings: Array[Vector2i] = get_openings_at(grid_pos)
	return direction in openings

func get_adjacent_cells(grid_pos: Vector2i) -> Dictionary:
	"""Get adjacent cells and what's in them"""
	var result: Dictionary = {}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	for dir: Vector2i in directions:
		var adjacent_pos: Vector2i = grid_pos + dir
		result[dir] = get_piece_at(adjacent_pos)
	
	return result

# =============================================
# COORDINATE CONVERSION
# =============================================

func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""Convert world position to grid coordinates"""
	return Vector2i(
		floori(world_pos.x / cell_size),
		floori(world_pos.y / cell_size)
	)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""Convert grid coordinates to world position (center of cell)"""
	return Vector2(
		grid_pos.x * cell_size + cell_size / 2.0,
		grid_pos.y * cell_size + cell_size / 2.0
	)


func grid_to_world_corner(grid_pos: Vector2i) -> Vector2:
	"""Convert grid coordinates to world position (top-left corner of cell)
	Use this for TileMap-based pieces to avoid half-cell offsets"""
	return Vector2(
		grid_pos.x * cell_size,
		grid_pos.y * cell_size
	)


func snap_to_grid(world_pos: Vector2) -> Vector2:
	"""Snap a world position to the nearest grid cell center"""
	var grid_pos: Vector2i = world_to_grid(world_pos)
	return grid_to_world(grid_pos)

# =============================================
# VALIDATION
# =============================================

func can_place_at(piece_id: String, grid_pos: Vector2i, rotation: int) -> bool:
	"""Check if a piece can be placed at the given position"""
	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(piece_id)
	if not piece_data:
		return false

	# Calculate which cells this piece would occupy
	var cells: Array[Vector2i] = []

	# Try to get actual cells from TileMap by temporarily instantiating
	var scene: PackedScene = load(piece_data.scene_path)
	if scene:
		var temp_instance: Node2D = scene.instantiate()
		var local_cells: Array[Vector2i] = _get_tilemap_cells_from_instance(temp_instance)

		if local_cells.size() > 0:
			# Use actual TileMap cells with rotation applied
			cells = _transform_cells_for_placement(local_cells, grid_pos, rotation)
		else:
			# Fallback to size-based rectangle
			cells = _get_occupied_cells(grid_pos, piece_data.size, rotation)

		# Clean up temporary instance
		temp_instance.queue_free()
	else:
		# If scene fails to load, use fallback
		cells = _get_occupied_cells(grid_pos, piece_data.size, rotation)

	# Type-specific validation
	match piece_data.building_type:
		DataTypes.BuildingType.CONSTRUCTION:
			# Rule 1: Constructions cannot overlap with other constructions
			for cell: Vector2i in cells:
				if is_construction_at(cell):
					return false

			# Rule 2: Must align navigation polygons with adjacent constructions
			if not _validate_nav_alignment(piece_id, grid_pos, rotation, cells):
				return false

			return true

		DataTypes.BuildingType.FURNITURE:
			# Furniture requires construction underneath AND no other furniture
			for cell: Vector2i in cells:
				if not is_construction_at(cell):
					return false  # Must have construction base
				if is_furniture_at(cell):
					return false  # Cannot stack furniture
			return true

	return false  # Unknown type


func _validate_nav_alignment(piece_id: String, grid_pos: Vector2i, rotation: int, cells: Array[Vector2i]) -> bool:
	"""Validate that navigation polygons align with adjacent constructions or connectable tiles

	Returns true if:
	- The piece connects to at least one adjacent construction or connectable tile
	- All connections have matching nav tile alignment on shared edges

	Returns false if:
	- No adjacent constructions or connectable tiles (isolated placement not allowed)
	- At least one connection has mismatched nav tiles on shared edge
	"""
	if debug_validation:
		print("\n=== NAV VALIDATION START ===")
		print("Piece: %s, GridPos: %s, Rotation: %s, Cells: %s" % [piece_id, grid_pos, rotation, cells])

	# Get nav tiles for the piece being placed (rotated)
	var nav_tiles: Array[Vector2i] = _get_rotated_nav_tiles(piece_id, grid_pos, rotation)

	if debug_validation:
		print("Nav tiles for piece: %s" % [nav_tiles])

	if nav_tiles.is_empty():
		if debug_validation:
			print("❌ FAIL: Piece has no nav tiles")
		return false

	# Find all adjacent constructions
	var adjacent_constructions: Dictionary = _find_adjacent_constructions(cells)

	if debug_validation:
		print("Adjacent constructions: %s" % [adjacent_constructions.keys()])

	# Find all adjacent connectable tiles
	var adjacent_connectable_tiles: Dictionary = _find_adjacent_connectable_tiles(cells)

	if debug_validation:
		print("Adjacent connectable tiles: %s" % [adjacent_connectable_tiles.keys()])

	# Must have at least one connection (construction or connectable tile)
	if adjacent_constructions.is_empty() and adjacent_connectable_tiles.is_empty():
		if debug_validation:
			print("❌ FAIL: No adjacent constructions or connectable tiles")
		return false

	# Check each adjacent construction for nav alignment
	for direction: Vector2i in adjacent_constructions.keys():
		var adjacent_placed: PlacedPiece = adjacent_constructions[direction]
		if not _check_edge_alignment(nav_tiles, adjacent_placed, direction, cells):
			if debug_validation:
				print("❌ FAIL: Misalignment with construction in direction %s" % [direction])
			return false

	# Check each adjacent connectable tile for nav alignment
	for direction: Vector2i in adjacent_connectable_tiles.keys():
		var connectable_positions: Array = adjacent_connectable_tiles[direction]
		if not _check_connectable_tiles_alignment(nav_tiles, connectable_positions, direction, cells):
			if debug_validation:
				print("❌ FAIL: Misalignment with connectable tiles in direction %s" % [direction])
			return false

	if debug_validation:
		print("✅ SUCCESS: All edges align correctly")
	return true  # All edges align correctly


func would_connect(piece_id: String, grid_pos: Vector2i, rotation: int) -> bool:
	"""Check if placing this piece would connect to at least one existing piece"""
	
	var openings: Array[Vector2i] = BuildingPieceRegistry.get_rotated_openings(piece_id, rotation)
	
	for opening_dir: Vector2i in openings:
		var adjacent_pos: Vector2i = grid_pos + opening_dir
		var opposite_dir: Vector2i = -opening_dir
		
		if has_opening_toward(adjacent_pos, opposite_dir):
			return true  # Found a matching connection
	
	return false


# =============================================
# HELPERS
# =============================================

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


func _transform_cells_for_placement(local_cells: Array[Vector2i], origin: Vector2i, rotation: int) -> Array[Vector2i]:
	"""Transform local tilemap cells to global grid coordinates with rotation applied"""
	var transformed: Array[Vector2i] = []

	for cell: Vector2i in local_cells:
		var rotated_cell: Vector2i = cell

		# Apply rotation transformation
		match rotation:
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


func _get_occupied_cells(origin: Vector2i, size: Vector2i, rotation: int) -> Array[Vector2i]:
	"""Calculate all cells a piece would occupy given its size and rotation"""
	var cells: Array[Vector2i] = []
	
	# Adjust size for rotation (swap width/height on 90/270 degree rotations)
	var effective_size: Vector2i = size
	if rotation == 1 or rotation == 3:
		effective_size = Vector2i(size.y, size.x)
	
	for x: int in effective_size.x:
		for y: int in effective_size.y:
			cells.append(origin + Vector2i(x, y))
	
	return cells


# =============================================
# NAV ALIGNMENT VALIDATION HELPERS
# =============================================

func _get_rotated_nav_tiles(piece_id: String, origin: Vector2i, rotation: int) -> Array[Vector2i]:
	"""Get navigation tile coordinates after rotation and translation to global grid"""
	var local_nav_tiles: Array[Vector2i] = BuildingPieceRegistry.get_nav_tile_coords(piece_id)
	if local_nav_tiles.is_empty():
		return []

	var global_nav_tiles: Array[Vector2i] = []
	for local_cell: Vector2i in local_nav_tiles:
		var rotated_cell: Vector2i = _rotate_cell(local_cell, rotation)
		global_nav_tiles.append(origin + rotated_cell)

	return global_nav_tiles


func _rotate_cell(cell: Vector2i, rotation: int) -> Vector2i:
	"""Rotate a cell coordinate by rotation * 90 degrees clockwise"""
	var result: Vector2i = cell
	match rotation:
		0:  # 0 degrees
			result = cell
		1:  # 90 degrees clockwise
			result = Vector2i(-cell.y, cell.x)
		2:  # 180 degrees
			result = Vector2i(-cell.x, -cell.y)
		3:  # 270 degrees clockwise (90 CCW)
			result = Vector2i(cell.y, -cell.x)
	return result


func _find_adjacent_constructions(cells: Array[Vector2i]) -> Dictionary:
	"""Find all adjacent constructions and which direction they're in

	Returns: Dictionary[Vector2i (direction) -> PlacedPiece]
	Only returns one PlacedPiece per direction (the first found)
	"""
	var adjacent: Dictionary = {}  # direction -> PlacedPiece
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for cell: Vector2i in cells:
		for dir: Vector2i in directions:
			var adjacent_cell: Vector2i = cell + dir

			# Skip if this cell is part of the piece being placed
			if adjacent_cell in cells:
				continue

			# Check if there's a construction here
			if is_construction_at(adjacent_cell):
				var placed: PlacedPiece = get_construction_at(adjacent_cell)

				# Store one representative per direction
				if dir not in adjacent:
					adjacent[dir] = placed

	return adjacent


func _check_edge_alignment(
	new_piece_nav_tiles: Array[Vector2i],
	adjacent_placed: PlacedPiece,
	direction: Vector2i,
	new_piece_cells: Array[Vector2i]
) -> bool:
	"""Check if navigation tiles align on the shared edge between new and adjacent piece

	Algorithm:
	1. Find edge cells for both pieces on the shared boundary
	2. Filter to only nav tiles on each edge
	3. Project nav tiles onto 1D axis perpendicular to edge
	4. Compare projections - must match exactly (same positions)
	"""
	# Get nav tiles for adjacent piece
	var adjacent_nav_tiles: Array[Vector2i] = _get_rotated_nav_tiles(
		adjacent_placed.piece_id,
		adjacent_placed.grid_pos,
		adjacent_placed.rotation
	)

	if adjacent_nav_tiles.is_empty():
		# Adjacent piece has no nav tiles - no alignment required
		return true

	# Find edge cells for new piece on this direction
	var new_edge_cells: Array[Vector2i] = _get_edge_cells(new_piece_cells, direction)
	var new_edge_nav_tiles: Array[Vector2i] = _filter_nav_tiles(new_edge_cells, new_piece_nav_tiles)

	# Find edge cells for adjacent piece on opposite direction
	var opposite_dir: Vector2i = -direction
	var adjacent_edge_cells: Array[Vector2i] = _get_edge_cells(adjacent_placed.occupied_cells, opposite_dir)
	var adjacent_edge_nav_tiles: Array[Vector2i] = _filter_nav_tiles(adjacent_edge_cells, adjacent_nav_tiles)

	# Project nav tiles onto 1D axis and compare
	return _compare_edge_projections(
		new_edge_nav_tiles,
		adjacent_edge_nav_tiles,
		direction
	)


func _get_edge_cells(cells: Array[Vector2i], direction: Vector2i) -> Array[Vector2i]:
	"""Get all cells on the edge of a piece in the specified direction

	Edge = cells that have no neighbor in that direction within the same piece
	"""
	var edge_cells: Array[Vector2i] = []

	for cell: Vector2i in cells:
		var neighbor: Vector2i = cell + direction
		if neighbor not in cells:
			# This cell is on the edge
			edge_cells.append(cell)

	return edge_cells


func _filter_nav_tiles(cells: Array[Vector2i], nav_tiles: Array[Vector2i]) -> Array[Vector2i]:
	"""Filter nav tiles to only those in the given cell list"""
	var filtered: Array[Vector2i] = []

	for tile: Vector2i in nav_tiles:
		if tile in cells:
			filtered.append(tile)

	return filtered


func _compare_edge_projections(
	edge1_nav_tiles: Array[Vector2i],
	edge2_nav_tiles: Array[Vector2i],
	direction: Vector2i
) -> bool:
	"""Compare two edges by projecting nav tiles onto perpendicular axis

	For horizontal edges (UP/DOWN): project onto X axis
	For vertical edges (LEFT/RIGHT): project onto Y axis

	Returns true if projections match exactly (same set of positions)
	"""
	# Determine projection axis based on direction
	var is_horizontal: bool = (direction == Vector2i.UP or direction == Vector2i.DOWN)

	# Project edge1 nav tiles
	var proj1: Array[int] = []
	for tile: Vector2i in edge1_nav_tiles:
		var position: int = tile.x if is_horizontal else tile.y
		if position not in proj1:
			proj1.append(position)
	proj1.sort()

	# Project edge2 nav tiles
	var proj2: Array[int] = []
	for tile: Vector2i in edge2_nav_tiles:
		var position: int = tile.x if is_horizontal else tile.y
		if position not in proj2:
			proj2.append(position)
	proj2.sort()

	# Compare sorted projections
	if proj1.size() != proj2.size():
		return false

	for i in range(proj1.size()):
		if proj1[i] != proj2[i]:
			return false

	return true


func _find_adjacent_connectable_tiles(cells: Array[Vector2i]) -> Dictionary:
	"""Find all adjacent tiles from TileMapLayers in 'construction_connectable' group

	Returns: Dictionary[Vector2i (direction) -> Array[grid_positions]]
	All connectable tile positions adjacent to the piece, grouped by direction
	"""
	var adjacent_tiles: Dictionary = {}  # direction -> Array of grid positions with connectable tiles
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	# Initialize arrays for each direction
	for dir in directions:
		adjacent_tiles[dir] = []

	# Get all TileMapLayers in the construction_connectable group
	if not get_tree():
		if debug_validation:
			print("DEBUG: get_tree() returned null!")
		return adjacent_tiles

	var connectable_layers: Array[Node] = get_tree().get_nodes_in_group("construction_connectable")

	if debug_validation:
		print("DEBUG: Found %d nodes in 'construction_connectable' group" % connectable_layers.size())

	# Debug: Print tilemap info
	if debug_validation:
		for node in connectable_layers:
			if node is TileMapLayer:
				var tilemap: TileMapLayer = node as TileMapLayer
				print("DEBUG: Found connectable tilemap: %s, tile_set=%s, transform=%s" %
					[tilemap.name, tilemap.tile_set, tilemap.global_transform])
				if tilemap.tile_set:
					print("  Tile size: %s" % [tilemap.tile_set.tile_size])

	# Collect all adjacent connectable tiles
	var checked_positions: Dictionary = {}  # Track which positions we've already checked

	for cell: Vector2i in cells:
		for dir: Vector2i in directions:
			var adjacent_cell: Vector2i = cell + dir

			# Skip if this cell is part of the piece being placed
			if adjacent_cell in cells:
				continue

			# Skip if we already checked this position
			var position_key: String = "%s_%s" % [adjacent_cell, dir]
			if position_key in checked_positions:
				continue
			checked_positions[position_key] = true

			# Check each connectable layer for a tile at this position
			for node in connectable_layers:
				if not node is TileMapLayer:
					continue

				var tilemap: TileMapLayer = node as TileMapLayer

				# Convert building grid position to world position (center of cell for consistency)
				var world_pos: Vector2 = grid_to_world(adjacent_cell)

				# Convert to tilemap local coordinates
				var tilemap_local: Vector2 = tilemap.to_local(world_pos)
				var tile_coords: Vector2i = tilemap.local_to_map(tilemap_local)

				# Check if this tilemap has a tile at this position
				var tile_data: TileData = tilemap.get_cell_tile_data(tile_coords)
				if tile_data and tile_data.get_navigation_polygon(0):
					if debug_validation:
						print("DEBUG: ✓ Found connectable tile! Direction=%s, GridPos=%s, TileCoords=%s" %
							[dir, adjacent_cell, tile_coords])

					# Add this position to the array for this direction
					adjacent_tiles[dir].append(adjacent_cell)
					break  # Found tile at this position, move to next

	# Remove empty directions
	var non_empty_tiles: Dictionary = {}
	for dir in directions:
		if adjacent_tiles[dir].size() > 0:
			non_empty_tiles[dir] = adjacent_tiles[dir]

	return non_empty_tiles


func _check_connectable_tiles_alignment(
	new_piece_nav_tiles: Array[Vector2i],
	connectable_positions: Array,
	direction: Vector2i,
	new_piece_cells: Array[Vector2i]
) -> bool:
	"""Check if navigation tiles align between new piece and connectable tiles

	connectable_positions: Array of grid positions where connectable tiles with nav polygons exist
	"""
	if connectable_positions.is_empty():
		return true

	# Find edge cells for new piece on this direction
	var new_edge_cells: Array[Vector2i] = _get_edge_cells(new_piece_cells, direction)
	var new_edge_nav_tiles: Array[Vector2i] = _filter_nav_tiles(new_edge_cells, new_piece_nav_tiles)

	# All connectable positions are assumed to have nav polygons (we filtered for that)
	var connectable_edge_nav_tiles: Array[Vector2i] = []
	for pos: Vector2i in connectable_positions:
		connectable_edge_nav_tiles.append(pos)

	if debug_validation:
		print("  Edge comparison for direction %s:" % [direction])
		print("    Hallway edge cells (all): %s" % [new_edge_cells])
		print("    Hallway edge nav tiles: %s" % [new_edge_nav_tiles])
		print("    Connectable edge nav tiles: %s" % [connectable_edge_nav_tiles])

	# Project and compare
	var result: bool = _compare_edge_projections(
		new_edge_nav_tiles,
		connectable_edge_nav_tiles,
		direction
	)

	if debug_validation:
		print("    Projection comparison result: %s" % result)

	return result


func get_all_placed_pieces() -> Array:
	"""Get all placed pieces (combined from both layers)"""
	var all_pieces: Array = []
	all_pieces.append_array(construction_pieces.values())
	all_pieces.append_array(furniture_pieces.values())
	return all_pieces

func clear_all() -> void:
	"""Remove all placed pieces"""
	# Clear furniture first (top layer)
	for origin_pos: Vector2i in furniture_pieces.keys().duplicate():
		remove_furniture_at(origin_pos)
	# Then clear constructions
	for origin_pos: Vector2i in construction_pieces.keys().duplicate():
		remove_construction_at(origin_pos)

# =============================================
# SAVE/LOAD
# =============================================

const SAVE_PATH: String = "user://building_layout_data.json"

func save_layout_data() -> void:
	"""Save layout data to file"""
	var data: Dictionary = get_save_data()
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("BuildingLayoutData: Saved layout data to %s" % SAVE_PATH)
	else:
		push_error("BuildingLayoutData: Failed to save layout data")


func load_layout_data() -> void:
	"""Load layout data from file"""
	if not FileAccess.file_exists(SAVE_PATH):
		print("BuildingLayoutData: No save file found at %s" % SAVE_PATH)
		return

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string: String = file.get_as_text()
		file.close()

		var json: JSON = JSON.new()
		var parse_result: Error = json.parse(json_string)

		if parse_result == OK:
			var data: Dictionary = json.data
			load_save_data(data)

			print("BuildingLayoutData: After load_save_data - construction_cells: %d, construction_pieces: %d" % [construction_cells.size(), construction_pieces.size()])
		else:
			push_error("BuildingLayoutData: Failed to parse save data: %s" % json.get_error_message())
	else:
		push_error("BuildingLayoutData: Failed to load layout data")


func get_save_data() -> Dictionary:
	"""Get layout data for saving"""
	var data: Dictionary = {
		"construction_pieces": [],
		"furniture_pieces": []
	}

	# Save construction pieces
	for placed: PlacedPiece in construction_pieces.values():
		var piece_dict: Dictionary = {
			"piece_id": placed.piece_id,
			"grid_pos": {"x": placed.grid_pos.x, "y": placed.grid_pos.y},
			"rotation": placed.rotation,
			"occupied_cells": _serialize_vector2i_array(placed.occupied_cells),
			"building_type": placed.building_type,
			"custom_data": placed.custom_data
		}
		data["construction_pieces"].append(piece_dict)

	# Save furniture pieces
	for placed: PlacedPiece in furniture_pieces.values():
		var piece_dict: Dictionary = {
			"piece_id": placed.piece_id,
			"grid_pos": {"x": placed.grid_pos.x, "y": placed.grid_pos.y},
			"rotation": placed.rotation,
			"occupied_cells": _serialize_vector2i_array(placed.occupied_cells),
			"building_type": placed.building_type,
			"custom_data": placed.custom_data
		}
		data["furniture_pieces"].append(piece_dict)

	return data


func _serialize_vector2i_array(arr: Array[Vector2i]) -> Array:
	"""Convert Array[Vector2i] to serializable format"""
	var result: Array = []
	for v: Vector2i in arr:
		result.append({"x": v.x, "y": v.y})
	return result


func _deserialize_vector2i_array(arr: Array) -> Array[Vector2i]:
	"""Convert serialized array back to Array[Vector2i]"""
	var result: Array[Vector2i] = []
	for dict: Dictionary in arr:
		result.append(Vector2i(dict["x"], dict["y"]))
	return result


func load_save_data(data: Dictionary) -> void:
	"""Load layout data from save (just restores the dictionaries)
	Your custom save system should handle loading the actual scene instances"""
	# Clear all layers
	construction_pieces.clear()
	furniture_pieces.clear()
	construction_cells.clear()
	furniture_cells.clear()
	pending_custom_data.clear()

	# Load construction pieces
	if data.has("construction_pieces"):
		for piece_dict: Dictionary in data["construction_pieces"]:
			var grid_pos: Vector2i = Vector2i(piece_dict["grid_pos"]["x"], piece_dict["grid_pos"]["y"])
			var cells: Array[Vector2i] = _deserialize_vector2i_array(piece_dict["occupied_cells"])
			var rotation: int = piece_dict.get("rotation", 0)
			var piece_id: String = piece_dict.get("piece_id", "")
			var building_type: int = piece_dict.get("building_type", DataTypes.BuildingType.CONSTRUCTION)
			var custom_data_dict: Dictionary = piece_dict.get("custom_data", {})

			# Create PlacedPiece with null instance (instance will be set when scene loads)
			var placed: PlacedPiece = PlacedPiece.new(
				piece_id,
				grid_pos,
				rotation,
				null,  # Instance not loaded yet
				cells,
				building_type,
				custom_data_dict
			)
			construction_pieces[grid_pos] = placed

			for cell: Vector2i in cells:
				construction_cells[cell] = grid_pos

			# Store custom_data for later application
			if not custom_data_dict.is_empty():
				pending_custom_data[grid_pos] = custom_data_dict

	# Load furniture pieces
	if data.has("furniture_pieces"):
		for piece_dict: Dictionary in data["furniture_pieces"]:
			var grid_pos: Vector2i = Vector2i(piece_dict["grid_pos"]["x"], piece_dict["grid_pos"]["y"])
			var cells: Array[Vector2i] = _deserialize_vector2i_array(piece_dict["occupied_cells"])
			var rotation: int = piece_dict.get("rotation", 0)
			var piece_id: String = piece_dict.get("piece_id", "")
			var building_type: int = piece_dict.get("building_type", DataTypes.BuildingType.FURNITURE)
			var custom_data_dict: Dictionary = piece_dict.get("custom_data", {})

			# Create PlacedPiece with null instance (instance will be set when scene loads)
			var placed: PlacedPiece = PlacedPiece.new(
				piece_id,
				grid_pos,
				rotation,
				null,  # Instance not loaded yet
				cells,
				building_type,
				custom_data_dict
			)
			furniture_pieces[grid_pos] = placed

			for cell: Vector2i in cells:
				furniture_cells[cell] = grid_pos

			# Store custom_data for later application
			if not custom_data_dict.is_empty():
				pending_custom_data[grid_pos] = custom_data_dict

	print("LayoutData: Loaded %d construction pieces, %d furniture pieces, %d construction cells, %d furniture cells" %
		  [construction_pieces.size(), furniture_pieces.size(), construction_cells.size(), furniture_cells.size()])


func get_and_clear_pending_custom_data(world_pos: Vector2) -> Dictionary:
	"""Get custom_data for a piece at world position (used during load).
	Clears the data after retrieval so it's only used once."""
	var grid_pos: Vector2i = world_to_grid(world_pos)
	if grid_pos in pending_custom_data:
		var data: Dictionary = pending_custom_data[grid_pos]
		pending_custom_data.erase(grid_pos)
		return data
	return {}


func get_rotation_for_load(world_pos: Vector2) -> int:
	"""Get the rotation for a piece at world position during load.
	Returns the rotation value (0-3) or 0 if not found.
	This is used by SceneDataResource during load to restore rotation."""
	var grid_pos: Vector2i = world_to_grid(world_pos)

	# Check furniture layer first (top layer)
	if grid_pos in furniture_cells:
		var origin_pos: Vector2i = furniture_cells[grid_pos]
		if origin_pos in furniture_pieces:
			var placed: PlacedPiece = furniture_pieces[origin_pos]
			return placed.rotation

	# Check construction layer
	if grid_pos in construction_cells:
		var origin_pos: Vector2i = construction_cells[grid_pos]
		if origin_pos in construction_pieces:
			var placed: PlacedPiece = construction_pieces[origin_pos]
			return placed.rotation

	# Not found - return default rotation
	return 0
