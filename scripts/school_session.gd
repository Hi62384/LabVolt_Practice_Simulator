extends Node
signal updated
signal academic_records_changed
signal activity_started(entrance: Vector3)
signal activity_completed
const Course = preload("res://scripts/course_generator.gd")
const DormSupplies = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
var game: Node
var papers := {}
var floor_leads := {}
var next_floor_lead := 1
var worn_gear := {}
var identities := {}
var class_students := {}
var mode := "Freeplay"
var difficulty := 0
var phase := "freeplay"
var remaining := 0.0
var round_id := 0
var activity_epoch := 0
var project := {}
var next_id := 1
var teacher_position := Vector3(0,0,5)
var teacher_goal := Vector3(2,0,4)
var teacher_yaw := 0.0
var sync_clock := 0.0
var local_identity := ""
var sent_identity := false
var gradebook := {}
var archive := {}
var last_requests := {}
const GradePolicy = preload("res://scripts/campus/academics/grade_policy.gd")
const PendingAssessment = preload("res://scripts/campus/academics/pending_assessment.gd")
const CourseProgression = preload("res://scripts/campus/academics/course_progression_adapter.gd")
const RecordMetadata=preload("res://scripts/campus/academics/record_metadata.gd")
const Attendance = preload("res://scripts/campus/academics/attendance_ledger.gd")
const ClassStartClock = preload("res://scripts/campus/academics/class_start/class_start_clock.gd")
const GradeWeights = preload("res://scripts/campus/academics/grade_weight_policy.gd")
const PracticeSheets = preload("res://scripts/campus/academics/open_lab/practice/practice_sheet_store.gd")
var practice_dirty := {}
var practice_save_clock := 0.0
var class_start = ClassStartClock.new()
var attendance_archive := {}
var local_attendance := {}
const Benches = preload("res://scripts/campus/academics/bench_allocator.gd")
var course_bridge = preload("res://scripts/campus/academics/course_bridge.gd").new()
var room_bridge = preload("res://scripts/campus/academics/room_bridge.gd").new()
var equipment_adapter: Object
var activity := {}
var presentation := {}
var released_teaching_stage := ""
var public_math_projects := {}
var allocation := {}
var assessment_id := ""
var assessment_deadline := 0.0
var teaching_seconds := 300.0
var assessment_seconds := 1800.0
var category_weights := {"lecture":1.0,"lab":1.0}
var recovery_clock := 0.0
var suspended := false
var host_departure_in_progress := false
var random := RandomNumberGenerator.new()
func build(owner_game: Node) -> void:
	game=owner_game
	equipment_adapter=preload("res://scripts/campus/academics/equipment_evidence.gd").new(game)
	random.randomize()
	for entry in [["user://student_grades.json","gradebook"],["user://teacher_records.json","archive"],["user://student_attendance.json","local_attendance"],["user://teacher_attendance.json","attendance_archive"]]:
		var data=JSON.parse_string(FileAccess.get_file_as_string(entry[0])) if FileAccess.file_exists(entry[0]) else {}
		if data is Dictionary:set(entry[1],data)
	game.session.roster_changed.connect(roster_changed)
	game.session.restarted.connect(_reset_session)
	game.session.leaving.connect(_session_leaving)
	game.characters.changed.connect(_identity_changed)
	if PendingAssessment.end_host_session(archive,_persist_archive)!=OK:
		push_warning("Could not reconcile interrupted class records. The archive will be retried on the next launch.")
	_identity_changed()
func _reset_session() -> void:
	_flush_practice()
	host_departure_in_progress=false
	class_start.cancel()
	sent_identity=false
	papers.clear()
	floor_leads.clear()
	next_floor_lead=1
	identities.clear()
	class_students.clear()
	mode="Freeplay"
	phase="freeplay"
	remaining=0
	project={}
	activity={}
	presentation={}
	public_math_projects.clear()
	allocation={}
	teaching_seconds=300
	assessment_seconds=1800
	suspended=false
	updated.emit()
func _identity_changed() -> void:
	# An active session retains its identity even if the appearance changes.
	if game.front.in_game:return
	var cfg := ConfigFile.new()
	cfg.load("user://student_identity.cfg")
	var profile: String=game.characters.selected if game.characters.selected!="" else "__default__"
	local_identity=str(cfg.get_value("profiles",profile,""))
	if local_identity=="":
		local_identity=Crypto.new().generate_random_bytes(24).hex_encode()
		cfg.set_value("profiles",profile,local_identity)
		cfg.save("user://student_identity.cfg")
	sent_identity=false
	_deliver_host_departure_grade()
	academic_records_changed.emit()
func start(new_mode: String,level: int) -> void:
	if not multiplayer.is_server():return
	if formal_active():
		_notice(1,"Finish or explicitly abandon the active assessment before changing activities.")
		return
	class_start.cancel()
	_flush_practice()
	activity_epoch+=1
	activity={}
	presentation={}
	allocation={}
	mode=new_mode
	teaching_seconds=300
	assessment_seconds=1800
	difficulty=clampi(level,0,4)
	papers.clear()
	class_students.clear()
	phase="freeplay"
	remaining=0
	if not identities.has(1):_identify(1,local_identity)
	else:_restore_practice(1)
	if mode=="Class":_clear_earthing_demo();_new_round()
	broadcast()
func roster_changed() -> void:
	if not multiplayer.is_server():
		if game.session.roster.has(multiplayer.get_unique_id()) and not sent_identity:
			sent_identity=true
			register_identity.rpc_id(1,local_identity)
		return
	for peer in identities.keys():
		if not game.session.roster.has(peer):
			var token: String=identities[peer]
			_save_practice(token)
			if not host_departure_in_progress:_fail_departing(token,peer)
			for id in papers.keys():
				if papers[id].owner==peer:papers.erase(id)
			identities.erase(peer)
	if game.session.online and not identities.has(1):
		_identify(1, local_identity)
		return
	broadcast()
@rpc("any_peer","call_remote","reliable",4)
func register_identity(token: String) -> void:
	if multiplayer.is_server():_identify(multiplayer.get_remote_sender_id(),token)
func _identify(peer: int,token: String) -> void:
	if not game.session.roster.has(peer) or identities.has(peer) or token.length()!=48 or not token.is_valid_hex_number():return
	if identities.values().has(token):
		token=Crypto.new().generate_random_bytes(24).hex_encode()
		_notice(peer,"That profile is already in this session. This instance will use a separate guest grade record.")
	if mode=="Class" and phase in ["travel","lesson"] and not class_students.has(token) and not _is_replay(token, project):
		var enrollment: Array[Dictionary]=[_enrollment_record(token,assessment_id,project,peer==1)]
		if PendingAssessment.enroll(archive,enrollment,_persist_archive)!=OK:
			_notice(peer,"Class enrollment could not be saved. Ask the host to retry admission.")
			return
	identities[peer]=token
	_restore_practice(peer)
	if peer==1:_identity_accepted(token,archive.get(token,{}))
	elif game.session.online:_identity_accepted.rpc_id(peer,token,archive.get(token,{}))
	if mode=="Class":
		if class_students.has(token):
			if phase in ["travel","lesson"]:class_start.arrive(token,Time.get_ticks_usec())
			if phase=="lesson":_record_attendance(peer)
			if bool(class_students[token].get("done",false)):
				_notice(peer,"Your previous class assignment is closed.")
			elif phase=="assignment":
				# Rejoining a departed class never restores or reissues its assessment.
				_fail_departing(token,peer)
		elif phase in ["travel","lesson"]:
			class_students[token]={"done":false,"replay":_is_replay(token, project)}
			class_start.arrive(token,Time.get_ticks_usec())
			if phase=="lesson":_record_attendance(peer)
			_individual_project(token)
			if activity.get("kind","")=="lab" and not allocation.has(token):
				var counts := [0,0,0]
				for slot in allocation.values():counts[int(slot.bench)]+=1
				var bench: int=counts.find(counts.min())
				allocation[token]={"bench":bench,"group":bench,"individual":true}
			if not activity.is_empty():_give_slip(peer)
		elif phase=="assignment":
			_give(peer,project,false,false)
			_notice(peer,"You joined during the lab. This copy is ungraded practice; your first graded round starts after the break.")
	broadcast()
@rpc("authority","call_remote","reliable",4)
func _identity_accepted(token: String,records: Dictionary) -> void:
	local_identity=token
	var settled: Array = records.values().filter(func(record): return record is Dictionary and not record.has("pending_assessment_version"))
	settled.sort_custom(RecordMetadata.precedes)
	for record in settled:
		_receive_grade(record)
	academic_records_changed.emit()
func _desk(peer: int) -> Vector3:
	if not activity.is_empty():
		var room: Dictionary=activity.get("room",{})
		var desks: Array=room.get("desks",[])
		var peers: Array=identities.keys();peers.sort()
		if not desks.is_empty():return room_bridge.point(desks[posmod(peers.find(peer),desks.size())])
		return room_bridge.point(room.get("teacher_position",Vector3.ZERO))+Vector3((peer%4-1.5)*.7,.895,-2.0-float(peer%2))
	return Vector3(-6.5 if peer%2==0 else 6.5,.895,1.5 if peer%3==0 else 6.0)+Vector3((peer%3-1)*.55,0,-.25)
func held(peer: int) -> int:
	for id in papers:
		if papers[id].owner==peer and papers[id].held:return int(id)
	return 0
func _individual_project(token: String) -> Dictionary:
	if not class_students.has(token):return project
	var metadata := RecordMetadata.from_project(archive.get(token, {}).get(GradePolicy.attempt_id(assessment_id, token), {}))
	if str(activity.get("course_id","")) not in ["MTH147","MTH255"]:
		if metadata.is_empty():return project
		var issued := project.duplicate(true)
		issued.merge(metadata, true)
		return issued
	var record: Dictionary=class_students[token]
	if record.has("project"):return record.project
	# Persist this immutable version before teaching/test time; reconnect never regenerates.
	var seed_value: int=(assessment_id+":"+token).sha256_text().substr(0,7).hex_to_int()
	var generated: Dictionary=course_bridge.generate(str(activity.course_id),int(activity.week),"lecture",difficulty,seed_value)
	if generated.is_empty() or generated.has("error"):return {}
	generated.assessment_id=assessment_id
	generated.merge(metadata, true)
	if project.has("official_assessment_title"):
		generated.title = project.official_assessment_title
	if not generated.has("assessment_policy"):generated.assessment_policy={}
	for permission in ["formula_allowed","calculator_allowed"]:generated.assessment_policy[permission]=bool(project.get("assessment_policy",{}).get(permission,false))
	record.project=generated.duplicate(true)
	return record.project
