# VisualNPC.gd
# Refactored to sync with new state-based simulation system
extends CharacterBody2D

@onready var name_label: Label = $NameLabel
@export var npc_id: String = ""
@export var animated_sprite_2d: AnimatedSprite2D
@export var navigation_agent_2d: NavigationAgent2D
@export var use_navigation: bool = true  # If false, just lerp to simulated position

var simulation_state: NPCSimulationManager.NPCSimulationState = null
var is_synced: bool = false
var current_animation: String = ""

# Preload scenes or sprite frames for each type
const SPRITE_LIBRARY := {
	"ghost": preload("res://assets/game/characters/sprites/girl_ghost_1/girl_ghost_1.tres"),
	"vampire": preload("res://assets/game/characters/sprites/vampires/vampire_1/vampire_1.tres"),
	# Add more NPC types here
}

# Animation mapping based on state
const STATE_ANIMATIONS := {
	NPCState.Type.IDLE: "idle",
	NPCState.Type.NAVIGATING: "walk",
	NPCState.Type.PERFORMING_ACTIONS: "action",
	NPCState.Type.WAITING: "idle"
}

func _ready():
	if npc_id == "":
		push_error("VisualNPC must have an npc_id set!")
		return
	
	# Get simulation state from manager
	simulation_state = NPCSimulationManager.get_npc_state(npc_id)
	
	if simulation_state == null:
		push_warning("No simulation state found for NPC: %s" % npc_id)
		return
	
	# Store reference to this visual instance
	simulation_state.npc_instance = self
	
	# Setup sprite for NPC type
	_setup_sprite()
	
	# Setup name label
	_setup_name_label()
	
	# Sync initial position
	global_position = simulation_state.current_position
	
	# Setup navigation
	if navigation_agent_2d and use_navigation:
		navigation_agent_2d.target_desired_distance = 1
		navigation_agent_2d.velocity_computed.connect(_on_navigation_velocity_computed)
	
	# Connect to simulation signals
	_connect_signals()
	
	# Sync initial state
	_sync_to_simulation_state()
	
	is_synced = true
	print("Visual NPC spawned: %s (%s) at %s" % [
		simulation_state.npc_name, 
		simulation_state.npc_type, 
		global_position
	])

func _connect_signals() -> void:
	# Connect to manager signals
	NPCSimulationManager.npc_started_traveling.connect(_on_npc_started_traveling)
	NPCSimulationManager.npc_arrived_at_zone.connect(_on_npc_arrived_at_zone)
	NPCSimulationManager.npc_waypoint_reached.connect(_on_npc_waypoint_reached)
	NPCSimulationManager.npc_action_attempted.connect(_on_npc_action_attempted)
	
	# Connect to NPC's state changes
	if simulation_state and simulation_state.state:
		simulation_state.state.state_changed.connect(_on_simulation_state_changed)

func _setup_sprite() -> void:
	if animated_sprite_2d == null:
		push_warning("%s has no AnimatedSprite2D assigned!" % npc_id)
		return
	
	var npc_type = simulation_state.npc_type
	
	if not SPRITE_LIBRARY.has(npc_type):
		push_warning("Unknown npc_type '%s' for %s" % [npc_type, npc_id])
		return
	
	animated_sprite_2d.sprite_frames = SPRITE_LIBRARY[npc_type]
	_play_animation("idle")

func _setup_name_label() -> void:
	if name_label == null:
		return
	
	name_label.text = simulation_state.npc_name

func _sync_to_simulation_state() -> void:
	if simulation_state == null:
		return
	
	# Sync position
	global_position = simulation_state.current_position
	
	# Sync animation based on state
	_update_animation_for_state(simulation_state.state.type)
	
	# Sync navigation target if navigating
	if simulation_state.state.type == NPCState.Type.NAVIGATING:
		if navigation_agent_2d and use_navigation:
			navigation_agent_2d.target_position = simulation_state.target_position

# =============================================================================
# SIGNAL HANDLERS - Simulation Events
# =============================================================================

