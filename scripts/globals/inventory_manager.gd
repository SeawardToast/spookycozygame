extends Node

var item_definitions: Dictionary = {}  # {item_id: Item}
var inventories: Dictionary = {}  # {inventory_id: InventoryData}

var player_inventory: InventoryData = null
var player_hotbar: InventoryData = null

var selected_hotbar_slot_index: int = 0

signal inventories_loaded()
signal inventories_saved()
signal hotbar_item_selected(item: Item)
signal inventory_registered(inventory_id: String)
signal inventory_unregistered(inventory_id: String)
const SAVE_PATH: String = "user://inventories.json"


func _ready() -> void:
	_load_item_definitions()
	_setup_player_inventories()

func _load_item_definitions() -> void:
	var items_path: String = "res://scenes/objects/interactable_items/"
	var dir: DirAccess = DirAccess.open(items_path)
	
	if not dir:
		push_error("Failed to open items directory: " + items_path)
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".tres"):
			var item: Item = load(items_path + file_name)
			if item and item.id != null:
				item_definitions[item.id] = item
		file_name = dir.get_next()
	
	dir.list_dir_end()


func _setup_player_inventories() -> void:
	var main_config := InventorySlotConfig.new()
	main_config.total_slots = 25
	main_config.columns = 5
	main_config.display_name = "Inventory"
	player_inventory = create_inventory("player_main", main_config)
	
	var hotbar_config := InventorySlotConfig.new()
	hotbar_config.total_slots = 5
	hotbar_config.columns = 5
	hotbar_config.display_name = "Hotbar"
	player_hotbar = create_inventory("player_hotbar", hotbar_config)
	
	# Starting items
	player_inventory.set_slot(0, 2, 3)
	player_inventory.set_slot(1, 1, 5)
	player_hotbar.set_slot(0, 3, 3)
	player_hotbar.set_slot(1, 1, 5)
	player_hotbar.set_slot(2, 4, 1)


# --------------------------------------------
# Registry
# --------------------------------------------

func create_inventory(id: String, config: InventorySlotConfig) -> InventoryData:
	var inventory := InventoryData.new(id, config)
	register_inventory(inventory)
	return inventory


func register_inventory(inventory: InventoryData) -> void:
	inventories[inventory.inventory_id] = inventory
	inventory_registered.emit(inventory.inventory_id)


func unregister_inventory(inventory_id: String) -> void:
	inventories.erase(inventory_id)
	inventory_unregistered.emit(inventory_id)


func get_inventory(inventory_id: String) -> InventoryData:
	return inventories.get(inventory_id)


# --------------------------------------------
# Item Lookup
# --------------------------------------------

func get_item(item_id: int) -> Item:
	return item_definitions.get(item_id)

# --------------------------------------------
# Hotbar Selection
# --------------------------------------------

func select_hotbar_slot(index: int) -> void:
	if index < 0 or index >= player_hotbar.get_slot_count():
		return
	selected_hotbar_slot_index = index
	var slot: Dictionary = player_hotbar.get_slot(index)
	var item: Item = get_item(slot.item_id) if slot.item_id != -1 else null
	hotbar_item_selected.emit(item)


func get_selected_item() -> Item:
	var slot: Dictionary = player_hotbar.get_slot(selected_hotbar_slot_index)
	return get_item(slot.item_id) if slot.item_id != -1 else null

# --------------------------------------------
# Transfer Operations
# --------------------------------------------

