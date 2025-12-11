class_name NPCSimulationState

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
