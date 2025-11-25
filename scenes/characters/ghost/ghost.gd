extends ScheduledNPC

@export var sleep_zone: NavigationRegion2D
@export var eat_zone: NavigationRegion2D
@export var haunt_zone: NavigationRegion2D

func _ready():
	# call parent ready to connect to clock
	super._ready()

	# Define custom schedule
	daily_schedule = [
		{"start_minute": 250, "end_minute": 600, "zone": "Kitchen", "actions": [ Callable(self, "eat")]},
		{"start_minute": 601, "end_minute": 800, "zone": "Sleep", "actions": [ Callable(self, "sleep")]},
		{"start_minute": 900, "end_minute": 1440, "zone": "Haunt", "actions": [ Callable(self, "haunt")]}
	]

func sleep():
	var tired = true
	if not tired:
		return [false, "not tired"]
	if tired:
		print("%s is sleeping..." % npc_name)
		return [true, ""]
		
func eat():
	print("%s is eating..." % npc_name)
	return [true, ""]
	
func haunt():
	print("%s is haunting..." % npc_name)
	return [true, ""]
