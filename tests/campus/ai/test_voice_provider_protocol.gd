extends SceneTree

const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Session=preload("res://scripts/campus/ai/openai_voice_session.gd")
const TeacherAI=preload("res://scripts/campus/academics/teacher_ai.gd")
const Usage=preload("res://scripts/campus/ai/openai_usage.gd")
const Pricing=preload("res://scripts/campus/ai/model_pricing.gd")
var failures: Array[String]=[]
var client: Node
var concurrent: Array=[]
var credential_results: Array=[]

func check(condition: bool,label: String) -> void:
	if not condition:failures.append(label);push_error(label)

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	create_timer(35).timeout.connect(func():push_error("VOICE_PROVIDER timeout");quit(1))
	client=Client.new();client._environment_key_disconnected=true;root.add_child(client)
	client.set_session_key("sk-fixture-12345678901234567890")
	client.configure("gpt-5.4-mini",64,"",true)
	client.tts_enabled=true;client.stt_enabled=true;client.live_enabled=false
	var port:=OS.get_environment("LABVOLT_VOICE_FIXTURE_PORT")
	if port.is_empty():port="28823"
	check(client.set_local_test_endpoint("http://127.0.0.1:"+port+"/v1"),"loopback HTTP fixture accepted")
	check(client.set_local_test_voice_endpoint("ws://127.0.0.1:"+port+"/v1"),"loopback websocket fixture accepted")
	check(not client.set_local_test_voice_endpoint("ws://example.com/v1"),"nonlocal fixture rejected")
	check((await client.list_models()).get("ok",false) and client.model_status("gpt-live-1.1","live").account_availability=="available","model availability comes from the current account catalog")
	await client.list_models("sk-fixture-preview-12345678901234567890")
	check(client.model_status("gpt-live-1.1","live").account_availability=="unknown","preview credentials cannot overwrite current-account availability")
	check(Models.voice_compatible("gpt-live-1.1",{"id":"voice_fixture"},"prompt"),"prompt voice accepted only by Live")
	check(not Models.voice_compatible("gpt-realtime-2.1-mini",{"id":"voice_fixture"},"prompt"),"Realtime rejects prompt voice")
	check(not Models.voice_compatible("gpt-realtime-2.1-mini","onyx","preset"),"legacy-only voice is not silently mapped")
	check(Models.lifecycle("gpt-4o-mini-tts","2027-01-06").status=="retired","shutdown date enforced")
	check(Models.lifecycle("gpt-future-voice").status=="unknown","unverified models remain unknown")
	check(Session.transcript_matches("Voltage is 12.5 volts.","voltage is 12.5 volts!"),"presentation punctuation is ignored")
	check(not Session.transcript_matches("Voltage is 12.5 volts.","Voltage is 125 volts."),"decimal value mismatch rejected")
	check(not Session.transcript_matches("The current is -2 A.","The current is 2 A."),"numeric sign mismatch rejected")
	var candidate: Dictionary=await client.create_prompt_voice("Original adult fixture","A clearly articulated original adult voice.","This is the representative audition sentence.")
	check(candidate.get("id")=="voice_fixture","prompt creation uses documented resource contract")
	var response: Dictionary=await client.speak("Voltage is 12.5 volts.",{},"ash",{"request_id":"verified"})
	check(response.get("ok",false) and response.get("transcript_verified",false),"Realtime audio requires matching transcript")
	check(response.get("stream") is AudioStreamWAV,"verified PCM becomes playable WAV")
	check(response.request_id=="verified" and client.request_journal[-1].request_id=="verified" and client.request_journal[-1].subsystem=="npc_speech","Speech completion is correlated in the central journal")
	var reused: Dictionary=await client.speak("A different line on the same voice.",{},"ash")
	check(reused.get("ok",false) and reused.get("timing",{}).get("connection_reused",false),"Compatible voice reuses a warm Realtime connection")
	if reused.get("ok",false):check(reused.stream.data.size()==9600,"Stale response audio is discarded")
	check(client.voice_diagnostics().idle_pool_size<=3,"Idle pool is bounded")
	var wrong: Dictionary=await client.speak("Mismatch this line.",{},"ash")
	check(not wrong.get("ok",true) and not wrong.has("stream"),"mismatched generated speech never returned")
	check(not wrong.get("retryable",true),"A billable transcript mismatch cannot automatically regenerate the same speech")
	check(wrong.get("measurement",{}).get("usage",{}).get("input")==100 and wrong.measurement.usage.get("output")==40,"Rejected speech preserves actual provider token usage")
	var silent: Dictionary=await client.speak("Silent audio fixture.",{},"ash")
	check(not silent.get("ok",true) and silent.get("code")=="speech_silent_audio" and not silent.has("stream"),"A matching transcript does not prove zero PCM is audible speech")
	check(silent.get("measurement",{}).get("usage",{}).get("output")==40,"Silent waveform rejection retains billable output usage")
	var missing: Dictionary=await client.speak("Missing transcript.",{},"ash")
	check(not missing.get("ok",true),"missing transcript never treated as verified speech")
	var limited: Dictionary=await client.speak("Rate limit this request.",{},"ash")
	check(not limited.get("ok",true) and limited.get("retryable",false) and not str(limited).contains("private fixture"),"rate limiting is retryable without private provider details")
	create_timer(.05).timeout.connect(func():client.cancel_speech_request("cancel_me"))
	var canceled: Dictionary=await client.speak("Cancel this request.",{},"ash",{"request_id":"cancel_me"})
	check(canceled.get("canceled",false) and not canceled.has("stream"),"canceled requests cannot publish late audio")
	check(client.request_journal[-1].canceled and client.request_journal[-1].request_id=="cancel_me","Canceled speech retains its exact request accounting")
	check(canceled.get("measurement",{}).get("usage",{}).get("input")==100 and canceled.measurement.usage.get("output")==40,"Canceled Realtime response drains terminal usage without publishing audio")
	for i in 5:_run_speech(i)
	_run_text()
	var data:=PackedByteArray();data.resize(16000*2*90)
	var wav:=TeacherAI.wav_16k(data)
	check(Client.valid_transcription_wav(wav),"90 second recording accepted")
	var transcript: Dictionary=await client.transcribe_wav(wav)
	check(transcript.get("ok",false) and str(transcript.get("text","")).length()>500,"long transcript retained without truncation")
	check(not str(transcript.get("request_id","")).is_empty() and client.request_journal.any(func(entry:Dictionary):return entry.request_id==transcript.request_id and entry.subsystem=="npc_microphone" and entry.purpose=="transcription"),"Transcription shares centralized request ID, subsystem and purpose accounting")
	while concurrent.size()<6:await process_frame
	check(concurrent.all(func(result: Dictionary):return result.get("ok",false)),"speech, text and transcription run in independent lanes")
	var live: Dictionary=await client.speak("Keep the same adult voice.",{"tts_enabled":true,"modalities":{"tts":"gpt-live-1.1"}},{"id":"voice_fixture"},{"voice_type":"prompt"})
	check(live.get("ok",false) and live.get("usage_confirmed",false),"Live renders verified prompt voice and finalizes usage")
	check(float(live.get("measurement",{}).get("usage",{}).get("seconds",0))==4.,"cumulative Live usage is counted once")
	var ready_times: Array=[]
	var early: Dictionary=await client.speak("Slow finalization should not delay playback.",{"tts_enabled":true,"modalities":{"tts":"gpt-live-1.1"}},"ash",{"request_id":"early_ready","_audio_ready":func(value: Dictionary):
		check(value.get("ok",false) and value.get("stream") is AudioStreamWAV,"Early callback carries only verified playable speech")
		ready_times.append(Time.get_ticks_msec())})
	check(early.get("ok",false) and ready_times.size()==1 and Time.get_ticks_msec()-int(ready_times[0])>=200,"Playable audio is delivered before slow final accounting completes")
	var close_canceled: Dictionary=await client.speak("Slow finalization cancellation.",{"tts_enabled":true,"modalities":{"tts":"gpt-live-1.1"}},"ash",{"request_id":"close_cancel","_audio_ready":func(_value: Dictionary):client.cancel_speech_request("close_cancel")})
	check(close_canceled.get("canceled",false) and not close_canceled.has("stream"),"Cancellation during finalization cannot resurrect a finished but canceled clip")
	var retired: Dictionary=client.create_live_conversation({},"ash")
	check(not retired.get("ok",true) and retired.get("code")=="native_live_retired","native Live conversation cannot be reactivated")
	# A session opened well after game boot must not treat its first silent
	# output packet as the end of a spoken turn. Test both delayed speech
	# and genuinely silent output using production event and validation code.
	var delayed:=Session.new()
	delayed._live=true;delayed._render_only=true;delayed.state="ready"
	delayed._expected_text="Hello there.";delayed._live_ready_at=10000
	var initial_silence:=PackedByteArray();initial_silence.resize(4800)
	delayed.receive_event({"type":"session.output_audio.delta","delta":Marshalls.raw_to_base64(initial_silence)})
	delayed._try_finish_live(14000)
	check(not delayed._render_finished,"Initial Live silence must not finish a render on a long-running game")
	delayed.receive_event({"type":"session.output_transcript.delta","delta":"Hello there."})
	delayed._last_transcript_at=14500
	delayed._try_finish_live(16000)
	check(not delayed._render_finished,"Transcript before actual audio must still wait for speech")
	delayed.receive_event({"type":"session.output_audio.delta","delta":Marshalls.raw_to_base64(PackedByteArray([100,0,100,0]))})
	delayed._last_voice_at=16000
	delayed._try_finish_live(17200)
	check(delayed._render_result.get("ok",false),"Delayed non-silent matching output validates after the quiet tail")
	delayed.free()
	var quick:=Session.new()
	quick._live=true;quick._render_only=true;quick.state="ready"
	quick._expected_text="Hello there.";quick._live_ready_at=10000
	var signal_pcm:=PackedByteArray();signal_pcm.resize(4800)
	for sample in 2400:signal_pcm.encode_s16(sample*2,1000)
	quick.receive_event({"type":"session.output_audio.delta","delta":Marshalls.raw_to_base64(signal_pcm)})
	quick._last_voice_at=10300
	quick.receive_event({"type":"session.output_transcript.delta","delta":"Hello there."})
	quick._last_transcript_at=10300
	quick._try_finish_live(10600)
	check(not quick._render_finished,"A network gap without received quiet PCM does not fast-finish")
	var tail:=PackedByteArray();tail.resize(24000)
	quick.receive_event({"type":"session.output_audio.delta","delta":Marshalls.raw_to_base64(tail)})
	quick._try_finish_live(10800)
	check(quick._render_result.get("ok",false) and quick._render_result.get("completion_mode","")=="matched_pcm_tail","Exact transcript and half-second actual silent tail release without another 1.1s wait")
	if quick._render_result.get("ok",false):
		check(quick._render_result.stream.data.size()==signal_pcm.size()+4800,"Trim only exact trailing silence and retain a 100ms tail")
		check(quick._render_result.stream.data.slice(0,signal_pcm.size())==signal_pcm,"Fast delivery preserves every voiced sample")
	quick.free()
	var silent_live:=Session.new()
	silent_live._live=true;silent_live._render_only=true;silent_live.state="ready"
	silent_live._expected_text="Hello there.";silent_live._live_ready_at=10000
	silent_live.receive_event({"type":"session.output_audio.delta","delta":Marshalls.raw_to_base64(initial_silence)})
	silent_live._try_finish_live(10000+Session.LIVE_SPEECH_START_TIMEOUT_MS)
	check(silent_live._render_result.get("code","")=="speech_silent_audio","A genuinely silent Live render still fails at a bounded startup deadline")
	silent_live.free()
	var speech_only:=Session.new()
	check(not speech_only.begin("gpt-live-1.1","ash","preset","sk-fixture-12345678901234567890","",[],"").get("ok",true),"transport refuses sessions without a supplied speech line")
	check(not speech_only.append_audio(PackedByteArray([1,2])),"speech transport never accepts player microphone audio")
	speech_only.free()
	var no_usage:=Session.new();no_usage._live=true;no_usage.state="ready"
	no_usage.receive_event({"type":"session.closed","reason":"failed"})
	check(not no_usage.usage_observed and not no_usage.final_usage_confirmed,"Absent usage is unknown rather than an invented provider-confirmed zero")
	no_usage.free()
	var missing_final:=Session.new();missing_final._live=true;missing_final.state="ready"
	missing_final.receive_event({"type":"session.usage.updated","usage":{"seconds":2.}})
	missing_final.receive_event({"type":"session.closed","reason":"failed"})
	check(missing_final.usage_observed and missing_final.latest_usage_seconds==2. and not missing_final.final_usage_confirmed,"Keep observed cumulative usage while marking incomplete final accounting")
	missing_final.free()
	var measured:=Usage.usage_from({"usage":{"input_tokens":100,"output_tokens":40,"input_token_details":{"text_tokens":100,"audio_tokens":0,"cached_tokens":0},"output_token_details":{"text_tokens":10,"audio_tokens":30}}})
	check(measured.get("audio_output")==30 and measured.get("text_output")==10,"Realtime audio usage separated from text tokens")
	check(Pricing.audio_cost(Pricing.pricing("gpt-realtime-2.1-mini","tts"),measured)==684000,"Realtime modality prices computed from actual token split")
	check(not FileAccess.get_file_as_string("user://host_openai.cfg").contains("sk-fixture"),"API key never persisted")
	for index in 5:_run_key_switch_speech(index)
	await create_timer(.025).timeout
	client.set_session_key("sk-fixture-replaced-12345678901234567890")
	while credential_results.size()<5:await process_frame
	check(credential_results.all(func(result: Dictionary):return result.get("canceled",false) and not result.has("stream")),"credential change cancels active and queued voice requests without late playback")
	check(client.active_requests.is_empty() and client.request_journal.any(func(entry:Dictionary):return entry.purpose=="voice_creation") and not JSON.stringify(client.request_diagnostics()).contains("sk-fixture"),"Control requests are visible, completed lanes clear, and diagnostics omit credentials")
	client.queue_free();await process_frame
	print("VOICE_PROVIDER_PROTOCOL ","PASS" if failures.is_empty() else "FAIL "+str(failures.size()))
	quit(0 if failures.is_empty() else 1)

func _run_speech(index: int) -> void:
	var result: Dictionary=await client.speak("Concurrent voice "+str(index)+".",{},"ash")
	concurrent.append(result)

func _run_text() -> void:
	var result: Dictionary=await client.respond("Concurrent text.")
	concurrent.append(result)

func _run_key_switch_speech(index: int) -> void:
	credential_results.append(await client.speak("Concurrent credential switch "+str(index)+".",{},"ash",{"request_id":"key_switch_"+str(index)}))
