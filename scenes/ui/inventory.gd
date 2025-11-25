extends Node2D

@onready var margin_container: MarginContainer = $MarginContainer
@onready var inventory_slots: GridContainer = $MarginContainer/TextureRect/MarginContainer/GridContainer
@onready var drag_preview_layer: Control = $DragPreview
@onready var tooltip_label: Label = $TooltipLabel

var holding_item: Node2D = null          # The actual item node in hand
var holding_quantity: int = 0            # Quantity in hand
var holding_source_slot: Node = null     # Slot the drag came from
var drag_ghost: TextureRect = null

# Load item config data globally
var item_data = JsonDataManager.load_data("res://resources/data/item_data.json")

func _ready() -> void:
	margin_container.hide()
	tooltip_label.hide()
	_connect_slot_signals()
	_connect_inventory_manager()
	_render_inventory()

	set_process_input(true)


# --------------------------------------------
# Slot / Inventory Connections
# --------------------------------------------

func _connect_slot_signals() -> void:
	for slot in inventory_slots.get_children():
		slot.gui_input.connect(_on_slot_gui_input.bind(slot))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))

func _connect_inventory_manager() -> void:
	if InventoryManager.has_signal("inventory_updated"):
		InventoryManager.connect("inventory_updated", Callable(self, "_on_inventory_updated"))


# --------------------------------------------
# Render Initial Inventory
# --------------------------------------------

func _render_inventory() -> void:
	var slots = inventory_slots.get_children()
	var index := 0
	for item_name in InventoryManager.inventory.keys():
		if index >= slots.size():
			print("Warning: not enough UI slots for item:", item_name)
			break
		var quantity = InventoryManager.inventory[item_name]
		slots[index].put_item_from_inventory(item_name, quantity)
		index += 1
	# Clear remaining slots
	for i in range(index, slots.size()):
		slots[i].clear_slot()


# --------------------------------------------
# Inventory Update Signal
# --------------------------------------------

func _on_inventory_updated(item_name: String, quantity: int) -> void:
	for slot in inventory_slots.get_children():
		if slot.item_name == item_name:
			if quantity > 0:
				slot.update_quantity(quantity)
			else:
				slot.clear_slot()
			return
	for slot in inventory_slots.get_children():
		if slot.item_name == "" or slot.item_name == null:
			if quantity > 0:
				slot.put_item_from_inventory(item_name, quantity)
			return


# --------------------------------------------
# Toggle inventory
# --------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		margin_container.visible = !margin_container.visible


# --------------------------------------------
# Slot Drag & Drop
# --------------------------------------------

func _on_slot_gui_input(event: InputEvent, slot):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.is_key_pressed(KEY_SHIFT):
				# SHIFT-CLICK QUICK MOVE
				_shift_quick_move(slot)
				return
			# Pick up or drop
			if holding_item:
				_handle_drop(slot)
			elif slot.item:
				_start_drag(slot)
		#elif event.button_index == MOUSE_BUTTON_RIGHT:
			#if slot.item and slot.item_quantity > 1:
				#_split_stack(slot)


func _start_drag(slot):
	# Pick item from slot (slot is now empty)
	holding_item = slot.pick_from_slot()
	if not holding_item:
		return

	holding_source_slot = slot
	holding_quantity = holding_item.item_quantity

	# Create ghost visual
	drag_ghost = TextureRect.new()
	drag_ghost.texture = holding_item.sprite.texture
	drag_ghost.modulate = Color(1,1,1,0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2,1.2)
	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
	
func _start_drag_from_swap(slot, holding_item):
	if not holding_item:
		return

	holding_source_slot = slot
	holding_quantity = holding_item.item_quantity

	# Create ghost visual
	drag_ghost = TextureRect.new()
	drag_ghost.texture = holding_item.sprite.texture
	drag_ghost.modulate = Color(1,1,1,0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2,1.2)
	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5



func _handle_drop(slot):
	if not slot.item:
		# Place holding item into empty slot
		slot.put_into_slot(holding_item)
		holding_item = null
		holding_source_slot = null
		holding_quantity = 0
		_destroy_drag_ghost()
		return
		
	# what happens when we swap?
	# save the holding item in a var
	# set the holding item to the slot item
	# set the slot item to the saved var holding item	

	# Slot has an item → swap
	var holding_item_dupe = holding_item
	var slot_item = slot.pick_from_slot()  
	print("slot item name", slot_item.name)   # remove item from target
	slot.put_into_slot(holding_item)          # place hand item
	holding_item = slot_item                   # previous target item now in hand
	holding_quantity = holding_item.item_quantity
	_destroy_drag_ghost()
	_start_drag_from_swap(slot, holding_item)                          # re-create drag ghost for swapped item


func _split_stack(slot):
	# Minecraft style: right-click takes half stack
	var half = int(slot.item_quantity / 2)
	if half <= 0:
		return
	holding_item = slot.item
	holding_quantity = half
	slot.update_quantity(slot.item_quantity - half)

	# Create drag ghost
	drag_ghost = TextureRect.new()
	drag_ghost.texture = holding_item.sprite.texture
	drag_ghost.modulate = Color(1,1,1,0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2,1.2)
	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5


func _destroy_drag_ghost():
	if drag_ghost:
		drag_ghost.queue_free()
		drag_ghost = null


func _shift_quick_move(slot):
	if not slot.item:
		return
	var item_name = slot.item_name
	var qty = slot.item_quantity

	# Find first empty slot
	for target in inventory_slots.get_children():
		if target == slot:
			continue
		if target.item_name == "" or target.item_name == null:
			target.put_item_from_inventory(item_name, qty)
			slot.clear_slot()
			return


# --------------------------------------------
# Tooltip Handling
# --------------------------------------------

func _on_slot_mouse_entered(slot):
	if slot.item:
		# Print for now, future-proof for sprite
		tooltip_label.text = slot.item_name
		tooltip_label.show()


func _on_slot_mouse_exited(slot):
	tooltip_label.hide()


# --------------------------------------------
# Input & Drag Update
# --------------------------------------------

func _input(event):
	if holding_item and drag_ghost:
		drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
