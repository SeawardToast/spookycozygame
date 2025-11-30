extends Area2D

@export var direction: String = "up" # "up" or "down"
@export var floor_change_delay: float = 0.2 # Optional delay to avoid multiple triggers

var _can_use: bool = true

func _on_body_entered(body: Node2D) -> void:
	if not _can_use:
		return
	
	# Make sure the body is the player
	if not body.is_in_group("player"):
		return
	
	var current_floor = FloorManager.get_current_floor()
	var new_floor = current_floor
	
	if direction == "up":
		new_floor = current_floor + 1
	elif direction == "down":
		new_floor = current_floor - 1
	else:
		push_warning("Stairs: Invalid direction: %s" % direction)
		return
	
	# Check if the target floor exists
	if new_floor not in FloorManager.get_all_floors():
		push_warning("Stairs: Target floor %d does not exist" % new_floor)
		return
	
	# Trigger the floor change
	_can_use = false
	_change_floor(new_floor)

func _change_floor(new_floor: int) -> void:
	# Optional: emit a signal if something else needs to know
	emit_signal("floor_transition_requested", new_floor)
	
	# Tell FloorManager to set the new active floor
	FloorManager.set_active_floor(new_floor)
	
	# Update the player's floor if they have a method for it
	if has_node("/root/MainHotelScene"): 
		var main_scene = get_node("/root/MainHotelScene")
		if main_scene.has_method("current_player_floor"):
			main_scene.current_player_floor = new_floor
	
	# Cooldown before stairs can be used again
	await get_tree().create_timer(floor_change_delay)
	_can_use = true