func transfer_item(from_id: String, from_slot: int, to_id: String, to_slot: int, quantity: int) -> bool:
	var from_inv: InventoryData = get_inventory(from_id)
	var to_inv: InventoryData = get_inventory(to_id)
	
	if from_inv == null or to_inv == null:
		return false
	
	var from_data: Dictionary = from_inv.get_slot(from_slot)
	if from_data.item_id == -1 or from_data.quantity < quantity:
		return false
	
	var item: Item = get_item(from_data.item_id)
	if not to_inv.can_accept_item(to_slot, item):
		return false
	
	var to_data: Dictionary = to_inv.get_slot(to_slot)
	
	if to_data.item_id == -1:
		to_inv.set_slot(to_slot, from_data.item_id, quantity)
		_reduce_slot(from_inv, from_slot, quantity)
		return true
	
	if to_data.item_id == from_data.item_id:
		var space: int = item.max_stack_size - to_data.quantity
		var to_transfer: int = mini(quantity, space)
		if to_transfer > 0:
			to_inv.set_slot(to_slot, to_data.item_id, to_data.quantity + to_transfer)
			_reduce_slot(from_inv, from_slot, to_transfer)
			return true
	
	return false


func quick_transfer(from_id: String, from_slot: int, to_id: String) -> bool:
	var from_inv := get_inventory(from_id)
	var to_inv := get_inventory(to_id)
	
	if from_inv == null or to_inv == null:
		return false
	
	var from_data := from_inv.get_slot(from_slot)
	if from_data.item_id == -1:
		return false
	
	var item := get_item(from_data.item_id)
	var remaining: int = from_data.quantity
	
	# Stack with existing
	for i in to_inv.get_slot_count():
		if remaining <= 0:
			break
		if not to_inv.can_accept_item(i, item):
			continue
		var to_data := to_inv.get_slot(i)
		if to_data.item_id == from_data.item_id:
			var space: int = item.max_stack_size - to_data.quantity
			var to_transfer := mini(remaining, space)
			if to_transfer > 0:
				to_inv.set_slot(i, to_data.item_id, to_data.quantity + to_transfer)
				remaining -= to_transfer
	
	# Fill empty slots
	for i in to_inv.get_slot_count():
		if remaining <= 0:
			break
		if not to_inv.can_accept_item(i, item):
			continue
		var to_data := to_inv.get_slot(i)
		if to_data.item_id == -1:
			var to_transfer := mini(remaining, item.max_stack_size)
			to_inv.set_slot(i, from_data.item_id, to_transfer)
			remaining -= to_transfer
	
	var transferred: int = from_data.quantity - remaining
	if transferred > 0:
		_reduce_slot(from_inv, from_slot, transferred)
		return true
	
	return false


func swap_items(inv1_id: String, slot1: int, inv2_id: String, slot2: int) -> bool:
	var inv1 := get_inventory(inv1_id)
	var inv2 := get_inventory(inv2_id)
	
	if inv1 == null or inv2 == null:
		return false
	
	var data1 := inv1.get_slot(slot1)
	var data2 := inv2.get_slot(slot2)
	
	var item1 := get_item(data1.item_id) if data1.item_id != -1 else null
	var item2 := get_item(data2.item_id) if data2.item_id != -1 else null
	
	if item1 and not inv2.can_accept_item(slot2, item1):
		return false
	if item2 and not inv1.can_accept_item(slot1, item2):
		return false
	
	inv1.set_slot(slot1, data2.item_id, data2.quantity)
	inv2.set_slot(slot2, data1.item_id, data1.quantity)
	return true


func _reduce_slot(inventory: InventoryData, slot: int, amount: int) -> void:
	var data: Dictionary = inventory.get_slot(slot)
	var new_quantity: int = data.quantity - amount
	if new_quantity <= 0:
		inventory.clear_slot(slot)
	else:
		inventory.set_slot(slot, data.item_id, new_quantity)


# --------------------------------------------
# Player Item Management
# --------------------------------------------

func try_add_item_to_player(item_id: int, quantity: int) -> bool:
	var item: Item = get_item(item_id)
	if item == null:
		return false
	
	var remaining: int = quantity
	
	# Try hotbar first
	remaining = _add_to_inventory(player_hotbar, item_id, remaining, item.max_stack_size)
	if remaining > 0:
		remaining = _add_to_inventory(player_inventory, item_id, remaining, item.max_stack_size)
	
	return remaining < quantity


