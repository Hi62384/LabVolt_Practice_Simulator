extends SceneTree
const School = preload("res://scripts/school_session.gd")
const Policy = preload("res://scripts/campus/academics/grade_policy.gd")
const Evidence = preload("res://scripts/campus/academics/equipment_evidence.gd")
const Allocator = preload("res://scripts/campus/academics/bench_allocator.gd")
var failures := 0
var checks := 0
class SessionStub extends Node:
	signal roster_changed
	signal restarted
	signal leaving
	var roster := {1:{"name":"A"},2:{"name":"B"}}
	var poses := {1:{"position":Vector3.ZERO},2:{"position":Vector3.ZERO}}
	var labs: Array=[]
	var online := false
	@rpc("authority","call_remote","reliable")
	func _notice(_message: String) -> void:pass
class UiStub extends Node:
	func log_message(_message: String) -> void:pass
class SoundStub extends Node:
	func play(_sound: String) -> void:pass
class FrontStub extends RefCounted:
	var in_game := false
class GameStub extends Node:
	var session=SessionStub.new()
	var ui=UiStub.new()
	var sfx=SoundStub.new()
	var front=FrontStub.new()
	var chairs: Array=[]
	var dc_lab: Node
	var kit_world: Node
	var electronics: Node
class DcStub extends Node:
	var benches: Array=[]
class RoomStub extends RefCounted:
	func activity_room(_course: String,_kind: String) -> Dictionary:
		return {"id":"fixture","number":"T1","building":"Test","floor":0,"name":"Test room","teacher_position":Vector3.ZERO,"entrance":Vector3(0,0,-10),"desks":[Vector3(0,.895,1)]}
	func room_contains(_id: String,position: Vector3) -> bool:return position.length()<5
class ProviderStub extends RefCounted:
	func weeks(_course: String,_kind: String) -> Array:
		var result: Array=[]
		for i in 12:result.append({"week":i+1,"title":"Fixture"})
		return result
	func generate(course: String,week: int,kind: String,difficulty: int,seed_value: int) -> Dictionary:
		return {"course_id":course,"week":week,"kind":kind,"difficulty":difficulty,"title":"Verified fixture","topic":0,"seed":seed_value,"theory":"Ohm's law","data":"10 V, 1 kΩ","procedure":"Wire with power off","source":"test","questions":[{"prompt":"I","answer":.01,"options":[],"unit":"A","explanation":"10/1000"},{"prompt":"P","answer":.1,"options":[],"unit":"W","explanation":"VI"}]}
	func lesson(_course: String,_week: int,_kind: String,duration: int) -> Dictionary:
		return {"stages":[{"title":"First","text":"V=IR","duration_seconds":duration/2},{"title":"Second","text":"P=VI","duration_seconds":duration-duration/2}]}
	func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
		return preload("res://scripts/course_generator.gd").grade(assignment,answers)