func _give(peer: int,assignment: Dictionary,lesson: bool,class_copy: bool,supply := false) -> int:
	if str(assignment.get("practice_scope",""))=="ungraded" and (class_copy or not lesson):return 0
	if class_copy:
		assignment=_individual_project(str(identities.get(peer,"")))
		if assignment.is_empty():_notice(peer,"Your assessment could not be prepared. Ask the host to restart the activity.");return 0
	var replay := class_copy and bool(class_students.get(identities.get(peer, ""), {}).get("replay", false))
	if class_copy and not replay:
		var token := str(identities.get(peer,""))
		var obligation := {"id":GradePolicy.attempt_id(assessment_id,token),"assessment_id":assessment_id,"profile":token,"title":str(assignment.get("title","Class assignment")),"course_id":assignment.get("course_id","ELM253"),"kind":assignment.get("kind","lecture"),"week":assignment.get("week",1),"difficulty":difficulty,"lesson":false,"time":Time.get_datetime_string_from_system()}
		obligation.merge(CourseProgression.record_fields(assignment),true)
		obligation.merge(RecordMetadata.from_project(assignment),true)
		obligation["class_authority_role"]="host" if peer==1 else "guest"
		if PendingAssessment.prepare(archive,obligation,_persist_archive)!=OK:return 0
	var count := 0
	for paper in papers.values():
		if paper.owner==peer and DormSupplies.paper_supply(paper).is_empty():count+=1
	if count>=6 and not class_copy and not supply:
		_notice(peer,"Keep up to six sheets. Trash an unwanted sheet first.")
		return 0
	var can_hold := held(peer)==0 and not _holding_cable(peer) and not _holding_kit(peer)
	var id := next_id
	next_id+=1
	var destination := _practice_desk(peer, assignment) if assignment.get("practice_scope") == "ungraded" else _desk(peer)
	papers[id]={"id":id,"owner":peer,"identity":identities.get(peer,""),"owner_name":game.session.roster.get(peer,{}).get("name","Student"),"project":assignment.duplicate(true),"lesson":lesson,"class_round":round_id if class_copy else 0,"held":can_hold,"position":destination,"course_id":assignment.get("course_id","ELM253"),"kind":assignment.get("kind","lab"),"assessment_id":assessment_id if class_copy else "","procedure":{},"page":0,"answers":{},"strokes":{},"mark":{},"revision":0}
	papers[id].replay = replay
	_queue_practice_save(papers[id])
	if str(assignment.get("course_id","")).begins_with("MTH"):
		papers[id].math_policy=course_bridge.paper_policy(assignment,lesson or not class_copy)
	if lesson:
		papers[id].project.questions=papers[id].project.get("questions",[]).slice(0,3)
		if not assignment.has("course_id"):
			papers[id].project.teaching=preload("res://scripts/lesson_content.gd").teaching(int(assignment.get("topic",0)))
	if lesson and assignment.has("course_id"):
		var teaching: Dictionary=course_bridge.lesson_for_assignment(assignment,420)
		papers[id].project.teaching={"equipment":str(teaching.get("equipment_text",assignment.get("procedure",""))),"worked":str(teaching.get("worked",assignment.get("theory","")))}
		if str(assignment.course_id).begins_with("MTH"):papers[id].project.lesson_stages=teaching.get("stages",[]).duplicate(true)
	if not can_hold:_notice(peer,"Your new sheet is on a student desk. Look for your name on its cover.")
	return id
func _holding_cable(peer: int) -> bool:
	var dc: Node = game.get("dc_lab")
	if is_instance_valid(dc) and (dc.carried_leads.has(peer) or (peer == multiplayer.get_unique_id() and dc.lead_color >= 0)):return true
	for lab in game.session.labs:
		if not lab.holding(peer).is_empty():return true
	return false
func request(action: Dictionary) -> void:
	if action.get("op")=="notebook":action.content=preload("res://scripts/notebook_store.gd").read(game.characters.selected)
	if str(action.get("op","")) in ["new","pickup","place","page","trash","submit"]:game.sfx.play("trash" if action.op=="trash" else "paper")
	if multiplayer.is_server():apply(multiplayer.get_unique_id(),action)
	elif game.session.online:_request.rpc_id(1,action)
@rpc("any_peer","call_remote","reliable",4)
func _request(action: Dictionary) -> void:
	if multiplayer.is_server():apply(multiplayer.get_remote_sender_id(),action)
func _near(peer: int,point: Vector3) -> bool:
	var pos: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	return pos.distance_to(point)<3.6

func ground_drop_position(point: Variant, peer: int) -> Variant:
	if not point is Vector3 or not point.is_finite():return null
	var feet: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if not feet.is_finite() or feet.distance_to(point)>1.8:return null
	var space: PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
	var top := Vector3(point.x,feet.y+.35,point.z)
	var obstruction := PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.35,top,1)
	if not space.intersect_ray(obstruction).is_empty():return null
	var floor_ray := PhysicsRayQueryParameters3D.create(top,top-Vector3.UP*.9,1)
	var floor_hit := space.intersect_ray(floor_ray)
	if floor_hit.is_empty() or floor_hit.normal.y<.75:return null
	return floor_hit.position+Vector3.UP*.005

func _move_floor_lead(peer: int, action: Dictionary) -> void:
	if action.op=="pickup_floor_lead":
		var id := int(action.get("id",0))
		var lead: Dictionary=floor_leads.get(id,{})
		if lead.is_empty() or lead.owner!=peer or not _near(peer,lead.position):return
		if held(peer)!=0 or _holding_cable(peer) or _holding_kit(peer):return
		if lead.dc:
			game.dc_lab.carried_leads[peer]=lead.color
			game.dc_lab.carried_lead_stations[peer]=lead.station
			game.dc_lab._reply_hotbar_lead(peer,true)
		else:
			var lab=game.session.labs[lead.station]
			if lab.cables.size()>=120:return
			lab.cables.append({"id":lab.next_id,"a":"","b":"","owner":peer,"creator":peer,"color":lead.color})
			lab.next_id+=1
			lab.revision+=1
			game.session.broadcast()
		floor_leads.erase(id)
	else:
		var point: Variant=ground_drop_position(action.get("position"),peer)
		if point==null:return
		if floor_leads.size()>=128:
			_notice(peer,"Pick up a dropped lead before dropping another.")
			return
		var dc: Node=game.dc_lab
		var lead: Dictionary={}
		if dc.carried_leads.has(peer):
			if dc.pending_endpoints.has(peer):
				_notice(peer,"Disconnect the lead before dropping it.")
				return
			lead={"dc":true,"station":dc.carried_lead_stations.get(peer,0),"color":dc.carried_leads[peer]}
			dc.carried_leads.erase(peer)
			dc.carried_lead_stations.erase(peer)
			dc._reply_hotbar_lead(peer,true)
		else:
			for index in game.session.labs.size():
				var lab=game.session.labs[index]
				var cable: Dictionary=lab.holding(peer)
				if cable.is_empty():continue
				if cable.a!="" or cable.b!="":
					_notice(peer,"Disconnect the lead before dropping it.")
					return
				lead={"dc":false,"station":index,"color":cable.color}
				lab.cables.erase(cable)
				lab.revision+=1
				game.session.broadcast()
				break
		if lead.is_empty():return
		lead.merge({"owner":peer,"position":point})
		floor_leads[next_floor_lead]=lead
		next_floor_lead+=1
	broadcast()

func _mark_whiteboard(peer: int, action: Dictionary) -> void:
	if DormSupplies.paper_supply(papers.get(held(peer),{}))!="marker":return
	var id := int(action.get("id",0))
	var paper: Dictionary=papers.get(id,{})
	if not paper.has("wall_normal") or not _near(peer,paper.position):return
	var from: Variant=action.get("from")
	var to: Variant=action.get("point")
	for point in [from,to]:
		if not point is Vector2 or not point.is_finite() or point.x<0 or point.y<0 or point.x>1 or point.y>1:return
	var lines: Array=paper.get("board_lines",[])
	if action.get("erase",false):
		lines=lines.filter(func(line):
			var nearest := Geometry2D.get_closest_point_to_segment(to,line[0],line[1])
			return nearest.distance_to(to)>.045)
	else:
		if lines.size()>=600:return
		lines.append([from,to])
	paper.board_lines=lines
	paper.revision=int(paper.revision)+1
	broadcast()

func _sync_supply_world() -> bool:
	var dorm = game.get("dorm_interactions")
	if not is_instance_valid(dorm):return false
	var gear := {}
	var changed := _ensure_classroom_whiteboards()
	for peer in identities:
		var profile: Dictionary=dorm._profile(dorm.authenticated_identity(peer))
		var state: Dictionary=profile.get("dorm",{})
		var back := DormSupplies.Backpacks.equipped(state)
		var head: bool=state.get("worn_supplies",{}).has("head")
		if head or not back.is_empty():gear[peer]={"head":head,"back":state.backpacks[back].size if not back.is_empty() else ""}
		var present := {}
		for id in papers.keys():
			var paper: Dictionary=papers[id]
			if paper.owner!=peer:continue
			var item := DormSupplies.paper_supply(paper)
			if item.is_empty():continue
			present[item]=true
			if not paper.get("supply_released",false) and item not in state.get("carry_items",[]):
				papers.erase(id)
				changed=true
		for id in state.get("backpacks",{}):
			var bag: Dictionary=state.backpacks[id]
			var item := "bag:"+str(id)
			if bag.location!="ground" or present.has(item):continue
			var paper_id := _give(peer,{"title":DormSupplies.Backpacks.SIZES[bag.size].name,"questions":[],"guide_pages":[]},true,false,true)
			if paper_id==0:continue
			var point: Array=bag.position
			papers[paper_id].merge({"held":false,"position":Vector3(float(point[0]),float(point[1]),float(point[2])),"supply_id":item,"supply_model":bag.size,"supply_released":true},true)
			changed=true
	if worn_gear!=gear:
		worn_gear=gear
		changed=true
	return changed