func _on_simulation_state_changed(old_state: int, new_state: int) -> void:
	print("Visual %s: State changed %s -> %s" % [
		simulation_state.npc_name,
		NPCState.Type.keys()[old_state],
		NPCState.Type.keys()[new_state]
	])
	
	_update_animation_for_state(new_state)
	
	# Handle state-specific visual changes
	match new_state:
		NPCState.Type.NAVIGATING:
			if navigation_agent_2d and use_navigation:
				navigation_agent_2d.target_position = simulation_state.target_position
		
		NPCState.Type.IDLE:
			velocity = Vector2.ZERO
		
		NPCState.Type.PERFORMING_ACTIONS:
			_play_action_animation()

func _on_npc_started_traveling(id: String, from_pos: Vector2, to_pos: Vector2, destination: String):
	if id != npc_id:
		return
	
	print("Visual %s: Starting travel to %s" % [simulation_state.npc_name, destination])
	
	if navigation_agent_2d and use_navigation:
		navigation_agent_2d.target_position = to_pos
	_play_animation("walk")

func _on_npc_arrived_at_zone(id: String, zone_name: String, position: Vector2):
	if id != npc_id:
		return
	
	print("Visual %s: Arrived at %s" % [simulation_state.npc_name, zone_name])
	velocity = Vector2.ZERO

func _on_npc_floor_changedd(id: String, new_floor: int):
	if id != npc_id:
		return
		
	if navigation_agent_2d:
			navigation_agent_2d.navigation_layers = 1 << (simulation_state.current_floor - 1)

func _on_npc_waypoint_reached(id: String, waypoint_type: String, position: Vector2):
	if id != npc_id:
		return
	
	print("Visual %s: Reached waypoint: %s" % [simulation_state.npc_name, waypoint_type])
	
	# Play special animation for stairs
	if waypoint_type == "stairs_up" or waypoint_type == "stairs_down":
		_play_animation("climb")

func _on_npc_action_attempted(id: String, action: NPCAction, success: bool):
	if id != npc_id:
		return
	
	if success:
		print("Visual %s: Completed action: %s" % [simulation_state.npc_name, action.display_name])
	else:
		print("Visual %s: Failed action: %s" % [simulation_state.npc_name, action.display_name])
	
	# Could trigger particle effects, sounds, etc.
	_play_action_effect(action, success)

# =============================================================================
# ANIMATION SYSTEM
# =============================================================================

func _update_animation_for_state(state_type: int) -> void:
	if animated_sprite_2d == null:
		return
	
	var anim = STATE_ANIMATIONS.get(state_type, "idle")
	_play_animation(anim)

func _play_animation(anim_name: String) -> void:
	if animated_sprite_2d == null:
		return
	
	# Check if animation exists
	if not animated_sprite_2d.sprite_frames.has_animation(anim_name):
		# Fall back to idle if animation doesn't exist
		if animated_sprite_2d.sprite_frames.has_animation("idle"):
			anim_name = "idle"
		else:
			return
	
	if current_animation != anim_name:
		current_animation = anim_name
		animated_sprite_2d.play(anim_name)

func _play_action_animation() -> void:
	# Try to play action-specific animation if it exists
	if simulation_state.active_entry != null:
		var action_count = simulation_state.active_entry.actions.size()
		if simulation_state.current_action_index < action_count:
			var action = simulation_state.active_entry.actions[simulation_state.current_action_index]
			var action_anim = "action_" + action.action_id
			
			if animated_sprite_2d and animated_sprite_2d.sprite_frames.has_animation(action_anim):
				_play_animation(action_anim)
				return
	
	# Fall back to generic action animation
	_play_animation("action")

func _play_action_effect(action: NPCAction, success: bool) -> void:
	# Override this in derived classes or add particle effects, sounds, etc.
	# Example:
	# if action.action_id == "eat":
	#     $EatParticles.emitting = true
	# elif action.action_id == "sleep":
	#     $SleepParticles.emitting = true
	pass

# =============================================================================
# MOVEMENT & PHYSICS
# =============================================================================

