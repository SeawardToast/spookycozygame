extends Control
@onready var hotel_management_panel: Control = $"."

func _ready() -> void:
	hotel_management_panel.hide()
	print("Management UI initialized")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_management_ui"):
		hotel_management_panel.visible = !hotel_management_panel.visible
