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
	BuildingLayoutData.save_layout_data()  # Save building layout dictionaries
	if save_level_data_component != null:
		save_level_data_component.save_game()
	print("Game saved")

func load_game() -> void:
	await get_tree().process_frame
	var save_level_data_component: SaveLevelDataComponent = get_tree().get_first_node_in_group("save_level_data_component")
	DayAndNightCycleManager.load_time()
	NPCSimulationManager.load_npcs()
	InventoryManager.load_all()
	if save_level_data_component != null:
		save_level_data_component.load_game()

	# Load building layout data (occupied cells dictionary)
	await get_tree().process_frame  # Wait for loaded scenes to be ready
	BuildingLayoutData.load_layout_data()
	print("Building layout data loaded")
		
func reset_game() -> void:
	await get_tree().process_frame
	InventoryManager.reset_inventory()
	DayAndNightCycleManager.reset_time()
	NPCSimulationManager.reset_npcs()
