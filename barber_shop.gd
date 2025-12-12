extends Node2D

const CustomerScene: PackedScene = preload("res://customer.tscn")

enum BarberState { SLEEPING, IDLE, CUTTING }
enum GameMode   { MANUAL, AUTO }

@onready var all_seats: Array = [
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

var seats: Array = []
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
@onready var haircut_timer: Timer      = $HaircutTimer

var seat_occupants: Array = []
var waiting_customers: Array = []
var current_customer = null

var spawn_position: Vector2
var barber_position: Vector2

var barber_state: int = BarberState.SLEEPING
var game_mode: int   = GameMode.MANUAL

var cutting_tween: Tween = null
var dbg_time := 0.0


func _ready() -> void:
	print("READY CALLED")

	update_active_seats()

	spawn_position = Vector2(150, 400)

	var barber_area: Control = $UI/BarberArea
	barber_position = barber_area.global_position + barber_area.size * 0.5

	set_barber_state(BarberState.SLEEPING)

	randomize()

	manual_button.pressed.connect(_on_manual_button_pressed)
	auto_button.pressed.connect(_on_auto_button_pressed)

	seats_minus_button.pressed.connect(_on_seats_minus_pressed)
	seats_plus_button.pressed.connect(_on_seats_plus_pressed)

	customer_timer.timeout.connect(_on_customer_timer_timeout)
	haircut_timer.timeout.connect(_on_haircut_timer_timeout)

	mode_panel.visible = true

	print("Barber shop ready with %d seats" % seats.size())


func _process(delta: float) -> void:
	dbg_time += delta
	if dbg_time > 0.5:
		dbg_time = 0.0

	if Input.is_action_just_pressed("add_customer"):
		print("A PRESSED → add_customer() called")
		add_customer()

	if Input.is_action_just_pressed("send_next"):
		print("S PRESSED → send_next_to_barber() called")
		send_next_to_barber()

	if Input.is_action_just_pressed("finish_haircut"):
		print("F PRESSED → finish_haircut() called")
		finish_haircut()

	if game_mode == GameMode.AUTO:
		if barber_state != BarberState.CUTTING \
				and current_customer == null \
				and not waiting_customers.is_empty():
			send_next_to_barber()


# --- SEATS CONFIG ---------------------------------------------------


func update_active_seats() -> void:
	seat_count = clamp(seat_count, 1, all_seats.size())

	seats.clear()
	for i in range(all_seats.size()):
		var seat_node = all_seats[i]  # <-- no : Control
		var active := i < seat_count
		seat_node.visible = active
		if active:
			seats.append(seat_node)

	seat_occupants.resize(seats.size())
	for i in range(seat_occupants.size()):
		seat_occupants[i] = null
	waiting_customers.clear()

	seats_label.text = "Seats: %d" % seat_count
	print("Seat configuration updated. seat_count =", seat_count)


func _on_seats_minus_pressed() -> void:
	if not waiting_customers.is_empty() or current_customer != null:
		print("Cannot decrease seats while customers are present.")
		return

	if seat_count <= 1:
		return

	seat_count -= 1
	update_active_seats()


func _on_seats_plus_pressed() -> void:
	if not waiting_customers.is_empty() or current_customer != null:
		print("Cannot increase seats while customers are present.")
		return

	if seat_count >= all_seats.size():
		return

	seat_count += 1
	update_active_seats()


# --- VISUAL HELPERS -------------------------------------------------


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
		BarberState.IDLE:
			barber_sprite.color = Color(0.0, 0.7, 0.0)
			status_label.text = "Barber awake, waiting for customer"
		BarberState.CUTTING:
			barber_sprite.color = Color(0.8, 0.0, 0.0)
			status_label.text = "Barber cutting a customer"

			cutting_tween = create_tween().set_loops()
			cutting_tween.tween_property(barber_sprite, "scale", Vector2(1.2, 1.2), 0.2)
			cutting_tween.tween_property(barber_sprite, "scale", Vector2(1.0, 1.0), 0.2)


func move_customer(customer, from_pos: Vector2, to_pos: Vector2, duration := 0.5) -> void:
	if customer.has_method("face_direction"):
		var dir := to_pos - from_pos
		customer.face_direction(dir)

	customer.global_position = from_pos
	var tween := create_tween()
	tween.tween_property(customer, "global_position", to_pos, duration)



# --- LOGIC: CUSTOMERS & BARBER --------------------------------------


func add_customer() -> void:
	var free_index := -1
	for i in range(seats.size()):
		if seat_occupants[i] == null:
			free_index = i
			break

	if free_index == -1:
		print("No free seats. Customer leaves.")
		return

	var customer = CustomerScene.instantiate()  # <-- no : Control
	$UI.add_child(customer)

	var seat_pos: Vector2 = seats[free_index].global_position
	move_customer(customer, spawn_position, seat_pos, 0.6)

	seat_occupants[free_index] = customer
	waiting_customers.append(customer)
	customer.set_meta("seat_index", free_index)

	if current_customer == null:
		set_barber_state(BarberState.IDLE)

	print("New customer seated. Waiting:", waiting_customers.size())
	print("DEBUG: add_customer() finished")


func send_next_to_barber() -> void:
	if current_customer != null:
		print("Barber is busy.")
		return

	if waiting_customers.is_empty():
		print("No customers waiting.")
		return

	var customer = waiting_customers.pop_front()
	var idx: int = int(customer.get_meta("seat_index"))
	seat_occupants[idx] = null

	var start_pos: Vector2 = customer.global_position
	move_customer(customer, start_pos, barber_position, 0.6)
	current_customer = customer

	set_barber_state(BarberState.CUTTING)

	if game_mode == GameMode.AUTO:
		var t = randf_range(1.5, 3.5)
		haircut_timer.start(t)

	print("Customer moved to barber chair. Remaining waiting:", waiting_customers.size())
	print("DEBUG: send_next_to_barber() finished")


func finish_haircut() -> void:
	if current_customer == null:
		print("No customer at the barber chair.")
		return

	current_customer.queue_free()
	current_customer = null

	if waiting_customers.is_empty():
		set_barber_state(BarberState.SLEEPING)
	else:
		set_barber_state(BarberState.IDLE)

	print("Haircut finished. Barber idle.")
	print("DEBUG: finish_haircut() finished")


func _on_manual_button_pressed() -> void:
	game_mode = GameMode.MANUAL
	mode_panel.visible = false
	customer_timer.stop()
	haircut_timer.stop()
	print("Manual mode selected")


func _on_auto_button_pressed() -> void:
	game_mode = GameMode.AUTO
	mode_panel.visible = false
	print("Automatic mode selected")
	_schedule_next_customer()


func _schedule_next_customer() -> void:
	var wait = randf_range(1.0, 3.0)
	customer_timer.start(wait)


func _on_customer_timer_timeout() -> void:
	add_customer()
	_schedule_next_customer()


func _on_haircut_timer_timeout() -> void:
	finish_haircut()
