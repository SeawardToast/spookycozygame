# NPCSimulationManager.gd
# Refactored with clean architecture
extends Node

var simulated_npcs: Dictionary = {}
var npc_id_counter: int = 0

signal npc_spawned(npc_id: String, npc_type: String, position: Vector2)
signal npc_despawned(npc_id: String)
signal npc_state_changed(npc_id: String, old_state: int, new_state: int)
signal npc_arrived_at_zone(npc_id: String, zone_name: String, position: Vector2)
signal npc_waypoint_reached(npc_id: String, waypoint_type: String, position: Vector2)
signal npc_action_attempted(npc_id: String, action: NPCAction, success: bool)
signal npc_started_traveling(npc_id: String, from_pos: Vector2, to_pos: Vector2, destination: String)

	
	func _init(id: String, type: String, name: String, pos: Vector2, spd: float):
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

func _ready():
	if DayAndNightCycleManager:
		DayAndNightCycleManager.time_tick.connect(_on_time_tick)

func _generate_npc_id(npc_type: String) -> String:
	npc_id_counter += 1
	return "%s_%d" % [npc_type, npc_id_counter]

## Spawn an NPC using the type registry
func spawn_npc(npc_type: String, spawn_position: Vector2 = Vector2.ZERO) -> String:
	var npc_definition = NPCTypeRegistry.create_npc_definition(npc_type)
	if npc_definition == null:
		push_error("Unknown NPC type: %s" % npc_type)
		return ""
	
	var npc_id = _generate_npc_id(npc_type)
	var start_pos = spawn_position if spawn_position != Vector2.ZERO else npc_definition.start_position
	
	# Create simulation state
	var state = NPCSimulationState.new(
		npc_id,
		npc_type,
		npc_definition.npc_name,
		start_pos,
		npc_definition.speed
	)
	
	# Store definition reference
	state.behavior_data["definition"] = npc_definition
	
	state.schedule = npc_definition.get_schedule()
	# Connect state change signal
	state.state.state_changed.connect(
		func(old_state, new_state):
			_on_npc_state_changed(npc_id, old_state, new_state)
	)
	
	simulated_npcs[npc_id] = state
	emit_signal("npc_spawned", npc_id, npc_type, start_pos)
	
	print("Spawned NPC: %s (%s) at %s" % [state.npc_name, npc_type, start_pos])
	return npc_id

## Despawn an NPC
func despawn_npc(npc_id: String) -> void:
	var state = simulated_npcs.get(npc_id)
	if state == null:
		return
	
	if state.npc_instance != null:
		state.npc_instance.queue_free()
	
	simulated_npcs.erase(npc_id)
	emit_signal("npc_despawned", npc_id)
	print("Despawned NPC: %s" % npc_id)

## Get NPC state
func get_npc_state(npc_id: String) -> NPCSimulationState:
	return simulated_npcs.get(npc_id)

## Get all NPC states
func get_all_npc_states() -> Dictionary:
	return simulated_npcs

## Get NPCs by type
func get_npcs_by_type(npc_type: String) -> Array:
	var npcs = []
	for npc_id in simulated_npcs:
		var state = simulated_npcs[npc_id]
		if state.npc_type == npc_type:
			npcs.append(state)
	return npcs

## Get NPC count
func get_npc_count() -> int:
	return simulated_npcs.size()

## Get NPC count by type
func get_npc_count_by_type(npc_type: String) -> int:
	return get_npcs_by_type(npc_type).size()

func _on_npc_state_changed(npc_id: String, old_state: int, new_state: int) -> void:
	emit_signal("npc_state_changed", npc_id, old_state, new_state)
	
	var state = get_npc_state(npc_id)
	if state:
		print("%s: %s -> %s" % [
			state.npc_name,
			NPCState.Type.keys()[old_state],
			NPCState.Type.keys()[new_state]
		])

## Main update loop
func _process(delta: float) -> void:
	for npc_id in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		_update_npc(npc, delta)

## Update individual NPC
func _update_npc(npc: NPCSimulationState, delta: float) -> void:
	match npc.state.type:
		NPCState.Type.NAVIGATING:
			_update_navigation(npc, delta)
		
		NPCState.Type.PERFORMING_ACTIONS:
			_update_actions(npc, delta)

## Update NPC navigation
## This is purely for simulation purposes unless the NPC is rendered, then we take that current position to account for collisions, and A* pathfinding
func _update_navigation(npc: NPCSimulationState, delta: float) -> void:
	# If visual NPC exists with navigation agent, use its position as source of truth
	if npc.npc_instance != null and npc.npc_instance.navigation_agent_2d != null:
		npc.current_position = npc.npc_instance.global_position
		
		# Check if navigation agent has reached destination
		if npc.npc_instance.navigation_agent_2d.is_navigation_finished():
			_handle_waypoint_arrival(npc)
		return
	
	# Fallback: Simulate movement for NPCs without visual instances
	var distance = npc.current_position.distance_to(npc.target_position)
	if distance <= 4:
		_handle_waypoint_arrival(npc)
		return
	
	# Move at exact speed
	var direction = (npc.target_position - npc.current_position).normalized()
	var move_amount = npc.speed * delta
	
	if move_amount >= distance:
		npc.current_position = npc.target_position
	else:
		npc.current_position += direction * move_amount

