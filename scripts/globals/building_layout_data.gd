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

# Spatial index for world connectable tiles (performance optimization)
var world_connectable_tiles_index: Dictionary = {}  # grid_pos -> true
var world_connectable_index_dirty: bool = true  # Rebuild index when dirty

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

	# Mark spatial index as dirty
	if piece_data.building_type == DataTypes.BuildingType.CONSTRUCTION:
		world_connectable_index_dirty = true

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

	# Check if rooms are attached to this hallway - prevent deletion
	var hallway_id: String = piece_id + "_" + str(origin_pos.x) + "_" + str(origin_pos.y)
	if RoomManager.has_attached_rooms(hallway_id):
		push_warning("Cannot remove hallway with attached rooms at %s" % origin_pos)
		return false

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

	# Mark spatial index as dirty
	world_connectable_index_dirty = true

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

			# Room-specific validation
			if piece_data.is_room:
				return _validate_room_placement(piece_id, grid_pos, rotation)

			# Rule 2: Must have valid connection group matches with adjacent pieces
			if not _validate_connection_groups(piece_id, grid_pos, rotation, cells):
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


func _validate_connection_groups(piece_id: String, grid_pos: Vector2i, rotation: int, cells: Array[Vector2i]) -> bool:
	"""Validate that connectable TileMapLayers match with adjacent connectable tiles

	Note: Constructions are always at rotation=0 (rotation parameter ignored for constructions)

	Simple validation:
	1. Find all TileMapLayers in "connectable_tiles" group in the piece
	2. For each layer, check if its tiles are adjacent to other "connectable_tiles" in the world
	3. Count must match exactly (4 tiles must touch 4 tiles)
	4. At least one layer must find a match

	Returns true if at least one connectable layer finds exact count match
	Returns false if no connections or count mismatch
	"""
	if debug_validation:
		print("\n=== CONNECTABLE TILES VALIDATION START ===")
		print("Piece: %s, GridPos: %s" % [piece_id, grid_pos])

	# Get cached connectable layer data (avoids repeated scene loading)
	var layer_data: Array = BuildingPieceRegistry.get_cached_connectable_layers(piece_id)

	if layer_data.is_empty():
		if debug_validation:
			print("❌ FAIL: Piece has no TileMapLayers in 'connectable_tiles' group")
		return false

	if debug_validation:
		print("Found %d connectable layers in piece (cached)" % layer_data.size())

	# Track if at least one layer finds a match
	var at_least_one_match: bool = false

	# Check each connectable layer
	for layer_info: Dictionary in layer_data:
		var layer_offset_cells: Vector2i = layer_info["offset"]
		var local_tiles: Array[Vector2i] = layer_info["tiles"]

		# Transform tiles to global grid (layer offset + translation)
		# Note: No rotation needed since constructions are always at rotation=0
		var global_tiles: Array[Vector2i] = []
		for local_tile: Vector2i in local_tiles:
			# Add layer offset to get position relative to piece origin
			var piece_relative_tile: Vector2i = local_tile + layer_offset_cells
			# Translate to global grid position (no rotation for constructions)
			global_tiles.append(grid_pos + piece_relative_tile)

		if debug_validation:
			print("  Layer with %d tiles (global positions): %s" % [global_tiles.size(), global_tiles])

		# Find adjacent connectable tiles in the world
		var adjacent_tiles: Array[Vector2i] = _find_adjacent_connectable_tiles_simple(global_tiles)

		if debug_validation:
			print("    Found %d adjacent connectable tiles" % adjacent_tiles.size())

		# Check if count matches
		if adjacent_tiles.size() == global_tiles.size() and adjacent_tiles.size() > 0:
			at_least_one_match = true
			if debug_validation:
				print("    ✓ Match! %d tiles connect to %d tiles" % [global_tiles.size(), adjacent_tiles.size()])
		elif adjacent_tiles.size() > 0:
			# Touching but count mismatch - invalid
			if debug_validation:
				print("    ❌ Count mismatch: %d tiles trying to connect to %d tiles" % [global_tiles.size(), adjacent_tiles.size()])
			return false

	if not at_least_one_match:
		if debug_validation:
			print("❌ FAIL: No connectable layers found matches")
		return false

	if debug_validation:
		print("✅ SUCCESS: At least one layer matched")
	return true


