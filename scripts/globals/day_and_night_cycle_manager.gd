extends Node

class Date:
	var day: int
	var minute: int
	var hour: int

const MINUTES_PER_DAY: int = 24 * 60
const MINUTES_PER_HOUR: int = 60
const GAME_MINUTE_DURATION: float = TAU / MINUTES_PER_DAY
const SAVE_PATH: String = "user://daytime_save.json"

var game_speed: float = 5.0
var initial_day: int = 1
var initial_hour: int = 1
var initial_minute: int = 30
var time: float = 0.0
var current_minute: int = -1
var current_day: int = 0

signal game_time(time: float)
signal time_tick(day: int, hour: int, minute: int)
signal time_tick_day(day: int)
signal time_loaded()
signal time_saved()

func _ready() -> void:
	# Try to load saved time, otherwise use initial time
	#if not load_time():

		#save_time()  # Save the starting state
	set_initial_time()

func _process(delta: float) -> void:
	time += delta * game_speed * GAME_MINUTE_DURATION
	game_time.emit(time)
	recalculate_time()

# --------------------------------------------
# Save/Load System
# --------------------------------------------

func save_time() -> bool:
	var current_time: Dictionary = get_current_time()
	
	var save_data: Dictionary = {
		"time": time,
		"current_minute": current_minute,
		"current_day": current_day,
		"game_speed": game_speed,
		"day": current_time.day,
		"hour": current_time.hour,
		"minute": current_time.minute,
		"version": "1.0"
	}
	
	var json_string: String = JSON.stringify(save_data, "\t")
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	
	if file == null:
		push_error("Failed to open save file for writing: " + SAVE_PATH)
		return false
	
	file.store_string(json_string)
	file.close()
	
	print("Time saved to: ", SAVE_PATH)
	time_saved.emit()
	return true

func load_time() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No time save file found at: ", SAVE_PATH)
		return false
	
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	
	if file == null:
		push_error("Failed to open save file for reading: " + SAVE_PATH)
		return false
	
	var json_string: String = file.get_as_text()
	file.close()
	
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse JSON: " + json.get_error_message())
		return false
	
	var save_data: Dictionary = json.data
	
	# Validate save data structure
	if not save_data.has("time"):
		push_error("Invalid save data structure")
		return false
	
	# Load time data
	time = save_data.get("time", 0.0)
	current_minute = save_data.get("current_minute", -1)
	current_day = save_data.get("current_day", 0)
	game_speed = save_data.get("game_speed", 5.0)
	
	print("Time loaded from: ", SAVE_PATH)
	print("Loaded day: ", save_data.get("day", 0), 
		  " hour: ", save_data.get("hour", 0), 
		  " minute: ", save_data.get("minute", 0))
	
	time_loaded.emit()
	return true

func delete_save() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		var dir: DirAccess = DirAccess.open("user://")
		var error: Error = dir.remove(SAVE_PATH)
		if error == OK:
			print("Time save file deleted: ", SAVE_PATH)
			return true
		else:
			push_error("Failed to delete time save file")
			return false
	return false

func reset_time() -> void:
	"""Reset time to initial state and save"""
	set_initial_time()
	current_minute = -1
	current_day = 0
	save_time()
	print("Time reset to initial state")

# --------------------------------------------
# Time Management
# --------------------------------------------

func set_initial_time() -> void:
	var initial_total_minutes: int = initial_day * MINUTES_PER_DAY + (initial_hour * MINUTES_PER_HOUR) + initial_minute
	time = initial_total_minutes * GAME_MINUTE_DURATION

func set_time(day: int, hour: int, minute: int) -> void:
	"""Manually set the current time"""
	var total_minutes: int = day * MINUTES_PER_DAY + (hour * MINUTES_PER_HOUR) + minute
	time = total_minutes * GAME_MINUTE_DURATION
	recalculate_time()

func get_current_time() -> Dictionary:
	var total_minutes: int = int(time / GAME_MINUTE_DURATION)
	var day: int = total_minutes / MINUTES_PER_DAY
	var current_day_minutes: int = total_minutes % MINUTES_PER_DAY
	var hour: int = current_day_minutes / MINUTES_PER_HOUR
	var minute: int = current_day_minutes % MINUTES_PER_HOUR
	
	return {
		"day": day,
		"hour": hour,
		"minute": minute,
		"total_minutes": total_minutes
	}

func recalculate_time() -> void:
	var total_minutes: int = int(time / GAME_MINUTE_DURATION)
	var day: int = int(total_minutes / MINUTES_PER_DAY)
	var current_day_minutes: int = total_minutes % MINUTES_PER_DAY
	var hour: int = int(current_day_minutes / MINUTES_PER_HOUR)
	var minute: int = int(current_day_minutes % MINUTES_PER_HOUR)
	
	if current_minute != minute:
		current_minute = minute
		time_tick.emit(day, hour, minute)
	
	if current_day != day:
		current_day = day
		time_tick_day.emit(day)

# --------------------------------------------
# Utility Functions
# --------------------------------------------

func get_time_of_day() -> String:
	"""Returns a string describing the current time of day"""
	var current_time: Dictionary = get_current_time()
	var hour: int = current_time.hour
	
	if hour >= 5 and hour < 12:
		return "Morning"
	elif hour >= 12 and hour < 17:
		return "Afternoon"
	elif hour >= 17 and hour < 21:
		return "Evening"
	else:
		return "Night"

func is_daytime() -> bool:
	"""Returns true if it's daytime (6 AM - 6 PM)"""
	var current_time: Dictionary = get_current_time()
	return current_time.hour >= 6 and current_time.hour < 18

func get_time_string() -> String:
	"""Returns formatted time string like 'Day 1, 12:30'"""
	var current_time: Dictionary = get_current_time()
	return "Day %d, %02d:%02d" % [current_time.day, current_time.hour, current_time.minute]

func set_game_speed(speed: float) -> void:
	"""Change the game speed multiplier"""
	game_speed = speed

func pause_time() -> void:
	"""Pause time progression"""
	game_speed = 0.0

func resume_time(speed: float = 5.0) -> void:
	"""Resume time progression"""
	game_speed = speed

# Auto-save on important events
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_time()
