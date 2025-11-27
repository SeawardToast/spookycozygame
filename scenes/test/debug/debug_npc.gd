# SimpleDebugScene.gd
# All-in-one debug scene that creates everything you need
# Just attach this to a Node2D and run!

extends Node2D

@export var debug_npc_type: String = "ghost"
@export var show_zones: bool = true

var debug_npc_id: String = ""
var visual_npc: CharacterBody2D
var debug_ui: Control

# Test zones data
var test_zones = [
	{"name": "Kitchen", "pos": Vector2(300, 200), "size": Vector2(200, 150), "color": Color.ORANGE},
	{"name": "Sleep", "pos": Vector2(700, 200), "size": Vector2(200, 150), "color": Color.PURPLE},
	{"name": "Haunt", "pos": Vector2(500, 450), "size": Vector2(250, 150), "color": Color.CYAN},
	{"name": "Entrance", "pos": Vector2(100, 400), "size": Vector2(150, 100), "color": Color.GREEN}
]

func _ready():
	print("=== SIMPLE DEBUG SCENE ===")
	_setup_scene()
	_create_test_zones()
	_setup_navigation()
	_setup_debug_ui()
	
	# Wait a frame for everything to initialize
	await get_tree().process_frame
	
	_spawn_debug_npc()
	
	# Connect signals
	NPCSimulationManager.npc_spawned.connect(_on_debug_event.bind("SPAWNED"))
	NPCSimulationManager.npc_started_traveling.connect(_on_travel_event)
	NPCSimulationManager.npc_arrived_at_zone.connect(_on_arrival_event)
	NPCSimulationManager.npc_action_attempted.connect(_on_action_event)

func _setup_scene():
	# Camera
	var camera = Camera2D.new()
	camera.enabled = true
	camera.position = Vector2(500, 350)
	camera.zoom = Vector2(.65, .65)
	add_child(camera)
	
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.2)
	bg.size = Vector2(2000, 1500)
	bg.position = Vector2(-500, -300)
	bg.z_index = -100
	add_child(bg)
	
	# Grid for reference
	queue_redraw()

func _draw():
	if show_zones:
		# Draw grid
		for x in range(0, 1000, 100):
			draw_line(Vector2(x, 0), Vector2(x, 700), Color(0.3, 0.3, 0.3), 1.0)
		for y in range(0, 700, 100):
			draw_line(Vector2(0, y), Vector2(1000, y), Color(0.3, 0.3, 0.3), 1.0)

func _create_test_zones():
	var zones_container = Node2D.new()
	zones_container.name = "TestZones"
	add_child(zones_container)
	
	for zone_data in test_zones:
		var zone = Area2D.new()
		zone.name = zone_data.name
		
		# Collision shape
		var collision = CollisionPolygon2D.new()
		var half = zone_data.size / 2
		collision.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y)
		])
		zone.add_child(collision)
		
		# Visual polygon
		if show_zones:
			var poly = Polygon2D.new()
			poly.polygon = collision.polygon
			poly.color = zone_data.color
			poly.color.a = 0.3
			zone.add_child(poly)
			
			# Border
			var line = Line2D.new()
			line.points = PackedVector2Array([
				Vector2(-half.x, -half.y),
				Vector2(half.x, -half.y),
				Vector2(half.x, half.y),
				Vector2(-half.x, half.y),
				Vector2(-half.x, -half.y)
			])
			line.width = 2.0
			line.default_color = zone_data.color
			zone.add_child(line)
			
			# Label
			var label = Label.new()
			label.text = zone_data.name
			label.position = Vector2(-40, -60)
			label.add_theme_font_size_override("font_size", 16)
			zone.add_child(label)
		
		zone.position = zone_data.pos
		zones_container.add_child(zone)
	
	print("Created %d test zones" % test_zones.size())

func _setup_navigation():
	var nav_region = NavigationRegion2D.new()
	var nav_poly = NavigationPolygon.new()
	
	# Large navigation area
	var outline = PackedVector2Array([
		Vector2(0, 0),
		Vector2(1000, 0),
		Vector2(1000, 700),
		Vector2(0, 700)
	])
	nav_poly.add_outline(outline)
	nav_poly.make_polygons_from_outlines()
	nav_region.navigation_polygon = nav_poly
	
	add_child(nav_region)
	print("Navigation setup complete")

func _setup_debug_ui():
	debug_ui = Control.new()
	
	# Panel container
	var panel = PanelContainer.new()
	panel.position = Vector2(10, 10)
	panel.custom_minimum_size = Vector2(350, 250)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "=== NPC DEBUG CONSOLE ==="
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	
	# Info label
	var info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.text = "Initializing..."
	vbox.add_child(info_label)
	
	# Separator
	vbox.add_child(HSeparator.new())
	
	# Control buttons
	var button_grid = GridContainer.new()
	button_grid.columns = 3
	button_grid.add_theme_constant_override("h_separation", 5)
	button_grid.add_theme_constant_override("v_separation", 5)
	
	_add_button(button_grid, "Respawn", _respawn_npc)
	_add_button(button_grid, "Despawn", _despawn_npc)
	_add_button(button_grid, "Ghost", func(): _change_type("ghost"))
	_add_button(button_grid, "Vampire", func(): _change_type("vampire"))
	_add_button(button_grid, "Werewolf", func(): _change_type("werewolf"))
	_add_button(button_grid, "Toggle Zones", _toggle_zones)
	
	vbox.add_child(button_grid)
	
	# Event log
	var log_label = Label.new()
	log_label.name = "LogLabel"
	log_label.text = "Event Log:\n"
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(log_label)
	
	debug_ui.add_child(panel)
	add_child(debug_ui)
	
	# Instructions
	var instructions = Label.new()
	instructions.position = Vector2(10, 280)
	instructions.text = "Shortcuts: R=Respawn | D=Despawn | T=Toggle Type | Space=Force Travel"
	debug_ui.add_child(instructions)

