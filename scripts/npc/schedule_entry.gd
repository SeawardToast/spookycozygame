# schedule_entry.gd
# Represents a single scheduled activity for an NPC
extends RefCounted
class_name ScheduleEntry

var id: String  # Unique identifier (e.g., "morning_breakfast")
var start_minute: int  # Start time in minutes from midnight (0-1439)
var end_minute: int  # End time in minutes from midnight
var zone_name: String  # Where to go
var actions: Array[Variant] = []  # What to do when there
var priority: int = 0  # For future conflict resolution
var can_interrupt: bool = false  # Can player interrupt this?
var completed_today: bool = false  # Tracks daily completion
var completion_day: int = -1  # Track which day this was completed on (for overnight schedules)

func _init(
	entry_id: String = "", 
	start: int = 0, 
	end: int = 0, 
	zone: String = ""
) -> void:
	id = entry_id
	start_minute = start
	end_minute = end
	zone_name = zone

## Check if this entry should be active at current time (with day awareness for overnight)
func is_active(current_minute: int, current_day: int = -1) -> bool:
	var is_in_time_range: bool = false
	
	# Handle overnight schedules (e.g., 22:00-02:00 spans midnight)
	if end_minute <= start_minute:
		# Overnight schedule: active if current time is after start OR before end
		is_in_time_range = (current_minute >= start_minute) or (current_minute < end_minute)
	else:
		# Normal schedule: active if between start and end
		is_in_time_range = (current_minute >= start_minute) and (current_minute < end_minute)
	
	# For overnight schedules that have been completed, check if we're on a new day
	var not_completed: bool = not completed_today
	if completed_today and current_day != -1 and completion_day != -1:
		# If it's a new day, allow reactivation
		if current_day > completion_day:
			not_completed = true
	
	return is_in_time_range and not_completed

## Mark this entry as completed for today
func mark_complete(current_day: int = -1) -> void:
	completed_today = true
	if current_day != -1:
		completion_day = current_day

## Check if this is an overnight schedule (spans midnight)
func is_overnight() -> bool:
	return end_minute <= start_minute

## Get the actual duration in minutes (handles overnight)
func get_duration_minutes() -> int:
	if is_overnight():
		# Overnight: time until midnight + time after midnight
		return (1440 - start_minute) + end_minute
	else:
		# Normal: simple subtraction
		return end_minute - start_minute

## Reset for a new day
func reset() -> void:
	completed_today = false
	completion_day = -1

## Add an action to this schedule entry
func add_action(action: Variant) -> ScheduleEntry:
	actions.append(action)
	return self  # For chaining

## Static helper to create schedule entries easily
static func create(id: String, start: int, end: int, zone: String) -> ScheduleEntry:
	return ScheduleEntry.new(id, start, end, zone)

## Get human-readable time string
func get_time_range() -> String:
	var start_hour: int = start_minute / 60
	var start_min: int = start_minute % 60
	var end_hour: int = end_minute / 60
	var end_min: int = end_minute % 60
	return "%02d:%02d - %02d:%02d" % [start_hour, start_min, end_hour, end_min]

## Serialization support
func to_dict() -> Dictionary:
	return {
		"id": id,
		"start_minute": start_minute,
		"end_minute": end_minute,
		"zone_name": zone_name,
		"priority": priority,
		"can_interrupt": can_interrupt,
		"completed_today": completed_today,
		"completion_day": completion_day
	}

func from_dict(data: Dictionary) -> void:
	id = data.get("id", id)
	start_minute = data.get("start_minute", start_minute)
	end_minute = data.get("end_minute", end_minute)
	zone_name = data.get("zone_name", zone_name)
	priority = data.get("priority", 0)
	can_interrupt = data.get("can_interrupt", false)
	completed_today = data.get("completed_today", false)
	completion_day = data.get("completion_day", -1)

## String representation for debugging
func toString() -> String:
	return "%s: %s at %s (completed: %s)" % [
		id,
		zone_name,
		get_time_range(),
		"yes" if completed_today else "no"
	]
