extends Node2D

@onready var inventory_slots: GridContainer = $MarginContainer/MainInventoryTextureRect/MarginContainer/InventoryContainer
@onready var hotbar_slots: GridContainer = $MarginContainer/HotbarTextureRect/HotbarMarginContainer/HotbarItemMarginContainer/HotbarContainer
@onready var drag_preview_layer: Control = $DragPreview
@onready var tooltip_label: Label = $TooltipLabel
@onready var main_inventory_texture_rect: TextureRect = $MarginContainer/MainInventoryTextureRect

var holding_item: InventoryItem = null
var holding_source_slot_index: int = -1
var holding_from_hotbar: bool = false
var drag_ghost: TextureRect = null
var drag_ghost_label: Label = null
var current_hotbar_index: int = 0

const INVENTORY_ITEM_SCENE = preload("res://scenes/ui/inventory_item.tscn")

func _ready() -> void:
	main_inventory_texture_rect.hide()
	tooltip_label.hide()
	_setup_slots()
	_render_all_slots()
	_select_hotbar_slot(2)
	
	# Connect to item placement to update UI
	ItemPlacementManager.item_placed.connect(_on_item_placed)
	
	# Connect to world item pickups to update UI
	SignalBus.item_picked_up.connect(_on_item_picked_up)

# --------------------------------------------
# Setup
# --------------------------------------------

func _setup_slots() -> void:
	# Setup hotbar slot properties
	for i in hotbar_slots.get_child_count():
		var slot: InventorySlot = hotbar_slots.get_child(i)
		slot.is_hotbar_slot = true
		slot.hotbar_index = i
	
	# Connect all slot signals
	for slot in inventory_slots.get_children() + hotbar_slots.get_children():
		slot.gui_input.connect(_on_slot_gui_input.bind(slot))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited)

# --------------------------------------------
# Rendering
# --------------------------------------------

func _render_all_slots() -> void:
	# Render inventory slots
	for i in inventory_slots.get_child_count():
		var slot: InventorySlot = inventory_slots.get_child(i)
		var slot_data: Dictionary = InventoryManager.get_inventory_slot(i)
		_render_slot(slot, slot_data)
	
	# Render hotbar slots
	for i in hotbar_slots.get_child_count():
		var slot: InventorySlot = hotbar_slots.get_child(i)
		var slot_data: Dictionary = InventoryManager.get_hotbar_slot(i)
		_render_slot(slot, slot_data)

func _render_slot(slot: InventorySlot, slot_data: Dictionary) -> void:
	if slot_data.item_id == -1 or slot_data.quantity <= 0:
		slot.clear_slot()
	else:
		var item: Item = InventoryManager.get_item(slot_data.item_id)
		if item:
			slot.put_item_from_inventory(item, slot_data.quantity)

# --------------------------------------------
# Hotbar Selection
# --------------------------------------------

func _select_hotbar_slot(index: int) -> void:
	var slots := hotbar_slots.get_children()
	if index < 0 or index >= slots.size():
		return
	
	current_hotbar_index = index
	var slot: InventorySlot = slots[index]
	
	InventoryManager.select_item(slot.item_id if slot.item_id != -1 else -1, index)
	
	for hotbar_slot: InventorySlot in slots:
		hotbar_slot.on_selection_changed()

