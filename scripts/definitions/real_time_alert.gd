extends RefCounted
class_name RealTimeAlert

var alert_type: String  # "critical_failure", "negative_mood", "service_issue"
var severity: String  # "low", "medium", "high", "critical"
var guest_id: String
var guest_name: String
var message: String
var timestamp: float
var location: String
var requires_immediate_action: bool = false

func _init(type: String, sev: String, g_id: String, g_name: String, msg: String, loc: String) -> void:
	alert_type = type
	severity = sev
	guest_id = g_id
	guest_name = g_name
	message = msg
	location = loc
	timestamp = Time.get_unix_time_from_system()

func to_dict() -> Dictionary:
	return {
		"alert_type": alert_type,
		"severity": severity,
		"guest_id": guest_id,
		"guest_name": guest_name,
		"message": message,
		"timestamp": timestamp,
		"location": location,
		"requires_immediate_action": requires_immediate_action
	}
