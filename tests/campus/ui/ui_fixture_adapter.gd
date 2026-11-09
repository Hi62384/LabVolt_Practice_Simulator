extends RefCounted
signal navigation_requested(room_id: String)
var requested := {}
var target := ""
var room_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/campus/ui/fixtures/room_contract.json"))
func courses() -> Array:
	return [{"id":"ELM253","title":"AC Electrical Systems"},{"id":"ETY155","title":"Basic DC Electricity"}]
func weeks(id: String, kind: String) -> Array:
	var output: Array=[]
	for i in range(12 if id=="ETY155" else (11 if kind=="lecture" else 8)): output.append({"week":i+1,"title":"UI contract fixture %d"%(i+1),"topics":["Fixture selection test"]})
	return output
func progress(_id: String) -> Dictionary: return {"lecture":90.0,"lab":null,"overall":90.0}
func week_progress(_id: String, _week: int) -> Dictionary: return {"lecture":{"count":1,"best":90.0,"recent":90.0},"lab":{"count":0}}
func assigned_room(id: String, kind: String) -> Dictionary:
	var target_id := "dc_lab" if id=="ETY155" else "ac_lab"
	if kind=="lecture": target_id="ety155_lecture" if id=="ETY155" else "elm253_lecture"
	for room in room_data.rooms:
		if room.id==target_id: return room
	return {}
func rooms(query := "") -> Array:
	var found: Array=[]
	for room in room_data.rooms:
		if query.is_empty() or (str(room.number)+" "+str(room.title)).to_lower().contains(query.to_lower()): found.append(room)
	return found
func request_activity(config: Dictionary) -> Dictionary:
	requested=config.duplicate(true); return {"ok":true}
func navigate(id: String) -> void:
	target=id; navigation_requested.emit(id)
