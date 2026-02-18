class_name PendingGuestListBlock
extends PanelContainer

@onready var _name_label: Label = $MarginContainer/Label
@onready var _accept_button: Button = $MarginContainer/Button

var _assignment: GuestAssignment


func _ready() -> void:
	_accept_button.pressed.connect(_on_accept_pressed)


func setup(assignment: GuestAssignment) -> void:
	_assignment = assignment
	_name_label.text = assignment.guest_name


func _on_accept_pressed() -> void:
	GuestAssignmentManager.check_in(_assignment.guest_id)
	queue_free()
