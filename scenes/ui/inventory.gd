extends Node2D

@onready var margin_container: MarginContainer = $MarginContainer
@onready var inventory_slots: GridContainer = $MarginContainer/TextureRect/MarginContainer/GridContainer
@onready var drag_preview_layer: Control = $DragPreview
@onready var tooltip_label: Label = $TooltipLabel

var holding_item: Variant = null          # The actual item node in hand
var holding_quantity: int = 0            # Quantity held
var holding_source_slot: Variant = null  # Slot node
var drag_ghost: TextureRect = null

var item_data: Variant = JsonDataManager.load_data("res://resources/data/item_data.json")


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
	for slot: Variant in inventory_slots.get_children():
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
	var slots: Array = inventory_slots.get_children()
	var index: int = 0

	for item_name: String in InventoryManager.inventory.keys():
		if index >= slots.size():
			print("Warning: not enough UI slots for item:", item_name)
			break
		var quantity: int = InventoryManager.inventory[item_name]
		slots[index].put_item_from_inventory(item_name, quantity)
		index += 1

	for i: int in range(index, slots.size()):
		slots[i].clear_slot()


# --------------------------------------------
# On Inventory Update
# --------------------------------------------

func _on_inventory_updated(item_name: String, quantity: int) -> void:
	for slot: Variant in inventory_slots.get_children():
		if slot.item_name == item_name:
			if quantity > 0:
				slot.update_quantity(quantity)
			else:
				slot.clear_slot()
			return

	for slot: Variant in inventory_slots.get_children():
		if slot.item_name == "" or slot.item_name == null:
			if quantity > 0:
				slot.put_item_from_inventory(item_name, quantity)
			return


# --------------------------------------------
# Toggle Inventory
# --------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		margin_container.visible = !margin_container.visible


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
		holding_item = null
		holding_source_slot = null
		holding_quantity = 0
		_destroy_drag_ghost()
		return

	var held_prev: Variant = holding_item
	var slot_item: Variant = slot.pick_from_slot()
	print("slot item name", slot_item.name)

	slot.put_into_slot(holding_item)
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
