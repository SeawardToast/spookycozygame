extends Node

var item_definitions: Dictionary = {}  # [item_id -> Item resource]

# Slot-based inventory data
var inventory_slots: Array[Dictionary] = []  # [{item_id: int, quantity: int}]
var hotbar_slots: Array[Dictionary] = []     # [{item_id: int, quantity: int}]

const MAX_INVENTORY_SIZE: int = 25
const MAX_HOTBAR_SIZE: int = 5

var selected_item_id: int = -1
var selected_hotbar_slot_index: int = 0

signal hotbar_item_selected(item: Item)

func _ready() -> void:
	_load_item_definitions()
	_initialize_slots()
	_setup_starting_items()

func _initialize_slots() -> void:
	inventory_slots.resize(MAX_INVENTORY_SIZE)
	hotbar_slots.resize(MAX_HOTBAR_SIZE)
	
	for i in MAX_INVENTORY_SIZE:
		inventory_slots[i] = {item_id = -1, quantity = 0}
	for i in MAX_HOTBAR_SIZE:
		hotbar_slots[i] = {item_id = -1, quantity = 0}

func _setup_starting_items() -> void:
	set_inventory_slot(0, 2, 3)  # Palm tree
	set_inventory_slot(1, 1, 5)  # Slime potion
	set_hotbar_slot(0, 3, 3)     # Tomato seed
	set_hotbar_slot(1, 1, 5)     # Slime potion
	set_hotbar_slot(2, 4, 1)     # Watering can

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
	for i in hotbar_slots.size():
		if hotbar_slots[i].item_id == item_id:
			set_hotbar_slot(i, item_id, hotbar_slots[i].quantity + quantity)
			return i
	
	# Try to stack with existing items in inventory
	for i in inventory_slots.size():
		if inventory_slots[i].item_id == item_id:
			set_inventory_slot(i, item_id, inventory_slots[i].quantity + quantity)
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
