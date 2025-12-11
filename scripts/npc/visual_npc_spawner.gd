extends Node

@export var player: Node2D
@export var current_floor: int = 1
@export var spawn_distance: float = 1000.0
@export var despawn_distance: float = 1500.0

const VISUAL_NPC_SCENE: PackedScene = preload("res://scenes/characters/base_npc/visual_npc.tscn")

var spawned_visuals: Dictionary[String, Node2D] = {}  # npc_id -> VisualNPC instance


func _ready() -> void:
	NPCSimulationManager.npc_spawned.connect(_on_npc_spawned_in_simulation)
	NPCSimulationManager.npc_despawned.connect(_on_npc_despawned_in_simulation)
	NPCSimulationManager.npc_state_changed.connect(_on_npc_state_changed)
	FloorManager.floor_changed.connect(_on_player_floor_change)

	_spawn_all_npcs_on_floor(current_floor)


func _process(_delta: float) -> void:
	if player == null:
		return

	for npc_id: String in NPCSimulationManager.get_all_npc_states():
		var npc_state: NPCSimulationManager.NPCSimulationState = NPCSimulationManager.get_npc_state(npc_id)

		if npc_state == null:
			continue

		var should_be_visible: bool = _should_npc_be_visible(npc_state)
		var is_currently_visible: bool = spawned_visuals.has(npc_id)

		if should_be_visible and not is_currently_visible:
			spawn_visual_npc(npc_id)
		elif not should_be_visible and is_currently_visible:
			despawn_visual_npc(npc_id)


func _should_npc_be_visible(npc_state: NPCSimulationManager.NPCSimulationState) -> bool:
	if npc_state.current_floor != current_floor:
		return false

	if player != null:
		var distance: float = player.global_position.distance_to(npc_state.current_position)

		if spawned_visuals.has(npc_state.npc_id):
			return distance < despawn_distance
		else:
			return distance < spawn_distance

	return true


func spawn_visual_npc(npc_id: String) -> Node2D:
	if spawned_visuals.has(npc_id):
		return spawned_visuals[npc_id]

	var npc_state: NPCSimulationManager.NPCSimulationState = NPCSimulationManager.get_npc_state(npc_id)
	if npc_state == null:
		push_error("Cannot spawn visual for unknown NPC: %s" % npc_id)
		return null

	var visual_npc: Node2D = VISUAL_NPC_SCENE.instantiate()
	visual_npc.npc_id = npc_id

	add_child(visual_npc)

	spawned_visuals[npc_id] = visual_npc
	print("Spawned visual for: %s (%s)" % [npc_state.npc_name, npc_id])

	return visual_npc


func despawn_visual_npc(npc_id: String) -> void:
	if not spawned_visuals.has(npc_id):
		return

	var visual_npc: Node2D = spawned_visuals[npc_id]
	spawned_visuals.erase(npc_id)

	if is_instance_valid(visual_npc):
		visual_npc.queue_free()
		print("Despawned visual for: %s" % npc_id)


func _spawn_all_npcs_on_floor(floor: int) -> void:
	for npc_id: String in NPCSimulationManager.get_all_npc_states():
		var npc_state: NPCSimulationManager.NPCSimulationState = NPCSimulationManager.get_npc_state(npc_id)

		if npc_state and npc_state.current_floor == floor:
			if _should_npc_be_visible(npc_state):
				spawn_visual_npc(npc_id)


func despawn_all_visuals() -> void:
	for npc_id: String in spawned_visuals.keys():
		despawn_visual_npc(npc_id)


func _on_player_floor_change(old_floor: int, new_floor: int) -> void:
	print("VISUAL NPC SPAWNER: PLAYER FLOOR CHANGE")

	if new_floor == current_floor:
		return

	print("Changing floor from %d to %d" % [current_floor, new_floor])

	despawn_all_visuals()

	current_floor = new_floor

	_spawn_all_npcs_on_floor(current_floor)


func _on_npc_spawned_in_simulation(npc_id: String, npc_type: String, position: Vector2) -> void:
	var npc_state: NPCSimulationManager.NPCSimulationState = NPCSimulationManager.get_npc_state(npc_id)

	if npc_state and _should_npc_be_visible(npc_state):
		spawn_visual_npc(npc_id)


func _on_npc_despawned_in_simulation(npc_id: String) -> void:
	despawn_visual_npc(npc_id)


func _on_npc_state_changed(npc_id: String, old_state: int, new_state: int) -> void:
	pass


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
