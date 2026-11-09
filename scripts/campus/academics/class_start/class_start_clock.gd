extends RefCounted
## Host-owned monotonic countdown. Callers supply Time.get_ticks_usec(); clients receive
## only a snapshot of remaining seconds, never a deadline they can advance.
const WAIT_USEC := 120000000
var session_id := ""
var deadline_usec := -1
var started := false
var arrivals := {} # authenticated profile -> bool late, immutable within a session

func arm(id: String, now_usec: int) -> bool:
	if id.is_empty() or now_usec < 0 or (session_id == id and deadline_usec >= 0):return false
	session_id=id
	deadline_usec=now_usec+WAIT_USEC
	started=false
	arrivals.clear()
	return true

func cancel() -> void:
	session_id=""
	deadline_usec=-1
	started=false
	arrivals.clear()

func restore(id: String, seconds_left: float, now_usec: int, first_arrivals: Dictionary) -> bool:
	if id.is_empty() or now_usec < 0 or not is_finite(seconds_left):return false
	session_id=id
	deadline_usec=now_usec+int(maxf(0.0,seconds_left)*1000000.0)
	started=false
	arrivals=first_arrivals.duplicate(true)
	return true

func remaining(now_usec: int) -> float:
	if deadline_usec < 0 or started:return 0.0
	return float(maxi(0,deadline_usec-now_usec))/1000000.0

func due(now_usec: int) -> bool:
	return deadline_usec >= 0 and not started and now_usec >= deadline_usec

func begin_if_due(now_usec: int) -> bool:
	if not due(now_usec):return false
	started=true
	return true

func arrive(profile: String, now_usec: int) -> Dictionary:
	if profile.is_empty() or deadline_usec < 0:return {"ok":false}
	if not arrivals.has(profile):arrivals[profile]=now_usec >= deadline_usec
	return {"ok":true,"late":bool(arrivals[profile])}

func snapshot(now_usec: int) -> Dictionary:
	return {"session_id":session_id,"remaining":remaining(now_usec),"started":started}
