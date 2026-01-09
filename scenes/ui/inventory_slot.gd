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
	var is_selected: bool = false
	
	# Check if this hotbar slot is selected
	if is_hotbar_slot and InventoryManager.selected_hotbar_slot_index == hotbar_index:
		is_selected = true
	
	if is_hotbar_slot and is_selected:
		set("theme_override_styles/panel", selected_style)
	else:
		if inventory_item == null:
			set("theme_override_styles/panel", empty_style)
		else:
			set("theme_override_styles/panel", default_style)

func pick_from_slot() -> Node2D:
	if inventory_item == null:
		return null
	
	var picked_item: Node2D = inventory_item
	print("Item picked from slot: ", item_name)
	
	# if this is a hotbar slot and it is currently selected, select a null item for this slot when picking up item
	if is_hotbar_slot and InventoryManager.selected_hotbar_slot_index == hotbar_index:
		InventoryManager.select_item(-1, hotbar_index)
		
	
	if inventory_item.get_parent():
		inventory_item.get_parent().remove_child(inventory_item)
	
	inventory_item = null
	item_id = -1
	item_name = ""
	item_quantity = 0
	_refresh_style()
	
	return picked_item

func put_into_slot(new_item: Node2D) -> void:
	if new_item == null:
		return
	
	inventory_item = new_item
	
	if inventory_item.get_parent():
		inventory_item.get_parent().remove_child(inventory_item)
	
	add_child(inventory_item)
	inventory_item.position = Vector2.ZERO
	
	item_id = inventory_item.item_reference.id
	item_name = inventory_item.item_reference.display_name
	item_quantity = inventory_item.item_quantity
	
	_refresh_style()

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

func clear_slot() -> void:
	item_id = -1
	item_name = ""
	item_quantity = 0
	
	if inventory_item != null:
		remove_child(inventory_item)
		inventory_item.queue_free()
		inventory_item = null
	
	_refresh_style()

func get_item_resource() -> Item:
	if item_id != -1:
		return InventoryManager.get_item(item_id)
	return null

func on_selection_changed() -> void:
	_refresh_style()
