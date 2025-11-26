extends Node2D

var name_popup: AcceptDialog
var name_input: LineEdit
var pending_confirm := false
@export var tile_size: Vector2 = Vector2(16, 16)
@export var max_search_tiles: int = 5000  # safety limit
@export var zone_color: Color = Color(0.5, 0.5, 1, 0.3)
@export var zone_data_script: Script
@export var default_zone_type: String = "Room"
@export var player_node: NodePath  # assign in editor
@export var wall_tilemap: TileMapLayer  # Reference to your walls TileMap layer
@export var floor_tilemap: TileMapLayer  # Reference to your floor TileMap layer

var preview_polygon: Polygon2D
var last_tiles: Array[Vector2i] = []

func _ready():
	preview_polygon = Polygon2D.new()
	preview_polygon.color = zone_color
	preview_polygon.z_index = 100
	add_child(preview_polygon)
	name_popup = AcceptDialog.new()
	name_popup.title = "Name Zone"
	add_child(name_popup)

	name_input = LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_popup.add_child(name_input)

	name_popup.hide()
	name_popup.connect("confirmed", Callable(self, "_on_zone_name_confirmed"))


func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == Key.KEY_Z:
			_generate_preview_zone()
		elif event.keycode == Key.KEY_U:
			_reset_preview()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MouseButton.MOUSE_BUTTON_RIGHT and last_tiles.size() > 0:
			pending_confirm = true
			name_input.text = ""
			name_popup.popup_centered()
			
			
func _on_zone_name_confirmed():
	if not pending_confirm:
		return

	var zone_name = name_input.text.strip_edges()
	if zone_name == "":
		zone_name = default_zone_type

	_confirm_zone(zone_name)
	pending_confirm = false


# -----------------------------
# Generate preview zone around player
# -----------------------------
func _generate_preview_zone():
	var player = get_tree().get_nodes_in_group("player")[0]
	if player == null:
		push_warning("Player node not found!")
		return

	var start_pos = player.global_position
	last_tiles = _flood_fill_tiles(start_pos)
	if last_tiles.size() == 0:
		push_warning("No area detected!")
		_reset_preview()
		return

	var polygon_points = _tiles_to_polygon(last_tiles)
	preview_polygon.polygon = PackedVector2Array(polygon_points)

# -----------------------------
# Confirm and create ZoneData
# -----------------------------
func _confirm_zone(zone_name: String):
	if last_tiles.size() == 0:
		return

	var polygon_points = _tiles_to_polygon(last_tiles)

	# Draw polygon permanently
	preview_polygon.polygon = PackedVector2Array(polygon_points)

	# Create ZoneData
	var zone_data = zone_data_script.new()
	zone_data.zone_type = zone_name
	zone_data.color = zone_color
	zone_data.polygon = PackedVector2Array(polygon_points)
	zone_data.name = zone_name

	ZoneManager.add_zone(zone_data)
	print("Zone confirmed with ", last_tiles.size(), " tiles.")

	_reset_preview()

# -----------------------------
# Reset preview
# -----------------------------
func _reset_preview():
	last_tiles.clear()
	preview_polygon.polygon = []

