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

func _ready() -> void:
	# Load main scene
	if not get_tree().root.has_node(main_scene_root_path):
		var node: Node = load(main_scene_path).instantiate()
		if node != null:
			get_tree().root.add_child(node)
			await get_tree().process_frame
	
	# Show menu on startup
	show_game_menu_screen()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_menu"):
		show_game_menu_screen()

# --------------------------------------------
# Game Start & Menu Flow
# --------------------------------------------

func start_game() -> void:
	"""Called from menu Start Game button - initializes and starts the game"""
	# If game already started, just resume (unpause)
	if game_started:
		print("GameManager: Resuming game")
		get_tree().paused = false
		return
	
	# Load save data
	SaveGameManager.load_game()
	
	# Get references from main scene
	var main_scene: Node = get_tree().root.get_node_or_null(main_scene_root_path)
	if not main_scene:
		push_error("GameManager: Cannot start game - main scene not found")
		return
	
	var level_root_ref: Node2D = main_scene.get_node_or_null("GameRoot/LevelRoot")
	var player_ref: Node = main_scene.get_node_or_null("GameRoot/Player")
	var camera_ref: Camera2D = main_scene.get_node_or_null("GameRoot/Camera2D")
	
	if not level_root_ref or not player_ref or not camera_ref:
		push_error("GameManager: Cannot start game - missing required nodes")
		return
	
	# Initialize the game
	_initialize_game(level_root_ref, player_ref, camera_ref, 1)

func exit_game() -> void:
	get_tree().quit()

func show_game_menu_screen() -> void:
	"""Open the game menu (initial or pause menu)"""
	# Only pause if game has started
	if game_started:
		get_tree().paused = true
	
	var game_menu_screen_instance: Node = game_menu_screen.instantiate()
	# Set process mode so menu works while paused
	game_menu_screen_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(game_menu_screen_instance)

# --------------------------------------------
# Game Initialization
# --------------------------------------------

func _initialize_game(level_root_ref: Node2D, player_ref: Node, camera_ref: Camera2D, starting_floor: int = 1) -> void:
	"""Internal initialization - sets up all game systems"""
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
	
	# Load additional floors
	load_floor(2, true)
	
	# Mark game as started and enable saving
	game_started = true
	SaveGameManager.allow_save_game = true
	
	game_initialized.emit()
	
	# Spawn initial NPCs
	call_deferred("_spawn_initial_npcs")

func initialize_game(level_root_ref: Node2D, player_ref: Node, camera_ref: Camera2D, starting_floor: int = 1) -> void:
	"""Public method for development/testing - directly initializes the game"""
	_initialize_game(level_root_ref, player_ref, camera_ref, starting_floor)

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
