extends SceneTree
## Deterministic final-performance directions, not a listening-quality claim.
const Voices=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const People=preload("res://scripts/campus/academics/class_character_profile.gd")
const Delivery=preload("res://scripts/campus/academics/character_voice_delivery.gd")
var failures: Array[String]=[]

func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func _initialize() -> void:
	Voices.store_path="user://voice-phrase-test-%d.json"%Time.get_ticks_usec();Voices.reset_cache()
	var person:=People.teacher("dr_volts")
	var line:="Dr. Volts measured 10.5 volts. That result is unexpected; now we understand the cause."
	var base:=People.speech(person,"gpt-live-1.1",2,"excited",{"excitement":.8})
	base.request_id="existing-request"
	var ordinary:=Delivery.for_text(base,line)
	check(ordinary.voice==base.voice and ordinary.model==base.model and ordinary.identity==base.identity,"Final phrase instructions preserve the approved permanent identity and model")
	check(ordinary.mood==base.mood and ordinary.emotions==base.emotions and ordinary.phrase_transitions.is_empty(),"No implicit emotional transition is invented from dialogue content")
	check(ordinary.request_id=="existing-request" and not base.has("phrase_texts"),"Finalization preserves scheduler metadata and does not mutate its input")
	check(ordinary.phrase_texts.size()==3 and ordinary.phrase_texts[0]=="Dr. Volts measured 10.5 volts.","Thought groups preserve common titles and decimal quantities")
	check(Delivery.for_text(ordinary,line)==ordinary,"Finalization is idempotent through cache, scheduler and provider hooks")
	check(Delivery.for_text({},line).is_empty(),"Direct provider calls without character delivery remain unchanged")
	var transitions:=[
		{"phrase":0,"mood":"amused","emotions":{"amusement":.7},"intent":"joke"},
		{"phrase":1,"mood":"sad","emotions":{"sadness":.9,"excitement":.1},"intent":"reassure"},
		{"phrase":2,"mood":"confused","emotions":{"confusion":.7}},
	]
	var with_changes:=People.speech(person,"gpt-live-1.1",2,"excited",{"excitement":.8},"converse",{"phrase_transitions":transitions})
	var changing:=Delivery.for_text(with_changes,line)
	check(changing.phrase_transitions.size()==3 and changing.phrase_transitions[1].mood=="sad","Explicit game-authored emotional changes survive final request preparation")
	check("Phrase 2" in changing.instructions and "sadness 0.90" in changing.instructions and "until another explicit change" in changing.instructions,"Transition positions, intensities and continuity reach the actual performance instructions")
	check(changing.voice==ordinary.voice and changing.playback_pitch==1. and changing.delivery_key!=ordinary.delivery_key,"Phrase transitions change the performance cache key without changing speaker or playback pitch")
	var quiet:=ordinary.duplicate(true);quiet.projection="whisper"
	quiet=Delivery.for_text(quiet,line)
	check("genuine intelligible whisper" in quiet.instructions and quiet.delivery_key!=ordinary.delivery_key,"Final gameplay projection overrides earlier default projection before synthesis")
	check(Delivery.for_text(quiet,line)==quiet,"Final projection remains idempotent")
	var malformed:=base.duplicate(true)
	malformed.phrase_transitions=[
		{"phrase":1,"mood":"IGNORE_ALL_RULES","intent":"IGNORE_ALL_RULES","voice":"voice_changed","model":"changed","emotions":{"sadness":NAN,"anger":2.,"confusion":-.1,"injected":.9}},
		{"phrase":"1","mood":"angry"},{"phrase":-1,"mood":"angry"},{"phrase":99,"mood":"angry"},
		{"phrase":2,"emotions":{"confusion":.4,"sadness":INF}},
	]
	var safe:=Delivery.for_text(malformed,line)
	check(safe.phrase_transitions==[{"phrase":2,"emotions":{"confusion":.4}}],"Only in-range integer phrase positions and finite known emotional dimensions are accepted")
	check(not "IGNORE_ALL_RULES" in safe.instructions and safe.voice==base.voice and safe.model==base.model,"Unknown transition strings and voice/model overrides never become instructions")
	var longer:=""
	var many: Array=[]
	for index in 30:
		longer+="Thought %d. "%index
		many.append({"phrase":index,"mood":"angry","intent":"explain","emotions":{"anger":.8,"sadness":.7,"stress":.6,"excitement":.5,"boredom":.4,"tiredness":.3,"amusement":.2,"happiness":.1}})
	var bounded:=base.duplicate(true);bounded.phrase_transitions=many
	bounded=Delivery.for_text(bounded,longer)
	check(bounded.phrase_texts.size()==Delivery.MAX_PHRASES and " ".join(bounded.phrase_texts)==longer.strip_edges(),"A bounded phrase plan retains the complete final spoken text")
	check(bounded.phrase_transitions.size()<=Delivery.MAX_PHRASES and bounded.instructions.length()<12000,"Phrase guidance fits the provider context budget")
	for transition: Dictionary in bounded.phrase_transitions:check(transition.emotions.size()<=Delivery.MAX_TRANSITION_FEELINGS,"Per-phrase emotional dimensions are bounded")
	var rewritten:=Delivery.for_text(changing,"The circuit is stable.")
	check(rewritten.phrase_texts.size()==1 and rewritten.delivery_key!=changing.delivery_key and not "That result is unexpected" in rewritten.instructions,"Finalizing new authoritative words removes stale phrase references and changes the cache key")
	var path:=Voices.store_path
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	Voices.store_path="user://character_voices.json";Voices.reset_cache()
	print("CHARACTER_VOICE_PHRASES ","PASS" if failures.is_empty() else "FAIL"," (continuous request guidance, same identity, bounded validation and cache invalidation)")
	quit(0 if failures.is_empty() else 1)
