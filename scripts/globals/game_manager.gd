# GameManager.gd
extends Node

var game_menu_screen: Resource = preload("res://scenes/ui/game_menu_screen.tscn")
var main_scene_path: String = "res://scenes/main_scene.tscn"
var main_scene_root_path: String = "/root/MainScene"

var current_player_floor: int = 1
var game_started: bool = false

# References set during initialization
var level_root: Node2D = null
var player: Node = null
var camera: Camera2D = null

signal game_initialized()
signal player_floor_changed(new_floor: int)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_menu"):
		show_game_menu_screen()

func start_game() -> void:
	# load main scene
	if get_tree().root.has_node(main_scene_root_path):
		return
	
	var node: Node = load(main_scene_path).instantiate()
	
	if node != null:
		get_tree().root.add_child(node)
	
	SaveGameManager.load_game()
	SaveGameManager.allow_save_game = true

func exit_game() -> void:
	get_tree().quit()

func show_game_menu_screen() -> void:
	var game_menu_screen_instance: Node = game_menu_screen.instantiate()
	get_tree().root.add_child(game_menu_screen_instance)

# --------------------------------------------
# Game Initialization
# --------------------------------------------

func initialize_game(level_root_ref: Node2D, player_ref: Node, camera_ref: Camera2D, starting_floor: int = 1) -> void:
	"""Called by main scene to set up core game systems"""
	print("=== GAME INITIALIZATION ===")
	
	# Store references
	level_root = level_root_ref
	player = player_ref
	camera = camera_ref
	current_player_floor = starting_floor
	
	# Set up FloorManager
	FloorManager.set_main_container(level_root)
	FloorManager.floor_changed.connect(_on_floor_changed)
	FloorManager.floor_loaded.connect(_on_floor_loaded)
	
	# Load and activate starting floor
	change_floor(starting_floor, true)
	
	# Load additional floors (you can customize this)
	load_floor(2, true)
	
	game_started = true
	game_initialized.emit()
	
	# Spawn initial NPCs
	call_deferred("_spawn_initial_npcs")

func _spawn_initial_npcs() -> void:
	"""Spawn starting NPCs for the game"""
	print("=== Spawning Initial NPCs ===")
	
	NPCSimulationManager.spawn_npc("ghost", Vector2(200, 500))
	NPCSimulationManager.spawn_npc("vampire", Vector2(500, 500))
	
	print("Total NPCs: %d" % NPCSimulationManager.get_npc_count())

# --------------------------------------------
# Floor Management
# --------------------------------------------

func change_floor(new_floor: int, initializing: bool = false) -> void:
	"""Change to a different floor"""
	if new_floor not in FloorManager.get_all_floors():
		push_warning("Floor %d does not exist" % new_floor)
		return
	
	FloorManager.set_active_floor(new_floor, initializing)
	print("GameManager: Now on floor %d" % new_floor)

func load_floor(floor: int, initializing: bool = false) -> void:
	"""Load a floor without changing to it"""
	if floor not in FloorManager.get_all_floors():
		push_warning("Floor %d does not exist" % floor)
		return
	
	FloorManager.load_floor(floor)

func _on_floor_changed(old_floor: int, new_floor: int) -> void:
	"""Handle floor changes"""
	current_player_floor = new_floor
	
	if camera:
		camera.recalculate_bounds()
	
	player_floor_changed.emit(new_floor)
	print("GameManager: Floor changed %d -> %d" % [old_floor, new_floor])

func _on_floor_loaded(floor_number: int) -> void:
	"""Handle floor loading completion"""
	print("GameManager: Floor %d loaded" % floor_number)

# --------------------------------------------
# Utility Functions
# --------------------------------------------

func get_current_floor() -> int:
	return current_player_floor

func is_game_started() -> bool:
	return game_started
