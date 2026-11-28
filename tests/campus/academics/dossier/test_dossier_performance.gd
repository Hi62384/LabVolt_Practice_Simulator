extends SceneTree
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Dossier=preload("res://scripts/campus/academics/character_dossier.gd")
const Fixture=preload("res://tests/campus/academics/dossier/dossier_fixture.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	Store.set_host_profile("dossier-performance-"+str(Time.get_ticks_usec()))
	var fixture:=Fixture.make()
	var published:=Store.publish(fixture,{"identity":{"id":fixture.identity.id,"role":"student"}})
	if not published.get("ok",false):push_error(str(published));quit(1);return
	Profiles.teacher("mr_bro")
	Profiles.student(90)
	var loops:=500
	var started:=Time.get_ticks_usec()
	for _i in loops:Profiles.teacher("mr_bro")
	var teacher_us:=float(Time.get_ticks_usec()-started)/loops
	started=Time.get_ticks_usec()
	for _i in loops:Profiles.student(90)
	var student_us:=float(Time.get_ticks_usec()-started)/loops
	var person:=Profiles.student(90)
	person.dossier=Store.get_dossier(person.id)
	started=Time.get_ticks_usec()
	var context: Dictionary={}
	for _i in 100:context=Dossier.retrieve(person,"Tell me about your childhood and that old radio.",[],"sad",{},6500)
	var retrieve_us:=float(Time.get_ticks_usec()-started)/100.
	var baseline: Dictionary={}
	if FileAccess.file_exists("res://.godot/dossier-baseline/class_character_profile.gd"):
		var previous: Script=load("res://.godot/dossier-baseline/class_character_profile.gd")
		previous.teacher("mr_bro")
		started=Time.get_ticks_usec()
		for _i in loops:previous.teacher("mr_bro")
		baseline.teacher_profile_usec=float(Time.get_ticks_usec()-started)/loops
		started=Time.get_ticks_usec()
		for _i in loops:previous.student(90)
		baseline.student_profile_usec=float(Time.get_ticks_usec()-started)/loops
	print("DOSSIER_PERFORMANCE "+JSON.stringify({"synthetic_fixture_not_live_ai":true,"iterations":loops,"teacher_profile_usec":teacher_us,"student_profile_usec":student_us,"retrieval_usec":retrieve_us,"selected_context_chars":JSON.stringify(context).length(),"full_dossier_bytes":JSON.stringify(person.dossier).to_utf8_buffer().size(),"lightweight_profile_bytes":JSON.stringify(Profiles.student(90)).to_utf8_buffer().size(),"baseline_commit":"7ec6c95241fca70e724783d6234dc3f445a6630c","baseline":baseline,"actual_tokens":"unavailable_without_live_API"}))
	quit(0)
