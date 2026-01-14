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
var floor_astars: Dictionary = {}  # floor_number -> AStarGrid2D
var floors_nav_ready: Dictionary = {}  # floor_number -> bool (tracks which floors have navigation ready)
var all_floors_initialized: bool = false

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
	
	# Preload all floors and their navigation
	await _preload_all_floors()
	all_floors_initialized = true
	all_floors_ready.emit()
	print("FloorManager: All floors preloaded and navigation ready!")

	
func setup_floor_navigation(floor_node: Node, floor_number: int) -> void:
	# Wait for navigation to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	
	print("Setting up navigation for floor %d..." % floor_number)
	
	# Find all TileMapLayers in the floor
	var tilemaps: Array[TileMapLayer] = []
	_find_all_tilemaps(floor_node, tilemaps)
	
	# Initialize navigation region mapping for this floor
	floor_nav_regions[floor_number] = {}
	for tilemap in tilemaps:
		map_tilemap_navigation_regions(tilemap, floor_number)
		tilemap.tile_set.set_navigation_layer_layer_value(0, floor_number, true)
	
	# Process obstacle tilemaps to disable navigation under them
	_process_obstacle_tilemaps(floor_node, floor_number)
	
	# build a star map for unrendered navigation
	_build_floor_astar(floor_number)
	# Mark this floor's navigation as ready
	floors_nav_ready[floor_number] = true
	floor_navigation_ready.emit(floor_number, floor_node)
	print("Navigation ready for floor %d" % floor_number)
	
func _build_floor_astar(floor_number: int) -> void:
	var astar: AStarGrid2D = AStarGrid2D.new()
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN

	# Get all navigable tiles
	var tiles: Array = floor_nav_regions[floor_number].keys()
	if tiles.is_empty():
		return

	# Determine bounds
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF

	for t: Vector2i in tiles:
		min_x = min(min_x, t.x)
		min_y = min(min_y, t.y)
		max_x = max(max_x, t.x)
		max_y = max(max_y, t.y)

	astar.region = Rect2i(
		Vector2i(min_x, min_y),
		Vector2i(max_x - min_x + 1, max_y - min_y + 1)
	)

	astar.cell_size = Vector2.ONE
	astar.update()

	# Enable navigable tiles
	for tile: Vector2i in tiles:
		astar.set_point_solid(tile, false)

	# Disable blocked tiles
	for blocked: Variant in floors[floor_number].disabled_nav_tiles:
		astar.set_point_solid(blocked, true)

	floor_astars[floor_number] = astar

func get_navigation_path(
	floor_number: int,
	start_world_pos: Vector2,
	end_world_pos: Vector2,
) -> Array[Vector2]:

	if not floor_astars.has(floor_number):
		push_error("Navigation not ready for floor %d" % floor_number)
		return []

	var floor_node: Node2D = get_floor_node(floor_number)
	if not floor_node:
		return []

	# Convert world → tile
	var tilemap: TileMapLayer = _get_primary_navigation_tilemap(floor_node)
	if not tilemap:
		return []

	var start_tile: Vector2i = tilemap.local_to_map(
		tilemap.to_local(start_world_pos)
	)
	var end_tile: Vector2i = tilemap.local_to_map(
		tilemap.to_local(end_world_pos)
	)

	var astar: AStarGrid2D = floor_astars[floor_number]

	if astar.is_point_solid(start_tile) or astar.is_point_solid(end_tile):
		return []

	var tile_path: Array[Vector2i] = astar.get_id_path(start_tile, end_tile)

	# Convert back to world positions
	var world_path: Array[Vector2] = []
	for tile in tile_path:
		var local: Vector2 = tilemap.map_to_local(tile)
		world_path.append(tilemap.to_global(local))

	return world_path
	
func _get_primary_navigation_tilemap(floor_node: Node) -> TileMapLayer:
	var tilemaps: Array[TileMapLayer] = []
	_find_navigation_tilemaps(floor_node, tilemaps)
	return null if tilemaps.is_empty() else tilemaps[0]

	
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
			# IMPORTANT: Disable by default - will be enabled when floor becomes active
			NavigationServer2D.region_set_enabled(matching_rid, false)
	
	print("Mapped %d navigation tiles for floor %d (all disabled by default)" % [floor_nav_regions[floor_number].size(), floor_number])

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

