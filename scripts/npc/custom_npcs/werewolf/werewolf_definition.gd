# WerewolfNPCDefinition.gd
extends RefCounted
class_name Werewolf

var npc_id: String = ""
var npc_name: String = "Howling Wolf"
var start_position: Vector2 = Vector2(300, 300)
var speed: float = 150.0

var moon_phase: float = 0.5  # 0 = new moon, 1 = full moon
var rage: int = 0

func get_schedule() -> Array[ScheduleEntry]:
	var schedule: Array[ScheduleEntry] = []
	
	# Morning patrol
	var patrol = ScheduleEntry.create("morning_patrol", 360, 540, "Forest")
	patrol.add_action(NPCAction.create("patrol", "Patrol Territory", patrol_territory))
	patrol.add_action(NPCAction.create("mark", "Mark Territory", mark_territory))
	schedule.append(patrol)
	
	# Evening hunting
	var hunt = ScheduleEntry.create("evening_hunt", 1080, 1200, "Forest")
	hunt.add_action(NPCAction.create("hunt", "Hunt for Food", hunt_for_food))
	hunt.priority = 10  # Very important
	schedule.append(hunt)
	
	# Full moon transformation (conditional)
	if moon_phase > 0.8:
		var transform = ScheduleEntry.create("transformation", 0, 60, "Courtyard")
		transform.add_action(NPCAction.create("howl", "Howl at Moon", howl_at_moon))
		transform.add_action(NPCAction.create("rampage", "Rampage", rampage))
		transform.priority = 100  # Highest priority
		schedule.append(transform)
	
	return schedule

func patrol_territory() -> Dictionary:
	print("%s is patrolling the forest" % npc_name)
	return {"success": true, "area_covered": "50%"}

func mark_territory() -> bool:
	print("%s marked territory" % npc_name)
	return true

func hunt_for_food() -> Array:
	var success = randf() > 0.3
	if success:
		print("%s caught prey!" % npc_name)
		rage = max(0, rage - 20)
	else:
		print("%s hunting failed" % npc_name)
		rage += 10
	return [success, "No prey found" if not success else ""]

func howl_at_moon() -> bool:
	print("%s howls at the full moon! AWOOOO!" % npc_name)
	rage = 100
	return true

func rampage() -> Dictionary:
	print("%s is in a rampage!" % npc_name)
	rage = max(0, rage - 50)
	return {"success": true, "damage_done": rage}
