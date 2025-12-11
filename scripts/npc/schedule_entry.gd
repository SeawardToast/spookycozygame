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

## Check if this entry should be active at current time
func is_active(current_minute: int) -> bool:
	return (current_minute >= start_minute and 
			current_minute < end_minute and 
			not completed_today)

## Mark this entry as completed for today
func mark_complete() -> void:
	completed_today = true

## Reset for a new day
func reset() -> void:
	completed_today = false

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
	
