extends Panel

var empty_background = preload("res://assets/ui/item_slot_empty_background.png")
var default_background = preload("res://assets/ui/item_slot_default_background.png")
var inventory_item_scene = preload("res://scenes/ui/inventory_item.tscn")

var item: Node2D = null
var item_name: String = ""
var item_quantity: int = 0

var default_style: StyleBoxTexture = null
var empty_style: StyleBoxTexture = null

func _ready() -> void:
	default_style = StyleBoxTexture.new()
	default_style.texture = default_background
	empty_style = StyleBoxTexture.new()
	empty_style.texture = empty_background
	_refresh_style()

# Refresh panel style depending on whether slot has an item
func _refresh_style() -> void:
	if item == null:
		set("theme_override_styles/panel", empty_style)
	else:
		set("theme_override_styles/panel", default_style)

	
func pick_from_slot() -> Node2D:
	if item == null:
		return null

	var picked_item = item
	print("item picked from slotr", item)
	if item.get_parent():
		item.get_parent().remove_child(item)
	item = null        # Slot is now empty
	item_name = ""
	item_quantity = 0
	_refresh_style()  # Update slot visuals
	print("pick from slot", picked_item)

	return picked_item


# Place an item into this slot
func put_into_slot(new_item: Node2D) -> void:
	if new_item == null:
		return
	item = new_item
	if item.get_parent():
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2.ZERO
	item_name = item.item_name
	item_quantity = item.item_quantity
	_refresh_style()

# Initialize slot with InventoryManager data
func put_item_from_inventory(name: String, quantity: int) -> void:
	item_name = name
	item_quantity = quantity

	if item == null:
		item = inventory_item_scene.instantiate()
		add_child(item)

	item.set_item(item_name, item_quantity)
	_refresh_style()

# Update quantity
func update_quantity(quantity: int) -> void:
	item_quantity = quantity
	if item != null:
		item.set_quantity(item_quantity)

# Clear this slot
func clear_slot() -> void:
	item_name = ""
	item_quantity = 0
	if item != null:
		remove_child(item)
		item.queue_free()
		item = null
	_refresh_style()
