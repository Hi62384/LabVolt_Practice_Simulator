extends RefCounted
## Pure host-owned state. Floor IDs are the existing registry's zero-based floors.
const FLOORS := [0, 1]
const DOOR_SECONDS := 0.8
const TRAVEL_SECONDS := 2.2
const DWELL_SECONDS := 1.2
var floor_id := 0
var destination := 0
var phase := "open"
var elapsed := 0.0
var queue: Array[int] = []
var riders: Dictionary = {}
var revision := 0

func request(stop: int, cabin: bool) -> bool:
	if stop not in FLOORS: return false
	if cabin and phase != "open": return false
	if stop == floor_id and phase in ["open", "opening"]: return true
	if stop == destination and phase == "moving": return true
	if not queue.has(stop):
		queue.append(stop)
		revision += 1
	return true

func advance(delta: float, blocked: bool, occupants: Dictionary, eligible: bool) -> String:
	elapsed += maxf(delta, 0.0)
	match phase:
		"open":
			if not queue.is_empty() and elapsed >= DWELL_SECONDS:
				if queue[0] == floor_id:
					queue.pop_front(); revision += 1; elapsed = 0.0
				elif not blocked and eligible: _phase("closing")
		"closing":
			if blocked or not eligible:
				_phase("opening")
			elif elapsed >= DOOR_SECONDS:
				# Snapshot the entire cabin at the last safe instant, never the requester only.
				riders = occupants.duplicate(true)
				destination = queue.pop_front()
				_phase("moving")
				return "depart"
		"moving":
			if elapsed >= TRAVEL_SECONDS:
				floor_id = destination
				_phase("opening")
				return "arrive"
		"opening":
			if elapsed >= DOOR_SECONDS:
				riders.clear()
				_phase("open")
		"closed":
			if not queue.is_empty():
				destination = queue.pop_front()
				if destination == floor_id: _phase("opening")
				else: _phase("moving")
	return ""

func _phase(value: String) -> void:
	phase = value; elapsed = 0.0; revision += 1

func forget(peer: int) -> void:
	if riders.erase(peer): revision += 1

func snapshot() -> Dictionary:
	return {"floor":floor_id, "destination":destination, "phase":phase,
		"elapsed":elapsed, "queue":queue.duplicate(), "riders":riders.duplicate(true), "revision":revision}
