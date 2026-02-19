extends Node

var allow_save_game: bool

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		save_game()

func save_game() -> void:
	var save_level_data_component: SaveLevelDataComponent = get_tree().get_first_node_in_group("save_level_data_component")
	DayAndNightCycleManager.save_time()
	NPCSimulationManager.save_npcs()
	InventoryManager.save_all()
	BuildingLayoutData.save_layout_data()
	RoomManager.save_rooms()
	GuestAssignmentManager.save_state()
	if save_level_data_component != null:
		save_level_data_component.save_game()
	print("Game saved")

func load_game() -> void:
	await get_tree().process_frame
	var save_level_data_component: SaveLevelDataComponent = get_tree().get_first_node_in_group("save_level_data_component")
	DayAndNightCycleManager.load_time()
	NPCSimulationManager.load_npcs()
	InventoryManager.load_all()

	# Load layout data before scenes so pending_custom_data and room data are available
	BuildingLayoutData.load_layout_data()
	RoomManager.load_rooms()

	# Load scene instances — room _ready() calls reconnect_instance() to set instance pointers
	if save_level_data_component != null:
		save_level_data_component.load_game()

	# Restore guest assignment state after scenes are loaded
	GuestAssignmentManager.load_state()
	GuestAssignmentManager.sync_pending_from_room_manager()

func reset_game() -> void:
	await get_tree().process_frame
	InventoryManager.delete_save()
	DayAndNightCycleManager.reset_time()
	NPCSimulationManager.reset_npcs()
	if FileAccess.file_exists(RoomManager.SAVE_PATH):
		DirAccess.remove_absolute(RoomManager.SAVE_PATH)
	if FileAccess.file_exists(GuestAssignmentManager.SAVE_PATH):
		DirAccess.remove_absolute(GuestAssignmentManager.SAVE_PATH)