func _validate_room_placement(piece_id: String, grid_pos: Vector2i, rotation: int) -> bool:
	"""Room door must be placed ON TOP of a hallway wall tile"""
	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(piece_id)
	if not piece_data:
		if debug_validation:
			print("❌ FAIL: Room piece not found")
		return false

	# Get door position from scene's door_edge layer
	var door_offset: Vector2i = _get_room_door_offset(piece_data.scene_path)
	var door_grid: Vector2i = grid_pos + door_offset

	if debug_validation:
		print("\n=== ROOM PLACEMENT VALIDATION ===")
		print("Room: %s, GridPos: %s, DoorOffset: %s, DoorGrid: %s" % [piece_id, grid_pos, door_offset, door_grid])

	# Check all 4 directions from door
	for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var adjacent: Vector2i = door_grid + dir

		# Must be construction (hallway)
		if not is_construction_at(adjacent):
			continue

		var hallway: PlacedPiece = get_construction_at(adjacent)
		if not hallway or not hallway.instance:
			continue

		# Door attaches to hallway WALL, not opening
		if has_opening_toward(adjacent, -dir):
			if debug_validation:
				print("  Direction %s: hallway has opening toward door (invalid)" % dir)
			continue

		# CRITICAL: Verify there's actually a wall tile at the door position
		var walls_layer: TileMapLayer = hallway.instance.get_node_or_null("GameTileMap/Walls")
		if not walls_layer:
			if debug_validation:
				print("  Direction %s: no Walls layer found" % dir)
			continue

		# Convert door grid position to hallway's Walls layer local coords
		var door_world: Vector2 = grid_to_world(door_grid)
		var local_pos: Vector2 = walls_layer.to_local(door_world)
		var wall_cell: Vector2i = walls_layer.local_to_map(local_pos)

		# Check if there's a tile at this position
		var tile_source: int = walls_layer.get_cell_source_id(wall_cell)
		if tile_source != -1:  # -1 means no tile
			if debug_validation:
				print("✅ SUCCESS: Found wall tile at %s (source: %d)" % [wall_cell, tile_source])
			return true
		else:
			if debug_validation:
				print("  Direction %s: no wall tile at cell %s" % [dir, wall_cell])

	if debug_validation:
		print("❌ FAIL: Room door must be placed on a hallway wall tile")
	return false


func _get_room_door_offset(scene_path: String) -> Vector2i:
	"""Get door position offset from room scene's door_edge layer"""
	var scene: PackedScene = load(scene_path)
	if not scene:
		return Vector2i.ZERO

	var temp_instance: Node2D = scene.instantiate()
	var door_edge: TileMapLayer = temp_instance.get_node_or_null("GameTileMap/door_edge")

	var offset: Vector2i = Vector2i.ZERO
	if door_edge:
		var cells: Array[Vector2i] = door_edge.get_used_cells()
		if cells.size() > 0:
			offset = cells[0]

	temp_instance.queue_free()
	return offset


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
# CONNECTABLE TILES VALIDATION HELPERS
# =============================================

func _rebuild_world_connectable_index() -> void:
	"""Rebuild the spatial index of world connectable tiles

	This is called lazily when the index is dirty (after placing/removing pieces)
	"""
	world_connectable_tiles_index.clear()

	# Index world TileMapLayers in "connectable_tiles" group
	if get_tree():
		var world_layers: Array[Node] = get_tree().get_nodes_in_group("connectable_tiles")
		for node in world_layers:
			if not node is TileMapLayer:
				continue

			var tilemap: TileMapLayer = node as TileMapLayer
			var used_cells: Array[Vector2i] = tilemap.get_used_cells()

			for cell_coords: Vector2i in used_cells:
				# Convert tilemap coordinates to global grid
				var cell_world_pos: Vector2 = tilemap.map_to_local(cell_coords)
				var cell_global_pos: Vector2 = tilemap.to_global(cell_world_pos)
				var grid_pos: Vector2i = world_to_grid(cell_global_pos)

				world_connectable_tiles_index[grid_pos] = true

	# Index placed construction pieces' connectable layers
	for placed: PlacedPiece in construction_pieces.values():
		if not placed.instance or not is_instance_valid(placed.instance):
			continue

		var piece_layers: Array = _find_connectable_layers_recursive(placed.instance)
		for layer: TileMapLayer in piece_layers:
			var used_cells: Array[Vector2i] = layer.get_used_cells()

			for cell_coords: Vector2i in used_cells:
				# Convert to global grid coordinates
				var cell_world_pos: Vector2 = layer.map_to_local(cell_coords)
				var cell_global_pos: Vector2 = layer.to_global(cell_world_pos)
				var grid_pos: Vector2i = world_to_grid(cell_global_pos)

				world_connectable_tiles_index[grid_pos] = true

	world_connectable_index_dirty = false


func _find_connectable_layers_recursive(node: Node) -> Array:
	"""Recursively find all TileMapLayers that are in the 'connectable_tiles' group"""
	var layers: Array = []

	if node is TileMapLayer:
		var tilemap: TileMapLayer = node as TileMapLayer
		if tilemap.is_in_group("connectable_tiles"):
			layers.append(tilemap)

	for child in node.get_children():
		layers.append_array(_find_connectable_layers_recursive(child))

	return layers


func _find_adjacent_connectable_tiles_simple(tiles: Array[Vector2i]) -> Array[Vector2i]:
	"""Find connectable tiles adjacent to the given tiles (optimized with spatial index)

	Returns array of positions where connectable tiles exist adjacent to the input tiles
	"""
	# Rebuild spatial index if dirty (after placing/removing pieces)
	if world_connectable_index_dirty:
		_rebuild_world_connectable_index()

	var adjacent_connectable: Array[Vector2i] = []
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var checked: Dictionary = {}  # Avoid duplicates

	# For each tile in our list, check all 4 directions using the spatial index
	for tile: Vector2i in tiles:
		for dir: Vector2i in directions:
			var adjacent_pos: Vector2i = tile + dir

			# Skip if we already checked this position
			var pos_key: String = "%d_%d" % [adjacent_pos.x, adjacent_pos.y]
			if pos_key in checked:
				continue
			checked[pos_key] = true

			# Skip if this position is in our own tiles list
			if adjacent_pos in tiles:
				continue

			# Fast O(1) lookup in spatial index
			if adjacent_pos in world_connectable_tiles_index:
				adjacent_connectable.append(adjacent_pos)

	return adjacent_connectable






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