func _cycle_hotbar(direction: int) -> void:
	var slot_count := hotbar_slots.get_child_count()
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
	if holding_item and drag_ghost:
		drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_hotbar(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_hotbar(1)
			get_viewport().set_input_as_handled()

func _on_slot_gui_input(event: InputEvent, slot: InventorySlot) -> void:
	if not event is InputEventMouseButton or not event.pressed or not main_inventory_texture_rect.visible:
		return
	
	var mouse_event := event as InputEventMouseButton
	var slot_index := _get_slot_index(slot)
	
	match mouse_event.button_index:
		MOUSE_BUTTON_LEFT:
			if holding_item:
				_handle_drop(slot, slot_index)
			elif slot.inventory_item:
				_start_drag(slot, slot_index)
		MOUSE_BUTTON_RIGHT:
			if holding_item:
				_handle_drop_single(slot, slot_index)
			elif slot.inventory_item:
				_split_stack(slot, slot_index)

func _get_slot_index(slot: InventorySlot) -> int:
	if slot.is_in_group("hotbar_slot"):
		return hotbar_slots.get_children().find(slot)
	else:
		return inventory_slots.get_children().find(slot)

# --------------------------------------------
# Drag Operations
# --------------------------------------------

func _start_drag(slot: InventorySlot, slot_index: int) -> void:
	holding_item = slot.pick_from_slot()
	if not holding_item:
		return
	
	holding_source_slot_index = slot_index
	holding_from_hotbar = slot.is_in_group("hotbar_slot")
	
	# Clear the source slot
	if holding_from_hotbar:
		InventoryManager.clear_hotbar_slot(slot_index)
	else:
		InventoryManager.clear_inventory_slot(slot_index)
	
	_create_drag_ghost(holding_item.sprite.texture)

func _split_stack(slot: InventorySlot, slot_index: int) -> void:
	var half := int(slot.item_quantity / 2)
	if half <= 0:
		return
	
	holding_item = INVENTORY_ITEM_SCENE.instantiate() as InventoryItem
	add_child(holding_item)
	holding_item.set_item(slot.inventory_item.item_reference, half)
	remove_child(holding_item)
	
	holding_source_slot_index = slot_index
	holding_from_hotbar = slot.is_in_group("hotbar_slot")
	
	var new_quantity := slot.item_quantity - half
	slot.update_quantity(new_quantity)
	
	if holding_from_hotbar:
		InventoryManager.set_hotbar_slot(slot_index, slot.item_id, new_quantity)
	else:
		InventoryManager.set_inventory_slot(slot_index, slot.item_id, new_quantity)
	
	_create_drag_ghost(holding_item.sprite.texture)

func _create_drag_ghost(texture: Texture2D) -> void:
	drag_ghost = TextureRect.new()
	drag_ghost.texture = texture
	drag_ghost.modulate = Color(1, 1, 1, 0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2, 1.2)
	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
	
	# Add quantity label if holding more than 1 item
	if holding_item and holding_item.item_quantity > 1:
		drag_ghost_label = Label.new()
		drag_ghost_label.text = str(holding_item.item_quantity)
		drag_ghost_label.add_theme_font_size_override("font_size", 14)
		drag_ghost_label.add_theme_color_override("font_color", Color.WHITE)
		drag_ghost_label.add_theme_color_override("font_outline_color", Color.BLACK)
		drag_ghost_label.add_theme_constant_override("outline_size", 2)
		drag_ghost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		drag_ghost_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		drag_ghost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_ghost_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		drag_ghost.add_child(drag_ghost_label)

func _update_drag_ghost_label() -> void:
	if drag_ghost_label and holding_item:
		if holding_item.item_quantity > 1:
			drag_ghost_label.text = str(holding_item.item_quantity)
			drag_ghost_label.show()
		else:
			drag_ghost_label.hide()

func _destroy_drag_ghost() -> void:
	if drag_ghost:
		drag_ghost.queue_free()
		drag_ghost = null
		drag_ghost_label = null

func _handle_drop_single(slot: InventorySlot, slot_index: int) -> void:
	var is_hotbar := slot.is_in_group("hotbar_slot")
	var same_item := slot.inventory_item and holding_item.item_reference.id == slot.item_id
	
	if slot.inventory_item and not same_item:
		return
	
	# Check max stack size
	var max_stack := holding_item.item_reference.max_stack_size
	if slot.inventory_item and slot.item_quantity >= max_stack:
		return  # Stack is already full
	
	var new_quantity := 1 if not slot.inventory_item else slot.item_quantity + 1
	
	if not slot.inventory_item:
		slot.put_item_from_inventory(holding_item.item_reference, 1)
	else:
		slot.update_quantity(new_quantity)
	
	if is_hotbar:
		InventoryManager.set_hotbar_slot(slot_index, holding_item.item_reference.id, new_quantity)
	else:
		InventoryManager.set_inventory_slot(slot_index, holding_item.item_reference.id, new_quantity)
	
	if holding_item.item_quantity <= 1:
		_cleanup_holding()
	else:
		holding_item.set_quantity(holding_item.item_quantity - 1)
		_update_drag_ghost_label()

func _handle_drop(slot: InventorySlot, slot_index: int) -> void:
	var is_hotbar := slot.is_in_group("hotbar_slot")
	
	# Empty slot - simple drop (with max stack consideration)
	if not slot.inventory_item:
		var max_stack := holding_item.item_reference.max_stack_size
		var amount_to_place: int = min(holding_item.item_quantity, max_stack)
		var leftover: int = holding_item.item_quantity - amount_to_place
		
		# Create new item for the slot with the amount we're placing
		var item_for_slot: InventoryItem = INVENTORY_ITEM_SCENE.instantiate() as InventoryItem
		add_child(item_for_slot)
		item_for_slot.set_item(holding_item.item_reference, amount_to_place)
		remove_child(item_for_slot)
		
		slot.put_into_slot(item_for_slot)
		if is_hotbar:
			InventoryManager.set_hotbar_slot(slot_index, holding_item.item_reference.id, amount_to_place)
		else:
			InventoryManager.set_inventory_slot(slot_index, holding_item.item_reference.id, amount_to_place)
		
		if leftover > 0:
			# Keep holding the leftover
			holding_item.set_quantity(leftover)
			_update_drag_ghost_label()
		else:
			_cleanup_holding()
		
		if is_hotbar and slot_index == current_hotbar_index:
			_select_hotbar_slot(current_hotbar_index)
		return
	
	# Same item - stack with max stack size consideration
	if holding_item.item_reference.id == slot.item_id:
		var max_stack := holding_item.item_reference.max_stack_size
		var space_available := max_stack - slot.item_quantity
		
		if space_available <= 0:
			return  # Stack is already full, can't add more
		
		var amount_to_add: int = min(holding_item.item_quantity, space_available)
		var new_quantity: int = slot.item_quantity + amount_to_add
		var leftover: int = holding_item.item_quantity - amount_to_add
		
		slot.update_quantity(new_quantity)
		
		if is_hotbar:
			InventoryManager.set_hotbar_slot(slot_index, slot.item_id, new_quantity)
		else:
			InventoryManager.set_inventory_slot(slot_index, slot.item_id, new_quantity)
		
		if leftover > 0:
			# Keep holding the leftover
			holding_item.set_quantity(leftover)
			_update_drag_ghost_label()
		else:
			_cleanup_holding()
		return
	
	# Different items - swap
	var slot_item := slot.pick_from_slot()
	var held_item_id := holding_item.item_reference.id
	var held_quantity := holding_item.item_quantity
	
	# Place held item in target slot
	slot.put_into_slot(holding_item)
	if is_hotbar:
		InventoryManager.set_hotbar_slot(slot_index, held_item_id, held_quantity)
	else:
		InventoryManager.set_inventory_slot(slot_index, held_item_id, held_quantity)
	
	# Put slot item back in source location
	if holding_from_hotbar:
		InventoryManager.set_hotbar_slot(holding_source_slot_index, slot_item.item_reference.id, slot_item.item_quantity)
	else:
		InventoryManager.set_inventory_slot(holding_source_slot_index, slot_item.item_reference.id, slot_item.item_quantity)
	
	# Update holding item for continued drag
	holding_item = slot_item
	holding_source_slot_index = slot_index
	holding_from_hotbar = is_hotbar
	_destroy_drag_ghost()
	_create_drag_ghost(holding_item.sprite.texture)
	
	# Re-render source slot to show swapped item
	_render_all_slots()
	
	if is_hotbar and slot_index == current_hotbar_index:
		_select_hotbar_slot(current_hotbar_index)

func _cleanup_holding() -> void:
	holding_item = null
	holding_source_slot_index = -1
	holding_from_hotbar = false
	_destroy_drag_ghost()

# --------------------------------------------
# Tooltip
# --------------------------------------------

func _on_slot_mouse_entered(slot: InventorySlot) -> void:
	if slot.inventory_item and main_inventory_texture_rect.visible:
		tooltip_label.text = slot.item_name
		tooltip_label.show()

func _on_slot_mouse_exited() -> void:
	tooltip_label.hide()

# --------------------------------------------
# Item Placement Handler
# --------------------------------------------

func _on_item_placed(item: Item, position: Vector2) -> void:
	# Re-render the selected hotbar slot
	var slot_index: int = InventoryManager.selected_hotbar_slot_index
	if slot_index >= 0 and slot_index < hotbar_slots.get_child_count():
		var slot: InventorySlot = hotbar_slots.get_child(slot_index)
		var slot_data: Dictionary = InventoryManager.get_hotbar_slot(slot_index)
		_render_slot(slot, slot_data)

func _on_item_picked_up(item: Item, quantity: int) -> void:
	# Re-render all slots since we don't know which one was updated
	_render_all_slots()
