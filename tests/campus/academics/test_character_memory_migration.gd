extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const PATH:="user://character_memory_migration_fixture.json"
var failures: Array[String]=[]

func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);push_error(message)

func write_json(path: String,value: Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:check(false,"fixture file opens");return
	file.store_string(JSON.stringify(value));file.close()

func _initialize() -> void:
	for version in range(1,6):
		for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
		var record:={"familiarity":12,"positive":5,"disruptions":2,"last_seen":100000,"resentment":3,"study_sessions":4,
			"facts":{"my favorite game":{"statement":"My favorite game is Minecraft.","source":"speaker_statement","domain":"gaming","at":99999}},
			"episodes":[{"event":"insult","at":99998,"count":3}]}
		var snapshot:={"version":version,"relationships":{"brian:alex":record}}
		if version>=2:snapshot.conversations={"brian:alex":[{"student":"My favorite game is Minecraft.","teacher":"I remember you saying that."}]}
		if version>=4:snapshot.biographies={"brian":{"childhood":"I grew up near an old steelworks."}}
		if version>=5:
			var old_mind:=Mind.new();old_mind.feel(Characters.teacher("brian"),"insult",1.,0)
			snapshot.character_states=old_mind.export_state();snapshot.processed_events={"brian:alex":["old-event"]}
		write_json(PATH,snapshot)
		var migrated:=Brain.new();migrated.memory_path=PATH
		check(migrated.load_memory(),"legacy v%d loads"%version)
		var memory:=migrated.relationship("brian","alex")
		check(memory.familiarity==12 and memory.facts.size()==1 and memory.episodes[0].count==3,"v%d keeps identity, fact and significant history"%version)
		check(memory.dimensions.size()==13 and memory.dimensions.resentment>0.,"v%d initializes independent dimensions from old counters"%version)
		migrated.remember("brian","alex","initiative",100001)
		check(migrated.save_memory()==OK,"v%d migrates atomically to v6 on next observation"%version)
		var reload:=Brain.new();reload.memory_path=PATH
		check(reload.load_memory() and reload.relationship("brian","alex").positive==6,"v%d migration survives a second load"%version)
		if version>=4:check(reload.character_biography(Characters.teacher("brian")).childhood==snapshot.biographies.brian.childhood,"legacy detailed biography survives migration")
		if version>=5:check(reload.character_states.moods.has("brian") and reload.processed_events["brian:alex"]==["old-event"],"v5 affect and event receipts survive v6 migration")
		check(reload.belief_revisions.is_empty(),"v%d migration does not invent past changes of opinion"%version)

	# These tests must be launched with isolated XDG_DATA_HOME like the other
	# native fixtures; no actual player's profile path is opened.
	var legacy:=Brain.new();legacy.memory_path="user://migration_profile_legacy_fixture.json"
	legacy.remember_conversation("chad","alex","I keep a red notebook.","Write something useful in it.",100000)
	check(legacy.save_memory()==OK,"legacy profile fixture saves")
	var scoped:=Brain.new()
	var mind:=Mind.new();scoped.bind_mind(mind)
	var a:="memory_fixture_host_a_"+str(Time.get_ticks_usec())
	var b:=a+"_b"
	check(scoped.set_host_profile(a)==OK and scoped.load_memory(),"first isolated host namespace opens")
	var first_path:=scoped.memory_path
	scoped.remember_conversation("chad","alex","I keep a green notebook.","Keep your own record.",100001)
	mind.feel(Characters.teacher("chad"),"insult",1.,1000)
	check(scoped.save_memory()==OK,"first host's state saves")
	check(not scoped.memory_dirty,"memory is clean before an affect-only change")
	mind.feel(Characters.teacher("chad"),"insult",1.,1010)
	var unsaved_anger:=float(mind.context(Characters.teacher("chad"),1010).emotions.anger)
	check(not scoped.memory_dirty,"affect-only changes do not incorrectly depend on conversation dirtiness")
	check(scoped.set_host_profile(b)==OK and scoped.load_memory(),"second host namespace opens")
	var second_path:=scoped.memory_path
	check(scoped.relationship("chad","alex").familiarity==0 and scoped.recall("chad","alex").is_empty() and mind.moods.is_empty(),"host profile switch does not leak conversations, relationships or moods")
	scoped.remember("brian","jordan","study",100002)
	check(scoped.save_memory()==OK,"second host state saves independently")
	check(scoped.set_host_profile(a)==OK and scoped.load_memory(),"first profile can be reopened")
	check(scoped.recall("chad","alex").size()==1 and scoped.relationship("brian","jordan").familiarity==0 and mind.moods.has("chad"),"first profile restores its own histories and mood")
	check(absf(float(mind.context(Characters.teacher("chad"),Time.get_ticks_msec()).emotions.anger)-unsaved_anger)<.02,"switching profiles captures affect changed since the last conversation save")
	var valid:=scoped._read_memory(first_path)
	check(valid.ok,"validated profile snapshot is readable")
	var file:=FileAccess.open(first_path,FileAccess.READ)
	var damaged: Dictionary=JSON.parse_string(file.get_as_text());file.close()
	check(DirAccess.copy_absolute(first_path,first_path+".bak")==OK,"known-valid backup created")
	damaged.character_states.moods.chad.values.anger=5.0
	write_json(first_path,damaged)
	var recovered:=Brain.new();recovered.memory_path=first_path
	check(recovered.load_memory() and recovered.memory_dirty and not recovered.memory_blocked,"out-of-range affect corruption recovers validated backup")
	check(recovered.save_memory()==OK,"corrupt primary never replaces valid backup")
	for path in [PATH,first_path,second_path,legacy.memory_path]:
		for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("CHARACTER_MEMORY_MIGRATION ","PASS" if failures.is_empty() else "FAIL", " versions=1,2,3,4,5 profile_isolation=true affect_only_switch=true")
	quit(0 if failures.is_empty() else 1)
