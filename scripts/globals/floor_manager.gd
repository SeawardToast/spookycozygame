# =============================================
# FloorManager.gd - 2D FLOOR MANAGEMENT (REFACTORED)
# =============================================
# Global singleton for managing hotel floors in a 2D game
# Each floor has its own NavigationServer2D map for complete isolation
# Add as autoload: FloorManager

extends Node

# Store all floors
var floors: Dictionary = {}  # floor_number -> FloorData
var current_floor: int = 1
var main_scene_container: Node2D = null  # Reference to where floors are added

# REFACTORED: Each floor gets its own navigation map RID
var floor_nav_maps: Dictionary = {}  # floor_number -> RID (navigation map)
var floor_nav_regions: Dictionary = {}  # floor_number -> { tile_coords: RID }
var floors_nav_ready: Dictionary = {}  # floor_number -> bool
var all_floors_initialized: bool = false

# Signals
signal floor_changed(old_floor: int, new_floor: int)
signal floor_loaded(floor_number: int)
signal floor_unloaded(floor_number: int)
signal floor_hidden(floor_number: int)
signal floor_shown(floor_number: int)
signal floor_navigation_ready(floor_number: int, floor_node: Node)
signal all_floors_ready()


func _ready() -> void:
	_setup_hotel_floors()


func _setup_hotel_floors() -> void:
	"""Define hotel structure with scene paths"""
	register_floor(1, "res://scenes/floors/Floor1.tscn")
	register_floor(2, "res://scenes/floors/Floor2.tscn")
	#register_floor(3, "res://scenes/floors/Floor3.tscn")
	#register_floor(4, "res://scenes/floors/Floor4.tscn")
	#register_floor(5, "res://scenes/floors/Floor5.tscn")
	
	print("FloorManager: Initialized with %d floors" % floors.size())


func register_floor(floor_number: int, scene_path: String = "", autoload: bool = true) -> void:
	"""Register a floor with its scene path and create its navigation map"""
	var floor_data: FloorData = FloorData.new(floor_number, scene_path)
	floors[floor_number] = floor_data
	
	# REFACTORED: Create a dedicated navigation map for this floor
	var nav_map_rid: RID = NavigationServer2D.map_create()
	NavigationServer2D.map_set_active(nav_map_rid, true)
	NavigationServer2D.map_set_cell_size(nav_map_rid, 1.0)  # Match your tile size if needed
	floor_nav_maps[floor_number] = nav_map_rid
	
	print("FloorManager: Registered floor %d -> %s (nav map: %s)" % [floor_number, scene_path, nav_map_rid])
	
	if autoload:
		load_floor(floor_number)


func set_main_container(container: Node2D) -> void:
	"""Set the main scene container where floors will be added"""
	main_scene_container = container
	print("FloorManager: Main container set: %s" % container.name)
	
	all_floors_initialized = true
	all_floors_ready.emit()
	print("FloorManager: All floors preloaded and navigation ready!")


# =============================================
# NAVIGATION MAP MANAGEMENT (REFACTORED)
# =============================================

func get_navigation_map_for_floor(floor_number: int) -> RID:
	"""Get the navigation map RID for a specific floor"""
	if floor_nav_maps.has(floor_number):
		return floor_nav_maps[floor_number]
	
	push_error("FloorManager: No navigation map for floor %d" % floor_number)
	return RID()


func setup_floor_navigation(floor_node: Node, floor_number: int) -> void:
	"""Setup navigation for a floor by assigning all regions to the floor's dedicated map"""
	# Wait for navigation to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	
	print("Setting up navigation for floor %d..." % floor_number)
	
	var floor_map_rid: RID = get_navigation_map_for_floor(floor_number)
	if floor_map_rid == RID():
		push_error("Cannot setup navigation: no map for floor %d" % floor_number)
		return
	
	# Find all TileMapLayers in the floor
	var tilemaps: Array[TileMapLayer] = []
	_find_all_tilemaps(floor_node, tilemaps)
	
	# Initialize navigation region mapping for this floor
	floor_nav_regions[floor_number] = {}
	
	for tilemap in tilemaps:
		_assign_tilemap_regions_to_floor_map(tilemap, floor_number, floor_map_rid)
	
	# Process obstacle tilemaps to disable navigation under them
	_process_obstacle_tilemaps(floor_node, floor_number)
	
	# Force navigation map to update
	NavigationServer2D.map_force_update(floor_map_rid)
	
	# Mark this floor's navigation as ready
	floors_nav_ready[floor_number] = true
	floor_navigation_ready.emit(floor_number, floor_node)
	print("Navigation ready for floor %d (map RID: %s)" % [floor_number, floor_map_rid])
	
	debug_navigation_state(floor_number)


