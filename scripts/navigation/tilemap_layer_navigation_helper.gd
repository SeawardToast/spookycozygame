extends TileMapLayer
### Automatically disables navigation tiles underneath this obstacle TileMapLayer
### Attach this to any TileMapLayer that represents obstacles (fences, walls, buildings, etc.)
#
## Reference to the TileMapLayer that has navigation polygons
#@export var floor_number: int
#@export var navigation_tilemap: TileMapLayer
#
## Automatically disable navigation on ready
#@export var auto_disable_on_ready: bool = true
#
## Debug output
#@export var debug_output: bool = true
#
## Skip checking if nav tiles exist (useful if nav tiles are added dynamically)
#@export var skip_tile_existence_check: bool = false
#
## Track which tiles we've disabled so we can re-enable them if needed
#var disabled_tiles: Array[Vector2i] = []
#
#func _ready() -> void:
#
	## Fallback if no signal exists
	#await get_tree().process_frame
	#await get_tree().process_frame
	#await get_tree().physics_frame
	#FloorManager.floor_navigation_ready.connect(_on_floor_navigation_ready)
#
#
#func _on_floor_navigation_ready() -> void:
		#disable_navigation_under_all_tiles()
#
#func disable_navigation_under_all_tiles() -> void:
	#"""
	#Disables navigation for all tiles in the navigation tilemap 
	#that are covered by tiles in this obstacle tilemap.
	#"""
	#if not navigation_tilemap:
		#push_error("Navigation TileMapLayer reference not set on ", name)
		#return
	#
	#var used_cells: Array[Vector2i] = get_used_cells()
	#
	#if debug_output:
		#print("=== Obstacle TileMapLayer: ", name, " ===")
		#print("Obstacle tiles found: ", used_cells.size())
		#print("Obstacle tilemap global position: ", global_position)
		#print("Obstacle tile size: ", tile_set.tile_size if tile_set else "NO TILESET")
		#print("Navigation tilemap global position: ", navigation_tilemap.global_position)
		#print("Navigation tile size: ", navigation_tilemap.tile_set.tile_size if navigation_tilemap.tile_set else "NO TILESET")
		## Check navigation tilemap cells
		#var nav_cells: Array[Vector2i] = navigation_tilemap.get_used_cells()
		#print("Navigation tiles found: ", nav_cells.size())
#
	#disabled_tiles.clear()
	#var successful_disables: int = 0
	#var missing_nav_tiles: int = 0
	#
	#for cell_coords: Vector2i in used_cells:
		#var result: bool = disable_navigation_at_cell(cell_coords)
		#if result:
			#successful_disables += 1
		#else:
			#missing_nav_tiles += 1
	#
	#if debug_output:
		#print("Successfully disabled: ", successful_disables)
		#print("Missing nav tiles: ", missing_nav_tiles)
		#print("Total disabled tiles tracked: ", disabled_tiles.size())
		#print("=====================================")
	#
	#if missing_nav_tiles > 0 and successful_disables == 0:
		#push_warning("No navigation tiles were found under obstacles! Check tilemap alignment and tile sizes.")
#
#func disable_navigation_at_cell(cell_coords: Vector2i) -> bool:
	#"""
	#Disables navigation at a specific cell coordinate of this obstacle tilemap.
	#Converts the obstacle tile position to navigation tilemap coordinates.
	#Handles different tile sizes between obstacle and navigation tilemaps.
	#Returns true if successful, false if no navigation tile was found.
	#"""
	## Get the world position of this obstacle cell CENTER
	#var obstacle_local_pos: Vector2 = map_to_local(cell_coords)
	#var obstacle_world_pos: Vector2 = to_global(obstacle_local_pos)
	#
	## Convert to navigation tilemap coordinates
	#var nav_local_pos: Vector2 = navigation_tilemap.to_local(obstacle_world_pos)
	#var nav_tile_coords: Vector2i = navigation_tilemap.local_to_map(nav_local_pos)
	#
	#if debug_output:
		#print("  Obstacle cell ", cell_coords, " -> World ", obstacle_world_pos, " -> Nav tile ", nav_tile_coords)
	#
	## Check if we've already disabled this nav tile (multiple obstacles might overlap same nav tile)
	#if nav_tile_coords in disabled_tiles:
		#if debug_output:
			#print("    ℹ Already disabled ", nav_tile_coords)
		#return true
	#
