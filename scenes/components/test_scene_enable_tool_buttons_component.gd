extends Node

func _ready() -> void:
	call_deferred("enable_tool_buttons")
	
func enable_tool_buttons() -> void:
	ToolManager.enable_tool_button(DataTypes.ItemType.TillGround)
	ToolManager.enable_tool_button(DataTypes.ItemType.WaterCrops)
	ToolManager.enable_tool_button(DataTypes.ItemType.PlantCorn)
	ToolManager.enable_tool_button(DataTypes.ItemType.PlantTomato)
