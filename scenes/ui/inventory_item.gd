extends Node2D

class_name InventoryItem

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label

var item_reference: Item = null
var item_quantity: int = 0
# Initialize the item with an Item resource
func set_item(item_resource: Item, quantity: int = 0) -> void:
	if not item_resource:
		clear_item()
		return
	
	item_reference = item_resource
	item_quantity = quantity
	print("Setting item: ", item_resource.display_name)
	
	_update_label()
	_update_icon(item_resource)

# Update only quantity
func set_quantity(quantity: int) -> void:
	item_quantity = quantity
	_update_label()

# Clear the item
func clear_item() -> void:
	item_quantity = 0
	sprite.texture = null
	label.text = ""

# Private: update the label showing quantity
func _update_label() -> void:
	if label != null:
		label.text = str(item_quantity) if (item_quantity > 1) else ""

# Private: update the icon from Item resource
func _update_icon(item_resource: Item) -> void:
	if sprite == null:
		return
	
	if not item_resource:
		print("Setting sprite to null")
		sprite.texture = null
		return
	
	# Use the icon directly from the Item resource
	if item_resource.icon:
		sprite.texture = item_resource.icon
	else:
		# Fallback: try to load from path if icon not set in resource
		var icon_path: String = "res://assets/ui/inventory_icons/%s.png" % item_resource.display_name.to_lower().replace(" ", "_")
		if ResourceLoader.exists(icon_path):
			sprite.texture = load(icon_path)
			push_warning("Item '%s' missing icon in resource definition, loaded from fallback path" % item_resource.display_name)
		else:
			sprite.texture = null
			push_warning("Icon not found for item: %s (ID: %s)" % [item_resource.display_name, item_resource.id])
