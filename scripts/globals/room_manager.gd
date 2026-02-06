extends Node

signal room_registered(room_instance_id: String)
signal room_unregistered(room_instance_id: String)
signal room_quality_changed(room_instance_id: String, new_quality: int)
signal guest_assigned(room_instance_id: String, guest_id: String)
signal guest_checked_in(room_instance_id: String, guest_id: String)
signal guest_checked_out(room_instance_id: String, guest_id: String)

# Room tracking
var placed_rooms: Dictionary = {}           # instance_id -> PlacedRoom
var rooms_by_grid: Dictionary = {}          # grid_pos -> instance_id
var rooms_by_hallway: Dictionary = {}       # hallway_instance_id -> [room_instance_ids]

# Assignment tracking
var active_assignments: Dictionary = {}     # assignment_id -> GuestAssignment
var room_assignments: Dictionary = {}       # room_instance_id -> assignment_id
var guest_to_room: Dictionary = {}          # guest_id -> room_instance_id

const SAVE_PATH: String = "user://room_manager_save.json"

# Quality values per furniture type
const FURNITURE_QUALITY: Dictionary = {
	"furniture_chest": 5,
	"furniture_bed_basic": 10,
	"furniture_bed_luxury": 25,
	"furniture_coffin": 15,
	"furniture_desk": 8,
	"furniture_wardrobe": 10,
}

# Amenities provided by furniture
const FURNITURE_AMENITIES: Dictionary = {
	"furniture_coffin": ["coffin", "bed"],
	"furniture_bed_basic": ["bed"],
	"furniture_bed_luxury": ["bed", "luxury"],
	"furniture_curtains": ["curtains", "darkness"],
}


func _ready() -> void:
	BuildingLayoutData.piece_added.connect(_on_furniture_placed)
	BuildingLayoutData.piece_removed.connect(_on_furniture_removed)


# =============================================
# ROOM REGISTRATION
# =============================================

func register_room(
	piece_id: String,
	grid_pos: Vector2i,
	floor_number: int,
	instance: Node2D,
	interior_cells: Array[Vector2i],
	door_grid_pos: Vector2i,
	door_world_pos: Vector2,
	hallway_data: Dictionary
) -> PlacedRoom:
	var room := PlacedRoom.new(piece_id, grid_pos, floor_number, instance, interior_cells)
	room.door_grid_pos = door_grid_pos
	room.door_world_pos = door_world_pos
	room.covered_hallway_id = hallway_data.get("hallway_id", "")
	room.covered_wall_cell = hallway_data.get("wall_cell", Vector2i.ZERO)
	room.covered_wall_tile_data = hallway_data.get("tile_data", {})
	room.door_side_wall_hidden = true

	placed_rooms[room.instance_id] = room
	rooms_by_grid[grid_pos] = room.instance_id

	# Track which hallway this room is attached to
	var hallway_id: String = room.covered_hallway_id
	if hallway_id:
		if hallway_id not in rooms_by_hallway:
			rooms_by_hallway[hallway_id] = []
		rooms_by_hallway[hallway_id].append(room.instance_id)

	# Initial quality scan
	rescan_room_furniture(room.instance_id)

	room_registered.emit(room.instance_id)
	print("RoomManager: Registered room %s at %s" % [room.instance_id, grid_pos])
	return room


func unregister_room(instance_id: String) -> bool:
	if instance_id not in placed_rooms:
		return false

	var room: PlacedRoom = placed_rooms[instance_id]

	# Cannot unregister if guest is assigned
	if room.is_occupied():
		push_warning("Cannot unregister room with guest assigned")
		return false

	# Restore hallway wall tile
	if room.covered_hallway_id and not room.covered_wall_tile_data.is_empty():
		_restore_hallway_wall_tile(room)

	# Remove from hallway tracking
	if room.covered_hallway_id in rooms_by_hallway:
		rooms_by_hallway[room.covered_hallway_id].erase(instance_id)
		if rooms_by_hallway[room.covered_hallway_id].is_empty():
			rooms_by_hallway.erase(room.covered_hallway_id)

	# Clean up tracking
	rooms_by_grid.erase(room.grid_pos)
	placed_rooms.erase(instance_id)

	# Free instance
	if room.instance and is_instance_valid(room.instance):
		room.instance.queue_free()

	room_unregistered.emit(instance_id)
	print("RoomManager: Unregistered room %s" % instance_id)
	return true