func _process_obstacle_tilemaps(floor_node: Node, floor_number: int) -> void:
	"""
	Find all TileMapLayers in the 'navigation_obstacles' group and disable
	navigation underneath their tiles.
	"""
	var obstacle_tilemaps: Array[Node] = []
	_find_nodes_in_group(floor_node, "navigation_obstacles", obstacle_tilemaps)
	
	print("=== OBSTACLE PROCESSING DEBUG ===")
	print("Floor %d node: %s" % [floor_number, floor_node.name if floor_node else "NULL"])
	print("Obstacle tilemaps found: %d" % obstacle_tilemaps.size())
	
	if obstacle_tilemaps.is_empty():
		print("FloorManager: No obstacle tilemaps found in 'navigation_obstacles' group on floor %d" % floor_number)
		print("Make sure your obstacle TileMapLayers are added to the 'navigation_obstacles' group!")
		return
	
	print("FloorManager: Processing %d obstacle tilemaps on floor %d" % [obstacle_tilemaps.size(), floor_number])
	
	for obstacle_tilemap in obstacle_tilemaps:
		if obstacle_tilemap is TileMapLayer:
			print("  Processing obstacle layer: %s" % obstacle_tilemap.name)
			_disable_navigation_under_obstacles(obstacle_tilemap, floor_number)
		else:
			print("  WARNING: Node '%s' in navigation_obstacles group is not a TileMapLayer!" % obstacle_tilemap.name)

func _find_nodes_in_group(node: Node, group_name: String, result: Array[Node]) -> void:
	"""Recursively find all nodes in a specific group"""
	if node.is_in_group(group_name):
		result.append(node)
	for child in node.get_children():
		_find_nodes_in_group(child, group_name, result)

func _disable_navigation_under_obstacles(obstacle_tilemap: TileMapLayer, floor_number: int) -> void:
	"""
	Disables navigation for all tiles in the navigation tilemap that are covered
	by tiles in the obstacle tilemap.
	"""
	var used_cells: Array[Vector2i] = obstacle_tilemap.get_used_cells()
	
	print("  === Obstacle layer '%s' ===" % obstacle_tilemap.name)
	print("    Obstacle tiles: %d" % used_cells.size())
	print("    Obstacle global pos: %s" % obstacle_tilemap.global_position)
	
	if used_cells.is_empty():
		print("    WARNING: No tiles found in this obstacle layer!")
		return
	
	# Check if we have navigation regions mapped
	if not floor_nav_regions.has(floor_number) or floor_nav_regions[floor_number].is_empty():
		print("    ERROR: No navigation regions mapped for floor %d yet!" % floor_number)
		print("    Navigation must be set up before processing obstacles!")
		return
	
	print("    Available nav regions: %d" % floor_nav_regions[floor_number].size())
	
	var successful_disables: int = 0
	var failed_disables: int = 0
	
	for cell_coords: Vector2i in used_cells:
		# Get the world position of this obstacle cell
		var obstacle_local_pos: Vector2 = obstacle_tilemap.map_to_local(cell_coords)
		var obstacle_world_pos: Vector2 = obstacle_tilemap.to_global(obstacle_local_pos)
		
		# Find the navigation tile coordinate at this world position
		var nav_tile_coords: Vector2i = _world_pos_to_nav_tile_direct(obstacle_world_pos, floor_number)
		
		# Check if this nav tile exists in our regions
		if floor_nav_regions[floor_number].has(nav_tile_coords):
			disable_navigation_at_tile(floor_number, nav_tile_coords)
			successful_disables += 1
		else:
			failed_disables += 1
			if failed_disables <= 3:  # Only print first few failures
				print("    No nav tile at coords %s (world: %s)" % [nav_tile_coords, obstacle_world_pos])
	
	print("    Successfully disabled: %d" % successful_disables)
	if failed_disables > 0:
		print("    Failed to find nav tiles: %d" % failed_disables)
	print("  ===========================")

func _world_pos_to_nav_tile_direct(world_pos: Vector2, floor_number: int) -> Vector2i:
	"""
	Convert a world position to navigation tile coordinate by directly checking
	against mapped navigation regions.
	"""
	if not floor_nav_regions.has(floor_number):
		return Vector2i(-99999, -99999)
	
	# Find the closest navigation tile to this world position
	var closest_tile: Vector2i = Vector2i(-99999, -99999)
	var closest_distance: float = INF
	var search_radius: float = 32.0  # Adjust based on your tile size
	
	for nav_tile_coords: Vector2i in floor_nav_regions[floor_number].keys():
		var rid: RID = floor_nav_regions[floor_number][nav_tile_coords]
		var region_transform: Transform2D = NavigationServer2D.region_get_transform(rid)
		var region_pos: Vector2 = region_transform.origin
		
		var distance: float = region_pos.distance_to(world_pos)
		if distance < search_radius and distance < closest_distance:
			closest_distance = distance
			closest_tile = nav_tile_coords
	
	return closest_tile

