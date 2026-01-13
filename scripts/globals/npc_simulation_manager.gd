extends Node

var simulated_npcs: Dictionary[String, NPCSimulationState] = {}
var npc_id_counter: int = 0

const SAVE_PATH: String = "user://npc_simulation_save.json"
const WAYPOINT_ARRIVAL_DISTANCE: float = 6.0  # Standardized arrival distance
const IDLE_POSITION_SYNC_SPEED: float = 3.0
const NAVIGATION_RETRY_DELAY: float = 5.0
const MAX_PATHFINDING_RETRIES: int = 3

signal npc_spawned(npc_id: String, npc_type: String, position: Vector2)
signal npc_despawned(npc_id: String)
signal npc_state_changed(npc_id: String, old_state: int, new_state: int)
signal npc_arrived_at_zone(npc_id: String, zone_name: String, position: Vector2)
signal npc_waypoint_reached(npc_id: String, waypoint_type: String, position: Vector2)
signal npc_action_started(npc_id: String, action: NPCAction)
signal npc_action_completed(npc_id: String, action: NPCAction, success: bool)
signal npc_action_progress(npc_id: String, action: NPCAction, progress: float)
signal npc_started_traveling(npc_id: String, from_pos: Vector2, to_pos: Vector2, destination: String)
signal npcs_loaded()
signal npcs_saved()

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
	var pathfinding_retry_count: int = 0
	var failed_destination: String = ""
	
	var schedule: Array[ScheduleEntry] = []
	var active_entry: ScheduleEntry = null
	var current_action_index: int = 0
	var current_action: NPCAction = null
	
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
	
	func to_dict() -> Dictionary:
		"""Serialize NPC state to dictionary for saving"""
		var schedule_data: Array = []
		for entry in schedule:
			schedule_data.append(entry.to_dict() if entry.has_method("to_dict") else {})
		
		var active_entry_id: String = ""
		if active_entry and active_entry.has_method("get_id"):
			active_entry_id = active_entry.id if active_entry.id else ""
		
		var current_action_data: Dictionary = {}
		if current_action and current_action.has_method("to_dict"):
			current_action_data = current_action.to_dict()
		
		# Serialize navigation path
		var navigation_data: Dictionary = navigation.to_dict()
		
		return {
			"npc_id": npc_id,
			"npc_type": npc_type,
			"npc_name": npc_name,
			"current_floor": current_floor,
			"current_position": {"x": current_position.x, "y": current_position.y},
			"target_position": {"x": target_position.x, "y": target_position.y},
			"speed": speed,
			"last_waypoint_position": {"x": last_waypoint_position.x, "y": last_waypoint_position.y},
			"is_moving_to_waypoint": is_moving_to_waypoint,
			"state_type": state.type,
			"state_data": state.context,
			"navigation_cooldown": navigation_cooldown,
			"navigation_data": navigation_data,
			"pathfinding_retry_count": pathfinding_retry_count,
			"failed_destination": failed_destination,
			"schedule": schedule_data,
			"active_entry_id": active_entry_id,
			"current_action_index": current_action_index,
			"current_action": current_action_data,
			"travel_start_time": travel_start_time,
			"travel_duration": travel_duration,
			"behavior_data": behavior_data
		}
	
	func from_dict(data: Dictionary) -> void:
		"""Deserialize NPC state from dictionary"""
		npc_id = data.get("npc_id", npc_id)
		npc_type = data.get("npc_type", npc_type)
		npc_name = data.get("npc_name", npc_name)
		current_floor = data.get("current_floor", 1)
		
		var pos_data: Dictionary = data.get("current_position", {})
		current_position = Vector2(pos_data.get("x", 0.0), pos_data.get("y", 0.0))
		
		var target_pos_data: Dictionary = data.get("target_position", {})
		target_position = Vector2(target_pos_data.get("x", 0.0), target_pos_data.get("y", 0.0))
		
		speed = data.get("speed", speed)
		
		var waypoint_pos_data: Dictionary = data.get("last_waypoint_position", {})
		last_waypoint_position = Vector2(waypoint_pos_data.get("x", 0.0), waypoint_pos_data.get("y", 0.0))
		
		is_moving_to_waypoint = data.get("is_moving_to_waypoint", false)
		navigation_cooldown = data.get("navigation_cooldown", 0.0)
		pathfinding_retry_count = data.get("pathfinding_retry_count", 0)
		failed_destination = data.get("failed_destination", "")
		current_action_index = data.get("current_action_index", 0)
		travel_start_time = data.get("travel_start_time", 0.0)
		travel_duration = data.get("travel_duration", 0.0)
		behavior_data = data.get("behavior_data", {})
		
		# Restore navigation path
		var navigation_data: Dictionary = data.get("navigation_data", {})
		if not navigation_data.is_empty():
			navigation.from_dict(navigation_data)
		
		# Restore state
		var state_type: int = data.get("state_type", NPCState.Type.IDLE)
		var state_data: Dictionary = data.get("state_data", {})
		state.change_to(state_type, state_data)
	
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
		DayAndNightCycleManager.time_tick_day.connect(reset_daily_schedules)
	
	# Wait for all floors to be ready
	if FloorManager:
		await FloorManager.wait_for_all_floors_ready()
		print("NPCSimulationManager: All floors ready")

