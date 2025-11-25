extends Node

var inventory: Dictionary = {}
signal inventory_updated(item_name: String, quantity: int)

func _ready() -> void:
	# Example starting items for testing
	if inventory.size() == 0:
		add_item("Palm Tree", 3)
		add_item("Slime Potion", 5)

func add_item(item_name: String, quantity: int = 1) -> void:
	if inventory.has(item_name):
		inventory[item_name] += quantity
	else:
		inventory[item_name] = quantity
	inventory_updated.emit(item_name, inventory[item_name])

func remove_item(item_name: String, quantity: int = 1) -> void:
	if not inventory.has(item_name):
		return
	inventory[item_name] -= quantity
	if inventory[item_name] <= 0:
		inventory[item_name] = 0
	inventory_updated.emit(item_name, inventory[item_name])
