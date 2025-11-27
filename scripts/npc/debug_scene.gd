# DebugScene.gd
# A standalone debug scene for testing NPCs
# Attach this to the root node of your debug scene
extends Node2D

# Configure these in the inspector or here
@export var debug_npc_type: String = "ghost" # "ghost", "vampire", "werewolf"
@export var spawn_visual: bool = true
@export var spawn_position: Vector2 = Vector2(400, 300)
@export var enable_auto_spawn: bool = false
@export var show_debug_info: bool = true

var debug_npc_id: String = ""
var visual_npc: Node = null
var debug_label: Label

func _ready():
	# Setup debug UI
	if show_debug_info:
		_setup_debug_ui()
	
	# Spawn the debug NPC
	spawn_debug_npc()
	
	# Connect to simulation signals for debugging
	NPCSimulationManager.npc_spawned.connect(_on_npc_spawned)
	NPCSimulationManager.npc_started_traveling.connect(_on_npc_traveling)
	NPCSimulationManager.npc_arrived_at_zone.connect(_on_npc_arrived)
	NPCSimulationManager.npc_action_attempted.connect(_on_npc_action)
	NPCSimulationManager.npc_action_failed.connect(_on_npc_action_failed)

func spawn_debug_npc():
	# Spawn NPC in simulation
	debug_npc_id = NPCSimulationManager.spawn_npc(debug_npc_type, spawn_position)
	
	if debug_npc_id == "":
		push_error("Failed to spawn debug NPC of type: %s" % debug_npc_type)
		return
	
	print("=== DEBUG NPC SPAWNED ===")
	print("ID: %s" % debug_npc_id)
	print("Type: %s" % debug_npc_type)
	print("Position: %s" % spawn_position)
	
	# Spawn visual representation if enabled
	if spawn_visual:
		call_deferred("_spawn_visual_npc")

func _spawn_visual_npc():
	# Load and instantiate visual NPC
	var visual_scene = load("res://scenes/characters/base_npc/visual_npc.tscn")
	if visual_scene == null:
		push_warning("VisualNPC.tscn not found - creating basic debug visual")
		_create_debug_visual()
		return
	
	visual_npc = visual_scene.instantiate()
	visual_npc.npc_id = debug_npc_id
	visual_npc.npc_type = debug_npc_type
	#visual_npc.name = debug_npc_name
	visual_npc.global_position = spawn_position
	add_child(visual_npc)
	
	print("Visual NPC spawned and linked to simulation")

func _create_debug_visual():
	# Create a simple visual representation for debugging
	visual_npc = CharacterBody2D.new()
	visual_npc.name = "DebugVisualNPC"
	visual_npc.global_position = spawn_position
	
	# Add a colored circle sprite
	var sprite = Sprite2D.new()
	var color_dict = {
		"ghost": Color.CYAN,
		"vampire": Color.RED,
		"werewolf": Color.BROWN
	}
	
	# Create a simple circle texture
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in range(64):
		for y in range(64):
			var dx = x - 32
			var dy = y - 32
			if dx*dx + dy*dy < 30*30:
				img.set_pixel(x, y, color_dict.get(debug_npc_type, Color.WHITE))
	
	sprite.texture = ImageTexture.create_from_image(img)
	visual_npc.add_child(sprite)
	
	# Add label with NPC name
	var label = Label.new()
	var state = NPCSimulationManager.get_npc_state(debug_npc_id)
	if state:
		label.text = state.npc_name
	label.position = Vector2(-50, -40)
	visual_npc.add_child(label)
	
	add_child(visual_npc)
	
	# Manually sync position with simulation
	var timer = Timer.new()
	timer.wait_time = 0.016 # ~60 FPS
	timer.timeout.connect(_sync_debug_visual)
	add_child(timer)
	timer.start()

func _sync_debug_visual():
	if visual_npc == null or debug_npc_id == "":
		return
	
	var state = NPCSimulationManager.get_npc_state(debug_npc_id)
	if state:
		visual_npc.global_position = visual_npc.global_position.lerp(state.current_position, 0.3)

