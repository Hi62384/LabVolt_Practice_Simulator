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
	client.tts_enabled=true;client.stt_enabled=true;client.live_enabled=true
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
	var wrong: Dictionary=await client.speak("Mismatch this line.",{},"ash")
	check(not wrong.get("ok",true) and not wrong.has("stream"),"mismatched generated speech never returned")
	var missing: Dictionary=await client.speak("Missing transcript.",{},"ash")
	check(not missing.get("ok",true),"missing transcript never treated as verified speech")
	var limited: Dictionary=await client.speak("Rate limit this request.",{},"ash")
	check(not limited.get("ok",true) and limited.get("retryable",false) and not str(limited).contains("private fixture"),"rate limiting is retryable without private provider details")
	create_timer(.05).timeout.connect(func():client.cancel_speech_request("cancel_me"))
	var canceled: Dictionary=await client.speak("Cancel this request.",{},"ash",{"request_id":"cancel_me"})
	check(canceled.get("canceled",false) and not canceled.has("stream"),"canceled requests cannot publish late audio")
	for i in 5:_run_speech(i)
	_run_text()
	var data:=PackedByteArray();data.resize(16000*2*90)
	var wav:=TeacherAI.wav_16k(data)
	check(Client.valid_transcription_wav(wav),"90 second recording accepted")
	var transcript: Dictionary=await client.transcribe_wav(wav)
	check(transcript.get("ok",false) and str(transcript.get("text","")).length()>500,"long transcript retained without truncation")
	while concurrent.size()<6:await process_frame
	check(concurrent.all(func(result: Dictionary):return result.get("ok",false)),"speech, text and transcription run in independent lanes")
	var live: Dictionary=await client.speak("Keep the same adult voice.",{"tts_enabled":true,"modalities":{"tts":"gpt-live-1.1"}},{"id":"voice_fixture"},{"voice_type":"prompt"})
	check(live.get("ok",false) and live.get("usage_confirmed",false),"Live renders verified prompt voice and finalizes usage")
	check(float(live.get("measurement",{}).get("usage",{}).get("seconds",0))==4.,"cumulative Live usage is counted once")
	var created: Dictionary=client.create_live_conversation({"summary":"You are an original adult circuit teacher.","history":[]},"ash")
	check(created.get("ok",false),"guarded Live client delegation session starts")
	if created.get("ok",false):await _test_live_conversation(created.session)
	check(not client.create_live_conversation({},"ash",{"model":"gpt-realtime-2.1-mini"}).get("ok",true),"Live never substitutes a character's approved non-Live model")
	var measured:=Usage.usage_from({"usage":{"input_tokens":100,"output_tokens":40,"input_token_details":{"text_tokens":100,"audio_tokens":0,"cached_tokens":0},"output_token_details":{"text_tokens":10,"audio_tokens":30}}})
	check(measured.get("audio_output")==30 and measured.get("text_output")==10,"Realtime audio usage separated from text tokens")
	check(Pricing.audio_cost(Pricing.pricing("gpt-realtime-2.1-mini","tts"),measured)==684000,"Realtime modality prices computed from actual token split")
	check(not FileAccess.get_file_as_string("user://host_openai.cfg").contains("sk-fixture"),"API key never persisted")
	for index in 5:_run_key_switch_speech(index)
	await create_timer(.025).timeout
	client.set_session_key("sk-fixture-replaced-12345678901234567890")
	while credential_results.size()<5:await process_frame
	check(credential_results.all(func(result: Dictionary):return result.get("canceled",false) and not result.has("stream")),"credential change cancels active and queued voice requests without late playback")
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

func _test_live_conversation(session: Node) -> void:
	var audio: Array=[]
	var delegated: Array=[]
	var terminal: Array=[]
	var validated_line:="Voltage is the difference in electric potential. "+"电压是两点之间的电势差。".repeat(45)
	session.audio_received.connect(func(pcm: PackedByteArray):audio.append(pcm))
	session.closed.connect(func(summary: Dictionary):terminal.append(summary))
	session.delegation_requested.connect(func(id: String,history: Array):
		delegated.append(id)
		var words:=""
		for item in history:
			if item.get("role")=="user":words+=str(item.get("text",""))
		check(words=="What is voltage?","delegation uses accumulated transcript, not nonexistent utterance field")
		check(session.apply_delivery("Keep the same adult speaker and shape each phrase to the current emotion. ".repeat(24),id),"complete expressive delivery is refreshed through bounded Live instruction appends")
		check(session.submit_delegation(id,validated_line),"long multilingual authoritative dialogue is staged within each append token cap"))
	while session.state!="ready":await process_frame
	await create_timer(.1).timeout
	check(audio.is_empty(),"spontaneous independent model speech stays inaudible")
	var pcm:=PackedByteArray();pcm.resize(4800)
	session.append_audio(pcm)
	while audio.is_empty():await process_frame
	check(delegated.size()==1,"duplicate delegation event executes once")
	session.interrupt()
	check(not session.submit_delegation("delegation_fixture","Stale response."),"late delegated result rejected after interruption")
	session.close_session()
	while terminal.is_empty():await process_frame
	check(terminal[0].usage_confirmed,"Live graceful close observed")