func _assign_tilemap_regions_to_floor_map(tilemap: TileMapLayer, floor_number: int, floor_map_rid: RID) -> void:
	"""Find navigation regions from tilemap and assign them to the floor's dedicated map"""
	# Get the world's default navigation map to find existing regions
	var world_map: RID = main_scene_container.get_world_2d().navigation_map
	var all_regions: Array[RID] = NavigationServer2D.map_get_regions(world_map)
	var used_cells: Array[Vector2i] = tilemap.get_used_cells()
	
	print("Assigning navigation for tilemap: %s on floor %d" % [tilemap.name, floor_number])
	print("Used cells: %d, Total nav regions in world: %d" % [used_cells.size(), all_regions.size()])
	
	var tile_size: float = tilemap.tile_set.tile_size.x
	var max_distance: float = tile_size * 0.6
	var assigned_count: int = 0
	
	for cell_coords: Vector2i in used_cells:
		var tile_data: TileData = tilemap.get_cell_tile_data(cell_coords)
		
		# Skip tiles without navigation polygons
		if not tile_data or not tile_data.get_navigation_polygon(0):
			continue
		
		# Get world position of this tile
		var cell_world_pos: Vector2 = tilemap.map_to_local(cell_coords)
		cell_world_pos = tilemap.to_global(cell_world_pos)
		
		# Find matching navigation region
		var matching_rid: RID = _find_nav_region_at_position(all_regions, cell_world_pos, max_distance)
		
		if matching_rid != RID():
			# REFACTORED: Assign this region to the floor's dedicated navigation map
			NavigationServer2D.region_set_map(matching_rid, floor_map_rid)
			
			# Store the mapping for later (obstacles, etc.)
			floor_nav_regions[floor_number][cell_coords] = matching_rid
			assigned_count += 1
	
	print("Assigned %d navigation regions to floor %d map" % [assigned_count, floor_number])


func _find_nav_region_at_position(regions: Array[RID], target_pos: Vector2, max_distance: float) -> RID:
	"""Find the navigation region closest to a world position"""
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


# =============================================
# OBSTACLE MANAGEMENT
# =============================================

func _process_obstacle_tilemaps(floor_node: Node, floor_number: int) -> void:
	"""Find all TileMapLayers in the 'navigation_obstacles' group and disable navigation underneath"""
	var obstacle_tilemaps: Array[Node] = []
	_find_nodes_in_group(floor_node, "navigation_obstacles", obstacle_tilemaps)
	
	print("=== OBSTACLE PROCESSING DEBUG ===")
	print("Floor %d: Found %d obstacle tilemaps" % [floor_number, obstacle_tilemaps.size()])
	
	if obstacle_tilemaps.is_empty():
		print("FloorManager: No obstacle tilemaps found in 'navigation_obstacles' group on floor %d" % floor_number)
		return
	
	for obstacle_tilemap in obstacle_tilemaps:
		if obstacle_tilemap is TileMapLayer:
			print("  Processing obstacle layer: %s" % obstacle_tilemap.name)
			_disable_navigation_under_obstacles(obstacle_tilemap, floor_number)


func _disable_navigation_under_obstacles(obstacle_tilemap: TileMapLayer, floor_number: int) -> void:
	"""Disable navigation for tiles covered by obstacles"""
	var used_cells: Array[Vector2i] = obstacle_tilemap.get_used_cells()
	
	if used_cells.is_empty():
		return
	
	if not floor_nav_regions.has(floor_number) or floor_nav_regions[floor_number].is_empty():
		push_error("No navigation regions mapped for floor %d yet!" % floor_number)
		return
	
	var successful_disables: int = 0
	
	for cell_coords: Vector2i in used_cells:
		var obstacle_local_pos: Vector2 = obstacle_tilemap.map_to_local(cell_coords)
		var obstacle_world_pos: Vector2 = obstacle_tilemap.to_global(obstacle_local_pos)
		var nav_tile_coords: Vector2i = _world_pos_to_nav_tile_direct(obstacle_world_pos, floor_number)
		
		if floor_nav_regions[floor_number].has(nav_tile_coords):
			disable_navigation_at_tile(floor_number, nav_tile_coords)
			successful_disables += 1
	
	print("  Disabled %d navigation tiles under obstacles" % successful_disables)


