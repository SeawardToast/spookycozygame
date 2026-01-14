extends Node

var simulated_npcs: Dictionary[String, NPCSimulationState] = {}
var npc_id_counter: int = 0

const SAVE_PATH: String = "user://npc_simulation_save.json"
const WAYPOINT_ARRIVAL_DISTANCE: float = 10.0
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


# =============================================
# NPC SIMULATION STATE
# =============================================
class NPCSimulationState:
	var npc_id: String
	var npc_type: String
	var npc_name: String
	var current_floor: int = 1
	var current_position: Vector2
	var target_position: Vector2
	var speed: float
	
	# A* path data
	var path: Array[Vector2] = []
	var path_index: int = 0
	var path_target: Vector2 = Vector2.ZERO
	
	# State
	var state: NPCState
	var navigation: NPCNavigation
	var navigation_cooldown: float = 0.0
	var pathfinding_retry_count: int = 0
	var failed_destination: String = ""
	var is_moving_to_waypoint: bool = false
	
	# Schedule
	var schedule: Array[ScheduleEntry] = []
	var active_entry: ScheduleEntry = null
	var current_action_index: int = 0
	var current_action: NPCAction = null
	
	# Visual
	var npc_instance: Node2D = null
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
	
	func has_valid_path() -> bool:
		return not path.is_empty() and path_index < path.size()
	
	func clear_path() -> void:
		path.clear()
		path_index = 0
		path_target = Vector2.ZERO
	
	func to_dict() -> Dictionary:
		var schedule_data: Array = []
		for entry in schedule:
			if entry.has_method("to_dict"):
				schedule_data.append(entry.to_dict())
		
		var path_data: Array = []
		for point in path:
			path_data.append({"x": point.x, "y": point.y})
		
		var current_action_data: Dictionary = {}
		if current_action and current_action.has_method("to_dict"):
			current_action_data = current_action.to_dict()
		
		return {
			"npc_id": npc_id,
			"npc_type": npc_type,
			"npc_name": npc_name,
			"current_floor": current_floor,
			"current_position": {"x": current_position.x, "y": current_position.y},
			"target_position": {"x": target_position.x, "y": target_position.y},
			"speed": speed,
			"path": path_data,
			"path_index": path_index,
			"path_target": {"x": path_target.x, "y": path_target.y},
			"state_type": state.type,
			"state_data": state.context,
			"navigation_data": navigation.to_dict(),
			"navigation_cooldown": navigation_cooldown,
			"pathfinding_retry_count": pathfinding_retry_count,
			"failed_destination": failed_destination,
			"is_moving_to_waypoint": is_moving_to_waypoint,
			"schedule": schedule_data,
			"active_entry_id": active_entry.id if active_entry else "",
			"current_action_index": current_action_index,
			"current_action": current_action_data,
			"behavior_data": behavior_data
		}
	
	func from_dict(data: Dictionary) -> void:
		npc_id = data.get("npc_id", npc_id)
		npc_type = data.get("npc_type", npc_type)
		npc_name = data.get("npc_name", npc_name)
		current_floor = data.get("current_floor", 1)
		speed = data.get("speed", speed)
		is_moving_to_waypoint = data.get("is_moving_to_waypoint", false)
		navigation_cooldown = data.get("navigation_cooldown", 0.0)
		pathfinding_retry_count = data.get("pathfinding_retry_count", 0)
		failed_destination = data.get("failed_destination", "")
		current_action_index = data.get("current_action_index", 0)
		behavior_data = data.get("behavior_data", {})
		
		var pos: Dictionary = data.get("current_position", {})
		current_position = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		
		var target: Dictionary = data.get("target_position", {})
		target_position = Vector2(target.get("x", 0.0), target.get("y", 0.0))
		
		var path_target_data: Dictionary = data.get("path_target", {})
		path_target = Vector2(path_target_data.get("x", 0.0), path_target_data.get("y", 0.0))
		
		# Restore path
		path.clear()
		for point: Variant in data.get("path", []):
			if point is Dictionary:
				path.append(Vector2(point.get("x", 0.0), point.get("y", 0.0)))
		path_index = data.get("path_index", 0)
		
		# Restore navigation
		var nav_data: Dictionary = data.get("navigation_data", {})
		if not nav_data.is_empty():
			navigation.from_dict(nav_data)
		
		# Restore state
		state.change_to(data.get("state_type", NPCState.Type.IDLE), data.get("state_data", {}))
	
	func debug_info() -> String:
		var path_info: String = "No path" if path.is_empty() else "Path %d/%d" % [path_index, path.size()]
		var action_info: String = "None"
		if current_action:
			action_info = "%s (%.0f%%)" % [current_action.display_name, current_action.get_progress() * 100.0]
		
		return "%s | %s | Floor %d | %s | Action: %s" % [
			npc_name, state.get_name(), current_floor, path_info, action_info
		]


