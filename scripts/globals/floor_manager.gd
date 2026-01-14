# =============================================
# FloorManager.gd - 2D FLOOR MANAGEMENT (A* Only)
# =============================================

extends Node

var floors: Dictionary = {}  # floor_number -> FloorData
var floor_astars: Dictionary = {}  # floor_number -> AStarGrid2D
var floor_tile_size: Vector2 = Vector2(16, 16)
var current_floor: int = 1
var main_scene_container: Node2D = null
var all_floors_initialized: bool = false

signal floor_changed(old_floor: int, new_floor: int)
signal floor_loaded(floor_number: int)
signal all_floors_ready()


func _ready() -> void:
	_setup_hotel_floors()


func _setup_hotel_floors() -> void:
	register_floor(1, "res://scenes/floors/Floor1.tscn")
	register_floor(2, "res://scenes/floors/Floor2.tscn")
	print("FloorManager: Initialized with %d floors" % floors.size())


# =============================================
# FLOOR REGISTRATION & LOADING
# =============================================

func register_floor(floor_number: int, scene_path: String = "") -> void:
	var floor_data: FloorData = FloorData.new(floor_number, scene_path)
	floors[floor_number] = floor_data
	print("FloorManager: Registered floor %d" % floor_number)


func set_main_container(container: Node2D) -> void:
	main_scene_container = container
	print("FloorManager: Main container set")
	await _preload_all_floors()
	all_floors_initialized = true
	all_floors_ready.emit()
	print("FloorManager: All floors ready!")


func _preload_all_floors() -> void:
	for floor_number: int in floors.keys():
		load_floor(floor_number)
		await get_tree().process_frame
	
	for floor_number: int in floors.keys():
		_build_floor_astar(floor_number)
	
	print("FloorManager: All %d floors preloaded" % floors.size())


func load_floor(floor_number: int) -> Node2D:
	if floor_number not in floors:
		push_error("FloorManager: Floor %d does not exist" % floor_number)
		return null

	var floor_data: FloorData = floors[floor_number]
	if floor_data.is_loaded and floor_data.floor_node:
		return floor_data.floor_node

	if not main_scene_container:
		push_error("FloorManager: No main container set")
		return null

	if floor_data.scene_path != "" and ResourceLoader.exists(floor_data.scene_path):
		var floor_scene: Resource = load(floor_data.scene_path)
		floor_data.floor_node = floor_scene.instantiate()
		floor_data.floor_node.name = "Floor%d" % floor_number
	else:
		floor_data.floor_node = Node2D.new()
		floor_data.floor_node.name = "Floor%d" % floor_number

	main_scene_container.add_child(floor_data.floor_node)
	_tag_floor_recursive(floor_data.floor_node, floor_number)

	floor_data.floor_node.visible = false
	floor_data.floor_node.process_mode = Node.PROCESS_MODE_DISABLED
	_set_floor_collisions(floor_data.floor_node, false)
	floor_data.is_loaded = true

	floor_loaded.emit(floor_number)
	return floor_data.floor_node


func _tag_floor_recursive(node: Node, floor_number: int) -> void:
	node.set_meta("floor_number", floor_number)
	for child in node.get_children():
		_tag_floor_recursive(child, floor_number)


# =============================================
# A* NAVIGATION
# =============================================

