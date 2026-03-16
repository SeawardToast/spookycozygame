class_name AlertBlock
extends Control

@onready var _dismiss_button: Button = $MarginContainer/HBoxContainer/DismissButton
@onready var _vbox: VBoxContainer = $MarginContainer/HBoxContainer/VBoxContainer

func _ready() -> void:
	_dismiss_button.pressed.connect(_on_dismiss_pressed)


func setup(message: String) -> void:
	for child in _vbox.get_children():
		child.queue_free()

	var lines := message.split("\n")
	var multiline := lines.size() > 1
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER if not multiline else BoxContainer.ALIGNMENT_BEGIN
	for line: String in lines:
		var label := Label.new()
		label.theme_type_variation = &"DayAndNightLabel"
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if not multiline else HORIZONTAL_ALIGNMENT_LEFT
		_vbox.add_child(label)


func _on_dismiss_pressed() -> void:
	queue_free()