func _ensure_classroom_whiteboards() -> bool:
	if room_bridge.registry==null:return false
	var changed := false
	for room_id in ["elm253_lecture","ety155_lecture"]:
		if papers.values().any(func(item):return item.get("classroom_board","")==room_id):continue
		var room: Dictionary=room_bridge.room("","lecture",room_id)
		if room.is_empty():continue
		var position: Vector3=room_bridge.point(room.center)+Vector3(0,2.28,-float(room.size[2])*.5+.18)
		papers[next_id]={
			"id":next_id,"owner":0,"owner_name":"","classroom_board":room_id,
			"project":{"title":"Classroom whiteboard","questions":[],"guide_pages":[]},
			"supply_id":"whiteboard","board_size":Vector2(5.4,1.62),"wall_normal":Vector3.BACK,
			"held":false,"position":position,"lesson":false,"class_round":0,"page":0,
			"answers":{},"strokes":{},"mark":{},"revision":0
		}
		next_id+=1
		changed=true
	return changed

func _table_position(pos: Vector3, peer := 0) -> bool:
	if not pos.is_finite():return false
	if peer>0 and is_instance_valid(game.get("dorm_interactions")) and game.dorm_interactions.valid_desk_surface(peer,pos):
		return true
	if not activity.is_empty() and room_bridge.contains(str(activity.room.id),pos):
		for desk in activity.room.get("desks",[]):
			if pos.distance_to(room_bridge.point(desk))<.5:return true
	for x in [-6.5,6.5]:
		for z in [1.5,6.0]:
			if absf(pos.x-x)<1.3 and absf(pos.z-z)<.42 and absf(pos.y-.895)<.05:return true
	if game.dc_lab.bench_surface_contains(pos):return true
	if game.is_inside_tree():
		var ray := PhysicsRayQueryParameters3D.create(pos+Vector3.UP*.025,pos-Vector3.UP*.07,1)
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.normal.y>.8 and hit.collider.get_meta("role","")=="table":return true
	for x in [-6.0,0.0,6.0]:
		if absf(pos.x-x)<2.25 and pos.z> -2.65 and pos.z< -2.38 and absf(pos.y-.785)<.05:return true
	return false