# =============================================
# HALLWAY WALL MANAGEMENT
# =============================================

func erase_hallway_wall_tile(hallway_instance: Node2D, wall_cell: Vector2i) -> Dictionary:
	var walls_layer: TileMapLayer = hallway_instance.get_node_or_null("GameTileMap/Walls")
	if not walls_layer:
		push_warning("RoomManager: No Walls layer found in hallway")
		return {}

	# Get current tile data before erasing
	var source_id: int = walls_layer.get_cell_source_id(wall_cell)
	var atlas_coords: Vector2i = walls_layer.get_cell_atlas_coords(wall_cell)
	var alternative_tile: int = walls_layer.get_cell_alternative_tile(wall_cell)

	if source_id == -1:
		push_warning("RoomManager: No tile at wall cell %s" % wall_cell)
		return {}

	var tile_data: Dictionary = {
		"source_id": source_id,
		"atlas_coords": {"x": atlas_coords.x, "y": atlas_coords.y},
		"alternative_tile": alternative_tile
	}

	# Erase the tile
	walls_layer.erase_cell(wall_cell)
	print("RoomManager: Erased hallway wall tile at %s" % wall_cell)

	return tile_data


func _restore_hallway_wall_tile(room: PlacedRoom) -> void:
	# Find the hallway instance
	var hallway_grid_pos := _parse_hallway_grid_pos(room.covered_hallway_id)
	var hallway: BuildingLayoutData.PlacedPiece = BuildingLayoutData.get_construction_at(hallway_grid_pos)

	if not hallway or not hallway.instance:
		push_warning("RoomManager: Could not find hallway instance to restore wall")
		return

	var walls_layer: TileMapLayer = hallway.instance.get_node_or_null("GameTileMap/Walls")
	if not walls_layer:
		return

	var tile_data: Dictionary = room.covered_wall_tile_data
	var atlas_coords := Vector2i(tile_data["atlas_coords"]["x"], tile_data["atlas_coords"]["y"])

	walls_layer.set_cell(
		room.covered_wall_cell,
		tile_data["source_id"],
		atlas_coords,
		tile_data["alternative_tile"]
	)
	print("RoomManager: Restored hallway wall tile at %s" % room.covered_wall_cell)


func _parse_hallway_grid_pos(hallway_id: String) -> Vector2i:
	# hallway_id format: "piece_id_x_y" e.g. "hallway_straight_10_20"
	var parts: PackedStringArray = hallway_id.rsplit("_", false, 2)
	if parts.size() >= 2:
		return Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))
	return Vector2i.ZERO


# =============================================
# HALLWAY PROTECTION
# =============================================

func has_attached_rooms(hallway_instance_id: String) -> bool:
	return hallway_instance_id in rooms_by_hallway and not rooms_by_hallway[hallway_instance_id].is_empty()


func get_attached_rooms(hallway_instance_id: String) -> Array[PlacedRoom]:
	var result: Array[PlacedRoom] = []
	if hallway_instance_id in rooms_by_hallway:
		for room_id: String in rooms_by_hallway[hallway_instance_id]:
			if room_id in placed_rooms:
				result.append(placed_rooms[room_id])
	return result


# =============================================
# QUERIES
# =============================================

func get_room_at(grid_pos: Vector2i) -> PlacedRoom:
	# Check if this exact position is a room origin
	var instance_id: String = rooms_by_grid.get(grid_pos, "")
	if instance_id:
		return placed_rooms.get(instance_id)

	# Check if this position is within any room's occupied cells
	for room: PlacedRoom in placed_rooms.values():
		if grid_pos in room.occupied_cells:
			return room

	return null