# --------------------------------------------
# Save/Load System
# --------------------------------------------

func save_npcs() -> bool:
	var npcs_data: Array = []
	
	for npc_id: String in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		npcs_data.append(npc.to_dict())
	
	var save_data: Dictionary = {
		"npc_id_counter": npc_id_counter,
		"npcs": npcs_data,
		"version": "1.0"
	}
	
	var json_string: String = JSON.stringify(save_data, "\t")
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	
	if file == null:
		push_error("Failed to open NPC save file for writing: " + SAVE_PATH)
		return false
	
	file.store_string(json_string)
	file.close()
	
	print("NPCs saved to: ", SAVE_PATH, " (", npcs_data.size(), " NPCs)")
	npcs_saved.emit()
	return true

func load_npcs() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No NPC save file found at: ", SAVE_PATH)
		return false
	
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	
	if file == null:
		push_error("Failed to open NPC save file for reading: " + SAVE_PATH)
		return false
	
	var json_string: String = file.get_as_text()
	file.close()
	
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse NPC JSON: " + json.get_error_message())
		return false
	
	var save_data: Dictionary = json.data
	
	if not save_data.has("npcs"):
		push_error("Invalid NPC save data structure")
		return false
	
	# Clear existing NPCs
	for npc_id: String in simulated_npcs.keys():
		despawn_npc(npc_id)
	simulated_npcs.clear()
	
	# Restore ID counter
	npc_id_counter = save_data.get("npc_id_counter", 0)
	
	# Wait for floors to be ready before restoring NPCs
	if FloorManager:
		await FloorManager.wait_for_all_floors_ready()
	
	# Restore NPCs - collect them first, then spawn sequentially
	var npcs_data: Array = save_data["npcs"]
	
	for npc_data: Variant in npcs_data:
		var npc_state: NPCSimulationState = _create_npc_state_from_dict(npc_data)
		if npc_state:
			simulated_npcs[npc_state.npc_id] = npc_state
	
	# Spawn all visual instances (can happen in parallel via deferred calls)
	for npc_id: String in simulated_npcs:
		var npc_state: NPCSimulationState = simulated_npcs[npc_id]
		_spawn_npc_instance.call_deferred(npc_state)
	
	# Wait one frame to ensure all deferred spawns are queued
	await get_tree().process_frame
	
	print("NPCs loaded from: ", SAVE_PATH, " (", simulated_npcs.size(), " NPCs)")
	npcs_loaded.emit()
	return true

