extends Node

# Item definitions - loaded once and referenced everywhere
var item_definitions: Dictionary = {}  # [item_id -> Item resource]

# Actual inventory data - just quantities
var inventory: Dictionary = {}  # [item_id -> quantity]
var hotbar: Dictionary = {}     # [item_id -> quantity]

var selected_item_id: int = -1
var selected_hotbar_slot_index: int = 0

signal hotbar_item_selected(item: Item)
signal inventory_updated(item: Item, quantity: int)
signal hotbar_updated(item: Item, quantity: int)

func _ready() -> void:
	_load_item_definitions()
	
	# Example starting items
	if inventory.size() == 0:
		var palm_tree: Item = get_item(2) # get by item id
		var slime_potion: Item = get_item(1)
		var tomato_seed: Item = get_item(3)
		var watering_can: Item = get_item(4)
		
		add_inventory_item(palm_tree, 3)
		add_inventory_item(slime_potion, 5)
		add_hotbar_item(tomato_seed, 3)
		add_hotbar_item(slime_potion, 5)
		add_hotbar_item(watering_can, 1)

func _load_item_definitions() -> void:
	# Automatically load all .tres files from items folder
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

func get_item(item_id: int) -> Item:
	var item: Item = item_definitions.get(item_id)
	return item

func get_item_quantity(item_id: int, in_hotbar: bool = false) -> int:
	var target: Dictionary = hotbar if in_hotbar else inventory
	return target.get(item_id, 0)

func has_item(item_id: int, quantity: int = 1, in_hotbar: bool = false) -> bool:
	return get_item_quantity(item_id, in_hotbar) >= quantity

# --------------------------------------------
# Selection
# --------------------------------------------

func select_item(item_id: int, hotbar_slot_index: int) -> void:
	selected_item_id = item_id
	selected_hotbar_slot_index = hotbar_slot_index
	var item: Item = get_item(item_id)
	
	if item:
		hotbar_item_selected.emit(item)
	else:
		hotbar_item_selected.emit(null)

func get_selected_item() -> Item:
	return get_item(selected_item_id)

# --------------------------------------------
# Inventory Operations
# --------------------------------------------

func add_inventory_item(item: Item, quantity: int = 1) -> void:
	if not item:
		return
	
	if inventory.has(item.id):
		inventory[item.id] += quantity
	else:
		inventory[item.id] = quantity
	
	print("Inventory updated: ", inventory)
	print("Hotbar: ", hotbar)
	inventory_updated.emit(item, inventory[item.id])

func remove_inventory_item(item: Item, quantity: int = 1) -> bool:
	if not item or not inventory.has(item.id):
		return false
	
	inventory[item.id] -= quantity
	
	if inventory[item.id] <= 0:
		inventory.erase(item.id)
		inventory_updated.emit(item, 0)
	else:
		inventory_updated.emit(item, inventory[item.id])
	
	print("Inventory updated: ", inventory)
	print("Hotbar: ", hotbar)
	return true

# --------------------------------------------
# Hotbar Operations
# --------------------------------------------

func add_hotbar_item(item: Item, quantity: int = 1) -> void:
	if not item:
		return
	
	if hotbar.has(item.id):
		hotbar[item.id] += quantity
	else:
		hotbar[item.id] = quantity
	
	print("Inventory updated: ", inventory)
	print("Hotbar: ", hotbar)
	hotbar_updated.emit(item, hotbar[item.id])

func remove_hotbar_item(item: Item, quantity: int = 1) -> bool:
	if not item or not hotbar.has(item.id):
		return false
	
	hotbar[item.id] -= quantity
	
	if hotbar[item.id] <= 0:
		hotbar.erase(item.id)
		hotbar_updated.emit(item, 0)
	else:
		hotbar_updated.emit(item, hotbar[item.id])
	
	print("Inventory updated: ", inventory)
	print("Hotbar: ", hotbar)
	return true

func remove_item(item: Item, quantity: int = 1) -> bool:
	"""Remove item from hotbar first, then inventory if not found in hotbar"""
	if not item:
		return false
	
	# Try hotbar first
	if hotbar.has(item.id):
		return remove_hotbar_item(item, quantity)
	# Fall back to inventory
	elif inventory.has(item.id):
		return remove_inventory_item(item, quantity)
	
	return false

# --------------------------------------------
# Utility Functions
# --------------------------------------------

func get_inventory_summary() -> String:
	var summary: String = ""
	for item_id: int in inventory:
		var item: Item = get_item(item_id)
		if item:
			summary += "%s: %d\n" % [item.display_name, inventory[item_id]]
	return summary
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hit"):
		var selected_item: Item = item_definitions.get(selected_item_id)
		if selected_item == null:
			return
		selected_item.use()