func get_rooms_on_floor(floor_number: int) -> Array[PlacedRoom]:
	var result: Array[PlacedRoom] = []
	for room: PlacedRoom in placed_rooms.values():
		if room.floor_number == floor_number:
			result.append(room)
	return result


func get_available_rooms() -> Array[PlacedRoom]:
	var result: Array[PlacedRoom] = []
	for room: PlacedRoom in placed_rooms.values():
		if room.is_available and not room.is_occupied():
			result.append(room)
	return result


# =============================================
# FURNITURE SCANNING
# =============================================

func _on_furniture_placed(grid_pos: Vector2i, piece_id: String) -> void:
	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(piece_id)
	if not piece_data or piece_data.building_type != DataTypes.BuildingType.FURNITURE:
		return

	# Check if this furniture is inside any room
	for room_id: String in placed_rooms:
		var room: PlacedRoom = placed_rooms[room_id]
		if grid_pos in room.occupied_cells:
			rescan_room_furniture(room_id)
			break


func _on_furniture_removed(grid_pos: Vector2i, _piece_id: String) -> void:
	for room_id: String in placed_rooms:
		var room: PlacedRoom = placed_rooms[room_id]
		if grid_pos in room.furniture_inside:
			rescan_room_furniture(room_id)
			break


func rescan_room_furniture(room_instance_id: String) -> void:
	var room: PlacedRoom = placed_rooms.get(room_instance_id)
	if not room:
		return

	var old_quality: int = room.current_quality
	room.furniture_inside.clear()
	var total_quality: int = 0

	# Scan all cells in room for furniture
	for cell: Vector2i in room.occupied_cells:
		var furniture: BuildingLayoutData.PlacedPiece = BuildingLayoutData.get_furniture_at(cell)
		if furniture:
			room.furniture_inside.append(cell)
			total_quality += FURNITURE_QUALITY.get(furniture.piece_id, 0)

	room.current_quality = total_quality

	if old_quality != room.current_quality:
		room_quality_changed.emit(room_instance_id, room.current_quality)
		print("RoomManager: Room %s quality changed to %d" % [room_instance_id, room.current_quality])


# =============================================
# GUEST ASSIGNMENT
# =============================================

func find_available_room(
	guest_type: String,
	min_quality: int = 0,
	required_amenities: Array = []
) -> String:
	for instance_id: String in placed_rooms:
		var room: PlacedRoom = placed_rooms[instance_id]
		if not room.is_available or room.is_occupied():
			continue

		# Check quality threshold
		if room.current_quality < min_quality:
			continue

		# Check required amenities
		if not _room_has_amenities(room, required_amenities):
			continue

		# TODO: Check guest type compatibility with room type
		return instance_id

	return ""


func assign_guest(
	guest_id: String,
	guest_type: String,
	room_instance_id: String,
	check_in_day: int,
	check_out_day: int
) -> GuestAssignment:
	var room: PlacedRoom = placed_rooms.get(room_instance_id)
	if not room or room.is_occupied():
		return null

	var assignment := GuestAssignment.create(
		guest_id, guest_type, room_instance_id, check_in_day, check_out_day
	)

	active_assignments[assignment.assignment_id] = assignment
	room_assignments[room_instance_id] = assignment.assignment_id
	guest_to_room[guest_id] = room_instance_id

	room.assigned_guest_id = guest_id
	room.is_available = false

	guest_assigned.emit(room_instance_id, guest_id)
	print("RoomManager: Assigned guest %s to room %s" % [guest_id, room_instance_id])
	return assignment


