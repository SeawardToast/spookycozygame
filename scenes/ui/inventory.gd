extends Node2D
@onready var inventory_slots: GridContainer = $MarginContainer/MainInventoryTextureRect/MarginContainer/InventoryContainer
@onready var hotbar_slots: GridContainer = $MarginContainer/HotbarTextureRect/HotbarMarginContainer/HotbarItemMarginContainer/HotbarContainer
@onready var drag_preview_layer: Control = $DragPreview
@onready var tooltip_label: Label = $TooltipLabel
@onready var main_inventory_texture_rect: TextureRect = $MarginContainer/MainInventoryTextureRect

var holding_item: InventoryItem = null
var holding_quantity: int = 0
var holding_source_slot: InventorySlot = null
var drag_ghost: TextureRect = null

var item_data: Variant = JsonDataManager.load_data("res://resources/data/item_data.json")

# Hotbar selection
var current_hotbar_index: int = 0

func _ready() -> void:
	main_inventory_texture_rect.hide()
	tooltip_label.hide()
	
	# Initialize hotbar slots
	_setup_hotbar_slots()
	
	_connect_slot_signals()
	_connect_inventory_manager()

	_render_inventory()
	set_process_input(true)

	# Select first hotbar slot by default
	_select_hotbar_slot(2)

# --------------------------------------------
# Hotbar Setup
# --------------------------------------------

func _setup_hotbar_slots() -> void:
	var slots_array: Array = hotbar_slots.get_children()
	for i in range(slots_array.size()):
		slots_array[i].is_hotbar_slot = true
		slots_array[i].hotbar_index = i

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
	InventoryManager.connect("inventory_updated", Callable(self, "_on_inventory_updated"))
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

	index = _render_slots(inventory_slots_array, inventory_items, index)
	_render_slots(hotbar_slots_array, hotbar_items, index, true)
		
func _render_slots(slots: Array, item_ids: Array, start_index: int, hotbar_slots: bool = false) -> int:
	var index := start_index
	
	for item_id: int in item_ids:
		if index >= slots.size():
			break
		
		var item: Item = InventoryManager.get_item(item_id)
		var quantity: int = InventoryManager.get_item_quantity(item_id, hotbar_slots)
		
		if item:
			slots[index].put_item_from_inventory(item, quantity)
		index += 1
	
	for i in range(index, slots.size()):
		slots[i].clear_slot()
	
	return index

# to be used when you are picking stuff up, receiving items, etc
func _on_inventory_updated(item: Item, quantity: int, slot_type: String) -> void:
	apply_item_to_slots(inventory_slots.get_children(), item, quantity)
	
func _on_hotbar_updated(item: Item, quantity: int, slot_type: String) -> void:
	apply_item_to_slots(hotbar_slots.get_children(), item, quantity)
			
# should parse through slots and add it to an existing slot if found, otherwise place it in the first free slot
func apply_item_to_slots(slots: Array, item: Item, quantity: int) -> void:
	for slot: Variant in slots:
		if slot.item_id == item.id:
			if quantity > 0:
				slot.update_quantity(quantity)
			else:
				slot.clear_slot()
			return

	for slot: Variant in slots:
		if slot.item_name == "" or slot.item_name == null:
			if quantity > 0:
				slot.put_item_from_inventory(item, quantity)
			return


func _select_hotbar_slot(index: int) -> void:
	var slots_array: Array = hotbar_slots.get_children()
	if index < 0 or index >= slots_array.size():
		return
	
	current_hotbar_index = index
	var slot: Variant = slots_array[index]
	
	# Update InventoryManager with the selected item ID
	if slot and slot.item_id != -1:
		InventoryManager.select_item(slot.item_id, index)
	else:
		InventoryManager.select_item(-1, index)
		
	# Refresh all hotbar slots
	for hotbar_slot: Variant in slots_array:
		hotbar_slot.on_selection_changed()

