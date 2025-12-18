extends Node

var simulated_npcs: Dictionary[String, NPCSimulationState] = {}
var npc_id_counter: int = 0

signal npc_spawned(npc_id: String, npc_type: String, position: Vector2)
signal npc_despawned(npc_id: String)
signal npc_state_changed(npc_id: String, old_state: int, new_state: int)
signal npc_arrived_at_zone(npc_id: String, zone_name: String, position: Vector2)
signal npc_waypoint_reached(npc_id: String, waypoint_type: String, position: Vector2)
signal npc_action_started(npc_id: String, action: NPCAction)
signal npc_action_completed(npc_id: String, action: NPCAction, success: bool)
signal npc_action_progress(npc_id: String, action: NPCAction, progress: float)
signal npc_started_traveling(npc_id: String, from_pos: Vector2, to_pos: Vector2, destination: String)

# -----------------------------
# NPC Simulation State Class
# -----------------------------
class NPCSimulationState:
	var npc_id: String
	var npc_type: String
	var npc_name: String
	
	var current_floor: int = 1
	var current_position: Vector2
	var target_position: Vector2
	var speed: float
	var last_waypoint_position: Vector2 = Vector2.ZERO
	var is_moving_to_waypoint: bool = false
	
	var state: NPCState
	var navigation: NPCNavigation
	var navigation_cooldown: float = 0.0
	
	var schedule: Array[ScheduleEntry] = []
	var active_entry: ScheduleEntry = null
	var current_action_index: int = 0
	var current_action: NPCAction = null  # Track currently executing action
	
	var travel_start_time: float = 0.0
	var travel_duration: float = 0.0
	
	var npc_instance: Node = null
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
		var action_info: String = "None"
		if current_action:
			action_info = "%s (%.1f%% complete, %.1fs remaining)" % [
				current_action.display_name,
				current_action.get_progress() * 100.0,
				current_action.get_remaining_duration()
			]
		
		return """
		NPC: %s (%s)
		State: %s
		Floor: %d
		Position: %s
		Schedule Entry: %s
		Current Action: %s
		Actions: %d/%d
		Navigation: %s
		""" % [
			npc_name, npc_id,
			state.get_name(),
			current_floor,
			current_position,
			active_entry.id if active_entry else "None",
			action_info,
			current_action_index,
			active_entry.actions.size() if active_entry else 0,
			navigation.to_string()
		]


# -----------------------------
# MAIN MANAGER
# -----------------------------
func _ready() -> void:
	if DayAndNightCycleManager:
		DayAndNightCycleManager.time_tick.connect(_on_time_tick)
	
	# Wait for all floors to be ready before spawning NPCs
	if FloorManager:
		await FloorManager.wait_for_all_floors_ready()
		print("NPCSimulationManager: All floors ready, can now spawn NPCs safely")


func _generate_npc_id(npc_type: String) -> String:
	npc_id_counter += 1
	return "%s_%d" % [npc_type, npc_id_counter]


func spawn_npc(npc_type: String, spawn_position: Vector2 = Vector2.ZERO) -> String:
	var npc_definition: Variant = NPCTypeRegistry.create_npc_definition(npc_type)
	if npc_definition == null:
		push_error("Unknown NPC type: %s" % npc_type)
		return ""
	
	var npc_id: String = _generate_npc_id(npc_type)
	var start_pos: Vector2 = spawn_position if spawn_position != Vector2.ZERO else npc_definition.start_position
	
	var state: NPCSimulationState = NPCSimulationState.new(
		npc_id,
		npc_type,
		npc_definition.npc_name,
		start_pos,
		npc_definition.speed
	)
	
	state.behavior_data["definition"] = npc_definition
	state.schedule = npc_definition.get_schedule()

	state.state.state_changed.connect(
		func(old_state: int, new_state: int) -> void:
			_on_npc_state_changed(npc_id, old_state, new_state)
	)
	
	simulated_npcs[npc_id] = state
	emit_signal("npc_spawned", npc_id, npc_type, start_pos)
	
	print("Spawned NPC: %s (%s) at %s" % [state.npc_name, npc_type, start_pos])
	return npc_id


func despawn_npc(npc_id: String) -> void:
	var state: NPCSimulationState = simulated_npcs.get(npc_id)
	if state == null:
		return
	
	if state.npc_instance != null:
		state.npc_instance.queue_free()
	
	simulated_npcs.erase(npc_id)
	emit_signal("npc_despawned", npc_id)
	print("Despawned NPC: %s" % npc_id)


func get_npc_state(npc_id: String) -> NPCSimulationState:
	return simulated_npcs.get(npc_id)


func get_all_npc_states() -> Dictionary[String, NPCSimulationState]:
	return simulated_npcs


func get_npcs_by_type(npc_type: String) -> Array[NPCSimulationState]:
	var npcs: Array[NPCSimulationState] = []
	for npc_id: String in simulated_npcs:
		var state: NPCSimulationState = simulated_npcs[npc_id]
		if state.npc_type == npc_type:
			npcs.append(state)
	return npcs


