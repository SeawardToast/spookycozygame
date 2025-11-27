# WerewolfNPCDefinition.gd
extends RefCounted
class_name Werewolf

var npc_id: String = ""
var npc_name: String = "Wolfgang"
var start_position: Vector2 = Vector2(200, 100)
var speed: float = 150.0

var sprite_texture: String = "res://sprites/werewolf.png"
var sprite_animation: String = "werewolf_idle"

var is_full_moon: bool = false
var wildness: int = 50
var pack_loyalty: int = 80

func _init():
	var werewolf_names = ["Wolfgang", "Luna", "Fang", "Howler", "Moonpaw", "Silverfur"]
	npc_name = werewolf_names[randi() % werewolf_names.size()]
	
	speed = randf_range(130.0, 170.0) # Werewolves are fast!
	wildness = randi_range(30, 70)
	
	# Check if it's full moon (simplified)
	is_full_moon = randi() % 30 == 0

func get_schedule() -> Array:
	# Schedule changes based on moon phase
	if is_full_moon:
		return [
			{"start_minute": 1200, "end_minute": 1440, "zone": "Courtyard", "actions": [Callable(self, "howl_at_moon")]},
			{"start_minute": 0, "end_minute": 300, "zone": "Forest", "actions": [Callable(self, "hunt")]}
		]
	else:
		return [
			{"start_minute": 420, "end_minute": 600, "zone": "Kitchen", "actions": [Callable(self, "eat_meat")]},
			{"start_minute": 720, "end_minute": 900, "zone": "Gym", "actions": [Callable(self, "exercise")]},
			{"start_minute": 1320, "end_minute": 1440, "zone": "Sleep", "actions": [Callable(self, "sleep")]}
		]

func eat_meat():
	print("%s is devouring meat..." % npc_name)
	wildness = max(0, wildness - 10)
	return [true, ""]

func exercise():
	print("%s is working out at the gym..." % npc_name)
	wildness = max(0, wildness - 5)
	return [true, ""]

func sleep():
	if wildness > 80:
		return [false, "too wild to sleep"]
	print("%s is sleeping peacefully..." % npc_name)
	return [true, ""]

func howl_at_moon():
	print("%s is HOWLING at the full moon! AROOOOO!" % npc_name)
	wildness = min(100, wildness + 20)
	return [true, ""]

func hunt():
	print("%s is hunting in the forest..." % npc_name)
	wildness = max(0, wildness - 30)
	return [true, ""]
