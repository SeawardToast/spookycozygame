# item_placement_manager.gd (add as autoload)
extends Node

signal item_placed(item: Item, position: Vector2)
signal placement_failed(reason: String)

@export var max_placement_distance: float = 100.0  # Adjust this value
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
	
	# Spawn the item at mouse position
	_spawn_item(selected_item, mouse_pos)
	
	# Remove from inventory
	InventoryManager.remove_hotbar_item(selected_item, 1)

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
	# Load and instantiate the scene from the item's scene_path
	var item_scene: PackedScene = item.placeable_scene
	if not item_scene:
		push_error("Failed to load scene")
		placement_failed.emit("Failed to load item scene")
		return
	
	var placed_item: Node2D = item_scene.instantiate()	
	placed_item.global_position = position
	get_tree().current_scene.add_child(placed_item)
	item_placed.emit(item, position)

func get_placement_valid() -> bool:
	return placement_valid

func get_preview_position() -> Vector2:
	return preview_position
