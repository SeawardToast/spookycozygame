extends Node

signal guest_pending(assignment: GuestAssignment)
signal guest_checked_in(assignment: GuestAssignment)
signal guest_checked_out(assignment: GuestAssignment)

const MAX_PENDING: int = 5
const STAY_MIN_DAYS: int = 1
const STAY_MAX_DAYS: int = 3
const SAVE_PATH: String = "user://guest_assignments.json"

const BASE_RATE_PER_NIGHT: int = 10
const QUALITY_GOLD_PER_POINT: int = 2

var _pending_guests: Dictionary = {}  # guest_id -> GuestAssignment
var _guest_to_npc: Dictionary = {}    # guest_id -> npc_id
var _npc_to_guest: Dictionary = {}    # npc_id -> guest_id
var _guest_counter: int = 0


func _ready() -> void:
	DayAndNightCycleManager.time_tick_day.connect(_on_new_day)


func _on_new_day(day: int) -> void:
	_auto_checkout_expired(day)
	_try_generate_pending_guest(day)


# =============================================
# GUEST GENERATION
# =============================================

func _try_generate_pending_guest(day: int) -> void:
	if _pending_guests.size() >= MAX_PENDING:
		return

	var guest_type: String = NPCTypeRegistry.get_random_type()
	if guest_type.is_empty():
		return

	var room_id: String = RoomManager.find_available_room(guest_type)
	if room_id.is_empty():
		return

	var guest_id: String = _generate_guest_id(guest_type)
	var definition: Variant = NPCTypeRegistry.create_npc_definition(guest_type)
	var stay_days: int = randi_range(STAY_MIN_DAYS, STAY_MAX_DAYS)

	var assignment: GuestAssignment = RoomManager.assign_guest(
		guest_id, guest_type, room_id, day, day + stay_days
	)
	if not assignment:
		return

	assignment.guest_name = definition.npc_name
	_pending_guests[guest_id] = assignment
	guest_pending.emit(assignment)
	DailyReportManager.generate_alert("guest_pending", "low", guest_id, assignment.guest_name, "%s is waiting to check in" % assignment.guest_name, "lobby")
	print("GuestAssignmentManager: New pending guest %s (%s) in room %s" % [assignment.guest_name, guest_type, room_id])


func _generate_guest_id(guest_type: String) -> String:
	_guest_counter += 1
	return "%s_%d" % [guest_type, _guest_counter]


# =============================================
# QUERIES
# =============================================

func get_pending_guests() -> Array[GuestAssignment]:
	var result: Array[GuestAssignment] = []
	for assignment: GuestAssignment in _pending_guests.values():
		result.append(assignment)
	return result


func get_checked_in_guests() -> Array[GuestAssignment]:
	var result: Array[GuestAssignment] = []
	for assignment: GuestAssignment in RoomManager.active_assignments.values():
		if assignment.status == GuestAssignment.Status.CHECKED_IN:
			result.append(assignment)
	return result


# =============================================
# CHECK IN / OUT
# =============================================

func check_in(guest_id: String) -> bool:
	var assignment: GuestAssignment = _pending_guests.get(guest_id)
	if not assignment:
		push_warning("GuestAssignmentManager: No pending guest with id %s" % guest_id)
		return false

	if not RoomManager.check_in_guest(guest_id):
		push_warning("GuestAssignmentManager: RoomManager check_in failed for %s" % guest_id)
		return false

	var room: PlacedRoom = RoomManager.get_guest_room(guest_id)
	var spawn_pos: Vector2 = room.door_world_pos if room else Vector2.ZERO

	var npc_id: String = NPCSimulationManager.spawn_npc(assignment.guest_type, spawn_pos, assignment.guest_name)
	_guest_to_npc[guest_id] = npc_id
	_npc_to_guest[npc_id] = guest_id
	_pending_guests.erase(guest_id)

	_report_room_quality_mood(assignment, room)
	guest_checked_in.emit(assignment)
	print("GuestAssignmentManager: Checked in %s (npc_id: %s)" % [assignment.guest_name, npc_id])
	return true


func _report_room_quality_mood(assignment: GuestAssignment, room: PlacedRoom) -> void:
	if not room:
		return
	var quality: int = room.current_quality
	var mood: String
	var intensity: int
	if quality == 0:
		mood = "disappointed"
		intensity = 3
	elif quality < 10:
		mood = "neutral"
		intensity = 5
	elif quality < 25:
		mood = "satisfied"
		intensity = 6
	elif quality < 45:
		mood = "happy"
		intensity = 8
	else:
		mood = "delighted"
		intensity = 10
	DailyReportManager.report_mood(
		assignment.guest_id,
		assignment.guest_name,
		mood,
		intensity,
		"room quality",
		assignment.room_instance_id
	)


