extends CharacterBody2D

@onready var name_label: Label = $NameLabel

@export var npc_id: String = ""
@export var animated_sprite_2d: AnimatedSprite2D

const POSITION_SYNC_SPEED: float = 10.0
const ANIMATION_FADE_SPEED: float = 2.0

var simulation_state: Variant = null
var is_synced: bool = false
var current_animation: String = ""
var current_action_animation: String = ""

const SPRITE_LIBRARY: Dictionary[String, Resource] = {
	"ghost": preload("res://assets/game/characters/sprites/girl_ghost_1/girl_ghost_1.tres"),
	"vampire": preload("res://assets/game/characters/sprites/vampires/vampire_1/vampire_1.tres"),
}

const STATE_ANIMATIONS: Dictionary = {
	NPCState.Type.IDLE: "idle",
	NPCState.Type.NAVIGATING: "walk",
	NPCState.Type.PERFORMING_ACTIONS: "action",
	NPCState.Type.WAITING: "idle"
}

const ACTION_ANIMATIONS: Dictionary = {
	"eat": "eat",
	"read": "read",
	"sleep": "sleep",
	"haunt": "haunt",
	"scare": "scare",
	"read_books": "read",
	"contemplate": "sit",
}


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if npc_id == "":
		push_error("[VisualNPC] No npc_id set!")
		return
	
	simulation_state = NPCSimulationManager.get_npc_state(npc_id)
	if simulation_state == null:
		push_warning("[VisualNPC] No simulation state for: %s" % npc_id)
		queue_free()
		return
	
	# Check if there's already a visual instance - prevent duplicates
	if simulation_state.npc_instance != null and simulation_state.npc_instance != self:
		print("[VisualNPC] Duplicate detected for %s, removing self" % npc_id)
		queue_free()
		return
	
	simulation_state.npc_instance = self
	
	_setup_sprite()
	_setup_name_label()
	_connect_signals()
	_sync_to_simulation()
	
	is_synced = true
	print("[VisualNPC] Ready: %s (%s)" % [simulation_state.npc_name, npc_id])


func _exit_tree() -> void:
	_disconnect_signals()
	if simulation_state and simulation_state.npc_instance == self:
		simulation_state.npc_instance = null
	print("[VisualNPC] Removed: %s" % npc_id)


# =============================================================================
# SETUP
# =============================================================================

func _setup_sprite() -> void:
	if not animated_sprite_2d:
		return
	
	var npc_type: String = simulation_state.npc_type
	if SPRITE_LIBRARY.has(npc_type):
		animated_sprite_2d.sprite_frames = SPRITE_LIBRARY[npc_type]
	
	_play_animation("idle")


func _setup_name_label() -> void:
	if name_label:
		name_label.text = simulation_state.npc_name


func _sync_to_simulation() -> void:
	if not simulation_state:
		return
	
	global_position = simulation_state.current_position
	_update_animation_for_state(simulation_state.state.type)
	
	if simulation_state.state.type == NPCState.Type.PERFORMING_ACTIONS and simulation_state.current_action:
		_play_action_animation(simulation_state.current_action)


func _connect_signals() -> void:
	NPCSimulationManager.npc_started_traveling.connect(_on_started_traveling)
	NPCSimulationManager.npc_arrived_at_zone.connect(_on_arrived_at_zone)
	NPCSimulationManager.npc_waypoint_reached.connect(_on_waypoint_reached)
	NPCSimulationManager.npc_action_started.connect(_on_action_started)
	NPCSimulationManager.npc_action_completed.connect(_on_action_completed)
	NPCSimulationManager.npc_action_progress.connect(_on_action_progress)
	
	if simulation_state and simulation_state.state:
		simulation_state.state.state_changed.connect(_on_state_changed)


func _disconnect_signals() -> void:
	if NPCSimulationManager.npc_started_traveling.is_connected(_on_started_traveling):
		NPCSimulationManager.npc_started_traveling.disconnect(_on_started_traveling)
	if NPCSimulationManager.npc_arrived_at_zone.is_connected(_on_arrived_at_zone):
		NPCSimulationManager.npc_arrived_at_zone.disconnect(_on_arrived_at_zone)
	if NPCSimulationManager.npc_waypoint_reached.is_connected(_on_waypoint_reached):
		NPCSimulationManager.npc_waypoint_reached.disconnect(_on_waypoint_reached)
	if NPCSimulationManager.npc_action_started.is_connected(_on_action_started):
		NPCSimulationManager.npc_action_started.disconnect(_on_action_started)
	if NPCSimulationManager.npc_action_completed.is_connected(_on_action_completed):
		NPCSimulationManager.npc_action_completed.disconnect(_on_action_completed)
	if NPCSimulationManager.npc_action_progress.is_connected(_on_action_progress):
		NPCSimulationManager.npc_action_progress.disconnect(_on_action_progress)
	
	if simulation_state and simulation_state.state and simulation_state.state.state_changed.is_connected(_on_state_changed):
		simulation_state.state.state_changed.disconnect(_on_state_changed)


# =============================================================================
# PHYSICS - SIMPLE POSITION SYNC
# =============================================================================

