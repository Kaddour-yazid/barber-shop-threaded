extends Node2D
@export var os_log_icon: Texture2D
@export var game_log_icon: Texture2D

const CustomerScene: PackedScene = preload("res://customer.tscn")

enum BarberState { SLEEPING, IDLE, CUTTING }

@onready var all_seats: Array[Node2D] = [
	$UI/Seat1,
	$UI/Seat2,
	$UI/Seat3,
	$UI/Seat4,
	$UI/Seat5,
	$UI/Seat6,
	$UI/Seat7,
	$UI/Seat8,
	$UI/Seat9,
	$UI/Seat10,
]

var seats: Array[Node2D] = []
var seat_count: int = 4

@onready var barber_sprite: ColorRect = $UI/BarberArea/BarberSprite
@onready var status_label: Label       = $UI/StatusLabel

@onready var mode_panel: Panel         = $UI/ModePanel
@onready var manual_button: Button     = $UI/ModePanel/VBoxContainer/ManualButton
@onready var auto_button: Button       = $UI/ModePanel/VBoxContainer/AutoButton

@onready var seats_label: Label        = $UI/ModePanel/VBoxContainer/SeatsHBox/SeatsLabel
@onready var seats_minus_button: Button = $UI/ModePanel/VBoxContainer/SeatsHBox/SeatsMinus
@onready var seats_plus_button: Button  = $UI/ModePanel/VBoxContainer/SeatsHBox/SeatsPlus

@onready var customer_timer: Timer     = $CustomerTimer
@onready var logic: ThreadedLogic      = $ThreadedLogic

@export var barber_tex_sleep: Texture2D
@export var barber_tex_work: Texture2D
@onready var barber_sprite_2d: Sprite2D = $BarberSprite2D

@onready var queue_label: Label = $UI/QueueLabel
@onready var stats_label: Label = $UI/StatsLabel

@onready var bgm_player: AudioStreamPlayer = $BgmPlayer
@onready var mute_button: TextureButton = $UI/MuteButton
@onready var back_button: TextureButton = $UI/BackButton

# PC logger: nodes are direct children of BarberShop
@onready var pc_desk: TextureRect       = $PcDesk
@onready var pc_log_popup: TextureRect  = $PcLogPopup
@onready var pc_log_text: RichTextLabel = $PcLogPopup/PcLogText

@onready var settings_button: TextureButton = $SettingsButton
@onready var settings_popup: TextureRect = $SettingsPopup
@onready var arrival_speed_slider: HSlider = $SettingsPopup/VBoxContainer/ArrivalSpeedSlider
@onready var haircut_speed_slider: HSlider = $SettingsPopup/VBoxContainer/HaircutSpeedSlider
@onready var walk_speed_slider: HSlider = $SettingsPopup/VBoxContainer/WalkSpeedSlider
@onready var patience_slider: HSlider = $SettingsPopup/VBoxContainer/PatienceSlider
@onready var close_settings_button: Button = $SettingsPopup/CloseSettingsButton
@onready var reset_button: TextureButton = $SettingsPopup/ResetButton
@onready var log_mode_button: TextureButton = $PcLogPopup/LogModeButton




var arrival_speed_factor := 1.0
var haircut_speed_factor := 1.0
var walk_speed_factor := 1.0
var patience_factor := 1.0

var bgm_muted: bool = false

var _game_log: String = ""
var _os_log: String = ""
var show_os_log: bool = false



var seat_occupants: Array[Control] = []
var waiting_customers: Array[Control] = []

var customers_by_id: Dictionary = {}      # AUTO mode customers
var manual_current_customer: Control = null

var spawn_position: Vector2
var barber_position: Vector2

var barber_state: int = BarberState.SLEEPING
var current_mode: int = GameConfig.GameMode.MANUAL

var cutting_tween: Tween = null
var total_arrived: int = 0

func log_from_thread(msg: String) -> void:
	call_deferred("add_log", msg)

