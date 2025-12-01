# NPCSimulationManager.gd
# Global singleton that simulates all NPCs without requiring visual representation
extends Node

# Stores simulation state for all NPCs
var simulated_npcs: Dictionary = {} # npc_id -> NPCSimulationState
var npc_id_counter: int = 0

signal npc_arrived_at_zone(npc_id: String, zone_name: String, position: Vector2)
signal npc_action_attempted(npc_id: String, action_name: String)
signal npc_action_failed(npc_id: String, action_name: String, reason: String)
signal npc_started_traveling(npc_id: String, from_pos: Vector2, to_pos: Vector2, zone_name: String)
signal npc_spawned(npc_id: String, npc_type: String, position: Vector2)
signal npc_despawned(npc_id: String)

class NPCSimulationState:
	var npc_id: String
	var npc_type: String # Type identifier (e.g., "ghost", "vampire", "werewolf")
	var npc_name: String
	var current_floor: int = 1
	var target_floor: int = 1
	var is_changing_floors: bool = false
	var direction_changing_floors: String = ""
	var current_position: Vector2
	var target_position: Vector2
	var speed: float
	var daily_schedule: Array
	var completed_schedule_entries: Array
	var active_schedule_entry: Dictionary
	var current_target_zone_name: String
	var current_actions: Array
	var is_traveling: bool
	var travel_start_time: float
	var travel_duration: float
	var npc_instance: Node # Optional reference to actual NPC if spawned
	var behavior_data: Dictionary # Store custom data for this NPC
	
	func update_floor(floor_number: int):
		"""Manually set the NPC's current floor"""
		current_floor = floor_number
		
	func update_target_floor_from_zone(zone_id: int):
		"""Look up which floor the target zone is on"""
		target_floor = ZoneManager.get_zone_floor(zone_id)
		is_changing_floors = (current_floor != target_floor)
	
	func _init(id: String, type: String, name: String, start_pos: Vector2, spd: float, schedule: Array):
		npc_id = id
		npc_type = type
		npc_name = name
		current_position = start_pos
		target_position = start_pos
		speed = spd
		daily_schedule = schedule
		completed_schedule_entries = []
		active_schedule_entry = {}
		current_target_zone_name = ""
		current_actions = []
		is_traveling = false
		travel_start_time = 0.0
		travel_duration = 0.0
		npc_instance = null
		behavior_data = {}

func _ready():
	DayAndNightCycleManager.time_tick.connect(_on_time_tick)

# Generate unique NPC ID
func _generate_npc_id(npc_type: String) -> String:
	npc_id_counter += 1
	return "%s_%d" % [npc_type, npc_id_counter]

# Spawn a new NPC of a specific type
func spawn_npc(npc_type: String, spawn_position: Vector2 = Vector2.ZERO) -> String:
	var npc_definition = NPCTypeRegistry.create_npc_definition(npc_type)
	if npc_definition == null:
		push_error("Unknown NPC type: %s" % npc_type)
		return ""
	
	var npc_id = _generate_npc_id(npc_type)
	npc_definition.npc_id = npc_id
		
	# Use spawn position if provided, otherwise use definition's default
	var start_pos = spawn_position if spawn_position != Vector2.ZERO else npc_definition.start_position
	
	# Register with custom initialization
	register_npc(
		npc_id,
		npc_type,
		npc_definition.npc_name,
		start_pos,
		npc_definition.speed,
		npc_definition.get_schedule(),
		npc_definition
	)
	
	emit_signal("npc_spawned", npc_id, npc_type, start_pos)
	print("Spawned NPC: %s (%s) at %s" % [npc_definition.npc_name, npc_type, start_pos])
	
	return npc_id
	

# Despawn an NPC (remove from simulation)
func despawn_npc(npc_id: String) -> void:
	var state = simulated_npcs.get(npc_id)
	if state == null:
		return
	
	# Remove visual instance if it exists
	if state.npc_instance != null:
		state.npc_instance.queue_free()
	
	simulated_npcs.erase(npc_id)
	emit_signal("npc_despawned", npc_id)
	print("Despawned NPC: %s" % npc_id)

# Register an NPC for simulation (now supports NPC definition object)
func register_npc(npc_id: String, npc_type: String, npc_name: String, start_position: Vector2, speed: float, schedule: Array, definition = null) -> void:
	var state = NPCSimulationState.new(npc_id, npc_type, npc_name, start_position, speed, schedule)
	
	# Store reference to definition for action callbacks
	if definition != null:
		state.behavior_data["definition"] = definition
	
	simulated_npcs[npc_id] = state
	print("Registered NPC for simulation: %s (%s) at %s" % [npc_name, npc_type, start_position])

# Unregister an NPC
func unregister_npc(npc_id: String) -> void:
	despawn_npc(npc_id)

# Get current state of an NPC
func get_npc_state(npc_id: String) -> NPCSimulationState:
	return simulated_npcs.get(npc_id)