func _create_npc_state_from_dict(data: Dictionary) -> NPCSimulationState:
	"""Create and configure NPC state from saved data without spawning"""
	var npc_id: String = data.get("npc_id", "")
	var npc_type: String = data.get("npc_type", "")
	var npc_name: String = data.get("npc_name", "")
	
	var pos_data: Dictionary = data.get("current_position", {})
	var position: Vector2 = Vector2(pos_data.get("x", 0.0), pos_data.get("y", 0.0))
	
	var speed: float = data.get("speed", 100.0)
	
	# Create NPC state
	var state: NPCSimulationState = NPCSimulationState.new(
		npc_id,
		npc_type,
		npc_name,
		position,
		speed
	)
	
	# Restore full state from saved data
	state.from_dict(data)
	
	# Get NPC definition to restore schedule
	var npc_definition: Variant = NPCTypeRegistry.create_npc_definition(npc_type)
	if npc_definition:
		state.behavior_data["definition"] = npc_definition
		state.schedule = npc_definition.get_schedule()
		
		# Restore active schedule entry reference
		var active_entry_id: String = data.get("active_entry_id", "")
		if active_entry_id != "":
			for entry in state.schedule:
				if entry.id == active_entry_id:
					state.active_entry = entry
					break
		
		# Restore current action if it exists
		var action_data: Dictionary = data.get("current_action", {})
		if not action_data.is_empty() and state.active_entry:
			# Find the matching action in the schedule
			if state.current_action_index < state.active_entry.actions.size():
				var action: NPCAction = state.active_entry.actions[state.current_action_index]
				# Restore action progress
				action.restore_from_dict(action_data)
				state.current_action = action
	
	# Connect signals
	state.state.state_changed.connect(
		func(old_state: int, new_state: int) -> void:
			_on_npc_state_changed(npc_id, old_state, new_state)
	)
	
	print("Created NPC state: %s (%s) at floor %d, position %s - State: %s" % [
		npc_name,
		npc_type,
		state.current_floor,
		state.current_position,
		NPCState.Type.keys()[state.state.type]
	])
	
	return state

func delete_save() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		var dir: DirAccess = DirAccess.open("user://")
		var error: Error = dir.remove(SAVE_PATH)
		if error == OK:
			print("NPC save file deleted: ", SAVE_PATH)
			return true
		else:
			push_error("Failed to delete NPC save file")
			return false
	return false

func reset_npcs() -> void:
	"""Clear all NPCs and reset to initial state"""
	for npc_id: String in simulated_npcs.keys():
		despawn_npc(npc_id)
	
	simulated_npcs.clear()
	npc_id_counter = 0
	save_npcs()
	print("All NPCs reset")

# --------------------------------------------
# NPC Management
# --------------------------------------------

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
	
func _spawn_npc_instance(npc: NPCSimulationState) -> void:
	"""Spawn the visual instance of an NPC in the world"""
	if npc.npc_instance != null:
		return  # Already has an instance
	
	var npc_definition: Variant = npc.behavior_data.get("definition")
	if not npc_definition:
		push_error("Cannot spawn NPC instance: missing definition for " + npc.npc_name)
		return
	
	if not "npc_scene_path" in npc_definition or npc_definition.npc_scene_path == "":
		push_error("Cannot spawn NPC instance: missing scene path for " + npc.npc_name)
		return
	
	# Wait for the NPC's floor to be ready
	if FloorManager and not FloorManager.is_floor_navigation_ready(npc.current_floor):
		await FloorManager.wait_for_floor_ready(npc.current_floor)
	
	# Load and instantiate the NPC scene
	var npc_scene: Resource = load(npc_definition.npc_scene_path)
	if not npc_scene:
		push_error("Failed to load NPC scene: " + npc_definition.npc_scene_path)
		return
	
	var instance: Node = npc_scene.instantiate()
	if not instance:
		push_error("Failed to instantiate NPC scene")
		return
	
	# Set position and floor
	instance.global_position = npc.current_position
	
	# Get the floor's NPC container
	var floor_container: Node2D = FloorManager.get_floor_npc_container(npc.current_floor)
	if not floor_container:
		push_error("No NPC container found for floor " + str(npc.current_floor))
		instance.queue_free()
		return
	
	# Add to scene
	floor_container.add_child(instance)
	
	# Configure navigation if available
	if instance.has_node("NavigationAgent2D"):
		var nav_agent: NavigationAgent2D = instance.get_node("NavigationAgent2D")
		nav_agent.set_navigation_layer_value(npc.current_floor, true)
	
	# Store reference
	npc.npc_instance = instance
	
	print("Spawned visual instance for: %s at %s on floor %d" % [
		npc.npc_name,
		npc.current_position,
		npc.current_floor
	])


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
		
		# FIX #1: Check schedules when transitioning to IDLE
		if new_state == NPCState.Type.IDLE:
			if DayAndNightCycleManager:
				var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
				var total_minute: int = current_time.hour * 60 + current_time.minute
				_check_schedule(state, total_minute)


