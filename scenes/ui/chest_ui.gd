extends Node2D
class_name ChestUI

@onready var chest_slots: GridContainer = $MarginContainer/ChestTextureRect/ChestMarginContainer/ChestContainer
@onready var drag_preview_layer: Control = $DragPreview
@onready var tooltip_label: Label = $TooltipLabel
@onready var player_hotbar_slots: GridContainer = $MarginContainer/HotbarTextureRect/HotbarMarginContainer/HotbarItemMarginContainer/HotbarContainer
@onready var player_main_slots: GridContainer = $MarginContainer/MainInventoryTextureRect/MarginContainer/InventoryContainer
@onready var chest_title_label: Label = $MarginContainer/ChestTextureRect/ChestMarginContainer/Label

var chest_inventory_id: String = ""
var holding_item_id: int = -1
var holding_quantity: int = 0
var holding_source_inventory_id: String = ""
var holding_source_slot: int = -1
var drag_ghost: TextureRect = null
var drag_ghost_label: Label = null

func _ready() -> void:
	hide()
	tooltip_label.hide()
	_setup_player_slots()

func _setup_player_slots() -> void:
	for i in player_main_slots.get_child_count():
		var slot: InventorySlot = player_main_slots.get_child(i)
		slot.gui_input.connect(_on_player_main_slot_input.bind(slot, i))
		slot.mouse_entered.connect(_on_slot_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_exited)
	
	for i in player_hotbar_slots.get_child_count():
		var slot: InventorySlot = player_hotbar_slots.get_child(i)
		slot.is_hotbar_slot = true
		slot.hotbar_index = i
		slot.gui_input.connect(_on_player_hotbar_slot_input.bind(slot, i))
		slot.mouse_entered.connect(_on_slot_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_exited)


func _setup_chest_slots() -> void:
	for i in chest_slots.get_child_count():
		var slot: InventorySlot = chest_slots.get_child(i)
		if not slot.gui_input.is_connected(_on_chest_slot_input):
			slot.gui_input.connect(_on_chest_slot_input.bind(slot, i))
			slot.mouse_entered.connect(_on_slot_entered.bind(slot))
			slot.mouse_exited.connect(_on_slot_exited)


func open(inventory_id: String) -> void:
	chest_inventory_id = inventory_id
	var chest_inv: InventoryData = InventoryManager.get_inventory(inventory_id)
	
	if not chest_inv:
		push_error("ChestUI: Inventory not found: " + inventory_id)
		return
	
	chest_title_label.text = chest_inv.slot_config.display_name
	
	_setup_chest_slots()
	
	chest_inv.slot_changed.connect(_on_chest_slot_changed)
	InventoryManager.player_inventory.slot_changed.connect(_on_player_main_changed)
	InventoryManager.player_hotbar.slot_changed.connect(_on_player_hotbar_changed)
	SignalBus.chest_opened.emit()
	_render_all()
	show()


func close() -> void:
	var chest_inv := InventoryManager.get_inventory(chest_inventory_id)
	if chest_inv and chest_inv.slot_changed.is_connected(_on_chest_slot_changed):
		chest_inv.slot_changed.disconnect(_on_chest_slot_changed)
	if InventoryManager.player_inventory.slot_changed.is_connected(_on_player_main_changed):
		InventoryManager.player_inventory.slot_changed.disconnect(_on_player_main_changed)
	if InventoryManager.player_hotbar.slot_changed.is_connected(_on_player_hotbar_changed):
		InventoryManager.player_hotbar.slot_changed.disconnect(_on_player_hotbar_changed)
	
	_return_held_item()
	chest_inventory_id = ""
	hide()
	SignalBus.chest_closed.emit()

# --------------------------------------------
# Rendering
# --------------------------------------------

func _render_all() -> void:
	var chest_inv := InventoryManager.get_inventory(chest_inventory_id)
	
	for i in chest_slots.get_child_count():
		_render_slot(chest_slots.get_child(i), chest_inv.get_slot(i))
	
	for i in player_main_slots.get_child_count():
		_render_slot(player_main_slots.get_child(i), InventoryManager.player_inventory.get_slot(i))
	
	for i in player_hotbar_slots.get_child_count():
		_render_slot(player_hotbar_slots.get_child(i), InventoryManager.player_hotbar.get_slot(i))