# -----------------------------
# Flood fill using tiles - FIXED VERSION
# -----------------------------
func _flood_fill_tiles(start_pos: Vector2) -> Array[Vector2i]:
	var start_tile = Vector2i(floor(start_pos.x / tile_size.x), floor(start_pos.y / tile_size.y))
	var visited := {}  # Dictionary of Vector2i keys
	var queue := [start_tile]
	var result: Array[Vector2i] = []

	var space_state = get_world_2d().direct_space_state
	
	print("=== ZONE CREATION DEBUG ===")
	print("Starting from tile: ", start_tile)
	print("Starting world pos: ", start_pos)

	while queue.size() > 0:
		var tile = queue.pop_front()
		if visited.has(tile):
			continue
			
		var tile_center = Vector2(tile.x * tile_size.x + tile_size.x/2,
								  tile.y * tile_size.y + tile_size.y/2)
		
		# Check if current tile is valid (not a wall)
		var is_wall = _is_wall_at_position(tile_center)
		print("Tile ", tile, " at ", tile_center, " is_wall: ", is_wall)
		
		if is_wall:
			continue  # Skip this tile entirely
		
		visited[tile] = true
		result.append(tile)

		if result.size() > max_search_tiles:
			push_warning("Reached max search limit!")
			break

		# Check 4 neighbors
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if abs(dx) + abs(dy) != 1:
					continue
				var neighbor = Vector2i(tile.x + dx, tile.y + dy)
				if visited.has(neighbor):
					continue
				queue.append(neighbor)
	
	print("Total tiles found: ", result.size())
	print("========================")
	return result

# -----------------------------
# Check if there's a wall at position
# -----------------------------
func _is_wall_at_position(world_pos: Vector2) -> bool:
	# Method 1: Check TileMap directly (for painted tiles)
	if wall_tilemap:
		var tile_coords = wall_tilemap.local_to_map(wall_tilemap.to_local(world_pos))
		var tile_data = wall_tilemap.get_cell_tile_data(tile_coords)
		if tile_data != null:
			return true  # There's a wall tile here
	
	# Method 2: Also check for floor tiles - if no floor, it's not walkable
	if floor_tilemap:
		var tile_coords = floor_tilemap.local_to_map(floor_tilemap.to_local(world_pos))
		var tile_data = floor_tilemap.get_cell_tile_data(tile_coords)
		if tile_data == null:
			return true  # No floor tile, treat as wall/unwalkable
	
	# Method 3: Check physics collision (for scene-based walls)
	var query = PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	var results = get_world_2d().direct_space_state.intersect_point(query)
	
	for result in results:
		var collider = result.collider
		if collider.is_in_group("walls"):
			return true
		# Check if it's from a walls TileMap
		if collider is TileMapLayer and collider == wall_tilemap:
			return true
	
	return false
	
func _tiles_to_polygon(filled_tiles: Array[Vector2i], tile_size: int = 16, padding: int = 0) -> PackedVector2Array:
	# Convert to set for fast lookup
	var tile_set := {}
	for t in filled_tiles:
		tile_set[t] = true

	# Expand each tile by padding
	var expanded_tiles := []
	for t in filled_tiles:
		for dx in range(-padding, padding + 1):
			for dy in range(-padding, padding + 1):
				var nt = Vector2i(t.x + dx, t.y + dy)
				expanded_tiles.append(nt)
	tile_set.clear()
	for t in expanded_tiles:
		tile_set[t] = true

	# Each boundary edge becomes a pair of points
	var edges: Array = []

	for tile in tile_set.keys():
		var x = tile.x * tile_size
		var y = tile.y * tile_size

		# check neighbors and add exposed edges
		if not tile_set.has(tile + Vector2i(0, -1)):
			edges.append([Vector2(x, y), Vector2(x + tile_size, y)]) # top
		if not tile_set.has(tile + Vector2i(1, 0)):
			edges.append([Vector2(x + tile_size, y), Vector2(x + tile_size, y + tile_size)]) # right
		if not tile_set.has(tile + Vector2i(0, 1)):
			edges.append([Vector2(x + tile_size, y + tile_size), Vector2(x, y + tile_size)]) # bottom
		if not tile_set.has(tile + Vector2i(-1, 0)):
			edges.append([Vector2(x, y + tile_size), Vector2(x, y)]) # left

	# Convert loose edges into a continuous polygon
	var polygon: Array[Vector2] = []
	if edges.size() == 0:
		return PackedVector2Array()

	# Start with first edge
	var current = edges.pop_front()
	polygon.append(current[0])
	polygon.append(current[1])

	while edges.size() > 0:
		var last_point = polygon[polygon.size() - 1]
		var found = false

		for i in range(edges.size()):
			var e = edges[i]
			if e[0] == last_point:
				polygon.append(e[1])
				edges.remove_at(i)
				found = true
				break
			elif e[1] == last_point:
				polygon.append(e[0])
				edges.remove_at(i)
				found = true
				break

		if not found:
			break

	return PackedVector2Array(polygon)

