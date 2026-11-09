class_name DormPlacementRules
extends RefCounted

## Pure host-side validation. Coordinates are local to the furnished room centre.
## The entrance is at x=+/-3.5, z=0. Nothing in this class grants ownership.
const ROOM_HALF := Vector2(3.5, 5.75)
const MARGIN := 0.18
const WALK_RADIUS := 0.42
const GRID := 0.25
const MAX_PLACED := 64
const FOOTPRINTS := {
	"bed":Vector2(1.2, 2.15), "bedside":Vector2(0.55, 0.52),
	"wardrobe":Vector2(1.35, 1.0), "study_desk":Vector2(2.35, 1.1),
	"study_chair":Vector2(0.55, 0.55), "storage_cabinet":Vector2(1.0, 0.58),
	"shelf":Vector2(1.6, 0.38), "rug":Vector2(1.7, 2.1),
	"plant":Vector2(0.5, 0.5), "bedside_lamp":Vector2(0.3, 0.3),
	"desk_lamp":Vector2(0.3, 0.3), "desk_laptop":Vector2(0.42, 0.3),
	"display":Vector2(0.35, 0.35), "poster":Vector2(0.08, 0.8)
}
const NON_SOLID := ["rug", "poster"]
const ON_SURFACE := ["bedside_lamp", "desk_lamp", "desk_laptop", "display"]

static func footprint(item: Dictionary) -> Rect2:
	var size: Vector2 = FOOTPRINTS.get(str(item.get("kind", "")), Vector2.ZERO)
	var rotation := int(item.get("rotation", 0))
	if rotation % 2 != 0: size = Vector2(size.y, size.x)
	var point := Vector2(float(item.get("x", 0)), float(item.get("z", 0)))
	return Rect2(point-size*0.5, size)

static func validate(items: Array, side: String) -> String:
	if side not in ["west", "east"]: return "invalid_room_side"
	if items.size() > MAX_PLACED: return "too_many_items"
	var identifiers := {}
	var solids: Array[Rect2] = []
	for value in items:
		if not value is Dictionary: return "invalid_item"
		var item: Dictionary = value
		var kind := str(item.get("kind", ""))
		var identifier := str(item.get("id", ""))
		if not FOOTPRINTS.has(kind) or identifier.is_empty() or identifier.length() > 96 or identifiers.has(identifier): return "invalid_item"
		identifiers[identifier] = true
		var rotation: Variant = item.get("rotation")
		# Profile JSON reloads integers as floats. Accept only the four exact quarter turns.
		if not _finite_number(rotation) or float(rotation) not in [0.0, 1.0, 2.0, 3.0]: return "invalid_rotation"
		if not _finite_number(item.get("x")) or not _finite_number(item.get("z")): return "invalid_position"
		var rect := footprint(item)
		if rect.position.x < -ROOM_HALF.x + MARGIN or rect.end.x > ROOM_HALF.x - MARGIN or rect.position.y < -ROOM_HALF.y + MARGIN or rect.end.y > ROOM_HALF.y - MARGIN: return "outside_room"
		if kind in ON_SURFACE: continue # Surface attachment is checked by the owner catalog adapter.
		if kind in NON_SOLID: continue
		# Door sweep includes the leaf and an avatar's standing clearance.
		var door_x := -ROOM_HALF.x if side == "west" else ROOM_HALF.x
		var door := Rect2(Vector2(door_x - 1.05, -1.1), Vector2(2.1, 2.2))
		if rect.intersects(door): return "door_blocked"
		var entrance_path := Rect2(Vector2(-2.6 if side == "west" else 0.0, -0.75), Vector2(2.6, 1.5))
		if rect.intersects(entrance_path): return "entrance_blocked"
		for other in solids:
			if rect.intersects(other): return "overlap"
		solids.append(rect)
	if not _walkable(solids, side): return "entrance_blocked"
	return ""

static func _walkable(solids: Array[Rect2], side: String) -> bool:
	# Check a full avatar footprint along a route from the entrance to the room
	# centre and to the back half. This catches long barriers and traps.
	var start := Vector2(-2.65 if side == "west" else 2.65, 0.0)
	var goals := [Vector2.ZERO, Vector2(0.0, -3.0), Vector2(0.0, 3.0)]
	var queue := [start]
	var visited := {_grid_key(start):true}
	var reached := {}
	while not queue.is_empty():
		var point: Vector2 = queue.pop_front()
		for index in goals.size():
			if point.distance_to(goals[index]) < 0.37: reached[index] = true
		if reached.size() == goals.size(): return true
		for step in [Vector2(GRID, 0), Vector2(-GRID, 0), Vector2(0, GRID), Vector2(0, -GRID)]:
			var next: Vector2 = point + step
			var key := _grid_key(next)
			if visited.has(key) or absf(next.x) > ROOM_HALF.x - WALK_RADIUS or absf(next.y) > ROOM_HALF.y - WALK_RADIUS: continue
			var avatar := Rect2(next-Vector2.ONE*WALK_RADIUS, Vector2.ONE*WALK_RADIUS*2.0)
			var blocked := false
			for solid in solids:
				if avatar.intersects(solid): blocked = true; break
			if not blocked: visited[key] = true; queue.append(next)
	return false

static func _grid_key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / GRID), roundi(point.y / GRID))

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
