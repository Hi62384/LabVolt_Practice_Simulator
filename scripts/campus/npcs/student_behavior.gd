extends RefCounted
## Deterministic, bounded local ambient-student simulation.
## Uses the immutable campus registry for authored doors and room bounds. It has
## no physics, navigation-server, multiplayer, or per-frame pathfinding work.

const TICK_SECONDS := 0.125
const WALK_SPEED := 1.15
const ARRIVAL_DISTANCE := 0.12
const MIN_WORK_SECONDS := 18.0
const MAX_WORK_SECONDS := 55.0
const MIN_WANDER_SECONDS := 8.0
const MAX_WANDER_SECONDS := 24.0

var registry: Object
var students: Array[Dictionary] = []
var _accumulator := 0.0
var _seed := 0x4c414256

func configure(source: Object) -> bool:
	if not is_instance_valid(source) or not source.has_method("directory") or not source.has_method("route_from_position"):
		return false
	registry = source
	return true

func set_population(count: int) -> void:
	count = clampi(count, 0, 24)
	while students.size() < count:
		students.append(_make_student(students.size()))
	while students.size() > count:
		students.pop_back()

func advance(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta) or not is_instance_valid(registry):
		return
	_accumulator = minf(_accumulator + delta, TICK_SECONDS * 4.0)
	while _accumulator >= TICK_SECONDS:
		_accumulator -= TICK_SECONDS
		for student in students:
			_tick(student, TICK_SECONDS)

func _make_student(index: int) -> Dictionary:
	var floor := index % 2
	var lane_x := 12.15 + float(index % 3) * 0.75
	var z := -1.0 + fposmod(float(index * 11), 46.0)
	var student := {
		"id": index,
		"position": Vector3(lane_x, float(floor) * 5.0, z),
		"state": "wander",
		"room_id": "",
		"path": PackedVector3Array(),
		"target": 0,
		"remaining": _range_for(index, 0, MIN_WANDER_SECONDS, MAX_WANDER_SECONDS),
		"cycle": 0,
		"moving": false,
	}
	_set_wander_path(student)
	return student

func _tick(student: Dictionary, delta: float) -> void:
	if str(student.state) == "working":
		student.remaining = maxf(0.0, float(student.remaining) - delta)
		student.moving = false
		if student.remaining <= 0.0:
			_begin_return(student)
		return
	if str(student.state) == "wander":
		student.remaining = maxf(0.0, float(student.remaining) - delta)
		if student.remaining <= 0.0:
			_begin_room_trip(student)
			return
	_move_path(student, delta)

func _move_path(student: Dictionary, delta: float) -> void:
	var path: PackedVector3Array = student.path
	if path.is_empty() or int(student.target) >= path.size():
		_arrived(student)
		return
	var target := path[int(student.target)]
	var position: Vector3 = student.position
	var distance := position.distance_to(target)
	if distance <= ARRIVAL_DISTANCE:
		student.position = target
		student.target = int(student.target) + 1
		student.moving = int(student.target) < path.size()
		if not student.moving:
			_arrived(student)
		return
	student.position = position.move_toward(target, WALK_SPEED * delta)
	student.moving = true

func _arrived(student: Dictionary) -> void:
	match str(student.state):
		"to_room":
			student.state = "working"
			student.remaining = _range_for(int(student.id), int(student.cycle) + 17, MIN_WORK_SECONDS, MAX_WORK_SECONDS)
			student.moving = false
		"to_hall":
			student.state = "wander"
			student.room_id = ""
			student.remaining = _range_for(int(student.id), int(student.cycle) + 31, MIN_WANDER_SECONDS, MAX_WANDER_SECONDS)
			_set_wander_path(student)
		_:
			_set_wander_path(student)

func _begin_room_trip(student: Dictionary) -> void:
	var choices: Array = []
	var floor := 1 if float(student.position.y) >= 4.5 else 0
	for room in registry.call("directory"):
		if int(room.get("floor", -1)) == floor and str(room.get("kind", "")) != "washroom":
			choices.append(room)
	if choices.is_empty():
		student.remaining = MIN_WANDER_SECONDS
		return
	var cycle := int(student.cycle) + 1
	student.cycle = cycle
	var room: Dictionary = choices[_mix(int(student.id), cycle) % choices.size()]
	var path: PackedVector3Array = registry.call("route_from_position", student.position, str(room.id))
	if path.size() < 3 or not _valid_path(path):
		student.remaining = MIN_WANDER_SECONDS
		return
	# End at a stable per-student work point inside the room, never in a wall.
	path[path.size() - 1] = _work_point(room, int(student.id), cycle)
	student.state = "to_room"
	student.room_id = str(room.id)
	student.path = path
	student.target = 1
	student.moving = true

func _begin_return(student: Dictionary) -> void:
	var room: Dictionary = registry.call("get_room", str(student.room_id))
	if room.is_empty():
		student.state = "wander"
		_set_wander_path(student)
		return
	# Explicit interior -> real door -> approach -> hall lane ordering.
	var approach := _point(room.get("approach", []))
	var door := _point(room.get("door", []))
	var hall := Vector3(12.15 + float(int(student.id) % 3) * 0.75, door.y, door.z)
	student.state = "to_hall"
	student.path = PackedVector3Array([student.position, door, approach, hall])
	student.target = 1
	student.moving = true

func _set_wander_path(student: Dictionary) -> void:
	var p: Vector3 = student.position
	var lane := 12.15 + float(int(student.id) % 3) * 0.75
	var forward := (_mix(int(student.id), int(student.cycle) + 7) & 1) == 0
	var low := -1.0
	var high := 47.0
	student.path = PackedVector3Array([p, Vector3(lane, p.y, high if forward else low), Vector3(lane, p.y, low if forward else high)])
	student.target = 1
	student.moving = true

func _work_point(room: Dictionary, id: int, cycle: int) -> Vector3:
	var low := _point(room.get("bounds_min", []))
	var high := _point(room.get("bounds_max", []))
	var inset_x := 2.2 + float(_mix(id, cycle) % 5) * 1.1
	var inset_z := 2.0 + float(_mix(id + 9, cycle) % 4) * 1.15
	return Vector3(lerpf(low.x, high.x, 0.25 if int(room.door[0]) > float(room.center[0]) else 0.75) + (inset_x - 4.4) * 0.2, float(room.floor) * 5.0, clampf(low.z + inset_z, low.z + 1.2, high.z - 1.2))

func _valid_path(path: PackedVector3Array) -> bool:
	if path.size() > 20:
		return false
	for point in path:
		if not point.is_finite():
			return false
	return true

func _point(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _range_for(id: int, cycle: int, low: float, high: float) -> float:
	return lerpf(low, high, float(_mix(id, cycle) % 1000) / 999.0)

func _mix(id: int, cycle: int) -> int:
	var value := int(_seed) ^ (id * 1103515245) ^ (cycle * 12345)
	value = ((value >> 16) ^ value) * 0x45d9f3b
	return absi((value >> 16) ^ value)

