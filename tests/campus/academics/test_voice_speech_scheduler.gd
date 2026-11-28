extends SceneTree
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
class Provider extends Node:
	var starts: Array=[]
	var cancellations: Array=[]
	var running:=0
	var peak:=0
	var attempts: Dictionary={}
	var held:=false
	func configured() -> bool:return true
	func cancel_speech_request(request_id: String) -> void:cancellations.append(request_id)
	func speak(text: String,_draft: Dictionary,voice: Variant,delivery: Dictionary) -> Dictionary:
		starts.append({"text":text,"voice":voice,"request_id":delivery.request_id,"delivery":delivery.duplicate(true)})
		running+=1;peak=maxi(peak,running)
		attempts[text]=int(attempts.get(text,0))+1
		await get_tree().process_frame
		await get_tree().process_frame
		while held:await get_tree().process_frame
		running-=1
		if text=="retry" and int(attempts[text])<2:return {"ok":false,"status":429,"retryable":true,"error":"rate limited"}
		if text=="invalid voice":return {"ok":false,"status":400,"error":"invalid custom voice","retryable":false}
		var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=16000;wav.data=PackedByteArray([0,0,100,0])
		return {"ok":true,"stream":wav}
var events: Array=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var provider:=Provider.new();root.add_child(provider)
	var synth:=Synth.new();root.add_child(synth);synth.configure_provider(provider)
	synth.completed.connect(func(channel,serial,key,stream,status):events.append({"channel":channel,"serial":serial,"key":key,"stream":stream,"status":status}))
	assert(synth.request("one",1,"bro","first","one",1,{"voice":"onyx","instructions":"Calm and reserved.","projection":"normal","profile_version":1,"delivery_key":"permanent-bro"})=="queued")
	assert(synth.request("two",1,"volts","second","two",1,{"voice":"cedar"})=="queued")
	assert(synth.request("three",1,"bird","third","three",1,{"voice":"sage"})=="queued")
	assert(synth.request("four",1,"stanley","fourth","four",1,{"voice":"echo"})=="queued")
	for frame in 12:await process_frame
	assert(events.size()==4 and provider.peak==3,"Speech runs concurrently without a global single busy failure.")
	assert(events.all(func(event):return event.status=="ok"))
	assert(provider.starts[0].voice=="onyx" and provider.starts[1].voice=="cedar")
	assert("PHRASE PERFORMANCE:" in provider.starts[0].delivery.instructions and provider.starts[0].delivery.phrase_texts==["first"],"The provider must receive finalized phrase guidance for the authoritative words.")
	assert(provider.starts[0].delivery.profile_version==1 and provider.starts[0].delivery.delivery_key!="permanent-bro" and not provider.starts[0].request_id.is_empty(),"Phrase guidance preserves identity and cancellation while contributing to delivery identity.")
	events.clear()
	assert(synth.request("owner",2,"bro","shared phrase","shared",1,{"voice":"onyx"})=="queued")
	assert(synth.request("listener",2,"bro","shared phrase","shared",1,{"voice":"onyx"})=="duplicate")
	synth.cancel("owner")
	for frame in 8:await process_frame
	assert(events.size()==2 and events[0].status=="cancelled" and events[1].channel=="listener" and events[1].status=="ok")
	assert(int(provider.attempts["shared phrase"])==1,"Deduplication preserves remaining listeners when one conversation leaves.")
	events.clear();provider.held=true
	assert(synth.request("same-room",10,"bro","shared turn","exact-listener",1,{"voice":"onyx"})=="queued")
	assert(synth.request("same-room",11,"bro","shared turn","exact-listener",1,{"voice":"onyx"})=="duplicate")
	await process_frame
	var previous_cancellations:=provider.cancellations.size()
	synth.cancel_utterance("same-room",10)
	assert(events.size()==1 and events[0].serial==10 and events[0].status=="cancelled" and provider.cancellations.size()==previous_cancellations,"Canceling one serial keeps another listener's shared request alive.")
	provider.held=false
	for frame in 8:await process_frame
	assert(events.size()==2 and events[1].serial==11 and events[1].status=="ok" and int(provider.attempts["shared turn"])==1)
	events.clear()
	assert(synth.request("retry",3,"bro","retry","retry",1,{"voice":"onyx"})=="queued")
	for frame in 5:await process_frame
	assert(synth.cloud_pending.size()==1 and events.is_empty())
	synth.cloud_pending[0].ready_at=0
	for frame in 8:await process_frame
	assert(events.size()==1 and events[0].status=="ok" and int(provider.attempts.retry)==2)
	assert(synth.request("bad",4,"bro","invalid voice","bad",1,{"voice":{"id":"voice_fixed"},"voice_type":"prompt"})=="queued")
	for frame in 8:await process_frame
	assert(events[-1].status=="unavailable" and int(provider.attempts["invalid voice"])==1)
	assert(synth.active.is_empty(),"A failed OpenAI request must never activate the legacy process path.")
	events.clear();provider.held=true
	assert(synth.request("cancel",5,"bro","late","cancel",1,{"voice":"onyx"})=="queued")
	await process_frame;synth.cancel("cancel")
	assert(events.size()==1 and events[0].status=="cancelled" and not provider.cancellations.is_empty())
	provider.held=false
	for frame in 8:await process_frame
	assert(events.size()==1 and synth.cloud_active.is_empty() and synth.cloud_keys.is_empty(),"Late cancelled results cannot resurrect playback.")
	for index in Synth.MAX_CLOUD_JOBS:
		assert(synth.request("queued",index+10,"bro","Bounded queue","bounded-%d"%index,0,{"voice":"onyx"})=="queued")
	assert(synth.request("queued",100,"bro","overflow","overflow",0,{"voice":"onyx"})=="busy")
	synth.clear_session();assert(synth.cloud_pending.is_empty() and synth.cloud_keys.is_empty())
	synth.queue_free();provider.queue_free();await process_frame
	print("VOICE_SPEECH_SCHEDULER PASS (concurrency, deduplication, retry, identity, cancellation, bounds)")
	quit()
