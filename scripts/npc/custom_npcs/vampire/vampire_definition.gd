extends RefCounted
class_name Vampire

var npc_id: String = ""
var npc_name: String = "Mysterious Vampire"
var start_position: Vector2 = Vector2(200, 150)
var speed: float = 5.0

# Vampire state
var thirst: int = 100        # Hunger but for blood
var elegance: int = 50       # Vampires judge themselves by grace & poise
var tired: bool = false      # Vampires rest in coffins at daybreak

func _init() -> void:
	# Randomize name
	var first_names: Array[String] = ["Vladimir", "Lilith", "Sanguis", "Noctis", "Valerie", "Dorian", "Elowen"]
	var surnames: Array[String] = ["Drakov", "Nightshade", "von Crimson", "Blackthorn", "Hollowmoor"]
	npc_name = "%s %s" % [
		first_names[randi() % first_names.size()],
		surnames[randi() % surnames.size()]
	]
	
	# Randomize properties
	speed = randf_range(70.0, 110.0)
	thirst = randi_range(40, 100)
	elegance = randi_range(30, 90)
	tired = randf() < 0.3

# ========================================================================
# SCHEDULE — Using NEW schedule system like the Ghost NPC
# ========================================================================
func get_schedule() -> Array[ScheduleEntry]:
	var schedule: Array[ScheduleEntry] = []
	
	# Late-afternoon rise from coffin
	var rise: ScheduleEntry = ScheduleEntry.create("rise", 1000, 1100, "Crypt")
	rise.add_action(NPCAction.create("rise_from_coffin", "Rise from Coffin", rise_from_coffin))
	schedule.append(rise)
	
	# Early evening hunt
	var hunt: ScheduleEntry = ScheduleEntry.create("evening_hunt", 1101, 1250, "Town")
	hunt.add_action(NPCAction.create("hunt", "Hunt for Blood", hunt_for_blood))
	hunt.add_action(NPCAction.create("stalk", "Stalk Prey", stalk_prey))
	hunt.priority = 6
	schedule.append(hunt)
	
	# Midnight ballroom practice
	var dance: ScheduleEntry = ScheduleEntry.create("midnight_dance", 1251, 1380, "Grand Hall")
	dance.add_action(NPCAction.create("practice_dance", "Practice Dark Waltz", practice_dark_waltz))
	dance.can_interrupt = false
	schedule.append(dance)
	
	# Pre-dawn retreat
	var retreat: ScheduleEntry = ScheduleEntry.create("retreat", 1381, 1439, "Crypt")
	retreat.add_action(NPCAction.create("return_to_crypt", "Return to Coffin", return_to_crypt))
	retreat.can_interrupt = true
	schedule.append(retreat)
	
	return schedule

# ========================================================================
# ACTION METHODS
# ========================================================================

func rise_from_coffin() -> Array:
	if tired == false:
		return [false, "Already awake"]
	
	print("%s rises slowly from the ancient coffin..." % npc_name)
	tired = false
	elegance += 5
	return [true, ""]

func hunt_for_blood() -> Array:
	if thirst <= 10:
		return [false, "Not thirsty enough to hunt"]
	
	print("%s is hunting for fresh blood..." % npc_name)
	thirst = max(0, thirst - 40)
	elegance += 2
	return [true, ""]

func stalk_prey() -> Dictionary:
	var skill: int = randi_range(1, 10)
	var success: bool = skill >= 4
	
	if success:
		print("%s stalked prey with grace (Skill: %d/10)" % [npc_name, skill])
		elegance = min(100, elegance + skill)
	else:
		print("%s stumbled during stalking... (Skill: %d/10)" % [npc_name, skill])
	
	return {
		"success": success,
		"reason": "Too clumsy" if not success else "",
		"skill": skill
	}

func practice_dark_waltz() -> bool:
	print("%s gracefully practices the forbidden waltz..." % npc_name)
	elegance = min(100, elegance + 4)
	return true

func return_to_crypt() -> Array:
	if tired:
		return [false, "Already heading to rest"]
	
	print("%s retreats into the shadows, returning to the crypt..." % npc_name)
	tired = true
	thirst += 15
	return [true, ""]

# ========================================================================
# HELPER METHODS
# ========================================================================

func get_mood() -> String:
	if thirst > 80:
		return "Blood-Starved"
	elif elegance > 70:
		return "Impeccably Graceful"
	elif tired:
		return "Weary of the Night"
	elif elegance < 30:
		return "Awkward and Irritated"
	else:
		return "Calmly Nocturnal"

func toString() -> String:
	return "%s - Thirst: %d, Tired: %s, Elegance: %d, Mood: %s" % [
		npc_name,
		thirst,
		"Yes" if tired else "No",
		elegance,
		get_mood()
	]
