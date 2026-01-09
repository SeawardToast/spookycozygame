extends Node2D

@onready var inventory_slots: GridContainer = $MarginContainer/MainInventoryTextureRect/MarginContainer/InventoryContainer
@onready var hotbar_slots: GridContainer = $MarginContainer/HotbarTextureRect/HotbarMarginContainer/HotbarItemMarginContainer/HotbarContainer
@onready var drag_preview_layer: Control = $DragPreview
@onready var tooltip_label: Label = $TooltipLabel
@onready var main_inventory_texture_rect: TextureRect = $MarginContainer/MainInventoryTextureRect

var holding_item: InventoryItem = null
var holding_source_slot: InventorySlot = null
var drag_ghost: TextureRect = null
var current_hotbar_index: int = 0

const INVENTORY_ITEM_SCENE = preload("res://scenes/ui/inventory_item.tscn")

func _ready() -> void:
	main_inventory_texture_rect.hide()
	tooltip_label.hide()
	
	_setup_hotbar_slots()
	_connect_all_signals()
	_render_inventory()
	_select_hotbar_slot(2)

# --------------------------------------------
# Setup & Connections
# --------------------------------------------

func _setup_hotbar_slots() -> void:
	for i: int in hotbar_slots.get_child_count():
		var slot: InventorySlot = hotbar_slots.get_child(i)
		slot.is_hotbar_slot = true
		slot.hotbar_index = i

func _connect_all_signals() -> void:
	for slot: InventorySlot in inventory_slots.get_children() + hotbar_slots.get_children():
		slot.gui_input.connect(_on_slot_gui_input.bind(slot))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited)
	
	InventoryManager.inventory_updated.connect(_on_inventory_updated)
	InventoryManager.hotbar_updated.connect(_on_hotbar_updated)

# --------------------------------------------
# Rendering
# --------------------------------------------

func _render_inventory() -> void:
	_render_slot_group(inventory_slots.get_children(), InventoryManager.inventory.keys(), false)
	_render_slot_group(hotbar_slots.get_children(), InventoryManager.hotbar.keys(), true)

func _render_slot_group(slots: Array, item_ids: Array, is_hotbar: bool) -> void:
	var index: int = 0
	
	for item_id: int in item_ids:
		if index >= slots.size():
			break
		
		var item: Item = InventoryManager.get_item(item_id)
		var quantity: int = InventoryManager.get_item_quantity(item_id, is_hotbar)
		
		if item:
			var slot: InventorySlot = slots[index]
			slot.put_item_from_inventory(item, quantity)
		index += 1
	
	# Clear remaining slots
	for i: int in range(index, slots.size()):
		var slot: InventorySlot = slots[i]
		slot.clear_slot()

func _on_inventory_updated(item: Item, quantity: int, _slot_type: String) -> void:
	_apply_item_to_slots(inventory_slots.get_children(), item, quantity)

func _on_hotbar_updated(item: Item, quantity: int, _slot_type: String) -> void:
	_apply_item_to_slots(hotbar_slots.get_children(), item, quantity)

func _apply_item_to_slots(slots: Array, item: Item, quantity: int) -> void:
	# Try to update existing slot
	for slot: InventorySlot in slots:
		if slot.item_id == item.id:
			if quantity > 0:
				slot.update_quantity(quantity)
			else:
				slot.clear_slot()
			return
	
	# Place in first empty slot
	for slot: InventorySlot in slots:
		if not slot.item_name:
			if quantity > 0:
				slot.put_item_from_inventory(item, quantity)
			return

# --------------------------------------------
# Hotbar Selection
# --------------------------------------------

func _select_hotbar_slot(index: int) -> void:
	var slots: Array = hotbar_slots.get_children()
	if index < 0 or index >= slots.size():
		return
	
	current_hotbar_index = index
	var slot: InventorySlot = slots[index]
	
	InventoryManager.select_item(slot.item_id if slot.item_id != -1 else -1, index)
	
	for hotbar_slot: InventorySlot in slots:
		hotbar_slot.on_selection_changed()

func _cycle_hotbar(direction: int) -> void:
	var slot_count: int = hotbar_slots.get_child_count()
	if slot_count == 0:
		return
	
	current_hotbar_index = (current_hotbar_index + direction + slot_count) % slot_count
	_select_hotbar_slot(current_hotbar_index)

# --------------------------------------------
# Input Handling
# --------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		main_inventory_texture_rect.visible = !main_inventory_texture_rect.visible

func _input(event: InputEvent) -> void:
	# Update drag ghost position
	if holding_item and drag_ghost:
		drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
	
	# Handle hotbar scrolling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_hotbar(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_hotbar(1)
			get_viewport().set_input_as_handled()

func _on_slot_gui_input(event: InputEvent, slot: InventorySlot) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	match mouse_event.button_index:
		MOUSE_BUTTON_LEFT:
			if holding_item:
				_handle_drop(slot)
			elif slot.inventory_item:
				_start_drag(slot)
		MOUSE_BUTTON_RIGHT:
			if holding_item:
				_handle_drop_single(slot)
			elif slot.inventory_item:
				_split_stack(slot)

# --------------------------------------------
# Drag Operations
# --------------------------------------------