func get_npc_count() -> int:
	return simulated_npcs.size()


func get_npc_count_by_type(npc_type: String) -> int:
	return get_npcs_by_type(npc_type).size()


func _on_npc_state_changed(npc_id: String, old_state: int, new_state: int) -> void:
	emit_signal("npc_state_changed", npc_id, old_state, new_state)
	
	var state: NPCSimulationState = get_npc_state(npc_id)
	if state:
		print("%s: %s -> %s" % [
			state.npc_name,
			NPCState.Type.keys()[old_state],
			NPCState.Type.keys()[new_state]
		])


func _process(delta: float) -> void:
	for npc_id: String in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		_update_npc(npc, delta)


func _update_npc(npc: NPCSimulationState, delta: float) -> void:
	if npc.navigation_cooldown > 0:
		npc.navigation_cooldown -= delta
		
	match npc.state.type:
		NPCState.Type.NAVIGATING:
			_update_navigation(npc, delta)
		
		NPCState.Type.PERFORMING_ACTIONS:
			_update_actions(npc, delta)


func _update_navigation(npc: NPCSimulationState, delta: float) -> void:
	if npc.npc_instance != null and npc.npc_instance.navigation_agent_2d != null:
		npc.current_position = npc.npc_instance.global_position
		var distance_to_target: float = npc.current_position.distance_to(npc.target_position)
		if npc.npc_instance.navigation_agent_2d.is_navigation_finished() and distance_to_target <= 8.0 and npc.is_moving_to_waypoint:
			_handle_waypoint_arrival(npc)
		return
	
	var distance: float = npc.current_position.distance_to(npc.target_position)
	if distance <= 4.0 and npc.is_moving_to_waypoint:
		_handle_waypoint_arrival(npc)
		return
	
	var direction: Vector2 = (npc.target_position - npc.current_position).normalized()
	var move_amount: float = npc.speed * delta
	
	if move_amount >= distance:
		npc.current_position = npc.target_position
	else:
		npc.current_position += direction * move_amount


func _handle_waypoint_arrival(npc: NPCSimulationState) -> void:
	var waypoint: NPCNavigation.NavWaypoint = npc.navigation.get_current_waypoint()
	if waypoint == null:
		return
	
	emit_signal("npc_waypoint_reached", npc.npc_id, waypoint.type, npc.current_position)
	npc.is_moving_to_waypoint = false
	
	if waypoint.type in ["stairs_up", "stairs_down"]:
		var target_floor: int = waypoint.metadata.get("target_floor", npc.current_floor)
		npc.current_floor = target_floor
		if npc.npc_instance != null and npc.npc_instance.navigation_agent_2d != null:
			npc.npc_instance.navigation_agent_2d.set_navigation_layer_value(target_floor, true)
		print("%s changed to floor %d" % [npc.npc_name, npc.current_floor])
	
	var next_waypoint: bool = npc.navigation.advance_waypoint()
	
	if next_waypoint:
		_start_travel_to_waypoint(npc, npc.navigation.get_current_waypoint())
	else:
		var zone_name: String = waypoint.metadata.get("zone_name", "unknown")
		emit_signal("npc_arrived_at_zone", npc.npc_id, zone_name, npc.current_position)
		
		npc.state.change_to(NPCState.Type.PERFORMING_ACTIONS, {
			"zone": zone_name,
			"position": npc.current_position
		})
		npc.current_action_index = 0


func _start_travel_to_waypoint(npc: NPCSimulationState, waypoint: NPCNavigation.NavWaypoint) -> void:
	var distance: float = npc.current_position.distance_to(waypoint.position)
	npc.travel_duration = (distance / npc.speed) + 10.0 if npc.speed > 0 else 0.1
	npc.travel_start_time = Time.get_ticks_msec() / 1000.0
	npc.target_position = waypoint.position
	npc.last_waypoint_position = waypoint.position
	npc.is_moving_to_waypoint = true
	var destination: String = waypoint.metadata.get("zone_name", waypoint.type)
	emit_signal("npc_started_traveling", npc.npc_id, npc.current_position, waypoint.position, destination)


