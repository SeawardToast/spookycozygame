class_name AlertBlock
extends Control

@onready var _label: Label = $HBoxContainer/Label
@onready var _dismiss_button: Button = $HBoxContainer/DismissButton


func _ready() -> void:
	_dismiss_button.pressed.connect(_on_dismiss_pressed)


func setup(message: String) -> void:
	_label.text = message


func _on_dismiss_pressed() -> void:
	queue_free()
