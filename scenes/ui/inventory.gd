extends Node2D
@onready var inventory_slots: GridContainer = $MarginContainer/MainInventoryTextureRect/MarginContainer/InventoryContainer
@onready var hotbar_slots: GridContainer = $MarginContainer/HotbarTextureRect/HotbarMarginContainer/HotbarItemMarginContainer/HotbarContainer
@onready var drag_preview_layer: Control = $DragPreview
@onready var tooltip_label: Label = $TooltipLabel
@onready var main_inventory_texture_rect: TextureRect = $MarginContainer/MainInventoryTextureRect

var holding_item: Variant = null          # The actual item node in hand
var holding_quantity: int = 0            # Quantity held
var holding_source_slot: Variant = null  # Slot node
var drag_ghost: TextureRect = null

var item_data: Variant = JsonDataManager.load_data("res://resources/data/item_data.json")


func _ready() -> void:
	main_inventory_texture_rect.hide()
	tooltip_label.hide()
	_connect_slot_signals()
	_connect_inventory_manager()
	_render_inventory()
	set_process_input(true)

# --------------------------------------------
# Slot / Inventory Connections
# --------------------------------------------

func _connect_slot_signals() -> void:
	for slot: Variant in inventory_slots.get_children():
		slot.gui_input.connect(_on_slot_gui_input.bind(slot))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))
	
	for slot: Variant in hotbar_slots.get_children():
		slot.gui_input.connect(_on_slot_gui_input.bind(slot))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))


func _connect_inventory_manager() -> void:
	if InventoryManager.has_signal("inventory_updated"):
		InventoryManager.connect("inventory_updated", Callable(self, "_on_inventory_updated"))
		
	if InventoryManager.has_signal("hotbar_updated"):
		InventoryManager.connect("hotbar_updated", Callable(self, "_on_hotbar_updated"))


# --------------------------------------------
# Render Initial Inventory
# --------------------------------------------

func _render_inventory() -> void:
	var inventory_items: Array = InventoryManager.inventory.keys()
	var hotbar_items: Array = InventoryManager.hotbar.keys()
	var inventory_slots_array: Array = inventory_slots.get_children()
	var hotbar_slots_array: Array = hotbar_slots.get_children()

	var index := 0

	# Fill inventory slots first
	index = _render_slots(inventory_slots_array, inventory_items, index)

	# Continue filling hotbar slots
	_render_slots(hotbar_slots_array, hotbar_items, index)
		
func _render_slots(slots: Array, item_ids: Array, start_index: int) -> int:
	var index := start_index
	
	for item_id: int in item_ids:
		if index >= slots.size():
			break
		
		# Get the Item resource from InventoryManager
		var item: Item = InventoryManager.get_item(item_id)
		var quantity: int = InventoryManager.inventory[item_id]
		
		if item:
			slots[index].put_item_from_inventory(item, quantity)
		index += 1
	
	# Clear remaining slots
	for i in range(index, slots.size()):
		slots[i].clear_slot()
	
	return index


# --------------------------------------------
# On Inventory Update
# --------------------------------------------

func _on_inventory_updated(item_name: String, quantity: int, slot_type: String) -> void:
	apply_item_to_slots(inventory_slots.get_children(), item_name, quantity)
	
	
func _on_hotbar_updated(item_name: String, quantity: int, slot_type: String) -> void:
	apply_item_to_slots(hotbar_slots.get_children(), item_name, quantity)
			
func apply_item_to_slots(slots: Array, item_name: String, quantity: int) -> void:
	# First: try to update existing item
	for slot: Variant in slots:
		if slot.item_name == item_name:
			if quantity > 0:
				slot.update_quantity(quantity)
			else:
				slot.clear_slot()
			return

	# Second: try to put item into empty slot
	for slot: Variant in slots:
		if slot.item_name == "" or slot.item_name == null:
			if quantity > 0:
				slot.put_item_from_inventory(item_name, quantity)
			return


# --------------------------------------------
# Toggle Inventory
# --------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		main_inventory_texture_rect.visible = !main_inventory_texture_rect.visible


# --------------------------------------------
# Drag + Drop Handlers
# --------------------------------------------

func _on_slot_gui_input(event: InputEvent, slot: Variant) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.is_key_pressed(KEY_SHIFT):
				_shift_quick_move(slot)
				return

			if holding_item:
				_handle_drop(slot)
			elif slot.item:
				_start_drag(slot)


func _start_drag(slot: Variant) -> void:
	holding_item = slot.pick_from_slot()
	if not holding_item:
		return

	holding_source_slot = slot
	holding_quantity = holding_item.item_quantity

	drag_ghost = TextureRect.new()
	drag_ghost.texture = holding_item.sprite.texture
	drag_ghost.modulate = Color(1, 1, 1, 0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2, 1.2)

	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5


func _start_drag_from_swap(slot: Variant, item: Variant) -> void:
	if not item:
		return

	holding_source_slot = slot
	holding_quantity = item.item_quantity

	drag_ghost = TextureRect.new()
	drag_ghost.texture = item.sprite.texture
	drag_ghost.modulate = Color(1, 1, 1, 0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2, 1.2)

	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5


func _handle_drop(slot: Variant) -> void:
	if not slot.item:
		slot.put_into_slot(holding_item)
		
		# manage distinct hotbar and inventory dictionaries in inventory manager 
		if slot.is_in_group("hotbar_slot"):
			InventoryManager.add_hotbar_item(holding_item.item_reference)
			InventoryManager.remove_inventory_item(holding_item.item_reference)

			
		holding_item = null
		holding_source_slot = null
		holding_quantity = 0
		_destroy_drag_ghost()
		return

	var held_prev: Variant = holding_item
	var slot_item: Variant = slot.pick_from_slot()


	slot.put_into_slot(holding_item)
	
		# remove item from hotbar if you swapped with it
	if slot.is_in_group("hotbar_slot"):
		InventoryManager.remove_hotbar_item(slot_item.item_name)
		InventoryManager.add_hotbar_item(holding_item.item_name)

		
	holding_item = slot_item
	holding_quantity = holding_item.item_quantity

	_destroy_drag_ghost()
	_start_drag_from_swap(slot, holding_item)


func _split_stack(slot: Variant) -> void:
	var half: int = int(slot.item_quantity / 2)
	if half <= 0:
		return

	holding_item = slot.item
	holding_quantity = half
	slot.update_quantity(slot.item_quantity - half)

	drag_ghost = TextureRect.new()
	drag_ghost.texture = holding_item.sprite.texture
	drag_ghost.modulate = Color(1, 1, 1, 0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2, 1.2)

	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5


func _destroy_drag_ghost() -> void:
	if drag_ghost:
		drag_ghost.queue_free()
		drag_ghost = null


func _shift_quick_move(slot: Variant) -> void:
	if not slot.item:
		return

	var item_name: String = slot.item_name
	var qty: int = slot.item_quantity

	for target: Variant in inventory_slots.get_children():
		if target == slot:
			continue
		if target.item_name == "" or target.item_name == null:
			target.put_item_from_inventory(item_name, qty)
			slot.clear_slot()
			return


# --------------------------------------------
# Tooltip Handling
# --------------------------------------------

func _on_slot_mouse_entered(slot: Variant) -> void:
	if slot.item:
		tooltip_label.text = slot.item_name
		tooltip_label.show()


func _on_slot_mouse_exited(slot: Variant) -> void:
	tooltip_label.hide()


# --------------------------------------------
# Drag Ghost Movement
# --------------------------------------------

func _input(event: InputEvent) -> void:
	if holding_item and drag_ghost:
		drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
