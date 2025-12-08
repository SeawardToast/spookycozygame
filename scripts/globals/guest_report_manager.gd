extends Node

var task_reports: Array[TaskReport] = []
var mood_reports: Array[MoodReport] = []
var real_time_alerts: Array[RealTimeAlert] = []
var per_guest_reports: Dictionary = {}  # guest_id: PerGuestReport
var daily_summaries: Dictionary = {}  # date_string: DailySummary
var historical_trends: Array[HistoricalTrend] = []

# Configuration
var alert_thresholds = {
	"negative_mood_intensity": 7,  # Moods with intensity >= 7 trigger alerts
	"consecutive_failures": 3,  # Number of consecutive failures to trigger alert
	"low_success_rate": 50.0  # Success rate below this triggers concern
}

# Signals for real-time notifications
signal task_reported(task_report: TaskReport)
signal mood_reported(mood_report: MoodReport)
signal alert_generated(alert: RealTimeAlert)
signal daily_summary_generated(summary: DailySummary)


func _ready():
	print("Hotel Report Manager initialized")
	# Create today's summary
	var date = DayAndNightCycleManager.get_current_time()
	date = {"day": date.day, "year": 1900}
	generate_daily_summary(date)
	
# ============================================================================
# TASK REPORTING METHODS
# ============================================================================

func report_task_completion(guest_id: String, guest_name: String, task_type: String, location: String, additional_context: Dictionary) -> TaskReport:
	var report = TaskReport.new(guest_id, guest_name, task_type, "completed", location)
	report.additional_context = additional_context
	
	task_reports.append(report)
	_update_guest_report(guest_id, guest_name, report)
	_update_daily_summary(report)
	
	task_reported.emit(report)
	return report


func report_task_failure(guest_id: String, guest_name: String, task_type: String, failure_reason: String, location: String, additional_context: Dictionary) -> TaskReport:
	var report = TaskReport.new(guest_id, guest_name, task_type, "failed", location)
	report.failure_reason = failure_reason
	report.additional_context = additional_context
	
	task_reports.append(report)
	_update_guest_report(guest_id, guest_name, report)
	_update_daily_summary(report)
	
	# Check if this failure should generate an alert
	# _check_task_failure_alert(report)
	
	task_reported.emit(report)
	return report

func report_mood(guest_id: String, guest_name: String, mood_type: String, intensity: int, trigger: String, location: String, context: String = "", room_number: String = "") -> MoodReport:
	var report = MoodReport.new(guest_id, guest_name, mood_type, intensity, trigger, location)
	report.context = context
	report.room_number = room_number
	
	mood_reports.append(report)
	_update_guest_mood(guest_id, guest_name, report)
	_update_daily_summary_mood(report)
	
	# Check if this mood should generate an alert
	_check_mood_alert(report)
	
	mood_reported.emit(report)
	return report



func generate_alert(alert_type: String, severity: String, guest_id: String, guest_name: String, message: String, location: String) -> RealTimeAlert:
	var alert = RealTimeAlert.new(alert_type, severity, guest_id, guest_name, message, location)
	
	if severity == "critical":
		alert.requires_immediate_action = true
	
	real_time_alerts.append(alert)
	alert_generated.emit(alert)
	
	return alert


#func _check_task_failure_alert(report: TaskReport):
	## Check for consecutive failures
	#var recent_failures = _get_recent_guest_task_failures(report.guest_id, 5)
	#if recent_failures.size() >= alert_thresholds["consecutive_failures"]:
		#generate_alert(
			#"critical_failure",
			#"high",
			#report.guest_id,
			#report.guest_name,
			#"Guest has experienced %d consecutive task failures" % recent_failures.size(),
			#report.location
		#)


func _check_mood_alert(report: MoodReport):
	# Check for negative moods with high intensity
	var negative_moods = ["frustrated", "angry", "disappointed", "upset", "annoyed"]
	if report.mood_type in negative_moods and report.intensity >= alert_thresholds["negative_mood_intensity"]:
		var severity = "critical" if report.intensity >= 9 else "high"
		generate_alert(
			"negative_mood",
			severity,
			report.guest_id,
			report.guest_name,
			"Guest is experiencing %s (intensity: %d) - %s" % [report.mood_type, report.intensity, report.trigger],
			report.location
		)


func get_active_alerts(severity_filter: String = "") -> Array[RealTimeAlert]:
	if severity_filter.is_empty():
		return real_time_alerts.duplicate()
	
	var filtered: Array[RealTimeAlert] = []
	for alert in real_time_alerts:
		if alert.severity == severity_filter:
			filtered.append(alert)
	return filtered


func clear_alert(alert: RealTimeAlert):
	real_time_alerts.erase(alert)


func clear_all_alerts():
	real_time_alerts.clear()


# ============================================================================
# DAILY SUMMARY METHODS
# ============================================================================

func generate_daily_summary(date: Dictionary) -> DailySummary:
	if date.is_empty():
		date = DayAndNightCycleManager.get_current_time()
		date = {"day": date.day, "year": 1900}
	
	if date in daily_summaries:
		return daily_summaries[date]
	
	var summary = DailySummary.new(date)
	daily_summaries[date] = summary
	
	# Compile data for this date
	_compile_daily_summary(summary)
	
	daily_summary_generated.emit(summary)
	return summary


func get_daily_summary(date: Dictionary = {}) -> DailySummary:
	if date.is_empty():
		date = DayAndNightCycleManager.get_current_time()
		date = {"day": date.day, "year": 1900}
	
	if date in daily_summaries:
		return daily_summaries[date]
	
	return generate_daily_summary(date)


