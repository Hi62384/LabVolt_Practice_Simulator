extends SceneTree
## The real classroom controller must not publish a previous host's roster
## when selecting a new namespace fails, or write learning while unbound.
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
var failures: Array[String]=[]
var checks:=0

class SchoolFixture extends Node:
	var local_identity:="population-binding-alpha"
class RoomsFixture extends Node:
	var classes: Dictionary={}
class GameFixture extends Node:
	var school: SchoolFixture
	var lecture_classes: RoomsFixture

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("STUDENT BINDING FAIL: "+message)

func run() -> void:
	var game:=GameFixture.new();root.add_child(game)
	game.school=SchoolFixture.new();game.add_child(game.school)
	game.lecture_classes=RoomsFixture.new();game.add_child(game.lecture_classes)
	var students:=Students.new();game.add_child(students)
	students.configure(game)
	check(students.host_profile==game.school.local_identity and not students.population.profile_blocked,"Initial host population selection succeeds")
	Legacy.seed(students.population,24)
	students.population.people.campus_student_14.biography.host_private_fact="Only the alpha campus knows this story."
	students.population.dirty=true
	Legacy.sync(students.population)
	check(students.population.save_population()==OK,"Known alpha profile is saved")
	students.record_practice("campus_student_14","ELM253",true,1)
	check(students.learning_save_error==OK,"Known alpha learning is saved")
	students.configure(game)
	check(Students.profile_for("campus_student_14").biography.get("host_private_fact","")=="Only the alpha campus knows this story.","Controller publishes its selected host's full private profile locally")
	var alpha_population:=students.population.path
	var alpha_learning:=students.records_path
	var population_hash:=FileAccess.get_sha256(alpha_population)
	var learning_hash:=FileAccess.get_sha256(alpha_learning)

	game.school.local_identity=""
	students.configure(game)
	check(students.population.profile_blocked,"An invalid profile selection is blocked")
	check(students.host_profile.is_empty() and students.records_path.is_empty(),"Failed selection leaves no active host or writable learning path")
	check(Students.known_profiles.is_empty() and Students.profile_for("campus_student_14").is_empty(),"Failed selection cannot cache or publish the previous host's profile")
	check(students.learning.is_empty() and students.records.get_sections().is_empty(),"Failed selection cannot load another host's learning")
	students.record_practice("campus_student_14","ELM253",true,1)
	check(students.learning.is_empty() and students.records.get_sections().is_empty(),"Practice cannot change learning while population selection is blocked")
	check(FileAccess.get_sha256(alpha_population)==population_hash and FileAccess.get_sha256(alpha_learning)==learning_hash,"A failed rebind preserves the old host's files exactly")

	game.school.local_identity="population-binding-beta"
	students.configure(game)
	check(not students.population.profile_blocked and students.host_profile==game.school.local_identity,"A valid new host can recover after the failed selection")
	check(not Students.profile_for("campus_student_14").get("biography",{}).has("host_private_fact") and students.learning.is_empty(),"The new host inherits no alpha profile or learning")
	game.school.local_identity="population-binding-alpha"
	students.configure(game)
	check(Students.profile_for("campus_student_14").biography.get("host_private_fact","")=="Only the alpha campus knows this story.","Returning to alpha restores its correct identity")
	check(float(students.learning.get("campus_student_14",{}).get("ELM253",0.))>0.,"Returning to alpha restores its correct learning")

	# Corruption blocks persistence without blocking same-owner session use.
	var broken_profile:="population-binding-corrupt"
	var broken_path:=Memory.profile_prefix(broken_profile)+".population.json"
	for suffix in ["",".bak"]:
		var file:=FileAccess.open(broken_path+suffix,FileAccess.WRITE)
		file.store_string("{damaged population "+suffix);file.close()
	var broken_hash:=FileAccess.get_sha256(broken_path)
	var broken_backup_hash:=FileAccess.get_sha256(broken_path+".bak")
	game.school.local_identity=broken_profile
	students.configure(game)
	check(not students.population.profile_blocked and Students.profile_for("campus_student_14").is_empty(),"Corrupt current-host files do not invent an unsaved replacement identity")
	var diagnostics: Dictionary=students.debug_snapshot().get("population_persistence",{})
	check(diagnostics.get("persistence_state","")=="blocked_unsaved" and diagnostics.get("last_load_error",OK)==ERR_FILE_CORRUPT and diagnostics.get("unsaved_data",false),"Controller diagnostics report actual population corruption and unsaved state")
	check(FileAccess.get_sha256(broken_path)==broken_hash and FileAccess.get_sha256(broken_path+".bak")==broken_backup_hash,"Controller configuration preserves both corrupt files unchanged")
	print("STUDENT_POPULATION_BINDING %s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
