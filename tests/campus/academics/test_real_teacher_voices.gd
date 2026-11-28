extends SceneTree
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
const Profiles=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var profiles: Dictionary=Profiles.profiles()
 var available: Dictionary=Profiles.available_voice_ids()
 if profiles.size()!=21 or available.size()!=21:failures.append("Not all 21 teacher profiles have a usable model")
 var voices: Dictionary={}
 for id in Roster.PEOPLE:
  if not profiles.has(id):continue
  var profile: Dictionary=profiles[id]
  var identity:=str(profile.model)+":"+str(profile.speaker)
  if voices.has(identity):failures.append("Shared speaker identity: "+str(id))
  voices[identity]=id
 var synth:=Synth.new();root.add_child(synth)
 # This release test deliberately exercises the bundled legacy renderer, not
 # the normal OpenAI scheduler. Never enable legacy fallback in gameplay.
 synth.configure_provider(null,"legacy_offline")
 var wave_hashes: Dictionary={}
 var serial:=0
 for id in profiles:
  serial+=1
  var start:=Time.get_ticks_msec()
  var status: String=synth.request("ac_lab",serial,str(id),"Today we will measure voltage across this circuit.","voice-test-"+str(id))
  if status!="queued":failures.append("Voice unavailable for "+str(id)+": "+status);continue
  var event: Array=await synth.completed
  var elapsed:=Time.get_ticks_msec()-start
  var stream: AudioStreamWAV=event[3]
  if str(event[4])!="ok" or stream==null or stream.data.size()<20000:failures.append("No audible WAV for "+str(id)+": "+str(event[4]));continue
  var energy:=0.0
  for offset in range(0,stream.data.size()-1,100):energy+=absf(float(stream.data.decode_s16(offset)))
  if energy<10000.0:failures.append("Silent WAV for "+str(id))
  var fingerprint:=hash(stream.data)
  if wave_hashes.has(fingerprint):failures.append("Identical synthesized audio for "+str(id))
  wave_hashes[fingerprint]=id
  if elapsed>7000:failures.append("Voice exceeded latency target for "+str(id)+": "+str(elapsed)+" ms")
 synth.queue_free()
 for failure in failures:push_error(failure)
 print("REAL_TEACHER_VOICES ","PASS" if failures.is_empty() else "FAIL (%d)"%failures.size())
 quit(0 if failures.is_empty() else 1)