func _ready() -> void:
	add_log("READY (threaded)")

	if GameConfig.seat_count > 0:
		seat_count = GameConfig.seat_count

	current_mode = GameConfig.game_mode
	if current_mode == GameConfig.GameMode.NONE:
		current_mode = GameConfig.GameMode.MANUAL
		add_log("Warning: Scene run directly, defaulting to MANUAL")

	update_active_seats()
	_update_seat_queue_labels()

	mode_panel.visible = false

	set_barber_state(BarberState.SLEEPING)
	randomize()

	spawn_position = Vector2(120, 360)
	var barber_area: Control = $UI/BarberArea
	barber_position = barber_area.global_position + barber_area.size * 0.5

	if queue_label:
		queue_label.text = "Next ticket: 1"
	if stats_label:
		stats_label.text = "Total entered: 0"

	manual_button.pressed.connect(_on_manual_button_pressed)
	auto_button.pressed.connect(_on_auto_button_pressed)
	seats_minus_button.pressed.connect(_on_seats_minus_pressed)
	seats_plus_button.pressed.connect(_on_seats_plus_pressed)

	# Make sure timeout is NOT also connected in the editor
	customer_timer.timeout.connect(_on_customer_timer_timeout)

	logic.barber_started.connect(_on_barber_started)
	logic.barber_finished.connect(_on_barber_finished)
	logic.stats_updated.connect(_on_stats_updated)

	if logic:
		logic.logger = Callable(self, "log_from_thread")

	if settings_popup:
		settings_popup.visible = false

	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)
	if close_settings_button:
		close_settings_button.pressed.connect(_on_close_settings_button_pressed)

	if arrival_speed_slider:
		arrival_speed_slider.value_changed.connect(_on_arrival_speed_changed)
		arrival_speed_slider.min_value = 0.5
		arrival_speed_slider.max_value = 2.0
		arrival_speed_slider.value = 1.0

	if haircut_speed_slider:
		haircut_speed_slider.value_changed.connect(_on_haircut_speed_changed)
		haircut_speed_slider.min_value = 0.5
		haircut_speed_slider.max_value = 2.0
		haircut_speed_slider.value = 1.0

	if walk_speed_slider:
		walk_speed_slider.value_changed.connect(_on_walk_speed_changed)
		walk_speed_slider.min_value = 0.5
		walk_speed_slider.max_value = 2.0
		walk_speed_slider.value = 1.0

	if patience_slider:
		patience_slider.value_changed.connect(_on_patience_changed)
		patience_slider.min_value = 0.5
		patience_slider.max_value = 2.0
		patience_slider.value = 1.0

	if reset_button:
		reset_button.pressed.connect(_on_reset_button_pressed)

	if mute_button:
		mute_button.toggled.connect(_on_mute_toggled)
		_sync_mute_state()

	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)

	if pc_log_popup:
		pc_log_popup.visible = false
	if log_mode_button:
		log_mode_button.pressed.connect(_on_log_mode_button_pressed)

	if current_mode == GameConfig.GameMode.AUTO:
		add_log("Starting in AUTO mode")
		_schedule_next_customer()
		auto_button.disabled = true
		manual_button.disabled = false
	else:
		add_log("Starting in MANUAL mode")
		auto_button.disabled = false
		manual_button.disabled = true


func _on_reset_button_pressed() -> void:
	# reset factors
	arrival_speed_factor = 1.0
	haircut_speed_factor = 1.0
	walk_speed_factor = 1.0
	patience_factor = 1.0

	# reset sliders (this will also fire the *_changed handlers)
	if arrival_speed_slider:
		arrival_speed_slider.value = 1.0
	if haircut_speed_slider:
		haircut_speed_slider.value = 1.0
	if walk_speed_slider:
		walk_speed_slider.value = 1.0
	if patience_slider:
		patience_slider.value = 1.0

	# make sure thread uses default haircut time again
	if logic:
		logic.haircut_time_sec = 2.0

	add_log("Settings reset to 1x")


func _exit_tree() -> void:
	if logic:
		logic.stop()

func _on_settings_button_pressed() -> void:
	if settings_popup:
		settings_popup.visible = true
	add_log("Settings button pressed")

