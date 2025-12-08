# VisualNPCSpawner.gd
# Manages spawning/despawning visual NPCs based on player location
extends Node

@export var player: Node2D  # Reference to player
@export var current_floor: int = 1
@export var spawn_distance: float = 1000.0  # Only spawn NPCs within this distance
@export var despawn_distance: float = 1500.0  # Despawn if further than this

# Scene references
const VISUAL_NPC_SCENE = preload("res://scenes/characters/base_npc/visual_npc.tscn")

var spawned_visuals: Dictionary = {}  # npc_id -> VisualNPC instance

func _ready():
	# Connect to simulation signals
	NPCSimulationManager.npc_spawned.connect(_on_npc_spawned_in_simulation)
	NPCSimulationManager.npc_despawned.connect(_on_npc_despawned_in_simulation)
	NPCSimulationManager.npc_state_changed.connect(_on_npc_state_changed)
	FloorManager.floor_changed.connect(_on_player_floor_change)
	
	# Initial spawn of all NPCs on current floor
	_spawn_all_npcs_on_floor(current_floor)

func _process(_delta: float) -> void:
	if player == null:
		return
	
	# Check distance for all simulated NPCs
	for npc_id in NPCSimulationManager.get_all_npc_states():
		var npc_state = NPCSimulationManager.get_npc_state(npc_id)
		
		if npc_state == null:
			continue
		
		var should_be_visible = _should_npc_be_visible(npc_state)
		var is_currently_visible = spawned_visuals.has(npc_id)
		
		if should_be_visible and not is_currently_visible:
			spawn_visual_npc(npc_id)
		elif not should_be_visible and is_currently_visible:
			despawn_visual_npc(npc_id)

## Check if NPC should have a visual representation
func _should_npc_be_visible(npc_state: NPCSimulationManager.NPCSimulationState) -> bool:
	# Must be on same floor as player
	if npc_state.current_floor != current_floor:
		return false
	
	# Must be within spawn distance
	if player != null:
		var distance = player.global_position.distance_to(npc_state.current_position)
		
		# Use hysteresis: different distances for spawn vs despawn
		if spawned_visuals.has(npc_state.npc_id):
			return distance < despawn_distance
		else:
			return distance < spawn_distance
	
	return true

## Spawn visual representation for an NPC
func spawn_visual_npc(npc_id: String) -> Node2D:
	if spawned_visuals.has(npc_id):
		return spawned_visuals[npc_id]
	
	var npc_state = NPCSimulationManager.get_npc_state(npc_id)
	if npc_state == null:
		push_error("Cannot spawn visual for unknown NPC: %s" % npc_id)
		return null
	
	# Instantiate visual NPC
	var visual_npc = VISUAL_NPC_SCENE.instantiate()
	visual_npc.npc_id = npc_id
	
	# Add to scene
	add_child(visual_npc)
	
	# Track it
	spawned_visuals[npc_id] = visual_npc
	
	print("Spawned visual for: %s (%s)" % [npc_state.npc_name, npc_id])
	return visual_npc

## Despawn visual representation for an NPC
func despawn_visual_npc(npc_id: String) -> void:
	if not spawned_visuals.has(npc_id):
		return
	
	var visual_npc = spawned_visuals[npc_id]
	spawned_visuals.erase(npc_id)
	
	if is_instance_valid(visual_npc):
		visual_npc.queue_free()
		print("Despawned visual for: %s" % npc_id)

## Spawn all NPCs on a specific floor
func _spawn_all_npcs_on_floor(floor: int) -> void:
	for npc_id in NPCSimulationManager.get_all_npc_states():
		var npc_state = NPCSimulationManager.get_npc_state(npc_id)
		if npc_state and npc_state.current_floor == floor:
			if _should_npc_be_visible(npc_state):
				spawn_visual_npc(npc_id)

## Despawn all visual NPCs
func despawn_all_visuals() -> void:
	for npc_id in spawned_visuals.keys():
		despawn_visual_npc(npc_id)

## Change current floor (despawn old, spawn new)
func _on_player_floor_change(old_floor, new_floor) -> void:
	print("VISUAL NPC SPAWNER: PLAYER FLOOR CHANGE")
	if new_floor == current_floor:
		return
	
	print("Changing floor from %d to %d" % [current_floor, new_floor])
	
	# Despawn all current visuals
	despawn_all_visuals()
	
	current_floor = new_floor
	
	# Spawn NPCs on new floor
	_spawn_all_npcs_on_floor(current_floor)

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_npc_spawned_in_simulation(npc_id: String, npc_type: String, position: Vector2):
	var npc_state = NPCSimulationManager.get_npc_state(npc_id)
	if npc_state and _should_npc_be_visible(npc_state):
		spawn_visual_npc(npc_id)

func _on_npc_despawned_in_simulation(npc_id: String):
	despawn_visual_npc(npc_id)

func _on_npc_state_changed(npc_id: String, old_state: int, new_state: int):
	# Could trigger special effects when NPCs change state
	pass

# =============================================================================
# UTILITY METHODS
# =============================================================================

func get_visible_npc_count() -> int:
	return spawned_visuals.size()

func get_spawned_visual(npc_id: String) -> Node2D:
	return spawned_visuals.get(npc_id)

func is_npc_visible(npc_id: String) -> bool:
	return spawned_visuals.has(npc_id)

func debug_info() -> String:
	return """
	Visual NPC Spawner
	Current Floor: %d
	Visible NPCs: %d
	Total Simulated: %d
	""" % [
		current_floor,
		spawned_visuals.size(),
		NPCSimulationManager.get_npc_count()
	]