func _physics_process(delta: float) -> void:
	if not is_synced or simulation_state == null:
		return
	
	# Update based on simulation state
	match simulation_state.state.type:
		NPCState.Type.NAVIGATING:
			_update_navigation(delta)
		
		NPCState.Type.IDLE, NPCState.Type.WAITING:
			_update_idle(delta)
		
		NPCState.Type.PERFORMING_ACTIONS:
			_update_performing_actions(delta)
	
	# Update sprite direction
	_update_sprite_direction()

func _update_navigation(delta: float) -> void:
	if use_navigation and navigation_agent_2d:
		# Use NavigationAgent2D for pathfinding
		if not navigation_agent_2d.is_navigation_finished():
			var next_pos = navigation_agent_2d.get_next_path_position()
			var target_direction: Vector2 = global_position.direction_to(next_pos)
			var vel: Vector2 = target_direction * simulation_state.speed
			
			if navigation_agent_2d.avoidance_enabled:
				navigation_agent_2d.velocity = vel
			else:
				velocity = vel
				move_and_slide()
	else:
		# Move at same speed as simulation, not smoothing lerp
		var distance = global_position.distance_to(simulation_state.target_position)
		
		if distance <= 4.0:
			velocity = Vector2.ZERO
			return
		
		# Move directly toward target at simulation speed
		var direction = global_position.direction_to(simulation_state.target_position)
		velocity = direction * simulation_state.speed
		
		# Update position
		var move_amount = simulation_state.speed * delta
		if move_amount >= distance:
			global_position = simulation_state.target_position
			velocity = Vector2.ZERO
		else:
			global_position += velocity * delta

func _update_idle(delta: float) -> void:
	# Smoothly stop movement
	velocity = velocity.lerp(Vector2.ZERO, delta * 10.0)

#	 Ensure we're at the simulated position
	var distance_to = global_position.distance_to(simulation_state.current_position)
	if distance_to > 1.0:
		global_position = global_position.lerp(simulation_state.current_position, delta * 3.0)

func _update_performing_actions(delta: float) -> void:
	# Stay still while performing actions
	velocity = Vector2.ZERO
	
	# Could add subtle idle movements here (bobbing, etc.)

func _update_sprite_direction() -> void:
	if animated_sprite_2d == null:
		return
	
	# Flip sprite based on movement direction
	if velocity.x != 0:
		animated_sprite_2d.flip_h = velocity.x < 0

func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

# =============================================================================
# UTILITY METHODS
# =============================================================================

func get_simulation_state() -> NPCSimulationManager.NPCSimulationState:
	return simulation_state

func is_in_state(state_type: int) -> bool:
	return simulation_state != null and simulation_state.state.type == state_type

func get_current_state_name() -> String:
	if simulation_state and simulation_state.state:
		return simulation_state.state.get_name()
	return "UNKNOWN"

func debug_info() -> String:
	if simulation_state:
		return """
		Visual NPC: %s
		Position: %s
		Velocity: %s
		Animation: %s
		Simulation State: %s
		Floor: %d
		""" % [
			simulation_state.npc_name,
			global_position,
			velocity,
			current_animation,
			get_current_state_name(),
			simulation_state.current_floor
		]
	return "No simulation state"

# =============================================================================
# CLEANUP
# =============================================================================

func _exit_tree():
	# Disconnect signals
	NPCSimulationManager.npc_started_traveling.disconnect(_on_npc_started_traveling)
	NPCSimulationManager.npc_arrived_at_zone.disconnect(_on_npc_arrived_at_zone)
	NPCSimulationManager.npc_waypoint_reached.disconnect(_on_npc_waypoint_reached)
	NPCSimulationManager.npc_action_attempted.disconnect(_on_npc_action_attempted)
	
	if simulation_state and simulation_state.state:
		simulation_state.state.state_changed.disconnect(_on_simulation_state_changed)
	
	# Clear reference when visual is removed
	if simulation_state:
		simulation_state.npc_instance = null
	
	print("Visual NPC despawned: %s" % npc_id)
