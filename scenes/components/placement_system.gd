# PlacementSystem.gd
# Handles piece selection, ghost preview, placement, and deletion in build mode
# Add as child of BuildModeManager or as standalone node
extends Node2D

signal placement_succeeded(piece_id: String, grid_pos: Vector2i)
signal placement_failed(reason: String)
signal piece_deleted(grid_pos: Vector2i)
signal selection_changed(piece_id: String)

# Grid settings (should match LayoutData)
@export var cell_size: int = 16
@export var camera_pan_speed: float = 300.0
@export var camera_pan_edge_margin: float = 50.0  # For edge-of-screen panning

# Current selection state
var selected_piece_id: String = ""
var current_rotation: int = 0  # 0-3, each step is 90 degrees clockwise
var is_active: bool = false

# Ghost preview
var ghost_instance: Node2D = null
var ghost_valid: bool = false
var current_grid_pos: Vector2i = Vector2i.ZERO

# Visual feedback
var valid_color: Color = Color(0.2, 1.0, 0.2, 0.5)  # Green, semi-transparent
var invalid_color: Color = Color(1.0, 0.2, 0.2, 0.5)  # Red, semi-transparent

# Camera reference for panning
var camera: Camera2D = null

func _ready() -> void:
	# Register with BuildModeManager
	BuildModeManager.register_placement_system(self)
	
	# Get camera reference
	if GameManager.camera:
		camera = GameManager.camera
	else:
		GameManager.game_initialized.connect(_on_game_initialized)
	
	set_process(false)
	set_process_unhandled_input(false)


func _on_game_initialized() -> void:
	camera = GameManager.camera


func set_active(active: bool) -> void:
	is_active = active
	set_process(active)
	set_process_unhandled_input(active)
	
	if not active:
		_clear_ghost()
		selected_piece_id = ""
	
	print("PlacementSystem: Active = %s" % active)


func _process(delta: float) -> void:
	if not is_active:
		return
	
	_handle_camera_pan(delta)
	_update_ghost_position()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	
	# Rotate piece
	if event.is_action_pressed("build_rotate_cw"):
		_rotate_piece(1)
	elif event.is_action_pressed("build_rotate_ccw"):
		_rotate_piece(-1)
	
	# Place piece
	if event.is_action_pressed("build_place"):
		_try_place_piece()
	
	# Delete piece / cancel selection
	if event.is_action_pressed("build_cancel"):
		if selected_piece_id != "":
			# Cancel current selection
			select_piece("")
		else:
			# Try to delete piece under cursor
			_try_delete_piece()
	
	# Direct delete (right-click on existing piece)
	if event.is_action_pressed("build_delete"):
		_try_delete_piece()


# =============================================
# PIECE SELECTION
# =============================================

func select_piece(piece_id: String) -> void:
	"""Select a piece type to place"""
	if piece_id == selected_piece_id:
		return
	
	selected_piece_id = piece_id
	current_rotation = 0
	
	_clear_ghost()
	
	if piece_id != "":
		_create_ghost()
	
	selection_changed.emit(piece_id)
	print("PlacementSystem: Selected piece: %s" % piece_id)


func _rotate_piece(direction: int) -> void:
	"""Rotate the selected piece (direction: 1 for CW, -1 for CCW)"""
	if selected_piece_id == "":
		return
	
	current_rotation = (current_rotation + direction) % 4
	if current_rotation < 0:
		current_rotation += 4
	
	if ghost_instance:
		ghost_instance.rotation_degrees = current_rotation * 90
		_update_ghost_validity()
	
	print("PlacementSystem: Rotation = %d" % current_rotation)


# =============================================
# GHOST PREVIEW
# =============================================

func _create_ghost() -> void:
	"""Create a ghost preview of the selected piece"""
	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(selected_piece_id)
	if not piece_data:
		return
	
	var scene: PackedScene = load(piece_data.scene_path)
	if not scene:
		push_error("PlacementSystem: Failed to load scene: %s" % piece_data.scene_path)
		return
	
	ghost_instance = scene.instantiate()
	ghost_instance.rotation_degrees = current_rotation * 90
	
	# Make it a ghost (semi-transparent, no collision)
	_apply_ghost_material(ghost_instance)
	_disable_ghost_collision(ghost_instance)
	
	add_child(ghost_instance)
	_update_ghost_position()


func _clear_ghost() -> void:
	"""Remove the ghost preview"""
	if ghost_instance:
		ghost_instance.queue_free()
		ghost_instance = null
	ghost_valid = false


func _update_ghost_position() -> void:
	"""Update ghost position to follow mouse, snapped to grid"""
	if not ghost_instance:
		return
	
	var mouse_pos: Vector2 = get_global_mouse_position()
	current_grid_pos = BuildingLayoutData.world_to_grid(mouse_pos)
	var snapped_pos: Vector2 = BuildingLayoutData.grid_to_world(current_grid_pos)
	
	ghost_instance.global_position = snapped_pos
	_update_ghost_validity()


func _update_ghost_validity() -> void:
	"""Update ghost color based on placement validity"""
	if not ghost_instance:
		return
	
	ghost_valid = BuildingLayoutData.can_place_at(selected_piece_id, current_grid_pos, current_rotation)
	
	var color: Color = valid_color if ghost_valid else invalid_color
	_set_ghost_color(ghost_instance, color)