func _cycle_hotbar(direction: int) -> void:
	var slots_array: Array = hotbar_slots.get_children()
	if slots_array.is_empty():
		return
	
	current_hotbar_index = (current_hotbar_index + direction)
	if current_hotbar_index < 0:
		current_hotbar_index = slots_array.size() - 1
	if current_hotbar_index > slots_array.size() - 1:
		current_hotbar_index = 0
	
	_select_hotbar_slot(current_hotbar_index)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		main_inventory_texture_rect.visible = !main_inventory_texture_rect.visible

func _on_slot_gui_input(event: InputEvent, slot: InventorySlot) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if holding_item:
				_handle_drop(slot)
			elif slot.inventory_item:
				_start_drag(slot)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if holding_item:
				_handle_drop_single(slot)
			elif slot.inventory_item:
				_split_stack(slot)

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
	

func _handle_drop_single(slot: InventorySlot) -> void:
	# slot has no item in it
	if not slot.inventory_item:
		slot.put_item_from_inventory(holding_item.item_reference, 1)
		
		# Track movement between hotbar and inventory
		var came_from_hotbar: bool = holding_source_slot and holding_source_slot.is_in_group("hotbar_slot")
		var going_to_hotbar: bool = slot.is_in_group("hotbar_slot")

		# Remove from source
		if came_from_hotbar:
			InventoryManager.remove_hotbar_item(holding_item.item_reference, 1)
		else:
			InventoryManager.remove_inventory_item(holding_item.item_reference, 1)

		# Add to destination
		if going_to_hotbar:
			InventoryManager.add_hotbar_item(holding_item.item_reference, 1)
		else:
			InventoryManager.add_inventory_item(holding_item.item_reference, 1)
			
		# if holding item is going to be depleted after this, kill the drag ghost
		# otherwise, decrease the quantity of the held item
		if holding_item.item_quantity <= 1:
			_destroy_drag_ghost()
			holding_item = null
			holding_source_slot = null
		else:
			holding_item.set_quantity(holding_item.item_quantity - 1)
		return

	# Stacking the same item
	if holding_item.item_reference.id == slot.inventory_item.item_reference.id:
		slot.update_quantity(slot.item_quantity + 1)
		
		# Track movement between hotbar and inventory
		var came_from_hotbar: bool = holding_source_slot and holding_source_slot.is_in_group("hotbar_slot")
		var going_to_hotbar: bool = slot.is_in_group("hotbar_slot")

		# Remove from source
		if came_from_hotbar:
			InventoryManager.remove_hotbar_item(holding_item.item_reference, 1)
		else:
			InventoryManager.remove_inventory_item(holding_item.item_reference, 1)

		# Add to destination
		if going_to_hotbar:
			InventoryManager.add_hotbar_item(holding_item.item_reference, 1)
		else:
			InventoryManager.add_inventory_item(holding_item.item_reference, 1)
			
		# Decrease held quantity
		if holding_item.item_quantity <= 1:
			_destroy_drag_ghost()
			holding_item = null
			holding_source_slot = null
		else:
			holding_item.set_quantity(holding_item.item_quantity - 1)

