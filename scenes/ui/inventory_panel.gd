extends PanelContainer

@onready var log_label: Label = $MarginContainer/VBoxContainer/Logs/LogLabel
@onready var corn_label: Label = $MarginContainer/VBoxContainer/Corn/CornLabel
@onready var tomato_label: Label = $MarginContainer/VBoxContainer/Tomato/TomatoLabel

func _ready() -> void:
	InventoryManager.inventory_changed.connect(on_inventory_changed)
	
func on_inventory_changed() -> void:
	var inventory: Dictionary = InventoryManager.inventory
	
	if inventory.has("log"):
		log_label.text = str(inventory["log"])
		
	if inventory.has("corn"):
		corn_label.text = str(inventory["corn"])
		
	if inventory.has("tomato"):
		tomato_label.text = str(inventory["tomato"])
