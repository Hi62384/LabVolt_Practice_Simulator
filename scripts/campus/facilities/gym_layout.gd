extends RefCounted
## Shared M105 transforms for station geometry, storage and replicated bar motion.
const ORIGIN := Vector3(0, 0, 33)
const BENCH := Vector3(4, 0, -2)
const PULLUP := Vector3(-5, 0, -2)
const DUMBBELLS := Vector3(1.6, 0, -3.4)
const PLATES := Vector3(-7.75, 0, 2.6)
const BELTS := Vector3(-8.25, 1.35, -3.1)
const BAR_RESTS := {
	"gym/benchpress": ORIGIN + BENCH + Vector3(0, 1.25, -.8),
	"gym/squat": ORIGIN + Vector3(-5, 1.35, 2.8),
	"gym/barbell_rack_2": ORIGIN + Vector3(-1.5, 1.35, 2.8),
}

static func cable(index: int) -> Vector3:
	return Vector3(7, 0, -3.6 + index * 6.0)
