# npc_action.gd
# Structured action that NPCs can perform
class_name NPCAction
extends RefCounted

var action_id: String
var display_name: String
var callback: Callable
var duration: float = 0.0  # For future time-based actions
var metadata: Dictionary = {}  # Additional data

func _init(id: String = "", name: String = "", fn: Callable = Callable()):
	action_id = id
	display_name = name
	callback = fn

## Execute the action and return structured result
func execute() -> Dictionary:
	var result = {
		"success": false, 
		"reason": "",
		"action_id": action_id,
		"action_name": display_name
	}
	
	if not callback.is_valid():
		result.reason = "Invalid callback"
		return result
	
	var callback_result = callback.call()
	
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
	
	return result

## Static helper to create actions easily
static func create(id: String, name: String, fn: Callable) -> NPCAction:
	return NPCAction.new(id, name, fn)