func _start_drag(slot: InventorySlot) -> void:
	holding_item = slot.pick_from_slot()
	if not holding_item:
		return
	
	holding_source_slot = slot
	_create_drag_ghost(holding_item.sprite.texture)

func _split_stack(slot: InventorySlot) -> void:
	var half: int = int(slot.item_quantity / 2)
	if half <= 0:
		return
	
	# Create and initialize new item instance
	holding_item = INVENTORY_ITEM_SCENE.instantiate() as InventoryItem
	add_child(holding_item)
	holding_item.set_item(slot.inventory_item.item_reference, half)
	remove_child(holding_item)
	
	slot.update_quantity(slot.item_quantity - half)
	holding_source_slot = slot
	_create_drag_ghost(holding_item.sprite.texture)

func _create_drag_ghost(texture: Texture2D) -> void:
	drag_ghost = TextureRect.new()
	drag_ghost.texture = texture
	drag_ghost.modulate = Color(1, 1, 1, 0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2, 1.2)
	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5

func _destroy_drag_ghost() -> void:
	if drag_ghost:
		drag_ghost.queue_free()
		drag_ghost = null

# --------------------------------------------
# Drop Operations
# --------------------------------------------

func _handle_drop_single(slot: InventorySlot) -> void:
	var same_item: bool = slot.inventory_item and holding_item.item_reference.id == slot.inventory_item.item_reference.id
	
	# Place or stack item
	if not slot.inventory_item:
		slot.put_item_from_inventory(holding_item.item_reference, 1)
	elif same_item:
		slot.update_quantity(slot.item_quantity + 1)
	else:
		return  # Can't drop single on different item
	
	# Update inventory tracking
	_update_inventory_tracking(holding_source_slot, slot, 1)
	
	# Update held item
	if holding_item.item_quantity <= 1:
		_cleanup_holding()
	else:
		holding_item.set_quantity(holding_item.item_quantity - 1)

func _handle_drop(slot: InventorySlot) -> void:
	# Empty slot - simple drop
	if not slot.inventory_item:
		_drop_into_empty_slot(slot)
		return
	
	# Same item - stack
	if holding_item.item_reference.id == slot.inventory_item.item_reference.id:
		_stack_items(slot)
		return
	
	# Different items - swap
	_swap_items(slot)

func _drop_into_empty_slot(slot: InventorySlot) -> void:
	var quantity: int = holding_item.item_quantity
	slot.put_into_slot(holding_item)
	
	_update_inventory_tracking(holding_source_slot, slot, quantity)
	_cleanup_holding()
	_update_hotbar_selection_if_needed(slot)

func _stack_items(slot: InventorySlot) -> void:
	var quantity: int = holding_item.item_quantity
	slot.update_quantity(holding_item.item_quantity + slot.item_quantity)
	
	_update_inventory_tracking(holding_source_slot, slot, quantity)
	_cleanup_holding()

func _swap_items(slot: InventorySlot) -> void:
	var slot_item: InventoryItem = slot.pick_from_slot()
	var held_quantity: int = holding_item.item_quantity
	var slot_quantity: int = slot_item.item_quantity
	
	# Remove both items from their original locations
	_remove_from_inventory(holding_source_slot, holding_item.item_reference, held_quantity)
	_remove_from_inventory(slot, slot_item.item_reference, slot_quantity)
	
	# Place held item into slot
	slot.put_into_slot(holding_item)
	_add_to_inventory(slot, holding_item.item_reference, held_quantity)
	
	# Add swapped item to source location
	_add_to_inventory(holding_source_slot, slot_item.item_reference, slot_quantity)
	
	# Update holding item
	holding_item = slot_item
	_destroy_drag_ghost()
	_create_drag_ghost(holding_item.sprite.texture)
	_update_hotbar_selection_if_needed(slot)


func _update_inventory_tracking(from_slot: InventorySlot, to_slot: InventorySlot, quantity: int) -> void:
	if from_slot:
		_remove_from_inventory(from_slot, holding_item.item_reference, quantity)
	_add_to_inventory(to_slot, holding_item.item_reference, quantity)

func _remove_from_inventory(slot: InventorySlot, item: Item, quantity: int) -> void:
	if not slot:
		return
	
	if slot.is_in_group("hotbar_slot"):
		InventoryManager.remove_hotbar_item(item, quantity)
	else:
		InventoryManager.remove_inventory_item(item, quantity)

func _add_to_inventory(slot: InventorySlot, item: Item, quantity: int) -> void:
	if slot.is_in_group("hotbar_slot"):
		InventoryManager.add_hotbar_item(item, quantity)
	else:
		InventoryManager.add_inventory_item(item, quantity)

func _cleanup_holding() -> void:
	holding_item = null
	holding_source_slot = null
	_destroy_drag_ghost()

func _update_hotbar_selection_if_needed(slot: InventorySlot) -> void:
	if slot.is_hotbar_slot and slot.hotbar_index == current_hotbar_index:
		_select_hotbar_slot(current_hotbar_index)

func _on_slot_mouse_entered(slot: InventorySlot) -> void:
	if slot.inventory_item:
		tooltip_label.text = slot.item_name
		tooltip_label.show()

func _on_slot_mouse_exited() -> void:
	tooltip_label.hide()