## Handle arrival at a waypoint
func _handle_waypoint_arrival(npc: NPCSimulationState) -> void:
	var waypoint = npc.navigation.get_current_waypoint()
	if waypoint == null:
		return
	
	emit_signal("npc_waypoint_reached", npc.npc_id, waypoint.type, npc.current_position)
	
	# Handle floor changes
	if waypoint.type == "stairs_up" or waypoint.type == "stairs_down":
		var target_floor = waypoint.metadata.get("target_floor", npc.current_floor)
		npc.current_floor = target_floor
		print("%s changed to floor %d" % [npc.npc_name, npc.current_floor])
	
	# grab next waypoint
	var next_waypoint = npc.navigation.advance_waypoint()
	
	# Check if more waypoints
	if next_waypoint:
		# More waypoints to go
		_start_travel_to_waypoint(npc, npc.navigation.get_current_waypoint())
	else:
		# Reached final destination
		var zone_name = waypoint.metadata.get("zone_name", "unknown")
		emit_signal("npc_arrived_at_zone", npc.npc_id, zone_name, npc.current_position)
		
		# Start performing actions
		npc.state.change_to(NPCState.Type.PERFORMING_ACTIONS, {
			"zone": zone_name,
			"position": npc.current_position
		})
		npc.current_action_index = 0

## Start travel to a specific waypoint
func _start_travel_to_waypoint(npc: NPCSimulationState, waypoint: NPCNavigation.NavWaypoint) -> void:
	var distance = npc.current_position.distance_to(waypoint.position)
	# this distance does not take into account our A* I don't think, so padding with extra time for now
	npc.travel_duration = (distance / npc.speed) + 10 if npc.speed > 0 else 0.1
	npc.travel_start_time = Time.get_ticks_msec() / 1000.0
	npc.target_position = waypoint.position
	
	var destination = waypoint.metadata.get("zone_name", waypoint.type)
	emit_signal("npc_started_traveling", npc.npc_id, npc.current_position, waypoint.position, destination)

## Update NPC actions
func _update_actions(npc: NPCSimulationState, delta: float) -> void:
	if npc.active_entry == null:
		npc.state.change_to(NPCState.Type.IDLE)
		return
	
	# Execute actions sequentially
	if npc.current_action_index < npc.active_entry.actions.size():
		var action = npc.active_entry.actions[npc.current_action_index]
		var result = action.execute()
		
		# Emit action result
		emit_signal("npc_action_attempted", npc.npc_id, action, result.success)
		
		if result.success:
			print("%s completed: %s" % [npc.npc_name, action.display_name])
			DailyReportManager.report_task_completion(npc.npc_id, npc.npc_name, action.display_name, "location", {})
		else:
			print("%s failed: %s (%s)" % [npc.npc_name, action.display_name, result.reason])
			DailyReportManager.report_task_failure(npc.npc_id, npc.npc_name, action.display_name, "failure reason", "location", {})
		
		npc.current_action_index += 1
	else:
		# All actions complete
		npc.active_entry.mark_complete()
		npc.active_entry = null
		npc.current_action_index = 0
		npc.state.change_to(NPCState.Type.IDLE)

## Handle time tick from day/night cycle
func _on_time_tick(day: int, hour: int, minute: int) -> void:
	var total_minute = hour * 60 + minute
	
	for npc_id in simulated_npcs:
		_check_schedule(simulated_npcs[npc_id], total_minute)

## Check if any schedule entries should activate
func _check_schedule(npc: NPCSimulationState, current_minute: int) -> void:
	# Don't interrupt busy NPCs
	if npc.is_busy():
		return
	
	# Find active schedule entry
	for entry in npc.schedule:
		if entry.is_active(current_minute):
			if npc.active_entry != entry:
				# New schedule entry activated
				_activate_schedule_entry(npc, entry)
			return

## Activate a schedule entry
func _activate_schedule_entry(npc: NPCSimulationState, entry: ScheduleEntry) -> void:
	npc.active_entry = entry
	npc.current_action_index = 0
	
	print("%s activating schedule: %s" % [npc.npc_name, entry.to_string()])
	
	# Get target floor from zone
	var target_floor = _get_zone_floor(entry.zone_name, npc)
	
	# Plan route
	if npc.navigation.set_destination(entry.zone_name, target_floor, ZoneManager):
		# Start navigating
		npc.state.change_to(NPCState.Type.NAVIGATING, {
			"destination": entry.zone_name,
			"target_floor": target_floor
		})
		
		var first_waypoint = npc.navigation.get_current_waypoint()
		if first_waypoint:
			_start_travel_to_waypoint(npc, first_waypoint)
	else:
		push_error("Failed to plan route for %s to %s" % [npc.npc_name, entry.zone_name])
		npc.active_entry = null

## Get floor number for a zone
func _get_zone_floor(zone_name: String, npc: NPCSimulationState) -> int:
	if not ZoneManager:
		return 1
	
	# This is a simplified version - adjust to match your ZoneManager API
	var closest_zone_id = ZoneManager.get_closest_zone_of_type_from_position(zone_name, npc.current_position)
	var zone: ZoneData = ZoneManager.get_zone_data(closest_zone_id)
	if zone:
		return zone.floor
	return 1

## Reset all schedules (call at midnight)
func reset_daily_schedules() -> void:
	for npc_id in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		for entry in npc.schedule:
			entry.reset()
		npc.active_entry = null
		npc.current_action_index = 0
		npc.state.change_to(NPCState.Type.IDLE)
	
	print("Reset all NPC schedules")

## Debug: Print info for a specific NPC
func debug_npc(npc_id: String) -> void:
	var npc = get_npc_state(npc_id)
	if npc:
		print(npc.debug_info())
	else:
		print("NPC not found: %s" % npc_id)

## Debug: Print info for all NPCs
func debug_all_npcs() -> void:
	print("=== NPC Simulation Status ===")
	print("Total NPCs: %d" % simulated_npcs.size())
	for npc_id in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		print("%s - %s - Floor %d" % [npc.npc_name, npc.state.get_name(), npc.current_floor])