func _on_close_settings_button_pressed() -> void:
	if settings_popup:
		settings_popup.visible = false



# -------------------------------------------------------------------
# LOG HELPER
# -------------------------------------------------------------------

# PC DESK / LOG MONITOR
# -------------------------------------------------------------------
func add_log(msg: String) -> void:
	print(msg)

	if msg.begins_with("THREAD:") or msg.begins_with("MUTEX:") \
	or msg.begins_with("SEMAPHORE:") or msg.begins_with("EVENT:") \
	or msg.begins_with("SLEEP:"):
		_os_log += msg + "\n"
	else:
		_game_log += msg + "\n"

	if pc_log_text:
		pc_log_text.clear()
		if show_os_log:
			pc_log_text.append_text(_os_log)
		else:
			pc_log_text.append_text(_game_log)
		pc_log_text.scroll_to_line(pc_log_text.get_line_count() - 1)



func _on_log_mode_button_pressed() -> void:
	show_os_log = not show_os_log

	if pc_log_text:
		pc_log_text.clear()
		if show_os_log:
			pc_log_text.append_text(_os_log)
		else:
			pc_log_text.append_text(_game_log)
		pc_log_text.scroll_to_line(pc_log_text.get_line_count() - 1)








# -------------------------------------------------------------------
# PROCESS / INPUT
# -------------------------------------------------------------------

func _process(_delta: float) -> void:
	if current_mode == GameConfig.GameMode.MANUAL:
		if Input.is_action_just_pressed("add_customer"):
			_manual_add_customer()
		if Input.is_action_just_pressed("send_next"):
			_manual_send_next_to_barber()
		if Input.is_action_just_pressed("finish_haircut"):
			_manual_finish_haircut()

# -------------------------------------------------------------------
# SEATS
# -------------------------------------------------------------------

func update_active_seats() -> void:
	seat_count = clamp(seat_count, 1, all_seats.size())

	seats.clear()
	for i in range(all_seats.size()):
		var seat_node := all_seats[i]
		var active: bool = i < seat_count
		seat_node.visible = active
		if active:
			seats.append(seat_node)

	var old_size = seat_occupants.size()
	seat_occupants.resize(seats.size())
	for i in range(old_size, seat_occupants.size()):
		seat_occupants[i] = null

	seats_label.text = "Seats: %d" % seat_count

	if logic:
		logic.set_seat_count(seat_count)

	add_log("Seat configuration updated. seat_count = %d" % seat_count)


func _on_seats_minus_pressed() -> void:
	if not waiting_customers.is_empty() or manual_current_customer or customers_by_id.size() > 0:
		add_log("Cannot change seats while customers are present.")
		return

	if seat_count <= 1:
		return
	seat_count -= 1
	update_active_seats()
	_update_seat_queue_labels()


func _on_seats_plus_pressed() -> void:
	if not waiting_customers.is_empty() or manual_current_customer or customers_by_id.size() > 0:
		add_log("Cannot change seats while customers are present.")
		return

	if seat_count >= all_seats.size():
		return
	seat_count += 1
	update_active_seats()
	_update_seat_queue_labels()

# random free seat
func _find_free_visual_seat() -> int:
	var free_indices: Array[int] = []
	for i in range(seats.size()):
		if seat_occupants[i] == null:
			free_indices.append(i)

	if free_indices.is_empty():
		return -1

	var rand_index := randi() % free_indices.size()
	return free_indices[rand_index]

# -------------------------------------------------------------------
# QUEUE LABELS ABOVE SEATS
# -------------------------------------------------------------------

func _update_seat_queue_labels() -> void:
	for i in range(seats.size()):
		var seat_node := seats[i]
		if seat_node == null:
			continue

		var label: Label = seat_node.get_node("QueueLabel") if seat_node.has_node("QueueLabel") else null
		if label == null:
			continue

		var customer := seat_occupants[i]
		if customer == null:
			label.text = ""
			continue

		var pos := waiting_customers.find(customer)
		if pos == -1:
			label.text = ""
		else:
			label.text = str(pos + 1)

# -------------------------------------------------------------------
# VISUAL HELPERS
# -------------------------------------------------------------------

