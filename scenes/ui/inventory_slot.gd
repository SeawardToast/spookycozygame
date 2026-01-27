extends Panel
class_name InventorySlot

var empty_background: Resource = preload("res://assets/ui/item_slot_empty_background.png")
var default_background: Resource = preload("res://assets/ui/item_slot_default_background.png")
var selected_background: Resource = preload("res://assets/ui/item_slot_selected_background.png")
var inventory_item_scene: Resource = preload("res://scenes/ui/inventory_item.tscn")

var inventory_item: InventoryItem = null
var item_id: int = -1
var item_name: String = ""
var item_quantity: int = 0

var default_style: StyleBoxTexture = null
var empty_style: StyleBoxTexture = null
var selected_style: StyleBoxTexture = null

@export var is_hotbar_slot: bool = false
@export var hotbar_index: int = -1


func _ready() -> void:
	default_style = StyleBoxTexture.new()
	default_style.texture = default_background
	
	empty_style = StyleBoxTexture.new()
	empty_style.texture = empty_background
	
	selected_style = StyleBoxTexture.new()
	selected_style.texture = selected_background
	
	_refresh_style()


func _refresh_style() -> void:
	var is_selected := is_hotbar_slot and InventoryManager.selected_hotbar_slot_index == hotbar_index
	
	if is_selected:
		set("theme_override_styles/panel", selected_style)
	elif inventory_item == null:
		set("theme_override_styles/panel", empty_style)
	else:
		set("theme_override_styles/panel", default_style)


func put_item_from_inventory(item_resource: Item, quantity: int) -> void:
	if not item_resource:
		return
	
	item_id = item_resource.id
	item_name = item_resource.display_name
	item_quantity = quantity
	
	if inventory_item == null:
		inventory_item = inventory_item_scene.instantiate()
		add_child(inventory_item)
	
	inventory_item.set_item(item_resource, item_quantity)
	_refresh_style()


func update_quantity(quantity: int) -> void:
	item_quantity = quantity
	if inventory_item != null:
		inventory_item.set_quantity(item_quantity)
		if item_quantity == 0:
			clear_slot()


func clear_slot() -> void:
	item_id = -1
	item_name = ""
	item_quantity = 0
	
	if inventory_item != null:
		inventory_item.queue_free()
		inventory_item = null
	
	_refresh_style()


func get_item_resource() -> Item:
	if item_id != -1:
		return InventoryManager.get_item(item_id)
	return null


func on_selection_changed() -> void:
	_refresh_style()
