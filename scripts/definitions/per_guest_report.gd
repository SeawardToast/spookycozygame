extends RefCounted
class_name PerGuestReport

var guest_id: String
var guest_name: String
var check_in_time: float
var check_out_time: float = 0.0
var total_tasks_attempted: int = 0
var total_tasks_completed: int = 0
var total_tasks_failed: int = 0
var task_success_rate: float = 0.0
var mood_history: Array[Dictionary] = []
var average_mood: float = 0.0
var highest_mood: int = 0
var lowest_mood: int = 10
var task_history: Array[Dictionary] = []
var complaints: Array[String] = []
var satisfaction_score: float = 0.0
var areas_visited: Array[String] = []

func _init(g_id: String, g_name: String):
	guest_id = g_id
	guest_name = g_name
	check_in_time = Time.get_unix_time_from_system()

func calculate_metrics():
	if total_tasks_attempted > 0:
		task_success_rate = (float(total_tasks_completed) / float(total_tasks_attempted)) * 100.0
	
	if mood_history.size() > 0:
		var mood_sum = 0.0
		for mood in mood_history:
			mood_sum += mood.intensity
		average_mood = mood_sum / mood_history.size()

func to_dict() -> Dictionary:
	return {
		"guest_id": guest_id,
		"guest_name": guest_name,
		"check_in_time": check_in_time,
		"check_out_time": check_out_time,
		"total_tasks_attempted": total_tasks_attempted,
		"total_tasks_completed": total_tasks_completed,
		"total_tasks_failed": total_tasks_failed,
		"task_success_rate": task_success_rate,
		"mood_history": mood_history,
		"average_mood": average_mood,
		"highest_mood": highest_mood,
		"lowest_mood": lowest_mood,
		"task_history": task_history,
		"complaints": complaints,
		"satisfaction_score": satisfaction_score,
		"areas_visited": areas_visited
	}
