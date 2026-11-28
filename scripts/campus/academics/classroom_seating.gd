extends Node
## All claims live on actual chair objects, alongside the existing human rider.
## Only the host reserves, moves and clears occupants; clients render snapshots.
const Route=preload("res://scripts/campus/academics/classroom_teacher_route.gd")
var game: Node
var students: Node
var clock:=0.

func configure(owner_game: Node,owner_students: Node) -> void:
	game=owner_game;students=owner_students

func chair_for(id: String) -> Node3D:
	if id.is_empty() or not is_instance_valid(game) or not "chairs" in game:return null
	for chair in game.chairs:
		if is_instance_valid(chair) and str(chair.seat_id)==id:return chair
	return null

func chair_at(point: Vector3) -> Node3D:
	if not is_instance_valid(game) or not "chairs" in game:return null
	for chair in game.chairs:
		if is_instance_valid(chair) and chair.global_position.distance_to(point)<.65:return chair
	return null

func available_points(room: Dictionary,players: Array[Vector3]) -> Array:
	var result: Array=[]
	for chair in game.chairs:
		if not is_instance_valid(chair) or not chair.available_for_npc():continue
		if str(chair.get_meta("classroom_room",""))!=str(room.get("id","")):continue
		var at: Vector3=chair.global_position
		if not game.campus.registry.room_contains(str(room.get("id","")),at):continue
		if not players.any(func(point: Vector3):return at.distance_to(point)<1.1) and npc_space_clear(at,""):result.append(at)
	return result

func assign(member: Dictionary,class_id: String) -> bool:
	var chair:=chair_at(member.seat)
	if chair==null or not chair.available_for_npc():return false
	var room:=str(chair.get_meta("classroom_room",""))
	if room.is_empty() or not game.campus.registry.room_contains(room,chair.global_position):return false
	chair.npc_occupant=str(member.profile.id);chair.npc_class=class_id
	chair.npc_arrived=bool(member.get("seated",false))
	member.seat_id=chair.seat_id
	member.seat=chair.global_position
	member.seat_yaw=chair.swivel.global_rotation.y+PI
	return true

func _member(chair: Node3D) -> Dictionary:
	for activity in game.lecture_classes.classes.values():
		if str(activity.get("id",""))!=str(chair.npc_class):continue
		var member: Dictionary=activity.get("classmates",{}).get(chair.npc_occupant,{})
		if member.is_empty() or bool(member.get("removed_from_class",false)):return {}
		return {"member":member,"activity":activity}
	return {}

func request_player(chair: Node3D,peer: int) -> bool:
	if not multiplayer.is_server() or chair.occupant!=0 or (chair.reserved_peer!=0 and chair.reserved_peer!=peer):return false
	var found:=_member(chair)
	if found.is_empty():chair.release_npc();game.call_deferred("_claim_chair",peer,game.chairs.find(chair));return true
	var member: Dictionary=found.member
	if member.has("seat_relocation") or member.get("using_bench",false) or member.get("leaving_class",false):return false
	var room:=str(chair.get_meta("classroom_room",""))
	var destination: Node3D
	var path: Array[Vector3]=[]
	var candidates: Array=[]
	for other in game.chairs:
		if other!=chair and str(other.get_meta("classroom_room",""))==room and other.available_for_npc() and game.campus.registry.room_contains(room,other.global_position):candidates.append(other)
	candidates.sort_custom(func(a,b):return a.global_position.distance_squared_to(chair.global_position)<b.global_position.distance_squared_to(chair.global_position))
	for other in candidates:
		path=_route(room,member.position,other.global_position,[chair,other],str(member.profile.id))
		if not path.is_empty():destination=other;break
	if path.is_empty():
		# A full room still permits a clear standing place behind the desk.
		for offset in [Vector3(0,0,1.5),Vector3(1.8,0,.8),Vector3(-1.8,0,.8),Vector3(0,0,2.5)]:
			path=_route(room,member.position,chair.global_position+offset,[chair],str(member.profile.id))
			if not path.is_empty():break
	if path.is_empty():
		_feedback(peer,"There is no clear place for this student to move yet.")
		return false
	chair.reserved_peer=peer;chair.reservation_until=Time.get_ticks_msec()+20000;chair.npc_vacating=true
	if destination!=null:
		destination.npc_occupant=str(member.profile.id);destination.npc_class=str(found.activity.id);destination.npc_arrived=false
	member.seat_relocation={"origin":str(chair.seat_id),"destination":str(destination.seat_id) if destination!=null else "","path":path,
		"index":0,"starts":Time.get_ticks_msec()+400,"deadline":Time.get_ticks_msec()+20000,"room":room,"peer":peer}
	member.erase("walk");member.seated=false;member.standing=true;member.walking=false;member.action="standing to make room"
	students.call_deferred("seat_request_reaction",found.activity,member,peer)
	game._send_chairs()
	return true

