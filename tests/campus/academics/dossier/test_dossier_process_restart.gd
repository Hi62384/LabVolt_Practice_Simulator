extends SceneTree
## Synthetic full-dossier transport fixture, reopened by a separate OS process.
## Does not claim that an AI invented this identity or that a human reviewed it.
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Generation=preload("res://scripts/campus/academics/character_dossier_generation.gd")
const Fixture=preload("res://tests/campus/academics/dossier/dossier_fixture.gd")
const OWNER:="dossier-process-restart-fixture"
var failures: Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);push_error(message)
func _initialize()->void:
	if OS.get_environment("LABVOLT_CHARACTER_TEST_ISOLATED")!="1":print("DOSSIER_PROCESS_RESTART requires disposable user data");quit(2);return
	var mode:=OS.get_environment("LABVOLT_DOSSIER_RESTART_MODE")
	if mode not in ["write","read"]:quit(2);return
	var population:=Population.new()
	check(population.set_host_profile(OWNER)==OK,"host namespace")
	population.load_population()
	if mode=="write":
		var candidate:=Fixture.make()
		check(Store.publish(candidate,{"identity":{"id":candidate.identity.id,"role":"student"}},{"fixture":true,"usage":{"input":123,"output":456},"requests":1}).get("ok",false),"complete fixture persists")
		check(population.import_generated(Generation.student_profile(Store.get_dossier(candidate.identity.id))),"persisted population publication")
		Store.queue_student("campus_student_91")
		Store.jobs.campus_student_91.status="running"
		Store.jobs.campus_student_91.attempts=1
		Store.jobs.campus_student_91.stage="repair"
		Store.jobs.campus_student_91.draft={"life_history":[{"id":"preserved_completed_section","text":"An already completed draft section survives interruption."}]}
		Store.jobs.campus_student_91.invalid_sections=["communication"]
		Store.dirty=true
		check(Store.save()==OK,"interrupted job checkpoint persists")
		var file:=FileAccess.open("user://dossier-restart-expectation.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"writer_pid":OS.get_process_id(),"dossier":Store.get_dossier(candidate.identity.id),"name":population.profile_for(candidate.identity.id).name}));file.flush();file.close()
	else:
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://dossier-restart-expectation.json"))
		check(int(expected.writer_pid)!=OS.get_process_id(),"new OS process")
		var actual:=Store.get_dossier("campus_student_90")
		check(actual.generation.status=="complete","completed generation status survives process restart")
		check(actual.identity==expected.dossier.identity,"name age role and physical identity unchanged")
		check(actual.life_history==expected.dossier.life_history,"full biography sections and chronology unchanged")
		check(actual.personality==expected.dossier.personality,"personality beliefs and goals unchanged")
		check(actual.communication==expected.dossier.communication,"speaking description and all mood examples unchanged")
		check(actual.traits==expected.dossier.traits,"independent numerical traits unchanged")
		check(actual.voice==expected.dossier.voice,"permanent vocal identity unchanged")
		check(actual.generation.measurement.usage.input==123,"recorded fixture telemetry survives restart")
		check(population.profile_for("campus_student_90").name==expected.name,"roster resolves the same authoritative character")
		check(Store.jobs.campus_student_91.status=="queued" and Store.jobs.campus_student_91.attempts==0,"interrupted request resumes without consuming a repair attempt")
		check(Store.jobs.campus_student_91.stage=="repair" and Store.jobs.campus_student_91.draft.life_history[0].id=="preserved_completed_section","completed generation sections are not regenerated after restart")
		check(Store.jobs.campus_student_91.invalid_sections==["communication"],"repair remains scoped to incomplete section")
	print("DOSSIER_PROCESS_RESTART "+("PASS" if failures.is_empty() else "FAIL")+" phase="+mode+" pid="+str(OS.get_process_id())+" synthetic_fixture_only")
	quit(0 if failures.is_empty() else 1)
