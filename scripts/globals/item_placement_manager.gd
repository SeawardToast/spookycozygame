# item_placement_manager.gd (add as autoload)
extends Node

signal item_placed(item: Item, position: Vector2)
signal placement_failed(reason: String)

@export var max_placement_distance: float = 100.0
@export var show_placement_preview: bool = true

var placement_valid: bool = false
var preview_position: Vector2 = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("hit"):
		_try_place_selected_item()

func _process(_delta: float) -> void:
	if show_placement_preview:
		_update_placement_preview()

func _try_place_selected_item() -> void:
	var selected_item: Item = InventoryManager.get_selected_item()
	
	if not selected_item or not selected_item.can_be_placed():
		placement_failed.emit("Item cannot be placed")
		return
	
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if not player:
		placement_failed.emit("Player not found")
		return
	
	var mouse_pos: Vector2 = player.get_global_mouse_position()
	var player_pos: Vector2 = player.global_position
	
	# Check if mouse is within placement range
	var distance: float = player_pos.distance_to(mouse_pos)
	if distance > max_placement_distance:
		placement_failed.emit("Too far from player")
		return
	
	# Check if player has the item in their hotbar
	var hotbar_slot_index: int = InventoryManager.selected_hotbar_slot_index
	var slot_data: Dictionary = InventoryManager.get_hotbar_slot(hotbar_slot_index)
	
	if slot_data.item_id != selected_item.id or slot_data.quantity <= 0:
		placement_failed.emit("Item not in selected hotbar slot")
		return
	
	# Remove one from the selected hotbar slot FIRST
	var new_quantity: int = slot_data.quantity - 1
	if new_quantity > 0:
		InventoryManager.set_hotbar_slot(hotbar_slot_index, selected_item.id, new_quantity)
	else:
		InventoryManager.clear_hotbar_slot(hotbar_slot_index)
		# Deselect the item since slot is now empty
		InventoryManager.select_item(-1, hotbar_slot_index)
	
	# Then spawn the item at mouse position
	_spawn_item(selected_item, mouse_pos)

func _update_placement_preview() -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if not player:
		placement_valid = false
		return
	
	var selected_item: Item = InventoryManager.get_selected_item()
	
	if not selected_item or not selected_item.can_be_placed():
		placement_valid = false
		return
	
	var mouse_pos: Vector2 = player.get_global_mouse_position()
	var player_pos: Vector2 = player.global_position
	var distance: float = player_pos.distance_to(mouse_pos)
	
	preview_position = mouse_pos
	placement_valid = distance <= max_placement_distance

func _spawn_item(item: Item, position: Vector2) -> void:
	var item_scene: PackedScene = item.placeable_scene
	if not item_scene:
		push_error("Failed to load scene for item: ", item.display_name)
		placement_failed.emit("Failed to load item scene")
		return
	
	var placed_item: Node2D = item_scene.instantiate()
	placed_item.global_position = position
	
	var floor_node: Node2D = FloorManager.get_floor_node(FloorManager.current_floor)
	if floor_node:
		floor_node.add_child(placed_item)
		item_placed.emit(item, position)
	else:
		push_error("Failed to find floor node")
		placement_failed.emit("Failed to find floor node")
		placed_item.queue_free()

func get_placement_valid() -> bool:
	return placement_valid

func get_preview_position() -> Vector2:
	return preview_position
