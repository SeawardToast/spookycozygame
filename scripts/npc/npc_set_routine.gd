extends CharacterBody2D
class_name NPC

@onready var agent := $NavigationAgent2D

var schedule := []
var current_goal = null
var doing_action = false

func _ready():
	DayAndNightCycleManager.time_changed.connect(_on_time_changed)
	schedule.sort_custom(func(a, b): return a.time < b.time)

func _on_time_changed(m):
	var entry = get_current_entry(m)
	if entry and entry != current_goal:
		current_goal = entry
		go_to(entry.target)

func get_current_entry(minute):
	var last
	for e in schedule:
		if e.time <= minute:
			last = e
		else:
			break
	return last

func go_to(target_name):
	var t = get_tree().current_scene.get_node(target_name)
	if not t:
		push_error("Target not found: " + target_name)
		return

	agent.target_position = t.global_position
	doing_action = false

func _physics_process(delta):
	if agent.is_navigation_finished():
		if not doing_action:
			perform_action(current_goal)
			doing_action = true
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var next = agent.get_next_path_position()
	var dir = (next - global_position).normalized()
	velocity = dir * get_speed()
	move_and_slide()

func get_speed() -> float:
	return 60.0  # override in child if needed

func perform_action(entry):
	# BASE IMPLEMENTATION — child classes override
	idle()

func idle():
	pass  # base idle (do nothing)