func _setup_debug_ui():
	# Create debug info panel
	var panel = PanelContainer.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(300, 200)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	debug_label = Label.new()
	debug_label.text = "Debug Info Loading..."
	vbox.add_child(debug_label)
	
	# Add control buttons
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var btn_respawn = Button.new()
	btn_respawn.text = "Respawn"
	btn_respawn.pressed.connect(respawn_npc)
	button_container.add_child(btn_respawn)
	
	var btn_despawn = Button.new()
	btn_despawn.text = "Despawn"
	btn_despawn.pressed.connect(despawn_npc)
	button_container.add_child(btn_despawn)
	
	var btn_toggle = Button.new()
	btn_toggle.text = "Toggle Type"
	btn_toggle.pressed.connect(toggle_npc_type)
	button_container.add_child(btn_toggle)
	
	add_child(panel)

func _process(delta):
	if show_debug_info and debug_label:
		_update_debug_info()
	
	# Sync visual position if using basic debug visual
	if visual_npc and not visual_npc.has_method("_physics_process"):
		_sync_debug_visual()

func _update_debug_info():
	if debug_npc_id == "":
		debug_label.text = "No NPC spawned"
		return
	
	var state = NPCSimulationManager.get_npc_state(debug_npc_id)
	if state == null:
		debug_label.text = "NPC state not found"
		return
	
	var info = "=== NPC Debug Info ===\n"
	info += "ID: %s\n" % state.npc_id
	info += "Name: %s\n" % state.npc_name
	info += "Type: %s\n" % state.npc_type
	info += "Position: (%.0f, %.0f)\n" % [state.current_position.x, state.current_position.y]
	info += "Traveling: %s\n" % state.is_traveling
	info += "Target Zone: %s\n" % state.current_target_zone_name
	info += "Speed: %.0f\n" % state.speed
	info += "Visual: %s\n" % ("Active" if visual_npc else "None")
	
	# Get current time
	var time_data = DayAndNightCycleManager.get_current_time() if DayAndNightCycleManager else null
	if time_data:
		info += "Time: %02d:%02d\n" % [time_data["hour"], time_data["minute"]]
	
	debug_label.text = info

# Debug controls
func respawn_npc():
	if debug_npc_id != "":
		despawn_npc()
	spawn_debug_npc()

func despawn_npc():
	if debug_npc_id != "":
		NPCSimulationManager.despawn_npc(debug_npc_id)
		if visual_npc:
			visual_npc.queue_free()
			visual_npc = null
		debug_npc_id = ""

func toggle_npc_type():
	var types = ["ghost", "vampire", "werewolf"]
	var current_index = types.find(debug_npc_type)
	debug_npc_type = types[(current_index + 1) % types.size()]
	respawn_npc()

# Signal handlers for debug output
func _on_npc_spawned(npc_id: String, npc_type: String, position: Vector2):
	if npc_id == debug_npc_id:
		print("[DEBUG] NPC Spawned: %s at %s" % [npc_type, position])

func _on_npc_traveling(npc_id: String, from_pos: Vector2, to_pos: Vector2, zone_name: String):
	if npc_id == debug_npc_id:
		print("[DEBUG] NPC Traveling: %s -> %s (Zone: %s)" % [from_pos, to_pos, zone_name])

func _on_npc_arrived(npc_id: String, zone_name: String, position: Vector2):
	if npc_id == debug_npc_id:
		print("[DEBUG] NPC Arrived: %s at %s" % [zone_name, position])

func _on_npc_action(npc_id: String, action_name: String):
	if npc_id == debug_npc_id:
		print("[DEBUG] NPC Action: %s" % action_name)

func _on_npc_action_failed(npc_id: String, action_name: String, reason: String):
	if npc_id == debug_npc_id:
		print("[DEBUG] NPC Action Failed: %s - Reason: %s" % [action_name, reason])

# Keyboard shortcuts for debugging
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				respawn_npc()
			KEY_D:
				despawn_npc()
			KEY_T:
				toggle_npc_type()
			KEY_SPACE:
				# Force NPC to travel to a random zone
				force_travel_to_random_zone()

func force_travel_to_random_zone():
	if debug_npc_id == "":
		return
	
	var zones = ZoneManager.get_zones() if ZoneManager else []
	if zones.is_empty():
		print("[DEBUG] No zones available")
		return
	
	var random_zone = zones[randi() % zones.size()]
	print("[DEBUG] Forcing travel to zone: %s" % random_zone.name)
	
	var state = NPCSimulationManager.get_npc_state(debug_npc_id)
	if state:
		# Manually trigger travel (hack for debugging)
		var definition = state.behavior_data.get("definition")
		if definition:
			var actions = [Callable(definition, "sleep")] # Use any action
			NPCSimulationManager._start_travel_to_zone(state, random_zone.name, actions, {})
