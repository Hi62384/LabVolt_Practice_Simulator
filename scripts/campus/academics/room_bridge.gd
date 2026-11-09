extends RefCounted
var registry: Object

func _init(injected: Object = null) -> void:
	registry=injected
	if registry==null and ResourceLoader.exists("res://scripts/campus/world/room_registry.gd"):
		registry=load("res://scripts/campus/world/room_registry.gd").new()

static func point(value: Variant) -> Vector3:
	if value is Vector3:return value
	if value is Array and value.size()>=3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

func room(course: String, kind: String, lecture_room := "") -> Dictionary:
	if registry==null:return {}
	if registry.has_method("activity_room"):
		var activity: Dictionary=registry.call("activity_room",course,kind) if lecture_room.is_empty() else registry.call("activity_room",course,kind,lecture_room)
		if activity.is_empty():return {}
		var raw: Dictionary=registry.call("get_room",str(activity.id)) if registry.has_method("get_room") else {}
		raw.merge(activity,true)
		return raw
	if not registry.has_method("course_room"):return {}
	var data: Dictionary=registry.call("course_room",course,kind)
	if data.is_empty():return {}
	data=data.duplicate(true)
	data.name=data.get("title","")
	data.teacher_position=point(data.get("anchor",data.get("center",[])))+Vector3(0,0,2)
	if kind=="lecture":
		data.desks=preload("res://scripts/campus/academics/classroom_layout.gd").desks(data)
		data.teacher_position=preload("res://scripts/campus/academics/classroom_layout.gd").teacher(data)
	data.entrance=Vector3.ZERO
	if "data" in registry:data.entrance=point(registry.data.get("entrance",[]))
	if registry.has_method("room_slip"):data.merge(registry.call("room_slip",str(data.id)),true)
	return data

func contains(id: String, position: Vector3) -> bool:
	if registry==null:return false
	if registry.has_method("room_contains"):return bool(registry.call("room_contains",id,position))
	return registry.has_method("locate") and str(registry.call("locate",position))==id