func _update_actions(npc: NPCSimulationState, delta: float) -> void:
	if npc.active_entry == null:
		npc.state.change_to(NPCState.Type.IDLE)
		return
	
	# If we have a current action, check if it's still in progress
	if npc.current_action != null:
		# Emit progress signal for UI updates
		emit_signal("npc_action_progress", npc.npc_id, npc.current_action, npc.current_action.get_progress())
		
		# Check if action duration is complete
		if npc.current_action.is_duration_complete():
			# Action finished!
			npc.current_action.complete()
			emit_signal("npc_action_completed", npc.npc_id, npc.current_action, true)
			
			print("%s completed: %s (took %.1fs)" % [
				npc.npc_name,
				npc.current_action.display_name,
				npc.current_action.duration
			])
			
			DailyReportManager.report_task_completion(
				npc.npc_id,
				npc.npc_name,
				npc.current_action.display_name,
				"location",
				{"duration": npc.current_action.duration}
			)
			
			npc.current_action = null
			npc.current_action_index += 1
		else:
			# Still waiting for action to complete
			return
	
	# Start next action if available
	if npc.current_action_index < npc.active_entry.actions.size():
		var action: NPCAction = npc.active_entry.actions[npc.current_action_index]
		
		# Execute the action (this runs the callback and starts the timer)
		var result: Dictionary = action.execute()
		
		if result.success:
			npc.current_action = action
			emit_signal("npc_action_started", npc.npc_id, action)
			
			if action.duration > 0.0:
				print("%s started: %s (will take %.1fs)" % [
					npc.npc_name,
					action.display_name,
					action.duration
				])
			else:
				# Instant action - mark complete immediately
				action.complete()
				emit_signal("npc_action_completed", npc.npc_id, action, true)
				print("%s completed instantly: %s" % [npc.npc_name, action.display_name])
				
				DailyReportManager.report_task_completion(
					npc.npc_id,
					npc.npc_name,
					action.display_name,
					"location",
					{}
				)
				
				npc.current_action = null
				npc.current_action_index += 1
		else:
			# Action failed to start
			print("%s failed to start: %s (%s)" % [
				npc.npc_name,
				action.display_name,
				result.reason
			])
			
			DailyReportManager.report_task_failure(
				npc.npc_id,
				npc.npc_name,
				action.display_name,
				result.reason,
				"location",
				{}
			)
			
			npc.current_action_index += 1
	
	else:
		# All actions complete
		npc.active_entry.mark_complete()
		npc.active_entry = null
		npc.current_action_index = 0
		npc.current_action = null
		npc.state.change_to(NPCState.Type.IDLE)


func _on_time_tick(day: int, hour: int, minute: int) -> void:
	var total_minute: int = hour * 60 + minute
	
	for npc_id: String in simulated_npcs:
		_check_schedule(simulated_npcs[npc_id], total_minute)


func _check_schedule(npc: NPCSimulationState, current_minute: int) -> void:
	if npc.is_busy():
		return
	
	for entry: ScheduleEntry in npc.schedule:
		if entry.is_active(current_minute):
			if npc.active_entry != entry:
				_activate_schedule_entry(npc, entry)
			return


func _activate_schedule_entry(npc: NPCSimulationState, entry: ScheduleEntry) -> void:
	npc.active_entry = entry
	npc.current_action_index = 0
	npc.current_action = null
	npc.is_moving_to_waypoint = false
	
	print("%s activating schedule: %s" % [npc.npc_name, entry.to_string()])
	
	var target_floor: int = _get_zone_floor(entry.zone_name, npc)
	
	# Wait for target floor to be ready
	if FloorManager and not FloorManager.is_floor_navigation_ready(target_floor):
		print("%s waiting for floor %d navigation..." % [npc.npc_name, target_floor])
		await FloorManager.wait_for_floor_ready(target_floor)
	
	if npc.navigation.set_destination(entry.zone_name, target_floor, ZoneManager):
		npc.state.change_to(NPCState.Type.NAVIGATING, {
			"destination": entry.zone_name,
			"target_floor": target_floor
		})
		
		var first_waypoint: NPCNavigation.NavWaypoint = npc.navigation.get_current_waypoint()
		if first_waypoint:
			_start_travel_to_waypoint(npc, first_waypoint)
	else:
		push_error("Failed to plan route for %s to %s" % [npc.npc_name, entry.zone_name])
		npc.active_entry = null


func _get_zone_floor(zone_name: String, npc: NPCSimulationState) -> int:
	if not ZoneManager:
		return 1
	
	var closest_zone_id: int = ZoneManager.get_closest_zone_of_type_from_position(zone_name, npc.current_position)
	var zone: ZoneData = ZoneManager.get_zone_data(closest_zone_id)
	if zone:
		return zone.floor
	return 1


func reset_daily_schedules() -> void:
	for npc_id: String in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		for entry: ScheduleEntry in npc.schedule:
			entry.reset()
		npc.active_entry = null
		npc.current_action_index = 0
		npc.current_action = null
		npc.state.change_to(NPCState.Type.IDLE)
	
	print("Reset all NPC schedules")


func debug_npc(npc_id: String) -> void:
	var npc: NPCSimulationState = get_npc_state(npc_id)
	if npc:
		print(npc.debug_info())
	else:
		print("NPC not found: %s" % npc_id)


func debug_all_npcs() -> void:
	print("=== NPC Simulation Status ===")
	print("Total NPCs: %d" % simulated_npcs.size())
	for npc_id: String in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		var action_text: String = ""
		if npc.current_action:
			action_text = " - %s (%.0f%%)" % [
				npc.current_action.display_name,
				npc.current_action.get_progress() * 100.0
			]
		print("%s - %s - Floor %d%s" % [
			npc.npc_name,
			npc.state.get_name(),
			npc.current_floor,
			action_text
		])
