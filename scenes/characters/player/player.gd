class_name Player
extends CharacterBody2D

@onready var hit_component: HitComponent = $HitComponent
@export var current_item: Item

var player_direction: Vector2

func _ready() -> void:
	InventoryManager.hotbar_item_selected.connect(on_hotbar_item_selected)
	
func on_hotbar_item_selected(item: Item) -> void:
	if item == null:
		current_item = null
		hit_component.current_tool = DataTypes.Tools.None
		return
	current_item = item
	hit_component.current_tool = item.tool_type