func check_out(guest_id: String) -> bool:
	var assignment: GuestAssignment = _find_active_assignment(guest_id)
	# Fetch room before RoomManager erases guest_to_room
	var room: PlacedRoom = RoomManager.placed_rooms.get(assignment.room_instance_id) if assignment else null

	if not RoomManager.check_out_guest(guest_id):
		push_warning("GuestAssignmentManager: RoomManager check_out failed for %s" % guest_id)
		return false

	var npc_id: String = _guest_to_npc.get(guest_id, "")
	if not npc_id.is_empty():
		NPCSimulationManager.despawn_npc(npc_id)
		_npc_to_guest.erase(npc_id)
	_guest_to_npc.erase(guest_id)

	if assignment:
		guest_checked_out.emit(assignment)
		var message: String = _build_checkout_message(assignment, room)
		DailyReportManager.generate_alert("checkout", "low", assignment.guest_id, assignment.guest_name, message, "lobby")
		print("GuestAssignmentManager: Checked out %s" % assignment.guest_name)
	return true


func _build_checkout_message(assignment: GuestAssignment, room: PlacedRoom) -> String:
	var nights: int = assignment.check_out_day - assignment.check_in_day
	var night_str: String = "night" if nights == 1 else "nights"

	var report: Variant = DailyReportManager.get_guest_report(assignment.guest_id)
	var mood_line: String = ""
	if report:
		report.calculate_metrics()
		mood_line = "\nMood: %s (avg %.1f) — peaked at %d, dipped to %d" % [
			_mood_label(report.average_mood), report.average_mood,
			report.highest_mood, report.lowest_mood
		]

	var room_quality: int = room.current_quality if room else 0
	var base_pay: int = nights * BASE_RATE_PER_NIGHT
	var bonus_pay: int = room_quality * QUALITY_GOLD_PER_POINT
	var payment_line: String = "\nPayment: %d gold (%d base + %d room bonus)" % [
		base_pay + bonus_pay, base_pay, bonus_pay
	]

	return "%s has checked out (%d %s)%s%s" % [
		assignment.guest_name, nights, night_str, mood_line, payment_line
	]


func _mood_label(avg: float) -> String:
	if avg >= 9.0:
		return "delighted"
	elif avg >= 7.0:
		return "happy"
	elif avg >= 5.0:
		return "satisfied"
	elif avg >= 3.0:
		return "neutral"
	elif avg >= 1.5:
		return "disappointed"
	return "miserable"


func _auto_checkout_expired(current_day: int) -> void:
	var to_checkout: Array[String] = []
	for assignment: GuestAssignment in RoomManager.active_assignments.values():
		if assignment.status == GuestAssignment.Status.CHECKED_IN and current_day >= assignment.check_out_day:
			to_checkout.append(assignment.guest_id)
	for guest_id: String in to_checkout:
		check_out(guest_id)


func _find_active_assignment(guest_id: String) -> GuestAssignment:
	var room_id: String = RoomManager.guest_to_room.get(guest_id, "")
	if room_id.is_empty():
		return null
	var assignment_id: String = RoomManager.room_assignments.get(room_id, "")
	return RoomManager.active_assignments.get(assignment_id)


# =============================================
# SAVE / LOAD
# =============================================

func save_state() -> void:
	var data: Dictionary = {
		"guest_counter": _guest_counter,
		"guest_to_npc": _guest_to_npc.duplicate(),
		"npc_to_guest": _npc_to_guest.duplicate()
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	else:
		push_error("GuestAssignmentManager: Failed to save state")


func load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("GuestAssignmentManager: Failed to open save file")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("GuestAssignmentManager: Failed to parse save file")
		return
	var data: Dictionary = json.data
	_guest_counter = data.get("guest_counter", 0)
	_guest_to_npc = data.get("guest_to_npc", {})
	_npc_to_guest = data.get("npc_to_guest", {})
	print("GuestAssignmentManager: Loaded state (counter: %d, checked_in: %d)" % [_guest_counter, _guest_to_npc.size()])


func sync_pending_from_room_manager() -> void:
	_pending_guests.clear()
	for assignment: GuestAssignment in RoomManager.active_assignments.values():
		if assignment.status == GuestAssignment.Status.PENDING:
			_pending_guests[assignment.guest_id] = assignment
	print("GuestAssignmentManager: Synced %d pending guests from RoomManager" % _pending_guests.size())