#extends Node2D
#
#var name_popup: AcceptDialog
#var name_input: LineEdit
#var pending_confirm := false
#@export var tile_size: Vector2 = Vector2(16, 16)
#@export var max_search_tiles: int = 5000  # safety limit
#@export var zone_color: Color = Color(0.5, 0.5, 1, 0.3)
#@export var zone_data_script: Script
#@export var default_zone_type: String = "Room"
#@export var player_node: NodePath  # assign in editor
#
#var preview_polygon: Polygon2D
#var last_tiles: Array[Vector2i] = []
#
#func _ready():
	#preview_polygon = Polygon2D.new()
	#preview_polygon.color = zone_color
	#preview_polygon.z_index = 100
	#add_child(preview_polygon)
	#name_popup = AcceptDialog.new()
	#name_popup.title = "Name Zone"
	#add_child(name_popup)
#
	#name_input = LineEdit.new()
	#name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#name_popup.add_child(name_input)
#
	#name_popup.hide()
	#name_popup.connect("confirmed", Callable(self, "_on_zone_name_confirmed"))
#
#
#func _unhandled_input(event):
	#if event is InputEventKey and event.pressed:
		#if event.keycode == Key.KEY_Z:
			#_generate_preview_zone()
		#elif event.keycode == Key.KEY_U:
			#_reset_preview()
	#elif event is InputEventMouseButton and event.pressed:
		#if event.button_index == MouseButton.MOUSE_BUTTON_RIGHT and last_tiles.size() > 0:
			#pending_confirm = true
			#name_input.text = ""
			#name_popup.popup_centered()
			#
			#
#func _on_zone_name_confirmed():
	#if not pending_confirm:
		#return
#
	#var zone_name = name_input.text.strip_edges()
	#if zone_name == "":
		#zone_name = default_zone_type
#
	#_confirm_zone(zone_name)
	#pending_confirm = false
#
#
## -----------------------------
## Generate preview zone around player
## -----------------------------
#func _generate_preview_zone():
	#var player = get_tree().get_nodes_in_group("player")[0]
	#if player == null:
		#push_warning("Player node not found!")
		#return
#
	#var start_pos = player.global_position
	#last_tiles = _flood_fill_tiles(start_pos)
	#if last_tiles.size() == 0:
		#push_warning("No area detected!")
		#_reset_preview()
		#return
#
	#var polygon_points = _tiles_to_polygon(last_tiles)
	#preview_polygon.polygon = PackedVector2Array(polygon_points)
#
## -----------------------------
## Confirm and create ZoneData
## -----------------------------
#func _confirm_zone(zone_name: String):
	#if last_tiles.size() == 0:
		#return
#
	#var polygon_points = _tiles_to_polygon(last_tiles)
#
	## Draw polygon permanently
	#preview_polygon.polygon = PackedVector2Array(polygon_points)
#
	## Create ZoneData
	#var zone_data = zone_data_script.new()
	#zone_data.zone_type = zone_name
	#zone_data.color = zone_color
	#zone_data.polygon = PackedVector2Array(polygon_points)
	#zone_data.name = zone_name
#
	#ZoneManager.add_zone(zone_data)
	#print("Zone confirmed with ", last_tiles.size(), " tiles.")
#
	#_reset_preview()
#
## -----------------------------
## Reset preview
## -----------------------------
#func _reset_preview():
	#last_tiles.clear()
	#preview_polygon.polygon = []
