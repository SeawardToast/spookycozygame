extends RefCounted
class_name DailySummary

var date: Dictionary
var total_tasks_attempted: int = 0
var total_tasks_completed: int = 0
var total_tasks_failed: int = 0
var success_rate: float = 0.0
var average_guest_mood: float = 0.0
var total_guests: int = 0
var most_common_failure_reason: String = ""
var most_problematic_area: String = ""
var positive_moods_count: int = 0
var negative_moods_count: int = 0
var neutral_moods_count: int = 0
var alerts_generated: int = 0
var task_breakdown: Dictionary = {}  # task_type: {completed: int, failed: int}
var mood_breakdown: Dictionary = {}  # mood_type: count

func _init(d: Dictionary) -> void:
	date = d

func calculate_metrics() -> void:
	if total_tasks_attempted > 0:
		success_rate = (float(total_tasks_completed) / float(total_tasks_attempted)) * 100.0

func to_dict() -> Dictionary:
	return {
		"date": date,
		"total_tasks_attempted": total_tasks_attempted,
		"total_tasks_completed": total_tasks_completed,
		"total_tasks_failed": total_tasks_failed,
		"success_rate": success_rate,
		"average_guest_mood": average_guest_mood,
		"total_guests": total_guests,
		"most_common_failure_reason": most_common_failure_reason,
		"most_problematic_area": most_problematic_area,
		"positive_moods_count": positive_moods_count,
		"negative_moods_count": negative_moods_count,
		"neutral_moods_count": neutral_moods_count,
		"alerts_generated": alerts_generated,
		"task_breakdown": task_breakdown,
		"mood_breakdown": mood_breakdown
	}