# =============================================
# LIFECYCLE
# =============================================
func _ready() -> void:
	print("[NPCSimulationManager] _ready()")
	if DayAndNightCycleManager:
		DayAndNightCycleManager.time_tick.connect(_on_time_tick)
		DayAndNightCycleManager.time_tick_day.connect(reset_daily_schedules)


func _process(delta: float) -> void:
	for npc_id: String in simulated_npcs:
		_update_npc(simulated_npcs[npc_id], delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_npcs()


# =============================================
# NPC UPDATE LOOP
# =============================================
func _update_npc(npc: NPCSimulationState, delta: float) -> void:
	# Handle navigation cooldown/retry
	if npc.navigation_cooldown > 0:
		npc.navigation_cooldown -= delta
		if npc.navigation_cooldown <= 0 and npc.failed_destination != "":
			_retry_pathfinding(npc)
	
	match npc.state.type:
		NPCState.Type.NAVIGATING:
			_update_navigation(npc, delta)
		NPCState.Type.PERFORMING_ACTIONS:
			_update_actions(npc, delta)


func _update_navigation(npc: NPCSimulationState, delta: float) -> void:
	# Request path if needed
	if not npc.has_valid_path() or npc.path_target.distance_to(npc.target_position) > 1.0:
		_request_path(npc)
	
	if not npc.has_valid_path():
		# Fallback: move directly toward target
		_move_toward(npc, npc.target_position, delta)
	else:
		# Follow A* path
		_follow_path(npc, delta)
	
	# Check arrival
	var dist: float = npc.current_position.distance_to(npc.target_position)
	if dist <= WAYPOINT_ARRIVAL_DISTANCE and npc.is_moving_to_waypoint:
		_handle_waypoint_arrival(npc)


func _request_path(npc: NPCSimulationState) -> void:
	npc.clear_path()
	npc.path = FloorManager.get_navigation_path(npc.current_floor, npc.current_position, npc.target_position)
	npc.path_target = npc.target_position
	
	if npc.path.is_empty():
		print("[NAV] %s: No path found from %s to %s" % [npc.npc_name, npc.current_position, npc.target_position])
	else:
		print("[NAV] %s: Path found with %d points" % [npc.npc_name, npc.path.size()])


func _follow_path(npc: NPCSimulationState, delta: float) -> void:
	if npc.path_index >= npc.path.size():
		# Path exhausted, move to final target
		_move_toward(npc, npc.target_position, delta)
		return
	
	var next_point: Vector2 = npc.path[npc.path_index]
	var dist: float = npc.current_position.distance_to(next_point)
	var move_dist: float = npc.speed * delta
	
	if move_dist >= dist:
		npc.current_position = next_point
		npc.path_index += 1
		# Use remaining movement
		var remaining: float = (move_dist - dist) / npc.speed
		if remaining > 0.001:
			_follow_path(npc, remaining)
	else:
		var dir: Vector2 = (next_point - npc.current_position).normalized()
		npc.current_position += dir * move_dist


func _move_toward(npc: NPCSimulationState, target: Vector2, delta: float) -> void:
	var dist: float = npc.current_position.distance_to(target)
	if dist < 0.5:
		npc.current_position = target
		return
	
	var dir: Vector2 = (target - npc.current_position).normalized()
	var move_dist: float = min(npc.speed * delta, dist)
	npc.current_position += dir * move_dist


func _handle_waypoint_arrival(npc: NPCSimulationState) -> void:
	var waypoint: NPCNavigation.NavWaypoint = npc.navigation.get_current_waypoint()
	if not waypoint:
		return
	
	print("[NAV] %s: Reached waypoint '%s' at %s" % [npc.npc_name, waypoint.type, npc.current_position])
	
	npc_waypoint_reached.emit(npc.npc_id, waypoint.type, npc.current_position)
	npc.is_moving_to_waypoint = false
	npc.clear_path()
	
	# Handle floor change
	if waypoint.type in ["stairs_up", "stairs_down"]:
		var old_floor: int = npc.current_floor
		npc.current_floor = waypoint.metadata.get("target_floor", npc.current_floor)
		print("[NAV] %s: Changed floor %d -> %d" % [npc.npc_name, old_floor, npc.current_floor])
	
	# Advance to next waypoint or complete navigation
	if npc.navigation.advance_waypoint():
		_start_waypoint_travel(npc, npc.navigation.get_current_waypoint())
	else:
		var zone: String = waypoint.metadata.get("zone_name", "unknown")
		print("[NAV] %s: Arrived at zone '%s'" % [npc.npc_name, zone])
		npc_arrived_at_zone.emit(npc.npc_id, zone, npc.current_position)
		npc.state.change_to(NPCState.Type.PERFORMING_ACTIONS, {"zone": zone})
		npc.current_action_index = 0


func _start_waypoint_travel(npc: NPCSimulationState, waypoint: NPCNavigation.NavWaypoint) -> void:
	npc.target_position = waypoint.position
	npc.clear_path()
	_request_path(npc)
	npc.is_moving_to_waypoint = true
	
	var dest: String = waypoint.metadata.get("zone_name", waypoint.type)
	print("[NAV] %s: Started traveling to '%s' at %s" % [npc.npc_name, dest, waypoint.position])
	npc_started_traveling.emit(npc.npc_id, npc.current_position, waypoint.position, dest)


func _retry_pathfinding(npc: NPCSimulationState) -> void:
	if npc.failed_destination == "" or not npc.active_entry:
		return
	
	npc.pathfinding_retry_count += 1
	print("[NAV] %s: Retry pathfinding attempt %d/%d to '%s'" % [
		npc.npc_name, npc.pathfinding_retry_count, MAX_PATHFINDING_RETRIES, npc.failed_destination
	])
	
	if npc.pathfinding_retry_count > MAX_PATHFINDING_RETRIES:
		push_error("[NAV] %s: Pathfinding failed after %d retries" % [npc.npc_name, MAX_PATHFINDING_RETRIES])
		npc.active_entry = null
		npc.failed_destination = ""
		npc.pathfinding_retry_count = 0
		npc.clear_path()
		npc.state.change_to(NPCState.Type.IDLE)
		return
	
	var target_floor: int = _get_zone_floor(npc.failed_destination, npc)
	
	if npc.navigation.set_destination(npc.failed_destination, target_floor, ZoneManager):
		npc.failed_destination = ""
		npc.pathfinding_retry_count = 0
		npc.state.change_to(NPCState.Type.NAVIGATING, {"destination": npc.active_entry.zone_name})
		
		var waypoint: NPCNavigation.NavWaypoint = npc.navigation.get_current_waypoint()
		if waypoint:
			_start_waypoint_travel(npc, waypoint)
	else:
		npc.navigation_cooldown = NAVIGATION_RETRY_DELAY


# =============================================
# ACTIONS
# =============================================
func _update_actions(npc: NPCSimulationState, delta: float) -> void:
	if not npc.active_entry:
		npc.state.change_to(NPCState.Type.IDLE)
		return
	
	# Check current action progress
	if npc.current_action:
		npc_action_progress.emit(npc.npc_id, npc.current_action, npc.current_action.get_progress())
		
		if npc.current_action.is_duration_complete():
			npc.current_action.complete()
			print("[ACTION] %s: Completed '%s' (took %.1fs)" % [
				npc.npc_name, npc.current_action.display_name, npc.current_action.duration
			])
			npc_action_completed.emit(npc.npc_id, npc.current_action, true)
			
			DailyReportManager.report_task_completion(
				npc.npc_id, npc.npc_name, npc.current_action.display_name,
				"location", {"duration": npc.current_action.duration}
			)
			
			npc.current_action = null
			npc.current_action_index += 1
		else:
			return
	
	# Start next action
	if npc.current_action_index < npc.active_entry.actions.size():
		var action: NPCAction = npc.active_entry.actions[npc.current_action_index]
		
		if not _is_callback_valid(action):
			push_error("[ACTION] %s: Invalid callback for '%s'" % [npc.npc_name, action.display_name])
			DailyReportManager.report_task_failure(npc.npc_id, npc.npc_name, action.display_name, "Invalid callback", "location", {})
			npc.current_action_index += 1
			return
		
		var result: Dictionary = action.execute()
		
		if result.success:
			npc.current_action = action
			print("[ACTION] %s: Started '%s' (duration: %.1fs)" % [
				npc.npc_name, action.display_name, action.duration
			])
			npc_action_started.emit(npc.npc_id, action)
			
			if action.duration <= 0.0:
				action.complete()
				print("[ACTION] %s: Instant complete '%s'" % [npc.npc_name, action.display_name])
				npc_action_completed.emit(npc.npc_id, action, true)
				DailyReportManager.report_task_completion(npc.npc_id, npc.npc_name, action.display_name, "location", {})
				npc.current_action = null
				npc.current_action_index += 1
		else:
			print("[ACTION] %s: Failed to start '%s' - %s" % [npc.npc_name, action.display_name, result.reason])
			DailyReportManager.report_task_failure(npc.npc_id, npc.npc_name, action.display_name, result.reason, "location", {})
			npc.current_action_index += 1
	else:
		# All actions complete
		print("[SCHEDULE] %s: Completed all actions for '%s'" % [npc.npc_name, npc.active_entry.id])
		var day: int = DayAndNightCycleManager.get_current_time().day if DayAndNightCycleManager else -1
		npc.active_entry.mark_complete(day)
		npc.active_entry = null
		npc.current_action_index = 0
		npc.current_action = null
		npc.state.change_to(NPCState.Type.IDLE)


func _is_callback_valid(action: NPCAction) -> bool:
	if not action.callback.is_valid():
		return false
	var obj: Object = action.callback.get_object()
	return obj != null and is_instance_valid(obj)


# =============================================
# SCHEDULING
# =============================================
func _on_time_tick(day: int, hour: int, minute: int) -> void:
	var total_minute: int = hour * 60 + minute
	for npc_id: String in simulated_npcs:
		_check_schedule(simulated_npcs[npc_id], total_minute, day)


func _check_schedule(npc: NPCSimulationState, current_minute: int, day: int = -1) -> void:
	for entry: ScheduleEntry in npc.schedule:
		if entry.is_active(current_minute, day) and npc.active_entry != entry:
			if not npc.is_busy() or not npc.active_entry:
				_activate_schedule(npc, entry)
			return


func _activate_schedule(npc: NPCSimulationState, entry: ScheduleEntry) -> void:
	print("[SCHEDULE] %s: Activating '%s' -> zone '%s'" % [npc.npc_name, entry.id, entry.zone_name])
	
	npc.active_entry = entry
	npc.current_action_index = 0
	npc.current_action = null
	npc.is_moving_to_waypoint = false
	npc.clear_path()
	
	var target_floor: int = _get_zone_floor(entry.zone_name, npc)
	
	if npc.navigation.set_destination(entry.zone_name, target_floor, ZoneManager):
		npc.failed_destination = ""
		npc.pathfinding_retry_count = 0
		npc.state.change_to(NPCState.Type.NAVIGATING, {"destination": entry.zone_name})
		
		var waypoint: NPCNavigation.NavWaypoint = npc.navigation.get_current_waypoint()
		if waypoint:
			_start_waypoint_travel(npc, waypoint)
	else:
		push_error("[SCHEDULE] %s: Failed to plan route to '%s'" % [npc.npc_name, entry.zone_name])
		npc.failed_destination = entry.zone_name
		npc.navigation_cooldown = NAVIGATION_RETRY_DELAY


func _get_zone_floor(zone_name: String, npc: NPCSimulationState) -> int:
	if not ZoneManager:
		return 1
	var zone_id: int = ZoneManager.get_closest_zone_of_type_from_position(zone_name, npc.current_position)
	var zone: ZoneData = ZoneManager.get_zone_data(zone_id)
	return zone.floor if zone else 1


func reset_daily_schedules() -> void:
	print("[SCHEDULE] ===== DAILY RESET =====")
	for npc_id: String in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		for entry: ScheduleEntry in npc.schedule:
			if npc.active_entry != entry:
				entry.reset()
	
	# Check schedules for idle NPCs
	if DayAndNightCycleManager:
		var time: Dictionary = DayAndNightCycleManager.get_current_time()
		var minute: int = time.hour * 60 + time.minute
		for npc_id: String in simulated_npcs:
			var npc: NPCSimulationState = simulated_npcs[npc_id]
			if npc.is_idle() and not npc.active_entry:
				_check_schedule(npc, minute, time.day)


# =============================================
# SPAWNING
# =============================================
func spawn_npc(npc_type: String, spawn_position: Vector2 = Vector2.ZERO) -> String:
	var definition: Variant = NPCTypeRegistry.create_npc_definition(npc_type)
	if not definition:
		push_error("[SPAWN] Unknown NPC type: %s" % npc_type)
		return ""
	
	npc_id_counter += 1
	var npc_id: String = "%s_%d" % [npc_type, npc_id_counter]
	var start_pos: Vector2 = spawn_position if spawn_position != Vector2.ZERO else definition.start_position
	
	# Check for duplicate
	if simulated_npcs.has(npc_id):
		push_error("[SPAWN] NPC already exists: %s" % npc_id)
		return npc_id
	
	print("[SPAWN] Creating NPC: %s (%s) at %s" % [definition.npc_name, npc_id, start_pos])
	
	var npc: NPCSimulationState = NPCSimulationState.new(npc_id, npc_type, definition.npc_name, start_pos, definition.speed)
	npc.behavior_data["definition"] = definition
	npc.schedule = definition.get_schedule()
	
	npc.state.state_changed.connect(func(old: int, new: int) -> void: _on_npc_state_changed(npc_id, old, new))
	
	simulated_npcs[npc_id] = npc
	_spawn_visual(npc)
	
	npc_spawned.emit(npc_id, npc_type, start_pos)
	print("[SPAWN] NPC spawned: %s (total: %d)" % [npc_id, simulated_npcs.size()])
	return npc_id


func _spawn_visual(npc: NPCSimulationState) -> void:
	# Check if visual already exists
	if npc.npc_instance != null:
		print("[SPAWN] Visual already exists for %s, skipping" % npc.npc_id)
		return
	
	var scene: PackedScene = load("res://scenes/characters/base_npc/visual_npc.tscn")
	if not scene:
		push_error("[SPAWN] Failed to load visual_npc.tscn")
		return
	
	var instance: Node2D = scene.instantiate()
	
	# Set the npc_id so the visual can find its simulation state
	if "npc_id" in instance:
		instance.npc_id = npc.npc_id
	
	instance.global_position = npc.current_position
	
	var container: Node2D = FloorManager.get_floor_npc_container(npc.current_floor)
	if container:
		container.add_child(instance)
		print("[SPAWN] Visual added to floor %d container for %s" % [npc.current_floor, npc.npc_id])
	else:
		push_error("[SPAWN] No container for floor %d" % npc.current_floor)
		instance.queue_free()


func despawn_npc(npc_id: String) -> void:
	var npc: NPCSimulationState = simulated_npcs.get(npc_id)
	if not npc:
		return
	
	print("[SPAWN] Despawning NPC: %s" % npc_id)
	
	if npc.npc_instance:
		npc.npc_instance.queue_free()
		npc.npc_instance = null
	
	simulated_npcs.erase(npc_id)
	npc_despawned.emit(npc_id)


func _on_npc_state_changed(npc_id: String, old_state: int, new_state: int) -> void:
	var npc: NPCSimulationState = get_npc_state(npc_id)
	if npc:
		print("[STATE] %s: %s -> %s" % [
			npc.npc_name,
			NPCState.Type.keys()[old_state],
			NPCState.Type.keys()[new_state]
		])
	
	npc_state_changed.emit(npc_id, old_state, new_state)
	
	if new_state == NPCState.Type.IDLE:
		if npc and DayAndNightCycleManager:
			var time: Dictionary = DayAndNightCycleManager.get_current_time()
			_check_schedule(npc, time.hour * 60 + time.minute)


# =============================================
# VISUAL SYNC
# =============================================
func sync_npc_visual_to_simulation(npc: NPCSimulationState) -> void:
	if npc.npc_instance:
		npc.npc_instance.global_position = npc.current_position


func sync_all_npcs_on_floor(floor_number: int) -> void:
	print("[SYNC] Syncing all NPCs on floor %d" % floor_number)
	for npc_id: String in simulated_npcs:
		var npc: NPCSimulationState = simulated_npcs[npc_id]
		if npc.current_floor == floor_number:
			sync_npc_visual_to_simulation(npc)
			print("[SYNC] %s synced to %s" % [npc.npc_name, npc.current_position])


# =============================================
# SAVE/LOAD
# =============================================
func save_npcs() -> bool:
	var npcs_data: Array = []
	for npc_id: String in simulated_npcs:
		npcs_data.append(simulated_npcs[npc_id].to_dict())
	
	var save_data: Dictionary = {
		"version": "2.0",
		"npc_id_counter": npc_id_counter,
		"npcs": npcs_data
	}
	
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("[SAVE] Failed to save NPCs")
		return false
	
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("[SAVE] Saved %d NPCs" % npcs_data.size())
	npcs_saved.emit()
	return true


func load_npcs() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[LOAD] No save file found")
		return false
	
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false
	file.close()
	
	var save_data: Dictionary = json.data
	if not save_data.has("npcs"):
		return false
	
	print("[LOAD] Loading NPCs from save...")
	
	# Clear existing
	for npc_id: String in simulated_npcs.keys():
		despawn_npc(npc_id)
	simulated_npcs.clear()
	
	npc_id_counter = save_data.get("npc_id_counter", 0)
	
	await FloorManager.wait_for_all_floors_ready()
	
	for npc_data: Variant in save_data["npcs"]:
		var npc: NPCSimulationState = _create_npc_from_dict(npc_data)
		if npc:
			simulated_npcs[npc.npc_id] = npc
			_spawn_visual(npc)
	
	await get_tree().process_frame
	print("[LOAD] Loaded %d NPCs" % simulated_npcs.size())
	npcs_loaded.emit()
	return true


func _create_npc_from_dict(data: Dictionary) -> NPCSimulationState:
	var pos: Dictionary = data.get("current_position", {})
	var npc: NPCSimulationState = NPCSimulationState.new(
		data.get("npc_id", ""),
		data.get("npc_type", ""),
		data.get("npc_name", ""),
		Vector2(pos.get("x", 0), pos.get("y", 0)),
		data.get("speed", 100.0)
	)
	
	npc.from_dict(data)
	
	var definition: Variant = NPCTypeRegistry.create_npc_definition(npc.npc_type)
	if definition:
		npc.behavior_data["definition"] = definition
		npc.schedule = definition.get_schedule()
		
		var active_id: String = data.get("active_entry_id", "")
		if active_id:
			for entry in npc.schedule:
				if entry.id == active_id:
					npc.active_entry = entry
					break
		
		var action_data: Dictionary = data.get("current_action", {})
		if not action_data.is_empty() and npc.active_entry:
			if npc.current_action_index < npc.active_entry.actions.size():
				var action: NPCAction = npc.active_entry.actions[npc.current_action_index]
				action.restore_from_dict(action_data)
				npc.current_action = action
	
	npc.state.state_changed.connect(func(old: int, new: int) -> void: _on_npc_state_changed(npc.npc_id, old, new))
	
	print("[LOAD] Created NPC from save: %s at %s" % [npc.npc_name, npc.current_position])
	return npc


func delete_save() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.open("user://").remove(SAVE_PATH)
		print("[SAVE] Deleted save file")
		return true
	return false


func reset_npcs() -> void:
	print("[RESET] Resetting all NPCs")
	for npc_id: String in simulated_npcs.keys():
		despawn_npc(npc_id)
	simulated_npcs.clear()
	npc_id_counter = 0
	save_npcs()


# =============================================
# GETTERS
# =============================================
func get_npc_state(npc_id: String) -> NPCSimulationState:
	return simulated_npcs.get(npc_id)


func get_all_npc_states() -> Dictionary[String, NPCSimulationState]:
	return simulated_npcs


func get_npcs_by_type(npc_type: String) -> Array[NPCSimulationState]:
	var result: Array[NPCSimulationState] = []
	for npc_id: String in simulated_npcs:
		if simulated_npcs[npc_id].npc_type == npc_type:
			result.append(simulated_npcs[npc_id])
	return result


func get_npc_count() -> int:
	return simulated_npcs.size()


# =============================================
# DEBUG
# =============================================
func debug_npc(npc_id: String) -> void:
	var npc: NPCSimulationState = get_npc_state(npc_id)
	if npc:
		print(npc.debug_info())


func debug_all_npcs() -> void:
	print("=== NPCs: %d ===" % simulated_npcs.size())
	for npc_id: String in simulated_npcs:
		print(simulated_npcs[npc_id].debug_info())