#
## -----------------------------
## Flood fill using tiles
## -----------------------------
#func _flood_fill_tiles(start_pos: Vector2) -> Array[Vector2i]:
	#var start_tile = Vector2i(floor(start_pos.x / tile_size.x), floor(start_pos.y / tile_size.y))
	#var visited := {}  # Dictionary of Vector2i keys
	#var queue := [start_tile]
	#var result: Array[Vector2i] = []
#
	#var space_state = get_world_2d().direct_space_state
#
	#while queue.size() > 0:
		#var tile = queue.pop_front()
		#if visited.has(tile):
			#continue
		#visited[tile] = true
		#result.append(tile)
#
		#if result.size() > max_search_tiles:
			#push_warning("Reached max search limit!")
			#break
#
		## Check 4 neighbors
		#for dx in [-1, 0, 1]:
			#for dy in [-1, 0, 1]:
				#if abs(dx) + abs(dy) != 1:
					#continue
				#var neighbor = Vector2i(tile.x + dx, tile.y + dy)
				#if visited.has(neighbor):
					#continue
				#var world_pos = Vector2(neighbor.x * tile_size.x + tile_size.x/2,
						#neighbor.y * tile_size.y + tile_size.y/2)
#
				#var query = PhysicsPointQueryParameters2D.new()
				#query.position = world_pos
				#query.collide_with_bodies = true
				#query.collide_with_areas = true
#
				#var result_check = get_world_2d().direct_space_state.intersect_point(query)
				#if result_check.size() == 0:
					#queue.append(neighbor)
#
	#return result
	#
#func _tiles_to_polygon(filled_tiles: Array[Vector2i], tile_size: int = 16, padding: int = 0) -> PackedVector2Array:
	## Convert to set for fast lookup
	#var tile_set := {}
	#for t in filled_tiles:
		#tile_set[t] = true
#
	## Expand each tile by padding
	#var expanded_tiles := []
	#for t in filled_tiles:
		#for dx in range(-padding, padding + 1):
			#for dy in range(-padding, padding + 1):
				#var nt = Vector2i(t.x + dx, t.y + dy)
				#expanded_tiles.append(nt)
	#tile_set.clear()
	#for t in expanded_tiles:
		#tile_set[t] = true
#
	## Each boundary edge becomes a pair of points
	#var edges: Array = []
#
	#for tile in tile_set.keys():
		#var x = tile.x * tile_size
		#var y = tile.y * tile_size
#
		## check neighbors and add exposed edges
		#if not tile_set.has(tile + Vector2i(0, -1)):
			#edges.append([Vector2(x, y), Vector2(x + tile_size, y)]) # top
		#if not tile_set.has(tile + Vector2i(1, 0)):
			#edges.append([Vector2(x + tile_size, y), Vector2(x + tile_size, y + tile_size)]) # right
		#if not tile_set.has(tile + Vector2i(0, 1)):
			#edges.append([Vector2(x + tile_size, y + tile_size), Vector2(x, y + tile_size)]) # bottom
		#if not tile_set.has(tile + Vector2i(-1, 0)):
			#edges.append([Vector2(x, y + tile_size), Vector2(x, y)]) # left
#
	## Convert loose edges into a continuous polygon
	#var polygon: Array[Vector2] = []
	#if edges.size() == 0:
		#return PackedVector2Array()
#
	## Start with first edge
	#var current = edges.pop_front()
	#polygon.append(current[0])
	#polygon.append(current[1])
#
	#while edges.size() > 0:
		#var last_point = polygon[polygon.size() - 1]
		#var found = false
#
		#for i in range(edges.size()):
			#var e = edges[i]
			#if e[0] == last_point:
				#polygon.append(e[1])
				#edges.remove_at(i)
				#found = true
				#break
			#elif e[1] == last_point:
				#polygon.append(e[0])
				#edges.remove_at(i)
				#found = true
				#break
#
		#if not found:
			#break
#
	#return PackedVector2Array(polygon)
