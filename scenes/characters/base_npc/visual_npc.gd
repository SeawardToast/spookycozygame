# =============================================
# VisualNPC.gd (REFACTORED)
# =============================================
# Visual representation of an NPC with navigation map switching per floor

extends CharacterBody2D

@onready var name_label: Label = $NameLabel

@export var npc_id: String = ""
@export var animated_sprite_2d: AnimatedSprite2D
@export var navigation_agent_2d: NavigationAgent2D
@export var use_navigation: bool = true

const WAYPOINT_ARRIVAL_DISTANCE: float = 6.0
const VELOCITY_LERP_SPEED: float = 10.0
const IDLE_POSITION_SYNC_SPEED: float = 3.0
const ACTION_ANIMATION_FADE_SPEED: float = 2.0
const PERFORMING_ACTIONS_POSITION_SYNC_SPEED: float = 5.0

var simulation_state: Variant = null
var is_synced: bool = false
var current_animation: String = ""
var current_action_animation: String = ""

const SPRITE_LIBRARY: Dictionary[String, Resource] = {
	"ghost": preload("res://assets/game/characters/sprites/girl_ghost_1/girl_ghost_1.tres"),
	"vampire": preload("res://assets/game/characters/sprites/vampires/vampire_1/vampire_1.tres"),
}

const STATE_ANIMATIONS: Dictionary = {
	NPCState.Type.IDLE: "idle",
	NPCState.Type.NAVIGATING: "walk",
	NPCState.Type.PERFORMING_ACTIONS: "action",
	NPCState.Type.WAITING: "idle"
}

const ACTION_ANIMATIONS: Dictionary = {
	"eat": "eat",
	"read": "read",
	"sleep": "sleep",
	"haunt": "haunt",
	"scare": "scare",
	"read_books": "read",
	"contemplate": "sit",
}


# =============================================================================
# READY
# =============================================================================

func _ready() -> void:
	if npc_id == "":
		push_error("VisualNPC must have an npc_id set!")
		return
	
	simulation_state = NPCSimulationManager.get_npc_state(npc_id)
	if simulation_state == null:
		push_warning("No simulation state found for NPC: %s" % npc_id)
		return
	
	simulation_state.npc_instance = self
	
	_setup_sprite()
	_setup_name_label()
	
	global_position = simulation_state.current_position
	
	# REFACTORED: Set up navigation agent with the correct floor's navigation map
	if navigation_agent_2d and use_navigation:
		navigation_agent_2d.target_desired_distance = 1
		navigation_agent_2d.velocity_computed.connect(_on_navigation_velocity_computed)
		
		# Set the navigation map for the current floor
		_set_navigation_map_for_floor(simulation_state.current_floor)
	
	_connect_signals()
	_sync_to_simulation_state()
	
	is_synced = true
	
	print("Visual NPC spawned: %s (%s) at %s on floor %d" % [
		simulation_state.npc_name,
		simulation_state.npc_type,
		global_position,
		simulation_state.current_floor
	])


# =============================================================================
# NAVIGATION MAP MANAGEMENT (REFACTORED)
# =============================================================================

func _set_navigation_map_for_floor(floor_number: int) -> void:
	"""
	REFACTORED: Set the navigation agent to use a specific floor's navigation map.
	This is the key change from the layer-based approach.
	"""
	if navigation_agent_2d == null:
		return
	
	var floor_map_rid: RID = FloorManager.get_navigation_map_for_floor(floor_number)
	
	if floor_map_rid != RID():
		navigation_agent_2d.set_navigation_map(floor_map_rid)
		print("Visual %s: Set navigation map to floor %d (map: %s)" % [
			simulation_state.npc_name,
			floor_number,
			floor_map_rid
		])
	else:
		push_error("Visual %s: Failed to get navigation map for floor %d" % [
			simulation_state.npc_name,
			floor_number
		])