func _world_pos_to_nav_tile_direct(world_pos: Vector2, floor_number: int) -> Vector2i:
	"""Convert a world position to navigation tile coordinate"""
	if not floor_nav_regions.has(floor_number):
		return Vector2i(-99999, -99999)
	
	var closest_tile: Vector2i = Vector2i(-99999, -99999)
	var closest_distance: float = INF
	var search_radius: float = 32.0
	
	for nav_tile_coords: Vector2i in floor_nav_regions[floor_number].keys():
		var rid: RID = floor_nav_regions[floor_number][nav_tile_coords]
		var region_transform: Transform2D = NavigationServer2D.region_get_transform(rid)
		var region_pos: Vector2 = region_transform.origin
		
		var distance: float = region_pos.distance_to(world_pos)
		if distance < search_radius and distance < closest_distance:
			closest_distance = distance
			closest_tile = nav_tile_coords
	
	return closest_tile


func disable_navigation_at_tile(floor_number: int, tile_coords: Vector2i) -> void:
	"""Disable a specific navigation tile"""
	if not floor_nav_regions.has(floor_number):
		return
	
	if floor_nav_regions[floor_number].has(tile_coords):
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		# REFACTORED: Just disable the region - no need for layer bitmasks
		NavigationServer2D.region_set_enabled(rid, false)
		
		if tile_coords not in floors[floor_number].disabled_nav_tiles:
			floors[floor_number].disabled_nav_tiles.append(tile_coords)


func enable_navigation_at_tile(floor_number: int, tile_coords: Vector2i) -> void:
	"""Enable a specific navigation tile"""
	if not floor_nav_regions.has(floor_number):
		return
	
	if floor_nav_regions[floor_number].has(tile_coords):
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		NavigationServer2D.region_set_enabled(rid, true)
		
		if floors[floor_number].disabled_nav_tiles:
			var disabled_tiles: Array = floors[floor_number].disabled_nav_tiles
			var index: int = disabled_tiles.find(tile_coords)
			if index != -1:
				disabled_tiles.remove_at(index)


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


func refresh_floor_obstacles(floor_number: int) -> void:
	"""Reprocess all obstacle tilemaps on a floor"""
	var floor_node: Node2D = get_floor_node(floor_number)
	if not floor_node:
		return
	
	if floors[floor_number].disabled_nav_tiles:
		floors[floor_number].disabled_nav_tiles.clear()
	
	_process_obstacle_tilemaps(floor_node, floor_number)


# =============================================
# FLOOR LOADING/VISIBILITY
# =============================================

func load_floor(floor_number: int) -> Node2D:
	"""Load a floor scene and add it to the main scene tree"""
	if floor_number not in floors:
		push_error("FloorManager: Floor %d does not exist" % floor_number)
		return null

	var floor_data: FloorData = floors[floor_number]

	if floor_data.is_loaded and floor_data.floor_node:
		return floor_data.floor_node

	if not main_scene_container:
		push_error("FloorManager: No main container set! Call set_main_container() first")
		return null

	if floor_data.scene_path != "" and ResourceLoader.exists(floor_data.scene_path):
		var floor_scene: Resource = load(floor_data.scene_path)
		floor_data.floor_node = floor_scene.instantiate()
		floor_data.floor_node.name = "Floor%d" % floor_number

	main_scene_container.add_child(floor_data.floor_node)

	_setup_floor_metadata(floor_data.floor_node, floor_number)
	setup_floor_navigation(floor_data.floor_node, floor_number)
	
	floor_data.floor_node.visible = false
	_set_floor_collisions(floor_data.floor_node, false)
	floor_data.is_loaded = true
	
	emit_signal("floor_loaded", floor_number)
	print("FloorManager: Loaded floor %d" % floor_number)

	return floor_data.floor_node


func _setup_floor_metadata(floor_node: Node, floor_number: int) -> void:
	if not "floor_number" in floor_node:
		floor_node.set_meta("floor_number", floor_number)
	_tag_children_recursively(floor_node, floor_number)


func _tag_children_recursively(node: Node, floor_number: int) -> void:
	node.set_meta("floor_number", floor_number)
	for child in node.get_children():
		_tag_children_recursively(child, floor_number)


