# =============================================
# FloorManager.gd - 2D FLOOR MANAGEMENT
# =============================================
# Global singleton for managing hotel floors in a 2D game
# Each floor is a separate scene - only one visible at a time
# Add as autoload: FloorManager

extends Node

# Store all floors
var floors: Dictionary = {}  # floor_number -> FloorData
var current_floor: int = 1
var main_scene_container: Node2D = null  # Reference to where floors are added
var floor_nav_regions: Dictionary = {}  # floor_number: { tile_coords: RID }
# Signals
signal floor_changed(old_floor: int, new_floor: int)
signal floor_loaded(floor_number: int)
signal floor_unloaded(floor_number: int)
signal floor_navigation_ready(floor_number: int, floor_node: Node)
signal all_floors_ready()

func _ready() -> void:
	_setup_hotel_floors()

func _setup_hotel_floors() -> void:
	"""Define hotel structure with scene paths"""
	# Register floors with their scene paths
	register_floor(1, "res://scenes/floors/Floor1.tscn")
	register_floor(2, "res://scenes/floors/Floor2.tscn")
	#register_floor(3, "res://scenes/floors/Floor3.tscn")
	#register_floor(4, "res://scenes/floors/Floor4.tscn")
	#register_floor(5, "res://scenes/floors/Floor5.tscn")
	
	print("FloorManager: Initialized with %d floors" % floors.size())

func _setup_floor_metadata(floor_node: Node, floor_number: int) -> void:
	# Add metadata to floor node if it doesn't exist
	if not "floor_number" in floor_node:
		floor_node.set_meta("floor_number", floor_number)
	
	# Tag all children with floor number
	_tag_children_recursively(floor_node, floor_number)

# this is so we can do things to these objects like change collision layers and what not
func _tag_children_recursively(node: Node, floor_number: int) -> void:
	node.set_meta("floor_number", floor_number)
	for child in node.get_children():
		_tag_children_recursively(child, floor_number)
		
func register_floor(floor_number: int, scene_path: String = "", autoload: bool = true) -> void:
	"""Register a floor with its scene path"""
	var floor_data: FloorData = FloorData.new(floor_number, scene_path)
	floors[floor_number] = floor_data
	print("FloorManager: Registered floor %d -> %s" % [floor_number, scene_path])
	load_floor(floor_number)

func set_main_container(container: Node2D) -> void:
	"""Set the main scene container where floors will be added"""
	main_scene_container = container
	print("FloorManager: Main container set: %s" % container.name)

	
func setup_floor_navigation(floor_node: Node, floor_number: int) -> void:
	# Wait for navigation to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	
	# Find all TileMapLayers in the floor
	var tilemaps: Array[TileMapLayer] = []
	_find_all_tilemaps(floor_node, tilemaps)
	
	# Initialize navigation region mapping for this floor
	floor_nav_regions[floor_number] = {}
	
	for tilemap in tilemaps:
		# this affects behavior, unsure if this is a good or bad thing though
		#tilemap.tile_set.set_navigation_layer_layers(0, floor_number)
		map_tilemap_navigation_regions(tilemap, floor_number)
		tilemap.tile_set.set_navigation_layer_layer_value(0, floor_number, true)

	floor_navigation_ready.emit()

func map_tilemap_navigation_regions(tilemap: TileMapLayer, floor_number: int) -> void:
	var nav_map: RID = main_scene_container.get_world_2d().navigation_map
	var all_regions: Array[RID] = NavigationServer2D.map_get_regions(nav_map)
	var used_cells: Array[Vector2i] = tilemap.get_used_cells()
	
	print("Mapping navigation for tilemap: %s on floor %d" % [tilemap.name, floor_number])
	print("Used cells: %d, Total nav regions: %d" % [used_cells.size(), all_regions.size()])
	
	var tile_size: float = tilemap.tile_set.tile_size.x
	var max_distance: float = tile_size * 0.6
	
	for cell_coords: Vector2i in used_cells:
		var tile_data: TileData = tilemap.get_cell_tile_data(cell_coords)
		
		# Skip tiles without navigation polygons
		if not tile_data or not tile_data.get_navigation_polygon(0):
			continue
		
		# Get world position of this tile
		var cell_world_pos: Vector2 = tilemap.map_to_local(cell_coords)
		cell_world_pos = tilemap.to_global(cell_world_pos)
		
		# Find matching navigation region
		var matching_rid: RID = find_nav_region_at_position(all_regions, cell_world_pos, max_distance)
		
		if matching_rid != RID():
			# Set the navigation layer to the floor number
			NavigationServer2D.region_set_navigation_layers(matching_rid, floor_number)
			# Store the mapping
			floor_nav_regions[floor_number][cell_coords] = matching_rid
	
	print("Mapped %d navigation tiles for floor %d" % [floor_nav_regions[floor_number].size(), floor_number])

func find_nav_region_at_position(regions: Array[RID], target_pos: Vector2, max_distance: float) -> RID:
	var closest_rid: RID = RID()
	var closest_distance: float = INF
	
	for rid: RID in regions:
		var region_transform: Transform2D = NavigationServer2D.region_get_transform(rid)
		var region_pos: Vector2 = region_transform.origin
		var distance: float = region_pos.distance_to(target_pos)
		
		if distance < max_distance and distance < closest_distance:
			closest_distance = distance
			closest_rid = rid
	
	return closest_rid

