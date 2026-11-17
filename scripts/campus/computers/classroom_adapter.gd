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
var public_id := "m203_r3_c4"
var public_ids := {}
var power_states := {}
var occupied := {}
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
		if not register_station(str(id),room.stations[id],str(id)==public_id):return false
	var layer := CanvasLayer.new()
	layer.layer=40
	add_child(layer)
	desktop=Desktop.new()
	layer.add_child(desktop)
	desktop.build(game.computers)
	game.computers.desktop_changed.connect(_desktop_changed)
	game.computers.occupancy_changed.connect(_occupancy)
	game.computers.power_changed.connect(_power)
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
func register_station(id: String,station: Node3D,is_public: bool) -> bool:
	var index: int=game.chairs.size()
	game._add_chair(station.seat_anchor.global_position)
	var chair: CharacterBody3D=game.chairs[index]
	chair.fixed_seat=true
	chair.fixed_yaw=station.seat_anchor.global_rotation.y
	# Keep the classroom's static chair visual. The existing gameplay chair
	# supplies occupant/rider/collider/network semantics at the exact seat anchor.
	for child in chair.get_children():
		if child is VisualInstance3D:child.hide()
		elif child is Node3D:
			for part in child.get_children():
				if part is VisualInstance3D:part.hide()
	chair.set_physics_process(false)
	chair_stations[index]=str(id)
	if not game.computers.register_station(str(id),index,station.interaction_anchor.global_position,is_public):return false
	var target := StaticBody3D.new()
	target.set_meta("role","computer")
	target.set_meta("station",str(id))
	target.set_meta("label","Use public computer" if is_public else "Use classroom computer")
	station.add_child(target)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.72,.48,.12)
	hit.shape=shape
	hit.position=station.screen_anchor.position
	target.add_child(hit)
	var label := Label3D.new()
	label.text="POWER OFF" if is_public else "CAMPUS • READY"
	label.font_size=28
	label.pixel_size=.0017
	label.position=station.screen_anchor.position+Vector3(0,0,.045)
	station.add_child(label)
	indicators[id]=label
	if is_public:
		var usb_target:=StaticBody3D.new()
		usb_target.collision_layer=4;usb_target.collision_mask=0
		usb_target.set_meta("role","public_computer_usb")
		usb_target.set_meta("station",str(id))
		usb_target.set_meta("label","Connect or remove USB drive")
		station.add_child(usb_target)
		var usb_hit:=CollisionShape3D.new();var usb_shape:=BoxShape3D.new()
		usb_shape.size=Vector3(.085,.055,.06);usb_hit.shape=usb_shape
		usb_hit.position=Vector3(.47,.88,.025);usb_target.add_child(usb_hit)
		station._box(station,Vector3(.47,.88,.004),Vector3(.075,.035,.008),"steel")
		station._box(station,Vector3(.47,.88,.01),Vector3(.052,.018,.006),"bezel")
		var power_target:=StaticBody3D.new()
		power_target.collision_layer=4;power_target.collision_mask=0
		power_target.set_meta("role","public_computer_power")
		power_target.set_meta("station",str(id))
		power_target.set_meta("label","Toggle computer power")
		station.add_child(power_target)
		var power_hit:=CollisionShape3D.new();var power_shape:=BoxShape3D.new()
		power_shape.size=Vector3(.12,.08,.08);power_hit.shape=power_shape
		power_hit.position=Vector3(.58,.98,.025);power_target.add_child(power_hit)
		station._box(station,Vector3(.58,.98,.008),Vector3(.035,.035,.012),"steel")
		var power_mark:=Label3D.new();power_mark.text="⏻";power_mark.font_size=24;power_mark.pixel_size=.001
		power_mark.position=Vector3(.58,.98,.018);station.add_child(power_mark)
	if is_public:public_ids[id]=true
	return true
func interact(target: Object) -> bool:
	if not is_instance_valid(target):return false
	var role: String=str(target.get_meta("role",""))
	if role=="public_computer_usb":
		game.computers.request({"op":"usb_port","station":str(target.get_meta("station",""))})
		return true
	if role=="public_computer_power":
		game.computers.request({"op":"power","station":str(target.get_meta("station",""))})
		return true
	if role!="computer":return false
	var id: String=str(target.get_meta("station",""))
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
		if is_instance_valid(game.front.campus_hud):game.front.campus_hud.hide()
		game.release_mouse()
func _occupancy(occupancy: Dictionary) -> void:
	occupied=occupancy
	_update_indicators()
func _power(power: Dictionary) -> void:
	power_states=power
	_update_indicators()
func _update_indicators() -> void:
	for id in indicators:
		indicators[id].text="POWER OFF" if public_ids.has(id) and not bool(power_states.get(id,false)) else ("CAMPUS • IN USE" if occupied.has(id) else "CAMPUS • READY")
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