func _process(delta: float) -> void:
	for npc_id: String in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		_update_npc(npc, delta)


func _update_npc(npc: NPCSimulationState, delta: float) -> void:
	if npc.navigation_cooldown > 0:
		npc.navigation_cooldown -= delta
		
		# Retry pathfinding if cooldown expired
		if npc.navigation_cooldown <= 0 and npc.failed_destination != "":
			_retry_pathfinding(npc)
		
	match npc.state.type:
		NPCState.Type.NAVIGATING:
			_update_navigation(npc, delta)
		
		NPCState.Type.PERFORMING_ACTIONS:
			_update_actions(npc, delta)
		
		NPCState.Type.IDLE:
			_update_idle_position_sync(npc, delta)


func _update_idle_position_sync(npc: NPCSimulationState, delta: float) -> void:
	"""Sync visual position to simulation position when idle"""
	if npc.npc_instance == null:
		return
	
	var dist: float = npc.npc_instance.global_position.distance_to(npc.current_position)
	if dist > 1.0:
		npc.npc_instance.global_position = npc.npc_instance.global_position.lerp(
			npc.current_position, 
			delta * IDLE_POSITION_SYNC_SPEED
		)


func _retry_pathfinding(npc: NPCSimulationState) -> void:
	"""Retry failed pathfinding after cooldown"""
	if npc.failed_destination == "" or npc.active_entry == null:
		return
	
	npc.pathfinding_retry_count += 1
	
	if npc.pathfinding_retry_count > MAX_PATHFINDING_RETRIES:
		push_error("NPC %s failed pathfinding to %s after %d retries - giving up" % [
			npc.npc_name,
			npc.failed_destination,
			MAX_PATHFINDING_RETRIES
		])
		npc.active_entry = null
		npc.failed_destination = ""
		npc.pathfinding_retry_count = 0
		npc.state.change_to(NPCState.Type.IDLE)
		return
	
	print("NPC %s retrying pathfinding to %s (attempt %d/%d)" % [
		npc.npc_name,
		npc.failed_destination,
		npc.pathfinding_retry_count,
		MAX_PATHFINDING_RETRIES
	])
	
	var target_floor: int = _get_zone_floor(npc.failed_destination, npc)
	
	if npc.navigation.set_destination(npc.failed_destination, target_floor, ZoneManager):
		# Success! Clear failure state
		npc.failed_destination = ""
		npc.pathfinding_retry_count = 0
		
		npc.state.change_to(NPCState.Type.NAVIGATING, {
			"destination": npc.active_entry.zone_name,
			"target_floor": target_floor
		})
		
		var first_waypoint: NPCNavigation.NavWaypoint = npc.navigation.get_current_waypoint()
		if first_waypoint:
			_start_travel_to_waypoint(npc, first_waypoint)
	else:
		# Still failing, set cooldown for next retry
		npc.navigation_cooldown = NAVIGATION_RETRY_DELAY


