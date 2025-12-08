# NPCSimulationManager.gd (Refactored)
extends Node

var simulated_npcs: Dictionary = {}
var npc_id_counter: int = 0

signal npc_arrived_at_zone(npc_id: String, zone_name: String, position: Vector2)
signal npc_action_attempted(npc_id: String, action_name: String)
signal npc_action_failed(npc_id: String, action_name: String, reason: String)
signal npc_started_traveling(npc_id: String, from_pos: Vector2, to_pos: Vector2, zone_name: String)
signal npc_spawned(npc_id: String, npc_type: String, position: Vector2)
signal npc_despawned(npc_id: String)
signal npc_state_changed(npc_id: String, old_state: int, new_state: int)

class NPCSimulationState:
	var npc_id: String
	var npc_type: String
	var npc_name: String
	var current_floor: int = 1
	var target_floor: int = 1
	var current_position: Vector2
	var target_position: Vector2
	var speed: float
	var daily_schedule: Array
	var completed_schedule_entries: Array
	var active_schedule_entry: Dictionary
	var current_target_zone_name: String
	var current_actions: Array
	var is_traveling: bool
	var is_changing_floors: bool
	var direction_changing_floors: String
	var travel_start_time: float
	var travel_duration: float
	var npc_instance: Node
	var behavior_data: Dictionary
	
	# State machine
	var state_machine: NPCStateMachine
	
	func update_floor(floor_number: int):
		"""Manually set the NPC's current floor"""
		current_floor = floor_number
	
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
		is_changing_floors = false
		direction_changing_floors = ""
		travel_start_time = 0.0
		travel_duration = 0.0
		npc_instance = null
		behavior_data = {}
		
		# Initialize state machine
		state_machine = NPCStateMachine.new(self)

func _ready():
	DayAndNightCycleManager.time_tick.connect(_on_time_tick)

func _generate_npc_id(npc_type: String) -> String:
	npc_id_counter += 1
	return "%s_%d" % [npc_type, npc_id_counter]

func spawn_npc(npc_type: String, spawn_position: Vector2 = Vector2.ZERO) -> String:
	var npc_definition = NPCTypeRegistry.create_npc_definition(npc_type)
	if npc_definition == null:
		push_error("Unknown NPC type: %s" % npc_type)
		return ""
	
	var npc_id = _generate_npc_id(npc_type)
	npc_definition.npc_id = npc_id
		
	var start_pos = spawn_position if spawn_position != Vector2.ZERO else npc_definition.start_position
	
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

func despawn_npc(npc_id: String) -> void:
	var state = simulated_npcs.get(npc_id)
	if state == null:
		return
	
	if state.npc_instance != null:
		state.npc_instance.queue_free()
	
	simulated_npcs.erase(npc_id)
	emit_signal("npc_despawned", npc_id)
	print("Despawned NPC: %s" % npc_id)

func register_npc(npc_id: String, npc_type: String, npc_name: String, start_position: Vector2, speed: float, schedule: Array, definition = null) -> void:
	var state = NPCSimulationState.new(npc_id, npc_type, npc_name, start_position, speed, schedule)
	
	if definition != null:
		state.behavior_data["definition"] = definition
	
	# Connect state machine signals
	state.state_machine.state_changed.connect(
		func(old_state, new_state): 
			_on_npc_state_changed(npc_id, old_state, new_state)
	)
	
	simulated_npcs[npc_id] = state
	print("Registered NPC for simulation: %s (%s) at %s" % [npc_name, npc_type, start_position])

func _on_npc_state_changed(npc_id: String, old_state: int, new_state: int) -> void:
	emit_signal("npc_state_changed", npc_id, old_state, new_state)
	print("NPC %s: %s -> %s" % [
		npc_id, 
		NPCStateMachine.State.keys()[old_state],
		NPCStateMachine.State.keys()[new_state]
	])

func get_npc_state(npc_id: String) -> NPCSimulationState:
	return simulated_npcs.get(npc_id)

func get_all_npc_states() -> Dictionary:
	return simulated_npcs

func get_npcs_by_type(npc_type: String) -> Array:
	var npcs = []
	for npc_id in simulated_npcs:
		var state = simulated_npcs[npc_id]
		if state.npc_type == npc_type:
			npcs.append(state)
	return npcs

func get_npc_count() -> int:
	return simulated_npcs.size()

func _on_time_tick(day: int, hour: int, minute: int) -> void:
	var total_minute = hour * 60 + minute
	for npc_id in simulated_npcs:
		_check_schedule(simulated_npcs[npc_id], total_minute)