func _on_npc_floor_changed(id: String, old_floor: int, new_floor: int) -> void:
	"""Handle floor change by switching navigation maps"""
	if id != npc_id:
		return
	
	print("Visual %s: Floor changed %d -> %d" % [simulation_state.npc_name, old_floor, new_floor])
	
	# Switch to the new floor's navigation map
	_set_navigation_map_for_floor(new_floor)


# =============================================================================
# SIGNAL CONNECTIONS
# =============================================================================

func _connect_signals() -> void:
	NPCSimulationManager.npc_started_traveling.connect(_on_npc_started_traveling)
	NPCSimulationManager.npc_arrived_at_zone.connect(_on_npc_arrived_at_zone)
	NPCSimulationManager.npc_waypoint_reached.connect(_on_npc_waypoint_reached)
	NPCSimulationManager.npc_action_started.connect(_on_npc_action_started)
	NPCSimulationManager.npc_action_completed.connect(_on_npc_action_completed)
	NPCSimulationManager.npc_action_progress.connect(_on_npc_action_progress)
	
	# REFACTORED: Connect to floor change signal
	NPCSimulationManager.npc_floor_changed.connect(_on_npc_floor_changed)
	
	if simulation_state and simulation_state.state:
		simulation_state.state.state_changed.connect(_on_simulation_state_changed)


# =============================================================================
# SETUP
# =============================================================================

func _setup_sprite() -> void:
	if animated_sprite_2d == null:
		push_warning("%s has no AnimatedSprite2D assigned!" % npc_id)
		return
	
	var npc_type: String = simulation_state.npc_type
	if not SPRITE_LIBRARY.has(npc_type):
		push_warning("Unknown npc_type '%s' for %s" % [npc_type, npc_id])
		return
	
	animated_sprite_2d.sprite_frames = SPRITE_LIBRARY[npc_type]
	_play_animation("idle")


func _setup_name_label() -> void:
	if name_label:
		name_label.text = simulation_state.npc_name


func _sync_to_simulation_state() -> void:
	if simulation_state == null:
		return
	
	global_position = simulation_state.current_position
	_update_animation_for_state(simulation_state.state.type)
	
	if simulation_state.state.type == NPCState.Type.PERFORMING_ACTIONS and simulation_state.current_action:
		_play_action_animation(simulation_state.current_action)
	
	if simulation_state.state.type == NPCState.Type.NAVIGATING:
		if navigation_agent_2d and use_navigation:
			# REFACTORED: Ensure we're on the correct navigation map
			_set_navigation_map_for_floor(simulation_state.current_floor)
			navigation_agent_2d.target_position = simulation_state.target_position


# =============================================================================
# SIMULATION STATE SIGNALS
# =============================================================================

func _on_simulation_state_changed(old_state: int, new_state: int) -> void:
	print("Visual %s: State changed %s -> %s" % [
		simulation_state.npc_name,
		NPCState.Type.keys()[old_state],
		NPCState.Type.keys()[new_state]
	])
	
	_update_animation_for_state(new_state)
	
	match new_state:
		NPCState.Type.NAVIGATING:
			if navigation_agent_2d and use_navigation:
				navigation_agent_2d.target_position = simulation_state.target_position
		
		NPCState.Type.IDLE:
			velocity = Vector2.ZERO
			_play_animation("idle")
		
		NPCState.Type.PERFORMING_ACTIONS:
			pass


func _on_npc_started_traveling(id: String, from_pos: Vector2, to_pos: Vector2, destination: String) -> void:
	if id != npc_id:
		return
	
	print("Visual %s: Starting travel to %s (floor %d)" % [
		simulation_state.npc_name, 
		destination,
		simulation_state.current_floor
	])
	
	if navigation_agent_2d and use_navigation:
		# REFACTORED: Verify we're on the correct navigation map before pathfinding
		_verify_navigation_map()
		
		navigation_agent_2d.target_position = to_pos
		
		await get_tree().physics_frame
		
		if not navigation_agent_2d.is_target_reachable():
			push_warning("Visual %s: Target %s not reachable on floor %d!" % [
				simulation_state.npc_name,
				to_pos,
				simulation_state.current_floor
			])
			_debug_navigation_state()
	
	_play_animation("walk")


