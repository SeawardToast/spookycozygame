# PieceRegistry.gd
# Defines all placeable building pieces and their properties
extends Node

# Piece data structure
class PieceData:
	var id: String
	var display_name: String
	var scene_path: String
	var icon_path: String
	var size: Vector2i  # Grid cells this piece occupies
	var openings: Array[Vector2i]  # Which directions have connections (before rotation)
	var category: String  # "hallway", "room", etc.
	var is_room: bool
	var building_type: DataTypes.BuildingType  # CONSTRUCTION or FURNITURE

	# Cached connectable layer data (computed once, reused many times)
	var connectable_layers_cached: bool = false
	var cached_layer_data: Array = []  # Array of {offset: Vector2i, tiles: Array[Vector2i]}

	func _init(
		p_id: String,
		p_display_name: String,
		p_scene_path: String,
		p_size: Vector2i = Vector2i(1, 1),
		p_openings: Array[Vector2i] = [],
		p_category: String = "hallway",
		p_is_room: bool = false,
		p_building_type: DataTypes.BuildingType = DataTypes.BuildingType.CONSTRUCTION
	) -> void:
		id = p_id
		display_name = p_display_name
		scene_path = p_scene_path
		size = p_size
		openings = p_openings
		category = p_category
		is_room = p_is_room
		building_type = p_building_type
		icon_path = ""


# All registered pieces
var pieces: Dictionary = {}  # id -> PieceData

func _ready() -> void:
	_register_default_pieces()

func _register_default_pieces() -> void:
	# =============================================
	# HALLWAY PIECES
	# =============================================
	# Openings use Vector2i directions: UP = (0,-1), DOWN = (0,1), LEFT = (-1,0), RIGHT = (1,0)
	
	# Straight hallway (vertical)
	register_piece(PieceData.new(
		"hallway_straight",
		"Straight Hallway",
		"res://scenes/constructions/hallway_straight.tscn",
		Vector2i(6, 12),
		[Vector2i.UP, Vector2i.DOWN],
		"hallway"
	))
	
	# Straight hallway (horizontal)
	register_piece(PieceData.new(
		"hallway_straight_horizontal",
		"Straight Horizontal Hallway",
		"res://scenes/constructions/hallway_straight_horizontal.tscn",
		Vector2i(12, 6),
		[Vector2i.UP, Vector2i.DOWN],
		"hallway"
	))
	
	# L-turn (connects up and right)
	register_piece(PieceData.new(
		"hallway_L",
		"L-Turn SE",
		"res://scenes/constructions/hallway_L_S_E.tscn",
		Vector2i(1, 1),
		[Vector2i.UP, Vector2i.RIGHT],
		"hallway"
	))
	
		# L-turn (connects from north to west)
	register_piece(PieceData.new(
		"hallway_L_N_W",
		"L-Turn NW",
		"res://scenes/constructions/hallway_L_N_W.tscn",
		Vector2i(1, 1),
		[Vector2i.UP, Vector2i.RIGHT],
		"hallway"
	))
	
			# L-turn (connects from north to east)
	register_piece(PieceData.new(
		"hallway_L_N_E",
		"L-Turn NE",
		"res://scenes/constructions/hallway_L_N_E.tscn",
		Vector2i(1, 1),
		[Vector2i.UP, Vector2i.RIGHT],
		"hallway"
	))
	
	# Inverted L-turn (connects up and left)
	register_piece(PieceData.new(
		"hallway_L_inverted",
		"L-Turn Inverted",
		"res://scenes/constructions/hallway_L_inverted.tscn",
		Vector2i(1, 1),
		[Vector2i.UP, Vector2i.RIGHT],
		"hallway"
	))
	
	# T-junction (connects up, left, right)
	register_piece(PieceData.new(
		"hallway_t_junction",
		"T-Junction",
		"res://scenes/building/hallways/hallway_t_junction.tscn",
		Vector2i(1, 1),
		[Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT],
		"hallway"
	))
	
	# Cross/4-way intersection
	register_piece(PieceData.new(
		"hallway_cross",
		"4-Way Intersection",
		"res://scenes/building/hallways/hallway_cross.tscn",
		Vector2i(1, 1),
		[Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT],
		"hallway"
	))
	
	# =============================================
	# ROOM PIECES
	# =============================================

	# Dark Chamber (Small) - for vampires
	# Door position is determined by door_edge layer in scene
	register_piece(PieceData.new(
		"room_dark_small",
		"Dark Chamber (Small)",
		"res://scenes/constructions/rooms/dark_small_room.tscn",
		Vector2i(7, 7),
		[],  # Rooms don't use openings
		"room",
		true,
		DataTypes.BuildingType.CONSTRUCTION
	))

	# =============================================
	# FURNITURE PIECES
	# =============================================

	# Storage Chest - can be placed on constructions
	register_piece(PieceData.new(
		"furniture_chest",
		"Storage Chest",
		"res://scenes/objects/storage_chest/storage_chest.tscn",
		Vector2i(1, 1),
		[],  # Furniture doesn't use openings
		"furniture",
		false,
		DataTypes.BuildingType.FURNITURE
	))

	print("PieceRegistry: Registered %d pieces" % pieces.size())