func _update_navigation(npc: NPCSimulationState, delta: float) -> void:
	if npc.npc_instance != null and npc.npc_instance.navigation_agent_2d != null:
		npc.current_position = npc.npc_instance.global_position
		var distance_to_target: float = npc.current_position.distance_to(npc.target_position)
		if npc.npc_instance.navigation_agent_2d.is_navigation_finished() and distance_to_target <= WAYPOINT_ARRIVAL_DISTANCE and npc.is_moving_to_waypoint:
			_handle_waypoint_arrival(npc)
		return
	
	var distance: float = npc.current_position.distance_to(npc.target_position)
	if distance <= WAYPOINT_ARRIVAL_DISTANCE and npc.is_moving_to_waypoint:
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
		
		# FIX #9: Validate callback before executing
		if not _is_action_callback_valid(action):
			push_error("%s: Action callback invalid for '%s' - skipping" % [
				npc.npc_name,
				action.display_name
			])
			
			DailyReportManager.report_task_failure(
				npc.npc_id,
				npc.npc_name,
				action.display_name,
				"Invalid callback object",
				"location",
				{}
			)
			
			npc.current_action_index += 1
			return
		
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
		var current_day: int = -1
		if DayAndNightCycleManager:
			var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
			current_day = current_time.day
		
		npc.active_entry.mark_complete(current_day)
		npc.active_entry = null
		npc.current_action_index = 0
		npc.current_action = null
		npc.state.change_to(NPCState.Type.IDLE)


func _is_action_callback_valid(action: NPCAction) -> bool:
	"""Validate that action callback is valid and object exists"""
	if not action.callback.is_valid():
		return false
	
	var callback_object: Object = action.callback.get_object()
	if callback_object == null:
		return false
	
	# Check if object has been freed
	if not is_instance_valid(callback_object):
		return false
	
	return true


func _on_time_tick(day: int, hour: int, minute: int) -> void:
	var total_minute: int = hour * 60 + minute
	
	# Debug: Log time ticks for schedule debugging
	if minute == 0:  # Log once per hour
		print("[Schedule] Day %d, %02d:%02d - Checking schedules for %d NPCs" % [
			day, hour, minute, simulated_npcs.size()
		])
	
	for npc_id: String in simulated_npcs:
		_check_schedule(simulated_npcs[npc_id], total_minute, day)


func _check_schedule(npc: NPCSimulationState, current_minute: int, current_day: int = -1) -> void:
	# FIX #1: Removed is_busy() check - now checks schedules even when idle
	# This allows NPCs to pick up new schedule entries when they become idle
	
	for entry: ScheduleEntry in npc.schedule:
		if entry.is_active(current_minute, current_day):
			if npc.active_entry != entry:
				# Only activate if not already busy with something else
				if not npc.is_busy() or npc.active_entry == null:
					print("[Schedule] %s: Activating entry '%s' at minute %d (day %d)" % [
						npc.npc_name,
						entry.id,
						current_minute,
						current_day
					])
					_activate_schedule_entry(npc, entry)
			return
	
	# Debug: Log if NPC is idle with no active schedule
	if npc.is_idle() and npc.active_entry == null:
		var next_entry: ScheduleEntry = _find_next_schedule_entry(npc, current_minute, current_day)
		if next_entry and (current_minute % 60) == 0:  # Log once per hour
			print("[Schedule] %s: Idle, next schedule '%s' at %s" % [
				npc.npc_name,
				next_entry.id,
				next_entry.get_time_range()
			])