func _verify_navigation_map() -> void:
	"""
	REFACTORED: Verify and correct the navigation map if needed.
	This ensures the agent is always on the correct floor's map.
	"""
	if navigation_agent_2d == null or simulation_state == null:
		return
	
	var expected_map: RID = FloorManager.get_navigation_map_for_floor(simulation_state.current_floor)
	var current_map: RID = navigation_agent_2d.get_navigation_map()
	
	if current_map != expected_map:
		push_warning("Visual %s: Navigation map mismatch! Correcting..." % simulation_state.npc_name)
		navigation_agent_2d.set_navigation_map(expected_map)


func _debug_navigation_state() -> void:
	"""Debug helper to print navigation agent state"""
	if navigation_agent_2d == null:
		return
	
	var current_map: RID = navigation_agent_2d.get_navigation_map()
	var expected_map: RID = FloorManager.get_navigation_map_for_floor(simulation_state.current_floor)
	
	print("=== Visual NPC Navigation Debug ===")
	print("  NPC: %s" % simulation_state.npc_name)
	print("  Floor: %d" % simulation_state.current_floor)
	print("  Current Nav Map: %s" % current_map)
	print("  Expected Nav Map: %s" % expected_map)
	print("  Maps Match: %s" % (current_map == expected_map))
	print("  Target Position: %s" % navigation_agent_2d.target_position)
	print("  Target Reachable: %s" % navigation_agent_2d.is_target_reachable())
	print("  Navigation Finished: %s" % navigation_agent_2d.is_navigation_finished())
	print("===================================")


func _on_npc_arrived_at_zone(id: String, zone_name: String, position: Vector2) -> void:
	if id != npc_id:
		return
	
	print("Visual %s: Arrived at %s" % [simulation_state.npc_name, zone_name])
	velocity = Vector2.ZERO
	_play_animation("idle")


func _on_npc_waypoint_reached(id: String, waypoint_type: String, position: Vector2) -> void:
	if id != npc_id:
		return
	
	print("Visual %s: Reached waypoint: %s" % [simulation_state.npc_name, waypoint_type])
	
	if waypoint_type == "stairs_up" or waypoint_type == "stairs_down":
		_play_animation("climb")


func _on_npc_action_started(id: String, action: NPCAction) -> void:
	if id != npc_id:
		return
	
	print("Visual %s: Started action: %s (duration: %.1fs)" % [
		simulation_state.npc_name,
		action.display_name,
		action.duration
	])
	
	_play_action_animation(action)
	_play_action_start_effect(action)


func _on_npc_action_completed(id: String, action: NPCAction, success: bool) -> void:
	if id != npc_id:
		return
	
	if success:
		print("Visual %s: Completed action: %s" % [simulation_state.npc_name, action.display_name])
		_play_action_completion_effect(action, true)
	else:
		print("Visual %s: Failed action: %s" % [simulation_state.npc_name, action.display_name])
		_play_action_completion_effect(action, false)
	
	current_action_animation = ""
	
	if simulation_state.state.type != NPCState.Type.PERFORMING_ACTIONS:
		_play_animation("idle")


func _on_npc_action_progress(id: String, action: NPCAction, progress: float) -> void:
	if id != npc_id:
		return
	
	_update_action_visual_progress(action, progress)


# =============================================================================
# ANIMATIONS
# =============================================================================

func _update_animation_for_state(state_type: int) -> void:
	if animated_sprite_2d == null:
		return
	
	var anim_name: String = STATE_ANIMATIONS.get(state_type, "idle")
	_play_animation(anim_name)


