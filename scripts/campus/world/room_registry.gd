extends RefCounted
## Single immutable source for signs, navigation, schedules and room slips.
const DATA_PATH := "res://assets/campus/world/room_registry.json"
var data: Dictionary
var rooms: Dictionary = {}

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	for room in data.rooms:
		rooms[str(room.id)] = room

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func get_room(id: String) -> Dictionary:
	return rooms.get(id, {}).duplicate(true)

func course_room(course: String, kind: String) -> Dictionary:
	return get_room(str(data.course_rooms.get(course, {}).get(kind, "")))

func search(query: String) -> Array:
	var result: Array = []
	var key := query.strip_edges().to_lower()
	for room in rooms.values():
		if key.is_empty() or (str(room.number)+" "+str(room.title)+" "+str(room.kind)).to_lower().contains(key):
			result.append(room.duplicate(true))
	result.sort_custom(func(a: Dictionary,b: Dictionary): return str(a.number)<str(b.number))
	return result

func locate(point: Vector3) -> String:
	for room in rooms.values():
		var low := vector(room.bounds_min)
		var high := vector(room.bounds_max)
		if point.x>low.x and point.x<high.x and point.z>low.z and point.z<high.z and point.y>=low.y-.3 and point.y<high.y:
			return str(room.id)
	if point.z < -14.0: return "exterior"
	if point.z < -4.0: return "lobby"
	if point.z>=50.0 and point.z<=62.0 and point.x<13.0 and point.x>=10.0: return "stairs"
	return "hall_f1" if point.y>=4.5 else "hall_f0"

func anchor(id: String) -> Transform3D:
	if not rooms.has(id): return Transform3D.IDENTITY
	return Transform3D(Basis.IDENTITY,vector(rooms[id].anchor))

func room_slip(id: String) -> Dictionary:
	var room := get_room(id)
	if room.is_empty(): return {}
	return {"room_id":id,"room_number":room.number,"building":room.building,"floor":room.floor,"name":room.title,"directions":"From the entrance follow the main corridor. "+("Use the north stairs or elevator to floor 2. " if int(room.floor)==1 else "Stay on floor 1. ")+"Follow signs for "+str(room.number)+".","door":room.door.duplicate()}

## Walkable waypoint route, including real stair landings rather than straight-line through floors.
func route(from_id: String, to_id: String) -> PackedVector3Array:
	if not rooms.has(to_id): return PackedVector3Array()
	var goal: Dictionary=rooms[to_id]
	var source: Dictionary=rooms.get(from_id,{"anchor":data.entrance,"approach":[13,0,-9],"floor":0})
	if from_id=="hall_f1": source={"anchor":[14.5,5,49],"approach":[14.5,5,49],"floor":1}
	var points := PackedVector3Array([vector(source.anchor),vector(source.approach)])
	if int(source.floor)!=int(goal.floor):
		var stair_points := [Vector3(11.5,0,49),Vector3(11.5,0,50),Vector3(11.5,5,62),Vector3(11.5,5,63),Vector3(14.5,5,64),Vector3(14.5,5,49)]
		if int(source.floor)==1: stair_points.reverse()
		for point in stair_points: points.append(point)
	points.append(Vector3(14.5,float(goal.floor)*5,float(goal.approach[2])))
	points.append(vector(goal.approach))
	points.append(vector(goal.door))
	points.append(vector(goal.anchor))
	return points

## Academic adapter derives every field from the same room record.
## The academic world owns actual desk/chair creation at these suggested slots.
const LECTURE_ROOMS := ["elm253_lecture", "ety155_lecture"]

func activity_room(course_id: String, kind: String, lecture_room := "") -> Dictionary:
	if kind=="lecture" and not lecture_room.is_empty() and lecture_room not in LECTURE_ROOMS:return {}
	var room := get_room(lecture_room) if kind=="lecture" and not lecture_room.is_empty() else course_room(course_id,kind)
	if room.is_empty(): return {}
	var center := vector(room.center)
	var desks: Array[Vector3]=[]
	var seats: Array[Vector3]=[]
	for z in [-2.0,2.0]:
		for x in [-6.0,-2.0,2.0,6.0]:
			desks.append(center+Vector3(x,.8,z))
			seats.append(center+Vector3(x,0,z+1))
	var benches: Array[Vector3]=[]
	if kind=="lab":
		desks.clear()
		seats.clear()
		if str(room.id)=="dc_lab":
			for values in data.composition.dc_bench_centers:
				var bench := vector(values)
				benches.append(bench)
				desks.append(bench+Vector3(1.65,.895,-.4))
		else:
			for x in [-6.,0.,6.]: benches.append(Vector3(x,0,-2.9))
			for z in [1.5,6.]:
				for x in [-6.5,6.5]: desks.append(Vector3(x,.895,z))
	var result := room_slip(str(room.id))
	result.merge({"id":room.id,"number":room.number,"name":room.title,"teacher_position":center+Vector3(0,0,-float(room.size[2])/2+2),"entrance":vector(data.entrance),"desks":desks,"seats":seats,"benches":benches})
	return result

func room_contains(id: String, point: Vector3) -> bool:
	return rooms.has(id) and locate(point)==id

func directory() -> Array:
	return search("")

func entrance() -> Vector3:
	return vector(data.entrance)

func route_from_position(point: Vector3, to_id: String) -> PackedVector3Array:
	# Hall/stair location IDs are valid sources, never room destinations.
	if not rooms.has(to_id): return PackedVector3Array()
	var current := locate(point)
	var path := route(current,to_id)
	if current==to_id: return PackedVector3Array([point,vector(rooms[to_id].anchor)])
	if current=="stairs" and rooms.has(to_id):
		var target: Dictionary=rooms[to_id]
		var waypoints := PackedVector3Array([point])
		if int(target.floor)==1:
			waypoints.append(Vector3(11.5,5,62))
			waypoints.append(Vector3(11.5,5,63))
			waypoints.append(Vector3(14.5,5,64))
		else:
			waypoints.append(Vector3(11.5,0,50))
			waypoints.append(Vector3(11.5,0,49))
		waypoints.append(Vector3(14.5,float(target.floor)*5,float(target.approach[2])))
		waypoints.append(vector(target.approach))
		waypoints.append(vector(target.door))
		waypoints.append(vector(target.anchor))
		return waypoints
	if path.is_empty(): return path
	path[0]=point
	if not rooms.has(current):
		path[1]=Vector3(14.5,5.0 if point.y>=4.5 else 0.0,point.z)
		# Unknown hall locations still need the proper floor for the staircase route.
		var goal := get_room(to_id)
		if point.y>=4.5 and int(goal.floor)==1:
			return PackedVector3Array([point,path[1],Vector3(14.5,5.0,float(goal.approach[2])),vector(goal.approach),vector(goal.door),vector(goal.anchor)])
		if point.y>=4.5 and int(goal.floor)==0:
			return PackedVector3Array([point,path[1],Vector3(14.5,5,49),Vector3(14.5,5,64),Vector3(11.5,5,63),Vector3(11.5,5,62),Vector3(11.5,0,50),Vector3(11.5,0,49),Vector3(14.5,0,float(goal.approach[2])),vector(goal.approach),vector(goal.door),vector(goal.anchor)])
	return path
