class_name InventoryData
extends Resource

@export var inventory_id: String = ""
@export var slot_config: InventorySlotConfig = null
@export var slots: Array[Dictionary] = []

signal slot_changed(slot_index: int)


func _init(id: String = "", config: InventorySlotConfig = null) -> void:
	inventory_id = id
	slot_config = config
	if slot_config:
		_initialize_slots()


func _initialize_slots() -> void:
	slots.clear()
	slots.resize(slot_config.total_slots)
	for i in slot_config.total_slots:
		slots[i] = {item_id = -1, quantity = 0}


func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {item_id = -1, quantity = 0}
	return slots[index]


func set_slot(index: int, item_id: int, quantity: int) -> void:
	if index < 0 or index >= slots.size():
		return
	slots[index] = {item_id = item_id, quantity = quantity}
	slot_changed.emit(index)


func clear_slot(index: int) -> void:
	set_slot(index, -1, 0)


func can_accept_item(slot_index: int, item: Item) -> bool:
	if slot_config == null:
		return true
	return slot_config.can_slot_accept(slot_index, item)


func get_slot_count() -> int:
	return slots.size()


func find_empty_slot() -> int:
	for i in slots.size():
		if slots[i].item_id == -1:
			return i
	return -1


func find_stackable_slot(item_id: int, max_stack: int) -> int:
	for i in slots.size():
		var slot := slots[i]
		if slot.item_id == item_id and slot.quantity < max_stack:
			return i
	return -1


func get_item_count(item_id: int) -> int:
	var total: int = 0
	for slot in slots:
		if slot.item_id == item_id:
			total += slot.quantity
	return total


func has_item(item_id: int, quantity: int = 1) -> bool:
	return get_item_count(item_id) >= quantity


func to_dict() -> Dictionary:
	var slot_array: Array = []
	for slot in slots:
		slot_array.append({"item_id": slot.item_id, "quantity": slot.quantity})
	return {"inventory_id": inventory_id, "slots": slot_array}


func from_dict(data: Dictionary) -> void:
	if data.has("inventory_id"):
		inventory_id = data["inventory_id"]
	if data.has("slots"):
		var slot_data: Array = data["slots"]
		for i in range(mini(slot_data.size(), slots.size())):
			slots[i] = {
				item_id = slot_data[i].get("item_id", -1),
				quantity = slot_data[i].get("quantity", 0)
			}