func _handle_drop(slot: InventorySlot) -> void:
	# Track where the item came from and where it's going
	var came_from_hotbar: bool = holding_source_slot and holding_source_slot.is_in_group("hotbar_slot")
	var going_to_hotbar: bool = slot.is_in_group("hotbar_slot")

	# Dropping into empty slot
	if not slot.inventory_item:
		slot.put_into_slot(holding_item)
		
		# Remove from source
		if came_from_hotbar:
			InventoryManager.remove_hotbar_item(holding_item.item_reference, holding_item.item_quantity)
		elif holding_source_slot:  # Only remove if there was a source slot
			InventoryManager.remove_inventory_item(holding_item.item_reference, holding_item.item_quantity)

		# Add to destination
		if going_to_hotbar:
			InventoryManager.add_hotbar_item(holding_item.item_reference, holding_item.item_quantity)
		else:
			InventoryManager.add_inventory_item(holding_item.item_reference, holding_item.item_quantity)
			
		holding_item = null
		holding_source_slot = null
		holding_quantity = 0
		_destroy_drag_ghost()
		
		# Update selection if dropped into current hotbar slot
		if slot.is_hotbar_slot and slot.hotbar_index == current_hotbar_index:
			_select_hotbar_slot(current_hotbar_index)
		return
		
	# Stacking the same item
	if holding_item.item_reference.id == slot.inventory_item.item_reference.id:
		slot.update_quantity(holding_item.item_quantity + slot.item_quantity)
		
		# Remove from source
		if came_from_hotbar:
			InventoryManager.remove_hotbar_item(holding_item.item_reference, holding_item.item_quantity)
		elif holding_source_slot:
			InventoryManager.remove_inventory_item(holding_item.item_reference, holding_item.item_quantity)

		# Add to destination (the merged stack)
		if going_to_hotbar:
			InventoryManager.add_hotbar_item(holding_item.item_reference, holding_item.item_quantity)
		else:
			InventoryManager.add_inventory_item(holding_item.item_reference, holding_item.item_quantity)
		
		_destroy_drag_ghost()
		holding_item = null
		holding_source_slot = null
		return

	# Swapping items
	var slot_item: InventoryItem = slot.pick_from_slot()
	
	# Remove both items from their locations
	# Remove held item from source
	if came_from_hotbar:
		InventoryManager.remove_hotbar_item(holding_item.item_reference, holding_item.item_quantity)
	elif holding_source_slot:
		InventoryManager.remove_inventory_item(holding_item.item_reference, holding_item.item_quantity)
	
	# Remove slot item from destination
	if going_to_hotbar:
		InventoryManager.remove_hotbar_item(slot_item.item_reference, slot_item.item_quantity)
	else:
		InventoryManager.remove_inventory_item(slot_item.item_reference, slot_item.item_quantity)
	
	# Place held item into slot
	slot.put_into_slot(holding_item)
	
	# Add held item to destination
	if going_to_hotbar:
		InventoryManager.add_hotbar_item(holding_item.item_reference, holding_item.item_quantity)
	else:
		InventoryManager.add_inventory_item(holding_item.item_reference, holding_item.item_quantity)
	
	# Add slot item to source (now being held)
	if came_from_hotbar:
		InventoryManager.add_hotbar_item(slot_item.item_reference, slot_item.item_quantity)
	else:
		InventoryManager.add_inventory_item(slot_item.item_reference, slot_item.item_quantity)
	
	# Now hold the swapped item
	holding_item = slot_item
	holding_quantity = holding_item.item_quantity
	
	_destroy_drag_ghost()
	_start_drag_from_swap(slot, holding_item)
	
	# Update selection if swapped in current hotbar slot
	if slot.is_hotbar_slot and slot.hotbar_index == current_hotbar_index:
		_select_hotbar_slot(current_hotbar_index)

func _split_stack(slot: Variant) -> void:
	var half: int = int(slot.item_quantity / 2)
	if half <= 0:
		return
	
	# Create new instance
	holding_item = preload("res://scenes/ui/inventory_item.tscn").instantiate()
	
	# IMPORTANT: Add to scene tree temporarily so @onready vars initialize
	add_child(holding_item)
	
	# Now set the item data (sprite and label are ready)
	holding_item.set_item(slot.inventory_item.item_reference, half)
	holding_quantity = half
	
	# Remove from this parent - it will be re-added when dropped
	remove_child(holding_item)
	
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

# --------------------------------------------
# Tooltip Handling
# --------------------------------------------

func _on_slot_mouse_entered(slot: InventorySlot) -> void:
	if slot.inventory_item:
		tooltip_label.text = slot.item_name
		tooltip_label.show()

func _on_slot_mouse_exited(slot: Variant) -> void:
	tooltip_label.hide()

# --------------------------------------------
# Input Handling (Drag Ghost + Hotbar Scroll)
# --------------------------------------------

func _input(event: InputEvent) -> void:
	# Handle drag ghost movement
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