func apply(peer: int,a: Dictionary) -> void:
	var byte_limit := 2004096 if a.get("op")=="notebook" else 64000
	if not identities.has(peer) or a.size()>8 or var_to_bytes(a).size()>byte_limit:return
	var now := Time.get_ticks_msec()
	var recent: Dictionary=last_requests.get(peer,{"time":now,"count":0})
	if now-int(recent.time)>1000:recent={"time":now,"count":0}
	recent.count+=1
	last_requests[peer]=recent
	if recent.count>80:return
	var op := str(a.get("op",""))
	if op in ["drop_floor_lead","pickup_floor_lead"]:
		_move_floor_lead(peer,a)
		return
	if op=="activity":
		if peer==1 and can_choose_next_activity() and int(a.get("expected_epoch",-1))==activity_epoch:
			var response := start_activity(a.get("config",{}))
			if not response.ok:_notice(peer,str(response.error))
		return
	if op=="begin_lesson":return
	if op=="abandon":
		if bool(a.get("confirmed",false)):abandon(peer)
		return
	if op=="replacement":
		if _near(peer,teacher_position):replacement(peer)
		return
	if op=="board_mark":
		_mark_whiteboard(peer,a)
		return
	if DormSupplies.TOOLS.has(op) or op.begins_with("bag:"):
		var dorm = game.get("dorm_interactions")
		var bag: Dictionary={}
		if is_instance_valid(dorm):
			var profile: Dictionary = dorm._profile(dorm.authenticated_identity(peer))
			if op not in profile.get("dorm",{}).get("carry_items",[]):return
			bag=profile.get("dorm",{}).get("backpacks",{}).get(op.trim_prefix("bag:"),{})
		for existing in papers.values():
			if existing.owner==peer and DormSupplies.paper_supply(existing)==op and not existing.get("supply_released",false):
				_notice(peer,"Your item is already in your hotbar.")
				return
		if held(peer)!=0 or _holding_cable(peer) or _holding_kit(peer):return
		if op!="notebook":
			var product: Dictionary=DormSupplies.Backpacks.SIZES.get(bag.get("size",""),{})
			var item_id := _give(peer,{"title":DormSupplies.TOOLS.get(op,product.get("name","Backpack")),"questions":[],"guide_pages":[]},true,false,true)
			if item_id!=0:
				papers[item_id].supply_id=op
				if not bag.is_empty():papers[item_id].supply_model=bag.size
				papers[item_id].calculator=op in DormSupplies.CALCULATORS
				papers[item_id].guide=true
			broadcast()
			return
		var content=a.get("content",{})
		if not preload("res://scripts/notebook_store.gd").valid(content):return
		var note := {"title":"Notebook","topic":0,"difficulty":0,"source":"Personal working notes","questions":[],"theory":"","procedure":"","data":"","seed":0,"guide_pages":[]}
		var pages := clampi(int(content.get("pages",2)),1,100)
		for page in range(pages):note.guide_pages.append({"title":"Notes · %d"%(page+1),"text":""})
		var id := _give(peer,note,true,false,true)
		if id!=0:
			papers[id].guide=true;papers[id].notebook=true
			papers[id].supply_id=op
			papers[id].strokes=content.get("strokes",{}).duplicate(true);papers[id].annotations=content.get("annotations",{}).duplicate(true);papers[id].page=clampi(int(content.get("page",0)),0,pages-1)
	elif op=="guide":
		if not preload("res://scripts/campus/academics/open_lab/tutorials/formal_guide_policy.gd").allowed(mode,activity):return
		if not _near(peer,teacher_position):return
		var id := _give(peer,preload("res://scripts/equipment_guide.gd").project(),true,false)
		if id!=0:papers[id].guide=true
	elif op=="practice_lesson":
		if mode not in ["Open Lab","Freeplay","Creative Freeplay"]:return
		if not game.session.roster.has(peer) or str(identities.get(peer,""))=="":return
		var pose: Variant=game.session.poses.get(peer,{}).get("position")
		if not pose is Vector3:return
		if room_bridge.registry==null:return
		var room_id := str(room_bridge.registry.call("locate",pose))
		if not room_bridge.contains(room_id,pose):return
		var service=preload("res://scripts/campus/academics/open_lab/practice/practice_service.gd")
		var course := service.course_for_room(room_id)
		if course.is_empty():return
		var instructor := teacher_position
		if room_id == "dc_lab" and mode in ["Freeplay", "Creative Freeplay"] and is_instance_valid(game.school_world.dc_instructor):
			instructor = game.school_world.dc_instructor.global_position
		if not _near(peer,instructor):return
		if mode=="Open Lab" and (activity.is_empty() or str(activity.get("course_id",""))!=course or str(activity.get("room",{}).get("id",""))!=room_id):return
		var week: Variant = a.get("week", 0)
		var level: Variant = a.get("difficulty", 2)
		if not week is int or not level is int:return
		var practice: Dictionary=service.issue_for_room(room_id,course_bridge,random.randi(),week,level)
		if practice.has("error"):_notice(peer,str(practice.error));return
		_give(peer,practice,true,false)
	elif op=="study_practice":
		if mode=="Class" or not game.session.roster.has(peer) or str(identities.get(peer,""))=="":return
		var pose: Variant=game.session.poses.get(peer,{}).get("position")
		if not pose is Vector3:return
		if not room_bridge.contains("library",pose) and not room_bridge.contains("study",pose):return
		var course_id := str(a.get("course_id",""))
		if course_id not in ["ELM253","ETY155","MTH147","MTH255"]:return
		var service=preload("res://scripts/campus/academics/open_lab/practice/practice_service.gd")
		var practice: Dictionary=service.issue_for_course(course_id,course_bridge,random.randi())
		if practice.has("error"):_notice(peer,str(practice.error));return
		_give(peer,practice,true,false)
	elif op=="new":
		if mode=="Class":return
		if not _near(peer,teacher_position):return
		var topic := clampi(int(a.get("topic",0)),0,Course.TOPICS.size()-1)
		if bool(a.get("random",false)):topic=random.randi_range(0,Course.TOPICS.size()-1)
		var practice: Dictionary
		if not activity.is_empty() or a.has("course_id"):
			var selected_course := str(a.get("course_id",activity.get("course_id","ELM253")))
			var selected_kind := practice_kind(selected_course)
			var available: Array=course_bridge.weeks(selected_course,selected_kind)
			var selected_week := clampi(int(a.get("week",activity.get("week",1))),1,maxi(1,available.size()))
			if bool(a.get("random",false)):selected_week=random.randi_range(1,maxi(1,available.size()))
			practice=course_bridge.generate(selected_course,selected_week,selected_kind,clampi(int(a.get("difficulty",0)),0,4),random.randi())
		else:practice=Course.generate(topic,clampi(int(a.get("difficulty",0)),0,2),random.randi())
		if practice.is_empty() or practice.has("error"):_notice(peer,"That teaching content is unavailable.");return
		_give(peer,practice,bool(a.get("lesson",false)),false)
	else:
		var id := int(a.get("id",0))
		if not papers.has(id):return
		var paper: Dictionary=papers[id]
		if paper.owner!=peer:return
		var room_class: bool=not str(paper.get("room_class","")).is_empty()
		if room_class and not game.lecture_classes.paper_action_allowed(peer,paper,op):return
		var supply := DormSupplies.paper_supply(paper)
		if not supply.is_empty() and not paper.get("notebook",false) and op not in ["equip_paper","pickup","place","drop","stow","trash"]:return
		if not supply.is_empty() and not paper.get("supply_released",false):
			var dorm = game.get("dorm_interactions")
			if op in ["equip_paper","pickup"] and is_instance_valid(dorm):
				var profile: Dictionary = dorm._profile(dorm.authenticated_identity(peer))
				if supply not in profile.get("dorm",{}).get("carry_items",[]):return
		if _class_assessment(paper) and phase=="assignment" and _assessment_remaining()<=0:
			advance(0)
			if op in ["answer","stroke","annotation","remove_annotation","undo_annotation","redo_annotation","erase_stroke","erase_area","undo_stroke","redo_stroke","erase","submit","procedure","measure"]:return
		if not paper.held and not paper.get("stowed",false) and not _near(peer,paper.position):return
		if not paper.lesson and paper.class_round==round_id and activity.get("kind","")=="lecture" and op in ["answer","stroke","annotation","remove_annotation","undo_annotation","redo_annotation","erase_stroke","erase_area","undo_stroke","redo_stroke","erase","submit"] and not _seated(peer):
			_notice(peer,"Sit at your classroom desk to complete or submit the lecture test.")
			return
		match op:
			"procedure":
				if not paper.mark.is_empty() or not _in_room(peer):return
				var step := str(a.get("step",""))
				if step.length()>80:return
				paper.procedure[step]={"time":Time.get_unix_time_from_system(),"student_reported":true}
			"stow":
				if not paper.held:return
				paper.held=false;paper.stowed=true
			"equip_paper","pickup":
				if held(peer)!=0 or _holding_cable(peer) or _holding_kit(peer):
					_notice(peer,"Put down the item you are holding first.")
					return
				if not supply.is_empty() and paper.get("supply_released",false):
					var reclaimed: Dictionary=game.dorm_interactions.move_world_backpack(peer,supply.trim_prefix("bag:"),true) if supply.begins_with("bag:") else game.dorm_interactions.move_world_supply(peer,supply,true)
					if not reclaimed.ok:_notice(peer,str(reclaimed.error));return
					paper.supply_released=false
					paper.erase("wall_normal")
				paper.held=true;paper.stowed=false
			"place","drop":
				var pos=a.get("position")
				if not paper.held or not pos is Vector3 or not pos.is_finite() or not _near(peer,pos):return
				if op=="drop":
					pos=ground_drop_position(pos,peer)
					if pos==null:return
				elif supply=="whiteboard":
					var normal: Variant=a.get("normal")
					if not normal is Vector3 or not normal.is_finite() or absf(normal.y)>.15 or not is_equal_approx(normal.length(),1.0):return
					var wall_query := PhysicsRayQueryParameters3D.create(pos+normal*.16,pos-normal*.15,1)
					var wall_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(wall_query)
					if wall_hit.is_empty() or wall_hit.normal.dot(normal)<.95:return
					pos=wall_hit.position+normal*.035
				elif supply.begins_with("bag:"):
					var floor_query := PhysicsRayQueryParameters3D.create(pos+Vector3.UP*.10,pos-Vector3.UP*.15,1)
					var floor_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(floor_query)
					if floor_hit.is_empty() or floor_hit.normal.y<.75:return
					pos=floor_hit.position+Vector3.UP*.005
				elif not _table_position(pos,peer):return
				for other in papers.values():
					if not other.held and other.id!=id and other.position.distance_to(pos)<.30:
						_notice(peer,"Choose a clear spot to put the item down.")
						return
				if not supply.is_empty():
					var placed: Dictionary=game.dorm_interactions.move_world_backpack(peer,supply.trim_prefix("bag:"),false,pos) if supply.begins_with("bag:") else game.dorm_interactions.move_world_supply(peer,supply,false)
					if not placed.ok:_notice(peer,str(placed.error));return
					paper.supply_released=true
					if supply=="whiteboard" and op=="place":paper.wall_normal=a.normal
				paper.position=pos
				paper.held=false
			"page":paper.page=clampi(int(a.get("page",0)),0,page_count(paper)-1)
			"notebook_page":
				if not paper.get("notebook",false) or page_count(paper)>=100:return
				var count := page_count(paper)
				paper.project.guide_pages.append({"title":"Notes · %d"%(count+1),"text":""})
				paper.page=count
			"answer":
				if not paper.mark.is_empty():return
				var key := str(a.get("key",""))
				if not key.is_valid_int() or int(key)<0 or int(key)>=paper.project.questions.size():return
				if paper.project.get("course_id", "") in ["MTH147", "MTH255"]:
					var question: Dictionary=paper.project.questions[int(key)]
					var decoded: Dictionary=preload("res://scripts/math_ui/answer_codec.gd").decode(str(a.get("value", "")),str(question.get("id", "")))
					if not decoded.ok:return
					if not paper.get("math_policy",{}).get("formula_allowed",false) and str(decoded.state.get("reference_section", ""))!="":return
					paper.answers[key]=decoded.answer
					if not paper.has("math_ui"):paper.math_ui={}
					paper.math_ui[key]=decoded.state
				else:paper.answers[key]=str(a.get("value","")).left(160)
			"stroke":
				if not can_mark_paper(paper):return
				var points=a.get("points",[])
				if not points is Array or points.size()>256:return
				for point in points:
					if not point is Vector2 or not point.is_finite() or point.x<0 or point.y<0 or point.x>1 or point.y>1:return
				var key := str(clampi(int(a.get("page",0)),0,page_count(paper)-1))
				if not paper.strokes.has(key):paper.strokes[key]=[]
				var color := str(a.get("color","263743"))
				if not Color.html_is_valid(color):return
				var width := float(a.get("width",2.0))
				if not is_finite(width):return
				var raw_hardness = a.get("hardness",1.0);var raw_opacity = a.get("opacity",1.0)
				if not (raw_hardness is int or raw_hardness is float) or not (raw_opacity is int or raw_opacity is float):return
				var hardness := float(raw_hardness);var opacity := float(raw_opacity)
				if not is_finite(hardness) or not is_finite(opacity):return
				if paper.strokes[key].size()<100:
					var stroke := {"points":points,"color":color,"width":clampf(width,1.,32.),"hardness":clampf(hardness,0.,1.),"opacity":clampf(opacity,.05,1.)}
					_remember_paper_edit(paper, "stroke", {"page":key, "index":paper.strokes[key].size(), "stroke":stroke, "added":true})
					paper.strokes[key].append(stroke)
			"annotation":
				if not can_mark_paper(paper):return
				var item=a.get("item",{})
				if not item is Dictionary or item.size()>16:return
				var pos=item.get("position")
				if not pos is Vector2 or not pos.is_finite() or pos.x<0 or pos.y<0 or pos.x>1 or pos.y>1:return
				if str(item.get("id","")).length()>40 or str(item.get("id",""))=="":return
				if item.get("kind") not in ["text","equation"] or item.get("font") not in ["Sans","Serif","Mono"]:return
				if not Color.html_is_valid(str(item.get("color",""))):return
				var angle: Variant=item.get("angle",0.0)
				var font_size: Variant=item.get("font_size",24)
				if not (angle is int or angle is float) or not (font_size is int or font_size is float):
					return
				if not is_finite(float(angle)) or not is_finite(float(font_size)):
					return
				var alignment := str(item.get("align","left"))
				if alignment not in ["left","center","right"]:return
				var opacity := float(item.get("opacity",1.0));var box_width := float(item.get("box_width",280.0))
				if not is_finite(opacity) or not is_finite(box_width):return
				var clean := {"id":str(item.id),"kind":item.kind,"text":str(item.get("text","")).left(256),"position":pos,"font":item.font,"font_size":int(clampf(float(font_size),10,96)),"angle":clampf(float(angle),-PI,PI),"color":item.color,"bold":bool(item.get("bold",false)),"italic":bool(item.get("italic",false)),"align":alignment,"opacity":clampf(opacity,0.05,1.0),"box_width":clampf(box_width,40.0,720.0),"baked":bool(item.get("baked",false))}
				if not paper.has("annotations"):paper.annotations={}
				var key := str(clampi(int(a.get("page",0)),0,page_count(paper)-1))
				if not paper.annotations.has(key):paper.annotations[key]=[]
				var found := false
				for i in paper.annotations[key].size():
					if paper.annotations[key][i].id==clean.id:
						if paper.annotations[key][i].baked:return
						_remember_paper_edit(paper, "annotation", {"page":key,"id":clean.id,"before":paper.annotations[key][i].duplicate(true),"after":clean})
						paper.annotations[key][i]=clean;found=true;break
				if not found and paper.annotations[key].size()<40:
					_remember_paper_edit(paper, "annotation", {"page":key,"id":clean.id,"before":{},"after":clean})
					paper.annotations[key].append(clean)
			"remove_annotation":
				if not can_mark_paper(paper):return
				var key := str(clampi(int(a.get("page",0)),0,page_count(paper)-1))
				if paper.get("annotations",{}).has(key):
					for existing in paper.annotations[key]:
						if existing.id==str(a.get("object","")):
							_remember_paper_edit(paper, "annotation", {"page":key,"id":existing.id,"before":existing.duplicate(true),"after":{}})
							break
					paper.annotations[key]=paper.annotations[key].filter(func(item):return item.id!=str(a.get("object","")))
			"undo_annotation", "redo_annotation":
				if not can_mark_paper(paper):return
				var redo := op == "redo_annotation"
				var entry := _move_paper_edit(paper, "annotation", str(clampi(int(a.get("page",0)),0,page_count(paper)-1)), redo)
				if entry.is_empty():return
				var key := str(entry.page)
				if not paper.annotations.has(key):paper.annotations[key]=[]
				paper.annotations[key]=paper.annotations[key].filter(func(item):return item.id!=entry.id)
				var value: Dictionary = entry.get("after" if redo else "before", {})
				if not value.is_empty():paper.annotations[key].append(value)
			"erase_area":
				if not can_mark_paper(paper):return
				var center: Variant=a.get("point")
				var radius: Variant=a.get("radius")
				if not center is Vector2 or not center.is_finite() or center!=center.clamp(Vector2.ZERO,Vector2.ONE):return
				if not radius is Vector2 or not radius.is_finite() or minf(radius.x,radius.y)<=0 or maxf(radius.x,radius.y)>.25:return
				var key := str(clampi(int(a.get("page",0)),0,page_count(paper)-1))
				var previous: Array=paper.strokes.get(key,[])
				var next := preload("res://scripts/paper_ink.gd").erase_area(previous,center,radius)
				if next==previous or next.size()>100:return
				_remember_paper_edit(paper,"stroke",{"page":key,"before":previous.duplicate(true),"after":next.duplicate(true)})
				paper.strokes[key]=next
			"erase_stroke":
				if not can_mark_paper(paper):return
				var key := str(clampi(int(a.get("page",0)),0,page_count(paper)-1));var index := int(a.get("index",-1))
				if paper.strokes.has(key) and index>=0 and index<paper.strokes[key].size():
					_remember_paper_edit(paper, "stroke", {"page":key,"index":index,"stroke":paper.strokes[key][index],"added":false})
					paper.strokes[key].remove_at(index)
			"undo_stroke", "redo_stroke":
				if not can_mark_paper(paper):return
				var redo := op == "redo_stroke"
				var entry := _move_paper_edit(paper, "stroke", str(clampi(int(a.get("page",0)),0,page_count(paper)-1)), redo)
				if entry.is_empty():return
				var page: Array = paper.strokes.get_or_add(entry.page, [])
				if entry.has("before"):
					paper.strokes[entry.page]=entry["after" if redo else "before"].duplicate(true)
				elif entry.added == redo:
					page.insert(clampi(entry.index, 0, page.size()), entry.stroke)
				elif entry.index in range(page.size()):
					page.remove_at(entry.index)
			"lesson_check":
				if not paper.lesson or paper.get("guide",false):return
				paper.mark=course_bridge.grade(paper.project,paper.answers)
				paper.mark.reason="Practice feedback — excluded from your average."
				_lesson_reward(paper)
			"lesson_retry":
				if paper.lesson:paper.mark={}
			"erase":
				if paper.mark.is_empty():
					var key := str(clampi(int(a.get("page",0)),0,page_count(paper)-1))
					paper.strokes.erase(key)
					paper.get("edit_history", {}).erase("stroke:" + key)
			"trash":
				if not paper.held or not supply.is_empty() or paper.get("notebook",false) or paper.get("calculator",false):return
				if not _trash_near(peer):
					_notice(peer,"Move closer to the paper recycling bin.")
					return
				if _official(paper) and paper.mark.is_empty():
					if not bool(a.get("confirmed",false)):_notice(peer,"Confirm disposal: this active marked assessment will receive 0%.");return
					_mark(paper,false,"Confirmed disposal of active marked assessment.")
				if paper.class_round==round_id and class_students.has(paper.identity):class_students[paper.identity].saved=paper.duplicate(true)
				papers.erase(id)
				_notice(peer,"Sheet recycled." if paper.class_round==0 else "Sheet recycled. Your Class deadline still applies; ask the teacher for a replacement.")
			"measure":
				if not _in_room(peer) or not paper.mark.is_empty():return
				var bench := int(allocation.get(str(paper.identity),{}).get("bench",-1))
				if equipment_adapter!=null and equipment_adapter.has_method("record_measurement"):
					var recorded: bool=equipment_adapter.call("record_measurement",peer,bench,paper.project)
					_notice(peer,"Instrument observation recorded." if recorded else "Check the assigned bench, circuit, meter mode, range and lead connections.")
			"submit":
				if paper.get("guide",false):return
				if not room_class and activity.get("kind","")!="lecture" and (not paper.held or not _near(peer,teacher_position)):return
				if paper.lesson:
					paper.mark=course_bridge.grade(paper.project,paper.answers)
					paper.mark.reason="Practice feedback — excluded from your average."
					_lesson_reward(paper)
					_notice(peer,"Practice checked. Your average is unchanged.")
				else:
					_mark(paper,false)
					if room_class and not paper.mark.is_empty():game.lecture_classes.paper_submitted(paper)
		paper.revision+=1
		_queue_practice_save(paper)
	broadcast()