func _play_animation(anim_name: String) -> void:
	if animated_sprite_2d == null:
		return
	
	if current_action_animation != "" and anim_name != current_action_animation:
		return
	
	if not animated_sprite_2d.sprite_frames.has_animation(anim_name):
		if animated_sprite_2d.sprite_frames.has_animation("idle"):
			anim_name = "idle"
		else:
			return
	
	if current_animation != anim_name:
		current_animation = anim_name
		animated_sprite_2d.play(anim_name)


func _play_action_animation(action: NPCAction) -> void:
	if animated_sprite_2d == null:
		return
	
	var action_anim: String = ""
	
	if ACTION_ANIMATIONS.has(action.action_id):
		action_anim = ACTION_ANIMATIONS[action.action_id]
	else:
		action_anim = "action_" + action.action_id
	
	if animated_sprite_2d.sprite_frames.has_animation(action_anim):
		current_action_animation = action_anim
		animated_sprite_2d.play(action_anim)
		print("  Playing animation: %s" % action_anim)
	else:
		if animated_sprite_2d.sprite_frames.has_animation("action"):
			current_action_animation = "action"
			animated_sprite_2d.play("action")
			print("  Playing fallback action animation")
		else:
			print("  No animation found for action: %s" % action.action_id)
			current_action_animation = ""


func _update_sprite_direction() -> void:
	if animated_sprite_2d == null:
		return
	
	if velocity.x != 0.0:
		animated_sprite_2d.flip_h = velocity.x < 0.0


# =============================================================================
# ACTION VISUAL EFFECTS
# =============================================================================

func _play_action_start_effect(action: NPCAction) -> void:
	pass


func _play_action_completion_effect(action: NPCAction, success: bool) -> void:
	if success:
		_flash_sprite(Color.GREEN, 0.2)
	else:
		_flash_sprite(Color.RED, 0.2)


func _update_action_visual_progress(action: NPCAction, progress: float) -> void:
	if action.action_id == "sleep":
		var alpha: float = 1.0 - (progress * 0.3)
		if animated_sprite_2d:
			animated_sprite_2d.modulate.a = alpha
	elif action.action_id == "haunt":
		if animated_sprite_2d:
			var flicker: float = 0.8 + (sin(progress * 20.0) * 0.2)
			animated_sprite_2d.modulate.a = flicker


func _flash_sprite(color: Color, duration: float) -> void:
	if animated_sprite_2d == null:
		return
	
	var original_modulate: Color = animated_sprite_2d.modulate
	animated_sprite_2d.modulate = color
	
	await get_tree().create_timer(duration).timeout
	
	if animated_sprite_2d:
		animated_sprite_2d.modulate = original_modulate


# =============================================================================
# PHYSICS
# =============================================================================

func _physics_process(delta: float) -> void:
	if not is_synced or simulation_state == null:
		return
	
	match simulation_state.state.type:
		NPCState.Type.NAVIGATING:
			_update_navigation(delta)
		
		NPCState.Type.IDLE, NPCState.Type.WAITING:
			_update_idle(delta)
		
		NPCState.Type.PERFORMING_ACTIONS:
			_update_performing_actions(delta)
	
	_update_sprite_direction()


func _update_navigation(delta: float) -> void:
	if use_navigation and navigation_agent_2d:
		if not navigation_agent_2d.is_navigation_finished():
			var next_pos: Vector2 = navigation_agent_2d.get_next_path_position()
			var dir: Vector2 = global_position.direction_to(next_pos)
			var vel: Vector2 = dir * simulation_state.speed
			
			if navigation_agent_2d.avoidance_enabled:
				navigation_agent_2d.velocity = vel
			else:
				velocity = vel
	else:
		var distance: float = global_position.distance_to(simulation_state.target_position)
		
		if distance <= WAYPOINT_ARRIVAL_DISTANCE:
			velocity = Vector2.ZERO
			return
		
		var direction: Vector2 = global_position.direction_to(simulation_state.target_position)
		velocity = direction * simulation_state.speed
		
		var move_amount: float = simulation_state.speed * delta
		if move_amount >= distance:
			global_position = simulation_state.target_position
			velocity = Vector2.ZERO
		else:
			global_position += velocity * delta