func check_in_guest(guest_id: String) -> bool:
	var room_id: String = guest_to_room.get(guest_id, "")
	if not room_id:
		return false

	var assignment_id: String = room_assignments.get(room_id, "")
	if not assignment_id:
		return false

	var assignment: GuestAssignment = active_assignments.get(assignment_id)
	if not assignment or assignment.status != GuestAssignment.Status.PENDING:
		return false

	assignment.status = GuestAssignment.Status.CHECKED_IN
	guest_checked_in.emit(room_id, guest_id)
	print("RoomManager: Guest %s checked in to room %s" % [guest_id, room_id])
	return true


func check_out_guest(guest_id: String) -> bool:
	var room_id: String = guest_to_room.get(guest_id, "")
	if not room_id:
		return false

	var assignment_id: String = room_assignments.get(room_id, "")
	var assignment: GuestAssignment = active_assignments.get(assignment_id) if assignment_id else null

	var room: PlacedRoom = placed_rooms.get(room_id)
	if room:
		room.assigned_guest_id = ""
		room.is_available = true

	if assignment:
		assignment.status = GuestAssignment.Status.CHECKED_OUT

	room_assignments.erase(room_id)
	guest_to_room.erase(guest_id)

	guest_checked_out.emit(room_id, guest_id)
	print("RoomManager: Guest %s checked out of room %s" % [guest_id, room_id])
	return true


func get_guest_room(guest_id: String) -> PlacedRoom:
	var room_id: String = guest_to_room.get(guest_id, "")
	return placed_rooms.get(room_id)


# =============================================
# HELPERS
# =============================================

func _room_has_amenities(room: PlacedRoom, required: Array) -> bool:
	for amenity: String in required:
		var found: bool = false
		for cell: Vector2i in room.furniture_inside:
			var furniture: BuildingLayoutData.PlacedPiece = BuildingLayoutData.get_furniture_at(cell)
			if furniture and _furniture_provides_amenity(furniture.piece_id, amenity):
				found = true
				break
		if not found:
			return false
	return true


func _furniture_provides_amenity(piece_id: String, amenity: String) -> bool:
	var provides: Array = FURNITURE_AMENITIES.get(piece_id, [])
	return amenity in provides


# =============================================
# SAVE/LOAD
# =============================================

func get_save_data() -> Dictionary:
	var rooms_data: Array = []
	for room: PlacedRoom in placed_rooms.values():
		rooms_data.append(room.to_dict())

	var assignments_data: Array = []
	for assignment: GuestAssignment in active_assignments.values():
		assignments_data.append(assignment.to_dict())

	return {
		"rooms": rooms_data,
		"assignments": assignments_data
	}


func load_save_data(data: Dictionary) -> void:
	# Clear existing
	placed_rooms.clear()
	rooms_by_grid.clear()
	rooms_by_hallway.clear()
	active_assignments.clear()
	room_assignments.clear()
	guest_to_room.clear()

	# Restore rooms (instances will be set when scenes load)
	for room_dict: Dictionary in data.get("rooms", []):
		var room := PlacedRoom.from_dict(room_dict)
		placed_rooms[room.instance_id] = room
		rooms_by_grid[room.grid_pos] = room.instance_id

		if room.covered_hallway_id:
			if room.covered_hallway_id not in rooms_by_hallway:
				rooms_by_hallway[room.covered_hallway_id] = []
			rooms_by_hallway[room.covered_hallway_id].append(room.instance_id)

	# Restore assignments
	for assign_dict: Dictionary in data.get("assignments", []):
		var assignment := GuestAssignment.from_dict(assign_dict)
		active_assignments[assignment.assignment_id] = assignment
		room_assignments[assignment.room_instance_id] = assignment.assignment_id
		guest_to_room[assignment.guest_id] = assignment.room_instance_id

	print("RoomManager: Loaded %d rooms, %d assignments" % [placed_rooms.size(), active_assignments.size()])


func save_rooms() -> void:
	var data: Dictionary = get_save_data()
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("RoomManager: Saved to %s" % SAVE_PATH)
	else:
		push_error("RoomManager: Failed to save")


func load_rooms() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			load_save_data(json.data)
		file.close()
