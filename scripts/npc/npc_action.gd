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
var _start_game_time: float = 0.0
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
	
	# Start execution using game time
	_is_executing = true
	if DayAndNightCycleManager:
		var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
		_start_game_time = current_time.day * 1440.0 + current_time.hour * 60.0 + current_time.minute
	else:
		# Fallback if manager not available
		_start_game_time = 0.0
	
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

## Check if action duration has elapsed (in game time)
func is_duration_complete() -> bool:
	if duration <= 0.0:
		return true  # Instant actions are always complete
	
	if not _is_executing:
		return false  # Haven't started yet
	
	if not DayAndNightCycleManager:
		return true  # Can't track time, assume complete
	
	var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
	var current_game_time: float = current_time.day * 1440.0 + current_time.hour * 60.0 + current_time.minute
	var elapsed: float = current_game_time - _start_game_time
	
	return elapsed >= duration

## Get how much time is remaining (in game minutes)
func get_remaining_duration() -> float:
	if duration <= 0.0:
		return 0.0
	
	if not _is_executing:
		return duration
	
	if not DayAndNightCycleManager:
		return 0.0
	
	var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
	var current_game_time: float = current_time.day * 1440.0 + current_time.hour * 60.0 + current_time.minute
	var elapsed: float = current_game_time - _start_game_time
	
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
	var current_game_time: float = current_time.day * 1440.0 + current_time.hour * 60.0 + current_time.minute
	var elapsed: float = current_game_time - _start_game_time
	
	return clamp(elapsed / duration, 0.0, 1.0)

## Mark action as complete and reset state
func complete() -> void:
	_is_executing = false
	_start_game_time = 0.0

## Reset action state (for reuse)
func reset() -> void:
	_is_executing = false
	_start_game_time = 0.0
	_execution_result.clear()

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
		return "%s (%s) - Duration: %.1f game minutes" % [display_name, action_id, duration]
	else:
		return "%s (%s) - Instant" % [display_name, action_id]