func _add_button(container: GridContainer, text: String, callback: Callable):
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 30)
	btn.pressed.connect(callback)
	container.add_child(btn)

func _spawn_debug_npc():
	var spawn_pos = Vector2(500, 350)
	debug_npc_id = NPCSimulationManager.spawn_npc(debug_npc_type, spawn_pos)
	
	if debug_npc_id == "":
		push_error("Failed to spawn NPC!")
		return
	
	print("Spawned debug NPC: %s" % debug_npc_id)
	_create_visual_npc(spawn_pos)

func _create_visual_npc(pos: Vector2):
	visual_npc = CharacterBody2D.new()
	visual_npc.name = "DebugNPC"
	visual_npc.position = pos
	
	# Circle sprite
	var sprite = Sprite2D.new()
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	
	var color_map = {
		"ghost": Color.CYAN,
		"vampire": Color.DARK_RED,
		"werewolf": Color.SADDLE_BROWN
	}
	var npc_color = color_map.get(debug_npc_type, Color.WHITE)
	
	# Draw circle
	for x in range(64):
		for y in range(64):
			var dx = x - 32
			var dy = y - 32
			if dx*dx + dy*dy < 28*28:
				img.set_pixel(x, y, npc_color)
	
	sprite.texture = ImageTexture.create_from_image(img)
	visual_npc.add_child(sprite)
	
	# Name label
	var state = NPCSimulationManager.get_npc_state(debug_npc_id)
	if state:
		var label = Label.new()
		label.text = state.npc_name
		label.position = Vector2(-60, -45)
		label.add_theme_font_size_override("font_size", 12)
		visual_npc.add_child(label)
	
	add_child(visual_npc)

func _process(delta):
	_update_visual_position()
	_update_debug_info()

func _update_visual_position():
	if not visual_npc or debug_npc_id == "":
		return
	
	var state = NPCSimulationManager.get_npc_state(debug_npc_id)
	if state:
		visual_npc.position = visual_npc.position.lerp(state.current_position, 0.2)

func _update_debug_info():
	var info_label = debug_ui.get_node_or_null("PanelContainer/VBoxContainer/InfoLabel")
	if not info_label or debug_npc_id == "":
		return
	
	var state = NPCSimulationManager.get_npc_state(debug_npc_id)
	if not state:
		return
	
	var info = "ID: %s\n" % state.npc_id
	info += "Name: %s\n" % state.npc_name
	info += "Type: %s\n" % state.npc_type
	info += "Pos: (%.0f, %.0f)\n" % [state.current_position.x, state.current_position.y]
	info += "Traveling: %s\n" % state.is_traveling
	info += "Zone: %s\n" % (state.current_target_zone_name if state.current_target_zone_name else "None")
	
	info_label.text = info

func _log_event(message: String):
	var log_label = debug_ui.get_node_or_null("PanelContainer/VBoxContainer/LogLabel")
	if log_label:
		var lines = log_label.text.split("\n")
		lines.append(message)
		if lines.size() > 6:
			lines.remove_at(1) # Keep header
		log_label.text = "\n".join(lines)
	print(message)

# Button callbacks
func _respawn_npc():
	_despawn_npc()
	await get_tree().process_frame
	_spawn_debug_npc()

func _despawn_npc():
	if debug_npc_id != "":
		NPCSimulationManager.despawn_npc(debug_npc_id)
		if visual_npc:
			visual_npc.queue_free()
			visual_npc = null
		debug_npc_id = ""

func _change_type(new_type: String):
	debug_npc_type = new_type
	_respawn_npc()

func _toggle_zones():
	show_zones = !show_zones
	get_tree().reload_current_scene()

# Event callbacks
func _on_debug_event(npc_id: String, npc_type: String, position: Vector2, event: String):
	if npc_id == debug_npc_id:
		_log_event("[%s] %s at %s" % [event, npc_type, position])

func _on_travel_event(npc_id: String, from_pos: Vector2, to_pos: Vector2, zone_name: String):
	if npc_id == debug_npc_id:
		_log_event("TRAVEL -> %s" % zone_name)

func _on_arrival_event(npc_id: String, zone_name: String, position: Vector2):
	if npc_id == debug_npc_id:
		_log_event("ARRIVED at %s" % zone_name)

func _on_action_event(npc_id: String, action_name: String):
	if npc_id == debug_npc_id:
		_log_event("ACTION: %s" % action_name)

# Keyboard shortcuts
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R: _respawn_npc()
			KEY_D: _despawn_npc()
			KEY_T: 
				var types = ["ghost", "vampire", "werewolf"]
				var idx = types.find(debug_npc_type)
				_change_type(types[(idx + 1) % types.size()])
			KEY_SPACE:
				if test_zones.size() > 0:
					var zone = test_zones[randi() % test_zones.size()]
					_log_event("Forcing travel to %s" % zone.name)