func unload_floor(floor_number: int) -> void:
	"""Unload a floor scene"""
	if floor_number not in floors:
		return
	
	var floor_data: FloorData = floors[floor_number]
	if not floor_data.is_loaded:
		return
	
	print("FloorManager: Unloading floor %d" % floor_number)
	floor_data.is_loaded = false
	emit_signal("floor_unloaded", floor_number)


func hide_floor(floor_number: int) -> void:
	"""Hide a floor while keeping it in the scene tree"""
	if floor_number not in floors:
		return
	
	var floor_data: FloorData = floors[floor_number]
	if not floor_data.is_loaded:
		return

	floor_data.floor_node.visible = false
	_set_floor_collisions(floor_data.floor_node, false)
	emit_signal("floor_hidden", floor_number)
	print("FloorManager: Hidden floor %d" % floor_number)


func show_floor(floor_number: int) -> void:
	"""Show a previously hidden floor"""
	if floor_number not in floors:
		return
	
	var floor_data: FloorData = floors[floor_number]
	if not floor_data.is_loaded:
		return
	
	floor_data.floor_node.visible = true
	_set_floor_collisions(floor_data.floor_node, true)
	emit_signal("floor_shown", floor_number)
	print("FloorManager: Shown floor %d" % floor_number)


func set_active_floor(floor_number: int, initializing: bool = false) -> void:
	"""Set which floor is currently active (visible and processing)"""
	if floor_number not in floors:
		push_error("FloorManager: Floor %d does not exist" % floor_number)
		return
	
	if current_floor == floor_number and initializing == false:
		return
	
	var old_floor: int = current_floor
	
	if old_floor in floors and floors[old_floor].is_loaded:
		var old_floor_node: Node = floors[old_floor].floor_node
		if old_floor_node:
			hide_floor(old_floor)
		floors[old_floor].is_active = false
	
	if not floors[floor_number].is_loaded:
		load_floor(floor_number)
	
	var new_floor_node: Node = floors[floor_number].floor_node
	if new_floor_node:
		show_floor(floor_number)
		
		if not floor_nav_regions.has(floor_number):
			await setup_floor_navigation(new_floor_node, floor_number)

	floors[floor_number].is_active = true
	current_floor = floor_number
	
	emit_signal("floor_changed", old_floor, floor_number)
	print("FloorManager: Active floor changed: %d -> %d" % [old_floor, floor_number])


# =============================================
# NPC CONTAINER MANAGEMENT
# =============================================

func get_floor_npc_container(floor_number: int) -> Node2D:
	"""Get or create the NPC container node for a floor"""
	var floor_node: Node2D = get_floor_node(floor_number)
	if not floor_node:
		return null
	
	# Look for existing NPC container
	var npc_container: Node2D = floor_node.get_node_or_null("NPCContainer")
	if npc_container:
		return npc_container
	
	# Create one if it doesn't exist
	npc_container = Node2D.new()
	npc_container.name = "NPCContainer"
	floor_node.add_child(npc_container)
	return npc_container


# =============================================
# COLLISION MANAGEMENT
# =============================================

func _set_floor_collisions(floor_node: Node, enabled: bool) -> void:
	for node: Node in _get_all_descendants(floor_node):
		_set_node_collision(node, enabled)


func _set_node_collision(node: Node, enabled: bool) -> void:
	if node is TileMapLayer:
		_set_tilemap_collision(node, enabled)
	elif node is CollisionObject2D:
		_set_collision_object_state(node, enabled)
	elif node is Area2D:
		node.monitoring = enabled
		node.monitorable = enabled
		_set_collision_object_state(node, enabled)


func _set_tilemap_collision(tilemap: TileMapLayer, enabled: bool) -> void:
	tilemap.collision_enabled = enabled


func _set_collision_object_state(collision_object: CollisionObject2D, enabled: bool) -> void:
	if enabled:
		if collision_object.has_meta("original_collision_layer"):
			collision_object.collision_layer = collision_object.get_meta("original_collision_layer")
			collision_object.collision_mask = collision_object.get_meta("original_collision_mask")
	else:
		if not collision_object.has_meta("original_collision_layer"):
			collision_object.set_meta("original_collision_layer", collision_object.collision_layer)
			collision_object.set_meta("original_collision_mask", collision_object.collision_mask)
		
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	
	for child in collision_object.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not enabled)


