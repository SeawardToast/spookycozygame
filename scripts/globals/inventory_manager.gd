extends Node

var item_definitions: Dictionary = {}  # [item_id -> Item resource]

# Slot-based inventory data
var inventory_slots: Array[Dictionary] = []  # [{item_id: int, quantity: int}]
var hotbar_slots: Array[Dictionary] = []     # [{item_id: int, quantity: int}]

const MAX_INVENTORY_SIZE: int = 25
const MAX_HOTBAR_SIZE: int = 5
const SAVE_PATH: String = "user://inventory_save.json"

var selected_item_id: int = -1
var selected_hotbar_slot_index: int = 0

signal hotbar_item_selected(item: Item)
signal inventory_intialized()
signal inventory_loaded()
signal inventory_saved()

func _ready() -> void:
	_load_item_definitions()
	_initialize_slots()

func _initialize_slots() -> void:
	inventory_slots.resize(MAX_INVENTORY_SIZE)
	hotbar_slots.resize(MAX_HOTBAR_SIZE)
	
	for i in MAX_INVENTORY_SIZE:
		inventory_slots[i] = {item_id = -1, quantity = 0}
	for i in MAX_HOTBAR_SIZE:
		hotbar_slots[i] = {item_id = -1, quantity = 0}

func _setup_starting_items() -> void:
	# slot index, item id, quantity
	set_inventory_slot(0, 2, 3)  # Palm tree
	set_inventory_slot(1, 1, 5)  # Slime potion
	set_hotbar_slot(0, 3, 3)     # Tomato seed
	set_hotbar_slot(1, 1, 5)     # Slime potion
	set_hotbar_slot(2, 4, 1)     # Watering can
	inventory_intialized.emit()

func _load_item_definitions() -> void:
	var items_path: String = "res://scenes/objects/interactable_items/"
	var dir: DirAccess = DirAccess.open(items_path)
	
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(".tres"):
				var item: Item = load(items_path + file_name)
				if item and item.id != null:
					item_definitions[item.id] = item
					print("Loaded item: ", item.display_name, " (", item.id, ")")
			file_name = dir.get_next()
		
		dir.list_dir_end()
	else:
		push_error("Failed to open items directory: " + items_path)

# --------------------------------------------
# Save/Load System
# --------------------------------------------

func save_inventory() -> bool:
	var save_data: Dictionary = {
		"inventory_slots": _slots_to_array(inventory_slots),
		"hotbar_slots": _slots_to_array(hotbar_slots),
		"selected_item_id": selected_item_id,
		"selected_hotbar_slot_index": selected_hotbar_slot_index,
		"version": "1.0"
	}
	
	var json_string: String = JSON.stringify(save_data, "\t")
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	
	if file == null:
		push_error("Failed to open save file for writing: " + SAVE_PATH)
		return false
	
	file.store_string(json_string)
	file.close()
	
	print("Inventory saved to: ", SAVE_PATH)
	inventory_saved.emit()
	return true

func load_inventory() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No save file found at: ", SAVE_PATH)
		return false
	
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	
	if file == null:
		push_error("Failed to open save file for reading: " + SAVE_PATH)
		return false
	
	var json_string: String = file.get_as_text()
	file.close()
	
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse JSON: " + json.get_error_message())
		return false
	
	var save_data: Dictionary = json.data
	
	# Validate save data structure
	if not save_data.has("inventory_slots") or not save_data.has("hotbar_slots"):
		push_error("Invalid save data structure")
		return false
	
	# Load inventory data
	_array_to_slots(save_data["inventory_slots"], inventory_slots)
	_array_to_slots(save_data["hotbar_slots"], hotbar_slots)
	
	selected_item_id = save_data.get("selected_item_id", -1)
	selected_hotbar_slot_index = save_data.get("selected_hotbar_slot_index", 0)
	
	print("Inventory loaded from: ", SAVE_PATH)
	inventory_loaded.emit()
	return true

func delete_save() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		var dir: DirAccess = DirAccess.open("user://")
		var error: Error = dir.remove(SAVE_PATH)
		if error == OK:
			print("Save file deleted: ", SAVE_PATH)
			return true
		else:
			push_error("Failed to delete save file")
			return false
	return false

func reset_inventory() -> void:
	"""Reset inventory to starting state and save"""
	_initialize_slots()
	_setup_starting_items()
	save_inventory()
	print("Inventory reset to default state")

# Helper functions for serialization
func _slots_to_array(slots: Array[Dictionary]) -> Array:
	var result: Array = []
	for slot in slots:
		result.append({
			"item_id": slot.item_id,
			"quantity": slot.quantity
		})
	return result

func _array_to_slots(data: Array, target_slots: Array[Dictionary]) -> void:
	for i in range(min(data.size(), target_slots.size())):
		target_slots[i] = {
			item_id = data[i].get("item_id", -1),
			quantity = data[i].get("quantity", 0)
		}

