# LayoutData.gd
# Tracks all placed building pieces and provides spatial queries
extends Node

signal layout_changed(grid_pos: Vector2i)
signal piece_added(grid_pos: Vector2i, piece_id: String)
signal piece_removed(grid_pos: Vector2i, piece_id: String)

# Grid cell size in pixels (adjust to match your tile size)
@export var cell_size: int = 16

# Placed pieces: grid_pos -> PlacedPiece data
var placed_pieces: Dictionary = {}

# Spatial lookup: which cells are occupied and by what
var occupied_cells: Dictionary = {}  # grid_pos -> origin_grid_pos (for multi-cell pieces)

class PlacedPiece:
	var piece_id: String
	var grid_pos: Vector2i  # Origin position
	var rotation: int  # 0-3
	var instance: Node2D  # Scene instance
	var occupied_cells: Array[Vector2i]  # All cells this piece occupies
	
	func _init(p_id: String, p_pos: Vector2i, p_rot: int, p_instance: Node2D, p_cells: Array[Vector2i]) -> void:
		piece_id = p_id
		grid_pos = p_pos
		rotation = p_rot
		instance = p_instance
		occupied_cells = p_cells

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
	var cells: Array[Vector2i] = _get_occupied_cells(grid_pos, piece_data.size, rotation)
	
	# Check if any cells are already occupied
	for cell: Vector2i in cells:
		if is_cell_occupied(cell):
			push_warning("LayoutData: Cell %s is already occupied" % cell)
			return false
	
	# Place the piece
	var placed: PlacedPiece = PlacedPiece.new(piece_id, grid_pos, rotation, instance, cells)
	placed_pieces[grid_pos] = placed
	
	# Mark all cells as occupied
	for cell: Vector2i in cells:
		occupied_cells[cell] = grid_pos  # Points back to origin
	
	piece_added.emit(grid_pos, piece_id)
	layout_changed.emit(grid_pos)
	
	print("LayoutData: Placed %s at %s (rotation: %d)" % [piece_id, grid_pos, rotation])
	return true

func remove_piece(grid_pos: Vector2i) -> bool:
	"""Remove a piece at the given grid position (or the piece that occupies that cell)"""
	# If this cell is occupied but not an origin, find the origin
	var origin_pos: Vector2i = grid_pos
	if grid_pos in occupied_cells:
		origin_pos = occupied_cells[grid_pos]
	
	if origin_pos not in placed_pieces:
		return false
	
	var placed: PlacedPiece = placed_pieces[origin_pos]
	var piece_id: String = placed.piece_id
	
	# Free the instance
	if placed.instance and is_instance_valid(placed.instance):
		placed.instance.queue_free()
	
	# Clear all occupied cells
	for cell: Vector2i in placed.occupied_cells:
		occupied_cells.erase(cell)
	
	# Remove from placed pieces
	placed_pieces.erase(origin_pos)
	
	piece_removed.emit(origin_pos, piece_id)
	layout_changed.emit(origin_pos)
	
	print("LayoutData: Removed %s from %s" % [piece_id, origin_pos])
	return true

# =============================================
# QUERIES
# =============================================

func is_cell_occupied(grid_pos: Vector2i) -> bool:
	return grid_pos in occupied_cells


func get_piece_at(grid_pos: Vector2i) -> PlacedPiece:
	"""Get the piece at a grid position (or null if empty)"""
	if grid_pos in occupied_cells:
		var origin: Vector2i = occupied_cells[grid_pos]
		return placed_pieces.get(origin)
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
	
	# Check if all required cells are free
	var cells: Array[Vector2i] = _get_occupied_cells(grid_pos, piece_data.size, rotation)
	for cell: Vector2i in cells:
		if is_cell_occupied(cell):
			return false
	
	# For now, allow placement anywhere that's free
	# You can add connection validation here later:
	# - Check that at least one opening connects to an existing piece
	# - Or allow "starting" pieces with no connections
	
	return true

func would_connect(piece_id: String, grid_pos: Vector2i, rotation: int) -> bool:
	"""Check if placing this piece would connect to at least one existing piece"""
	if placed_pieces.is_empty():
		return true  # First piece can go anywhere
	
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

func get_all_placed_pieces() -> Array:
	"""Get all placed pieces"""
	return placed_pieces.values()

func clear_all() -> void:
	"""Remove all placed pieces"""
	for origin_pos: Vector2i in placed_pieces.keys():
		remove_piece(origin_pos)