func _find_all_tilemaps(node: Node, result: Array[TileMapLayer]) -> void:
	if node is TileMapLayer:
		result.append(node)
	for child in node.get_children():
		_find_all_tilemaps(child, result)

# Bonus: Utility functions for disabling/enabling navigation
func disable_navigation_at_tile(floor_number: int, tile_coords: Vector2i) -> void:
	if not floor_nav_regions.has(floor_number):
		return
	var current_floor_nav_region: Variant = floor_nav_regions[floor_number]
	if current_floor_nav_region.has(tile_coords):
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		NavigationServer2D.region_set_navigation_layers(rid, 0)
		NavigationServer2D.region_set_enabled(rid, false)

func enable_navigation_at_tile(floor_number: int, tile_coords: Vector2i) -> void:
	if not floor_nav_regions.has(floor_number):
		return
	
	if floor_nav_regions[floor_number].has(tile_coords):
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		NavigationServer2D.region_set_navigation_layers(rid, floor_number)
		NavigationServer2D.region_set_enabled(rid, true)

func load_floor(floor_number: int) -> Node2D:
	#"""Load a floor scene and add it to the main scene tree"""
	if floor_number not in floors:
		push_error("FloorManager: Floor %d does not exist" % floor_number)
		return null

	var floor_data: FloorData = floors[floor_number]

	# Already loaded
	if floor_data.is_loaded and floor_data.floor_node:
		return floor_data.floor_node

	# Must have a container
	if not main_scene_container:
		push_error("FloorManager: No main container set! Call set_main_container() first")
		return null

	# Load floor scene if specified
	if floor_data.scene_path != "" and ResourceLoader.exists(floor_data.scene_path):
		var floor_scene: Resource = load(floor_data.scene_path)
		floor_data.floor_node = floor_scene.instantiate()
		floor_data.floor_node.name = "Floor%d" % floor_number
	else:
		# **Create a Node2D if no scene exists**
		floor_data.floor_node = Node2D.new()
		floor_data.floor_node.name = "Floor%d_Fallback" % floor_number
		print("FloorManager: Created Node2D fallback for floor %d" % floor_number)

		# Optional: create a Zones container inside
		var zones: Node2D = Node2D.new()
		zones.name = "Zones"
		floor_data.floor_node.add_child(zones)

	# Add floor node to main container
	main_scene_container.add_child(floor_data.floor_node)

	_setup_floor_metadata(floor_data.floor_node, floor_number)

	# Hide by default12
	floor_data.floor_node.visible = false
	floor_data.floor_node.process_mode = Node.PROCESS_MODE_DISABLED
	_set_floor_collisions(floor_data.floor_node, false)
	# setup floor nav layers but disable the nav regions initially
	setup_floor_navigation(floor_data.floor_node, floor_number)
	_set_floor_navigation(floor_data.floor_node, true)
	floor_data.is_loaded = true
	
	# disable collisions
	emit_signal("floor_loaded", floor_number)
	print("FloorManager: Loaded floor %d" % floor_number)

	return floor_data.floor_node

func unload_floor(floor_number: int) -> void:
	"""Unload a floor scene and remove it from the scene tree"""
	if floor_number not in floors:
		return
	
	var floor_data: FloorData = floors[floor_number]
	if not floor_data.is_loaded:
		return
	
	print("FloorManager: Unloading floor %d" % floor_number)
	
	floor_data.is_loaded = false
	
	emit_signal("floor_unloaded", floor_number)
	print("FloorManager: Unloaded floor %d" % floor_number)

func set_active_floor(floor_number: int, initializing: bool = false) -> void:
	"""Set which floor is currently active (visible and processing)"""
	if floor_number not in floors:
		push_error("FloorManager: Floor %d does not exist" % floor_number)
		return
	
	if current_floor == floor_number and initializing == false:
		return
	
	var old_floor: int = current_floor
	
	# Hide and disable old floor
	if old_floor in floors and floors[old_floor].is_loaded:
		var old_floor_node: Node = floors[old_floor].floor_node
		if old_floor_node:
			old_floor_node.visible = false
			old_floor_node.process_mode = Node.PROCESS_MODE_DISABLED
			_set_floor_collisions(old_floor_node, false)
			_set_floor_navigation(old_floor_node, false)
			print("Setting old floor node collisions and navigation to false")
		floors[old_floor].is_active = false
	
	# Load new floor if not loaded
	if not floors[floor_number].is_loaded:
		load_floor(floor_number)
	
	# Show and enable new floor
	var new_floor_node: Node = floors[floor_number].floor_node
	if new_floor_node:
		new_floor_node.visible = true
		new_floor_node.process_mode = Node.PROCESS_MODE_INHERIT
		_set_floor_collisions(new_floor_node, true)
		_set_floor_navigation(new_floor_node, true)
	floors[floor_number].is_active = true
	
	current_floor = floor_number
	
	emit_signal("floor_changed", old_floor, floor_number)
	print("FloorManager: Active floor changed: %d -> %d" % [old_floor, floor_number])

