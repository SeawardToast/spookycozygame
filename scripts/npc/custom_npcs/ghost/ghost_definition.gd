# GhostNPCDefinition.gd
# Refactored ghost NPC definition using new architecture
extends RefCounted
class_name Ghost

var npc_id: String = ""
var npc_name: String = "Ghostly Guest"
var start_position: Vector2 = Vector2(100, 100)
var speed: float = 100.0

# Visual properties
var sprite_texture: String = "res://sprites/ghost.png"
var sprite_animation: String = "ghost_idle"

# Ghost state
var tired: bool = true
var hunger: int = 100
var spookiness: int = 50  # How scary the ghost is feeling

func _init():
	# Randomize name
	var ghost_names = ["Casper", "Boo", "Phantom", "Specter", "Wraith", "Spirit", "Shade"]
	var titles = ["the Friendly", "the Mischievous", "the Shy", "the Dramatic", "the Hungry"]
	npc_name = "%s %s Ghost" % [ghost_names[randi() % ghost_names.size()], titles[randi() % titles.size()]]
	
	# Randomize properties
	speed = randf_range(80.0, 120.0)
	tired = randf() > 0.5
	hunger = randi_range(50, 100)
	spookiness = randi_range(20, 80)

## Alternative: Get schedule in NEW format (preferred)
func get_schedule() -> Array[ScheduleEntry]:
	var schedule: Array[ScheduleEntry] = []
	
	# Morning breakfast
	var breakfast = ScheduleEntry.create("breakfast", 250, 360, "Kitchen")
	breakfast.add_action(NPCAction.create("eat", "Eat Breakfast", eat_breakfast))
	breakfast.add_action(NPCAction.create("read", "Read Newspaper", read_newspaper))
	schedule.append(breakfast)
	
	# Morning sleep
	var sleep = ScheduleEntry.create("morning_rest", 361, 540, "Sleep")
	sleep.add_action(NPCAction.create("sleep", "Go to Sleep", go_to_sleep))
	schedule.append(sleep)
	
	# Afternoon haunting
	var haunt = ScheduleEntry.create("afternoon_haunt", 900, 1080, "Haunt")
	haunt.add_action(NPCAction.create("haunt", "Haunt Halls", haunt_halls))
	haunt.add_action(NPCAction.create("scare", "Practice Scares", practice_scares))
	haunt.priority = 5  # Higher priority
	schedule.append(haunt)
	
	# Evening reading
	var reading = ScheduleEntry.create("evening_reading", 1200, 1439, "Library")
	reading.add_action(NPCAction.create("read_books", "Read Spooky Books", read_spooky_books))
	reading.add_action(NPCAction.create("contemplate", "Contemplate Existence", contemplate_existence))
	reading.can_interrupt = true  # Player can interrupt reading
	schedule.append(reading)
	
	return schedule

# =============================================================================
# ACTION METHODS
# =============================================================================

func eat_breakfast() -> Array:
	if hunger <= 20:
		return [false, "Not hungry enough"]
	
	print("%s is eating a ghostly breakfast..." % npc_name)
	hunger = max(0, hunger - 30)
	spookiness += 5  # Feel more energetic
	return [true, ""]

func read_newspaper() -> Dictionary:
	print("%s is reading the obituaries..." % npc_name)
	return {
		"success": true,
		"reason": "",
		"info": "Found 3 new entries"
	}

func go_to_sleep() -> Array:
	if not tired:
		return [false, "Not tired enough to sleep"]
	
	print("%s is resting peacefully..." % npc_name)
	tired = false
	hunger += 10  # Get hungrier while sleeping
	return [true, ""]

func haunt_halls() -> Array:
	if hunger > 80:
		return [false, "Too hungry to haunt effectively"]
	
	print("%s is haunting the halls! Spookiness: %d" % [npc_name, spookiness])
	tired = true
	spookiness = min(100, spookiness + 10)
	return [true, ""]

func practice_scares() -> Dictionary:
	var scare_quality = randi_range(1, 10)
	var success = scare_quality > 3
	
	if success:
		print("%s practiced a great scare! (Quality: %d/10)" % [npc_name, scare_quality])
		spookiness = min(100, spookiness + scare_quality)
	else:
		print("%s failed to scare anyone... (Quality: %d/10)" % [npc_name, scare_quality])
	
	return {
		"success": success,
		"reason": "Scare quality too low" if not success else "",
		"scare_quality": scare_quality
	}

func read_spooky_books() -> bool:
	print("%s is reading 'The Phantom's Guide to Effective Haunting'..." % npc_name)
	spookiness += 3
	return true

func contemplate_existence() -> Array:
	print("%s is pondering what it means to be a ghost..." % npc_name)
	# Deep thoughts might make them less spooky but more wise
	spookiness = max(0, spookiness - 5)
	return [true, "Reached enlightenment"]

# =============================================================================
# HELPER METHODS
# =============================================================================

func get_mood() -> String:
	if hunger > 80:
		return "Starving"
	elif tired:
		return "Exhausted"
	elif spookiness > 70:
		return "Very Spooky"
	elif spookiness < 30:
		return "Not Very Scary"
	else:
		return "Content"

func toString() -> String:
	return "%s - Hunger: %d, Tired: %s, Spookiness: %d, Mood: %s" % [
		npc_name,
		hunger,
		"Yes" if tired else "No",
		spookiness,
		get_mood()
	]
