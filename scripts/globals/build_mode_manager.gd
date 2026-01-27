# BuildModeManager.gd
# Autoload that manages build mode state and coordinates between systems
extends Node

signal build_mode_entered()
signal build_mode_exited()
signal piece_placed(piece_id: String, grid_pos: Vector2i, rotation: int)
signal piece_removed(grid_pos: Vector2i)

var is_active: bool = false

# References (set during game initialization)
var player: Node = null
var camera: Camera2D = null
@onready var placement_system: Node2D = $PlacementSystem

# Store original camera state for restoration
var _original_camera_target: Node2D = null
var _original_camera_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Wait for GameManager to initialize, then grab references
	if GameManager.game_started:
		_on_game_initialized()
	else:
		GameManager.game_initialized.connect(_on_game_initialized)


func _on_game_initialized() -> void:
	player = GameManager.player
	camera = GameManager.camera
	print("BuildModeManager: Initialized with player and camera references")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build_mode"):
		toggle_build_mode()


func toggle_build_mode() -> void:
	if is_active:
		exit_build_mode()
	else:
		enter_build_mode()


func enter_build_mode() -> void:
	if is_active:
		return
	
	if not player or not camera:
		push_error("BuildModeManager: Cannot enter build mode - missing player or camera reference")
		return
	
	print("BuildModeManager: Entering build mode")
	is_active = true
	
	# Disable player input/movement
	_set_player_input_enabled(false)
	
	# Switch camera to free mode
	_enable_free_camera()
	
	# Enable placement system
	if placement_system:
		placement_system.set_active(true)
	
	build_mode_entered.emit()


func exit_build_mode() -> void:
	if not is_active:
		return
	
	print("BuildModeManager: Exiting build mode")
	is_active = false
	
	# Disable placement system first (clears ghost preview)
	if placement_system:
		placement_system.set_active(false)
	
	# Restore camera to follow player
	_restore_camera()
	
	# Re-enable player input/movement
	_set_player_input_enabled(true)
	
	build_mode_exited.emit()


func _set_player_input_enabled(enabled: bool) -> void:
	if not player:
		return
	
	# Your player uses a state machine - we can disable processing
	# or set a flag. For now, disable the state machine node.
	var state_machine: Node = player.get_node_or_null("PlayerStateMachine")
	if state_machine:
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	
	# Also stop any current velocity
	if not enabled and player is CharacterBody2D:
		player.velocity = Vector2.ZERO


func _enable_free_camera() -> void:
	if not camera:
		return
	
	# Store original state
	_original_camera_target = camera.target
	_original_camera_position = camera.global_position
	
	# Detach camera from player (set target to null)
	camera.target = null
	
	# Camera will now be controlled by PlacementSystem for panning


func _restore_camera() -> void:
	if not camera:
		return
	
	# Restore original target
	camera.target = _original_camera_target
	_original_camera_target = null


func register_placement_system(system: Node) -> void:
	placement_system = system
	print("BuildModeManager: PlacementSystem registered")


# Utility for other systems to check build mode state
func is_build_mode_active() -> bool:
	return is_active
