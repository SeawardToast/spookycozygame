class_name CollectableComponent
extends Area2D

@export var item_id: int
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _on_body_entered(body: Node2D) -> void:
	var item: Item = InventoryManager.get_item(item_id)
	if item == null:
		print("Unable to find item with item ID ", item_id)
		return
		
	if body is Player:
		# Try to add item to inventory
		var slot_index: bool = InventoryManager.try_add_item_to_player(item_id, 1)
		
		if slot_index == false:
			print("Inventory full! Cannot pick up ", item.display_name)
			return
		
		# Item was successfully added
		print("Collected ", item.display_name)
		
		# Emit signal for any other systems that need to know
		SignalBus.item_picked_up.emit(item, 1)
		
		# Remove the item from the world
		get_parent().queue_free()