func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error("FAIL: "+label)
	else:print("PASS: "+label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := GameStub.new();root.add_child(game)
	game.add_child(game.session);game.add_child(game.ui);game.add_child(game.sfx)
	var school := School.new();game.add_child(school);school.game=game
	var token := "a".repeat(48);var other := "b".repeat(48)
	school.local_identity=token;school.identities={1:token,2:other}
	school.configure_campus(RoomStub.new(),ProviderStub.new())
	var config := {"mode":"Course","course_id":"ETY155","kind":"lab","week":4,"difficulty":4,"teaching_seconds":300,"assessment_seconds":1800}
	check(school.start_activity(config).ok,"Start ETY155 through shared flow")
	check(school.phase=="travel" and school.remaining==0,"Walking phase is untimed")
	check(school.papers.values().all(func(p):return p.lesson and p.get("room_slip",false)),"Physical room slips are practice-only")
	check(not school.start_activity({"mode":"Freeplay"}).ok,"Active formal class blocks ordinary switching")
	check(school.begin_lesson(),"Host starts when students reach room")
	check(school.teaching_stage().title=="First","Timeline begins correct stage")
	school.advance(151)
	check(school.teaching_stage().title=="Second","Timeline advances from synchronized elapsed time")
	school.advance(149)
	check(school.phase=="assignment" and school.remaining==1800,"Teaching issues timed assessment")
	var deadline: float=school.assessment_deadline
	var official: Array=school.papers.values().filter(func(p):return not p.lesson)
	check(official.size()==2,"One official sheet per participant")
	official[0].answers={"0":"0.01"}
	school._mark(official[0],true)
	check(is_equal_approx(float(official[0].mark.score),50),"Timeout retains completed credit and zeros unanswered parts")
	school._mark(official[0],true)
	check(school.archive[token].size()==1,"Duplicate marking is idempotent")
	school.abandon(2)
	check(float(official[1].mark.score)==0,"Intentional active abandonment is zero")
	school.advance(0)
	check(school.phase=="complete","All submitted or abandoned completes class")
	check(school.course_summary("ELM253").overall==null,"ETY155 never changes ELM253 marks")
	check(school.course_summary("ETY155").lecture==null,"Unattempted lecture category is missing, not zero")
	check(is_equal_approx(float(school.course_summary("ETY155").overall),50),"Missing category is omitted from overall")
	var records := {"a":{"profile":token,"course_id":"ETY155","kind":"lecture","score":100},"b":{"profile":token,"course_id":"ETY155","kind":"lab","score":50},"c":{"profile":token,"course_id":"ELM253","kind":"lab","score":12},"d":{"profile":token,"course_id":"ETY155","kind":"lab","score":0,"lesson":true}}
	check(Policy.summary(records,token,"ETY155").overall==75.0,"Equal weighting separates categories and excludes practice")
	check(Policy.summary(records,token,"ETY155",{"lecture":1,"lab":3}).overall==62.5,"Configurable course weighting")
	check(school.start_activity({"mode":"Open Lab","course_id":"ETY155","kind":"lab","week":1}).ok,"Open Lab uses same course architecture")
	var practice_id: int=school._give(1,ProviderStub.new().generate("ETY155",1,"lab",0,1),true,false)
	var count: int=school.gradebook.size()
	school.papers[practice_id].answers={"0":".01","1":".1"}
	school._mark(school.papers[practice_id],false)
	check(school.gradebook.size()==count,"Practice cannot enter official gradebook")
	check(school.start_activity(config).ok,"Repeated week creates a fresh attempt")
	school.begin_lesson();school.advance(300)
	deadline=school.assessment_deadline
	var paper: Dictionary=school.papers.values().filter(func(p):return not p.lesson and p.owner==1)[0]
	paper.answers={"0":".01"};paper.strokes={"0":[{"points":[Vector2(.1,.2)],"width":2,"color":"263743"}]}
	school.checkpoint()
	var fresh := School.new();game.add_child(fresh);fresh.game=game;fresh.local_identity=token;fresh.identities={1:token};fresh.configure_campus(RoomStub.new(),ProviderStub.new())
	check(fresh.recover_activity().ok,"Trusted host recovers local journal")
	check(fresh.assessment_deadline==deadline,"Recovery preserves original deadline")
	check(fresh.papers.values().any(func(p):return p.get("answers",{}).get("0","")==".01" and not p.strokes.is_empty()),"Recovery restores answers and ink")
	var visible: Dictionary=fresh._public_state(2)
	check(visible.papers.values().all(func(p):return p.owner==2 or p.answers.is_empty()),"Other students' answers are private")
	for p in fresh.papers.values():p.project.reference_result={"answer":42};p.project.reference_parts=[{"secret":true}]
	check(fresh._public_state(2).papers.values().all(func(p):return not p.project.has("reference_result") and not p.project.has("reference_parts")),"Private solver answer keys never broadcast")
	var allocation := Allocator.allocate(["a","b","c","d","e","f","g","h"])
	check(allocation.size()==8 and allocation.values().all(func(a):return int(a.bench)>=0 and int(a.bench)<3),"Eight students use three real bench groups")
	check(Allocator.permits(allocation,"a",0) and not Allocator.permits(allocation,"a",1),"Unrelated groups cannot edit assigned benches through guard")
	var evidence := Evidence.new()
	var parts := [{"id":"Vs","kind":"V","a":"p","b":"g","value":10.0},{"id":"R1","kind":"R","a":"p","b":"g","value":1000.0}]
	var assignment := {"reference_parts":parts,"practical":{"target":"R1"}}
	var actual := [{"id":"real_supply","kind":"V","a":"lead+","b":"lead-","value":10.0},{"id":"physical_resistor","kind":"R","a":"hole1","b":"hole2","value":1000.0}]
	var snapshot := evidence.snapshot(actual,[["lead+","hole1"],["lead-","hole2"]],assignment)
	check(snapshot.topology and evidence.grade(assignment,snapshot).score==40,"Practical grading matches electrical nodes and actual solver, not object IDs")
	var wrong := evidence.snapshot(actual,[],assignment)
	check(not wrong.topology and evidence.grade(assignment,wrong).score==0,"Visually adjacent disconnected components fail practical")
	check(evidence.grade(assignment,snapshot,{"power_off_before_wiring":true}).procedure_count==0,"Self-reported procedure cannot earn verified credit")
	var dc := DcStub.new();game.add_child(dc);game.dc_lab=dc
	var station=preload("res://scripts/dc_station.gd").new();dc.benches=[station]
	station.master=true;station.channels[0]={"enabled":true,"voltage":10.0,"limit":.1}
	station.wires=[["CH1+","R1a"],["R1b","CH1-"],["VΩ","R1a"],["COM","R1b"]]
	station.meter_mode="DC V";station.meter_range=20;station.step()
	assignment.course_id="ETY155";assignment.seed=12
	var physical := Evidence.new(game)
	check(physical.record_measurement(1,0,assignment),"Capture actual DC supply/resistor/DMM voltage measurement")
	station.wires=[["CH1+","R1a"],["R1b","A"],["COM","CH1-"]]
	station.meter_mode="DC A";station.meter_range=.1;station.step()
	check(physical.record_measurement(1,0,assignment),"Capture actual in-series DMM current measurement")
	var measured := physical.capture(1,0,assignment)
	check(physical.grade(assignment,measured).score==80,"Real instrument observations, suitable range and actual operating circuit earn 80% practical credit")
	physical.record_verified_step(1,0,assignment,"power_off_before_wiring")
	physical.record_verified_step(1,0,assignment,"range_checked")
	var before_off: Array=station.netlist();station.master=false;station.step()
	physical.observe_action(1,0,assignment,"master",before_off)
	check(physical.grade(assignment,physical.capture(1,0,assignment)).score==100,"Authority-verified transitions complete the practical rubric")
	station.master=true;station.wires=[["CH1+","R1a"],["R1b","CH1-"],["A","CH1+"],["COM","CH1-"]];station.step()
	check(not physical.record_measurement(1,0,assignment),"Ammeter across source fails and cannot manufacture measurement credit")
	# Host interruption through the deadline voids unfinished work instead of zeros.
	fresh.assessment_deadline=Time.get_unix_time_from_system()-1;fresh.remaining=1;fresh.checkpoint()
	var protected := School.new();game.add_child(protected);protected.game=game;protected.local_identity=token;protected.identities={1:token};protected.configure_campus(RoomStub.new(),ProviderStub.new())
	check(protected.recover_activity().ok and protected.phase=="complete","Expired host interruption safely ends unresolved class")
	check(protected.archive.is_empty() and protected.papers.values().all(func(p):return p.lesson or not p.mark.is_empty()),"Host downtime creates no student zero marks")
	protected.free()
	school.free();fresh.free();game.free()
	print("ACADEMICS_RESULT checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
