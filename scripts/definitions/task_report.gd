extends RefCounted
class_name TaskReport

var guest_id: String
var guest_name: String
var task_type: String
var status: String  # "completed" or "failed"
var failure_reason: String = ""
var timestamp: float
var location: String
var zone: String = ""
var staff_involved: String = ""
var additional_context: Dictionary = {}

func _init(g_id: String, g_name: String, task: String, stat: String, loc: String) -> void:
	guest_id = g_id
	guest_name = g_name
	task_type = task
	status = stat
	location = loc
	timestamp = Time.get_unix_time_from_system()

func to_dict() -> Dictionary:
	return {
		"guest_id": guest_id,
		"guest_name": guest_name,
		"task_type": task_type,
		"status": status,
		"failure_reason": failure_reason,
		"timestamp": timestamp,
		"location": location,
		"zone": zone,
		"staff_involved": staff_involved,
		"additional_context": additional_context
	}