func _queue_practice_save(paper: Dictionary) -> void:
	if paper.project.get("practice_scope") != "ungraded":return
	var identity := str(paper.get("identity", ""))
	if not identity.is_empty():practice_dirty[identity] = true

func _save_practice(identity: String) -> void:
	if practice_dirty.has(identity) and PracticeSheets.write(identity, papers) == OK:practice_dirty.erase(identity)

func _flush_practice() -> void:
	if not multiplayer.is_server():return
	for identity in practice_dirty.keys():_save_practice(identity)

func _restore_practice(peer: int) -> void:
	if mode not in ["Open Lab", "Freeplay", "Creative Freeplay"]:return
	var identity := str(identities.get(peer, ""))
	if identity.is_empty():return
	for paper in papers.values():
		if paper.owner == peer and paper.project.get("practice_scope") == "ungraded":return
	for draft in PracticeSheets.read(identity):
		draft.id = next_id
		draft.identity = identity
		draft.owner = peer
		draft.owner_name = game.session.roster.get(peer, {}).get("name", "Student")
		draft.held = false
		draft.position = _practice_desk(peer, draft.project)
		draft.lesson = true
		draft.class_round = 0
		draft.assessment_id = ""
		papers[next_id] = draft
		next_id += 1

func _practice_desk(peer: int, project_data: Dictionary) -> Vector3:
	if project_data.get("course_id") == "ETY155":
		return Vector3(-6.0 + 6.0 * posmod(peer, 3), .895, 21.55)
	return _desk(peer)

func _remember_paper_edit(paper: Dictionary, kind: String, change: Dictionary) -> void:
	var all: Dictionary = paper.get_or_add("edit_history", {})
	var history: Dictionary = all.get_or_add(kind + ":" + str(change.page), {"past": [], "future": []})
	history.past.append(change)
	history.future.clear()
	if history.past.size() > 24:history.past.pop_front()

func _move_paper_edit(paper: Dictionary, kind: String, page: String, redo: bool) -> Dictionary:
	var history: Dictionary = paper.get("edit_history", {}).get(kind + ":" + page, {})
	if history.is_empty():return {}
	var source: Array = history.future if redo else history.past
	var target: Array = history.past if redo else history.future
	if source.is_empty():return {}
	var entry: Dictionary = source.pop_back()
	target.append(entry)
	return entry

func replacement(peer: int) -> void:
	var token: String=identities.get(peer,"")
	if mode=="Class" and phase=="assignment" and class_students.has(token) and not class_students[token].done:
		for paper in papers.values():
			if paper.identity==token and paper.class_round==round_id:return
		_give(peer,project,false,true)
		broadcast()
func _mark(paper: Dictionary,expired: bool,zero_reason: String="") -> void:
	if not paper.mark.is_empty():return
	var result := course_bridge.grade(paper.project,paper.answers)
	if result.has("error"):_notice(int(paper.get("owner",1)),str(result.error));return
	if _class_assessment(paper) and paper.project.get("kind","lab")=="lab" and not paper.project.get("practical",{}).is_empty():
		var practical := _practical_mark(paper)
		result.written_score=result.score
		result.practical=practical
		result.score=float(result.score)*.5+float(practical.get("score",0))*.5
	if expired:result.reason="Deadline reached; completed answers marked, unanswered parts receive no credit."
	if zero_reason!="":
		result.score=0.0
		result.reason=zero_reason
	paper.mark=result
	paper.revision+=1
	if _class_assessment(paper) and _replay_paper(paper):
		result.reason = "Replay feedback. Your original grade is preserved."
		_finish_class_paper(paper)
		if int(paper.owner) > 0:
			_notice(int(paper.owner), "Replay feedback: %.1f%%. Your original grade is preserved." % result.score)
		return
	if not _official(paper):return
	var token: String=paper.identity
	var grade_id := GradePolicy.attempt_id(str(paper.get("assessment_id",assessment_id)),token)
	if archive.get(token,{}).has(grade_id) and not archive[token][grade_id].has("pending_assessment_version"):
		_finish_class_paper(paper)
		return
	var record := {"id":grade_id,"profile":token,"title":paper.project.title,"score":result.score,"difficulty":paper.project.get("difficulty",0),"lesson":false,"course_id":paper.project.get("course_id","ELM253"),"kind":paper.project.get("kind","lab"),"week":paper.project.get("week",1),"assessment_id":paper.get("assessment_id",assessment_id),"time":Time.get_datetime_string_from_system(),"reason":result.get("reason","Submitted")}
	record.merge(CourseProgression.record_fields(paper.project),true)
	record.merge(RecordMetadata.from_project(paper.project),true)
	if not archive.has(token):archive[token]={}
	if PendingAssessment.settle(archive,record,_persist_archive)!=OK:
		paper.mark={}
		return
	var owner := int(paper.owner)
	if owner==1:_receive_grade(record)
	elif game.session.online and game.session.roster.has(owner):_receive_grade.rpc_id(owner,record)
	_finish_class_paper(paper)
	_notice(owner,"Marked: %.1f%%. Your sheet has been returned."%result.score)

func _finish_class_paper(paper: Dictionary) -> void:
	var token: String = paper.identity
	if paper.class_round == round_id and class_students.has(token):
		class_students[token].done = true
		class_students[token].saved = paper.duplicate(true)

@rpc("authority","call_remote","reliable",4)
func _receive_grade(record: Dictionary) -> void:
	if record.get("profile", "") != local_identity or gradebook.has(str(record.id)):
		return
	var curriculum_id := str(record.get("gradebook_assessment_id", ""))
	if not curriculum_id.is_empty() and RecordMetadata.is_official_result(record) and not RecordMetadata.first_result(gradebook, local_identity, str(record.course_id), str(record.kind), curriculum_id).is_empty():
		return
	game.sfx.play("mark")
	gradebook[str(record.id)]=record
	_apply_reward(record)
	_save("user://student_grades.json",gradebook)
	academic_records_changed.emit()
	updated.emit()
func course_summary(course_id: String,profile: String="") -> Dictionary:
	return CourseProgression.summary(gradebook,local_identity if profile=="" else profile,course_id,course_bridge)
func menu_catalog(attendance_events: Dictionary={}) -> Dictionary:
	var events := Attendance.private_for_profile(local_attendance,local_identity) if attendance_events.is_empty() else attendance_events
	return CourseProgression.menu_catalog(gradebook,local_identity,course_bridge,events)

func _record_attendance(peer: int) -> void:
	if not multiplayer.is_server() or mode!="Class" or activity.is_empty():return
	var token := str(identities.get(peer,""))
	record_room_attendance(peer,assessment_id,activity,bool(class_start.arrivals.get(token,false)))

func record_room_attendance(peer: int,id: String,assignment: Dictionary,late := false) -> void:
	var token := str(identities.get(peer,""))
	var result := Attendance.record_authoritative(attendance_archive,true,id,token,str(assignment.get("course_id","")),str(assignment.get("kind","")),int(assignment.get("week",0)),Time.get_datetime_string_from_system(),course_ids())
	if not result.get("ok",false):return
	if result.get("created",false):
		result.event["late"]=late
		attendance_archive[result.id]=result.event.duplicate(true)
		_save("user://teacher_attendance.json",attendance_archive)
	if peer==1:_receive_attendance(result.event)
	elif game.session.roster.has(peer):_receive_attendance.rpc_id(peer,result.event)