func _build_floor_astar(floor_number: int) -> void:
	var floor_node: Node2D = get_floor_node(floor_number)
	if not floor_node:
		return

	var nav_tilemaps: Array[TileMapLayer] = []
	_find_tilemaps_in_group(floor_node, "navigable", nav_tilemaps)
	
	if nav_tilemaps.is_empty():
		push_warning("FloorManager: No navigable tilemaps on floor %d" % floor_number)
		return

	floor_tile_size = nav_tilemaps[0].tile_set.tile_size

	var navigable_tiles: Dictionary = {}
	for tilemap: TileMapLayer in nav_tilemaps:
		for cell: Vector2i in tilemap.get_used_cells():
			navigable_tiles[cell] = tilemap

	if navigable_tiles.is_empty():
		return

	var min_coord: Vector2i = Vector2i(999999, 999999)
	var max_coord: Vector2i = Vector2i(-999999, -999999)
	for coord: Vector2i in navigable_tiles.keys():
		min_coord.x = min(min_coord.x, coord.x)
		min_coord.y = min(min_coord.y, coord.y)
		max_coord.x = max(max_coord.x, coord.x)
		max_coord.y = max(max_coord.y, coord.y)

	var astar: AStarGrid2D = AStarGrid2D.new()
	astar.region = Rect2i(min_coord, max_coord - min_coord + Vector2i.ONE)
	astar.cell_size = Vector2(floor_tile_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()

	for x in range(min_coord.x, max_coord.x + 1):
		for y in range(min_coord.y, max_coord.y + 1):
			astar.set_point_solid(Vector2i(x, y), true)

	for coord: Vector2i in navigable_tiles.keys():
		astar.set_point_solid(coord, false)

	floors[floor_number].nav_tilemap = nav_tilemaps[0]

	var obstacle_tilemaps: Array[TileMapLayer] = []
	_find_tilemaps_in_group(floor_node, "navigation_obstacles", obstacle_tilemaps)
	
	for tilemap: TileMapLayer in obstacle_tilemaps:
		for cell: Vector2i in tilemap.get_used_cells():
			if astar.region.has_point(cell):
				astar.set_point_solid(cell, true)

	floor_astars[floor_number] = astar
	print("FloorManager: Built A* for floor %d (%d navigable tiles)" % [floor_number, navigable_tiles.size()])


func _find_tilemaps_in_group(node: Node, group_name: String, result: Array[TileMapLayer]) -> void:
	if node is TileMapLayer and node.is_in_group(group_name):
		result.append(node)
	for child in node.get_children():
		_find_tilemaps_in_group(child, group_name, result)


func get_navigation_path(floor_number: int, from_world: Vector2, to_world: Vector2) -> Array[Vector2]:
	if not floor_astars.has(floor_number):
		return []

	var floor_data: FloorData = floors[floor_number]
	var tilemap: TileMapLayer = floor_data.nav_tilemap
	if not tilemap:
		return []

	var astar: AStarGrid2D = floor_astars[floor_number]
	var from_tile: Vector2i = tilemap.local_to_map(tilemap.to_local(from_world))
	var to_tile: Vector2i = tilemap.local_to_map(tilemap.to_local(to_world))

	if not astar.region.has_point(from_tile) or not astar.region.has_point(to_tile):
		return []

	if astar.is_point_solid(from_tile) or astar.is_point_solid(to_tile):
		return []

	var tile_path: Array[Vector2i] = astar.get_id_path(from_tile, to_tile)
	
	var world_path: Array[Vector2] = []
	for tile: Vector2i in tile_path:
		var local_pos: Vector2 = tilemap.map_to_local(tile)
		world_path.append(tilemap.to_global(local_pos))

	return world_path


# =============================================
# RUNTIME OBSTACLE MANAGEMENT
# =============================================

func set_obstacle(floor_number: int, world_pos: Vector2, blocked: bool) -> void:
	if not floor_astars.has(floor_number):
		return

	var tilemap: TileMapLayer = floors[floor_number].nav_tilemap
	if not tilemap:
		return

	var tile: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
	var astar: AStarGrid2D = floor_astars[floor_number]
	
	if astar.region.has_point(tile):
		astar.set_point_solid(tile, blocked)


func set_obstacle_tile(floor_number: int, tile_coord: Vector2i, blocked: bool) -> void:
	if not floor_astars.has(floor_number):
		return

	var astar: AStarGrid2D = floor_astars[floor_number]
	if astar.region.has_point(tile_coord):
		astar.set_point_solid(tile_coord, blocked)


func rebuild_floor_astar(floor_number: int) -> void:
	_build_floor_astar(floor_number)


# =============================================
# FLOOR SWITCHING
# =============================================

func set_active_floor(floor_number: int, force: bool = false) -> void:
	if floor_number not in floors:
		push_error("FloorManager: Floor %d does not exist" % floor_number)
		return

	# Skip if already active (unless forced for initial setup)
	if current_floor == floor_number and floors[floor_number].is_active and not force:
		return

	var old_floor: int = current_floor

	# Disable old floor (only if different and loaded)
	if old_floor != floor_number and old_floor in floors and floors[old_floor].is_loaded:
		var old_node: Node2D = floors[old_floor].floor_node
		if old_node:
			old_node.visible = false
			old_node.process_mode = Node.PROCESS_MODE_DISABLED
			_set_floor_collisions(old_node, false)
		floors[old_floor].is_active = false

	# Enable new floor
	if not floors[floor_number].is_loaded:
		load_floor(floor_number)

	var new_node: Node2D = floors[floor_number].floor_node
	if new_node:
		new_node.visible = true
		new_node.process_mode = Node.PROCESS_MODE_INHERIT
		_set_floor_collisions(new_node, true)

	floors[floor_number].is_active = true
	current_floor = floor_number

	# Sync NPCs on this floor
	if NPCSimulationManager:
		NPCSimulationManager.sync_all_npcs_on_floor(floor_number)

	floor_changed.emit(old_floor, floor_number)
	print("FloorManager: Floor %d -> %d" % [old_floor, floor_number])


func _set_floor_collisions(floor_node: Node, enabled: bool) -> void:
	for node: Node in _get_all_descendants(floor_node):
		if node is TileMapLayer:
			node.collision_enabled = enabled
		elif node is CollisionObject2D or node is Area2D:
			_set_collision_object(node, enabled)


func _set_collision_object(obj: CollisionObject2D, enabled: bool) -> void:
	if enabled:
		if obj.has_meta("original_collision_layer"):
			obj.collision_layer = obj.get_meta("original_collision_layer")
			obj.collision_mask = obj.get_meta("original_collision_mask")
	else:
		if not obj.has_meta("original_collision_layer"):
			obj.set_meta("original_collision_layer", obj.collision_layer)
			obj.set_meta("original_collision_mask", obj.collision_mask)
		obj.collision_layer = 0
		obj.collision_mask = 0

	for child in obj.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not enabled)


func _get_all_descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_get_all_descendants(child))
	return result


# =============================================
# GETTERS
# =============================================

func get_current_floor() -> int:
	return current_floor


func get_floor_node(floor_number: int) -> Node2D:
	if floor_number in floors:
		return floors[floor_number].floor_node
	return null


func get_floor_npc_container(floor_number: int) -> Node2D:
	var floor_node: Node2D = get_floor_node(floor_number)
	if not floor_node:
		return null

	if floor_node.has_node("NPCs"):
		return floor_node.get_node("NPCs")
	if floor_node.has_node("NPCContainer"):
		return floor_node.get_node("NPCContainer")

	return floor_node


func is_floor_loaded(floor_number: int) -> bool:
	return floor_number in floors and floors[floor_number].is_loaded


func is_floor_navigation_ready(floor_number: int) -> bool:
	return floor_astars.has(floor_number)


func are_all_floors_ready() -> bool:
	return all_floors_initialized


func wait_for_all_floors_ready() -> void:
	if all_floors_initialized:
		return
	await all_floors_ready


func wait_for_floor_ready(floor_number: int) -> void:
	while not is_floor_navigation_ready(floor_number):
		await get_tree().process_frame


func get_all_floors() -> Array:
	return floors.keys()
