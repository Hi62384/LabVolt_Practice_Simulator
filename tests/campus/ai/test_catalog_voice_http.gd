extends SceneTree

const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
const TeacherAI=preload("res://scripts/campus/academics/teacher_ai.gd")
func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	create_timer(25).timeout.connect(func():push_error("CATALOG_VOICE_HTTP timeout");quit(1))
	var client:=Client.new()
	client._environment_key_disconnected=true
	root.add_child(client)
	client.set_session_key("sk-fixture-12345678901234567890")
	client.configure("gpt-5.4-mini",64,"",true)
	var port:=OS.get_environment("LABVOLT_VOICE_FIXTURE_PORT")
	if port.is_empty():port="28823"
	assert(client.set_local_test_endpoint("http://127.0.0.1:"+port+"/v1"))
	assert(client.set_local_test_voice_endpoint("ws://127.0.0.1:"+port+"/v1"))
	var pcm:=PackedByteArray();pcm.resize(9600)
	var wav:=TeacherAI.wav_16k(pcm)
	for model in ["gpt-live-transcribe","gpt-realtime-whisper"]:
		var transcript: Dictionary=await client.transcribe_wav(wav,{"stt_enabled":true,"modalities":{"stt":model}})
		assert(transcript.get("ok",false) and transcript.get("text")=="What is voltage?")
	var draft:={"tts_enabled":true,"modalities":{"tts":"gpt-audio-1.5"}}
	var spoken: Dictionary=await client.speak("Voltage is 12.5 volts.",draft,"ash")
	assert(spoken.get("ok",false) and spoken.get("transcript_verified",false) and spoken.get("stream") is AudioStreamWAV)
	var mismatch: Dictionary=await client.speak("Mismatch this line.",draft,"ash")
	assert(not mismatch.get("ok",true) and not mismatch.has("stream"))
	client.queue_free();await process_frame
	print("CATALOG_VOICE_HTTP PASS")
	quit()