func _render_slot(slot: InventorySlot, data: Dictionary) -> void:
	if data.item_id == -1:
		slot.clear_slot()
	else:
		var item := InventoryManager.get_item(data.item_id)
		if item:
			slot.put_item_from_inventory(item, data.quantity)


func _on_chest_slot_changed(idx: int) -> void:
	if idx < chest_slots.get_child_count():
		var chest_inv := InventoryManager.get_inventory(chest_inventory_id)
		_render_slot(chest_slots.get_child(idx), chest_inv.get_slot(idx))


func _on_player_main_changed(idx: int) -> void:
	if idx < player_main_slots.get_child_count():
		_render_slot(player_main_slots.get_child(idx), InventoryManager.player_inventory.get_slot(idx))


func _on_player_hotbar_changed(idx: int) -> void:
	if idx < player_hotbar_slots.get_child_count():
		_render_slot(player_hotbar_slots.get_child(idx), InventoryManager.player_hotbar.get_slot(idx))


# --------------------------------------------
# Input
# --------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if _is_holding() and drag_ghost:
		drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
	
	if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_chest_slot_input(event: InputEvent, slot: InventorySlot, idx: int) -> void:
	_handle_slot_input(event, chest_inventory_id, idx)


func _on_player_main_slot_input(event: InputEvent, slot: InventorySlot, idx: int) -> void:
	_handle_slot_input(event, "player_main", idx)


func _on_player_hotbar_slot_input(event: InputEvent, slot: InventorySlot, idx: int) -> void:
	_handle_slot_input(event, "player_hotbar", idx)