@rpc("authority","call_remote","reliable",4)
func _receive_attendance(event: Dictionary) -> void:
	if str(event.get("profile",""))!=local_identity or not event.get("id") is String:return
	var id: String=event.id
	if local_attendance.has(id):return
	local_attendance[id]=event.duplicate(true)
	_save("user://student_attendance.json",local_attendance)
	academic_records_changed.emit()
	updated.emit()

func pending_gradebook_records() -> Dictionary:
	var pending := {}
	if mode != "Class" or phase != "assignment" or suspended:
		return pending
	var grade_id := GradePolicy.attempt_id(assessment_id, local_identity)
	if gradebook.has(grade_id):
		return pending
	var archived: Dictionary = archive.get(local_identity, {}).get(grade_id, {})
	if archived.has("pending_assessment_version"):
		pending[grade_id] = archived
		return pending
	for paper in papers.values():
		if paper.owner != multiplayer.get_unique_id() or not _official(paper) or paper.assessment_id != assessment_id or not paper.mark.is_empty():
			continue
		var assignment: Dictionary = paper.project
		var row := {"pending_assessment_version": PendingAssessment.VERSION, "profile": local_identity,
			"course_id": paper.course_id, "kind": paper.kind, "week": assignment.get("week", 1)}
		row.merge(RecordMetadata.from_project(assignment))
		pending[grade_id] = row
		break
	return pending
func course_ids() -> Array[String]:
	var ids: Array[String]=[]
	for course in course_bridge.catalog():
		var id := str(course.get("id",course.get("course_id","")))
		if id!="" and id not in ids:ids.append(id)
	return ids
func practice_kind(course: String) -> String:
	var preferred := str(activity.get("kind","lab"))
	if not course_bridge.weeks(course,preferred).is_empty():return preferred
	return "lecture" if not course_bridge.weeks(course,"lecture").is_empty() else preferred
func average() -> String:
	var parts: Array[String]=[]
	for id in course_ids():
		var value := course_summary(id)
		if value.final_mark!=null:parts.append("%s %.1f%% • %s"%[id,float(value.final_mark),"PASS" if value.passed else "FAIL"])
	return "No marked work yet" if parts.is_empty() else " | ".join(parts)
func _save(path: String,data: Dictionary) -> void:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))
func _enrollment_record(token: String, session_id: String, assignment: Dictionary, is_host: bool) -> Dictionary:
	var record := {"id":GradePolicy.attempt_id(session_id,token),"assessment_id":session_id,"profile":token,"title":str(assignment.get("title","Class assignment")),"course_id":assignment.get("course_id","ELM253"),"kind":assignment.get("kind","lecture"),"week":assignment.get("week",1),"difficulty":assignment.get("difficulty",difficulty),"lesson":false,"time":Time.get_datetime_string_from_system()}
	record["class_authority_role"]="host" if is_host else "guest"
	record.merge(CourseProgression.record_fields(assignment),true)
	var assessment := str(assignment.get("official_curriculum_id", ""))
	if not assessment.is_empty():
		var existing: Dictionary = archive.get(token, {}).get(record.id, {})
		var metadata := RecordMetadata.from_project(existing)
		if metadata.is_empty():
			metadata = RecordMetadata.from_project({
				"course_attempt": RecordMetadata.next_attempt(archive.get(token, {}), token, record.course_id, assessment),
				"gradebook_assessment_id": assessment,
			})
		record.merge(metadata, true)
	return record

func _persist_archive(value: Dictionary) -> Error:
	var path := "user://teacher_records.json"
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value))
	file.flush()
	var error := file.get_error()
	file.close()
	if error!=OK:return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))

func _notice(peer: int,message: String) -> void:
	if peer==multiplayer.get_unique_id():game.ui.log_message(message)
	elif game.session.online and game.session.roster.has(peer):game.session._notice.rpc_id(peer,message)
func _new_round() -> void:
	round_id+=1
	assessment_id=Crypto.new().generate_random_bytes(16).hex_encode()
	project=Course.generate(random.randi_range(0,Course.TOPICS.size()-1),difficulty,random.randi())
	class_students.clear()
	for token in identities.values():class_students[token]={"done":false}
	phase="lesson"
	remaining=teaching_seconds
	teacher_position=Vector3(-2,0,8.3)
	teacher_yaw=0
func _academic_now() -> float:
	return Time.get_unix_time_from_system()

func _assessment_remaining() -> float:
	# Keep the original wall-clock deadline authoritative, including between frames.
	return minf(remaining,maxf(0,assessment_deadline-_academic_now())) if assessment_deadline>0 else remaining

func advance(delta: float) -> void:
	if mode!="Class" or suspended or phase in ["travel","complete"]:return
	remaining=maxf(0,remaining-maxf(0,delta))
	if phase=="assignment":remaining=_assessment_remaining()
	if phase=="assignment" and not class_students.is_empty() and class_students.values().all(func(student):return student.done):remaining=0
	if remaining>0:return
	if phase=="break":
		_new_round()
	elif phase=="lesson":
		phase="assignment"
		remaining=assessment_seconds
		assessment_deadline=_academic_now()+remaining
		for peer in identities:
			if class_students.has(identities[peer]):_give(peer,project,false,true)
	elif phase=="assignment":
		for token in class_students:
			if class_students[token].done:continue
			var found := false
			for paper in papers.values():
				if paper.identity==token and paper.class_round==round_id:
					_mark(paper,true)
					found=true
			if not found:
				var lost: Dictionary=class_students[token].get("saved",{"id":-round_id,"identity":token,"owner":0,"project":_individual_project(token),"answers":{},"mark":{},"revision":0,"class_round":round_id,"assessment_id":assessment_id,"lesson":false})
				_mark(lost,true)
		phase="complete" if not activity.is_empty() else "break"
		remaining=0 if not activity.is_empty() else 60
		activity_completed.emit()
	broadcast()
	checkpoint()
func _process(delta: float) -> void:
	if game==null or not multiplayer.has_multiplayer_peer():return
	if multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED or not multiplayer.is_server():return
	practice_save_clock += delta
	if practice_save_clock >= 1.25:
		practice_save_clock = 0.0
		_flush_practice()
	if phase=="travel" and not suspended:
		var now_usec := Time.get_ticks_usec()
		remaining=class_start.remaining(now_usec)
		if class_start.begin_if_due(now_usec):
			phase="lesson"
			remaining=teaching_seconds
			for peer in identities:_record_attendance(int(peer))
			broadcast()
			checkpoint()
	if not game.front.in_game:return
	advance(delta)
	if phase=="lesson" and str(activity.get("course_id","")).begins_with("MTH"):
		var stage_key: String=assessment_id+":"+str(teaching_stage().get("index",0))
		if stage_key!=released_teaching_stage:released_teaching_stage=stage_key;broadcast()
	recovery_clock+=delta
	if recovery_clock>=1.0:
		recovery_clock=0
		checkpoint()
	if mode in ["Freeplay","Creative Freeplay"] and activity.is_empty():
		var offset := teacher_goal-teacher_position
		if offset.length()<.15:teacher_goal=Vector3(random.randf_range(-3,3),0,random.randf_range(2.5,8))
		elif not game.session.poses.values().any(func(p):return p.get("position",Vector3.ZERO).distance_to(teacher_position)<2.2):
			teacher_position+=offset.normalized()*minf(delta*.55,offset.length())
			teacher_yaw=atan2(-offset.x,-offset.z)
	sync_clock+=delta
	if sync_clock>=.25:
		sync_clock=0
		if _sync_supply_world():broadcast()
		else:updated.emit()
		if game.session.online:
			for peer in game.session.connected_peers():_motion.rpc_id(peer,teacher_position,teacher_yaw,remaining)
@rpc("authority","call_remote","unreliable_ordered",5)
func _motion(pos: Vector3,yaw: float,time_left: float) -> void:
	teacher_position=pos
	teacher_yaw=yaw
	remaining=time_left
	updated.emit()
func _public_presentation() -> Dictionary:
	if not str(activity.get("course_id","")).begins_with("MTH"):return presentation.duplicate(true)
	# Never transmit future worked solutions or the host's private practice key.
	var safe := {"title":presentation.get("title",""),"course_id":activity.get("course_id",""),"duration_seconds":teaching_seconds,"current_only":true,"stages":[]}
	if phase=="lesson":safe.stages=[teaching_stage().duplicate(true)]
	return safe
func _public_project(assignment: Dictionary,marked: bool=false) -> Dictionary:
	var cache_key := ""
	if str(assignment.get("course_id","")).begins_with("MTH"):
		var ids: Array=[]
		for question in assignment.get("questions",[]):ids.append(str(question.get("id","")))
		cache_key=JSON.stringify([assignment.get("course_id"),assignment.get("version",0),assignment.get("seed",""),ids,assignment.get("lesson_stages",[]).size(),marked])
		if public_math_projects.has(cache_key):return public_math_projects[cache_key].duplicate(true)
	var copy := assignment.duplicate(true)
	if not copy.has("questions"):copy.questions=[]
	copy=course_bridge.public_copy(copy,marked)
	if not marked:
		for key in ["practical","reference_parts","reference_result","reference_ac","answer_key","solution","rubric","netlist","expected","validation"]:copy.erase(key)
	if cache_key!="":
		if public_math_projects.size()>=128:public_math_projects.erase(public_math_projects.keys()[0])
		public_math_projects[cache_key]=copy.duplicate(true)
	return copy
func _public_state(recipient: int) -> Dictionary:
	var visible_papers := {}
	for id in papers:
		var source: Dictionary=papers[id]
		var paper: Dictionary=source.duplicate(false)
		paper.erase("identity");paper.erase("project")
		if paper.owner!=recipient:
			paper.answers={};paper.strokes={};paper.annotations={};paper.mark={};paper.erase("procedure");paper.erase("math_ui");paper.erase("annotation_history")
		paper=paper.duplicate(true)
		paper.project=_public_project(source.project,(not source.mark.is_empty() or source.lesson) and source.owner==recipient)
		if source.owner != recipient:
			paper.erase("replay")
		if source.owner == recipient and _official(source):
			paper.project = paper.project.duplicate()
			paper.project.merge(RecordMetadata.from_project(source.project), true)
		paper.erase("edit_history")
		visible_papers[id]=paper
	return {"papers":visible_papers,"floor_leads":floor_leads,"worn_gear":worn_gear,"mode":mode,"phase":phase,"remaining":remaining,"round":round_id,"teacher_position":teacher_position,"teacher_yaw":teacher_yaw,"project":_public_project(project),"activity":activity,"presentation":_public_presentation(),"assessment_id":assessment_id,"deadline":assessment_deadline,"suspended":suspended,"allocation":{}}