func _update_idle(delta: float) -> void:
	velocity = velocity.lerp(Vector2.ZERO, delta * VELOCITY_LERP_SPEED)
	
	var dist: float = global_position.distance_to(simulation_state.current_position)
	if dist > 1.0:
		global_position = global_position.lerp(simulation_state.current_position, delta * IDLE_POSITION_SYNC_SPEED)
	
	if animated_sprite_2d and animated_sprite_2d.modulate.a != 1.0:
		animated_sprite_2d.modulate.a = lerp(animated_sprite_2d.modulate.a, 1.0, delta * ACTION_ANIMATION_FADE_SPEED)


func _update_performing_actions(delta: float) -> void:
	velocity = Vector2.ZERO
	
	var dist: float = global_position.distance_to(simulation_state.current_position)
	if dist > 1.0:
		global_position = global_position.lerp(simulation_state.current_position, delta * PERFORMING_ACTIONS_POSITION_SYNC_SPEED)


func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()


# =============================================================================
# UTILITY
# =============================================================================

func get_simulation_state() -> Variant:
	return simulation_state


func is_in_state(state_type: int) -> bool:
	return simulation_state != null and simulation_state.state.type == state_type


func get_current_state_name() -> String:
	if simulation_state and simulation_state.state:
		return simulation_state.state.get_name()
	return "UNKNOWN"


func get_current_action_info() -> String:
	if simulation_state and simulation_state.current_action:
		var action: NPCAction = simulation_state.current_action
		return "%s (%.0f%% complete, %.1fs remaining)" % [
			action.display_name,
			action.get_progress() * 100.0,
			action.get_remaining_duration()
		]
	return "None"


func get_current_floor() -> int:
	if simulation_state:
		return simulation_state.current_floor
	return 1


func debug_info() -> String:
	if simulation_state:
		var nav_map_info: String = "N/A"
		if navigation_agent_2d:
			var current_map: RID = navigation_agent_2d.get_navigation_map()
			nav_map_info = str(current_map)
		
		return """
		Visual NPC: %s
		Position: %s
		Velocity: %s
		Animation: %s
		Action Animation: %s
		Current Action: %s
		Simulation State: %s
		Floor: %d
		Navigation Map: %s
		""" % [
			simulation_state.npc_name,
			global_position,
			velocity,
			current_animation,
			current_action_animation if current_action_animation != "" else "None",
			get_current_action_info(),
			get_current_state_name(),
			simulation_state.current_floor,
			nav_map_info
		]
	return "No simulation state"


# =============================================================================
# CLEANUP
# =============================================================================

func _exit_tree() -> void:
	NPCSimulationManager.npc_started_traveling.disconnect(_on_npc_started_traveling)
	NPCSimulationManager.npc_arrived_at_zone.disconnect(_on_npc_arrived_at_zone)
	NPCSimulationManager.npc_waypoint_reached.disconnect(_on_npc_waypoint_reached)
	NPCSimulationManager.npc_action_started.disconnect(_on_npc_action_started)
	NPCSimulationManager.npc_action_completed.disconnect(_on_npc_action_completed)
	NPCSimulationManager.npc_action_progress.disconnect(_on_npc_action_progress)
	NPCSimulationManager.npc_floor_changed.disconnect(_on_npc_floor_changed)
	
	if simulation_state and simulation_state.state:
		simulation_state.state.state_changed.disconnect(_on_simulation_state_changed)
	
	if simulation_state:
		simulation_state.npc_instance = null
	
	print("Visual NPC despawned: %s" % npc_id)
