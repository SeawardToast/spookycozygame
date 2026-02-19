extends Control

const PENDING_BLOCK := preload("res://scenes/ui/hotel_management_ui/pending_guest_list_block.tscn")

@onready var _panel: Control = $"."
@onready var _pending_list: VBoxContainer = $TabContainer/Guests/PendingGuestList


func _ready() -> void:
	_panel.hide()
	GuestAssignmentManager.guest_pending.connect(_on_guest_pending)
	_populate_pending_list()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_management_ui"):
		_panel.visible = !_panel.visible


func _populate_pending_list() -> void:
	for child in _pending_list.get_children():
		child.queue_free()
	for assignment: GuestAssignment in GuestAssignmentManager.get_pending_guests():
		_add_pending_block(assignment)


func _on_guest_pending(assignment: GuestAssignment) -> void:
	_add_pending_block(assignment)


func _add_pending_block(assignment: GuestAssignment) -> void:
	var block: Node = PENDING_BLOCK.instantiate()
	_pending_list.add_child(block)
	block.setup(assignment)