func broadcast() -> void:
	if not multiplayer.is_server():return
	updated.emit()
	if game.session.online:
		for peer in game.session.roster:
			if int(peer)!=1 and (not game.session.has_method("peer_connected_now") or game.session.peer_connected_now(int(peer))):_snapshot.rpc_id(int(peer),_public_state(int(peer)))
@rpc("authority","call_remote","reliable",4)
func _snapshot(data: Dictionary) -> void:
	papers=data.papers
	floor_leads=data.get("floor_leads",{})
	worn_gear=data.get("worn_gear",{})
	mode=data.mode
	phase=data.phase
	remaining=data.remaining
	round_id=data.round
	teacher_position=data.teacher_position
	teacher_yaw=data.teacher_yaw
	project=data.project
	activity=data.get("activity",{})
	presentation=data.get("presentation",{})
	assessment_id=data.get("assessment_id","")
	assessment_deadline=float(data.get("deadline",0))
	suspended=bool(data.get("suspended",false))
	updated.emit()

func _lesson_reward(paper: Dictionary) -> void:
	if str(paper.get("project",{}).get("practice_scope",""))=="ungraded":return
	if mode=="Creative Freeplay":return
	var token := str(paper.identity)
	var key := "lesson:"+token+":"+str(paper.project.get("course_id","ELM253"))+":"+str(paper.project.get("week",paper.project.get("topic",0)))+":"+str(paper.project.get("difficulty",0))
	if archive.get(token,{}).has(key):return
	var record := {"id":key,"profile":token,"title":paper.project.title,"score":paper.mark.score,"difficulty":paper.project.get("difficulty",0),"lesson":true,"time":Time.get_datetime_string_from_system()}
	if not archive.has(token):archive[token]={}
	archive[token][key]=record;_save("user://teacher_records.json",archive)
	if int(paper.owner)==1:_receive_grade(record)
	elif game.session.online and game.session.roster.has(paper.owner):_receive_grade.rpc_id(paper.owner,record)
func _apply_reward(record: Dictionary) -> void:
	if not is_instance_valid(game.electronics) or record.profile!=local_identity:return
	var difficulty := int(record.get("difficulty",0));var lesson := bool(record.get("lesson",false))
	var maximum := (10 if lesson else 60)*(clampi(difficulty,0,2)+1)
	var earned: int=game.electronics.profile.reward(str(record.id),float(record.score),difficulty,lesson)
	if earned>0:game.ui.log_message("%.1f%% · earned $%d of $%d%s"%[record.score,earned,maximum," · practice does not affect your average" if lesson else ""])

func _holding_kit(peer: int) -> bool:
	if is_instance_valid(game.dc_lab) and game.dc_lab.held_board(peer)>=0:return true
	return is_instance_valid(game.kit_world) and game.kit_world.kits.get(peer,{}).get("held",false)

func configure_campus(registry: Object=null,provider: Object=null,equipment: Object=null) -> void:
	room_bridge=preload("res://scripts/campus/academics/room_bridge.gd").new(registry)
	course_bridge=preload("res://scripts/campus/academics/course_bridge.gd").new(provider)
	if equipment!=null:equipment_adapter=equipment

func formal_active() -> bool:
	return mode=="Class" and phase in ["travel","lesson","assignment"]

func can_choose_next_activity() -> bool:
	return multiplayer.is_server() and ((mode in ["Freeplay","Creative Freeplay"] and phase=="freeplay") or (mode=="Class" and phase=="complete"))

func official_extra_assessments(course: String) -> Array[Dictionary]:
	return RecordMetadata.extra_options(GradeWeights.course(course), course_bridge, course)

func start_activity(config: Dictionary) -> Dictionary:
	if not multiplayer.is_server():return {"ok":false,"error":"Only the host chooses the activity."}
	if game.front.in_game and not can_choose_next_activity():return {"ok":false,"error":"The next activity is available to the host in Freeplay or after class ends."}
	var selected := str(config.get("mode","Freeplay"))
	var course := str(config.get("course_id","ELM253"))
	var kind := str(config.get("kind","lecture"))
	if selected=="Open Lab":kind="lab"
	var week := int(config.get("week",1))
	var level := int(config.get("difficulty",2))
	if selected not in ["Freeplay","Open Lab","Course"] or course not in course_ids() or kind not in ["lecture","lab"] or level<0 or level>4:
		return {"ok":false,"error":"Invalid activity selection."}
	if selected=="Freeplay":
		start("Creative Freeplay" if bool(config.get("creative",false)) else "Freeplay",level)
		teacher_position=Vector3(0,0,5);teacher_goal=Vector3(2,0,4)
		activity_started.emit(room_bridge.point(room_bridge.registry.data.entrance) if room_bridge.registry!=null else Vector3(13,0,-18))
		return {"ok":true,"error":""}
	var options := official_extra_assessments(course) if selected == "Course" else []
	var requested_id := str(config.get("gradebook_assessment_id", ""))
	var extra: Dictionary = {}
	if not requested_id.is_empty():
		for option in options:
			if option.id == requested_id:
				extra = option
				break
		if extra.is_empty():return {"ok":false,"error":"That assessment is not configured."}
		kind = extra.kind
		week = extra.content_week
	var weeks: Array=course_bridge.weeks(course,kind)
	if week<1 or week>weeks.size():return {"ok":false,"error":"That week is not implemented."}
	var lecture_room := str(config.get("lecture_room","")) if kind=="lecture" and selected!="Open Lab" else ""
	var room: Dictionary=room_bridge.room(course,"lab" if selected=="Open Lab" else kind,lecture_room)
	if room.is_empty():return {"ok":false,"error":"The campus room registry is required for this activity."}
	var lesson_time := float(config.get("teaching_seconds",420))
	var test_time := float(config.get("assessment_seconds",1800))
	if not is_finite(lesson_time) or not is_finite(test_time):return {"ok":false,"error":"Invalid class duration."}
	var assignment: Dictionary=course_bridge.generate(course,week,kind,level,random.randi())
	if assignment.is_empty() or assignment.has("error"):return {"ok":false,"error":str(assignment.get("error","Course content is unavailable."))}
	if selected == "Course":
		assignment.official_curriculum_id = requested_id if not extra.is_empty() else "%s:%d" % [kind, week]
		if not extra.is_empty():
			assignment.title = extra.title
			assignment.official_assessment_title = extra.title
	# A practical capability gate must not silently become a written-only official lab.
	if selected=="Course" and kind=="lab" and assignment.get("practical",{}).get("blocked",false):
		return {"ok":false,"error":str(assignment.practical.get("reason","Required practical equipment is unavailable."))}
	if selected=="Course" and kind=="lab" and not assignment.get("practical",{}).is_empty() and equipment_adapter!=null and equipment_adapter.has_method("supports"):
		var capability: Dictionary=equipment_adapter.call("supports",assignment)
		if not capability.get("ok",false):return capability
	var next_assessment_id := Crypto.new().generate_random_bytes(16).hex_encode()
	if selected=="Course":
		var enrollment: Array[Dictionary]=[]
		var profiles: Array=identities.values().duplicate()
		if local_identity not in profiles:profiles.append(local_identity)
		for profile in profiles:
			if str(profile).is_empty():return {"ok":false,"error":"A validated student identity is required."}
			if not _is_replay(str(profile), assignment):
				enrollment.append(_enrollment_record(str(profile),next_assessment_id,assignment,str(profile)==str(identities.get(1,local_identity))))
		if not enrollment.is_empty() and PendingAssessment.enroll(archive,enrollment,_persist_archive)!=OK:return {"ok":false,"error":"Class enrollment could not be saved. Class has not started."}
	_clear_earthing_demo()
	class_start.cancel()
	activity_epoch+=1
	_flush_practice()
	papers.clear()
	class_students.clear()
	round_id+=1
	assessment_id=next_assessment_id
	assessment_deadline=0
	teaching_seconds=clampf(lesson_time,300,600)
	assessment_seconds=clampf(test_time,1,7200)
	difficulty=level
	mode="Class" if selected=="Course" else selected
	phase="travel" if selected=="Course" else "practice" if selected=="Open Lab" else "freeplay"
	remaining=0
	suspended=false
	project=assignment
	if course.begins_with("MTH"):
		if not project.has("assessment_policy"):project.assessment_policy={}
		for permission in ["formula_allowed","calculator_allowed"]:
			project.assessment_policy[permission]=config.get(permission,false) is bool and bool(config.get(permission,false))
	project.assessment_id=assessment_id
	activity={"mode":selected,"course_id":course,"kind":kind,"week":week,"difficulty":level,"room":room,"creative":bool(config.get("creative",false)),"teaching_seconds":teaching_seconds,"assessment_seconds":assessment_seconds}
	presentation=course_bridge.lesson_for_assignment(assignment,teaching_seconds)
	teacher_position=room_bridge.point(room.get("teacher_position",Vector3.ZERO))
	if not identities.has(1):_identify(1,local_identity)
	if selected=="Course":
		for token in identities.values():
			class_students[token]={"done":false,"replay":_is_replay(token, project)}
			if _individual_project(token).is_empty():return {"ok":false,"error":"Individual assessment generation failed."}
	allocation=Benches.allocate(class_students.keys()) if kind=="lab" else {}
	if selected=="Course":
		class_start.arm(assessment_id,Time.get_ticks_usec())
		for token in class_students:class_start.arrive(str(token),Time.get_ticks_usec())
		remaining=class_start.remaining(Time.get_ticks_usec())
	for peer in identities:_give_slip(int(peer))
	activity_started.emit(room_bridge.point(room.get("entrance",Vector3.ZERO)))
	broadcast()
	checkpoint()
	return {"ok":true,"error":"","activity":activity.duplicate(true)}

