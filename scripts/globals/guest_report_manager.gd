extends Node

var task_reports: Array[Variant] = []
var mood_reports: Array[Variant] = []
var real_time_alerts: Array[Variant] = []
var per_guest_reports: Dictionary[String, Variant] = {}  # guest_id: PerGuestReport
var daily_summaries: Dictionary[String, Variant] = {}  # date_string: DailySummary
var historical_trends: Array[Variant] = []

# Configuration
var alert_thresholds: Dictionary[String, Variant] = {
	"negative_mood_intensity": 7,
	"consecutive_failures": 3,
	"low_success_rate": 50.0
}

# Signals
signal task_reported(task_report: Variant)
signal mood_reported(mood_report: Variant)
signal alert_generated(alert: Variant)
signal daily_summary_generated(summary: Variant)


func _ready() -> void:
	print("Hotel Report Manager initialized")

	var date: Dictionary = DayAndNightCycleManager.get_current_time()
	date = {"day": date.day, "year": 1900}
	generate_daily_summary(date)


# ============================================================================
# TASK REPORTING
# ============================================================================

func report_task_completion(
	guest_id: String,
	guest_name: String,
	task_type: String,
	location: String,
	additional_context: Dictionary
) -> Variant:

	var report: Variant = TaskReport.new(guest_id, guest_name, task_type, "completed", location)
	report.additional_context = additional_context

	task_reports.append(report)
	_update_guest_report(guest_id, guest_name, report)
	_update_daily_summary(report)

	task_reported.emit(report)
	return report


func report_task_failure(
	guest_id: String,
	guest_name: String,
	task_type: String,
	failure_reason: String,
	location: String,
	additional_context: Dictionary
) -> Variant:

	var report: Variant = TaskReport.new(guest_id, guest_name, task_type, "failed", location)
	report.failure_reason = failure_reason
	report.additional_context = additional_context

	task_reports.append(report)
	_update_guest_report(guest_id, guest_name, report)
	_update_daily_summary(report)

	task_reported.emit(report)
	return report


func report_mood(
	guest_id: String,
	guest_name: String,
	mood_type: String,
	intensity: int,
	trigger: String,
	location: String,
	context: String = "",
	room_number: String = ""
) -> Variant:

	var report: Variant = MoodReport.new(guest_id, guest_name, mood_type, intensity, trigger, location)
	report.context = context
	report.room_number = room_number

	mood_reports.append(report)
	_update_guest_mood(guest_id, guest_name, report)
	_update_daily_summary_mood(report)

	_check_mood_alert(report)

	mood_reported.emit(report)
	return report


func generate_alert(
	alert_type: String,
	severity: String,
	guest_id: String,
	guest_name: String,
	message: String,
	location: String
) -> Variant:

	var alert: Variant = RealTimeAlert.new(alert_type, severity, guest_id, guest_name, message, location)

	if severity == "critical":
		alert.requires_immediate_action = true

	real_time_alerts.append(alert)
	alert_generated.emit(alert)

	return alert


func _check_mood_alert(report: Variant) -> void:
	var negative_moods: Array[String] = ["frustrated", "angry", "disappointed", "upset", "annoyed"]
	if report.mood_type in negative_moods and report.intensity >= alert_thresholds["negative_mood_intensity"]:
		var severity: String = "critical" if report.intensity >= 9 else "high"
		generate_alert(
			"negative_mood",
			severity,
			report.guest_id,
			report.guest_name,
			"Guest is experiencing %s (intensity: %d) - %s" % [report.mood_type, report.intensity, report.trigger],
			report.location
		)


func get_active_alerts(severity_filter: String = "") -> Array[Variant]:
	if severity_filter.is_empty():
		return real_time_alerts.duplicate()

	var filtered: Array[Variant] = []
	for alert: Variant in real_time_alerts:
		if alert.severity == severity_filter:
			filtered.append(alert)
	return filtered


func clear_alert(alert: Variant) -> void:
	real_time_alerts.erase(alert)


func clear_all_alerts() -> void:
	real_time_alerts.clear()


# ============================================================================
# DAILY SUMMARY
# ============================================================================

func generate_daily_summary(date: Dictionary) -> Variant:
	if date.is_empty():
		date = DayAndNightCycleManager.get_current_time()
		date = {"day": date.day, "year": 1900}

	var date_key: String = str(date)

	if date_key in daily_summaries:
		return daily_summaries[date_key]

	var summary: Variant = DailySummary.new(date)
	daily_summaries[date_key] = summary

	_compile_daily_summary(summary)
	daily_summary_generated.emit(summary)

	return summary


func get_daily_summary(date: Dictionary = {}) -> Variant:
	if date.is_empty():
		date = DayAndNightCycleManager.get_current_time()
		date = {"day": date.day, "year": 1900}

	var date_key: String = str(date)

	if date_key in daily_summaries:
		return daily_summaries[date_key]

	return generate_daily_summary(date)