func _update_daily_summary(report: TaskReport):
	var date = DayAndNightCycleManager.get_current_time()
	date = {"day": date.day, "year": 1900}
	
	if not date in daily_summaries:
		daily_summaries[date] = DailySummary.new(date)
	
	var summary = daily_summaries[date]
	summary.total_tasks_attempted += 1
	
	if report.status == "completed":
		summary.total_tasks_completed += 1
	else:
		summary.total_tasks_failed += 1
	
	# Update task breakdown
	if not report.task_type in summary.task_breakdown:
		summary.task_breakdown[report.task_type] = {"completed": 0, "failed": 0}
	
	if report.status == "completed":
		summary.task_breakdown[report.task_type]["completed"] += 1
	else:
		summary.task_breakdown[report.task_type]["failed"] += 1
	
	summary.calculate_metrics()


func _update_daily_summary_mood(report: MoodReport):
	var date = DayAndNightCycleManager.get_current_time()
	
	if not date in daily_summaries:
		daily_summaries[date] = DailySummary.new(date)
	
	var summary = daily_summaries[date]
	
	# Update mood breakdown
	if not report.mood_type in summary.mood_breakdown:
		summary.mood_breakdown[report.mood_type] = 0
	summary.mood_breakdown[report.mood_type] += 1
	
	# Categorize mood as positive/negative/neutral
	var positive_moods = ["happy", "satisfied", "delighted", "content", "pleased"]
	var negative_moods = ["frustrated", "angry", "disappointed", "upset", "annoyed", "bored"]
	
	if report.mood_type in positive_moods:
		summary.positive_moods_count += 1
	elif report.mood_type in negative_moods:
		summary.negative_moods_count += 1
	else:
		summary.neutral_moods_count += 1


func _compile_daily_summary(summary: DailySummary):
	print("compiling summary")
	return {"summary": "cuckery"}
	
# ============================================================================
# PER-GUEST REPORT METHODS
# ============================================================================

func get_guest_report(guest_id: String) -> PerGuestReport:
	if guest_id in per_guest_reports:
		return per_guest_reports[guest_id]
	return null


func create_guest_report(guest_id: String, guest_name: String) -> PerGuestReport:
	var report = PerGuestReport.new(guest_id, guest_name)
	per_guest_reports[guest_id] = report
	return report


func finalize_guest_report(guest_id: String):
	if guest_id in per_guest_reports:
		var report = per_guest_reports[guest_id]
		report.check_out_time = Time.get_unix_time_from_system()
		report.calculate_metrics()


func _update_guest_report(guest_id: String, guest_name: String, task_report: TaskReport):
	if not guest_id in per_guest_reports:
		per_guest_reports[guest_id] = PerGuestReport.new(guest_id, guest_name)
	
	var guest_report = per_guest_reports[guest_id]
	guest_report.total_tasks_attempted += 1
	
	if task_report.status == "completed":
		guest_report.total_tasks_completed += 1
	else:
		guest_report.total_tasks_failed += 1
		guest_report.complaints.append(task_report.failure_reason)
	
	guest_report.task_history.append(task_report.to_dict())
	
	if not task_report.location in guest_report.areas_visited:
		guest_report.areas_visited.append(task_report.location)
	
	guest_report.calculate_metrics()


func _update_guest_mood(guest_id: String, guest_name: String, mood_report: MoodReport):
	if not guest_id in per_guest_reports:
		per_guest_reports[guest_id] = PerGuestReport.new(guest_id, guest_name)
	
	var guest_report = per_guest_reports[guest_id]
	guest_report.mood_history.append(mood_report.to_dict())
	
	if mood_report.intensity > guest_report.highest_mood:
		guest_report.highest_mood = mood_report.intensity
	
	if mood_report.intensity < guest_report.lowest_mood:
		guest_report.lowest_mood = mood_report.intensity
	
	guest_report.calculate_metrics()


func get_all_guest_reports() -> Array[PerGuestReport]:
	var reports: Array[PerGuestReport] = []
	for guest_id in per_guest_reports:
		reports.append(per_guest_reports[guest_id])
	return reports


# ============================================================================
# HISTORICAL TREND METHODS
# ============================================================================

func generate_historical_trend(start_date: String, end_date: String, trend_type: String = "task_success") -> HistoricalTrend:
	var trend = HistoricalTrend.new(start_date, end_date)
	trend.trend_type = trend_type
	
	# Gather daily summaries within the date range
	for date in daily_summaries:
		if _is_date_in_range(date, start_date, end_date):
			trend.daily_summaries.append(daily_summaries[date])
	
	trend.calculate_trends()
	historical_trends.append(trend)
	
	return trend


func get_trend_by_type(trend_type: String) -> Array[HistoricalTrend]:
	var trends: Array[HistoricalTrend] = []
	for trend in historical_trends:
		if trend.trend_type == trend_type:
			trends.append(trend)
	return trends
	
func export_reports_to_json() -> String:
	var export_data = {
		"task_reports": [],
		"mood_reports": [],
		"daily_summaries": {},
		"guest_reports": {}
	}
	
	for report in task_reports:
		export_data["task_reports"].append(report.to_dict())
	
	for report in mood_reports:
		export_data["mood_reports"].append(report.to_dict())
	
	for date in daily_summaries:
		export_data["daily_summaries"][date] = daily_summaries[date].to_dict()
	
	for guest_id in per_guest_reports:
		export_data["guest_reports"][guest_id] = per_guest_reports[guest_id].to_dict()
	
	return JSON.stringify(export_data, "\t")
	
func _is_date_in_range(date: String, start: String, end: String) -> bool:
	return date >= start and date <= end
