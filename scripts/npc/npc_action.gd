# npc_action.gd
# Structured action that NPCs can perform with duration support
class_name NPCAction
extends RefCounted

var action_id: String
var display_name: String
var callback: Callable
var duration: float = 0.0  # Duration in game minutes
var metadata: Dictionary = {}  # Additional data

# Internal tracking for time-based actions
var _start_game_day: int = 0
var _start_game_minute: int = 0  # Minutes from midnight (0-1439)
var _is_executing: bool = false
var _execution_result: Dictionary = {}

func _init(id: String = "", name: String = "", fn: Callable = Callable(), dur: float = 0.0) -> void:
	action_id = id
	display_name = name
	callback = fn
	duration = dur

## Execute the action and return structured result
func execute() -> Dictionary:
	var result: Dictionary = {
		"success": false, 
		"reason": "",
		"action_id": action_id,
		"action_name": display_name,
		"duration": duration,
		"requires_waiting": duration > 0.0
	}
	
	if not callback.is_valid():
		result.reason = "Invalid callback"
		return result
	
	# FIX #2: Store day AND minute separately for proper day rollover handling
	_is_executing = true
	if DayAndNightCycleManager:
		var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
		_start_game_day = current_time.day
		_start_game_minute = current_time.hour * 60 + current_time.minute
	else:
		# Fallback if manager not available
		_start_game_day = 0
		_start_game_minute = 0
	
	var callback_result: Variant = callback.call()
	
	# Handle different return types
	if typeof(callback_result) == TYPE_DICTIONARY:
		# Callback returned full result dictionary
		result.merge(callback_result, true)
	elif typeof(callback_result) == TYPE_ARRAY and callback_result.size() >= 2:
		# Callback returned [success, reason]
		result.success = callback_result[0]
		result.reason = callback_result[1]
	elif typeof(callback_result) == TYPE_BOOL:
		# Callback returned just success bool
		result.success = callback_result
	else:
		# Assume success if callback completed
		result.success = true
	
	_execution_result = result
	return result

## FIX #2: Check if action duration has elapsed with proper day rollover handling
func is_duration_complete() -> bool:
	if duration <= 0.0:
		return true  # Instant actions are always complete
	
	if not _is_executing:
		return false  # Haven't started yet
	
	if not DayAndNightCycleManager:
		return true  # Can't track time, assume complete
	
	var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
	var current_day: int = current_time.day
	var current_minute: int = current_time.hour * 60 + current_time.minute
	
	# Calculate elapsed minutes handling day rollover
	var elapsed: float = _calculate_elapsed_minutes(
		_start_game_day, 
		_start_game_minute, 
		current_day, 
		current_minute
	)
	
	return elapsed >= duration

## FIX #2: Helper to calculate elapsed minutes with day rollover
func _calculate_elapsed_minutes(start_day: int, start_minute: int, current_day: int, current_minute: int) -> float:
	const MINUTES_PER_DAY: int = 1440
	
	# Same day - simple subtraction
	if current_day == start_day:
		return float(current_minute - start_minute)
	
	# Different days - account for day rollover
	var days_passed: int = current_day - start_day
	var minutes_in_full_days: float = float(days_passed) * float(MINUTES_PER_DAY)
	var minutes_in_partial_days: float = float(current_minute - start_minute)
	
	return minutes_in_full_days + minutes_in_partial_days

## Get how much time is remaining (in game minutes)
func get_remaining_duration() -> float:
	if duration <= 0.0:
		return 0.0
	
	if not _is_executing:
		return duration
	
	if not DayAndNightCycleManager:
		return 0.0
	
	var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
	var current_day: int = current_time.day
	var current_minute: int = current_time.hour * 60 + current_time.minute
	
	var elapsed: float = _calculate_elapsed_minutes(
		_start_game_day, 
		_start_game_minute, 
		current_day, 
		current_minute
	)
	
	return max(0.0, duration - elapsed)

## Get progress (0.0 to 1.0)
func get_progress() -> float:
	if duration <= 0.0:
		return 1.0  # Instant actions are 100% complete
	
	if not _is_executing:
		return 0.0
	
	if not DayAndNightCycleManager:
		return 1.0
	
	var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
	var current_day: int = current_time.day
	var current_minute: int = current_time.hour * 60 + current_time.minute
	
	var elapsed: float = _calculate_elapsed_minutes(
		_start_game_day, 
		_start_game_minute, 
		current_day, 
		current_minute
	)
	
	return clamp(elapsed / duration, 0.0, 1.0)

## Mark action as complete and reset state
func complete() -> void:
	_is_executing = false
	_start_game_day = 0
	_start_game_minute = 0

## Reset action state (for reuse)
func reset() -> void:
	_is_executing = false
	_start_game_day = 0
	_start_game_minute = 0
	_execution_result.clear()

## FIX #6: Serialization support for action state
func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"display_name": display_name,
		"duration": duration,
		"metadata": metadata,
		"_start_game_day": _start_game_day,
		"_start_game_minute": _start_game_minute,
		"_is_executing": _is_executing,
		"_execution_result": _execution_result
	}

## FIX #6: Deserialization support for action state
func restore_from_dict(data: Dictionary) -> void:
	# Note: action_id, display_name, callback are already set from schedule
	# We only restore the execution state
	_start_game_day = data.get("_start_game_day", 0)
	_start_game_minute = data.get("_start_game_minute", 0)
	_is_executing = data.get("_is_executing", false)
	_execution_result = data.get("_execution_result", {})
	
	# Optional: restore duration if it was modified
	if data.has("duration"):
		duration = data.get("duration", duration)

## Static helper to create actions easily
static func create(id: String, name: String, fn: Callable, dur: float = 0.0) -> NPCAction:
	return NPCAction.new(id, name, fn, dur)

## Static helper to create instant action (explicit)
static func create_instant(id: String, name: String, fn: Callable) -> NPCAction:
	return NPCAction.new(id, name, fn, 0.0)

## Static helper to create timed action (explicit, duration in game minutes)
static func create_timed(id: String, name: String, fn: Callable, minutes: float) -> NPCAction:
	return NPCAction.new(id, name, fn, minutes)

## String representation for debugging
func toString() -> String:
	if duration > 0.0:
		if _is_executing:
			return "%s (%s) - Duration: %.1f game minutes (%.0f%% complete)" % [
				display_name, 
				action_id, 
				duration,
				get_progress() * 100.0
			]
		else:
			return "%s (%s) - Duration: %.1f game minutes" % [display_name, action_id, duration]
	else:
		return "%s (%s) - Instant" % [display_name, action_id]
