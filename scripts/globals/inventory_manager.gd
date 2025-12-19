extends Node

var inventory: Dictionary = {}
var hotbar: Dictionary = {}

signal inventory_updated(item_name: String, quantity: int)
signal hotbar_updated(item_name: String, quantity: int)

func _ready() -> void:
	# Example starting items for testing
	if inventory.size() == 0:
		add_inventory_item("Palm Tree", 3)
		add_inventory_item("Slime Potion", 5)
		add_hotbar_item("Slime Potion", 5)

func add_inventory_item(item_name: String, quantity: int = 1) -> void:
	if inventory.has(item_name):
		inventory[item_name] += quantity
	else:
		inventory[item_name] = quantity
		print("Inventory updated: ", inventory)
		print("Hotbar: ", hotbar)
	inventory_updated.emit(item_name, inventory[item_name])

func remove_inventory_item(item_name: String, quantity: int = 1) -> void:
	if not inventory.has(item_name):
		return
	inventory[item_name] -= quantity
	if inventory[item_name] <= 0:
		inventory[item_name] = 0
	print("Inventory updated: ", inventory)
	print("Hotbar: ", hotbar)
	inventory_updated.emit(item_name, inventory[item_name])
	
func add_hotbar_item(item_name: String, quantity: int = 1) -> void:
	if hotbar.has(item_name):
		hotbar[item_name] += quantity
	else:
		hotbar[item_name] = quantity
	print("Inventory updated: ", inventory)
	print("Hotbar: ", hotbar)
	hotbar_updated.emit(item_name, hotbar[item_name])

func remove_hotbar_item(item_name: String, quantity: int = 1) -> void:
	if not hotbar.has(item_name):
		return
	hotbar[item_name] -= quantity
	if hotbar[item_name] <= 0:
		hotbar[item_name] = 0
	print("Inventory updated: ", inventory)
	print("Hotbar: ", hotbar)
	hotbar_updated.emit(item_name, hotbar[item_name])