func _handle_slot_input(event: InputEvent, inv_id: String, idx: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	
	var btn := (event as InputEventMouseButton).button_index
	var inv := InventoryManager.get_inventory(inv_id)
	var slot_data := inv.get_slot(idx)
	
	match btn:
		MOUSE_BUTTON_LEFT:
			if Input.is_key_pressed(KEY_SHIFT):
				_quick_transfer(inv_id, idx)
			elif _is_holding():
				_handle_drop(inv_id, idx)
			elif slot_data.item_id != -1:
				_start_drag(inv_id, idx)
		MOUSE_BUTTON_RIGHT:
			if _is_holding():
				_handle_drop_single(inv_id, idx)
			elif slot_data.item_id != -1:
				_split_stack(inv_id, idx)


# --------------------------------------------
# Quick Transfer
# --------------------------------------------

func _quick_transfer(from_id: String, from_slot: int) -> void:
	if from_id == chest_inventory_id:
		if not InventoryManager.quick_transfer(from_id, from_slot, "player_hotbar"):
			InventoryManager.quick_transfer(from_id, from_slot, "player_main")
	else:
		InventoryManager.quick_transfer(from_id, from_slot, chest_inventory_id)


# --------------------------------------------
# Drag Operations
# --------------------------------------------

func _is_holding() -> bool:
	return holding_item_id != -1


func _start_drag(inv_id: String, idx: int) -> void:
	var inv := InventoryManager.get_inventory(inv_id)
	var slot_data := inv.get_slot(idx)
	
	holding_item_id = slot_data.item_id
	holding_quantity = slot_data.quantity
	holding_source_inventory_id = inv_id
	holding_source_slot = idx
	
	_create_drag_ghost(InventoryManager.get_item(holding_item_id).icon)
	inv.clear_slot(idx)


func _split_stack(inv_id: String, idx: int) -> void:
	var inv := InventoryManager.get_inventory(inv_id)
	var slot_data := inv.get_slot(idx)
	
	var half: int = slot_data.quantity / 2
	if half <= 0:
		return
	
	holding_item_id = slot_data.item_id
	holding_quantity = half
	holding_source_inventory_id = inv_id
	holding_source_slot = idx
	
	_create_drag_ghost(InventoryManager.get_item(holding_item_id).icon)
	inv.set_slot(idx, slot_data.item_id, slot_data.quantity - half)


func _handle_drop(inv_id: String, idx: int) -> void:
	var inv := InventoryManager.get_inventory(inv_id)
	var item := InventoryManager.get_item(holding_item_id)
	
	if not inv.can_accept_item(idx, item):
		return
	
	var slot_data := inv.get_slot(idx)
	
	# Empty slot
	if slot_data.item_id == -1:
		var amount := mini(holding_quantity, item.max_stack_size)
		inv.set_slot(idx, holding_item_id, amount)
		holding_quantity -= amount
		if holding_quantity <= 0:
			_cleanup_holding()
		else:
			_update_drag_ghost_label()
		return
	
	# Same item - stack
	if slot_data.item_id == holding_item_id:
		var space: int = item.max_stack_size - slot_data.quantity
		if space <= 0:
			return
		var amount := mini(holding_quantity, space)
		inv.set_slot(idx, holding_item_id, slot_data.quantity + amount)
		holding_quantity -= amount
		if holding_quantity <= 0:
			_cleanup_holding()
		else:
			_update_drag_ghost_label()
		return
	
	# Different item - swap
	var old_id: int = slot_data.item_id
	var old_qty: int = slot_data.quantity
	inv.set_slot(idx, holding_item_id, holding_quantity)
	holding_item_id = old_id
	holding_quantity = old_qty
	_destroy_drag_ghost()
	_create_drag_ghost(InventoryManager.get_item(holding_item_id).icon)


func _handle_drop_single(inv_id: String, idx: int) -> void:
	var inv := InventoryManager.get_inventory(inv_id)
	var item := InventoryManager.get_item(holding_item_id)
	
	if not inv.can_accept_item(idx, item):
		return
	
	var slot_data := inv.get_slot(idx)
	
	if slot_data.item_id != -1 and slot_data.item_id != holding_item_id:
		return
	if slot_data.item_id != -1 and slot_data.quantity >= item.max_stack_size:
		return
	
	var new_qty: int = 1 if slot_data.item_id == -1 else slot_data.quantity + 1
	inv.set_slot(idx, holding_item_id, new_qty)
	
	holding_quantity -= 1
	if holding_quantity <= 0:
		_cleanup_holding()
	else:
		_update_drag_ghost_label()


func _return_held_item() -> void:
	if not _is_holding():
		return
	
	var inv := InventoryManager.get_inventory(holding_source_inventory_id)
	if inv:
		var slot := inv.get_slot(holding_source_slot)
		if slot.item_id == -1:
			inv.set_slot(holding_source_slot, holding_item_id, holding_quantity)
		elif slot.item_id == holding_item_id:
			var item := InventoryManager.get_item(holding_item_id)
			var new_qty := mini(slot.quantity + holding_quantity, item.max_stack_size)
			inv.set_slot(holding_source_slot, holding_item_id, new_qty)
	
	_cleanup_holding()


# --------------------------------------------
# Drag Ghost
# --------------------------------------------

func _create_drag_ghost(texture: Texture2D) -> void:
	drag_ghost = TextureRect.new()
	drag_ghost.texture = texture
	drag_ghost.modulate = Color(1, 1, 1, 0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2, 1.2)
	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
	
	if holding_quantity > 1:
		drag_ghost_label = Label.new()
		drag_ghost_label.text = str(holding_quantity)
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
	if drag_ghost_label:
		drag_ghost_label.text = str(holding_quantity)
		drag_ghost_label.visible = holding_quantity > 1


func _destroy_drag_ghost() -> void:
	if drag_ghost:
		drag_ghost.queue_free()
		drag_ghost = null
		drag_ghost_label = null


func _cleanup_holding() -> void:
	holding_item_id = -1
	holding_quantity = 0
	holding_source_inventory_id = ""
	holding_source_slot = -1
	_destroy_drag_ghost()


# --------------------------------------------
# Tooltip
# --------------------------------------------

func _on_slot_entered(slot: InventorySlot) -> void:
	if slot.item_id != -1:
		tooltip_label.text = slot.item_name
		tooltip_label.show()


func _on_slot_exited() -> void:
	tooltip_label.hide()