func _get_all_descendants(node: Node) -> Array:
	var descendants: Array[Node] = [node]
	for child in node.get_children():
		descendants.append_array(_get_all_descendants(child))
	return descendants


# =============================================
# UTILITY FUNCTIONS
# =============================================

func _find_all_tilemaps(node: Node, result: Array[TileMapLayer]) -> void:
	if node is TileMapLayer:
		result.append(node)
	for child in node.get_children():
		_find_all_tilemaps(child, result)


func _find_nodes_in_group(node: Node, group_name: String, result: Array[Node]) -> void:
	if node.is_in_group(group_name):
		result.append(node)
	for child in node.get_children():
		_find_nodes_in_group(child, group_name, result)


func _find_navigation_tilemaps(node: Node, result: Array[TileMapLayer]) -> void:
	if node is TileMapLayer:
		var tilemap: TileMapLayer = node
		if _tilemap_has_navigation(tilemap):
			result.append(tilemap)
	
	for child in node.get_children():
		_find_navigation_tilemaps(child, result)


func _tilemap_has_navigation(tilemap: TileMapLayer) -> bool:
	var used_cells: Array[Vector2i] = tilemap.get_used_cells()
	for cell_coords: Vector2i in used_cells:
		var tile_data: TileData = tilemap.get_cell_tile_data(cell_coords)
		if tile_data and tile_data.get_navigation_polygon(0):
			return true
	return false


# =============================================
# GETTERS
# =============================================

func get_current_floor() -> int:
	return current_floor


func get_floor_data(floor_number: int) -> FloorData:
	return floors.get(floor_number)


func get_floor_node(floor_number: int) -> Node2D:
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
	return floors.keys()


func get_loaded_floors() -> Array:
	var loaded: Array[int] = []
	for floor_num: int in floors:
		if floors[floor_num].is_loaded:
			loaded.append(floor_num)
	return loaded


func is_floor_navigation_ready(floor_number: int) -> bool:
	return floors_nav_ready.get(floor_number, false)


func are_all_floors_ready() -> bool:
	return all_floors_initialized


func wait_for_all_floors_ready() -> void:
	if all_floors_initialized:
		return
	await all_floors_ready


func wait_for_floor_ready(floor_number: int) -> void:
	if is_floor_navigation_ready(floor_number):
		return
	
	while not is_floor_navigation_ready(floor_number):
		await floor_navigation_ready
		if is_floor_navigation_ready(floor_number):
			break


# =============================================
# DEBUG
# =============================================

func debug_navigation_state(floor_number: int) -> void:
	"""Print debug info about navigation state for a floor"""
	print("=== Navigation Debug for Floor %d ===" % floor_number)
	
	if not floor_nav_maps.has(floor_number):
		print("  No navigation map created!")
		return
	
	var floor_map_rid: RID = floor_nav_maps[floor_number]
	print("  Navigation Map RID: %s" % floor_map_rid)
	print("  Map Active: %s" % NavigationServer2D.map_is_active(floor_map_rid))
	
	if not floor_nav_regions.has(floor_number):
		print("  No navigation regions mapped!")
		return
	
	var total: int = floor_nav_regions[floor_number].size()
	var enabled_count: int = 0
	var disabled_count: int = 0
	
	for tile_coords: Vector2i in floor_nav_regions[floor_number]:
		var rid: RID = floor_nav_regions[floor_number][tile_coords]
		var is_enabled: bool = NavigationServer2D.region_get_enabled(rid)
		var region_map: RID = NavigationServer2D.region_get_map(rid)
		
		if is_enabled:
			enabled_count += 1
		else:
			disabled_count += 1
		
		# Verify region is on correct map
		if region_map != floor_map_rid:
			push_warning("  Region at %s is on wrong map!" % tile_coords)
	
	print("  Total regions: %d" % total)
	print("  Enabled: %d, Disabled: %d" % [enabled_count, disabled_count])
	print("=====================================")


func debug_all_navigation_maps() -> void:
	"""Debug all floor navigation maps"""
	print("=== ALL NAVIGATION MAPS ===")
	for floor_num: int in floor_nav_maps:
		var map_rid: RID = floor_nav_maps[floor_num]
		var regions: Array[RID] = NavigationServer2D.map_get_regions(map_rid)
		print("Floor %d: Map %s, %d regions, active: %s" % [
			floor_num,
			map_rid,
			regions.size(),
			NavigationServer2D.map_is_active(map_rid)
		])
	print("===========================")
