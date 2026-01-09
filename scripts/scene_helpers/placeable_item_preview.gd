# placement_preview.gd (attach to a Sprite2D or similar in your UI)
extends Sprite2D

@export var valid_color: Color = Color(0, 1, 0, 0.5)  # Green
@export var invalid_color: Color = Color(1, 0, 0, 0.5)  # Red

func _process(_delta: float) -> void:
	var selected_item: Item = InventoryManager.get_selected_item()
	
	if not selected_item or not selected_item.can_be_placed():
		hide()
		return
	
	show()
	global_position = ItemPlacementManager.preview_position
	texture = selected_item.icon
	modulate = valid_color if ItemPlacementManager.placement_valid else invalid_color
