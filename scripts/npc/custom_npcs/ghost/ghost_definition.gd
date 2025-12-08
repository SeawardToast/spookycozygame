# GhostNPCDefinition.gd
# Defines the ghost NPC's behavior and schedule
# This is a data/logic class, not a visual node
extends RefCounted
class_name Ghost

var npc_id: String = "" # Will be set by manager
var npc_name: String = "Ghostly Guest"
var start_position: Vector2 = Vector2(100, 100)
var speed: float = 100.0

# Visual properties (for when visual NPC is spawned)
var sprite_texture: String = "res://sprites/ghost.png"
var sprite_animation: String = "ghost_idle"

# State for actions (this would be the NPC's "brain")
var tired: bool = true
var hunger: int = 100

func _init():
	# Randomize name for variety
	var ghost_names = ["Casper", "Boo", "Phantom", "Specter", "Wraith", "Spirit"]
	npc_name = ghost_names[randi() % ghost_names.size()] + " the Ghost"
	
	# Randomize some properties
	speed = randf_range(80.0, 120.0)
	tired = randf() > 0.5

func get_schedule() -> Array:
	return [
		{"start_minute": 250, "end_minute": 600, "zone": "Kitchen", "actions": [Callable(self, "eat")]},
		{"start_minute": 601, "end_minute": 800, "zone": "Sleep", "actions": [Callable(self, "sleep")]},
		{"start_minute": 900, "end_minute": 1440, "zone": "Haunt", "actions": [Callable(self, "haunt")]}
	]
	
func sleep():
	if not tired:
		return [false, "not tired"]
	if tired:
		print("%s is sleeping..." % npc_name)
		tired = false
		return [true, ""]

func eat():
	print("%s is eating..." % npc_name)
	hunger = max(0, hunger - 20)
	return [true, ""]

func haunt():
	print("%s is haunting..." % npc_name)
	# Haunting makes them tired
	tired = true
	return [true, ""]