func _add_to_inventory(inv: InventoryData, item_id: int, quantity: int, max_stack: int) -> int:
	var remaining := quantity
	
	# Stack first
	for i in inv.get_slot_count():
		if remaining <= 0:
			break
		var slot := inv.get_slot(i)
		if slot.item_id == item_id and slot.quantity < max_stack:
			var space: int = max_stack - slot.quantity
			var to_add: int = mini(remaining, space)
			inv.set_slot(i, item_id, slot.quantity + to_add)
			remaining -= to_add
	
	# Empty slots
	for i in inv.get_slot_count():
		if remaining <= 0:
			break
		var slot := inv.get_slot(i)
		if slot.item_id == -1:
			var to_add := mini(remaining, max_stack)
			inv.set_slot(i, item_id, to_add)
			remaining -= to_add
	
	return remaining


func consume_player_item(item_id: int, quantity: int = 1) -> bool:
	var total: int = player_inventory.get_item_count(item_id) + player_hotbar.get_item_count(item_id)
	if total < quantity:
		return false
	
	var remaining: int = quantity
	
	for inv: InventoryData in [player_hotbar, player_inventory]:
		for i in inv.get_slot_count():
			if remaining <= 0:
				break
			var slot := inv.get_slot(i)
			if slot.item_id == item_id:
				var take := mini(remaining, slot.quantity)
				_reduce_slot(inv, i, take)
				remaining -= take
	
	return true


# --------------------------------------------
# Save / Load
# --------------------------------------------

func save_all() -> bool:
	var save_data: Dictionary = {
		"selected_hotbar_slot_index": selected_hotbar_slot_index,
		"inventories": {}
	}
	
	for inventory_id: String in inventories:
		var inventory: InventoryData = inventories[inventory_id]
		save_data["inventories"][inventory_id] = inventory.to_dict()
	
	var json_string := JSON.stringify(save_data, "\t")
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	
	if not file:
		push_error("Failed to open save file: " + SAVE_PATH)
		return false
	
	file.store_string(json_string)
	file.close()
	
	inventories_saved.emit()
	return true


func load_all() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to open save file: " + SAVE_PATH)
		return false
	
	var json_string := file.get_as_text()
	file.close()
	
	var json: JSON = JSON.new()
	if json.parse(json_string) != OK:
		push_error("Failed to parse save file: " + json.get_error_message())
		return false
	
	var save_data: Dictionary = json.data
	
	selected_hotbar_slot_index = save_data.get("selected_hotbar_slot_index", 0)
	
	var saved_inventories: Dictionary = save_data.get("inventories", {})
	for inventory_id: String in saved_inventories:
		var inventory: InventoryData = get_inventory(inventory_id)
		if inventory:
			inventory.from_dict(saved_inventories[inventory_id])
	
	inventories_loaded.emit()
	return true


func save_inventory(inventory_id: String) -> bool:
	var inventory: InventoryData = get_inventory(inventory_id)
	if not inventory:
		return false
	
	var path: String = "user://inventory_%s.json" % inventory_id
	var json_string: String= JSON.stringify(inventory.to_dict(), "\t")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	
	if not file:
		push_error("Failed to save inventory: " + inventory_id)
		return false
	
	file.store_string(json_string)
	file.close()
	return true


func load_inventory(inventory_id: String) -> bool:
	var inventory: InventoryData = get_inventory(inventory_id)
	if not inventory:
		return false
	
	var path: String = "user://inventory_%s.json" % inventory_id
	if not FileAccess.file_exists(path):
		return false
	
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	
	var json_string: String = file.get_as_text()
	file.close()
	
	var json: JSON = JSON.new()
	if json.parse(json_string) != OK:
		return false
	
	inventory.from_dict(json.data)
	return true


func delete_save() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_all()

# --------------------------------------------
# Input
# --------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hit"):
		var item := get_selected_item()
		if item:
			item.use()