# Get all NPC states
func get_all_npc_states() -> Dictionary:
	return simulated_npcs

# Get NPCs by type
func get_npcs_by_type(npc_type: String) -> Array:
	var npcs = []
	for npc_id in simulated_npcs:
		var state = simulated_npcs[npc_id]
		if state.npc_type == npc_type:
			npcs.append(state)
	return npcs

# Get count of active NPCs
func get_npc_count() -> int:
	return simulated_npcs.size()

# Get count of NPCs by type
func get_npc_count_by_type(npc_type: String) -> int:
	return get_npcs_by_type(npc_type).size()

# Time tick handler
func _on_time_tick(day: int, hour: int, minute: int) -> void:
	var total_minute = hour * 60 + minute
	for npc_id in simulated_npcs:
		_check_schedule(simulated_npcs[npc_id], total_minute)

# Check schedule for a specific NPC
func _check_schedule(state: NPCSimulationState, current_minute: int) -> void:
	for entry in state.daily_schedule:
		if entry in state.completed_schedule_entries:
			continue

		var start_minute = entry.get("start_minute", 0)
		var end_minute = entry.get("end_minute", 0)
		
		if current_minute >= start_minute and current_minute < end_minute:

			if state.is_traveling:
				return
				
			if state.active_schedule_entry == entry:
				return
			
			var zone_name = entry.get("zone", "")
			var actions = entry.get("actions", [])
			print("gotta go to zoneee", zone_name)
			print("active schedule entry", state.active_schedule_entry)
			print("entry", entry)

			if zone_name != "":
				# is our target zone on a different floor? if so, walk to the stairs
				var closest_zone_id_of_type = ZoneManager.get_closest_zone_of_type_from_position(zone_name, state.current_position)
				var zone: ZoneData = ZoneManager.get_zone_data(closest_zone_id_of_type)
				var target_floor = zone.floor
				var direction = "up" if target_floor > state.current_floor else "down"
				# If the NPC is not on the same floor as the zone, walk to the staircase that it would logically take
				if target_floor != state.current_floor:
					state.target_floor = target_floor
					_start_travel_to_staircase(state, state.current_floor, direction)
				else:
					_start_travel_to_zone(state, zone_name, actions, entry)

			elif actions:
				state.active_schedule_entry = entry
				_attempt_actions(state, actions)
				state.completed_schedule_entries.append(entry)
				state.active_schedule_entry = {}
			return
		
		if current_minute >= end_minute and state.active_schedule_entry == entry:
			state.completed_schedule_entries.append(entry)
			state.active_schedule_entry = {}

# Enhanced _start_travel_to_zone with floor lookup:
func _start_travel_to_zone(state: NPCSimulationState, zone_name: String, actions: Array, entry: Dictionary):
	# Look up the zone's floor dynamically
	var closest_zone_id_of_type = ZoneManager.get_closest_zone_of_type_from_position(zone_name, state.current_position)
	var zone: ZoneData = ZoneManager.get_zone_data(closest_zone_id_of_type)
	var target_floor = zone.floor
	
	if zone.position == Vector2.ZERO:
		push_warning("Zone '%s' not found for NPC %s" % [zone_name, state.npc_name])
		state.active_schedule_entry = {}
		return
	
	# Update floor tracking
	state.update_target_floor_from_zone(closest_zone_id_of_type)
	
	# If changing floors, log it
	if state.is_changing_floors:
		print("%s traveling from floor %d to floor %d (zone: %s)" % 
			[state.npc_name, state.current_floor, target_floor, zone_name])
	
	# Get zone area if floor is loaded, otherwise use position directly
	var zone_area = ZoneManager.get_zone_area(closest_zone_id_of_type)
	var target_point: Vector2
	
	if zone_area:
		# Floor is loaded, use actual zone area
		target_point = _get_random_point_in_area(zone_area)
	else:
		# Floor not loaded, use zone position from registry
		target_point = zone.position
		print("Zone '%s' floor not loaded, using registry position" % zone_name)
	
	# Calculate travel duration
	var distance = state.current_position.distance_to(target_point)
	state.travel_duration = distance / state.speed
	state.travel_start_time = Time.get_ticks_msec() / 1000.0
	state.target_position = target_point
	state.current_target_zone_name = zone_name
	state.current_actions = actions
	state.is_traveling = true
	
	emit_signal("npc_started_traveling", state.npc_id, state.current_position, target_point, zone_name)
	
	print("=== SIMULATION: %s traveling to %s ===" % [state.npc_name, zone_name])
	print("From: Floor %d (%s) To: Floor %d (%s)" % 
		[state.current_floor, state.current_position, target_floor, target_point])
		
		
