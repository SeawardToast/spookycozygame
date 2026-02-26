class_name GuestAssignment
extends RefCounted

enum Status {
	PENDING,
	CHECKED_IN,
	CHECKED_OUT,
	CANCELLED
}

var assignment_id: String
var guest_id: String
var guest_name: String = ""
var guest_type: String
var room_instance_id: String
var check_in_day: int
var check_out_day: int
var status: Status = Status.PENDING


static func create(
	p_guest_id: String,
	p_guest_type: String,
	p_room_id: String,
	p_check_in: int,
	p_check_out: int
) -> GuestAssignment:
	var assignment := GuestAssignment.new()
	assignment.assignment_id = "%s_%s_%d" % [p_guest_id, p_room_id, p_check_in]
	assignment.guest_id = p_guest_id
	assignment.guest_type = p_guest_type
	assignment.room_instance_id = p_room_id
	assignment.check_in_day = p_check_in
	assignment.check_out_day = p_check_out
	assignment.status = Status.PENDING
	return assignment


func to_dict() -> Dictionary:
	return {
		"assignment_id": assignment_id,
		"guest_id": guest_id,
		"guest_name": guest_name,
		"guest_type": guest_type,
		"room_instance_id": room_instance_id,
		"check_in_day": check_in_day,
		"check_out_day": check_out_day,
		"status": status
	}


static func from_dict(data: Dictionary) -> GuestAssignment:
	var assignment := GuestAssignment.new()
	assignment.assignment_id = data.get("assignment_id", "")
	assignment.guest_id = data.get("guest_id", "")
	assignment.guest_name = data.get("guest_name", "")
	assignment.guest_type = data.get("guest_type", "")
	assignment.room_instance_id = data.get("room_instance_id", "")
	assignment.check_in_day = data.get("check_in_day", 0)
	assignment.check_out_day = data.get("check_out_day", 0)
	assignment.status = data.get("status", Status.PENDING)
	return assignment
