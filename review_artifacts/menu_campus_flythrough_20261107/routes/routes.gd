extends RefCounted
## Authored from the existing campus registry and shell geometry.
## Positions are world-space metres; this module changes no campus content.

static func _curve(points: PackedVector3Array) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.12
	for i in points.size():
		var previous: Vector3 = points[maxi(0, i - 1)]
		var following: Vector3 = points[mini(points.size() - 1, i + 1)]
		var tangent: Vector3 = (following - previous) * 0.12
		curve.add_point(points[i], -tangent if i > 0 else Vector3.ZERO, tangent if i < points.size() - 1 else Vector3.ZERO)
	return curve

static func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append({
		"id": "entrance_reveal",
		"location": "exterior",
		"path": _curve(PackedVector3Array([Vector3(12.1, 1.85, -22), Vector3(12.7, 1.88, -20), Vector3(13.3, 1.9, -17.5), Vector3(13, 1.9, -14)])),
		"look": PackedVector3Array([Vector3(13, 2.5, -11.5), Vector3(13, 2.4, -11.5), Vector3(13, 2.2, -9), Vector3(13, 2, -7)]),
		"speed": 0.62,
		"transition": "crossfade",
		"weight": 1.4,
		"rooms": PackedStringArray([]),
	})
	result.append({
		"id": "courtyard_landscape",
		"location": "exterior",
		"path": _curve(PackedVector3Array([Vector3(12, 1.9, -14.5), Vector3(12.6, 1.9, -17), Vector3(13.5, 1.95, -19.5), Vector3(14.3, 1.9, -22)])),
		"look": PackedVector3Array([Vector3(5, 1.6, -16), Vector3(4, 2.1, -17), Vector3(13, 3, -11), Vector3(21, 2.1, -17)]),
		"speed": 0.57,
		"transition": "crossfade",
		"weight": 1.2,
		"rooms": PackedStringArray([]),
	})
	result.append({
		"id": "lobby_entry",
		"location": "circulation",
		"path": _curve(PackedVector3Array([Vector3(13, 1.85, -17), Vector3(13.1, 1.85, -14.5), Vector3(13.15, 1.85, -11.5), Vector3(13, 1.85, -8.5), Vector3(12.9, 1.85, -5.5)])),
		"look": PackedVector3Array([Vector3(13, 2.6, -11), Vector3(13, 2.2, -9), Vector3(13, 2, -6), Vector3(13, 2, -3), Vector3(13, 2, 2)]),
		"speed": 0.65,
		"transition": "crossfade",
		"weight": 1.4,
		"rooms": PackedStringArray([]),
	})
	result.append({
		"id": "ground_hall_south",
		"location": "circulation",
		"path": _curve(PackedVector3Array([Vector3(13, 1.85, -2), Vector3(13.28, 1.85, 1), Vector3(12.82, 1.85, 3), Vector3(13, 1.85, 6), Vector3(13.28, 1.85, 9), Vector3(12.82, 1.85, 12), Vector3(13, 1.85, 16), Vector3(13.28, 1.85, 19), Vector3(12.82, 1.85, 22)])),
		"look": PackedVector3Array([Vector3(8, 1.8, 3), Vector3(8, 1.8, 3), Vector3(8, 1.8, 3), Vector3(18, 1.8, 3), Vector3(18, 1.8, 3), Vector3(8, 1.8, 19), Vector3(8, 1.8, 19), Vector3(18, 1.8, 19), Vector3(18, 1.8, 19)]),
		"speed": 0.72,
		"transition": "crossfade",
		"weight": 1.7,
		"rooms": PackedStringArray(["ac_lab", "shop", "dc_lab", "cafeteria"]),
	})
	result.append({
		"id": "ground_hall_north",
		"location": "circulation",
		"path": _curve(PackedVector3Array([Vector3(13, 1.85, 25), Vector3(13.28, 1.85, 29), Vector3(12.82, 1.85, 33), Vector3(13, 1.85, 37), Vector3(13.28, 1.85, 41), Vector3(12.82, 1.85, 45), Vector3(13, 1.85, 47), Vector3(13.28, 1.85, 49)])),
		"look": PackedVector3Array([Vector3(18, 1.8, 19), Vector3(8, 1.8, 33), Vector3(8, 1.8, 33), Vector3(18, 1.8, 33), Vector3(18, 1.8, 33), Vector3(18, 1.8, 47), Vector3(18, 1.8, 47), Vector3(18, 1.8, 47)]),
		"speed": 0.72,
		"transition": "crossfade",
		"weight": 1.7,
		"rooms": PackedStringArray(["gym", "tim_hortons", "subway"]),
	})
	result.append({
		"id": "upper_hall_south",
		"location": "circulation",
		"path": _curve(PackedVector3Array([Vector3(13, 6.85, -2), Vector3(13.28, 6.85, 1), Vector3(12.82, 6.85, 3), Vector3(13, 6.85, 6), Vector3(13.28, 6.85, 10), Vector3(12.82, 6.85, 14), Vector3(13, 6.85, 19), Vector3(13.28, 6.85, 23)])),
		"look": PackedVector3Array([Vector3(8, 6.8, 3), Vector3(8, 6.8, 3), Vector3(18, 6.8, 3), Vector3(18, 6.8, 3), Vector3(8, 6.8, 19), Vector3(8, 6.8, 19), Vector3(18, 6.8, 19), Vector3(18, 6.8, 19)]),
		"speed": 0.72,
		"transition": "crossfade",
		"weight": 1.7,
		"rooms": PackedStringArray(["elm253_lecture", "ety155_lecture", "computer", "library"]),
	})
	result.append({
		"id": "upper_hall_north",
		"location": "circulation",
		"path": _curve(PackedVector3Array([Vector3(13, 6.85, 25), Vector3(13.28, 6.85, 28), Vector3(12.82, 6.85, 31), Vector3(13, 6.85, 33), Vector3(13.28, 6.85, 36), Vector3(12.82, 6.85, 39), Vector3(13, 6.85, 43), Vector3(13.28, 6.85, 47)])),
		"look": PackedVector3Array([Vector3(18, 6.8, 19), Vector3(8, 6.8, 33), Vector3(8, 6.8, 33), Vector3(8, 6.8, 33), Vector3(8, 6.8, 33), Vector3(18, 6.8, 47), Vector3(18, 6.8, 47), Vector3(18, 6.8, 47)]),
		"speed": 0.72,
		"transition": "crossfade",
		"weight": 1.7,
		"rooms": PackedStringArray(["study", "circuit_studio"]),
	})
	result.append({
		"id": "ac_lab_door_view",
		"location": "ac_lab",
		"path": _curve(PackedVector3Array([Vector3(13, 1.83, 0.5), Vector3(12.82, 1.86, 2.2), Vector3(12.82, 1.88, 3.8), Vector3(13, 1.83, 5.5)])),
		"look": PackedVector3Array([Vector3(6.5, 1.65, 2.55), Vector3(5.5, 1.7, 3), Vector3(5, 1.7, 3), Vector3(6.5, 1.65, 3.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["ac_lab"]),
	})
	result.append({
		"id": "dc_lab_door_view",
		"location": "dc_lab",
		"path": _curve(PackedVector3Array([Vector3(13, 1.83, 16.5), Vector3(12.82, 1.86, 18.2), Vector3(12.82, 1.88, 19.8), Vector3(13, 1.83, 21.5)])),
		"look": PackedVector3Array([Vector3(6.5, 1.65, 18.55), Vector3(5.5, 1.7, 19), Vector3(5, 1.7, 19), Vector3(6.5, 1.65, 19.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["dc_lab"]),
	})
	result.append({
		"id": "shop_door_view",
		"location": "shop",
		"path": _curve(PackedVector3Array([Vector3(13, 1.83, 0.5), Vector3(13.18, 1.86, 2.2), Vector3(13.18, 1.88, 3.8), Vector3(13, 1.83, 5.5)])),
		"look": PackedVector3Array([Vector3(19.5, 1.65, 2.55), Vector3(20.5, 1.7, 3), Vector3(21, 1.7, 3), Vector3(19.5, 1.65, 3.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["shop"]),
	})
	result.append({
		"id": "gym_door_view",
		"location": "gym",
		"path": _curve(PackedVector3Array([Vector3(13, 1.83, 30.5), Vector3(12.82, 1.86, 32.2), Vector3(12.82, 1.88, 33.8), Vector3(13, 1.83, 35.5)])),
		"look": PackedVector3Array([Vector3(6.5, 1.65, 32.55), Vector3(5.5, 1.7, 33), Vector3(5, 1.7, 33), Vector3(6.5, 1.65, 33.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["gym"]),
	})
	result.append({
		"id": "cafeteria_door_view",
		"location": "cafeteria",
		"path": _curve(PackedVector3Array([Vector3(13, 1.83, 16.5), Vector3(13.18, 1.86, 18.2), Vector3(13.18, 1.88, 19.8), Vector3(13, 1.83, 21.5)])),
		"look": PackedVector3Array([Vector3(19.5, 1.65, 18.55), Vector3(20.5, 1.7, 19), Vector3(21, 1.7, 19), Vector3(19.5, 1.65, 19.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["cafeteria"]),
	})
	result.append({
		"id": "tim_hortons_door_view",
		"location": "tim_hortons",
		"path": _curve(PackedVector3Array([Vector3(13, 1.83, 30.5), Vector3(13.18, 1.86, 32.2), Vector3(13.18, 1.88, 33.8), Vector3(13, 1.83, 35.5)])),
		"look": PackedVector3Array([Vector3(19.5, 1.65, 32.55), Vector3(20.5, 1.7, 33), Vector3(21, 1.7, 33), Vector3(19.5, 1.65, 33.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["tim_hortons"]),
	})
	result.append({
		"id": "subway_door_view",
		"location": "subway",
		"path": _curve(PackedVector3Array([Vector3(13, 1.83, 44.5), Vector3(13.18, 1.86, 46.2), Vector3(13.18, 1.88, 47.8), Vector3(13, 1.83, 49.5)])),
		"look": PackedVector3Array([Vector3(19.5, 1.65, 46.55), Vector3(20.5, 1.7, 47), Vector3(21, 1.7, 47), Vector3(19.5, 1.65, 47.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["subway"]),
	})
	result.append({
		"id": "elm253_lecture_door_view",
		"location": "elm253_lecture",
		"path": _curve(PackedVector3Array([Vector3(13, 6.83, 0.5), Vector3(12.82, 6.86, 2.2), Vector3(12.82, 6.88, 3.8), Vector3(13, 6.83, 5.5)])),
		"look": PackedVector3Array([Vector3(6.5, 6.65, 2.55), Vector3(5.5, 6.7, 3), Vector3(5, 6.7, 3), Vector3(6.5, 6.65, 3.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["elm253_lecture"]),
	})
	result.append({
		"id": "ety155_lecture_door_view",
		"location": "ety155_lecture",
		"path": _curve(PackedVector3Array([Vector3(13, 6.83, 0.5), Vector3(13.18, 6.86, 2.2), Vector3(13.18, 6.88, 3.8), Vector3(13, 6.83, 5.5)])),
		"look": PackedVector3Array([Vector3(19.5, 6.65, 2.55), Vector3(20.5, 6.7, 3), Vector3(21, 6.7, 3), Vector3(19.5, 6.65, 3.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["ety155_lecture"]),
	})
	result.append({
		"id": "computer_door_view",
		"location": "computer",
		"path": _curve(PackedVector3Array([Vector3(13, 6.83, 16.5), Vector3(12.82, 6.86, 18.2), Vector3(12.82, 6.88, 19.8), Vector3(13, 6.83, 21.5)])),
		"look": PackedVector3Array([Vector3(6.5, 6.65, 18.55), Vector3(5.5, 6.7, 19), Vector3(5, 6.7, 19), Vector3(6.5, 6.65, 19.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["computer"]),
	})
	result.append({
		"id": "library_door_view",
		"location": "library",
		"path": _curve(PackedVector3Array([Vector3(13, 6.83, 16.5), Vector3(13.18, 6.86, 18.2), Vector3(13.18, 6.88, 19.8), Vector3(13, 6.83, 21.5)])),
		"look": PackedVector3Array([Vector3(19.5, 6.65, 18.55), Vector3(20.5, 6.7, 19), Vector3(21, 6.7, 19), Vector3(19.5, 6.65, 19.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["library"]),
	})
	result.append({
		"id": "study_door_view",
		"location": "study",
		"path": _curve(PackedVector3Array([Vector3(13, 6.83, 30.5), Vector3(12.82, 6.86, 32.2), Vector3(12.82, 6.88, 33.8), Vector3(13, 6.83, 35.5)])),
		"look": PackedVector3Array([Vector3(6.5, 6.65, 32.55), Vector3(5.5, 6.7, 33), Vector3(5, 6.7, 33), Vector3(6.5, 6.65, 33.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["study"]),
	})
	result.append({
		"id": "circuit_studio_door_view",
		"location": "circuit_studio",
		"path": _curve(PackedVector3Array([Vector3(13, 6.83, 44.5), Vector3(13.18, 6.86, 46.2), Vector3(13.18, 6.88, 47.8), Vector3(13, 6.83, 49.5)])),
		"look": PackedVector3Array([Vector3(19.5, 6.65, 46.55), Vector3(20.5, 6.7, 47), Vector3(21, 6.7, 47), Vector3(19.5, 6.65, 47.45)]),
		"speed": 0.43,
		"transition": "crossfade",
		"weight": 0.9,
		"rooms": PackedStringArray(["circuit_studio"]),
	})
	result.append({
		"id": "elm253_lecture_interior",
		"location": "elm253_lecture",
		"path": _curve(PackedVector3Array([Vector3(13, 6.82, 3), Vector3(11, 6.84, 3), Vector3(8.25, 6.85, 3.12), Vector3(6.5, 6.86, 3.35), Vector3(6.5, 6.86, 3.65)])),
		"look": PackedVector3Array([Vector3(0, 6.7, 2), Vector3(0, 6.7, 2), Vector3(0, 6.6, 1.6), Vector3(0, 6.5, 1.4), Vector3(0, 6.5, 1.4)]),
		"speed": 0.5,
		"transition": "crossfade",
		"weight": 1.15,
		"rooms": PackedStringArray(["elm253_lecture"]),
	})
	result.append({
		"id": "ety155_lecture_interior",
		"location": "ety155_lecture",
		"path": _curve(PackedVector3Array([Vector3(13, 6.82, 3), Vector3(15, 6.84, 3), Vector3(17.75, 6.85, 3.12), Vector3(19.5, 6.86, 3.35), Vector3(19.5, 6.86, 3.65)])),
		"look": PackedVector3Array([Vector3(26, 6.7, 2), Vector3(26, 6.7, 2), Vector3(26, 6.6, 1.6), Vector3(26, 6.5, 1.4), Vector3(26, 6.5, 1.4)]),
		"speed": 0.5,
		"transition": "crossfade",
		"weight": 1.15,
		"rooms": PackedStringArray(["ety155_lecture"]),
	})
	result.append({
		"id": "computer_interior",
		"location": "computer",
		"path": _curve(PackedVector3Array([Vector3(13, 6.82, 19), Vector3(11, 6.84, 19), Vector3(9.4, 6.85, 19.12), Vector3(8.8, 6.86, 19.35), Vector3(8.8, 6.86, 19.65)])),
		"look": PackedVector3Array([Vector3(0, 6.7, 18), Vector3(0, 6.7, 18), Vector3(0, 6.6, 17.6), Vector3(0, 6.5, 17.4), Vector3(0, 6.5, 17.4)]),
		"speed": 0.4,
		"transition": "crossfade",
		"weight": 1.15,
		"rooms": PackedStringArray(["computer"]),
	})
	result.append({
		"id": "library_interior",
		"location": "library",
		"path": _curve(PackedVector3Array([Vector3(13, 6.82, 19), Vector3(15, 6.84, 19), Vector3(17.4, 6.85, 19.12), Vector3(18.8, 6.86, 19.35), Vector3(18.8, 6.86, 19.65)])),
		"look": PackedVector3Array([Vector3(26, 6.7, 18), Vector3(26, 6.7, 18), Vector3(26, 6.6, 17.6), Vector3(26, 6.5, 17.4), Vector3(26, 6.5, 17.4)]),
		"speed": 0.5,
		"transition": "crossfade",
		"weight": 1.15,
		"rooms": PackedStringArray(["library"]),
	})
	result.append({
		"id": "study_interior",
		"location": "study",
		"path": _curve(PackedVector3Array([Vector3(13, 6.82, 33), Vector3(11, 6.84, 33), Vector3(8.6, 6.85, 33.12), Vector3(7.2, 6.86, 33.35), Vector3(7.2, 6.86, 33.65)])),
		"look": PackedVector3Array([Vector3(0, 6.7, 32), Vector3(0, 6.7, 32), Vector3(0, 6.6, 31.6), Vector3(0, 6.5, 31.4), Vector3(0, 6.5, 31.4)]),
		"speed": 0.5,
		"transition": "crossfade",
		"weight": 1.15,
		"rooms": PackedStringArray(["study"]),
	})
	result.append({
		"id": "cafeteria_interior",
		"location": "cafeteria",
		"path": _curve(PackedVector3Array([Vector3(13, 1.82, 19), Vector3(15, 1.84, 19), Vector3(17.1, 1.85, 19.12), Vector3(18.2, 1.86, 19.35), Vector3(18.2, 1.86, 19.65)])),
		"look": PackedVector3Array([Vector3(26, 1.7, 18), Vector3(26, 1.7, 18), Vector3(26, 1.6, 17.6), Vector3(26, 1.5, 17.4), Vector3(26, 1.5, 17.4)]),
		"speed": 0.5,
		"transition": "crossfade",
		"weight": 1.15,
		"rooms": PackedStringArray(["cafeteria"]),
	})
	result.append({
		"id": "circuit_studio_interior",
		"location": "circuit_studio",
		"path": _curve(PackedVector3Array([Vector3(13, 6.82, 47), Vector3(15, 6.84, 47), Vector3(17.9, 6.85, 47.12), Vector3(19.8, 6.86, 47.35), Vector3(19.8, 6.86, 47.65)])),
		"look": PackedVector3Array([Vector3(26, 6.7, 46), Vector3(26, 6.7, 46), Vector3(26, 6.6, 45.6), Vector3(26, 6.5, 45.4), Vector3(26, 6.5, 45.4)]),
		"speed": 0.5,
		"transition": "crossfade",
		"weight": 1.15,
		"rooms": PackedStringArray(["circuit_studio"]),
	})
	result.append({
		"id": "dorm_hall_preview",
		"location": "circulation",
		"path": _curve(PackedVector3Array([Vector3(13, 1.82, 69.8), Vector3(13.2, 1.84, 71.4), Vector3(13, 1.86, 73.5), Vector3(12.8, 1.84, 75.5)])),
		"look": PackedVector3Array([Vector3(13, 1.7, 73.75), Vector3(10, 1.8, 73.75), Vector3(16, 1.8, 73.75), Vector3(13, 1.8, 78)]),
		"speed": 0.5,
		"transition": "crossfade",
		"weight": 0.85,
		"rooms": PackedStringArray([]),
	})
	return result
