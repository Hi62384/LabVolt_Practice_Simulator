extends SceneTree
## Real scheduler/player/transport with deterministic synthetic PCM. This is not
## a live-provider, physical-microphone or audible-speaker acceptance claim.
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Transfer=preload("res://scripts/campus/voice/speech_audio_transfer.gd")

class Provider extends Node:
	var calls: Array=[]
	var canceled: Array=[]
	var drain:=true
	var hold_audio:=false
	var fail_tail:=false
	func configured() -> bool:return true
	func cancel_speech_request(id: String) -> void:canceled.append(id)
	func speak(text: String,_draft: Dictionary,_voice: Variant,delivery: Dictionary) -> Dictionary:
		calls.append(delivery.request_id)
		await get_tree().create_timer(.02).timeout
		while hold_audio:await get_tree().process_frame
		if text=="timeout":return {"ok":false,"retryable":true,"error":"timeout"}
		if text=="mismatch":return {"ok":false,"retryable":true,"code":"speech_transcript_mismatch"}
		if fail_tail and str(delivery.request_id).ends_with("-part-1"):return {"ok":false,"error":"provider rejected tail"}
		var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=16000
		var data:=PackedByteArray();data.resize(9600);data.fill(20);stream.data=data
		var result:={"ok":true,"stream":stream}
		var callback: Callable=delivery.get("_audio_ready",Callable())
		if callback.is_valid():callback.call(result)
		while drain:await get_tree().process_frame
		return result

var segments: Array=[]
var completed: Array=[]
var finishes: Array=[]

func _initialize() -> void:call_deferred("run")

