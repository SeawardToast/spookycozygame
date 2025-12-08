# NPCStateMachine.gd
# Lightweight state machine for simulated NPCs
class_name NPCStateMachine

enum State {
	IDLE,
	TRAVELING_TO_ZONE,
	TRAVELING_TO_STAIRS,
	CHANGING_FLOORS,
	PERFORMING_ACTIONS,
	WAITING
}

var current_state: State = State.IDLE
var previous_state: State = State.IDLE
var state_data: Dictionary = {} # Store state-specific data
var npc_state: NPCSimulationManager.NPCSimulationState

signal state_changed(old_state: State, new_state: State)

func _init(npc_sim_state: NPCSimulationManager.NPCSimulationState):
	npc_state = npc_sim_state

func change_state(new_state: State, data: Dictionary = {}) -> void:
	if current_state == new_state:
		return
	
	_exit_state(current_state)
	previous_state = current_state
	current_state = new_state
	state_data = data
	_enter_state(new_state)
	
	emit_signal("state_changed", previous_state, current_state)

func _enter_state(state: State) -> void:
	match state:
		State.IDLE:
			print("%s entered IDLE state" % npc_state.npc_name)
		
		State.TRAVELING_TO_ZONE:
			print("%s traveling to zone: %s" % [npc_state.npc_name, state_data.get("zone_name", "unknown")])
			npc_state.is_traveling = true
		
		State.TRAVELING_TO_STAIRS:
			print("%s traveling to stairs (floor %d, direction: %s)" % 
				[npc_state.npc_name, state_data.get("floor", 0), state_data.get("direction", "unknown")])
			npc_state.is_traveling = true
			npc_state.is_changing_floors = true
		
		State.CHANGING_FLOORS:
			print("%s changing floors" % npc_state.npc_name)
			_handle_floor_change()
		
		State.PERFORMING_ACTIONS:
			print("%s performing actions at %s" % [npc_state.npc_name, state_data.get("location", "unknown")])
		
		State.WAITING:
			print("%s waiting (reason: %s)" % [npc_state.npc_name, state_data.get("reason", "scheduled")])

func _exit_state(state: State) -> void:
	match state:
		State.TRAVELING_TO_ZONE, State.TRAVELING_TO_STAIRS:
			npc_state.is_traveling = false
		
		State.CHANGING_FLOORS:
			npc_state.is_changing_floors = false

func _handle_floor_change() -> void:
	var direction = state_data.get("direction", "")
	if direction == "up":
		npc_state.current_floor += 1
	elif direction == "down":
		npc_state.current_floor -= 1
	
	print("%s now on floor %d" % [npc_state.npc_name, npc_state.current_floor])

func update(delta: float, current_time: float) -> void:
	match current_state:
		State.TRAVELING_TO_ZONE, State.TRAVELING_TO_STAIRS:
			_update_travel(delta, current_time)
		
		State.PERFORMING_ACTIONS:
			if state_data.get("actions_completed", false):
				change_state(State.IDLE)

func _update_travel(delta: float, current_time: float) -> void:
	var elapsed = current_time - npc_state.travel_start_time
	
	if elapsed >= npc_state.travel_duration:
		# Travel complete
		npc_state.current_position = npc_state.target_position
		_handle_arrival()
	else:
		# Update position
		var progress = elapsed / npc_state.travel_duration
		npc_state.current_position = npc_state.current_position.lerp(
			npc_state.target_position, 
			progress * delta * 60.0
		)

func _handle_arrival() -> void:
	if current_state == State.TRAVELING_TO_STAIRS:
		change_state(State.CHANGING_FLOORS, {
			"direction": state_data.get("direction", ""),
			"final_zone_name": state_data.get("final_zone_name", ""),
			"actions": state_data.get("actions", [])
		})
	
	elif current_state == State.TRAVELING_TO_ZONE:
		change_state(State.PERFORMING_ACTIONS, {
			"location": npc_state.current_target_zone_name,
			"actions": state_data.get("actions", [])
		})

func get_state_name() -> String:
	return State.keys()[current_state]

func is_busy() -> bool:
	return current_state != State.IDLE and current_state != State.WAITING