func _find_next_schedule_entry(npc: NPCSimulationState, current_minute: int, current_day: int = -1) -> ScheduleEntry:
	"""Find the next upcoming schedule entry for debugging purposes"""
	var next_entry: ScheduleEntry = null
	var smallest_diff: int = 9999
	
	for entry: ScheduleEntry in npc.schedule:
		# Check if entry can become active (not completed or completed on different day)
		var can_activate: bool = not entry.completed_today
		if entry.completed_today and current_day != -1 and entry.completion_day != -1:
			can_activate = current_day > entry.completion_day
		
		if can_activate:
			var diff: int = entry.start_minute - current_minute
			if diff > 0 and diff < smallest_diff:
				smallest_diff = diff
				next_entry = entry
	
	return next_entry


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
		# Clear any previous failure state
		npc.failed_destination = ""
		npc.pathfinding_retry_count = 0
		
		npc.state.change_to(NPCState.Type.NAVIGATING, {
			"destination": entry.zone_name,
			"target_floor": target_floor
		})
		
		var first_waypoint: NPCNavigation.NavWaypoint = npc.navigation.get_current_waypoint()
		if first_waypoint:
			_start_travel_to_waypoint(npc, first_waypoint)
	else:
		# FIX #14: Handle pathfinding failure with retry logic
		push_error("Failed to plan route for %s to %s - will retry" % [npc.npc_name, entry.zone_name])
		npc.failed_destination = entry.zone_name
		npc.navigation_cooldown = NAVIGATION_RETRY_DELAY
		npc.pathfinding_retry_count = 0
		# Don't clear active_entry - we'll retry later


func _get_zone_floor(zone_name: String, npc: NPCSimulationState) -> int:
	if not ZoneManager:
		return 1
	
	var closest_zone_id: int = ZoneManager.get_closest_zone_of_type_from_position(zone_name, npc.current_position)
	var zone: ZoneData = ZoneManager.get_zone_data(closest_zone_id)
	if zone:
		return zone.floor
	return 1


func reset_daily_schedules() -> void:
	"""
	Reset schedule completion flags for a new day.
	IMPORTANT: Does NOT interrupt active schedules or actions.
	Only resets entries that have finished or haven't started.
	"""
	print("[Schedule Reset] ===== RESETTING SCHEDULE FLAGS FOR NEW DAY =====")
	
	for npc_id: String in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		
		print("[Schedule Reset] %s: Processing %d schedule entries" % [
			npc.npc_name,
			npc.schedule.size()
		])
		
		for entry: ScheduleEntry in npc.schedule:
			# CRITICAL: Don't reset if this is the currently active entry
			# Let overnight/multi-day actions continue
			if npc.active_entry == entry:
				print("  - KEEPING '%s' - currently active (overnight/in-progress)" % entry.id)
				continue
			
			var was_completed: bool = entry.completed_today
			entry.reset()
			
			if was_completed:
				print("  - Reset '%s' (%s)" % [entry.id, entry.get_time_range()])
			else:
				print("  - '%s' already reset" % entry.id)
		
		# DO NOT clear active_entry, current_action_index, or current_action
		# DO NOT force state change to IDLE
		# Let ongoing work continue naturally
		
		print("[Schedule Reset] %s: Current state: %s, Active entry: %s" % [
			npc.npc_name,
			npc.state.get_name(),
			npc.active_entry.id if npc.active_entry else "None"
		])
	
	print("[Schedule Reset] ===== RESET COMPLETE (Active schedules preserved) =====")
	
	# Force immediate schedule check for idle NPCs only
	if DayAndNightCycleManager:
		var current_time: Dictionary = DayAndNightCycleManager.get_current_time()
		var total_minute: int = current_time.hour * 60 + current_time.minute
		var current_day: int = current_time.day
		
		print("[Schedule Reset] Checking schedules for idle NPCs at minute %d (day %d)" % [total_minute, current_day])
		
		for npc_id: String in simulated_npcs:
			var npc: NPCSimulationState = simulated_npcs[npc_id]
			# Only check schedule if NPC is actually idle and available
			if npc.is_idle() and npc.active_entry == null:
				_check_schedule(npc, total_minute, current_day)


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

# Auto-save on important events
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_npcs()