func _apply_ghost_material(node: Node) -> void:
	"""Make a node and its children semi-transparent"""
	if node is Sprite2D:
		node.modulate = valid_color
	elif node is TileMapLayer:
		node.modulate = valid_color
	
	for child in node.get_children():
		_apply_ghost_material(child)

func _set_ghost_color(node: Node, color: Color) -> void:
	"""Set the modulate color for ghost visualization"""
	if node is Sprite2D:
		node.modulate = color
	elif node is TileMapLayer:
		node.modulate = color
	elif node is CanvasItem:
		node.modulate = color
	
	for child in node.get_children():
		_set_ghost_color(child, color)


func _disable_ghost_collision(node: Node) -> void:
	"""Disable all collision on the ghost"""
	if node is CollisionObject2D:
		node.collision_layer = 0
		node.collision_mask = 0
	
	if node is CollisionShape2D or node is CollisionPolygon2D:
		node.disabled = true
	
	if node is TileMapLayer:
		node.collision_enabled = false
	
	for child in node.get_children():
		_disable_ghost_collision(child)


# =============================================
# PLACEMENT
# =============================================

func _try_place_piece() -> void:
	"""Attempt to place the selected piece at the current position"""
	if selected_piece_id == "":
		placement_failed.emit("No piece selected")
		return
	
	if not ghost_valid:
		placement_failed.emit("Invalid placement position")
		return
	
	var piece_data: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(selected_piece_id)
	if not piece_data:
		placement_failed.emit("Unknown piece")
		return
	
	# Load and instantiate the actual piece
	var scene: PackedScene = load(piece_data.scene_path)
	if not scene:
		placement_failed.emit("Failed to load piece scene")
		return
	
	var instance: Node2D = scene.instantiate()
	instance.position = BuildingLayoutData.grid_to_world(current_grid_pos)
	instance.rotation_degrees = current_rotation * 90
	
	# Add to the current floor
	var floor_node: Node2D = FloorManager.get_floor_node(FloorManager.current_floor)
	if not floor_node:
		placement_failed.emit("No floor node found")
		instance.queue_free()
		return
	
	# TODO
	# Get or create a container for placed pieces
	#var pieces_container: Node2D = floor_node.get_node_or_null("PlacedPieces")
	#if not pieces_container:
		#pieces_container = Node2D.new()
		#pieces_container.name = "PlacedPieces"
		#floor_node.add_child(pieces_container)
	
	floor_node.add_child(instance)
	
	# Register with LayoutData
	if BuildingLayoutData.place_piece(selected_piece_id, current_grid_pos, current_rotation, instance):
		placement_succeeded.emit(selected_piece_id, current_grid_pos)
		BuildModeManager.piece_placed.emit(selected_piece_id, current_grid_pos, current_rotation)
		
		# TODO: Update navigation if the piece has a NavigationRegion2D
		# FloorManager.refresh_floor_obstacles(FloorManager.current_floor)
	else:
		instance.queue_free()
		placement_failed.emit("LayoutData rejected placement")


func _try_delete_piece() -> void:
	"""Try to delete the piece under the cursor"""
	var mouse_pos: Vector2 = get_global_mouse_position()
	var grid_pos: Vector2i = BuildingLayoutData.world_to_grid(mouse_pos)
	
	if BuildingLayoutData.remove_piece(grid_pos):
		piece_deleted.emit(grid_pos)
		BuildModeManager.piece_removed.emit(grid_pos)
		print("PlacementSystem: Deleted piece at %s" % grid_pos)
	else:
		print("PlacementSystem: No piece to delete at %s" % grid_pos)


# =============================================
# CAMERA PANNING
# =============================================

func _handle_camera_pan(delta: float) -> void:
	"""Handle camera panning via WASD or edge-of-screen"""
	if not camera:
		return
	
	var pan_direction: Vector2 = Vector2.ZERO
	
	# WASD panning
	if Input.is_action_pressed("walk_up"):
		pan_direction.y -= 1
	if Input.is_action_pressed("walk_down"):
		pan_direction.y += 1
	if Input.is_action_pressed("walk_left"):
		pan_direction.x -= 1
	if Input.is_action_pressed("walk_right"):
		pan_direction.x += 1
	
	# Edge-of-screen panning (optional)
	#var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	#var viewport_size: Vector2 = get_viewport_rect().size
	#
	#if mouse_pos.x < camera_pan_edge_margin:
	#	pan_direction.x -= 1
	#elif mouse_pos.x > viewport_size.x - camera_pan_edge_margin:
	#	pan_direction.x += 1
	#
	#if mouse_pos.y < camera_pan_edge_margin:
	#	pan_direction.y -= 1
	#elif mouse_pos.y > viewport_size.y - camera_pan_edge_margin:
	#	pan_direction.y += 1
	
	if pan_direction != Vector2.ZERO:
		pan_direction = pan_direction.normalized()
		camera.global_position += pan_direction * camera_pan_speed * delta


# =============================================
# UTILITY
# =============================================

func get_current_grid_position() -> Vector2i:
	return current_grid_pos


func get_selected_piece() -> String:
	return selected_piece_id


func is_placement_valid() -> bool:
	return ghost_valid