## Try to disable navigation at that tile
## The navigation system will check if a navigation region exists at this coordinate
	#FloorManager.disable_navigation_at_tile(floor_number, nav_tile_coords)
	#disabled_tiles.append(nav_tile_coords)
	#if debug_output:
		#print("    ✓ Attempted to disable navigation at ", nav_tile_coords)
	#return true
#
#
#func enable_navigation_at_cell(cell_coords: Vector2i) -> void:
	#"""
	#Re-enables navigation at a specific cell coordinate.
	#"""
	#var obstacle_local_pos: Vector2 = map_to_local(cell_coords)
	#var obstacle_world_pos: Vector2 = to_global(obstacle_local_pos)
	#var nav_local_pos: Vector2 = navigation_tilemap.to_local(obstacle_world_pos)
	#var nav_tile_coords: Vector2i = navigation_tilemap.local_to_map(nav_local_pos)
	#
	#FloorManager.enable_navigation_at_tile(floor_number, nav_tile_coords)
	#disabled_tiles.erase(nav_tile_coords)
#
#func disable_navigation_in_area(top_left: Vector2i, bottom_right: Vector2i) -> void:
	#"""
	#Disables navigation for a rectangular area of obstacle tiles.
	#Useful when painting multiple tiles at once.
	#"""
	#for x: int in range(top_left.x, bottom_right.x + 1):
		#for y: int in range(top_left.y, bottom_right.y + 1):
			#var cell_coords: Vector2i = Vector2i(x, y)
			#if get_cell_source_id(cell_coords) != -1:  # Check if tile exists
				#disable_navigation_at_cell(cell_coords)
#
#func enable_navigation_in_area(top_left: Vector2i, bottom_right: Vector2i) -> void:
	#"""
	#Re-enables navigation for a rectangular area.
	#"""
	#for x: int in range(top_left.x, bottom_right.x + 1):
		#for y: int in range(top_left.y, bottom_right.y + 1):
			#var cell_coords: Vector2i = Vector2i(x, y)
			#enable_navigation_at_cell(cell_coords)
#
#func on_tile_placed(cell_coords: Vector2i) -> void:
	#"""
	#Call this when you place a new obstacle tile at runtime.
	#"""
	#disable_navigation_at_cell(cell_coords)
#
#func on_tile_removed(cell_coords: Vector2i) -> void:
	#"""
	#Call this when you remove an obstacle tile at runtime.
	#"""
	#enable_navigation_at_cell(cell_coords)
#
#func refresh_all_tiles() -> void:
	#"""
	#Re-enables all previously disabled tiles, then disables navigation 
	#for all current obstacle tiles. Useful if tiles have changed significantly.
	#"""
	## Re-enable all previously disabled tiles
	#for tile_coords: Vector2i in disabled_tiles:
		#FloorManager.enable_navigation_at_tile(floor_number, tile_coords)
	#
	#disabled_tiles.clear()
	#
	## Disable navigation under current obstacle tiles
	#disable_navigation_under_all_tiles()
#
## Signal connections for dynamic tile changes
#func _on_tiles_changed() -> void:
	#"""
	#Connect this to any signal that fires when tiles are modified.
	#Alternatively, call refresh_all_tiles() manually when needed.
	#"""
	#await get_tree().process_frame
	#refresh_all_tiles()
#
#func clear_all_disabled_navigation() -> void:
	#"""
	#Re-enables navigation for all tiles this obstacle layer disabled.
	#Useful when removing or hiding the entire obstacle layer.
	#"""
	#for tile_coords: Vector2i in disabled_tiles:
		#FloorManager.enable_navigation_at_tile(floor_number, tile_coords)
	#
	#disabled_tiles.clear()
	#print("Re-enabled navigation for all tiles.")
#
## Helper function to get all tiles in world rect
#func get_tiles_in_world_rect(world_rect: Rect2) -> Array[Vector2i]:
	#"""
	#Returns all obstacle tile coordinates within a world-space rectangle.
	#"""
	#var tiles: Array[Vector2i] = []
	#
	#var top_left_local: Vector2 = to_local(world_rect.position)
	#var bottom_right_local: Vector2 = to_local(world_rect.end)
	#
	#var top_left: Vector2i = local_to_map(top_left_local)
	#var bottom_right: Vector2i = local_to_map(bottom_right_local)
	#
	#for x: int in range(top_left.x, bottom_right.x + 1):
		#for y: int in range(top_left.y, bottom_right.y + 1):
			#var cell_coords: Vector2i = Vector2i(x, y)
			#if get_cell_source_id(cell_coords) != -1:
				#tiles.append(cell_coords)
	#
	#return tiles
