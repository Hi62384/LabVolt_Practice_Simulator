extends Node
## Composition layer: static room anchors + existing chair authority + one local UI.
const Desktop = preload("res://scripts/campus/computers/course_desktop.gd")
const Board = preload("res://scripts/campus/academics/teaching_board.gd")
var game: Node
var room: Node3D
var desktop: Control
var board: Node3D
var chair_stations := {}
var indicators := {}
var active := false
var ui_was_open := false
var visibility_timer: Timer
func build(owner_game: Node, mounted_room: Node3D) -> bool:
	game=owner_game
	room=mounted_room
	if not room.mounted:return false
	var ids: Array=room.stations.keys()
	ids.sort()
	for id in ids:
		var station: Node3D=room.stations[id]
		var index: int=game.chairs.size()
		game._add_chair(station.seat_anchor.global_position)
		var chair: CharacterBody3D=game.chairs[index]
		# Keep the classroom's static chair visual. The existing gameplay chair
		# supplies occupant/rider/collider/network semantics at the exact seat anchor.
		for child in chair.get_children():
			if child is VisualInstance3D:child.hide()
			elif child is Node3D:
				for part in child.get_children():
					if part is VisualInstance3D:part.hide()
		chair.set_physics_process(false)
		chair_stations[index]=str(id)
		if not game.computers.register_station(str(id),index,station.interaction_anchor.global_position):return false
		var target := StaticBody3D.new()
		target.set_meta("role","computer")
		target.set_meta("station",str(id))
		target.set_meta("label","Use classroom computer")
		station.add_child(target)
		var hit := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size=Vector3(.72,.48,.12)
		hit.shape=shape
		hit.position=station.screen_anchor.position
		target.add_child(hit)
		var label := Label3D.new()
		label.text="CAMPUS • READY"
		label.font_size=28
		label.pixel_size=.0017
		label.position=station.screen_anchor.position+Vector3(0,0,.045)
		station.add_child(label)
		indicators[id]=label
	var layer := CanvasLayer.new()
	layer.layer=40
	add_child(layer)
	desktop=Desktop.new()
	layer.add_child(desktop)
	desktop.build(game.computers)
	game.computers.desktop_changed.connect(_desktop_changed)
	game.computers.occupancy_changed.connect(_occupancy)
	board=Board.new()
	room.root.get_node("TeachingDisplayMount").add_child(board)
	game.school.updated.connect(_teaching)
	visibility_timer=Timer.new()
	visibility_timer.wait_time=.5
	visibility_timer.timeout.connect(_teaching)
	add_child(visibility_timer)
	visibility_timer.start()
	_teaching()
	return true
func interact(target: Object) -> bool:
	if not is_instance_valid(target):return false
	var id: String=str(target.get_meta("station",""))
	if id.is_empty() and target.get_meta("role","")=="chair":
		id=str(chair_stations.get(game.chairs.find(target.get_parent()),""))
	if id.is_empty():return false
	game.computers.request({"op":"enter","station":id})
	return true
func route_event(event: InputEvent) -> bool:
	if not is_instance_valid(desktop) or not desktop.visible:return false
	# Return from game._input without marking general pointer events handled:
	# GUI controls must still receive them. Desktop owns Esc/Ctrl+S in its _input.
	return event is InputEventKey or event is InputEventMouse
func _desktop_changed(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		if game.computers.get_meta("resetting",false):
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
			game.player.enabled=false
		elif ui_was_open and game.front.in_game:game.capture()
		ui_was_open=false
	else:
		ui_was_open=true
		game.release_mouse()
func _occupancy(occupancy: Dictionary) -> void:
	for id in indicators:
		indicators[id].text="CAMPUS • IN USE" if occupancy.has(id) else "CAMPUS • READY"
func _teaching() -> void:
	if not is_instance_valid(board):return
	var inside: bool=game.campus.registry.locate(game.player.global_position)=="computer"
	board.set_room_active(inside)
	if not inside:return
	var school: Node=game.school
	var assigned: bool=str(school.activity.get("room",{}).get("id",""))=="computer"
	var stage := {"text":"Computer classroom • Freeplay practice"}
	var phase := "freeplay"
	if assigned:
		phase=str(school.phase)
		if phase=="lesson":stage=school.teaching_stage().duplicate(true)
		else:stage={"text":"Class begins in %02d:%02d"%[int(school.remaining)/60,int(school.remaining)%60]} if phase=="travel" else {"text":"Complete your assigned work using the classroom paper and computer interfaces."}
	board.show_public_content({"course_id":str(school.activity.get("course_id","")) if assigned else "","phase":phase,"heading":"M203 Computer Classroom","stage":stage,"status":""})
