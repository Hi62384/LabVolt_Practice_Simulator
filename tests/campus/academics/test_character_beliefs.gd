extends SceneTree
## Native persistence/validation regression, not an evaluation of live model
## persuasion or human-like conversation. Use isolated Godot user data:
## XDG_DATA_HOME=/tmp/labvolt-beliefs godot --headless --path . \
##   --script res://tests/campus/academics/test_character_beliefs.gd
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Beliefs=preload("res://scripts/campus/academics/character_beliefs.gd")
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const PATH:="user://character_beliefs_fixture.json"
var failures: Array[String]=[]
var checks:=0

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func belief(brain: RefCounted,person: Dictionary,id: String="education") -> Dictionary:
	for item in brain.character_beliefs(person):
		if item.id==id:return item
	return {}

func proposal(position: String,evidence: String,change:=.03,id: String="education") -> Dictionary:
	return {"id":id,"position":position,"reason":"The speaker gave a concrete counterexample worth considering.","evidence":evidence,"conviction_change":change}

func record(brain: RefCounted,person: Dictionary,question: String,speech: String,updates: Array,token: String,event: String="disagreement",speaker: String="alex") -> bool:
	return brain.remember_event(person,speaker,{"event":event,"details":{"speech":speech,"belief_updates":updates}},question,speech,int(Time.get_unix_time_from_system()),token)

