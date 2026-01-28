extends Node2D

@onready var inventory_slots: GridContainer = $MarginContainer/MainInventoryTextureRect/MarginContainer/InventoryContainer
@onready var hotbar_slots: GridContainer = $MarginContainer/HotbarTextureRect/HotbarMarginContainer/HotbarItemMarginContainer/HotbarContainer
@onready var drag_preview_layer: Control = $DragPreview
@onready var tooltip_label: Label = $TooltipLabel
@onready var main_inventory_texture_rect: TextureRect = $MarginContainer/MainInventoryTextureRect
@onready var hotbar_texture_rect: TextureRect = $MarginContainer/HotbarTextureRect

var holding_item_id: int = -1
var holding_quantity: int = 0
var holding_source_inventory_id: String = ""
var holding_source_slot: int = -1
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
	
	InventoryManager.player_inventory.slot_changed.connect(_on_main_slot_changed)
	InventoryManager.player_hotbar.slot_changed.connect(_on_hotbar_slot_changed)
	SignalBus.chest_opened.connect(_on_chest_opened)
	SignalBus.chest_closed.connect(_on_chest_closed)


func _setup_slots() -> void:
	for i in hotbar_slots.get_child_count():
		var slot: InventorySlot = hotbar_slots.get_child(i)
		slot.is_hotbar_slot = true
		slot.hotbar_index = i
	
	for slot in inventory_slots.get_children():
		var idx := inventory_slots.get_children().find(slot)
		slot.gui_input.connect(_on_main_slot_input.bind(slot, idx))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited)
	
	for slot in hotbar_slots.get_children():
		var idx := hotbar_slots.get_children().find(slot)
		slot.gui_input.connect(_on_hotbar_slot_input.bind(slot, idx))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited)


func _render_all_slots() -> void:
	for i in inventory_slots.get_child_count():
		var slot: InventorySlot = inventory_slots.get_child(i)
		var data := InventoryManager.player_inventory.get_slot(i)
		_render_slot(slot, data)
	
	for i in hotbar_slots.get_child_count():
		var slot: InventorySlot = hotbar_slots.get_child(i)
		var data := InventoryManager.player_hotbar.get_slot(i)
		_render_slot(slot, data)


func _render_slot(slot: InventorySlot, data: Dictionary) -> void:
	if data.item_id == -1:
		slot.clear_slot()
	else:
		var item: Item = InventoryManager.get_item(data.item_id)
		if item:
			slot.put_item_from_inventory(item, data.quantity)


func _on_main_slot_changed(slot_index: int) -> void:
	if slot_index < inventory_slots.get_child_count():
		var slot: InventorySlot = inventory_slots.get_child(slot_index)
		_render_slot(slot, InventoryManager.player_inventory.get_slot(slot_index))


func _on_hotbar_slot_changed(slot_index: int) -> void:
	if slot_index < hotbar_slots.get_child_count():
		var slot: InventorySlot = hotbar_slots.get_child(slot_index)
		_render_slot(slot, InventoryManager.player_hotbar.get_slot(slot_index))


func _select_hotbar_slot(index: int) -> void:
	if index < 0 or index >= hotbar_slots.get_child_count():
		return
	current_hotbar_index = index
	InventoryManager.select_hotbar_slot(index)
	for slot in hotbar_slots.get_children():
		slot.on_selection_changed()


func _cycle_hotbar(direction: int) -> void:
	var count := hotbar_slots.get_child_count()
	current_hotbar_index = (current_hotbar_index + direction + count) % count
	_select_hotbar_slot(current_hotbar_index)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		main_inventory_texture_rect.visible = !main_inventory_texture_rect.visible


