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
	var door_positions: Array[Vector2i]  # For rooms: where doors can connect
	var building_type: DataTypes.BuildingType  # CONSTRUCTION or FURNITURE
	
	func _init(
		p_id: String,
		p_display_name: String,
		p_scene_path: String,
		p_size: Vector2i = Vector2i(1, 1),
		p_openings: Array[Vector2i] = [],
		p_category: String = "hallway",
		p_is_room: bool = false,
		p_door_positions: Array[Vector2i] = [],
		p_building_type: DataTypes.BuildingType = DataTypes.BuildingType.CONSTRUCTION
	) -> void:
		id = p_id
		display_name = p_display_name
		scene_path = p_scene_path
		size = p_size
		openings = p_openings
		category = p_category
		is_room = p_is_room
		door_positions = p_door_positions
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
		"res://scenes/buildings/hallway_straight.tscn",
		Vector2i(1, 1),
		[Vector2i.UP, Vector2i.DOWN],
		"hallway"
	))
	
	# L-turn (connects up and right)
	register_piece(PieceData.new(
		"hallway_l_turn",
		"L-Turn",
		"res://scenes/building/hallways/hallway_l_turn.tscn",
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
	# ROOM PIECES (examples - you'll customize these)
	# =============================================

	# Small room (2x2)
	#register_piece(PieceData.new(
	#	"room_small",
	#	"Small Room",
	#	"res://scenes/building/rooms/room_small.tscn",
	#	Vector2i(2, 2),
	#	[],  # Rooms don't use openings
	#	"room",
	#	true,
	#	[Vector2i(0, 1), Vector2i(1, 0)]  # Door positions on perimeter
	#))

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
		[],
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


func get_rotated_door_positions(piece_id: String, rotation: int) -> Array[Vector2i]:
	"""Get door positions for a room after applying rotation"""
	var piece: PieceData = get_piece(piece_id)
	if not piece or not piece.is_room:
		return []
	
	var rotated: Array[Vector2i] = []
	for door_pos: Vector2i in piece.door_positions:
		var rotated_pos: Vector2i = _rotate_position(door_pos, piece.size, rotation)
		rotated.append(rotated_pos)
	
	return rotated


func _rotate_direction(dir: Vector2i, rotation: int) -> Vector2i:
	"""Rotate a direction vector by rotation * 90 degrees clockwise"""
	var result: Vector2i = dir
	for i: int in rotation:
		# 90 degree clockwise rotation: (x, y) -> (y, -x)
		# But for grid directions: (x, y) -> (-y, x)
		result = Vector2i(-result.y, result.x)
	return result


func _rotate_position(pos: Vector2i, size: Vector2i, rotation: int) -> Vector2i:
	"""Rotate a position within a piece's bounds"""
	var result: Vector2i = pos
	var current_size: Vector2i = size
	
	for i: int in rotation:
		# Rotate position 90 degrees clockwise within bounds
		var new_x: int = current_size.y - 1 - result.y
		var new_y: int = result.x
		result = Vector2i(new_x, new_y)
		# Size dimensions swap on each rotation
		current_size = Vector2i(current_size.y, current_size.x)
	
	return result