func _route(room: String,start: Vector3,goal: Vector3,chairs: Array,actor: String) -> Array[Vector3]:
	if not game.campus.registry.room_contains(room,goal):return []
	var ignored:=_ignored(chairs)
	var clear:=npc_space_clear.bind(actor)
	var path:=Route.plan(game,room,start,goal,0.,clear,ignored)
	if path.is_empty() or path.back().distance_to(goal)>.9:return []
	if not Route.clear_step(game,path.back(),goal,clear,ignored):return []
	path.append(goal)
	return path

func npc_space_clear(point: Vector3,actor: String) -> bool:
	# NPC interaction bodies use a ray-picking layer. Check their authoritative
	# floor positions too, including students walking between their chairs.
	var now: float=game.lecture_classes._now()
	for activity in game.lecture_classes.classes.values():
		for member in activity.get("classmates",{}).values():
			if str(member.get("profile",{}).get("id",""))==actor or member.get("removed_from_class",false) or float(member.get("arrival",0.))>now:continue
			var other: Vector3=member.get("position",Vector3.INF)
			if not other.is_finite() or absf(point.y-other.y)>1.5:continue
			if Vector2(point.x-other.x,point.z-other.z).length_squared()<.70*.70:return false
	return true

func move_student(member: Dictionary,activity: Dictionary,room: String,target: Vector3) -> bool:
	if not multiplayer.is_server() or member.has("seat_relocation"):return false
	var origin:=chair_for(str(member.get("seat_id","")))
	var destination:=chair_at(target)
	if origin==null or destination==null or not destination.available_for_npc():return false
	if str(destination.get_meta("classroom_room",""))!=room or not game.campus.registry.room_contains(room,destination.global_position):return false
	var path:=_route(room,member.position,destination.global_position,[origin,destination],str(member.profile.id))
	if path.is_empty():return false
	destination.npc_occupant=str(member.profile.id);destination.npc_class=str(activity.id);destination.npc_arrived=false
	origin.npc_vacating=true
	member.seat_relocation={"origin":str(origin.seat_id),"destination":str(destination.seat_id),"path":path,
		"index":0,"starts":Time.get_ticks_msec()+400,"deadline":Time.get_ticks_msec()+20000,"room":room,"peer":0,"purpose":"discipline"}
	member.erase("walk");member.seated=false;member.standing=true;member.walking=false;member.action="changing seats"
	return true

func _ignored(chairs: Array) -> Array[RID]:
	var result: Array[RID]=[]
	for chair in chairs:
		if not is_instance_valid(chair):continue
		if chair is CollisionObject3D:result.append(chair.get_rid())
		for child in chair.get_children():
			if child is CollisionObject3D and str(child.get_meta("role",""))=="chair":result.append(child.get_rid())
	return result

