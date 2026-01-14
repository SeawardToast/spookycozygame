# Stores data about a single floor

class_name FloorData
extends RefCounted

var floor_number: int
var scene_path: String
var floor_node: Node2D = null
var is_loaded: bool = false
var is_active: bool = false
var nav_tilemap: TileMapLayer = null  # Reference tilemap for coordinate conversion
var zones: Array[int] = []


func _init(number: int, path: String = "") -> void:
	floor_number = number
	scene_path = path
