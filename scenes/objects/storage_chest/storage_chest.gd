extends Node2D
class_name StorageChest

@export var chest_size: int = 20
@export var chest_columns: int = 5
@export var chest_name: String = "Chest"

var inventory_id: String = ""
var chest_ui: ChestUI = null
var persistent_id: String = ""  # Persistent ID for build mode chests

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var interactable_label_component: Control = $InteractableLabelComponent

var in_range: bool = false
var is_chest_open: bool = false


func _ready() -> void:
	interactable_component.interactable_activated.connect(on_interactable_activated)
	interactable_component.interactable_deactivated.connect(on_interactable_deactivated)
	interactable_label_component.hide()

	# Check for pending custom_data from save system (for loaded chests)
	if persistent_id == "":
		var custom_data: Dictionary = BuildingLayoutData.get_and_clear_pending_custom_data(global_position)
		if custom_data.has("persistent_id"):
			persistent_id = custom_data["persistent_id"]

	# Use persistent_id if set (from build mode or save), otherwise use instance ID
	if persistent_id != "":
		inventory_id = persistent_id
	else:
		inventory_id = "chest_" + str(get_instance_id())
	
	var config := SimpleStorageConfig.new()
	config.total_slots = chest_size
	config.columns = chest_columns
	config.display_name = chest_name
	
	var chest_inventory: InventoryData = InventoryManager.get_inventory(inventory_id)
	
	if chest_inventory:
		InventoryManager.create_inventory(inventory_id, config)
	
	chest_ui = get_tree().get_first_node_in_group("chest_ui") as ChestUI
	if chest_ui:
		chest_ui.closed.connect(_on_chest_ui_closed)


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


func set_persistent_id(id: String) -> void:
	"""Set persistent ID before _ready() is called (used by build mode)"""
	persistent_id = id


func _exit_tree() -> void:
	InventoryManager.unregister_inventory(inventory_id)
