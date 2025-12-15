# Floor data structure
class_name FloorData
	
var floor_number: int
var floor_node: Node2D  # The actual instantiated floor scene
var scene_path: String  # Path to the floor scene file
var zones: Array[int]  # Zone IDs on this floor (from ZoneManager)
var is_loaded: bool = false
var is_active: bool = false  # Currently visible/active floor
var disabled_nav_tiles: Array[Vector2i] = []

func _init(num: int, path: String = "") -> void:
	floor_number = num
	scene_path = path
	zones = []
