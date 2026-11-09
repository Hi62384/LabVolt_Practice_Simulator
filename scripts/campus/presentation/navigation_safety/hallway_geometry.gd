extends RefCounted
## Geometry contract for closing only the unsupported gaps between campus rooms.
## Door openings, stairs, and the east elevator entrance are deliberately excluded.

const WALL_COLOR := "c6cbd6"
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 0.16

# Each entry is [floor_index, z_min, z_max]. Existing room walls cover every
# other corridor-edge span. Keeping this list explicit makes layout changes
# fail review instead of silently placing a barrier across a real doorway.
const EDGE_GAPS := [
	[0, 10.0, 13.0],
	[0, 25.0, 27.0],
	[0, 39.0, 41.0],
	[0, 53.0, 54.0],
	[1, -4.0, -3.0],
	[1, 9.0, 13.0],
	[1, 25.0, 27.0],
	[1, 39.0, 40.0, 10.0],
	[1, 39.0, 41.0, 16.0],
	[1, 53.0, 54.0, 16.0],
]

const CORRIDOR_X_MIN := 10.0
const CORRIDOR_X_MAX := 16.0

static func edge_closures() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for gap in EDGE_GAPS:
		var y := float(gap[0]) * 5.0
		var z_min := float(gap[1])
		var z_max := float(gap[2])
		var edges: Array = [gap[3]] if gap.size() == 4 else [CORRIDOR_X_MIN, CORRIDOR_X_MAX]
		for x in edges:
			result.append({
				"floor": int(gap[0]),
				"position": Vector3(x, y + WALL_HEIGHT / 2.0, (z_min + z_max) / 2.0),
				"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, z_max - z_min),
				"z_min": z_min,
				"z_max": z_max,
			})
	return result

static func protected_walkable_bounds() -> Dictionary:
	return {
		"ground_corridor": AABB(Vector3(10.0, -0.25, -14.0), Vector3(6.0, 1.0, 82.0)),
		"upper_corridor": AABB(Vector3(10.0, 4.75, -4.0), Vector3(6.0, 1.0, 72.0)),
		"stairs": AABB(Vector3(10.0, -0.25, 50.0), Vector3(3.0, 5.5, 12.0)),
		"elevator_entrance": AABB(Vector3(15.75, -0.25, 56.0), Vector3(8.25, 5.5, 4.0)),
	}

