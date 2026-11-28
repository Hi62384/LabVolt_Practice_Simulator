extends SceneTree
## Corrupt durable state must not be overwritten, nor make new perceived events
## disappear from the current session. Run with isolated Godot user data.
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const PATH:="user://character_memory_corrupt_fixture.json"
var failures: Array[String]=[]
var checks:=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func write_text(path: String,value: String) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:check(false,"corruption fixture opens");return
	file.store_string(value);file.close()

func _initialize() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
	write_text(PATH,"{broken primary fixture")
	write_text(PATH+".bak","{broken backup fixture")
	var original_primary:=FileAccess.get_file_as_string(PATH)
	var original_backup:=FileAccess.get_file_as_string(PATH+".bak")
	var brain:=Brain.new();var mind:=Mind.new()
	brain.memory_path=PATH;brain.bind_mind(mind)
	check(not brain.load_memory() and brain.memory_blocked,"both corrupt copies block durable writes")
	var person:=Characters.teacher("bill_nye")
	var question:="I learned to troubleshoot during a supervised repair placement."
	var position:="College should provide more supervised practice with real equipment."
	var biography:="I built a cardboard wind tunnel with my uncle."
	var speech:=position+" "+biography
	var turn:=mind.observe(person,{},question,0,"alex","disagreement","blocked-first",{"event":"disagreement","severity":.4,"important":true})
	turn.details={"memories":[{"subject":"experience.placement","quote":question,"domain":"mechanics"}],
		"biography":{"topic":"childhood.wind_tunnel","detail":biography},
		"belief_updates":[{"id":"education","position":position,"reason":"The placement offered a useful practical counterexample.","evidence":question,"conviction_change":.03}]}
	var now:=int(Time.get_unix_time_from_system())
	check(brain.remember_event(person,"alex",turn,question,speech,now,"blocked-first"),"new perceived event is retained in RAM while disk is blocked")
	check(brain.recall(person.id,"alex").size()==1 and brain.relationship(person.id,"alex").episodes.size()==1,"descriptive history and actual speech survive in the session")
	check(brain.relationship(person.id,"alex").facts.has("experience.placement"),"speaker facts can still be learned in memory")
	check(brain.character_biography(person).has("childhood.wind_tunnel"),"delivered biography can still be retained in memory")
	check(brain.character_beliefs(person)[0].position==position,"grounded belief revisions are retained in memory")
	check(brain.remember_event(person,"alex",turn,question,speech,now,"blocked-first") and brain.recall(person.id,"alex").size()==1,"RAM event receipts still prevent duplicate consequences")
	var silent:=mind.observe(person,brain.relationship(person.id,"alex"),"Your last explanation skipped a step.",1,"alex","criticism","blocked-delayed",{"event":"criticism","severity":.3})
	check(brain.remember_event(person,"alex",silent,"Your last explanation skipped a step.","",now+1,"blocked-delayed"),"silent events are retained while persistence is blocked")
	check(brain.complete_event(person,"alex","blocked-delayed","Which step did I skip?"),"later delivery can complete an unsaved event")
	check(brain.recall(person.id,"alex")[1].teacher=="Which step did I skip?","delayed speech remains visible to retrieval")
	brain.remember_conversation(person.id,"alex","I keep a repair notebook.","Keep the failures in it too.",now+2)
	check(brain.recall(person.id,"alex").size()==3,"legacy conversation API also preserves unsaved session progress")
	var diagnostic:=brain.diagnostics()
	check(diagnostic.persistence_state=="blocked_unsaved" and diagnostic.unsaved_data and diagnostic.blocked_reason=="existing_save_corrupt","diagnostics explicitly distinguish retained unsaved progress from durable state")
	check(not brain.retry_memory_load() and brain.recall(person.id,"alex").size()==3,"retrying a load cannot erase unsaved session observations")
	check(brain.save_memory()==ERR_FILE_CORRUPT,"saving still refuses to overwrite two corrupt durable copies")
	check(not brain.character_states.is_empty() and brain.character_states.moods.has(person.id),"blocked save captures the bound emotional state in RAM")
	check(FileAccess.get_file_as_string(PATH)==original_primary and FileAccess.get_file_as_string(PATH+".bak")==original_backup,"both corrupt files remain byte-for-byte unchanged for recovery")
	check(not FileAccess.file_exists(PATH+".tmp"),"blocked persistence does not create a replacement snapshot")
	check(brain.set_host_profile("blocked_other_profile")==ERR_BUSY and brain.memory_path==PATH and brain.recall(person.id,"alex").size()==3,"unscoped legacy progress cannot be silently assigned to a different identity")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)

	# A damaged scoped profile remains usable in this session and cannot trap the
	# player in that identity. It is cached without leaking into the next profile.
	var scoped:=Brain.new();var scoped_mind:=Mind.new();scoped.bind_mind(scoped_mind)
	var a:="corrupt_host_"+str(Time.get_ticks_usec())
	var b:=a+"_valid"
	check(scoped.set_host_profile(a)==OK and scoped.load_memory(),"first scoped fixture opens")
	var path_a:=scoped.memory_path
	write_text(path_a,original_primary);write_text(path_a+".bak",original_backup)
	check(not scoped.load_memory() and scoped.memory_blocked,"corruption is detected inside the first host's namespace")
	var remembered_turn:=scoped_mind.observe(person,{},question,0,"alex","disagreement","cached-event",{"event":"disagreement","severity":.4})
	remembered_turn.details=turn.details.duplicate(true)
	check(scoped.remember_event(person,"alex",remembered_turn,question,speech,now,"cached-event"),"corrupt profile accumulates complete session progress")
	var old_emotions: Dictionary=scoped_mind.context(person,0).emotions.duplicate(true)
	# Another host's actual legacy version must not become this quarantined
	# host's migration source when its unsaved state is restored from RAM.
	write_text(Brain.profile_prefix(b)+".json",JSON.stringify({"version":1,"relationships":{}}))
	check(scoped.set_host_profile(b)==OK and scoped.load_memory(),"a corrupt profile can switch to another valid host identity")
	check(scoped.loaded_memory_version==1,"the other host independently loads its actual legacy migration version")
	var path_b:=scoped.memory_path
	check(scoped.diagnostics().cached_unsaved_profiles==1 and not scoped.diagnostics().profile_cache_durable,"diagnostics expose that an inactive profile has session-only unsaved data")
	check(scoped.recall(person.id,"alex").is_empty() and scoped.belief_revisions.is_empty() and scoped_mind.moods.is_empty(),"cached conversations, opinions and affect do not leak into the valid profile")
	scoped.remember_conversation(person.id,"jordan","I keep a different notebook.","Use it.",now)
	check(scoped.save_memory()==OK,"the second profile saves normally while the first is quarantined in RAM")
	check(scoped.set_host_profile(a)==OK and not scoped.load_memory(),"returning to a corrupt profile restores RAM and honestly reports blocked durability")
	check(scoped.loaded_memory_version==Brain.MEMORY_VERSION,"restoring quarantined state preserves its own migration source version")
	check(scoped.recall(person.id,"alex").size()==1 and scoped.recall(person.id,"jordan").is_empty() and scoped.character_beliefs(person)[0].position==position,"returning restores only the original profile's transcript and current opinion")
	check(absf(float(scoped_mind.context(person,Time.get_ticks_msec()).emotions.interest)-float(old_emotions.interest))<.02,"cached emotional state returns with its host identity")
	check(scoped.diagnostics().persistence_state=="blocked_unsaved" and scoped.diagnostics().cached_unsaved_profiles==0,"restored unsaved state is active and no longer counted as an inactive cache entry")
	check(FileAccess.get_file_as_string(path_a)==original_primary and FileAccess.get_file_as_string(path_a+".bak")==original_backup,"switching away and back preserves both damaged files exactly")
	for path in [path_a,path_b]:
		for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)

	# Retention has an explicit bound. It never evicts a dirty character to make
	# space, and an already-cached identity can still be reopened at capacity.
	var bounded:=Brain.new()
	var prefix:="bounded_cache_"+str(Time.get_ticks_usec())+"_"
	var paths: Array[String]=[]
	for index in range(Brain.MAX_CACHED_PROFILES+1):
		check(bounded.set_host_profile(prefix+str(index))==OK,"bounded cache accepts profile %d"%index)
		paths.append(bounded.memory_path)
		write_text(bounded.memory_path,original_primary);write_text(bounded.memory_path+".bak",original_backup)
		check(not bounded.load_memory(),"bounded fixture %d is blocked on disk"%index)
		bounded.remember_conversation(person.id,"alex","I keep notebook %d."%index,"Keep it.",now)
	var active:=bounded.host_profile()
	check(bounded.set_host_profile(prefix+"overflow")==ERR_OUT_OF_MEMORY,"capacity exhaustion returns an explicit error instead of discarding dirty data")
	check(bounded.host_profile()==active and bounded.recall(person.id,"alex").size()==1 and bounded.diagnostics().cached_unsaved_profiles==Brain.MAX_CACHED_PROFILES,"capacity failure preserves the active state and all cached profiles")
	check(bounded.set_host_profile(prefix+"0")==OK and not bounded.load_memory(),"a full cache still permits returning to an existing cached identity")
	check(bounded.recall(person.id,"alex")[0].student=="I keep notebook 0." and bounded.diagnostics().cached_unsaved_profiles==Brain.MAX_CACHED_PROFILES,"reopening swaps active and inactive states without an eviction")
	for path in paths:
		for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("CHARACTER_MEMORY_RESILIENCE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	quit(0 if failures.is_empty() else 1)
