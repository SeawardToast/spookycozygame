extends RefCounted
class_name MoodReport

var guest_id: String
var guest_name: String
var mood_type: String  # "happy", "frustrated", "angry", "satisfied", "bored", etc.
var intensity: int  # 1-10 scale
var trigger: String
var context: String
var timestamp: float
var location: String
var zone: String = ""

func _init(g_id: String, g_name: String, mood: String, intens: int, trig: String, loc: String):
	guest_id = g_id
	guest_name = g_name
	mood_type = mood
	intensity = clamp(intens, 1, 10)
	trigger = trig
	location = loc
	timestamp = Time.get_unix_time_from_system()

func to_dict() -> Dictionary:
	return {
		"guest_id": guest_id,
		"guest_name": guest_name,
		"mood_type": mood_type,
		"intensity": intensity,
		"trigger": trigger,
		"context": context,
		"timestamp": timestamp,
		"location": location,
		"zone": zone
	}