func _check_schedule(state: NPCSimulationState, current_minute: int) -> void:
	# Don't interrupt busy NPCs
	if state.state_machine.is_busy():
		return
	
	if state.completed_schedule_entries == state.daily_schedule:
		state.completed_schedule_entries = []
	
	for entry in state.daily_schedule:
		if entry in state.completed_schedule_entries:
			continue

		var start_minute = entry.get("start_minute", 0)
		var end_minute = entry.get("end_minute", 0)
		
		if current_minute >= start_minute and current_minute < end_minute:
			if state.active_schedule_entry == entry:
				return
			
			var zone_name = entry.get("zone", "")
			var actions = entry.get("actions", [])

			if zone_name != "":
				var closest_zone_id = ZoneManager.get_closest_zone_of_type_from_position(zone_name, state.current_position)
				var zone: ZoneData = ZoneManager.get_zone_data(closest_zone_id)
				var target_floor = zone.floor
				
				if target_floor != state.current_floor:
					var direction = "up" if target_floor > state.current_floor else "down"
					state.target_floor = target_floor
					_start_travel_to_staircase(state, direction, zone_name, actions, entry)
				else:
					_start_travel_to_zone(state, zone_name, actions, entry)
		
		if current_minute >= end_minute:
			if state.active_schedule_entry == entry:
				state.completed_schedule_entries.append(entry)
				state.active_schedule_entry = {}

func _start_travel_to_zone(state: NPCSimulationState, zone_name: String, actions: Array, entry: Dictionary):
	var closest_zone_id = ZoneManager.get_closest_zone_of_type_from_position(zone_name, state.current_position)
	var zone: ZoneData = ZoneManager.get_zone_data(closest_zone_id)
	
	if zone.position == Vector2.ZERO:
		push_warning("Zone '%s' not found for NPC %s" % [zone_name, state.npc_name])
		return
	
	var zone_area = ZoneManager.get_zone_area(closest_zone_id)
	var target_point: Vector2
	
	if zone_area:
		target_point = _get_random_point_in_area(zone_area)
	else:
		target_point = zone.position
	
	var distance = state.current_position.distance_to(target_point)
	state.travel_duration = distance / state.speed
	state.travel_start_time = Time.get_ticks_msec() / 1000.0
	state.target_position = target_point
	state.current_target_zone_name = zone_name
	state.current_actions = actions
	state.active_schedule_entry = entry
	
	# Use state machine
	state.state_machine.change_state(NPCStateMachine.State.TRAVELING_TO_ZONE, {
		"zone_name": zone_name,
		"actions": actions
	})
	
	emit_signal("npc_started_traveling", state.npc_id, state.current_position, target_point, zone_name)

func _start_travel_to_staircase(state: NPCSimulationState, direction: String, final_zone: String, actions: Array, entry: Dictionary):
	var stairs = get_tree().get_nodes_in_group("stairs")
	var target_stairset = null
	
	for stairset in stairs:
		if stairset.direction == direction and stairset.floor == state.current_floor:
			target_stairset = stairset
			break
	
	if target_stairset == null or target_stairset.position == Vector2.ZERO:
		push_warning("No stairs found for floor %d direction %s" % [state.current_floor, direction])
		return
	
	var target_point = target_stairset.position
	var distance = state.current_position.distance_to(target_point)
	state.travel_duration = distance / state.speed
	state.travel_start_time = Time.get_ticks_msec() / 1000.0
	state.target_position = target_point
	state.direction_changing_floors = direction
	state.active_schedule_entry = entry
	
	# Use state machine
	state.state_machine.change_state(NPCStateMachine.State.TRAVELING_TO_STAIRS, {
		"floor": state.current_floor,
		"direction": direction,
		"final_zone_name": final_zone,
		"actions": actions
	})
	
	emit_signal("npc_started_traveling", state.npc_id, state.current_position, target_point, "Staircase")

func _process(delta: float) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	for npc_id in simulated_npcs:
		var state = simulated_npcs[npc_id]
		state.state_machine.update(delta, current_time)
		
		# Handle state-specific logic
		_handle_state_updates(state, current_time)

func _handle_state_updates(state: NPCSimulationState, current_time: float):
	match state.state_machine.current_state:
		NPCStateMachine.State.TRAVELING_TO_STAIRS:
			if not state.is_traveling:
				# Arrived at stairs
				state.state_machine.change_state(NPCStateMachine.State.CHANGING_FLOORS, {
					"direction": state.direction_changing_floors
				})
		
		NPCStateMachine.State.CHANGING_FLOORS:
			# After floor change, resume journey
			if state.current_floor == state.target_floor:
				var data = state.state_machine.state_data
				var zone_name = data.get("final_zone_name", "")
				if zone_name != "":
					_start_travel_to_zone(state, zone_name, 
						data.get("actions", []), 
						state.active_schedule_entry)
		
		NPCStateMachine.State.PERFORMING_ACTIONS:
			_zone_arrival(state)
			state.state_machine.change_state(NPCStateMachine.State.IDLE)

func _zone_arrival(state: NPCSimulationState) -> void:
	print("SIMULATION: %s arrived at %s" % [state.npc_name, state.current_target_zone_name])
	emit_signal("npc_arrived_at_zone", state.npc_id, state.current_target_zone_name, state.current_position)
	_attempt_actions(state, state.current_actions)

	if not state.active_schedule_entry.is_empty():
		state.completed_schedule_entries.append(state.active_schedule_entry)
		state.active_schedule_entry = {}

	state.current_target_zone_name = ""
	state.current_actions = []

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

func reset_daily_schedules() -> void:
	for npc_id in simulated_npcs:
		var state = simulated_npcs[npc_id]
		state.completed_schedule_entries.clear()
		state.active_schedule_entry = {}
		state.state_machine.change_state(NPCStateMachine.State.IDLE)
