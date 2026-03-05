class_name ActiveGuestListBlock
extends PanelContainer

@onready var _room_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/RoomNumberLabel
@onready var _name_label: Label = $MarginContainer/VBoxContainer/HBoxContainer2/GuestNameLabel
@onready var _mood_label: Label = $MarginContainer/VBoxContainer/HBoxContainer2/HBoxContainer/GuestMoodLabel

var guest_id: String


func setup(assignment: GuestAssignment) -> void:
	guest_id = assignment.guest_id
	_name_label.text = assignment.guest_name
	_room_label.text = assignment.room_instance_id
	refresh_mood()


func refresh_mood() -> void:
	var report: Variant = DailyReportManager.get_guest_report(guest_id)
	if not report or report.mood_history.is_empty():
		_mood_label.text = "—"
		return
	var last_mood: Dictionary = report.mood_history.back()
	_mood_label.text = last_mood.get("mood_type", "—")
