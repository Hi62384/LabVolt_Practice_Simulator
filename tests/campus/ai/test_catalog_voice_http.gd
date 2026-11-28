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
		var request_id: String="diagnostic_"+model
		var transcript: Dictionary=await client.transcribe_wav(wav,{"request_id":request_id,"stt_enabled":true,"modalities":{"stt":model},"_valid":func():return true,"_transcription_progress":func(_partial: String):pass})
		assert(transcript.get("ok",false) and transcript.get("text")=="What is voltage?")
		assert(transcript.get("request_id")==request_id)
		var journal: Dictionary=client.request_journal[-1]
		assert(journal.request_id==request_id and journal.purpose=="transcription")
		# The transport's plural timings must survive the central journal's
		# singular timing schema, including conversion and early delta evidence.
		for field in ["conversion_ms","connected_ms","committed_ms","first_delta_ms","total_ms"]:
			assert(transcript.get("timings",{}).has(field) and int(transcript.timings[field])>=0)
			assert(transcript.get("timing",{}).get(field)==transcript.timings[field])
			assert(journal.timing.get(field)==transcript.timings[field])
		assert(journal.timing.has("queue_ms"))
	var file_id:="diagnostic_file_stt"
	var file_transcript: Dictionary=await client.transcribe_wav(wav,{"request_id":file_id,"stt_enabled":true,"modalities":{"stt":"gpt-transcribe"}})
	assert(file_transcript.get("ok",false) and int(file_transcript.get("status",0))==200)
	assert(file_transcript.request_id==file_id and not file_transcript.get("retryable",true))
	assert(client.request_journal[-1].request_id==file_id and client.request_journal[-1].status==200)
	assert(client.active_requests.is_empty() and int(client._lane_active.get("transcription",0))==0)
	var saved:=FileAccess.get_file_as_string("user://host_openai.cfg")
	assert(not saved.contains("sk-fixture") and not saved.contains("Callable"))
	var draft:={"tts_enabled":true,"modalities":{"tts":"gpt-audio-1.5"}}
	var spoken: Dictionary=await client.speak("Voltage is 12.5 volts.",draft,"ash")
	assert(spoken.get("ok",false) and spoken.get("transcript_verified",false) and spoken.get("stream") is AudioStreamWAV)
	var mismatch: Dictionary=await client.speak("Mismatch this line.",draft,"ash")
	assert(not mismatch.get("ok",true) and not mismatch.has("stream"))
	client.queue_free();await process_frame
	print("CATALOG_VOICE_HTTP PASS")
	quit()
