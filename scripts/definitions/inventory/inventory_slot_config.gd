# resource for normal inventory slots, you could create things like oven_slot_config as well

class_name InventorySlotConfig
extends Resource

@export var total_slots: int = 10
@export var columns: int = 5
@export var display_name: String = "Storage"


func get_slot_type(_index: int) -> SlotType.Type:
	return SlotType.Type.GENERIC

func can_slot_accept(_index: int, _item: Item) -> bool:
	return true
