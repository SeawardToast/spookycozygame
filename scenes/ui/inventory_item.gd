extends Node2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label

var item_name: String = ""
var item_quantity: int = 0

# Initialize the item (can be empty)
func set_item(name: String = "", quantity: int = 0) -> void:
	print("Setting item", name)
	item_name = name
	item_quantity = quantity
	_update_label()
	_update_icon()

# Update only quantity
func set_quantity(quantity: int) -> void:
	item_quantity = quantity
	_update_label()

# Private: update the label showing quantity
func _update_label() -> void:
	if label != null:
		label.text = str(item_quantity) if (item_quantity > 1) else ""

# Private: update the icon
func _update_icon() -> void:
	if sprite == null:
		return

	if item_name == "":
		print("setting sprite to null")
		sprite.texture = null
		return

	var icon_path: String = "res://assets/ui/inventory_icons/%s.png" % item_name.to_lower().replace(" ", "_")
	if ResourceLoader.exists(icon_path):
		sprite.texture = load(icon_path)
	else:
		sprite.texture = null
		push_warning("Icon not found for item: %s" % item_name)