func set_barber_state(new_state: int) -> void:
	barber_state = new_state

	if cutting_tween != null:
		cutting_tween.kill()
		cutting_tween = null
		barber_sprite.scale = Vector2.ONE

	match barber_state:
		BarberState.SLEEPING:
			barber_sprite.color = Color(0.1, 0.1, 0.1)
			status_label.text = "Barber sleeping (no customers)"
			if is_instance_valid(barber_sprite_2d) and barber_tex_sleep:
				barber_sprite_2d.texture = barber_tex_sleep

		BarberState.IDLE:
			barber_sprite.color = Color(0.0, 0.7, 0.0)
			status_label.text = "Barber awake, waiting"
			if is_instance_valid(barber_sprite_2d) and barber_tex_work:
				barber_sprite_2d.texture = barber_tex_work

		BarberState.CUTTING:
			barber_sprite.color = Color(0.8, 0.0, 0.0)
			status_label.text = "Barber cutting a customer"
			if is_instance_valid(barber_sprite_2d) and barber_tex_work:
				barber_sprite_2d.texture = barber_tex_work

			cutting_tween = create_tween().set_loops()
			cutting_tween.tween_property(barber_sprite, "scale", Vector2(1.1, 1.1), 0.2)
			cutting_tween.tween_property(barber_sprite, "scale", Vector2(1.0, 1.0), 0.2)


func move_customer(customer: Control, from_pos: Vector2, to_pos: Vector2, duration := 0.5, use_facing := true) -> void:
	if use_facing and customer.has_method("face_direction"):
		customer.face_direction(to_pos - from_pos)

	customer.global_position = from_pos
	var t := create_tween()
	t.tween_property(customer, "global_position", to_pos, duration / max(0.1, walk_speed_factor))


func _on_arrival_speed_changed(value: float) -> void:
	arrival_speed_factor = clamp(value, 0.5, 2.0)
	add_log("Settings: arrival factor = %f" % arrival_speed_factor)

func _on_haircut_speed_changed(value: float) -> void:
	haircut_speed_factor = clamp(value, 0.5, 2.0)
	if logic:
		logic.haircut_time_sec = 2.0 / haircut_speed_factor
	add_log("Settings: haircut factor = %f" % haircut_speed_factor)

func _on_walk_speed_changed(value: float) -> void:
	walk_speed_factor = clamp(value, 0.5, 2.0)
	add_log("Settings: walk factor = %f" % walk_speed_factor)

func _on_patience_changed(value: float) -> void:
	patience_factor = clamp(value, 0.5, 2.0)
	add_log("Settings: patience = %f" % patience_factor)



func _show_customer_leaving() -> void:
	var customer: Control = CustomerScene.instantiate()
	$UI.add_child(customer)

	var enter_pos := spawn_position + Vector2(-80, 0)
	var door_pos  := spawn_position

	customer.global_position = enter_pos

	move_customer(customer, enter_pos, door_pos, 0.4)

	var t := create_tween()
	t.tween_interval(0.4)
	t.tween_callback(func ():
		if customer.has_method("face_direction"):
			customer.face_direction(Vector2(-1, 0))
		var t2 := create_tween()
		t2.tween_property(customer, "global_position", enter_pos, 0.4)
		t2.finished.connect(func ():
			if is_instance_valid(customer):
				customer.queue_free()
		))

# ===================================================================
# MANUAL MODE
# ===================================================================