func _initialize() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
	var brain:=Brain.new();brain.memory_path=PATH
	var chad:=Characters.teacher("chad")
	var nye:=Characters.teacher("bill_nye")
	var bird:=Characters.teacher("ms_bird_heart")
	var evidence:="My paid placement let me test the theory with real equipment."
	var position:="College should make more room for supervised practical work."
	var update:=proposal(position,evidence,.04)
	var speech:="That is a useful counterexample. "+position
	check(brain.belief_revision_policy(nye).education.can_revise_position,"an open character can revise an uncertain opinion from new evidence")
	check(not brain.belief_revision_policy(chad).education.can_revise_position,"Chad cannot instantly reverse a strongly held view")
	check(brain.belief_revision_policy(chad).education.max_conviction_change<brain.belief_revision_policy(nye).education.max_conviction_change,"openness controls the rate of conviction changes")
	check(not brain.belief_revision_policy(nye).personal_priority.can_revise_position,"core personal priorities remain stable even for an open character")
	check(brain.validate_belief_update(nye,evidence,speech,update,"disagreement").ok,"a grounded delivered revision validates")
	check(not brain.validate_belief_update(chad,evidence,speech,proposal(position,evidence,.01),"disagreement").ok,"a small conviction delta cannot bypass a stubborn position gate")
	check(not brain.validate_belief_update(nye,evidence,"I am still thinking.",update,"disagreement").ok,"an undelivered opinion cannot become persistent")
	check(not brain.validate_belief_update(nye,"I prefer the library.",speech,update,"disagreement").ok,"evidence must be quoted from the current input")
	check(not brain.validate_belief_update(nye,evidence,speech,proposal(position,evidence,.01,"official_grade"),"disagreement").ok,"unknown belief IDs cannot overwrite curriculum or invent new identity")
	check(not brain.validate_belief_update(nye,evidence,speech,proposal(position,evidence,.9),"disagreement").ok,"a large conviction reversal is rejected")
	check(not brain.validate_belief_update(nye,evidence,speech,proposal(position,evidence,NAN),"disagreement").ok,"nonfinite conviction changes are rejected")
	check(not brain.validate_belief_update(nye,evidence,speech,update,"insult").ok and not brain.validate_belief_update(nye,evidence,speech,update,"compliment").ok,"insults and flattery do not count as reasoned evidence")
	var authored:=nye.duplicate(true)
	check(record(brain,nye,evidence,speech,[update],"nye-revision"),"delivered revision records through the production event API")
	check(belief(brain,nye).position==position and belief(brain,nye).history_count==1,"current opinion and its reason are recorded")
	check(nye==authored,"remembering a new opinion does not mutate the authored profile")
	check(brain.character_context(nye,"jordan","What is education for?").beliefs[0].position==position,"the character retains the same current opinion with another speaker")
	check(record(brain,nye,evidence,speech,[update],"nye-revision") and belief(brain,nye).history_count==1,"replayed event IDs cannot revise a belief twice")
	check(not brain.validate_belief_update(nye,evidence,speech,update,"disagreement").ok,"repeating the same evidence cannot gradually wear down a belief")
	var repeated:=proposal(position,evidence.to_upper().trim_suffix("."),.01)
	check(not brain.validate_belief_update(nye,repeated.evidence,speech,repeated,"disagreement").ok,"case and terminal punctuation changes do not create new evidence")
	check(brain.character_biography(nye)==authored.biography,"an opinion change leaves ordinary biography intact")

	# A moderately open person can soften conviction before adopting a new view.
	var initial:=belief(brain,bird)
	check(not brain.belief_revision_policy(bird).education.can_revise_position,"moderate openness requires accumulated evidence")
	var arguments:=["The quieter students in my group spoke more during workshop pairs.","Our supervised placement helped a classmate who struggled with lectures."]
	for index in arguments.size():
		var current:=belief(brain,bird)
		var line:="I still believe this, although I see the complication: "+str(current.position)
		check(record(brain,bird,arguments[index],line,[proposal(current.position,arguments[index],-.03)],"bird-soften-%d"%index),"considered argument %d records"%index)
	check(is_equal_approx(float(belief(brain,bird).conviction),float(initial.conviction)-.06),"conviction changes gradually without an instant opinion reversal")
	check(brain.belief_revision_policy(bird).education.can_revise_position,"distinct considered evidence can open a later position revision")
	var new_view:="Education should offer several practical routes so hesitant students can find their footing."
	var third:="Our evening workshop gave three students a way to continue after their day jobs."
	check(record(brain,bird,third,new_view,[proposal(new_view,third,.02)],"bird-revision","disagreement","jordan"),"a justified later revision records across interlocutors")
	var revised:=belief(brain,bird)
	check(revised.position==new_view and revised.history_count==3 and revised.history[2].from_position==initial.position,"the evidence chain preserves the previous opinion and transition")
	check(revised.authored_position==initial.position and revised.history[2].speaker=="jordan","current opinion retains its authored anchor and actual source")
	var effective_person:=bird.duplicate(true);effective_person.beliefs=brain.character_beliefs(bird)
	check(brain.character_beliefs(effective_person)==brain.character_beliefs(bird),"merging effective beliefs into a prepared profile does not reset or duplicate history")

	# Unheard generated text, delayed speech, and reused physical observations
	# must obey the same grounding rules as a normal spoken exchange.
	var cancelled:="The equipment loan scheme helped apprentices practise after work."
	var withheld:="College should lend equipment as well as teach theory."
	var hidden:=proposal(withheld,cancelled,.01)
	check(brain.remember_event(nye,"alex",{"event":"disagreement","details":{"speech":withheld,"belief_updates":[hidden]}},cancelled,"",int(Time.get_unix_time_from_system()),"unheard"),"a cancelled reply still records the perceived question")
	check(belief(brain,nye).position==position,"cancelled speech cannot revise an opinion")
	check(brain.complete_event(nye,"alex","unheard",withheld,{"belief_updates":[hidden]}),"delayed delivered speech can complete a grounded argument")
	check(belief(brain,nye).position==withheld and belief(brain,nye).history_count==2,"delayed completion applies one grounded belief revision")
	check(brain.complete_event(nye,"alex","unheard",withheld,{"belief_updates":[hidden]}) and belief(brain,nye).history_count==2,"repeated completion cannot apply the revision again")
	var observation:="A nearby student left a phone ringing on the bench."
	check(record(brain,nye,observation,"",[],"physical-warning","disruption"),"a perceived physical event records before speech")
	check(brain.complete_event(nye,"alex","physical-warning",position,{"belief_updates":[proposal(position,observation,.01)]}),"physical warning speech can be stored")
	check(belief(brain,nye).history_count==2 and brain.last_belief_update.rejected.has("event_is_not_reasoned_evidence"),"a reused physical observation cannot masquerade as a new reasoned argument")
	var parsed:=Mind.decode_dialogue(JSON.stringify({"speech":position,"belief_updates":[update]}))
	check(parsed.belief_updates==[update],"dialogue decoding retains explicit belief proposals")
	check(Mind.decode_dialogue(JSON.stringify({"speech":"I heard you.","belief_updates":"invalid"})).belief_updates=="invalid","malformed proposals remain visible for upstream rejection")
	check("Active beliefs" in Mind.instructions(effective_person,"steady"),"character instructions explicitly prefer saved current positions")

	check(Beliefs.valid_snapshot(brain.belief_revisions),"complete belief histories pass strict persistence validation")
	var damaged:=brain.belief_revisions.duplicate(true)
	damaged.bill_nye.education.history[0].conviction=2.
	check(not Beliefs.valid_snapshot(damaged),"out-of-range conviction corrupts a snapshot")
	damaged=brain.belief_revisions.duplicate(true);damaged.bill_nye.education.position="An opinion absent from its evidence chain."
	check(not Beliefs.valid_snapshot(damaged),"a snapshot cannot rewrite the current position without matching history")
	check(brain.save_memory()==OK,"version six atomically saves beliefs and ordinary memories together")
	var loaded:=Brain.new();loaded.memory_path=PATH
	var loaded_ok:=loaded.load_memory()
	# Godot's JSON parser represents integer timestamps as floats. Compare the
	# serialized values after numeric normalization, including every history field.
	check(loaded_ok and loaded.belief_revisions==JSON.parse_string(JSON.stringify(brain.belief_revisions)),"a new process-equivalent memory object restores the complete evidence chain")
	check(JSON.parse_string(JSON.stringify(loaded.character_beliefs(bird)))==JSON.parse_string(JSON.stringify(brain.character_beliefs(bird))),"effective opinions and their conviction survive reload")
	check(not loaded.validate_belief_update(nye,cancelled,withheld,hidden,"disagreement").ok,"evidence deduplication survives reload")
	check(loaded.character_context(chad,"alex",evidence).beliefs[0].position==chad.beliefs[0].position,"one character's revision does not alter another character")
	check(DirAccess.copy_absolute(PATH,PATH+".bak")==OK,"validated belief backup is available before corruption")
	var damaged_snapshot: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	damaged_snapshot.belief_revisions.bill_nye.education.position="An unsupported opinion absent from the evidence chain."
	var damaged_file:=FileAccess.open(PATH,FileAccess.WRITE)
	damaged_file.store_string(JSON.stringify(damaged_snapshot));damaged_file.close()
	var recovered:=Brain.new();recovered.memory_path=PATH
	check(recovered.load_memory() and recovered.memory_dirty and belief(recovered,nye).position==withheld,"a corrupt belief chain rejects the primary and recovers the valid backup")
	check(recovered.save_memory()==OK,"recovery replaces the invalid primary without overwriting its valid backup")

	var scoped:=Brain.new()
	var profile_a:="belief_fixture_host_"+str(Time.get_ticks_usec())
	var profile_b:=profile_a+"_second"
	check(scoped.set_host_profile(profile_a)==OK and scoped.load_memory(),"a fresh host profile opens for a belief isolation check")
	check(record(scoped,nye,evidence,speech,[update],"profile-revision") and scoped.save_memory()==OK,"first host's considered opinion is saved")
	var path_a:=scoped.memory_path
	check(scoped.set_host_profile(profile_b)==OK and scoped.load_memory(),"another host profile opens independently")
	var path_b:=scoped.memory_path
	check(scoped.belief_revisions.is_empty() and belief(scoped,nye).position==nye.beliefs[0].position,"another host cannot inherit the first host's changed opinions or evidence")
	check(scoped.set_host_profile(profile_a)==OK and scoped.load_memory() and belief(scoped,nye).position==position,"returning to the first host restores its changed view")
	for path in [path_a,path_b]:
		for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
	print("CHARACTER_BELIEFS ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," source=deterministic_host_validation")
	quit(0 if failures.is_empty() else 1)
