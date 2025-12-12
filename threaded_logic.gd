extends Node
class_name ThreadedLogic

signal barber_started(customer_id: int)
signal barber_finished(customer_id: int)
signal stats_updated(waiting_count: int, free_seats: int)

@export var num_seats: int = 4              # waiting chairs (not barber chair)
@export var haircut_time_sec: float = 2.0   # base haircut duration
var logger: Callable = func(msg: String) -> void:
	print(msg)
	
var _running: bool = false
var _thread: Thread

var _mutex: Mutex = Mutex.new()
var _customers_sem: Semaphore = Semaphore.new()

var _waiting_queue: Array[int] = []  # logical queue of customer ids
var _next_customer_id: int = 0
var _free_seats: int = 0             # free waiting seats

# events pushed from thread, consumed on main thread
var _events: Array = []
var _events_mutex: Mutex = Mutex.new()

# Random Number Generator for the thread
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_free_seats = num_seats
	_running = true

	_rng.randomize()

	_thread = Thread.new()
	_thread.start(Callable(self, "_barber_loop"))
	logger.call("THREAD: barber thread started")

	emit_signal("stats_updated", 0, _free_seats)



func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	# MAIN THREAD: flush events from worker
	_events_mutex.lock()
	var events := _events.duplicate()
	_events.clear()
	_events_mutex.unlock()

	for e in events:
		match e["type"]:
			"barber_started":
				emit_signal("barber_started", e["id"])
			"barber_finished":
				emit_signal("barber_finished", e["id"])
			"stats":
				emit_signal("stats_updated", e["waiting"], e["free"])


func stop() -> void:
	if not _running:
		return
	_running = false
	_customers_sem.post()  # wake barber so thread can exit
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func set_seat_count(new_count: int) -> void:
	_mutex.lock()
	num_seats = max(1, new_count)
	_free_seats = max(0, num_seats - _waiting_queue.size())
	var waiting := _waiting_queue.size()
	var free := _free_seats
	_mutex.unlock()
	emit_signal("stats_updated", waiting, free)


func request_seat() -> int:
	var customer_id: int = -1

	_mutex.lock()
	logger.call("MUTEX: lock in request_seat()")
	if _free_seats > 0:
		_free_seats -= 1
		_next_customer_id += 1
		customer_id = _next_customer_id
		_waiting_queue.append(customer_id)
		var waiting := _waiting_queue.size()
		var free := _free_seats
		_mutex.unlock()
		logger.call("MUTEX: unlock in request_seat() waiting=%d free=%d" % [waiting, free])

		emit_signal("stats_updated", waiting, free)
		_customers_sem.post()
		logger.call("SEMAPHORE: post (customer arrived)")
		return customer_id
	else:
		_mutex.unlock()
		logger.call("MUTEX: unlock in request_seat() queue full")
		return -1



# ------------ worker thread ----------------------------------------

func _push_event(e: Dictionary) -> void:
	_events_mutex.lock()
	_events.append(e)
	_events_mutex.unlock()


func _barber_loop(_userdata: Variant = null) -> void:
	while _running:
		logger.call("SEMAPHORE: barber waiting on customers_sem")
		_customers_sem.wait()
		logger.call("SEMAPHORE: barber woke up from customers_sem")

		if not _running:
			break

		var cust_id: int = -1
		var waiting: int = 0
		var free: int = 0

		_mutex.lock()
		logger.call("MUTEX: lock in _barber_loop()")
		if _waiting_queue.size() > 0:
			cust_id = _waiting_queue.pop_front()
			_free_seats = min(num_seats, _free_seats + 1)
			waiting = _waiting_queue.size()
			free = _free_seats
		_mutex.unlock()
		logger.call("MUTEX: unlock in _barber_loop() picked=%d waiting=%d free=%d" % [cust_id, waiting, free])

		if cust_id == -1:
			continue

		_push_event({
			"type": "barber_started",
			"id": cust_id,
		})
		logger.call("EVENT: barber_started id=%d" % cust_id)
		_push_event({
			"type": "stats",
			"waiting": waiting,
			"free": free,
		})

		var random_factor = _rng.randf_range(0.5, 2.0)
		var actual_cut_time = haircut_time_sec * random_factor
		logger.call("SLEEP: haircut for %f sec" % actual_cut_time)

		var total_ms: int = int(actual_cut_time * 1000.0)
		var step_ms: int = 100
		var elapsed: int = 0

		while elapsed < total_ms:
			if not _running:
				break
			var to_sleep = min(step_ms, total_ms - elapsed)
			OS.delay_msec(to_sleep)
			elapsed += to_sleep

		if not _running:
			break

		_push_event({
			"type": "barber_finished",
			"id": cust_id,
		})
		logger.call("EVENT: barber_finished id=%d" % cust_id)