# --------------------------------------------
# Slot Access
# --------------------------------------------

func get_inventory_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= inventory_slots.size():
		return {item_id = -1, quantity = 0}
	return inventory_slots[slot_index]

func get_hotbar_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= hotbar_slots.size():
		return {item_id = -1, quantity = 0}
	return hotbar_slots[slot_index]

func set_inventory_slot(slot_index: int, item_id: int, quantity: int) -> void:
	if slot_index < 0 or slot_index >= inventory_slots.size():
		return
	inventory_slots[slot_index] = {item_id = item_id, quantity = quantity}

func set_hotbar_slot(slot_index: int, item_id: int, quantity: int) -> void:
	if slot_index < 0 or slot_index >= hotbar_slots.size():
		return
	hotbar_slots[slot_index] = {item_id = item_id, quantity = quantity}

func clear_inventory_slot(slot_index: int) -> void:
	set_inventory_slot(slot_index, -1, 0)

func clear_hotbar_slot(slot_index: int) -> void:
	set_hotbar_slot(slot_index, -1, 0)

# --------------------------------------------
# Item Lookup
# --------------------------------------------

func get_item(item_id: int) -> Item:
	return item_definitions.get(item_id)

func get_selected_item() -> Item:
	return get_item(selected_item_id)

# --------------------------------------------
# Selection
# --------------------------------------------

func select_item(item_id: int, hotbar_slot_index: int) -> void:
	selected_item_id = item_id
	selected_hotbar_slot_index = hotbar_slot_index
	var item: Item = get_item(item_id)
	hotbar_item_selected.emit(item if item else null)

# --------------------------------------------
# Item Addition
# --------------------------------------------

func try_add_item(item_id: int, quantity: int) -> int:
	# Try to stack with existing items in hotbar first
	var item: Item = get_item(item_id)
	for i in hotbar_slots.size():
		if hotbar_slots[i].item_id == item_id and hotbar_slots[i].quantity < item.max_stack_size:
			var new_quantity: int = min(hotbar_slots[i].quantity + quantity, item.max_stack_size)
			set_hotbar_slot(i, item_id, new_quantity)
			return i
	
	# Try to stack with existing items in inventory
	for i in inventory_slots.size():
		if inventory_slots[i].item_id == item_id and inventory_slots[i].quantity < item.max_stack_size:
			var new_quantity: int = min(inventory_slots[i].quantity + quantity, item.max_stack_size)
			set_inventory_slot(i, item_id, new_quantity)
			return i
	
	# Find first empty hotbar slot
	for i in hotbar_slots.size():
		if hotbar_slots[i].item_id == -1:
			set_hotbar_slot(i, item_id, quantity)
			return i
	
	# Find first empty inventory slot
	for i in inventory_slots.size():
		if inventory_slots[i].item_id == -1:
			set_inventory_slot(i, item_id, quantity)
			return i
	
	return -1  # Inventory full

# --------------------------------------------
# Utility Functions
# --------------------------------------------

func get_total_item_count(item_id: int) -> int:
	var total: int = 0
	for slot in inventory_slots:
		if slot.item_id == item_id:
			total += slot.quantity
	for slot in hotbar_slots:
		if slot.item_id == item_id:
			total += slot.quantity
	return total

func has_item(item_id: int, quantity: int = 1) -> bool:
	return get_total_item_count(item_id) >= quantity

func consume_item(item_id: int, quantity: int = 1) -> bool:
	var remaining: int = quantity
	
	# Consume from hotbar first
	for i in hotbar_slots.size():
		if hotbar_slots[i].item_id == item_id and remaining > 0:
			var take: int = min(remaining, hotbar_slots[i].quantity)
			hotbar_slots[i].quantity -= take
			remaining -= take
			if hotbar_slots[i].quantity <= 0:
				clear_hotbar_slot(i)
	
	# Then inventory
	for i in inventory_slots.size():
		if inventory_slots[i].item_id == item_id and remaining > 0:
			var take: int = min(remaining, inventory_slots[i].quantity)
			inventory_slots[i].quantity -= take
			remaining -= take
			if inventory_slots[i].quantity <= 0:
				clear_inventory_slot(i)
	
	return remaining == 0

func get_inventory_summary() -> String:
	var summary: String = ""
	var counted: Dictionary = {}
	
	for slot in inventory_slots + hotbar_slots:
		if slot.item_id != -1:
			if not counted.has(slot.item_id):
				counted[slot.item_id] = 0
			counted[slot.item_id] += slot.quantity
	
	for item_id: int in counted:
		var item: Item = get_item(item_id)
		if item:
			summary += "%s: %d\n" % [item.display_name, counted[item_id]]
	
	return summary

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hit"):
		var selected_item: Item = get_item(selected_item_id)
		if selected_item:
			selected_item.use()

# Auto-save on important actions
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_inventory()
