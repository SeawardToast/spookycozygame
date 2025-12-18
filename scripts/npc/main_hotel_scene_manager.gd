# MainHotelScene.gd - For 2D floor switching
extends Node2D

@onready var floor_container: Node2D = $FloorContainer
@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D
@onready var visual_npc_spawner: Node2D = $VisualNpcSpawner

@export var starting_floor: int = 1
@export var preload_adjacent_floors: bool = false  # Usually false for 2D

var spawned_visuals: Dictionary = {}  # Dictionary[String, Node2D]
var current_player_floor: int = 1
var game_started: bool = false

func _ready() -> void:
	print("=== HOTEL INITIALIZATION ===")
	
	# CRITICAL: Set the floor container in FloorManager
	FloorManager.set_main_container(floor_container)
	
	# Connect signals
	FloorManager.floor_changed.connect(_on_floor_changed)
	FloorManager.floor_loaded.connect(_on_floor_loaded)
	
	# Load and activate starting floor
	change_floor(starting_floor, true)
	
	# Load remaining floors
	load_floor(2, true)
	game_started = true
	
	# Spawn some initial guests
	call_deferred("_spawn_initial_npcs")
	

func _spawn_initial_npcs() -> void:
	print("=== Spawning NPCs ===")
	# Spawn some ghosts
	#for i in range(3):
		#var ghost_id: String = NPCSimulationManager.spawn_npc("ghost")
		#print("Spawned: %s" % ghost_id)
	
	NPCSimulationManager.spawn_npc("ghost", Vector2(200, 500))
	NPCSimulationManager.spawn_npc("vampire", Vector2(500, 500))
	print("Total NPCs: %d" % NPCSimulationManager.get_npc_count())

func change_floor(new_floor: int, initializing: bool = false) -> void:
	"""Change to a different floor"""
	if new_floor not in FloorManager.get_all_floors():
		push_warning("Floor %d does not exist" % new_floor)
		return
	
	# Set the new active floor (loads if needed, shows it)
	FloorManager.set_active_floor(new_floor, initializing)
	print("MainScene: Now on floor %d" % new_floor)

func load_floor(floor: int, initializing: bool = false) -> void:
	"""Load a floor without changing to it"""
	if floor not in FloorManager.get_all_floors():
		push_warning("Floor %d does not exist" % floor)
		return
	
	# Set the new active floor (loads if needed, shows it)
	FloorManager.load_floor(floor)

# Signal handlers
func _on_floor_changed(old_floor: int, new_floor: int) -> void:
	current_player_floor = new_floor
	$Camera2D.recalculate_bounds()
	print("MainScene: Floor changed %d -> %d" % [old_floor, new_floor])

func _on_floor_loaded(floor_number: int) -> void:
	print("MainScene: Floor %d loaded" % floor_number)

# Debug controls
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: change_floor(1)
			KEY_2: change_floor(2)
			#KEY_3: change_floor(3)
			#KEY_4: change_floor(4)
			#KEY_5: change_floor(5)
			#KEY_G: spawn_guest_on_current_floor("ghost")
			#KEY_V: spawn_guest_on_current_floor("vampire")
			#KEY_W: spawn_guest_on_current_floor("werewolf")
			#KEY_R: spawn_guest_on_current_floor()
			KEY_F1:
				print("\n=== CURRENT FLOOR: %d ===" % current_player_floor)
				print("Loaded floors: %s" % FloorManager.get_loaded_floors())
			KEY_F2:
				var npcs_on_floor: Array[String] = []
				for npc_id: Variant in NPCSimulationManager.get_all_npc_states():
					var state: NPCSimulationManager.NPCSimulationState = NPCSimulationManager.get_npc_state(npc_id)
					if state.current_floor == current_player_floor:
						npcs_on_floor.append(state.npc_name)
				print("\n=== NPCs on Floor %d ===" % current_player_floor)
				print(npcs_on_floor)
