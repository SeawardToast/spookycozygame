class_name ActiveGuestListBlock
extends PanelContainer

@onready var _name_label: Label = $MarginContainer/VBoxContainer/Label
@onready var _room_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/RoomNumberLabel

var guest_id: String


func setup(assignment: GuestAssignment) -> void:
	guest_id = assignment.guest_id
	_name_label.text = assignment.guest_name
	_room_label.text = assignment.room_instance_id
