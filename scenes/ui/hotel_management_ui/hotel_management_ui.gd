extends Control

const PENDING_BLOCK := preload("res://scenes/ui/hotel_management_ui/pending_guest_list_block.tscn")
const ACTIVE_BLOCK := preload("res://scenes/ui/hotel_management_ui/active_guest_list_block.tscn")
const ALERT_BLOCK := preload("res://scenes/ui/hotel_management_ui/alert.tscn")

@onready var _panel: Control = $"."
@onready var _pending_list: VBoxContainer = $TabContainer/PendingGuests/PendingGuestList
@onready var _active_list: VBoxContainer = $TabContainer/ActiveGuests/ActiveGuestsList
@onready var _alerts_list: VBoxContainer = $TabContainer/Alerts/MarginContainer/VBoxContainer


func _ready() -> void:
	_panel.hide()
	GuestAssignmentManager.guest_pending.connect(_on_guest_pending)
	GuestAssignmentManager.guest_checked_in.connect(_on_guest_checked_in)
	GuestAssignmentManager.guest_checked_out.connect(_on_guest_checked_out)
	DailyReportManager.alert_generated.connect(_on_alert_generated)
	SaveGameManager.game_loaded.connect(_on_game_loaded)
	_populate_pending_list()
	_populate_active_list()
	_populate_alerts()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_management_ui"):
		_panel.visible = !_panel.visible


func _populate_pending_list() -> void:
	for child in _pending_list.get_children():
		child.queue_free()
	for assignment: GuestAssignment in GuestAssignmentManager.get_pending_guests():
		_add_pending_block(assignment)


func _populate_active_list() -> void:
	for child in _active_list.get_children():
		child.queue_free()
	for assignment: GuestAssignment in GuestAssignmentManager.get_checked_in_guests():
		_add_active_block(assignment)


func _populate_alerts() -> void:
	for child in _alerts_list.get_children():
		child.queue_free()
	for alert: Variant in DailyReportManager.get_active_alerts():
		_add_alert_block(alert)


func _on_guest_pending(assignment: GuestAssignment) -> void:
	_add_pending_block(assignment)


func _on_guest_checked_in(assignment: GuestAssignment) -> void:
	_add_active_block(assignment)


func _on_guest_checked_out(assignment: GuestAssignment) -> void:
	for child in _active_list.get_children():
		if child is ActiveGuestListBlock and child.guest_id == assignment.guest_id:
			child.queue_free()
			return


func _on_alert_generated(alert: Variant) -> void:
	_add_alert_block(alert)


func _add_pending_block(assignment: GuestAssignment) -> void:
	var block: Node = PENDING_BLOCK.instantiate()
	_pending_list.add_child(block)
	block.setup(assignment)


func _add_active_block(assignment: GuestAssignment) -> void:
	var block: Node = ACTIVE_BLOCK.instantiate()
	_active_list.add_child(block)
	block.setup(assignment)


func _add_alert_block(alert: Variant) -> void:
	var block: Node = ALERT_BLOCK.instantiate()
	_alerts_list.add_child(block)
	block.setup(alert.message)


func _on_game_loaded() -> void:
	_populate_pending_list()
	_populate_active_list()
	_populate_alerts()