func _find_navigation_tilemaps(node: Node, result: Array[TileMapLayer]) -> void:
	"""Find TileMapLayers that have navigation polygons"""
	if node is TileMapLayer:
		var tilemap: TileMapLayer = node
		# Check if this tilemap has any tiles with navigation data
		if _tilemap_has_navigation(tilemap):
			result.append(tilemap)
	
	for child in node.get_children():
		_find_navigation_tilemaps(child, result)

func _tilemap_has_navigation(tilemap: TileMapLayer) -> bool:
	"""Check if a tilemap has any navigation polygons"""
	var used_cells: Array[Vector2i] = tilemap.get_used_cells()
	for cell_coords: Vector2i in used_cells:
		var tile_data: TileData = tilemap.get_cell_tile_data(cell_coords)
		if tile_data and tile_data.get_navigation_polygon(0):
			return true
	return false

func disable_navigation_at_tile(floor_number: int, tile_coords: Vector2i) -> void:
	if not floor_nav_regions.has(floor_number):
		return
	var current_floor_nav_region: Variant = floor_nav_regions[floor_number]
	if current_floor_nav_region.has(tile_coords):
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		NavigationServer2D.region_set_navigation_layers(rid, 0)
		NavigationServer2D.region_set_enabled(rid, false)
		
		# Track this tile as disabled in the floor data
		if tile_coords not in floors[floor_number].disabled_nav_tiles:
			floors[floor_number].disabled_nav_tiles.append(tile_coords)
			if floor_astars.has(floor_number):
				floor_astars[floor_number].set_point_solid(tile_coords, true)

func enable_navigation_at_tile(floor_number: int, tile_coords: Vector2i) -> void:
	if not floor_nav_regions.has(floor_number):
		return
	
	if floor_nav_regions[floor_number].has(tile_coords):
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		NavigationServer2D.region_set_navigation_layers(rid, floor_number)
		NavigationServer2D.region_set_enabled(rid, true)
		if floor_astars.has(floor_number):
			floor_astars[floor_number].set_point_solid(tile_coords, false)
		# Remove this tile from the disabled list
		if floors[floor_number].disabled_nav_tiles:
			var disabled_tiles: Array = floors[floor_number].disabled_nav_tiles
			var index: int = disabled_tiles.find(tile_coords)
			if index != -1:
				disabled_tiles.remove_at(index)

func _disable_floor_navigation(floor_number: int) -> void:
	"""Disable all navigation regions for a specific floor"""
	if not floor_nav_regions.has(floor_number):
		return
	
	print("Disabling navigation for floor %d" % floor_number)
	for tile_coords: Vector2i in floor_nav_regions[floor_number]:
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		NavigationServer2D.region_set_enabled(rid, false)
	
	print("Disabled %d navigation regions for floor %d" % [floor_nav_regions[floor_number].size(), floor_number])

func _enable_floor_navigation(floor_number: int) -> void:
	"""Enable all navigation regions for a specific floor"""
	if not floor_nav_regions.has(floor_number):
		return
	
	print("Enabling navigation for floor %d" % floor_number)
	
	# Get the list of tiles that should remain disabled
	var disabled_tiles: Array = []
	disabled_tiles = floors[floor_number].disabled_nav_tiles
	
	for tile_coords: Vector2i in floor_nav_regions[floor_number]:
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		
		# Check if this tile should remain disabled
		if tile_coords in disabled_tiles:
			NavigationServer2D.region_set_enabled(rid, false)
			NavigationServer2D.region_set_navigation_layers(rid, 0)
		else:
			NavigationServer2D.region_set_enabled(rid, true)
			NavigationServer2D.region_set_navigation_layers(rid, floor_number)
	
	print("Enabled %d navigation regions for floor %d (%d tiles remain disabled)" % [floor_nav_regions[floor_number].size(), floor_number, disabled_tiles.size()])

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

	# Hide by default
	floor_data.floor_node.visible = false
	floor_data.floor_node.process_mode = Node.PROCESS_MODE_DISABLED
	_set_floor_collisions(floor_data.floor_node, false)
	floor_data.is_loaded = true
	
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
			_disable_floor_navigation(old_floor)
			print("Disabled old floor %d (collisions and navigation off)" % old_floor)
		floors[old_floor].is_active = false
	
	# Load new floor if not loaded (shouldn't happen with preloading, but safety check)
	if not floors[floor_number].is_loaded:
		load_floor(floor_number)
	
	# Show and enable new floor
	var new_floor_node: Node = floors[floor_number].floor_node
	if new_floor_node:
		new_floor_node.visible = true
		new_floor_node.process_mode = Node.PROCESS_MODE_INHERIT
		_set_floor_collisions(new_floor_node, true)
		
		# Setup navigation if not already mapped (shouldn't happen with preloading)
		if not floor_nav_regions.has(floor_number):
			await setup_floor_navigation(new_floor_node, floor_number)
		
		# Enable navigation for this floor
		_enable_floor_navigation(floor_number)
		print("Enabled new floor %d (collisions and navigation on)" % floor_number)

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