func _input(event: InputEvent) -> void:
	if _is_holding() and drag_ghost:
		drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_hotbar(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_hotbar(1)
			get_viewport().set_input_as_handled()


func _on_main_slot_input(event: InputEvent, slot: InventorySlot, slot_index: int) -> void:
	_handle_slot_input(event, slot, "player_main", slot_index)


func _on_hotbar_slot_input(event: InputEvent, slot: InventorySlot, slot_index: int) -> void:
	_handle_slot_input(event, slot, "player_hotbar", slot_index)


func _handle_slot_input(event: InputEvent, slot: InventorySlot, inv_id: String, slot_index: int) -> void:
	if not event is InputEventMouseButton or not event.pressed or not main_inventory_texture_rect.visible:
		return
	
	var mouse_event := event as InputEventMouseButton
	var slot_data := InventoryManager.get_inventory(inv_id).get_slot(slot_index)
	
	match mouse_event.button_index:
		MOUSE_BUTTON_LEFT:
			if _is_holding():
				_handle_drop(inv_id, slot, slot_index)
			elif slot_data.item_id != -1:
				_start_drag(inv_id, slot_index)
		MOUSE_BUTTON_RIGHT:
			if _is_holding():
				_handle_drop_single(inv_id, slot, slot_index)
			elif slot_data.item_id != -1:
				_split_stack(inv_id, slot_index)


func _is_holding() -> bool:
	return holding_item_id != -1


func _start_drag(inv_id: String, slot_index: int) -> void:
	var inv := InventoryManager.get_inventory(inv_id)
	var slot_data := inv.get_slot(slot_index)
	
	holding_item_id = slot_data.item_id
	holding_quantity = slot_data.quantity
	holding_source_inventory_id = inv_id
	holding_source_slot = slot_index
	
	var item := InventoryManager.get_item(holding_item_id)
	_create_drag_ghost(item.icon)
	
	inv.clear_slot(slot_index)


func _split_stack(inv_id: String, slot_index: int) -> void:
	var inv := InventoryManager.get_inventory(inv_id)
	var slot_data := inv.get_slot(slot_index)
	
	var half: int = slot_data.quantity / 2
	if half <= 0:
		return
	
	holding_item_id = slot_data.item_id
	holding_quantity = half
	holding_source_inventory_id = inv_id
	holding_source_slot = slot_index
	
	var item := InventoryManager.get_item(holding_item_id)
	_create_drag_ghost(item.icon)
	
	inv.set_slot(slot_index, slot_data.item_id, slot_data.quantity - half)


func _handle_drop(inv_id: String, slot: InventorySlot, slot_index: int) -> void:
	var inv := InventoryManager.get_inventory(inv_id)
	var item := InventoryManager.get_item(holding_item_id)
	
	if not inv.can_accept_item(slot_index, item):
		return
	
	var slot_data := inv.get_slot(slot_index)
	
	# Empty slot
	if slot_data.item_id == -1:
		var amount := mini(holding_quantity, item.max_stack_size)
		inv.set_slot(slot_index, holding_item_id, amount)
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
		inv.set_slot(slot_index, holding_item_id, slot_data.quantity + amount)
		holding_quantity -= amount
		if holding_quantity <= 0:
			_cleanup_holding()
		else:
			_update_drag_ghost_label()
		return
	
	# Different item - swap
	var old_item_id: int = slot_data.item_id
	var old_quantity: int = slot_data.quantity
	
	inv.set_slot(slot_index, holding_item_id, holding_quantity)
	
	holding_item_id = old_item_id
	holding_quantity = old_quantity
	_destroy_drag_ghost()
	_create_drag_ghost(InventoryManager.get_item(holding_item_id).icon)


func _handle_drop_single(inv_id: String, slot: InventorySlot, slot_index: int) -> void:
	var inv := InventoryManager.get_inventory(inv_id)
	var item := InventoryManager.get_item(holding_item_id)
	
	if not inv.can_accept_item(slot_index, item):
		return
	
	var slot_data := inv.get_slot(slot_index)
	
	if slot_data.item_id != -1 and slot_data.item_id != holding_item_id:
		return
	
	if slot_data.item_id != -1 and slot_data.quantity >= item.max_stack_size:
		return
	
	var new_qty: int = 1 if slot_data.item_id == -1 else slot_data.quantity + 1
	inv.set_slot(slot_index, holding_item_id, new_qty)
	
	holding_quantity -= 1
	if holding_quantity <= 0:
		_cleanup_holding()
	else:
		_update_drag_ghost_label()


func _create_drag_ghost(texture: Texture2D) -> void:
	drag_ghost = TextureRect.new()
	drag_ghost.texture = texture
	drag_ghost.modulate = Color(1, 1, 1, 0.75)
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_ghost.scale = Vector2(1.2, 1.2)
	drag_preview_layer.add_child(drag_ghost)
	drag_ghost.global_position = get_global_mouse_position() - drag_ghost.size * 0.5
	# Set high z_index so ghost renders on top of placed pieces
	drag_ghost.z_index = 100
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


func _on_slot_mouse_entered(slot: InventorySlot) -> void:
	if slot.item_id != -1 and main_inventory_texture_rect.visible:
		tooltip_label.text = slot.item_name
		tooltip_label.show()

func _on_slot_mouse_exited() -> void:
	tooltip_label.hide()
	
func _on_chest_opened() -> void:
	hotbar_texture_rect.hide()

func _on_chest_closed() -> void:
	hotbar_texture_rect.show()