func _create_fallback_floor(floor_number: int) -> Node2D:
	"""Create a basic fallback floor if scene doesn't exist"""
	print("FloorManager: Creating fallback floor %d" % floor_number)
	
	var floor: Node2D = Node2D.new()
	floor.name = "Floor%d_Fallback" % floor_number
	
	# Create zones container
	var zones: Node2D = Node2D.new()
	zones.name = "Zones"
	floor.add_child(zones)
	
	# Create some basic zones
	var zone_configs: Variant = [
		{"name": "Room_A", "pos": Vector2(200, 300), "size": Vector2(150, 100)},
		{"name": "Room_B", "pos": Vector2(400, 300), "size": Vector2(150, 100)},
		{"name": "Hallway", "pos": Vector2(300, 500), "size": Vector2(300, 80)}
	]
	
	for config: Variant in zone_configs:
		var zone: Area2D = _create_zone_area(config.name, config.pos, config.size)
		zones.add_child(zone)
	
	return floor
	
func _set_floor_collisions(floor_node: Node, enabled: bool) -> void:
	# Handle different collision node types
	for node: Node in _get_all_descendants(floor_node):
		_set_node_collision(node, enabled)
		
func _set_node_collision(node: Node, enabled: bool) -> void:
	# TileMap (Godot 4.x)
	if node is TileMapLayer:
		_set_tilemap_collision(node, enabled)
	
	# StaticBody2D / RigidBody2D / CharacterBody2D
	elif node is CollisionObject2D:
		_set_collision_object_state(node, enabled)
	
	# Area2D
	elif node is Area2D:
		node.monitoring = enabled
		node.monitorable = enabled
		_set_collision_object_state(node, enabled)

func _set_tilemap_collision(tilemap: TileMapLayer, enabled: bool) -> void:
	# In Godot 4, TileMaps have collision layers
	if enabled:
		tilemap.collision_enabled = true
	else:
		# Disable all collision layers
		tilemap.collision_enabled = false
		print("tilemap collision layer disabled")

func _set_floor_navigation(floor_node: Node, enabled: bool) -> void:
	for child in floor_node.get_children():
		if child is TileMapLayer:
			child.navigation_enabled = enabled 
		
		# Recursively check children
		if child.get_child_count() > 0:
			_set_floor_navigation(child, enabled)


func _set_collision_object_state(collision_object: CollisionObject2D, enabled: bool) -> void:
	if enabled:
		# Restore original collision settings
		if collision_object.has_meta("original_collision_layer"):
			collision_object.collision_layer = collision_object.get_meta("original_collision_layer")
			collision_object.collision_mask = collision_object.get_meta("original_collision_mask")
	else:
		# Store original and disable
		if not collision_object.has_meta("original_collision_layer"):
			collision_object.set_meta("original_collision_layer", collision_object.collision_layer)
			collision_object.set_meta("original_collision_mask", collision_object.collision_mask)
		
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	
	# Also disable collision shapes
	for child in collision_object.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not enabled)
			
func _get_all_descendants(node: Node) -> Array:
	var descendants: Array[Node] = [node]
	for child in node.get_children():
		descendants.append_array(_get_all_descendants(child))
	return descendants

func _create_zone_area(zone_name: String, pos: Vector2, size: Vector2) -> Area2D:
	"""Helper to create a basic zone Area2D"""
	var zone: Area2D = Area2D.new()
	zone.name = zone_name
	zone.position = pos
	
	var collision: CollisionPolygon2D = CollisionPolygon2D.new()
	var half: Vector2 = size / 2
	collision.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
	zone.add_child(collision)
	
	# Add visual for debugging
	var visual: Polygon2D = Polygon2D.new()
	visual.polygon = collision.polygon
	visual.color = Color(randf(), randf(), randf(), 0.3)
	zone.add_child(visual)
	
	return zone

func get_current_floor() -> int:
	"""Get the currently active floor number"""
	return current_floor

func get_floor_data(floor_number: int) -> FloorData:
	return floors.get(floor_number)

func get_floor_node(floor_number: int) -> Node2D:
	"""Get the actual Node2D for a loaded floor"""
	if floor_number in floors:
		return floors[floor_number].floor_node
	return null

func is_floor_loaded(floor_number: int) -> bool:
	if floor_number in floors:
		return floors[floor_number].is_loaded
	return false

func is_floor_active(floor_number: int) -> bool:
	if floor_number in floors:
		return floors[floor_number].is_active
	return false

func get_all_floors() -> Array:
	"""Get all registered floor numbers"""
	return floors.keys()

func get_loaded_floors() -> Array:
	"""Get currently loaded floor numbers"""
	var loaded: Array[int] = []
	for floor_num: int in floors:
		if floors[floor_num].is_loaded:
			loaded.append(floor_num)
	return loaded

func get_zones_on_floor(floor_number: int) -> Array[int]:
	"""Get all zone IDs on a specific floor"""
	if floor_number in floors:
		return floors[floor_number].zones
	return []