func _manual_add_customer() -> void:
	var idx := _find_free_visual_seat()
	if idx == -1:
		add_log("MANUAL: no free seats, customer leaves.")
		_show_customer_leaving()
		return

	# NEW: also tell the logic thread about this customer
	if logic == null:
		add_log("MANUAL: logic node missing, cannot use thread.")
		return

	var cust_id := logic.request_seat()
	if cust_id < 0:
		add_log("MANUAL: logic queue full, customer leaves.")
		_show_customer_leaving()
		return

	var customer: Control = CustomerScene.instantiate()
	$UI.add_child(customer)

	# keep your existing visual/manual state:
	waiting_customers.append(customer)
	customer.set_meta("seat_index", idx)
	customers_by_id[cust_id] = customer  # NEW: track by id so _on_barber_started/_finished work even in manual

	total_arrived += 1
	if customer.has_method("set_queue_number"):
		customer.set_queue_number(total_arrived)
	if queue_label:
		queue_label.text = "Next ticket: %d" % (total_arrived + 1)
	if stats_label:
		stats_label.text = "Total entered: %d" % total_arrived

	var seat_pos := seats[idx].global_position
	seat_occupants[idx] = customer

	move_customer(customer, spawn_position, seat_pos, 0.6)

	if barber_state == BarberState.SLEEPING and manual_current_customer == null:
		set_barber_state(BarberState.IDLE)

	add_log("MANUAL: new customer at seat %d (id=%d)" % [idx, cust_id])
	_update_seat_queue_labels()



func _manual_send_next_to_barber() -> void:
	if manual_current_customer:
		add_log("MANUAL: barber already busy.")
		return
	if waiting_customers.is_empty():
		add_log("MANUAL: no customers waiting.")
		return

	var customer: Control = waiting_customers.pop_front()
	var idx := int(customer.get_meta("seat_index", -1))
	if idx >= 0 and idx < seat_occupants.size():
		seat_occupants[idx] = null

	manual_current_customer = customer
	set_barber_state(BarberState.CUTTING)

	var start_pos := customer.global_position
	move_customer(customer, start_pos, barber_position, 0.6)

	add_log("MANUAL: customer moved to barber chair.")
	_update_seat_queue_labels()


func _manual_finish_haircut() -> void:
	if manual_current_customer == null:
		add_log("MANUAL: no customer at the chair.")
		return

	if manual_current_customer.has_method("apply_random_new_style"):
		manual_current_customer.apply_random_new_style()

	var exit_pos := spawn_position
	var start_pos := manual_current_customer.global_position
	move_customer(manual_current_customer, start_pos, exit_pos, 0.6, false)

	var c := manual_current_customer
	manual_current_customer = null

	var t := create_tween()
	t.tween_interval(0.6)
	t.finished.connect(func():
		if is_instance_valid(c):
			c.queue_free()
	)

	if waiting_customers.is_empty():
		set_barber_state(BarberState.SLEEPING)
	else:
		set_barber_state(BarberState.IDLE)

	add_log("MANUAL: haircut finished.")
	_update_seat_queue_labels()

# ===================================================================
# AUTO MODE (ThreadedLogic)
# ===================================================================

func _spawn_customer_auto() -> void:
	if logic == null:
		return

	var cust_id := logic.request_seat()
	if cust_id < 0:
		add_log("AUTO: no free logical seats, customer leaves.")
		_show_customer_leaving()
		return

	var seat_index := _find_free_visual_seat()
	if seat_index == -1:
		add_log("AUTO: no visual seat free but logic gave one?!")
		_show_customer_leaving()
		return

	var customer: Control = CustomerScene.instantiate()
	$UI.add_child(customer)

	customers_by_id[cust_id] = customer
	waiting_customers.append(customer)
	customer.set_meta("seat_index", seat_index)

	total_arrived += 1
	if customer.has_method("set_queue_number"):
		customer.set_queue_number(total_arrived)
	if queue_label:
		queue_label.text = "Next ticket: %d" % (total_arrived + 1)
	if stats_label:
		stats_label.text = "Total entered: %d" % total_arrived

	var seat_pos := seats[seat_index].global_position
	seat_occupants[seat_index] = customer

	move_customer(customer, spawn_position, seat_pos, 0.6)

	if barber_state == BarberState.SLEEPING:
		set_barber_state(BarberState.IDLE)

	add_log("AUTO: new customer %d at seat %d" % [cust_id, seat_index])
	_update_seat_queue_labels()