func run() -> void:
	create_timer(15.).timeout.connect(func():push_error("segment pipeline timeout");quit(1))
	var provider:=Provider.new();root.add_child(provider)
	var synth:=Synth.new();root.add_child(synth);synth.configure_provider(provider)
	var player:=Player.new();root.add_child(player);player.set_process(false)
	var anchor:=Node3D.new();root.add_child(anchor)
	var text:="The voltage is 12.5 volts, and the resistor is 10 ohms, so keep the decimal value intact while we consider the next step. "+"The current follows Ohm's law; use the same units throughout the calculation and explain the physical meaning. ".repeat(4)
	var parts:=Synth.speech_parts(text)
	assert(parts.size()==2 and " ".join(parts)==text.strip_edges())
	assert(Synth.speech_parts("Short reply.")==["Short reply."])
	assert(Synth.speech_parts("x".repeat(500)).size()==1,"No complete sentence means no forced split.")
	assert(player.accept("speech","Teacher",1,text,2,anchor,null,1.,{"expect_audio":true}))
	synth.segment_completed.connect(func(channel,serial,key,stream,status,index,total,words):
		segments.append({"index":index,"status":status,"words":words})
		if status=="ok":assert(player.deliver_segment(channel,serial,stream,index,total,words))
		else:player.fail_stream(channel,serial,status))
	synth.completed.connect(func(channel,serial,key,stream,status):completed.append({"channel":channel,"stream":stream,"status":status}))
	player.utterance_finished.connect(func(channel,serial,delivered):finishes.append([channel,serial,delivered]))
	assert(synth.request("speech",1,"teacher",text,"segmented",2,{"voice":"ash","segmented":true})=="queued")
	while segments.size()<2:await process_frame
	assert(completed.is_empty() and provider.calls.size()==2,"Both segments become playable while provider accounting still drains.")
	assert(player.active.speech.item.text==parts[0] and player.subtitles.speech.item.text==parts[0],"Caption follows the actually playing first part.")
	assert(player.active.speech.item.segments.size()==2 and not player.has_pending("speech",1))
	player._finished("speech",1)
	assert(finishes.is_empty() and player.active.speech.item.text==parts[1],"The second part continues the same utterance without duplicate progress.")
	player._finished("speech",1)
	assert(finishes==[["speech",1,true]])
	provider.drain=false
	while completed.is_empty():await process_frame
	assert(completed[0].status=="ok" and completed[0].stream.data.size()==19200,"A complete cache clip is assembled once after segment delivery.")

	# Failure after a played prefix retains precisely the unread tail.
	provider.fail_tail=true
	assert(player.accept("partial","Teacher",1,text,2,anchor,null,1.,{"expect_audio":true}))
	assert(synth.request("partial",1,"teacher",text,"partial",2,{"voice":"ash","segmented":true})=="queued")
	while completed.size()<2:await process_frame
	assert(player.active.has("partial") and not player.has_pending("partial",1))
	player._finished("partial",1)
	assert(not player.active.has("partial") and player.subtitles.partial.item.text==parts[1])
	player.presentations.partial.until=0;player._process(0.)
	assert(finishes.back()==["partial",1,false])
	provider.fail_tail=false

	# Unknown network outcomes and rejected speech validation never regenerate.
	for word in ["timeout","mismatch"]:
		var before:=provider.calls.size()
		assert(synth.request(word,1,"teacher",word,word,2,{"voice":"ash"})=="queued")
		while synth.cloud_keys.has(word):await process_frame
		assert(provider.calls.size()==before+1 and synth.cloud_pending.is_empty())
	provider.hold_audio=true
	assert(synth.request("hung",1,"teacher","hung","hung",2,{"voice":"ash"})=="queued")
	await process_frame
	var request_id: String=synth.cloud_active.keys()[0]
	synth.cloud_active[request_id].created=Time.get_ticks_msec()-Synth.CLOUD_TIMEOUT_MS-1
	synth._pump_cloud()
	assert(not synth.cloud_active.has(request_id) and request_id in provider.canceled and completed.back().status=="timeout")
	var completed_before:=completed.size();provider.hold_audio=false
	await create_timer(.05).timeout
	assert(completed.size()==completed_before,"A late result cannot resurrect a timed-out turn.")
	provider.drain=true
	assert(synth.request("draining",1,"teacher","Already playable.","draining",2,{"voice":"ash"})=="queued")
	while completed.size()==completed_before:await process_frame
	var draining_id: String=provider.calls[-1]
	var cancellations_before:=provider.canceled.size()
	synth.cancel("unrelated-room")
	assert(synth.cloud_active.has(draining_id) and provider.canceled.size()==cancellations_before,"Canceling another conversation must not interrupt successful usage finalization.")
	provider.drain=false
	while synth.cloud_active.has(draining_id):await process_frame
	var another:=Synth.new();assert(another.instance_id!=synth.instance_id);another.free()

	# Direct streamed speech renders sentences during text generation. The
	# authoritative response adopts exact matching audio, not a new request.
	var lines: Array[String]=["First sentence.","Second sentence.","Third sentence."]
	var whole:=" ".join(lines)
	var delivery:={"ok":true,"voice":"ash","model":"gpt-live-1.1","instructions":"Read the exact supplied words.","sentence_mode":true,"prefetch_turn":"fixture-turn","segmented":true}
	var before_prefetch:=provider.calls.size()
	var before_segments:=segments.size()
	var current:={"valid":true}
	provider.drain=true
	for index in lines.size():synth.prefetch_sentence("fixture-turn",index,lines[index],delivery,func():return current.valid)
	while provider.calls.size()<before_prefetch+2:await process_frame
	assert(provider.calls.size()==before_prefetch+2,"The first two completed text sentences start rendering before final text admission.")
	assert(player.accept("direct","Teacher",1,whole,2,anchor,null,1.,{"expect_audio":true}))
	assert(synth.request("direct",1,"teacher",whole,"direct-three",2,delivery)=="queued")
	while segments.size()<before_segments+2:await process_frame
	assert(player.active.direct.item.text==lines[0],"Playback starts from the first prefetched sentence.")
	provider.drain=false
	while synth.cloud_keys.has("direct-three"):await process_frame
	assert(provider.calls.size()==before_prefetch+3 and synth.prefetch_hits==3,"All three matching sentences are adopted without a second paid rendering.")
	assert(player.active.direct.item.segments.size()==3)
	for index in lines.size():
		assert(player.active.direct.item.text==lines[index])
		player._finished("direct",1)
	assert(finishes.back()==["direct",1,true],"One utterance completes after every sentence in order.")
	var before_cached:=provider.calls.size()
	var cache_delivery:=delivery.duplicate(true);cache_delivery.prefetch_turn="repeat-turn"
	assert(player.accept("repeat-direct","Teacher",1,whole,2,anchor,null,1.,{"expect_audio":true}))
	assert(synth.request("repeat-direct",1,"teacher",whole,"repeat-direct",2,cache_delivery)=="queued")
	while synth.cloud_keys.has("repeat-direct"):await process_frame
	assert(provider.calls.size()==before_cached and synth.part_cache_hits>=3,"Exact repeated sentence audio is reused without provider usage.")
	for index in lines.size():player._finished("repeat-direct",1)
	provider.hold_audio=true
	synth.prefetch_sentence("canceled-turn",0,"Unaccepted draft.",delivery,func():return current.valid)
	while synth.prefetch_running.is_empty():await process_frame
	var canceled_prefetch: String=synth.prefetch_running.keys()[0]
	current.valid=false;synth._pump_prefetch()
	assert(canceled_prefetch in provider.canceled and not synth.prefetch_turns.has("canceled-turn"),"Invalidated dialogue cancels its speculative render.")
	provider.hold_audio=false
	await create_timer(.05).timeout

	# Independent assemblies prevent concurrent part packets from mixing.
	var transfer:=Transfer.new()
	var bytes:=PackedByteArray();bytes.resize(24000);bytes.fill(10)
	for part in [1,0]:
		var meta:={"segment_total":2,"segment_index":part,"segment_text":parts[part],"sha256":Transfer.digest(bytes)}
		assert(transfer.push("net",1,24000,12000,16000,false,bytes.slice(12000),meta).ok)
	for part in [0,1]:
		var meta:={"segment_total":2,"segment_index":part,"segment_text":parts[part],"sha256":Transfer.digest(bytes)}
		var value:=transfer.push("net",1,24000,0,16000,false,bytes.slice(0,12000),meta)
		assert(value.ok and value.complete and value.segment_index==part and value.segment_text==parts[part])
	assert(transfer.reserved_bytes==0)

	# Caption placement uses the lower free region rather than moving above
	# a central interaction prompt which does not actually cover that region.
	root.size=Vector2i(1280,720)
	var prompt:=Control.new();prompt.position=Vector2(440,340);prompt.size=Vector2(400,50);root.add_child(prompt);prompt.add_to_group("subtitle_obstacle")
	var hotbar:=Control.new();hotbar.position=Vector2(300,620);hotbar.size=Vector2(680,70);root.add_child(hotbar);hotbar.add_to_group("subtitle_obstacle")
	assert(player.accept("layout","Teacher",1,"A short subtitle.",2,anchor))
	await process_frame;player._layout_subtitles()
	var label: Label=player.subtitles.layout.label
	assert(label.visible and label.position.y>=prompt.position.y+prompt.size.y+12 and label.position.y+label.size.y<=hotbar.position.y-12)
	assert(not label.get_global_rect().intersects(prompt.get_global_rect()) and not label.get_global_rect().intersects(hotbar.get_global_rect()))
	player.clear_session();synth.clear_session()
	player.queue_free();synth.queue_free();provider.queue_free();anchor.queue_free();prompt.queue_free();hotbar.queue_free()
	await process_frame;await create_timer(.12).timeout
	print("VOICE_SEGMENT_PIPELINE PASS (prefetch, early audio, ordered captions, partial failure, cancellation, bounded retries, transport, layout)")
	quit()