func register_piece(piece_data: PieceData) -> void:
	pieces[piece_data.id] = piece_data

func get_piece(piece_id: String) -> PieceData:
	return pieces.get(piece_id)

func get_all_pieces() -> Array:
	return pieces.values()

func get_pieces_by_category(category: String) -> Array:
	var result: Array = []
	for piece: PieceData in pieces.values():
		if piece.category == category:
			result.append(piece)
	return result

func get_piece_ids() -> Array:
	return pieces.keys()

# =============================================
# CONNECTABLE LAYER CACHING
# =============================================

func get_cached_connectable_layers(piece_id: String) -> Array:
	"""Get cached connectable layer data for a piece

	Returns: Array of {offset: Vector2i, tiles: Array[Vector2i]}
	Caches the result to avoid repeated scene loading
	"""
	var piece: PieceData = get_piece(piece_id)
	if not piece:
		return []

	# Return cached data if available
	if piece.connectable_layers_cached:
		return piece.cached_layer_data

	# Compute and cache the data
	var scene: PackedScene = load(piece.scene_path)
	if not scene:
		piece.connectable_layers_cached = true
		return []

	var temp_instance: Node2D = scene.instantiate()
	var layer_data: Array = []

	# Find all connectable layers and extract their data
	var layers: Array = _find_connectable_layers_recursive(temp_instance)
	for layer: TileMapLayer in layers:
		var layer_offset_pixels: Vector2 = layer.position
		var layer_offset_cells: Vector2i = Vector2i(
			floori(layer_offset_pixels.x / 16),  # TODO: Use cell_size from somewhere
			floori(layer_offset_pixels.y / 16)
		)
		var local_tiles: Array[Vector2i] = layer.get_used_cells()

		layer_data.append({
			"offset": layer_offset_cells,
			"tiles": local_tiles
		})

	temp_instance.queue_free()

	# Cache the result
	piece.cached_layer_data = layer_data
	piece.connectable_layers_cached = true

	return layer_data


func _find_connectable_layers_recursive(node: Node) -> Array:
	"""Recursively find all TileMapLayers in 'connectable_tiles' group"""
	var layers: Array = []

	if node is TileMapLayer:
		var tilemap: TileMapLayer = node as TileMapLayer
		if tilemap.is_in_group("connectable_tiles"):
			layers.append(tilemap)

	for child in node.get_children():
		layers.append_array(_find_connectable_layers_recursive(child))

	return layers

# =============================================
# ROTATION HELPERS
# =============================================

func get_rotated_openings(piece_id: String, rotation: int) -> Array[Vector2i]:
	"""Get openings for a piece after applying rotation (0-3, each step is 90 degrees clockwise)"""
	var piece: PieceData = get_piece(piece_id)
	if not piece:
		return []
	
	var rotated: Array[Vector2i] = []
	for opening: Vector2i in piece.openings:
		var rotated_opening: Vector2i = _rotate_direction(opening, rotation)
		rotated.append(rotated_opening)
	
	return rotated


func _rotate_direction(dir: Vector2i, rotation: int) -> Vector2i:
	"""Rotate a direction vector by rotation * 90 degrees clockwise"""
	var result: Vector2i = dir
	for i: int in rotation:
		# 90 degree clockwise rotation: (x, y) -> (y, -x)
		# But for grid directions: (x, y) -> (-y, x)
		result = Vector2i(-result.y, result.x)
	return result
