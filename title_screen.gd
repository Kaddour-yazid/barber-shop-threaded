extends Control

const MIN_SEATS := 1
const MAX_SEATS := 10

# --- NODE REFS ------------------------------------------------------

var background_rect: TextureRect
var manual_button: TextureButton
var auto_button: TextureButton
var start_button: TextureButton
var seats_label: Label
var seats_minus: TextureButton
var seats_plus: TextureButton
var girl_sprite: Sprite2D

var help_button: TextureButton         # small ? button on title
var help_popup: TextureRect            # big HELP image panel
var help_back_button: Button           # invisible BACK button inside popup

# --- UNIVERSAL NODE FINDER -----------------------------------------

func _find_required_node(node_name: String, expected_class: String) -> Node:
	var found_node = find_child(node_name, true, false)

	if not is_instance_valid(found_node):
		print("FATAL ERROR: Node not found! Expected name: '", node_name, "'.")
		return null

	if not found_node.is_class(expected_class):
		if not (expected_class == "Button" and found_node.is_class("TextureButton")):
			print("WARNING: Node '", node_name, "' found, but type '",
				found_node.get_class(), "', expected '", expected_class, "'.")
	return found_node


func _ready() -> void:
	background_rect = _find_required_node("TitleScBackgroundreen", "TextureRect")
	manual_button   = _find_required_node("ManualButton", "TextureButton")
	auto_button     = _find_required_node("AutoButton", "TextureButton")
	start_button    = _find_required_node("StartButton", "TextureButton")
	seats_label     = _find_required_node("LabSeatsLabel", "Label")
	seats_minus     = _find_required_node("SeatsMinus", "TextureButton")
	seats_plus      = _find_required_node("SeatsPlus", "TextureButton")
	girl_sprite     = _find_required_node("GirlSprite", "Sprite2D")

	help_button      = _find_required_node("HelpButton", "TextureButton")
	help_popup       = _find_required_node("HelpPopup", "TextureRect")
	help_back_button = _find_required_node("HelpBackButton", "Button")

	if not (is_instance_valid(manual_button)
		and is_instance_valid(auto_button)
		and is_instance_valid(start_button)):
		print("Initialization failed. Not all critical nodes were found.")
		return

	_apply_style_and_text()
	_update_mode_buttons()
	_update_seats_label()

	manual_button.pressed.connect(_on_manual_pressed)
	auto_button.pressed.connect(_on_auto_pressed)
	seats_minus.pressed.connect(_on_seats_minus_pressed)
	seats_plus.pressed.connect(_on_seats_plus_pressed)
	start_button.pressed.connect(_on_start_pressed)

	if is_instance_valid(help_button):
		help_button.pressed.connect(_on_help_button_pressed)
	if is_instance_valid(help_back_button):
		help_back_button.pressed.connect(_on_help_back_pressed)

	if is_instance_valid(help_popup):
		help_popup.visible = false


func _apply_style_and_text() -> void:
	var pixel_color_accent = Color("#A85C32")
	if is_instance_valid(seats_label):
		seats_label.add_theme_color_override("font_color", pixel_color_accent)


func _update_mode_buttons() -> void:
	var m := GameConfig.game_mode
	if is_instance_valid(manual_button):
		manual_button.button_pressed = (m == GameConfig.GameMode.MANUAL)
	if is_instance_valid(auto_button):
		auto_button.button_pressed   = (m == GameConfig.GameMode.AUTO)


func _update_seats_label() -> void:
	if is_instance_valid(seats_label):
		seats_label.text = "Seats: %d" % GameConfig.seat_count


func _on_manual_pressed() -> void:
	GameConfig.game_mode = GameConfig.GameMode.MANUAL
	_update_mode_buttons()


func _on_auto_pressed() -> void:
	GameConfig.game_mode = GameConfig.GameMode.AUTO
	_update_mode_buttons()


func _on_seats_plus_pressed() -> void:
	if GameConfig.seat_count < MAX_SEATS:
		GameConfig.seat_count += 1
		_update_seats_label()


func _on_seats_minus_pressed() -> void:
	if GameConfig.seat_count > MIN_SEATS:
		GameConfig.seat_count -= 1
		_update_seats_label()


func _on_start_pressed() -> void:
	if GameConfig.game_mode == GameConfig.GameMode.NONE:
		print("ERROR: Please select MANUAL or AUTO mode before starting!")
		return

	if is_instance_valid(manual_button):
		manual_button.disabled = true
	if is_instance_valid(auto_button):
		auto_button.disabled = true
	if is_instance_valid(start_button):
		start_button.disabled = true

	if not is_instance_valid(girl_sprite):
		get_tree().change_scene_to_file("res://barber_shop_threaded.tscn")
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var target_pos: Vector2 = girl_sprite.global_position
	target_pos.x = viewport_size.x + 50.0

	var walk_time := 1.2
	var tween := create_tween()
	tween.tween_property(girl_sprite, "global_position", target_pos, walk_time)
	tween.finished.connect(_on_girl_walk_finished)


func _on_girl_walk_finished() -> void:
	get_tree().change_scene_to_file("res://barber_shop_threaded.tscn")

# --- HELP POPUP -----------------------------------------------------

func _on_help_button_pressed() -> void:
	if is_instance_valid(help_popup):
		help_popup.visible = true


func _on_help_back_pressed() -> void:
	if is_instance_valid(help_popup):
		help_popup.visible = false