func step(member: Dictionary,delta: float) -> bool:
	if not member.has("seat_relocation"):return false
	var move: Dictionary=member.seat_relocation
	var origin:=chair_for(str(move.origin));var destination:=chair_for(str(move.destination))
	if Time.get_ticks_msec()<int(move.starts):return true
	var path: Array=move.path
	# The destination is a rolling chair. A stale path must never finish at its
	# old location and then snap the seated body to wherever the chair moved.
	if destination!=null and (str(destination.npc_occupant)!=str(member.profile.id) or destination.global_position.distance_to(path.back())>.12):
		_abort_relocation(member,move,origin,destination,"The destination chair moved. Ask again once it is still.")
		return true
	var index:=int(move.index)
	if index>=path.size():
		member.erase("seat_relocation");member.walking=false;member.arrived=true
		member.has_seat=destination!=null;member.standing=destination==null;member.seated=destination!=null
		member.seat_id=str(destination.seat_id) if destination!=null else ""
		member.seat=member.position;member.action="listening";member.next=game.lecture_classes._now()+3.
		if destination!=null:
			destination.npc_arrived=true;member.seat_yaw=destination.swivel.global_rotation.y+PI
		if str(move.get("purpose",""))=="discipline" and member.has("last_discipline"):
			member.last_discipline.executed=true;member.last_discipline.pending=false
		_clear_origin(origin,member)
		return true
	var current: Vector3=member.position
	var next:=current.move_toward(path[index],delta*1.5)
	var safe:=Route.clear_step(game,current,next,npc_space_clear.bind(str(member.profile.id)),_ignored([origin,destination]))
	if not safe or Time.get_ticks_msec()>int(move.deadline):
		_abort_relocation(member,move,origin,destination,"The aisle is blocked. Clear a path and ask again.")
		return true
	member.position=next;member.walking=true;member.action="changing seats";member.look_at=path[index]+Vector3.UP*1.1
	if next.is_equal_approx(path[index]):move.index=index+1
	if origin!=null and origin.global_position.distance_to(next)>.85:_clear_origin(origin,member)
	return true

func _abort_relocation(member: Dictionary,move: Dictionary,origin: Node3D,destination: Node3D,reason: String) -> void:
	# Abort in place. Release pending claims without teleporting or clearing a
	# different occupant that acquired a chair after this request started.
	member.erase("seat_relocation");member.walking=false;member.standing=true;member.seated=false;member.arrived=true
	member.has_seat=false;member.seat_id="";member.seat=member.position;member.action="standing nearby"
	if destination!=null and str(destination.npc_occupant)==str(member.profile.id):destination.release_npc()
	if origin!=null and str(origin.npc_occupant)==str(member.profile.id):
		origin.reserved_peer=0;origin.reservation_until=0;origin.npc_vacating=false
		if origin.global_position.distance_to(member.position)>.85:origin.release_npc()
		else:member.seat_id=origin.seat_id;member.has_seat=true;member.seat=origin.global_position
	if str(move.get("purpose",""))=="discipline" and member.has("last_discipline"):
		member.last_discipline.executed=false;member.last_discipline.pending=false;member.last_discipline.reason=reason
	if int(move.peer)>0:_feedback(int(move.peer),reason)

func _clear_origin(origin: Node3D,member: Dictionary) -> void:
	if origin==null or str(origin.npc_occupant)!=str(member.profile.id):return
	var peer:=int(origin.reserved_peer)
	origin.release_npc()
	if peer>0 and _valid_reservation(origin):game.call_deferred("_claim_chair",peer,game.chairs.find(origin))

func _valid_reservation(chair: Node3D) -> bool:
	var peer:=int(chair.reserved_peer)
	if peer<=0:return false
	var valid: bool=game.session.roster.has(peer) and Time.get_ticks_msec()<int(chair.reservation_until)
	if valid:valid=game.lecture_classes._position(peer).distance_to(chair.global_position)<=3.2
	if valid:
		for other in game.chairs:
			if other.occupant==peer:valid=false;break
	if not valid:chair.reserved_peer=0;chair.reservation_until=0
	return valid

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not multiplayer.is_server() or not is_instance_valid(game.lecture_classes):return
	clock+=delta
	if clock<.15:return
	clock=0.
	for chair in game.chairs:
		_valid_reservation(chair)
		if chair.npc_occupant.is_empty():continue
		var found:=_member(chair)
		if found.is_empty():
			chair.release_npc();chair.reserved_peer=0;chair.reservation_until=0
			continue
		var member: Dictionary=found.member
		if member.has("seat_relocation"):continue
		if str(member.get("seat_id",""))!=str(chair.seat_id):chair.release_npc();continue
		chair.npc_arrived=bool(member.get("seated",false))
		member.seat=chair.global_position;member.seat_yaw=chair.swivel.global_rotation.y+PI
		if chair.npc_arrived:member.position=chair.global_position

func _feedback(peer: int,text: String) -> void:
	if peer==multiplayer.get_unique_id():game.ui.log_message(text)
	elif game.session.online and game.session.peer_connected_now(peer):_notice.rpc_id(peer,text)

@rpc("authority","call_remote","reliable")
func _notice(text: String) -> void:
	game.ui.log_message(text.left(180))
