class_name NPCSimulationStatessss

var npc_id: String
var npc_type: String
var npc_name: String

# Position & Movement
var current_floor: int = 1
var current_position: Vector2
var target_position: Vector2
var speed: float

# State Machine (simplified)
var state: NPCState
var navigation: NPCNavigation

# Schedule
var schedule: Array[ScheduleEntry] = []
var active_entry: ScheduleEntry = null
var current_action_index: int = 0

# Travel tracking
var travel_start_time: float = 0.0
var travel_duration: float = 0.0

# Optional visual instance
var npc_instance: Node = null

# Custom behavior data
var behavior_data: Dictionary = {}

func _init(id: String, type: String, name: String, pos: Vector2, spd: float) -> void:
	npc_id = id
	npc_type = type
	npc_name = name
	current_position = pos
	target_position = pos
	speed = spd
	state = NPCState.new()
	navigation = NPCNavigation.new(self)

func is_idle() -> bool:
	return state.type == NPCState.Type.IDLE

func is_busy() -> bool:
	return state.is_busy()

func debug_info() -> String:
	return """
	NPC: %s (%s)
	State: %s
	Floor: %d
	Position: %s
	Schedule Entry: %s
	Actions: %d/%d
	Navigation: %s
	""" % [
		npc_name, npc_id,
		state.get_name(),
		current_floor,
		current_position,
		active_entry.id if active_entry else "None",
		current_action_index,
		active_entry.actions.size() if active_entry else 0,
		navigation.to_string()
	]