# Enhanced _start_travel_to_zone with floor lookup:
func _start_travel_to_staircase(state: NPCSimulationState, current_floor: int, direction: String):
	# Look up the stairs on the current floor for the target direction 
	# Fetch all nodes in a group
	var stairs = get_tree().get_nodes_in_group("stairs")
	var target_stairset
	state.direction_changing_floors = direction
	# Iterate through them
	for stairset in stairs:
		print("Stairset floor:", stairset.floor)
		if stairset.direction == direction and stairset.floor == current_floor:
			target_stairset = stairset
	
	if target_stairset.position == Vector2.ZERO:
		push_warning("Position not found for stairset on floor %s when attempting to path NPC" % [target_stairset.floor])
		state.active_schedule_entry = {}
		return
	
	# If changing floors, log it
	state.is_changing_floors = true
	var target_point = target_stairset.position
	
	# Calculate travel duration
	var distance = state.current_position.distance_to(target_point)
	state.travel_duration = distance / state.speed
	state.travel_start_time = Time.get_ticks_msec() / 1000.0
	state.target_position = target_point
	state.is_traveling = true
	
	emit_signal("npc_started_traveling", state.npc_id, state.current_position, target_point,"Staircase %s" % [target_stairset.floor])
	
	print("=== SIMULATION: %s traveling to %s ===" % [state.npc_name, "Staircase %s" % [target_stairset.floor]])

		
# Update simulation (called every frame)
func _process(delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	for npc_id in simulated_npcs:
		var state = simulated_npcs[npc_id]
		if state.is_traveling:
			var elapsed = current_time - state.travel_start_time
			
			if elapsed >= state.travel_duration:
				state.current_position = state.target_position
				state.is_traveling = false
				
				# did we arrive at a staircase, do we need to take a direciton action
				if state.is_changing_floors:
					state.is_changing_floors = false
					if state.direction_changing_floors == "up":
						print("NPC current floor updating")
						state.current_floor += 1
					elif state.direction_changing_floors == "down":
						print("NPC current floor updating")
						state.current_floor -= 1
				else:
					print("running zone arrival")
					_zone_arrival(state)
			else:
				var progress = elapsed / state.travel_duration
				state.current_position = state.current_position.lerp(state.target_position, progress * delta * 60.0)
				
				# Continuously update floor during travel (for floor transitions)
				var old_floor = state.current_floor
				#state.update_floor_from_position()
				
				# Detect when NPC changes floors mid-travel
				if old_floor != state.current_floor:
					print("%s crossed from floor %d to floor %d" % 
						[state.npc_name, old_floor, state.current_floor])

# Zone arrival handler
func _zone_arrival(state: NPCSimulationState) -> void:
	print("SIMULATION: %s arrived at %s" % [state.npc_name, state.current_target_zone_name])
	emit_signal("npc_arrived_at_zone", state.npc_id, state.current_target_zone_name, state.current_position)
	_attempt_actions(state, state.current_actions)

	if not state.active_schedule_entry.is_empty():
		state.completed_schedule_entries.append(state.active_schedule_entry)
		state.active_schedule_entry = {}

	state.current_target_zone_name = ""
	state.current_actions = []
	
# Staircase arrival handler
func _staircase_arrival(state: NPCSimulationState) -> void:
	print("SIMULATION: %s arrived at floor %s" % [state.npc_name, state.target_floor])
	emit_signal("npc_arrived_at_zone", state.npc_id, state.target_floor, state.current_position)

# Attempt actions
func _attempt_actions(state: NPCSimulationState, actions: Array = []):
	for action in actions:
		if typeof(action) == TYPE_CALLABLE:
			var result = action.call()
			var success = true
			var reason = ""
			if typeof(result) == TYPE_ARRAY and result.size() == 2:
				success = result[0]
				reason = result[1]
			elif typeof(result) == TYPE_BOOL:
				success = result
			if success:
				emit_signal("npc_action_attempted", state.npc_id, str(action))
			else:
				emit_signal("npc_action_failed", state.npc_id, str(action), reason)

# Get random point in area
func _get_random_point_in_area(area: Area2D) -> Vector2:
	var poly_node := area.get_node_or_null("CollisionPolygon2D")
	if poly_node == null:
		return area.global_position

	var polygon: PackedVector2Array = poly_node.polygon
	if polygon.size() == 0:
		return area.global_position

	var points: Array[Vector2] = []
	var xf: Transform2D = poly_node.global_transform
	for p in polygon:
		points.append(xf * p)

	var min_x = points[0].x
	var max_x = points[0].x
	var min_y = points[0].y
	var max_y = points[0].y
	for pt in points:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)

	for i in range(40):
		var random_point = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if Geometry2D.is_point_in_polygon(random_point, points):
			return random_point

	return points[0]

# Reset daily schedules (call at midnight)
func reset_daily_schedules() -> void:
	for npc_id in simulated_npcs:
		var state = simulated_npcs[npc_id]
		state.completed_schedule_entries.clear()
		state.active_schedule_entry = {}
