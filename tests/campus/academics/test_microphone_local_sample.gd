extends SceneTree
const Meter=preload("res://scripts/campus/voice/microphone_meter.gd")
class Preferences extends RefCounted:
 var values:={"microphone_device":"Default","microphone_mode":"manual","microphone_muted":false}
class Client extends Node:
 var stt_enabled:=true
 var submitted: Array=[]
 var canceled: Array=[]
 func host_allowed() -> bool:return true
 func configured() -> bool:return true
 func transcribe_wav(wav: PackedByteArray,draft: Dictionary={}) -> Dictionary:
  submitted.append({"wav":wav,"request_id":draft.get("request_id","")})
  await get_tree().create_timer(.05).timeout
  return {"ok":true,"text":"A quiet test phrase."}
 func cancel_speech_request(id: String) -> void:canceled.append(id)
class Game extends Node:
 var client_preferences:=Preferences.new()
 var host_openai:=Client.new()
 func _ready() -> void:add_child(host_openai)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var game:=Game.new();root.add_child(game)
 var meter:=Meter.new();root.add_child(meter);meter.build(Callable(),game)
 meter._start_recording("local")
 assert(meter.running and meter.cloud_kind=="local")
 meter.microphone.set_process(false)
 var pcm:=PackedByteArray();pcm.resize(640)
 for index in 320:pcm.encode_s16(index*2,roundi(sin(float(index)*TAU*220./16000.)*16.))
 for index in 25:meter._packet(pcm,{"speech":false})
 meter._finish_cloud()
 assert(not meter.last_sample.is_empty() and meter.sample_stats.has_signal and not meter.speech_seen)
 assert(not meter.play_button.disabled and game.host_openai.submitted.is_empty(),"A local recording is replayable without any provider request")
 meter._play_sample()
 assert(is_instance_valid(meter.preview) and meter.preview.playing)
 meter._stop()
 assert(meter.preview==null and not meter.last_sample.is_empty(),"Playback stops without losing the selected sample")
 meter._start_cloud("transcription")
 assert(game.host_openai.submitted.size()==1 and not meter.running)
 assert(game.host_openai.submitted[0].wav.slice(44)==meter.last_sample,"Cloud testing uses the selected sample exactly once")
 await create_timer(.1).timeout
 assert(meter.stages.text.contains("A quiet test phrase.") and not meter.cloud_busy,"A valid quiet recording must reach STT despite local VAD rejecting it")
 meter._start_cloud("transcription")
 meter._stop();var previous:=meter.stages.text
 await create_timer(.1).timeout
 assert(game.host_openai.canceled.size()==1 and meter.stages.text==previous,"Canceled cloud tests cannot publish late results")
 meter.queue_free();game.queue_free();await process_frame
 print("MICROPHONE_LOCAL_SAMPLE PASS (local record/replay, quiet input, one selected-sample upload and cancellation; synthetic PCM and fixture STT)")
 quit()
