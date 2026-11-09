extends RefCounted
## Local movement-only recovery state. It never changes inventory, rewards, course,
## facility, or session state; the owning peer's normal pose stream replicates it.

const VOID_Y := -8.0
const GROUND_Y_MIN := -0.3
const GROUND_Y_MAX := 0.6
const UPPER_Y_MIN := 4.7
const UPPER_Y_MAX := 5.6

var spawn_position := Vector3(13.0, 0.05, -18.0)
var last_safe_position := spawn_position
var has_safe_position := false

func _init(spawn: Vector3 = Vector3(13.0, 0.05, -18.0)) -> void:
	spawn_position = spawn
	last_safe_position = spawn

func observe_grounded(point: Vector3) -> void:
	if is_known_walkable(point):
		last_safe_position = point
		has_safe_position = true

func needs_recovery(point: Vector3) -> bool:
	return point.y < VOID_Y

func recovery_position() -> Vector3:
	return last_safe_position if has_safe_position else spawn_position

static func is_known_walkable(point: Vector3) -> bool:
	var in_site := point.x >= -10.0 and point.x <= 36.0 and point.z >= -25.0 and point.z <= 68.0
	if not in_site:
		return false
	if point.y >= GROUND_Y_MIN and point.y <= GROUND_Y_MAX:
		return true
	if point.y >= UPPER_Y_MIN and point.y <= UPPER_Y_MAX:
		return point.z >= -4.0
	# The only intended transition between floor elevations is the north stair.
	return point.x >= 10.0 and point.x <= 13.0 and point.z >= 50.0 and point.z <= 62.0 and point.y > GROUND_Y_MAX and point.y < UPPER_Y_MIN

