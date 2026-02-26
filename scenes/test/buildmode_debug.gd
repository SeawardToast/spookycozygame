# BuildModeDebugUI.gd
# Temporary debug UI for testing build mode - replace with proper hotbar later
extends CanvasLayer

var panel: PanelContainer
var vbox: VBoxContainer
var piece_buttons: Dictionary = {}
var status_label: Label


func _ready() -> void:
	# Only show when build mode is active
	visible = false
	
	BuildModeManager.build_mode_entered.connect(_on_build_mode_entered)
	BuildModeManager.build_mode_exited.connect(_on_build_mode_exited)
	
	_create_ui()


func _create_ui() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(10, 10)
	add_child(panel)
	
	vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	# Title
	var title: Label = Label.new()
	title.text = "BUILD MODE"
	vbox.add_child(title)
	
	# Status
	status_label = Label.new()
	status_label.text = "Press B to toggle build mode"
	vbox.add_child(status_label)
	
	# Separator
	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)
	
	# Instructions
	var instructions: Label = Label.new()
	instructions.text = "Q/E: Rotate | LMB: Place | RMB: Delete"
	vbox.add_child(instructions)
	
	# Another separator
	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)
	
	# Piece buttons (will be populated when PieceRegistry is ready)
	call_deferred("_populate_piece_buttons")


func _populate_piece_buttons() -> void:
	# Clear existing buttons
	for button: Button in piece_buttons.values():
		button.queue_free()
	piece_buttons.clear()
	
	# Add a button for each registered piece
	var pieces: Array = BuildingPieceRegistry.get_all_pieces()
	
	if pieces.is_empty():
		var no_pieces_label: Label = Label.new()
		no_pieces_label.text = "(No pieces registered)"
		vbox.add_child(no_pieces_label)
		return
	
	for piece: BuildingPieceRegistry.PieceData in pieces:
		var button: Button = Button.new()
		button.text = piece.display_name
		button.pressed.connect(_on_piece_button_pressed.bind(piece.id))
		vbox.add_child(button)
		piece_buttons[piece.id] = button
	
	# Deselect button
	var deselect_btn: Button = Button.new()
	deselect_btn.text = "[Deselect]"
	deselect_btn.pressed.connect(_on_piece_button_pressed.bind(""))
	vbox.add_child(deselect_btn)


func _on_piece_button_pressed(piece_id: String) -> void:
	if BuildModeManager.placement_system:
		BuildModeManager.placement_system.select_piece(piece_id)
		_update_status()


func _update_status() -> void:
	if not BuildModeManager.placement_system:
		return
	
	var selected: String = BuildModeManager.placement_system.get_selected_piece()
	if selected == "":
		status_label.text = "No piece selected"
	else:
		var piece: BuildingPieceRegistry.PieceData = BuildingPieceRegistry.get_piece(selected)
		status_label.text = "Selected: %s" % piece.display_name


func _on_build_mode_entered() -> void:
	visible = true
	_update_status()


func _on_build_mode_exited() -> void:
	visible = false
