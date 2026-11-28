extends SceneTree
## Invalid network/disk records and identity boundaries. No provider or hardware.
const Sync=preload("res://scripts/campus/academics/student_population_sync.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const Archive=preload("res://scripts/campus/academics/student_social_archive.gd")
var failures: Array[String]=[]
var checks:=0

class School extends Node:
	var local_identity:=""
	var identities: Dictionary={}
class Faculty extends Node:
	var brain: RefCounted
class Session extends Node:
	signal leaving
	var online:=false
class Students extends Node:
	var population: RefCounted
class Classes extends Node:
	var classroom_students:=Students.new()
	var classes: Dictionary={}
class Game extends Node:
	var school:=School.new()
	var faculty:=Faculty.new()
	var session:=Session.new()
	var lecture_classes:=Classes.new()
	func _init() -> void:
		add_child(school);add_child(faculty);add_child(session);add_child(lecture_classes)
		lecture_classes.add_child(lecture_classes.classroom_students)
	func select(identity: String) -> void:
		school.local_identity=identity
		faculty.brain=Memory.new();faculty.brain.set_host_profile(identity);faculty.brain.load_memory()
		lecture_classes.classroom_students.population=Population.new()
		lecture_classes.classroom_students.population.set_host_profile(identity)
		lecture_classes.classroom_students.population.load_population()

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message)

func receipt(character: String,player: String,snapshot: Dictionary) -> Dictionary:
	var parser:=JSON.new()
	var digest:=Archive.digest(snapshot) if parser.parse(JSON.stringify(snapshot))==OK else "0".repeat(64)
	return {"version":1,"character":character,"player":player,"revision":1,"parents":[],"snapshot":snapshot.duplicate(true),"digest":digest}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var suffix:=str(Time.get_ticks_usec())
	var game:=Game.new();root.add_child(game);game.select("adversarial-a-"+suffix)
	var sync:=Sync.new();root.add_child(sync);sync.configure(game);sync.set_process(false)
	check(sync._bind(),"Authority fixture binds")
	var id:="campus_student_"+"a".repeat(32)
	var player:="b".repeat(48)
	var memory:=Memory.new()
	memory.remember(id,player,"study",1700000000)
	var snapshot:=memory.export_social_record(id,player)
	check(Archive.valid(JSON.parse_string(JSON.stringify(receipt(id,player,snapshot)))),"Valid social record survives wire normalization")
	var malformed: Array=[]
	for value in [[],1.5,null]:
		var bad:=snapshot.duplicate(true);bad.relationship=value;malformed.append(bad)
	var bad_episode:=snapshot.duplicate(true);bad_episode.relationship.episodes=[1.5];malformed.append(bad_episode)
	var bad_decision:=snapshot.duplicate(true);bad_decision.decision=[];malformed.append(bad_decision)
	var bad_number:=snapshot.duplicate(true);bad_number.relationship.dimensions.friendship=NAN;malformed.append(bad_number)
	var bad_count:=snapshot.duplicate(true);bad_count.relationship.familiarity=INF;malformed.append(bad_count)
	for bad in malformed:
		var record:=receipt(id,player,bad)
		check(not Archive.valid(record),"Malformed nested social shape/number rejected before remapping")
		sync._receive_social(record,id,player)
		check(not sync.brain.relationships.has(id+":"+player),"Malformed social record cannot mutate authoritative memory")
	for revision in [NAN,INF,-1,0,1000000001]:
		var record:=receipt(id,player,snapshot);record.revision=revision
		check(not Archive.valid(record),"Invalid causal revision rejected")
	check(not Archive.valid(receipt(id,"_npc_mood",{"mood":[]})),"Mood array rejected")
	check(not Archive.valid(receipt(id,"_npc_mood",{"mood":{"values":{"anger":INF},"at":1,"history":[]}})),"Nonfinite mood rejected")
	for value in [[],1.5,null]:
		# Regression also requires the engine log to contain no SCRIPT ERROR.
		sync._person_reply({"person":value})
		check(not sync._receive({"person":value},player,7),"Non-object person rejected")
		var result: Dictionary=sync.population.import_person({"version":1,"id":id,"origin_population":"c".repeat(64),"dossier":{"identity":value}})
		check(result.has("ok") and not result.ok,"Non-object dossier identity returns a normal rejection")
	for value in [NAN,INF,[],"bad"]:
		check(not Population._valid_metadata({"attendance":{"count":value}}),"Invalid attendance number rejected")
		check(not Population._valid_metadata({"learning":{"ELM253":value}}),"Invalid learning number rejected")
	sync.manifests[7]={id:{"id":id,"program":"electronics technology","revision":1,"appearances":0}}
	sync.requested[7]={id:Time.get_ticks_msec()-120000}
	sync._queue_candidates(7,"ELM253")
	check(id in sync.pending.get(7,[]) and not sync.requested[7].has(id),"Unavailable request expires and eligible student can be retried")
	sync.pending[7]=[];sync.requested[7]={id:Time.get_ticks_msec()}
	sync._queue_candidates(7,"ELM253")
	check(sync.pending[7].is_empty(),"Unexpired request is not duplicated")
	sync.peer_identities[7]=player
	sync.sent["7:"+id]="old";sync.sent_profiles["7:"+id]="old-profile"
	game.school.identities={1:game.school.local_identity}
	root.multiplayer.peer_disconnected.emit(7)
	check(not sync.peer_identities.has(7) and not sync.requested.has(7),"Disconnected contributor fetch state is cleared")
	check(not sync.sent.has("7:"+id) and not sync.sent_profiles.has("7:"+id),"Reused peer number must receive full profile before periodic processing")
	sync.sent_profiles["7:"+id]="previous-transport"
	root.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	check(sync._bind() and sync.sent_profiles.is_empty(),"Same owner and role on a replacement transport resets profile delivery cache")
	sync._pending_bonds["old"]=receipt(id,player,snapshot)
	sync.sent["7:"+id]="old";sync.sent_profiles["7:"+id]="old-profile"
	game.select("adversarial-b-"+suffix)
	check(sync._bind() and sync._pending_bonds.is_empty() and sync.sent.is_empty() and sync.sent_profiles.is_empty(),"Profile switch discards prior pending bonds and transport caches")
	var healthy:=Archive.new();healthy.configure("archive-healthy-"+suffix)
	check(healthy.save()==OK,"Healthy archive fixture is durable")
	var corrupt:=Archive.new();corrupt.configure("archive-corrupt-"+suffix)
	var file:=FileAccess.open(corrupt.path,FileAccess.WRITE);file.store_string("{\"version\":0}");file.close()
	var reused:=Archive.new()
	check(reused.configure("archive-corrupt-"+suffix)==ERR_FILE_CORRUPT and reused.blocked,"Corrupt profile is blocked")
	check(reused.configure("archive-healthy-"+suffix)==OK and not reused.blocked and reused.last_error==OK,"Healthy profile does not inherit old storage error")
	sync.free();game.free()
	for failure in failures:printerr("FAIL: "+failure)
	print("STUDENT_SYNC_ADVERSARIAL %s (%d checks)"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
