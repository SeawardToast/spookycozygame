class_name ScheduledNPC
extends CharacterBody2D

@export var npc_name: String = "NPC"
@export var speed: float = 100.0
@export var animated_sprite_2d: AnimatedSprite2D
@export var navigation_agent_2d: NavigationAgent2D
var debug_target_point: Vector2 = Vector2.ZERO

var daily_schedule: Array = []

var current_target_zone: Area2D = null
var current_actions: Array = []
var is_traveling: bool = false
var at_door: bool = false

var completed_schedule_entries: Array = [] # store references to entries we've executed
var active_schedule_entry: Dictionary = {} # the entry currently being processed


signal arrived_at_zone(zone: Node)
signal action_attempted(action_name: String)
signal action_failed(action_name: String, reason: String)

# -------------------------------
# Ready
# -------------------------------
func _ready():
	DayAndNightCycleManager.time_tick.connect(_on_time_tick)
	randomize()
	navigation_agent_2d.target_desired_distance = 4.0
	navigation_agent_2d.velocity_computed.connect(_on_navigation_agent_2d_velocity_computed)

# -------------------------------
# Time tick
# -------------------------------
func _on_time_tick(day: int, hour: int, minute: int) -> void:
	var total_minute = hour * 60 + minute
	_check_schedule(total_minute)
	
# -------------------------------
# Time tick
# -------------------------------
func _check_schedule(current_minute: int) -> void:
	for entry in daily_schedule:
		# Skip if already completed
		if entry in completed_schedule_entries:
			continue

		var start_minute = entry.get("start_minute", 0)
		var end_minute = entry.get("end_minute", 0)
		
		if current_minute >= start_minute and current_minute < end_minute:
			# This is the current time slot
			
			# If this entry is already active, don't retrigger it
			if active_schedule_entry == entry:
				return
			
			# Start processing this entry
			active_schedule_entry = entry
			var zone_name = entry.get("zone", "")
			var actions = entry.get("actions", [])
			
			if zone_name != "":
				_start_travel_to_zone(zone_name, actions, entry)
			elif actions:
				_attempt_actions(actions)
				completed_schedule_entries.append(entry)
				active_schedule_entry = {}
			return
		
		# If we've moved past the time window, mark as completed
		if current_minute >= end_minute and active_schedule_entry == entry:
			completed_schedule_entries.append(entry)
			active_schedule_entry = {}

# -------------------------------
# Start travel
# -------------------------------
func _start_travel_to_zone(zone_name: String, actions: Array, entry: Dictionary):
	var zone = null
	for area in ZoneManager.get_zones():
		if area.name == zone_name:
			zone = area
			break

	if zone == null:
		push_warning("Zone not found: %s" % zone_name)
		active_schedule_entry = {}
		return
		
	current_target_zone = ZoneManager.create_area_from_zone_data(zone)
	current_actions = actions
	is_traveling = true

	var door_or_random_point = _get_random_point_in_area(current_target_zone)
	navigation_agent_2d.target_position = door_or_random_point
	debug_target_point = door_or_random_point
	
	# Wait a frame for navigation to calculate
	await get_tree().process_frame
	
	if !navigation_agent_2d.is_target_reachable():
		push_warning("Target unreachable! Trying alternative point...")
		# Try a few more random points
		for i in 3:
			door_or_random_point = _get_random_point_in_area(current_target_zone)
			navigation_agent_2d.target_position = door_or_random_point
			await get_tree().process_frame
			if navigation_agent_2d.is_target_reachable():
				break
	
	print("=== PATHFINDING DEBUG ===")
	print("NPC Position: ", global_position)
	print("Target Zone: ", zone_name)
	print("Target Point: ", door_or_random_point)
	print("Target Reachable: ", navigation_agent_2d.is_target_reachable())
	print("========================")

func _draw() -> void:
	if debug_target_point != Vector2.ZERO:
		draw_circle(to_local(debug_target_point), 6.0, Color.RED)
		
# -------------------------------
# Arrive at zone
# -------------------------------
func _zone_arrival() -> void:
	print("arrived at zone")
	emit_signal("arrived_at_zone", current_target_zone)
	_attempt_actions(current_actions)

	# Mark as completed when actions are done
	if !active_schedule_entry.is_empty():
		completed_schedule_entries.append(active_schedule_entry)
		active_schedule_entry = {}

	current_target_zone = null
	current_actions = []
# -------------------------------
# Physics movement
# -------------------------------
func _physics_process(delta: float) -> void:
	queue_redraw()
	if not is_traveling:
		return

	if navigation_agent_2d.is_navigation_finished():
		is_traveling = false
		_zone_arrival()
		return
	

	var next_pos = navigation_agent_2d.get_next_path_position()
	var target_direction: Vector2 = global_position.direction_to(next_pos)
	var velocity: Vector2 = target_direction * speed
	
	if navigation_agent_2d.avoidance_enabled:
		animated_sprite_2d.flip_h = velocity.x < 0
		navigation_agent_2d.velocity = velocity
	else:
		velocity = target_direction * speed
		move_and_slide()
		
func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()
	if animated_sprite_2d:
		animated_sprite_2d.flip_h = velocity.x < 0

# -------------------------------
# Get random point inside Area2D
# -------------------------------
func _get_random_point_in_area(area: Area2D) -> Vector2:
	# Use CollisionPolygon2D child
	var poly_node := area.get_node_or_null("CollisionPolygon2D")
	if poly_node == null:
		return area.global_position

	var polygon: PackedVector2Array = poly_node.polygon
	if polygon.size() == 0:
		return area.global_position

	# Convert local polygon points to global coordinates
	var points: Array[Vector2] = []
	var xf: Transform2D = poly_node.global_transform
	for p in polygon:
		points.append(xf * p)  # Godot 4 uses '*' to transform Vector2 by Transform2D

	# Compute bounding box
	var min_x = points[0].x
	var max_x = points[0].x
	var min_y = points[0].y
	var max_y = points[0].y
	for pt in points:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)

	# Random point sampling
	for i in range(40):
		var random_point = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if Geometry2D.is_point_in_polygon(random_point, points):
			return random_point

	return points[0]  # fallback


# -------------------------------
# Attempt actions
# -------------------------------
func _attempt_actions(actions: Array = []):
	for action in actions:
		if typeof(action) == TYPE_CALLABLE:
			var result = action.call()
			var success = true
			var reason = ""
			if typeof(result) == TYPE_ARRAY and result.size() == 2:
				success = result[0]
				reason = result[1]
			elif typeof(result) == TYPE_BOOL:
				success = result
			if success:
				emit_signal("action_attempted", str(action))
			else:
				emit_signal("action_failed", str(action), reason)