func _on_barber_started(customer_id: int) -> void:
	if current_mode != GameConfig.GameMode.AUTO:
		return

	var customer: Control = customers_by_id.get(customer_id, null)
	if customer == null:
		return

	var seat_index := int(customer.get_meta("seat_index", -1))
	if seat_index >= 0 and seat_index < seat_occupants.size():
		seat_occupants[seat_index] = null

	waiting_customers.erase(customer)
	set_barber_state(BarberState.CUTTING)

	var start_pos := customer.global_position
	move_customer(customer, start_pos, barber_position, 0.6)

	add_log("AUTO: barber started on customer %d" % customer_id)
	_update_seat_queue_labels()


func _on_barber_finished(customer_id: int) -> void:
	if current_mode != GameConfig.GameMode.AUTO:
		return

	var customer: Control = customers_by_id.get(customer_id, null)
	if customer:
		if customer.has_method("apply_random_new_style"):
			customer.apply_random_new_style()

		var exit_pos := spawn_position
		var start_pos := customer.global_position
		move_customer(customer, start_pos, exit_pos, 0.6, false)

		var c := customer
		var t := create_tween()
		t.tween_interval(0.6)
		t.finished.connect(func():
			if is_instance_valid(c):
				c.queue_free()
		)

	customers_by_id.erase(customer_id)

	if waiting_customers.is_empty():
		set_barber_state(BarberState.SLEEPING)
	else:
		set_barber_state(BarberState.IDLE)

	add_log("AUTO: barber finished with customer %d" % customer_id)
	_update_seat_queue_labels()


func _on_stats_updated(_waiting_count: int, _free_seats: int) -> void:
	pass

# -------------------------------------------------------------------
# MODE SWITCHING + TIMER
# -------------------------------------------------------------------

func _on_manual_button_pressed() -> void:
	current_mode = GameConfig.GameMode.MANUAL
	GameConfig.game_mode = GameConfig.GameMode.MANUAL

	manual_button.disabled = true
	auto_button.disabled = false

	customer_timer.stop()

	for c in customers_by_id.values():
		if is_instance_valid(c):
			c.queue_free()
	customers_by_id.clear()

	add_log("Manual mode: use A (add), S (send), F (finish).")


func _on_auto_button_pressed() -> void:
	current_mode = GameConfig.GameMode.AUTO
	GameConfig.game_mode = GameConfig.GameMode.AUTO

	auto_button.disabled = true
	manual_button.disabled = false

	if manual_current_customer:
		manual_current_customer.queue_free()
	manual_current_customer = null
	waiting_customers.clear()
	for i in range(seat_occupants.size()):
		seat_occupants[i] = null

	add_log("Automatic mode selected.")
	_schedule_next_customer()
	_update_seat_queue_labels()


func _schedule_next_customer() -> void:
	var r := randf()
	var wait: float
	if r < 0.2:
		wait = randf_range(3.0, 7.0)
	else:
		wait = randf_range(0.5, 3.0)

	wait /= max(0.1, arrival_speed_factor)
	add_log("AUTO: next customer in %f" % wait)
	customer_timer.start(wait)



func _on_customer_timer_timeout() -> void:
	if current_mode != GameConfig.GameMode.AUTO:
		return

	add_log("AUTO: CustomerTimer timeout fired")
	_spawn_customer_auto()
	_schedule_next_customer()

# -------------------------------------------------------------------
# AUDIO MUTE TOGGLE
# -------------------------------------------------------------------

func _on_mute_toggled(pressed: bool) -> void:
	bgm_muted = pressed
	_sync_mute_state()


func _sync_mute_state() -> void:
	if bgm_player:
		bgm_player.volume_db = -80.0 if bgm_muted else 0.0
	if mute_button:
		mute_button.button_pressed = bgm_muted

# -------------------------------------------------------------------
# BACK BUTTON
# -------------------------------------------------------------------

func _on_back_button_pressed() -> void:
	customer_timer.stop()
	if logic:
		logic.stop()
	get_tree().change_scene_to_file("res://title_screen.tscn")

# -------------------------------------------------------------------
# PC DESK / LOG MONITOR
# -------------------------------------------------------------------



# Connected from PcDesk.gui_input in the editor.

func _on_PcDesk_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if pc_log_popup:
			pc_log_popup.visible = not pc_log_popup.visible
