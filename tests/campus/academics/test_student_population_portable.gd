extends SceneTree
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Dossier=preload("res://scripts/campus/academics/character_dossier.gd")
const Generation=preload("res://scripts/campus/academics/character_dossier_generation.gd")
const DossierFixture=preload("res://tests/campus/academics/dossier/dossier_fixture.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Programs=preload("res://scripts/campus/academics/academic_programs.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Archive=preload("res://scripts/campus/academics/student_social_archive.gd")
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
const Sync=preload("res://scripts/campus/academics/student_population_sync.gd")
var failures: Array[String]=[]
var checks:=0

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)

func wire(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _initialize() -> void:
	var suffix:=str(Time.get_ticks_usec())
	var alice:=Population.new()
	check(alice.set_host_profile("portable-alice-"+suffix)==OK,"Alice local collection opens")
	alice.load_population();Legacy.seed(alice,12)
	check(Population.valid_identity("campus_student_"+"1".repeat(32)),"all-numeric 128-bit identifier is not confused with a legacy index")
	var ids:={}
	for _index in 50:
		var id:=alice.reserve_identity()
		check(Population.valid_identity(id) and id.length()==47 and not ids.has(id),"128-bit new identity is unique and schema-valid")
		ids[id]=true
	alice.requested_courses={"ELM253":2}
	var pending_id:=alice.reserve_identity()
	var seed:=alice.generation_seed(pending_id)
	check(Programs.eligible({"program":seed.identity.program},"ELM253"),"new generation seed guarantees pending course eligibility")
	check(Store.queue_student(pending_id,seed) and Store.jobs[pending_id].seed==seed,"generation queue preserves authoritative program seed")
	var generated:=DossierFixture.make(pending_id,"Pending Student",false)
	generated.identity.program="hospitality"
	check(not Dossier.validate(generated,seed).ok,"generator cannot change student to an ineligible program")
	generated.identity.program=seed.identity.program
	check(Dossier.validate(generated,seed).ok,"correct program retains normal complete-dossier validation")
	var old_id:="campus_student_00"
	var original:=alice.profile_for(old_id)
	var portable_id:=str(original.persistent_id)
	check(portable_id!=old_id and alice.local_id(portable_id)==old_id,"legacy identity aliases preserve local history keys")
	var electrical:=""
	for person in alice.available({},6,41,"ETY155"):
		check(Programs.eligible(person,"ETY155"),"electrical classes exclude unrelated majors")
		electrical=str(person.id)
	check(not electrical.is_empty(),"eligible historical residents are available")
	check(not Programs.eligible({"program":"hospitality"},"ETY155"),"unrelated program cannot enter electrical lab")
	check(Programs.eligible({"program":"electrical engineering"},"MTH255"),"shared math curriculum accepts electrical students")
	check(not Programs.eligible({"program":"electronics technology","enrollment":{"ETY155":"suspended"}},"ETY155"),"enrollment restriction is enforced")
	alice.record_attendance(old_id,"MTH147","class-one",["player-alice"])
	alice.record_attendance(old_id,"MTH147","class-one",["player-alice"])
	check(int(alice.profile_for(old_id).appearances)==1,"duplicate attendance event cannot count twice")
	var payload: Dictionary=wire(alice.export_person(portable_id))
	check(not JSON.stringify(payload).contains("familiar_players"),"manifest/profile omit other players' familiarity identifiers")
	var local_memory:=Memory.new()
	check(local_memory.set_host_profile("portable-memory-alice-"+suffix)==OK,"local social memory opens")
	local_memory.load_memory()
	var mind:=Mind.new();local_memory.bind_mind(mind)
	local_memory.remember(old_id,"player-alice","study",1700000000)
	local_memory.remember_event(original,"player-alice",{"event":"joke","strategy":"joke","interpretation":{"summary":"We joked about a shared project."}},"I like the radio project.","That project was memorable.",1700000001,"portable-event-1")
	local_memory.remember_event(original,"player-bob",{"event":"insult"},"private Bob statement","private reply",1700000002,"private-bob")
	var snapshot:=local_memory.export_social_record(old_id,"player-alice")
	check(not JSON.stringify(snapshot).contains("private Bob"),"portable own relationship excludes unrelated conversations")
	check(snapshot.relationship.episodes.size()==2,"meaningful memories exported")
	var archive:=Archive.new();archive.configure("portable-archive-alice-"+suffix)
	var receipt:=archive.observe(portable_id,"player-alice",snapshot)
	check(Archive.valid(wire(receipt)),"causal record remains valid after JSON/network round trip")
	var bob:=Population.new()
	check(bob.set_host_profile("portable-bob-"+suffix)==OK,"Bob independent collection opens")
	bob.load_population();Legacy.seed(bob,12)
	var bob_alias:=str(bob.profile_for(old_id).persistent_id)
	check(bob_alias!=portable_id,"same historical numeric index on two devices is disambiguated")
	var accepted:=bob.import_person(payload,2)
	check(accepted.get("ok",false),"selected complete dossier imports from another player: "+str(accepted))
	check(bob.people.size()==13,"contribution adds one identity without replacing Bob's same-name student")
	var copy:=bob.profile_for(portable_id)
	check(copy.get("name")==original.name and Population._digest(copy.get("appearance"))==Population._digest(original.appearance),"contributed name and appearance stay fixed")
	check(copy.get("origin_population")==original.origin_population,"origin survives host migration")
	check(bob.import_person(payload,2).get("ok",false) and bob.people.size()==13,"duplicate contribution deduplicates by global identity")
	if payload.is_empty():
		for failure in failures:printerr("FAIL: "+failure)
		quit(1);return
	var disputed: Dictionary=payload.duplicate(true)
	disputed.dossier.identity.name="Contradictory identity"
	disputed.digest=Population._digest(disputed.dossier)
	check(not bob.import_person(disputed,2).get("ok",true) and bob.profile_for(portable_id).name==original.name,"conflicting biography does not overwrite established identity")
	bob.save_population()
	var restart:=Population.new();restart.set_host_profile("portable-bob-"+suffix)
	check(restart.load_population() and restart.people.size()==13,"restart retains combined local collection")
	check(restart.local_id(portable_id)==portable_id and restart.profile_for(portable_id).name==original.name,"contributor disconnect/restart retains admitted identity")
	var new_memory:=Memory.new();new_memory.set_host_profile("portable-memory-bob-"+suffix);new_memory.load_memory()
	check(new_memory.import_social_record(portable_id,"player-alice",wire(snapshot),true),"own relationship imports into next host")
	check(is_equal_approx(float(new_memory.social_context(new_memory.relationship(portable_id,"player-alice")).friendship),float(snapshot.relationship.dimensions.friendship)),"friendship scalar preserved across hosts")
	check(new_memory.recall(portable_id,"player-bob").is_empty(),"unrelated private dialogue never imported")
	check(new_memory.save_memory()==OK,"portable social snapshot passes authoritative persistence validation")
	var load_memory:=Memory.new();load_memory.set_host_profile("portable-memory-bob-"+suffix)
	check(load_memory.load_memory() and load_memory.relationship(portable_id,"player-alice").get("episodes",[]).size()==2,"significant relationship memories survive restart")
	var public_canon:=local_memory.export_identity_canon(original)
	check(new_memory.import_identity_canon(copy,wire(public_canon)).get("ok",false),"fictional canon passes bounded cross-host schema")
	var second_archive:=Archive.new();second_archive.configure("portable-archive-bob-"+suffix)
	check(second_archive.classify(wire(receipt))=="new","unknown record is recognized as new")
	check(second_archive.receive(wire(receipt),wire(snapshot)),"causal receipt persists")
	var modified:=snapshot.duplicate(true)
	modified.relationship.dimensions.liking=.2
	var divergent:=archive.observe(portable_id,"player-alice",modified)
	check(second_archive.classify(wire(divergent))=="descendant","causally newer state uses digest ancestry instead of clocks")
	second_archive.receive(wire(divergent),wire(modified))
	check(second_archive.classify(wire(receipt))=="older","stale relationship cannot replace newer state")
	var tampered:=receipt.duplicate(true);tampered.snapshot.relationship.dimensions.liking=1.
	check(second_archive.classify(tampered)=="invalid","changed social payload fails integrity digest")
	var protocol:=Sync.new();protocol.free()
	for failure in failures:printerr("FAIL: "+failure)
	print("STUDENT_POPULATION_PORTABLE %s (%d checks)"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
