extends Node2D
class_name StorageChest

@export var chest_size: int = 20
@export var chest_columns: int = 5
@export var chest_name: String = "Chest"

var inventory_id: String = ""
var persistent_id: String = ""  # Persistent ID for save/load
var chest_ui: ChestUI = null
var _is_registered: bool = false  # Track if inventory is registered

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var interactable_label_component: Control = $InteractableLabelComponent

var in_range: bool = false
var is_chest_open: bool = false


func _ready() -> void:
	interactable_component.interactable_activated.connect(on_interactable_activated)
	interactable_component.interactable_deactivated.connect(on_interactable_deactivated)
	interactable_label_component.hide()

	# Don't register if this is a ghost preview (parent is PlacementSystem)
	if get_parent() and get_parent().name == "PlacementSystem":
		return

	# If persistent_id not set (editor-placed chest), generate one based on position
	if persistent_id.is_empty():
		# Use position-based ID for editor-placed chests
		var grid_pos: Vector2i = BuildingLayoutData.world_to_grid(global_position)
		persistent_id = "chest_%d_%d" % [grid_pos.x, grid_pos.y]

	# Use persistent_id as inventory_id
	inventory_id = persistent_id

	# Register with inventory manager
	_register_inventory()

	chest_ui = get_tree().get_first_node_in_group("chest_ui") as ChestUI
	if chest_ui:
		chest_ui.closed.connect(_on_chest_ui_closed)


func set_persistent_id(id: String) -> void:
	"""Set the persistent ID for this chest (called by build system before _ready())"""
	persistent_id = id
	inventory_id = id


func _register_inventory() -> void:
	"""Register this chest's inventory with the InventoryManager"""
	if _is_registered:
		return

	# Check if inventory already exists (from loaded save data)
	var existing_inventory: InventoryData = InventoryManager.get_inventory(inventory_id)
	if existing_inventory:
		# Inventory was loaded from save, just mark as registered
		_is_registered = true
		print("StorageChest: Using existing inventory with ID: %s at position %s" % [inventory_id, global_position])
		return

	# Create new inventory if it doesn't exist
	var config := SimpleStorageConfig.new()
	config.total_slots = chest_size
	config.columns = chest_columns
	config.display_name = chest_name

	InventoryManager.create_inventory(inventory_id, config)
	_is_registered = true

	print("StorageChest: Created new inventory with ID: %s at position %s" % [inventory_id, global_position])


func on_interactable_activated() -> void:
	interactable_label_component.show()
	in_range = true


func on_interactable_deactivated() -> void:
	if is_chest_open:
		_close_chest()
	interactable_label_component.hide()
	in_range = false


func _unhandled_input(event: InputEvent) -> void:
	if not in_range:
		return
	
	if event.is_action_pressed("show_dialogue"):
		if is_chest_open:
			_close_chest()
		else:
			_open_chest()


func _open_chest() -> void:
	interactable_label_component.hide()
	animated_sprite_2d.play("chest_open")
	is_chest_open = true
	chest_ui.open(inventory_id)


func _close_chest() -> void:
	animated_sprite_2d.play("chest_close")
	is_chest_open = false
	chest_ui.close()


func _on_chest_ui_closed() -> void:
	animated_sprite_2d.play("chest_close")
	is_chest_open = false

#
#func _exit_tree() -> void:
	## Only unregister if we actually registered
	#if _is_registered and not inventory_id.is_empty():
		#InventoryManager.unregister_inventory(inventory_id)
		#_is_registered = false
