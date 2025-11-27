# VampireNPCDefinition.gd
extends RefCounted
class_name Vampire

var npc_id: String = ""
var npc_name: String = "Count Dracula"
var start_position: Vector2 = Vector2(150, 150)
var speed: float = 120.0

var sprite_texture: String = "res://sprites/vampire.png"
var sprite_animation: String = "vampire_idle"

var blood_level: int = 50
var coffin_rested: bool = false

func _init():
	var vampire_names = ["Count", "Baron", "Countess", "Lord", "Lady"]
	var vampire_surnames = ["Dracula", "Bloodsworth", "Nightshade", "Darkmore", "Crimson"]
	npc_name = vampire_names[randi() % vampire_names.size()] + " " + vampire_surnames[randi() % vampire_surnames.size()]
	
	speed = randf_range(100.0, 140.0)
	blood_level = randi_range(30, 80)

func get_schedule() -> Array:
	return [
		# Vampires are nocturnal - sleep during day, active at night
		{"start_minute": 0, "end_minute": 480, "zone": "Coffin", "actions": [Callable(self, "rest_in_coffin")]},
		{"start_minute": 1080, "end_minute": 1200, "zone": "Bar", "actions": [Callable(self, "drink_blood")]},
		{"start_minute": 1200, "end_minute": 1440, "zone": "Lounge", "actions": [Callable(self, "socialize")]}
	]

func rest_in_coffin():
	print("%s is resting in their coffin..." % npc_name)
	coffin_rested = true
	return [true, ""]

func drink_blood():
	if blood_level >= 100:
		return [false, "already satisfied"]
	print("%s is drinking blood wine..." % npc_name)
	blood_level = min(100, blood_level + 30)
	return [true, ""]

func socialize():
	if not coffin_rested:
		return [false, "too tired to socialize"]
	print("%s is socializing with other guests..." % npc_name)
	blood_level = max(0, blood_level - 5)
	return [true, ""]
