# npc_state.gd
# Simple, clean state representation for NPCs
class_name NPCState
extends RefCounted

enum Type {
	IDLE,           # Waiting for next schedule entry
	NAVIGATING,     # Moving to any destination
	PERFORMING_ACTIONS, # Executing scheduled actions
	WAITING         # Blocked or paused
}

var type: Type = Type.IDLE
var context: Dictionary = {}  # All state-specific data

signal state_changed(old_type: Type, new_type: Type)

func change_to(new_type: Type, new_context: Dictionary = {}) -> void:
	if type == new_type:
		return
	
	var old_type = type
	type = new_type
	context = new_context
	
	emit_signal("state_changed", old_type, new_type)

func is_busy() -> bool:
	return type != Type.IDLE and type != Type.WAITING

func get_name() -> String:
	return Type.keys()[type]

func toString() -> String:
	var ctx_str = ""
	if context.size() > 0:
		ctx_str = " (" + str(context) + ")"
	return get_name() + ctx_str
