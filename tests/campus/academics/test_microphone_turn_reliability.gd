extends SceneTree
## Native PCM/segmentation plus production router deduplication. Input audio and
## faculty delivery are explicit fixtures; this is not a hardware/provider test.
const Activity=preload("res://scripts/campus/computers/TeacherVoiceActivity.cs")
const Processor=preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs")
const Router=preload("res://scripts/campus/voice/npc_voice_router.gd")
class SessionFixture extends RefCounted:
 var roster:={1:{},2:{}}
 var online:=false
class GameFixture extends Node:
 var session:=SessionFixture.new()
class FacultyFixture extends Node:
 var accepted: Array=[]
 var resumed:=0
 var target:={"id":"mr_bro","room":"ac_lab","class_id":"fixture","student":""}
 func voice_target_valid(_peer: int,value: Dictionary) -> bool:return value.get("id","")==target.id
 func voice_candidates(_peer: int) -> Array:return [target]
 func attend_voice_target(_peer: int,_target: Dictionary) -> void:pass
 func resume_voice_target(_target: Dictionary) -> void:resumed+=1
 func accept_voice_turn(peer: int,_target: Dictionary,_wav: PackedByteArray,context: Dictionary) -> void:accepted.append([peer,context.token])

func _initialize() -> void:run.call_deferred()
func run() -> void:
 var pcm:=PackedByteArray();pcm.resize(640)
 for index in 320:pcm.encode_s16(index*2,roundi(sin(float(index)*TAU*220./16000.)*16.))
 var quiet_stats: Dictionary=Processor.new().InspectPcm16(pcm+pcm+pcm+pcm+pcm+pcm+pcm+pcm)
 assert(quiet_stats.has_signal and float(quiet_stats.peak)<.001,"Quiet samples must not need to pass automatic VAD")
 var activity=Activity.new()
 var onset: Dictionary=activity.BeginExplicitTurn()
 assert(onset.onset)
 for index in 25:assert(not activity.PushPcm(pcm,false).has("audio"))
 var silence:=PackedByteArray();silence.resize(640)
 for index in 120:assert(not activity.PushPcm(silence,false).has("audio"),"Holding PTT must survive a pause longer than automatic VAD's silence timeout")
 for index in 25:assert(not activity.PushPcm(pcm,false).has("audio"))
 var completed: Dictionary=activity.Flush()
 assert(completed.has("audio") and not completed.get("discarded",false) and completed.audio.size()==170*640 and completed.turn_id==onset.turn_id)
 activity.BeginExplicitTurn()
 for index in 30:activity.PushPcm(silence,false)
 assert(activity.Flush().get("discarded",false),"Silent PTT must not spend a transcription request")
 activity.BeginExplicitTurn()
 activity.PushPcm(pcm,false);activity.Reset()
 assert(activity.Flush().is_empty(),"Cancellation clears the explicit recording")
 var processor=Processor.new()
 processor.BeginResample16kTo24k(completed.audio)
 while not processor.IsResampleReady():await process_frame
 var converted: PackedByteArray=processor.TakeResampledPcm()
 assert(converted==processor.Resample16kTo24k(completed.audio),"Worker conversion must match synchronous native conversion exactly")
 assert(processor.TakeResampledPcm().is_empty(),"Worker output is consumed once")
 var game:=GameFixture.new();root.add_child(game)
 var faculty:=FacultyFixture.new();root.add_child(faculty)
 var router:=Router.new();root.add_child(router);router.set_process(false);router.game=game;router.faculty=faculty
 assert(router._begin_host(1,"turn_a",faculty.target))
 router._deliver(1,"turn_a",PackedByteArray([1,2]))
 router._deliver(1,"turn_a",PackedByteArray([1,2]))
 assert(faculty.accepted.size()==1,"Replayed delivery must not re-enter STT/dialogue")
 router.last_requests[1]=-1000
 assert(not router._begin_host(1,"turn_a",faculty.target),"Replayed begin cannot reset input_finished")
 assert(router._begin_host(1,"turn_b",faculty.target))
 router._deliver(1,"turn_a",PackedByteArray([1,2]))
 router._deliver(1,"turn_b",PackedByteArray([1,2]))
 assert(faculty.accepted.size()==2 and faculty.accepted.back()[1]=="turn_b")
 assert(router._begin_host(2,"turn_a",faculty.target),"Tokens are scoped to the speaking peer")
 router._deliver(2,"turn_a",PackedByteArray([1,2]))
 assert(faculty.accepted.size()==3 and faculty.accepted.back()[0]==2)
 router._cancel_host(1,"turn_b");router.last_requests[1]=-1000
 assert(not router._begin_host(1,"turn_b",faculty.target),"Canceled tokens cannot be replayed into a new billable recording")
 router.queue_free();faculty.queue_free();game.queue_free();await process_frame
 print("MICROPHONE_TURN_RELIABILITY PASS (quiet PTT, long pause, silence, worker PCM, cancellation and per-peer duplicate protection)")
 quit(0)
