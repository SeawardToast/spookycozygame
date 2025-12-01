# MainHotelScene.gd - For 2D floor switching

extends Node2D

@onready var floor_container = $FloorContainer
@onready var player = $Player
@onready var camera = $Camera2D

@export var starting_floor: int = 1
@export var preload_adjacent_floors: bool = false  # Usually false for 2D

var spawned_visuals: Dictionary = {}
var current_player_floor: int = 1

func _ready():
	print("=== HOTEL INITIALIZATION ===")
	
	# CRITICAL: Set the floor container in FloorManager
	FloorManager.set_main_container(floor_container)
	
	# Connect signals
	FloorManager.floor_changed.connect(_on_floor_changed)
	FloorManager.floor_loaded.connect(_on_floor_loaded)
	NPCSimulationManager.npc_spawned.connect(_on_npc_spawned)
	NPCSimulationManager.npc_despawned.connect(_on_npc_despawned)
	
	# Load and activate starting floor
	change_floor(starting_floor, true)
	
	# Load remaining floors
	load_floor(2, true)
	
	# Spawn some initial guests
	call_deferred("_spawn_initial_guests")

func _spawn_initial_guests():
	"""Spawn guests on the current floor"""
	for i in 1:
		#var random_type = ["ghost", "vampire", "werewolf"][randi() % 3]
		var random_type = "ghost"
		var spawn_pos = Vector2(randf_range(200, 600), randf_range(200, 400))
		var npc_id = NPCSimulationManager.spawn_npc(random_type, spawn_pos)
		
		# Set the NPC's floor to current floor
		var state = NPCSimulationManager.get_npc_state(npc_id)
		if state:
			state.update_floor(current_player_floor)

func change_floor(new_floor: int, initializing = false):
	"""Change to a different floor"""
	if new_floor not in FloorManager.get_all_floors():
		push_warning("Floor %d does not exist" % new_floor)
		return
	
	var old_floor = current_player_floor
	current_player_floor = new_floor
	
	print("MainScene: Changing to floor %d" % new_floor)
	
	# Clear visuals from old floor
	_despawn_all_visuals()
	
	# Optionally unload old floor to save memory
	if not preload_adjacent_floors and old_floor != new_floor:
		FloorManager.unload_floor(old_floor)
	
	# Set the new active floor (loads if needed, shows it)
	FloorManager.set_active_floor(new_floor, initializing)
	
	# Position camera/player for new floor (if needed)
	# In 2D, floors are at same position, just different scenes shown
	print("MainScene: Now on floor %d" % new_floor)
	
func load_floor(floor: int, initializing = false):
	"""Change to a different floor"""
	if floor not in FloorManager.get_all_floors():
		push_warning("Floor %d does not exist" % floor)
		return
	
	# Set the new active floor (loads if needed, shows it)
	FloorManager.load_floor(floor)


func _process(delta: float):
	_update_visible_npcs()

func _update_visible_npcs():
	"""Only render NPCs on current floor"""
	for npc_id in NPCSimulationManager.get_all_npc_states():
		var state = NPCSimulationManager.get_npc_state(npc_id)
		
		# Only render NPCs on current floor
		if state.current_floor != current_player_floor:
			if npc_id in spawned_visuals:
				_despawn_visual(npc_id)
			continue
		
		# Render if on current floor
		if npc_id not in spawned_visuals:
			_spawn_visual(npc_id)

func _spawn_visual(npc_id: String):
	if npc_id in spawned_visuals:
		return
	
	var state = NPCSimulationManager.get_npc_state(npc_id)
	if not state:
		return
	
	var visual_scene = load("res://scenes/characters/base_npc/visual_npc.tscn")
	var visual = visual_scene.instantiate()
	visual.npc_id = npc_id
	visual.npc_type = state.npc_type
	visual.global_position = state.current_position
	
	# Add to the current floor node
	var floor_node = FloorManager.get_floor_node(current_player_floor)
	if floor_node:
		floor_node.add_child(visual)
		spawned_visuals[npc_id] = visual

func _despawn_visual(npc_id: String):
	if npc_id not in spawned_visuals:
		return
	
	spawned_visuals[npc_id].queue_free()
	spawned_visuals.erase(npc_id)

func _despawn_all_visuals():
	for visual in spawned_visuals.values():
		visual.queue_free()
	spawned_visuals.clear()

func spawn_guest_on_current_floor(npc_type: String = "") -> String:
	"""Spawn a guest on the current floor"""
	if npc_type == "":
		var types = ["ghost"]
		npc_type = types[randi() % types.size()]
	
	var spawn_pos = Vector2(randf_range(200, 600), randf_range(200, 400))
	var npc_id = NPCSimulationManager.spawn_npc(npc_type, spawn_pos)
	
	# Set floor
	var state = NPCSimulationManager.get_npc_state(npc_id)
	if state:
		state.update_floor(current_player_floor)
	
	return npc_id

# Signal handlers
func _on_floor_changed(old_floor: int, new_floor: int):
	current_player_floor = new_floor
	print("MainScene: Floor changed %d -> %d" % [old_floor, new_floor])

func _on_floor_loaded(floor_number: int):
	print("MainScene: Floor %d loaded" % floor_number)

func _on_npc_spawned(npc_id: String, npc_type: String, position: Vector2):
	pass  # Handled by _update_visible_npcs

func _on_npc_despawned(npc_id: String):
	_despawn_visual(npc_id)

# Debug controls
func _input(event):
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
				var npcs_on_floor = []
				for npc_id in NPCSimulationManager.get_all_npc_states():
					var state = NPCSimulationManager.get_npc_state(npc_id)
					if state.current_floor == current_player_floor:
						npcs_on_floor.append(state.npc_name)
				print("\n=== NPCs on Floor %d ===" % current_player_floor)
				print(npcs_on_floor)