func _give_slip(peer: int) -> void:
	if activity.is_empty():return
	var room: Dictionary=activity.room
	var title := "Open Lab room slip" if mode=="Open Lab" else "Classroom assignment"
	var lines := "%s · %s\nBuilding %s · Floor %s\n%s\n%s · Week %d\nPractice only — no official marks."%[str(room.get("number",room.get("room_number",""))),str(room.get("name","")),str(room.get("building","")),str(room.get("floor","")),str(room.get("directions","Follow the hallway signs.")),str(activity.course_id),int(activity.week)]
	if mode=="Class":lines=lines.replace("Practice only — no official marks.","Walk to the assigned room. Teaching begins automatically two minutes after Class starts.")
	var token := str(identities.get(peer,""))
	if allocation.has(token):lines+="\nAssigned laboratory bench %d. Share this group's real circuit; record and submit your own answers."%(int(allocation[token].bench)+1)
	var pages: Array=[]
	for i in range(4):pages.append({"title":title,"text":lines})
	var slip := {"title":title,"topic":0,"difficulty":0,"source":"Campus room registry","questions":[],"theory":"","procedure":"","data":"","seed":0,"guide_pages":pages}
	var id := _give(peer,slip,true,false)
	if id!=0:papers[id].guide=true;papers[id].room_slip=true

func _in_room(peer: int) -> bool:
	if activity.is_empty():return true
	return room_bridge.contains(str(activity.room.id),game.session.poses.get(peer,{}).get("position",Vector3.INF))

func _trash_near(peer: int) -> bool:
	for bin in get_tree().get_nodes_in_group("paper_recycling"):
		if _near(peer,bin.global_position):return true
	return false

func _seated(peer: int) -> bool:
	if not _in_room(peer):return false
	# Chair occupancy is host-owned; the client's pose.seated flag is insufficient.
	for chair in game.chairs:
		if int(chair.occupant)==peer:
			if activity.is_empty():return true
			return room_bridge.contains(str(activity.room.id),chair.position)
	return false

func begin_lesson() -> bool:
	# Legacy callers cannot start scheduled teaching early.
	return false

func teaching_stage() -> Dictionary:
	if presentation.get("current_only",false):return presentation.get("stages",[{}])[0] if not presentation.get("stages",[]).is_empty() else {}
	var stages: Array=presentation.get("stages",[])
	if stages.is_empty():
		stages=[{"title":"Theory","text":project.get("theory",""),"duration":teaching_seconds/3},{"title":"Worked quantities","text":project.get("data",""),"duration":teaching_seconds/3},{"title":"Procedure","text":project.get("procedure",""),"duration":teaching_seconds/3}]
	var elapsed := maxf(0,teaching_seconds-remaining)
	var cursor := 0.0
	for i in stages.size():
		var stage: Dictionary=stages[i]
		cursor+=float(stage.get("duration_seconds",stage.get("duration",teaching_seconds/maxi(1,stages.size()))))
		if elapsed<cursor or i==stages.size()-1:
			var result := stage.duplicate(true)
			result.index=i;result.count=stages.size()
			return result
	return {}

static func can_mark_paper(paper: Dictionary) -> bool:
	return paper.get("mark",{}).is_empty() or bool(paper.get("lesson",false)) and int(paper.get("class_round",0))==0

func _class_assessment(paper: Dictionary) -> bool:
	return not bool(paper.get("lesson",true)) and int(paper.get("class_round",0))!=0 and str(paper.get("project",{}).get("practice_scope",""))!="ungraded"

func _replay_paper(paper: Dictionary) -> bool:
	return bool(paper.get("replay", false)) or bool(class_students.get(paper.get("identity", ""), {}).get("replay", false))

func _official(paper: Dictionary) -> bool:
	return _class_assessment(paper) and not _replay_paper(paper)

func _is_replay(token: String, assignment: Dictionary) -> bool:
	var id := str(assignment.get("official_curriculum_id", ""))
	if id.is_empty():
		return false
	var course := str(assignment.get("course_id", ""))
	var kind := str(assignment.get("kind", ""))
	if token == local_identity and not RecordMetadata.first_result(gradebook, token, course, kind, id).is_empty():
		return true
	return not RecordMetadata.first_result(archive.get(token, {}), token, course, kind, id).is_empty()

static func page_count(paper: Dictionary) -> int:
	if paper.get("project",{}).get("course_id", "") in ["MTH147", "MTH255"]:
		var lessons: int=paper.project.get("lesson_stages",[]).size() if paper.get("lesson",false) else 0
		return paper.project.get("questions",[]).size()+(lessons+1 if lessons>0 else 2)
	if paper.get("guide",false):return maxi(1,int(paper.get("project",{}).get("guide_pages",[]).size()))
	return 4+paper.get("project",{}).get("practice_instruction_pages",[]).size()

func equipment_access(peer: int,bench: int,domain: String="") -> bool:
	if not multiplayer.is_server():return false
	if not formal_active():return true
	if domain!="" and activity.get("kind","")=="lab" and domain!=activity.get("course_id",""):return false
	if allocation.is_empty():return true
	return Benches.permits(allocation,str(identities.get(peer,"")),bench)

func observe_equipment_action(peer: int,bench: int,op: String,before_parts: Array) -> void:
	if not multiplayer.is_server() or not formal_active() or not equipment_access(peer,bench):return
	if equipment_adapter==null or not equipment_adapter.has_method("observe_action"):return
	for paper in papers.values():
		if paper.owner==peer and _class_assessment(paper) and paper.mark.is_empty():
			equipment_adapter.call("observe_action",peer,bench,paper.project,op,before_parts)
			return

func _practical_mark(paper: Dictionary) -> Dictionary:
	var token := str(paper.identity)
	var bench := int(allocation.get(token,{}).get("bench",-1))
	if equipment_adapter!=null and equipment_adapter.has_method("capture") and equipment_adapter.has_method("grade"):
		var evidence: Dictionary=equipment_adapter.call("capture",int(paper.owner),bench,paper.project)
		return equipment_adapter.call("grade",paper.project,evidence,paper.get("procedure",{}))
	return {"score":0.0,"verified":false,"reason":"Host equipment evidence adapter is unavailable; no practical credit fabricated."}

func abandon(peer: int) -> void:
	if not multiplayer.is_server():return
	var token := str(identities.get(peer,""))
	if not formal_active() or not class_students.has(token):return
	# At the deadline, timeout credit wins over a later abandonment request.
	if phase=="assignment" and _assessment_remaining()<=0:
		advance(0)
		return
	if bool(class_students[token].done):return
	for paper in papers.values():
		if _class_assessment(paper) and paper.identity==token and paper.class_round==round_id:
			_mark(paper,false,"Intentional abandonment of active marked assessment.")
			broadcast();checkpoint();return
	# Only an issued assessment carries an abandonment penalty. Travel and teaching do not.
	if phase!="assignment":return
	var missing: Dictionary=class_students[token].get("saved",{"id":-round_id,"identity":token,"owner":peer,"project":_individual_project(token),"answers":{},"mark":{},"revision":0,"class_round":round_id,"assessment_id":assessment_id,"lesson":false})
	_mark(missing,false,"Intentional abandonment of active marked assessment.")
	broadcast();checkpoint()

func _fail_departing(token: String, peer: int) -> void:
	if not multiplayer.is_server() or mode!="Class" or phase not in ["travel","lesson","assignment"]:return
	if token.is_empty() or not class_students.has(token) or bool(class_students[token].get("done",false)):return
	if bool(class_students[token].get("replay", false)):
		class_students[token].done = true
		return
	var id := GradePolicy.attempt_id(assessment_id,token)
	if archive.get(token,{}).has(id) and not archive[token][id].has("pending_assessment_version"):
		class_students[token].done=true
		return
	var assigned: Dictionary=_individual_project(token)
	if assigned.is_empty():assigned=project
	if assigned.is_empty():return
	var record := {"id":id,"profile":token,"title":str(assigned.get("title","Class assignment")),"score":0.0,"difficulty":assigned.get("difficulty",difficulty),"lesson":false,"course_id":assigned.get("course_id",activity.get("course_id","ELM253")),"kind":assigned.get("kind",activity.get("kind","lecture")),"week":assigned.get("week",activity.get("week",1)),"assessment_id":assessment_id,"time":Time.get_datetime_string_from_system(),"reason":"Left class before completing the assigned assessment."}
	record.merge(CourseProgression.record_fields(assigned),true)
	record.merge(RecordMetadata.from_project(assigned),true)
	if not archive.has(token):archive[token]={}
	if PendingAssessment.settle(archive,record,_persist_archive)!=OK:return
	class_students[token].done=true
	class_students[token].erase("saved")
	if peer==1:_receive_grade(record)
	elif game.session.online and game.session.roster.has(peer):_receive_grade.rpc_id(peer,record)

func checkpoint() -> void:
	# Class sessions are not resumable. Official marks are stored separately.
	return

func recover_activity() -> Dictionary:
	return {"ok":false,"error":"Saved class sessions cannot be resumed."}

func suspend_for_host_loss() -> void:
	# No peer is promoted to authoritative host. Client copy remains read-only evidence.
	suspended=true
	updated.emit()

func _deliver_host_departure_grade() -> void:
	for record in archive.get(local_identity,{}).values():
		if not record is Dictionary or record.get("class_authority_role")!="host" or record.get("profile")!=local_identity:continue
		if record.get("reason")!="Hosted class ended before the assignment was completed." or not record.has("score"):continue
		if not gradebook.has(str(record.get("id",""))):_receive_grade(record)

func prepare_host_exit(intentional: bool) -> void:
	if multiplayer.is_server():
		if intentional:
			host_departure_in_progress=true
			if formal_active() and not assessment_id.is_empty():
				if PendingAssessment.end_host_session(archive,_persist_archive,assessment_id)==OK:
					_deliver_host_departure_grade()
				else:push_warning("Could not close class records. The archive will be retried on the next launch.")
	else:suspend_for_host_loss()

func _session_leaving() -> void:
	_flush_practice()
	if not game.front.in_game:return
	if game.session.get_meta("lost_authority",false):suspend_for_host_loss()
	else:prepare_host_exit(multiplayer.is_server())

func _clear_earthing_demo() -> void:
	for lab in game.session.labs:
		if not lab.protective_earth_profile.is_empty():
			lab.powered=false;lab.configure_protective_earth({})