func _update_daily_summary(report: Variant) -> void:
	var date: Variant = DayAndNightCycleManager.get_current_time()
	date = {"day": date.day, "year": 1900}
	var date_key: String = str(date)

	if not daily_summaries.has(date_key):
		daily_summaries[date_key] = DailySummary.new(date)

	var summary: Variant = daily_summaries[date_key]

	summary.total_tasks_attempted += 1
	if report.status == "completed":
		summary.total_tasks_completed += 1
	else:
		summary.total_tasks_failed += 1

	if not summary.task_breakdown.has(report.task_type):
		summary.task_breakdown[report.task_type] = {"completed": 0, "failed": 0}

	if report.status == "completed":
		summary.task_breakdown[report.task_type]["completed"] += 1
	else:
		summary.task_breakdown[report.task_type]["failed"] += 1

	summary.calculate_metrics()


func _update_daily_summary_mood(report: Variant) -> void:
	var date: Dictionary = DayAndNightCycleManager.get_current_time()
	var date_key: String = str(date)

	if not daily_summaries.has(date_key):
		daily_summaries[date_key] = DailySummary.new(date)

	var summary: Variant = daily_summaries[date_key]

	if not summary.mood_breakdown.has(report.mood_type):
		summary.mood_breakdown[report.mood_type] = 0

	summary.mood_breakdown[report.mood_type] += 1

	var positive_moods: Array[String] = ["happy", "satisfied", "delighted", "content", "pleased"]
	var negative_moods: Array[String] = ["frustrated", "angry", "disappointed", "upset", "annoyed", "bored"]

	if report.mood_type in positive_moods:
		summary.positive_moods_count += 1
	elif report.mood_type in negative_moods:
		summary.negative_moods_count += 1
	else:
		summary.neutral_moods_count += 1


func _compile_daily_summary(summary: Variant) -> Variant:
	print("compiling summary")
	return {"summary": "cuckery"}


# ============================================================================
# PER-GUEST REPORTS
# ============================================================================

func get_guest_report(guest_id: String) -> Variant:
	if per_guest_reports.has(guest_id):
		return per_guest_reports[guest_id]
	return null


func create_guest_report(guest_id: String, guest_name: String) -> Variant:
	var report: Variant = PerGuestReport.new(guest_id, guest_name)
	per_guest_reports[guest_id] = report
	return report


func finalize_guest_report(guest_id: String) -> void:
	if per_guest_reports.has(guest_id):
		var report: Variant = per_guest_reports[guest_id]
		report.check_out_time = Time.get_unix_time_from_system()
		report.calculate_metrics()


func _update_guest_report(guest_id: String, guest_name: String, task_report: Variant) -> void:
	if not per_guest_reports.has(guest_id):
		per_guest_reports[guest_id] = PerGuestReport.new(guest_id, guest_name)

	var guest_report: Variant = per_guest_reports[guest_id]

	guest_report.total_tasks_attempted += 1
	if task_report.status == "completed":
		guest_report.total_tasks_completed += 1
	else:
		guest_report.total_tasks_failed += 1
		guest_report.complaints.append(task_report.failure_reason)

	guest_report.task_history.append(task_report.to_dict())

	if not guest_report.areas_visited.has(task_report.location):
		guest_report.areas_visited.append(task_report.location)

	guest_report.calculate_metrics()


func _update_guest_mood(guest_id: String, guest_name: String, mood_report: Variant) -> void:
	if not per_guest_reports.has(guest_id):
		per_guest_reports[guest_id] = PerGuestReport.new(guest_id, guest_name)

	var guest_report: Variant = per_guest_reports[guest_id]

	guest_report.mood_history.append(mood_report.to_dict())

	if mood_report.intensity > guest_report.highest_mood:
		guest_report.highest_mood = mood_report.intensity

	if mood_report.intensity < guest_report.lowest_mood:
		guest_report.lowest_mood = mood_report.intensity

	guest_report.calculate_metrics()


func get_all_guest_reports() -> Array[Variant]:
	var reports: Array[Variant] = []
	for guest_id: String in per_guest_reports:
		reports.append(per_guest_reports[guest_id])
	return reports


# ============================================================================
# HISTORICAL TRENDS
# ============================================================================

func generate_historical_trend(start_date: String, end_date: String, trend_type: String = "task_success") -> Variant:
	var trend: Variant = HistoricalTrend.new(start_date, end_date)
	trend.trend_type = trend_type

	for date_key: String in daily_summaries:
		if _is_date_in_range(date_key, start_date, end_date):
			trend.daily_summaries.append(daily_summaries[date_key])

	trend.calculate_trends()
	historical_trends.append(trend)

	return trend


func get_trend_by_type(trend_type: String) -> Array[Variant]:
	var trends: Array[Variant] = []
	for trend: Variant in historical_trends:
		if trend.trend_type == trend_type:
			trends.append(trend)
	return trends


func export_reports_to_json() -> String:
	var export_data: Dictionary = {
		"task_reports": [],
		"mood_reports": [],
		"daily_summaries": {},
		"guest_reports": {}
	}

	for report: Variant in task_reports:
		export_data["task_reports"].append(report.to_dict())

	for report: Variant in mood_reports:
		export_data["mood_reports"].append(report.to_dict())

	for date_key: String in daily_summaries:
		export_data["daily_summaries"][date_key] = daily_summaries[date_key].to_dict()

	for guest_id: String in per_guest_reports:
		export_data["guest_reports"][guest_id] = per_guest_reports[guest_id].to_dict()

	return JSON.stringify(export_data, "\t")


func _is_date_in_range(date: String, start: String, end: String) -> bool:
	return date >= start and date <= end
