# VisualNPC.gd
# Lightweight visual representation that syncs with simulation
extends CharacterBody2D

@export var npc_id: String = ""
@export var npc_type: String = ""
@export var animated_sprite_2d: AnimatedSprite2D
@export var navigation_agent_2d: NavigationAgent2D
@export var use_navigation: bool = true # If false, just lerp to simulated position

var simulation_state: NPCSimulationManager.NPCSimulationState = null
var is_synced: bool = false

# Preload scenes or sprite frames for each type
const SPRITE_LIBRARY := {
	"ghost": preload("res://assets/game/characters/sprites/ghost.tres"),
}

func _ready():
	if npc_id == "":
		push_error("VisualNPC must have an npc_id set!")
		return
	
	_select_sprite_for_type()

	# Get simulation state from manager
	simulation_state = NPCSimulationManager.get_npc_state(npc_id)
	
	if simulation_state == null:
		push_warning("No simulation state found for NPC: %s" % npc_id)
		return
	
	# Store reference to this visual instance
	simulation_state.npc_instance = self
	
	# Sync initial position
	global_position = simulation_state.current_position
	
	# Connect to simulation signals
	NPCSimulationManager.npc_started_traveling.connect(_on_npc_started_traveling)
	NPCSimulationManager.npc_arrived_at_zone.connect(_on_npc_arrived_at_zone)
	
	if navigation_agent_2d and use_navigation:
		navigation_agent_2d.target_desired_distance = 4.0
		navigation_agent_2d.velocity_computed.connect(_on_navigation_agent_2d_velocity_computed)
	
	is_synced = true
	
func _select_sprite_for_type() -> void:
	if animated_sprite_2d == null:
		push_warning("%s has no AnimatedSprite2D assigned!" % npc_id)
		return
	
	if npc_type == "":
		push_warning("%s has no npc_type set!" % npc_id)
		return
	
	if not SPRITE_LIBRARY.has(npc_type):
		push_warning("Unknown npc_type '%s' for %s" % [npc_type, npc_id])
		return

	animated_sprite_2d.sprite_frames = SPRITE_LIBRARY[npc_type]
	animated_sprite_2d.play("idle") # optional default


func _on_npc_started_traveling(id: String, from_pos: Vector2, to_pos: Vector2, zone_name: String):
	if id != npc_id:
		return
	
	# Start visual movement
	if navigation_agent_2d and use_navigation:
		navigation_agent_2d.target_position = to_pos
	
	print("Visual NPC %s: Starting travel to %s" % [npc_id, zone_name])

func _on_npc_arrived_at_zone(id: String, zone_name: String, position: Vector2):
	if id != npc_id:
		return
	
	print("Visual NPC %s: Arrived at %s" % [npc_id, zone_name])

func _physics_process(delta: float) -> void:
	if not is_synced or simulation_state == null:
		return
	
	if use_navigation and navigation_agent_2d and simulation_state.is_traveling:
		# Use actual pathfinding
		if not navigation_agent_2d.is_navigation_finished():
			var next_pos = navigation_agent_2d.get_next_path_position()
			var target_direction: Vector2 = global_position.direction_to(next_pos)
			var vel: Vector2 = target_direction * simulation_state.speed
			
			if navigation_agent_2d.avoidance_enabled:
				navigation_agent_2d.velocity = vel
			else:
				velocity = vel
				move_and_slide()
			
			if animated_sprite_2d:
				animated_sprite_2d.flip_h = velocity.x < 0
	else:
		# Simple lerp to simulated position (for distant NPCs or simplified rendering)
		global_position = global_position.lerp(simulation_state.current_position, delta * 5.0)
		
		if animated_sprite_2d:
			var direction = simulation_state.current_position - global_position
			if direction.length() > 1.0:
				animated_sprite_2d.flip_h = direction.x < 0

func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()
	if animated_sprite_2d:
		animated_sprite_2d.flip_h = velocity.x < 0

func _exit_tree():
	# Clear reference when visual is removed
	if simulation_state:
		simulation_state.npc_instance = null
