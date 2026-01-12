# MainHotelScene.gd - DEVELOPMENT ONLY - Remove for production build
extends Node2D

@onready var level_root: Node2D = $GameRoot/LevelRoot
@onready var player: Player = $Player
@onready var visual_npc_spawner: Node2D = $VisualNpcSpawner
@onready var camera_2d: Camera2D = $GameRoot/Camera2D

@export var starting_floor: int = 1
@export var preload_adjacent_floors: bool = false  # Usually false for 2D

var spawned_visuals: Dictionary = {}  # Dictionary[String, Node2D]

func _ready() -> void:
	# Initialize the game through GameManager
	GameManager.initialize_game(level_root, player, camera_2d, starting_floor)
	
	# Connect to GameManager signals if needed for dev purposes
	GameManager.player_floor_changed.connect(_on_dev_floor_changed)

func _on_dev_floor_changed(new_floor: int) -> void:
	"""Development callback for floor changes"""
	print("[DEV] Player is now on floor %d" % new_floor)

# --------------------------------------------
# Debug Controls - Remove for production
# --------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			# Floor switching
			KEY_1: GameManager.change_floor(1)
			KEY_2: GameManager.change_floor(2)
			#KEY_3: GameManager.change_floor(3)
			#KEY_4: GameManager.change_floor(4)
			#KEY_5: GameManager.change_floor(5)
			
			# NPC spawning for testing
			KEY_G: _dev_spawn_npc("ghost")
			KEY_V: _dev_spawn_npc("vampire")
			KEY_W: _dev_spawn_npc("werewolf")
			
			# Debug info
			KEY_F1: _dev_print_floor_info()
			KEY_F2: _dev_print_npcs_on_floor()
			KEY_F3: _dev_print_all_npcs()

# --------------------------------------------
# Development Helper Functions
# --------------------------------------------

func _dev_spawn_npc(npc_type: String) -> void:
	"""Spawn an NPC at the player's position for testing"""
	var spawn_pos: Vector2 = player.global_position + Vector2(randf_range(-100, 100), randf_range(-50, 50))
	var npc_id: String = NPCSimulationManager.spawn_npc(npc_type, spawn_pos)
	print("[DEV] Spawned %s (%s) at %s" % [npc_type, npc_id, spawn_pos])

func _dev_print_floor_info() -> void:
	"""Print current floor and loaded floors"""
	print("\n=== [DEV] FLOOR INFO ===")
	print("Current Floor: %d" % GameManager.get_current_floor())
	print("Loaded Floors: %s" % FloorManager.get_loaded_floors())
	print("All Floors: %s" % FloorManager.get_all_floors())

func _dev_print_npcs_on_floor() -> void:
	"""Print all NPCs on the current floor"""
	var current_floor: int = GameManager.get_current_floor()
	var npcs_on_floor: Array[String] = []
	
	for npc_id: Variant in NPCSimulationManager.get_all_npc_states():
		var state: NPCSimulationManager.NPCSimulationState = NPCSimulationManager.get_npc_state(npc_id)
		if state.current_floor == current_floor:
			npcs_on_floor.append("%s (%s)" % [state.npc_name, npc_id])
	
	print("\n=== [DEV] NPCs on Floor %d ===" % current_floor)
	if npcs_on_floor.is_empty():
		print("No NPCs on this floor")
	else:
		for npc_info in npcs_on_floor:
			print("  - %s" % npc_info)

func _dev_print_all_npcs() -> void:
	"""Print all NPCs in the game with their floor locations"""
	print("\n=== [DEV] ALL NPCs ===")
	print("Total NPCs: %d" % NPCSimulationManager.get_npc_count())
	
	for npc_id: Variant in NPCSimulationManager.get_all_npc_states():
		var state: NPCSimulationManager.NPCSimulationState = NPCSimulationManager.get_npc_state(npc_id)
		print("  - %s (%s) on Floor %d at %s" % [
			state.npc_name,
			npc_id,
			state.current_floor,
			state.position
		])