# =============================================
# RUNTIME OBSTACLE MANAGEMENT
# =============================================
# Use these functions to dynamically enable/disable navigation at runtime

func refresh_floor_obstacles(floor_number: int) -> void:
	"""
	Reprocess all obstacle tilemaps on a floor.
	Useful if obstacles have been added/removed at runtime.
	"""
	var floor_node: Node2D = get_floor_node(floor_number)
	if not floor_node:
		return
	
	# Clear previously disabled tiles (they'll be re-disabled if obstacles still exist)
	if floors[floor_number].disabled_nav_tiles:
		floors[floor_number].disabled_nav_tiles.clear()
	
	# Reprocess obstacles
	_process_obstacle_tilemaps(floor_node, floor_number)

func disable_navigation_at_world_pos(floor_number: int, world_pos: Vector2) -> void:
	"""Disable navigation at a specific world position"""
	var nav_tile_coords: Vector2i = _world_pos_to_nav_tile_direct(world_pos, floor_number)
	if nav_tile_coords != Vector2i(-99999, -99999):
		disable_navigation_at_tile(floor_number, nav_tile_coords)

func enable_navigation_at_world_pos(floor_number: int, world_pos: Vector2) -> void:
	"""Enable navigation at a specific world position"""
	var nav_tile_coords: Vector2i = _world_pos_to_nav_tile_direct(world_pos, floor_number)
	if nav_tile_coords != Vector2i(-99999, -99999):
		enable_navigation_at_tile(floor_number, nav_tile_coords)

# =============================================
# PRELOADING & INITIALIZATION
# =============================================

func _preload_all_floors() -> void:
	"""
	Load all registered floors and set up their navigation regions.
	This ensures NPCs can path to any floor immediately.
	"""
	print("FloorManager: Preloading all floors...")
	
	var floor_numbers: Array = floors.keys()
	
	# Load all floors first
	for floor_number: int in floor_numbers:
		if not floors[floor_number].is_loaded:
			load_floor(floor_number)
			await get_tree().process_frame
	
	# Set up navigation for all floors (they'll be disabled by default in map_tilemap_navigation_regions)
	for floor_number: int in floor_numbers:
		var floor_node: Node2D = get_floor_node(floor_number)
		if floor_node and not floors_nav_ready.get(floor_number, false):
			await setup_floor_navigation(floor_node, floor_number)
	
	# Now enable only the current floor's navigation
	_enable_floor_navigation(current_floor)
	
	print("FloorManager: All %d floors preloaded and navigation initialized" % floor_numbers.size())
	print("FloorManager: Only floor %d navigation is active" % current_floor)

func is_floor_navigation_ready(floor_number: int) -> bool:
	"""Check if a specific floor's navigation is ready for pathfinding"""
	return floors_nav_ready.get(floor_number, false)

func are_all_floors_ready() -> bool:
	"""Check if all floors are loaded and navigation is set up"""
	return all_floors_initialized

func wait_for_all_floors_ready() -> void:
	"""
	Await this function to ensure all floors are ready before starting NPC movement.
	Usage: await FloorManager.wait_for_all_floors_ready()
	"""
	if all_floors_initialized:
		return
	await all_floors_ready

func wait_for_floor_ready(floor_number: int) -> void:
	"""
	Await this function to ensure a specific floor is ready.
	Usage: await FloorManager.wait_for_floor_ready(2)
	"""
	if is_floor_navigation_ready(floor_number):
		return
	
	# Wait for the specific floor's navigation to be ready
	while not is_floor_navigation_ready(floor_number):
		await floor_navigation_ready
		if is_floor_navigation_ready(floor_number):
			break
