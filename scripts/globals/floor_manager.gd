# =============================================
# MULTI-FLOOR HOTEL SYSTEM - DYNAMIC ZONES
# =============================================

# FloorManager.gd
# Global singleton for managing multiple hotel floors
# Add as autoload: FloorManager

extends Node

# Floor data structure
class Floor:
	var floor_number: int
	var floor_scene: Node2D  # The actual scene instance
	var zones: Array[Area2D]  # Zones on this floor
	var floor_y_range: Vector2  # Min/max Y position for this floor
	var is_loaded: bool = false
	var is_active: bool = false  # Player is on this floor
	
	func _init(num: int, y_min: float, y_max: float):
		floor_number = num
		floor_y_range = Vector2(y_min, y_max)
		zones = []

# Store all floors
var floors: Dictionary = {}  # floor_number -> Floor
var current_player_floor: int = 1
var floor_scenes_path: String = "res://scenes/floors/"

# Signals
signal floor_changed(old_floor: int, new_floor: int)
signal floor_loaded(floor_number: int)
signal floor_unloaded(floor_number: int)

func _ready():
	_setup_hotel_floors()

func _setup_hotel_floors():
	# Define hotel structure - just the Y ranges
	register_floor(1, 0, 400)      # Ground floor
	register_floor(2, 400, 800)    # Second floor
	register_floor(3, 800, 1200)   # Third floor
	register_floor(4, 1200, 1600)  # Fourth floor
	register_floor(5, 1600, 2000)  # Fifth floor
	
	print("Hotel structure initialized: %d floors" % floors.size())

func register_floor(floor_number: int, y_min: float, y_max: float):
	var floor = Floor.new(floor_number, y_min, y_max)
	floors[floor_number] = floor

func get_floor_from_position(position: Vector2) -> int:
	"""Determine which floor a position is on based on Y coordinate"""
	for floor_num in floors:
		var floor = floors[floor_num]
		if position.y >= floor.floor_y_range.x and position.y < floor.floor_y_range.y:
			return floor_num
	return 1  # Default to ground floor

func load_floor(floor_number: int, parent_node: Node2D) -> Node2D:
	"""Load a floor scene"""
	if floor_number not in floors:
		push_error("Floor %d does not exist" % floor_number)
		return null
	
	var floor = floors[floor_number]
	if floor.is_loaded:
		return floor.floor_scene
	
	# Load floor scene
	var scene_path = floor_scenes_path + "Floor%d.tscn" % floor_number
	if not ResourceLoader.exists(scene_path):
		push_warning("Floor scene not found: %s" % scene_path)
		return null
	
	var floor_scene = load(scene_path).instantiate()
	parent_node.add_child(floor_scene)
	floor.floor_scene = floor_scene
	floor.is_loaded = true
	
	# Register zones from this floor with ZoneManager
	_register_floor_zones(floor, floor_scene)
	
	emit_signal("floor_loaded", floor_number)
	print("Loaded floor %d" % floor_number)
	
	return floor_scene

func unload_floor(floor_number: int):
	"""Unload a floor scene (keep simulation running)"""
	if floor_number not in floors:
		return
	
	var floor = floors[floor_number]
	if not floor.is_loaded:
		return
	
	# Unregister zones from ZoneManager, maybe not though
	#for zone in floor.zones:
		#ZoneManager.unregister_zone(zone.name)
	#
	if floor.floor_scene:
		floor.floor_scene.queue_free()
		floor.floor_scene = null
	
	floor.is_loaded = false
	floor.zones.clear()
	
	emit_signal("floor_unloaded", floor_number)
	print("Unloaded floor %d" % floor_number)

func _register_floor_zones(floor: Floor, floor_scene: Node2D):
	"""Find and register all zones in a floor scene with ZoneManager"""
	var zones_container = floor_scene.get_node_or_null("Zones")
	if not zones_container:
		push_warning("No 'Zones' container found in floor %d scene" % floor.floor_number)
		return
	
	for child in zones_container.get_children():
		if child is Area2D:
			floor.zones.append(child)
			# Register with ZoneManager, including floor metadata
			ZoneManager.register_zone_with_floor(child.name, floor.floor_number, child)
			print("Registered zone '%s' on floor %d" % [child.name, floor.floor_number])

func set_active_floor(floor_number: int):
	"""Set which floor the player is currently on"""
	if current_player_floor == floor_number:
		return
	
	var old_floor = current_player_floor
	current_player_floor = floor_number
	
	# Update active status
	for floor_num in floors:
		floors[floor_num].is_active = (floor_num == floor_number)
	
	emit_signal("floor_changed", old_floor, floor_number)
	print("Player moved to floor %d" % floor_number)

func get_current_floor() -> int:
	return current_player_floor

func get_floor_data(floor_number: int) -> Floor:
	return floors.get(floor_number)

func get_all_floors() -> Array:
	return floors.keys()

func get_zones_on_floor(floor_number: int) -> Array[Area2D]:
	if floor_number in floors:
		return floors[floor_number].zones
	return []
