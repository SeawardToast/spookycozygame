extends Control

@onready var report_board: PanelContainer = $"."
@onready var task_completed_label: Label = $MarginContainer/VBoxContainer/TaskCompletedLabel
@onready var task_failed_label: Label = $MarginContainer/VBoxContainer/TaskFailedLabel
@onready var day_label: Label = $MarginContainer/VBoxContainer2/HBoxContainer/DayLabel
@onready var year_label: Label = $MarginContainer/VBoxContainer2/HBoxContainer/YearLabel

func _ready() -> void:
	DailyReportManager.daily_summary_generated.connect(on_daily_report)
	report_board.hide()
	print("Report board initialized")
	
func on_daily_report() -> void:
	report_board.show()
	
func _on_normal_speed_button_pressed() -> void:
	report_board.hide()
	
func _on_open() -> void:
	var daily_summary: DailySummary = DailyReportManager.get_daily_summary()
	task_completed_label.text = "Tasks Completed: " + str(daily_summary.total_tasks_completed)
	task_failed_label.text = "Tasks Failed: " + str(daily_summary.total_tasks_failed)
	var day_format_string = "Day %s,"
	day_label.text = day_format_string % daily_summary.date.day
	var year_format_string = "Year %s"
	year_label.text = year_format_string % daily_summary.date.year
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_journal"):
		_on_open()
		report_board.visible = !report_board.visible