func _physics_process(delta: float) -> void:
	if not is_synced or not simulation_state:
		return
	
	# Sync position from simulation
	var target_pos: Vector2 = simulation_state.current_position
	var dist: float = global_position.distance_to(target_pos)
	
	if dist > 0.5:
		# Smooth follow
		global_position = global_position.lerp(target_pos, delta * POSITION_SYNC_SPEED)
		
		# Update velocity for animation direction
		velocity = (target_pos - global_position).normalized() * simulation_state.speed
	else:
		global_position = target_pos
		velocity = Vector2.ZERO
	
	_update_sprite_direction()
	_update_modulate_reset(delta)


func _update_sprite_direction() -> void:
	if animated_sprite_2d and velocity.x != 0.0:
		animated_sprite_2d.flip_h = velocity.x < 0.0


func _update_modulate_reset(delta: float) -> void:
	# Reset modulate when not in special action
	if animated_sprite_2d and simulation_state.state.type != NPCState.Type.PERFORMING_ACTIONS:
		if animated_sprite_2d.modulate.a != 1.0:
			animated_sprite_2d.modulate.a = lerp(animated_sprite_2d.modulate.a, 1.0, delta * ANIMATION_FADE_SPEED)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_state_changed(old_state: int, new_state: int) -> void:
	_update_animation_for_state(new_state)
	
	if new_state == NPCState.Type.IDLE:
		velocity = Vector2.ZERO
		current_action_animation = ""
		_play_animation("idle")


func _on_started_traveling(id: String, _from: Vector2, _to: Vector2, _dest: String) -> void:
	if id != npc_id:
		return
	_play_animation("walk")


func _on_arrived_at_zone(id: String, _zone: String, _pos: Vector2) -> void:
	if id != npc_id:
		return
	velocity = Vector2.ZERO
	_play_animation("idle")


func _on_waypoint_reached(id: String, waypoint_type: String, _pos: Vector2) -> void:
	if id != npc_id:
		return
	
	if waypoint_type in ["stairs_up", "stairs_down"]:
		_play_animation("climb")


func _on_action_started(id: String, action: NPCAction) -> void:
	if id != npc_id:
		return
	_play_action_animation(action)
	_play_action_start_effect(action)


func _on_action_completed(id: String, action: NPCAction, success: bool) -> void:
	if id != npc_id:
		return
	
	_play_action_completion_effect(action, success)
	current_action_animation = ""
	
	if simulation_state.state.type != NPCState.Type.PERFORMING_ACTIONS:
		_play_animation("idle")


func _on_action_progress(id: String, action: NPCAction, progress: float) -> void:
	if id != npc_id:
		return
	_update_action_visual_progress(action, progress)


# =============================================================================
# ANIMATIONS
# =============================================================================

func _update_animation_for_state(state_type: int) -> void:
	var anim: String = STATE_ANIMATIONS.get(state_type, "idle")
	_play_animation(anim)


func _play_animation(anim_name: String) -> void:
	if not animated_sprite_2d:
		return
	
	# Don't interrupt action animations
	if current_action_animation != "" and anim_name != current_action_animation:
		return
	
	if not animated_sprite_2d.sprite_frames.has_animation(anim_name):
		anim_name = "idle" if animated_sprite_2d.sprite_frames.has_animation("idle") else ""
	
	if anim_name != "" and current_animation != anim_name:
		current_animation = anim_name
		animated_sprite_2d.play(anim_name)


func _play_action_animation(action: NPCAction) -> void:
	if not animated_sprite_2d:
		return
	
	var action_anim: String = ""
	
	if ACTION_ANIMATIONS.has(action.action_id):
		action_anim = ACTION_ANIMATIONS[action.action_id]
	else:
		action_anim = "action_" + action.action_id
	
	if animated_sprite_2d.sprite_frames.has_animation(action_anim):
		current_action_animation = action_anim
		animated_sprite_2d.play(action_anim)
	elif animated_sprite_2d.sprite_frames.has_animation("action"):
		current_action_animation = "action"
		animated_sprite_2d.play("action")
	else:
		current_action_animation = ""


# =============================================================================
# VISUAL EFFECTS
# =============================================================================

func _play_action_start_effect(_action: NPCAction) -> void:
	pass  # TODO: particles, sounds


func _play_action_completion_effect(_action: NPCAction, success: bool) -> void:
	_flash_sprite(Color.GREEN if success else Color.RED, 0.2)


func _update_action_visual_progress(action: NPCAction, progress: float) -> void:
	if not animated_sprite_2d:
		return
	
	match action.action_id:
		"sleep":
			animated_sprite_2d.modulate.a = 1.0 - (progress * 0.3)
		"haunt":
			animated_sprite_2d.modulate.a = 0.8 + (sin(progress * 20.0) * 0.2)


func _flash_sprite(color: Color, duration: float) -> void:
	if not animated_sprite_2d:
		return
	
	var original: Color = animated_sprite_2d.modulate
	animated_sprite_2d.modulate = color
	
	await get_tree().create_timer(duration).timeout
	
	if animated_sprite_2d:
		animated_sprite_2d.modulate = original


# =============================================================================
# UTILITY
# =============================================================================

func get_simulation_state() -> Variant:
	return simulation_state


func is_in_state(state_type: int) -> bool:
	return simulation_state != null and simulation_state.state.type == state_type


func debug_info() -> String:
	if not simulation_state:
		return "No simulation state"
	
	return "%s | %s | Floor %d | Anim: %s" % [
		simulation_state.npc_name,
		simulation_state.state.get_name(),
		simulation_state.current_floor,
		current_animation
	]
