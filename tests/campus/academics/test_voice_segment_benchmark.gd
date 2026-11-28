extends SceneTree
## Controlled loopback-free timing experiment. The imposed fake provider delays
## are disclosed; these measurements are NOT estimates of actual OpenAI latency.
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")

class BaselineSynth extends Synth:
	# Reproduce the former ordering: whole-utterance synthesis and waiting for
	# final provider accounting before delivering the playable clip.
	func _cloud_audio_ready(_result: Dictionary,_job: Dictionary) -> void:pass

class Provider extends Node:
	var requests:=0
	func configured() -> bool:return true
	func cancel_speech_request(_id: String) -> void:pass
	func speak(text: String,_draft: Dictionary,_voice: Variant,delivery: Dictionary) -> Dictionary:
		requests+=1
		await get_tree().create_timer(.03+text.length()*.0001).timeout
		var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=16000
		var data:=PackedByteArray();data.resize(9600);data.fill(20);stream.data=data
		var result:={"ok":true,"stream":stream}
		var callback: Callable=delivery.get("_audio_ready",Callable())
		if callback.is_valid():callback.call(result)
		await get_tree().create_timer(.15).timeout
		return result

var report:={"kind":"controlled_synthetic_provider","physical_audio_verified":false,"live_provider_verified":false,
	"fixture_generation_delay":"30 ms + 0.1 ms per input character","fixture_final_accounting_delay_ms":150,"samples":[]}

func _initialize() -> void:call_deferred("run")

func run() -> void:
	create_timer(15.).timeout.connect(func():push_error("segment benchmark timeout");quit(1))
	var text:="Start with the voltage across the resistor and keep the exact value of 12.5 volts while we work through the next calculation. "+"The current follows Ohm's law; use the same units throughout the calculation and explain the physical meaning. ".repeat(4)
	for mode in ["baseline_full_render_and_close","verified_first_part_prefetch"]:
		for iteration in 5:
			var sample:=await measure(mode,iteration,text)
			report.samples.append(sample)
	var summary: Dictionary={}
	for mode in ["baseline_full_render_and_close","verified_first_part_prefetch"]:
		var samples: Array=report.samples.filter(func(item):return item.mode==mode)
		var latencies: Array=samples.map(func(item):return item.first_playback_ms);latencies.sort()
		summary[mode]={"samples":samples.size(),"median_first_playback_ms":latencies[2],"p95_first_playback_ms":latencies[-1],"first_sample_playback_ms":samples[0].first_playback_ms,"requests_per_turn":samples[0].requests}
	report.summary=summary
	print("VOICE_SEGMENT_BENCHMARK_DATA ",JSON.stringify(report))
	assert(summary.verified_first_part_prefetch.median_first_playback_ms<summary.baseline_full_render_and_close.median_first_playback_ms)
	print("VOICE_SEGMENT_BENCHMARK PASS (controlled waits only; no real-provider speed claim)")
	await create_timer(.12).timeout
	quit()

func measure(mode: String,index: int,text: String) -> Dictionary:
	var provider:=Provider.new();root.add_child(provider)
	var synth: Node=BaselineSynth.new() if mode=="baseline_full_render_and_close" else Synth.new()
	root.add_child(synth);synth.configure_provider(provider)
	var player:=Player.new();root.add_child(player);player.set_process(false)
	var anchor:=Node3D.new();root.add_child(anchor)
	var started:=Time.get_ticks_usec()
	var sample:={"mode":mode,"iteration":index,"first_in_mode":index==0,"input_chars":text.length(),"first_playback_ms":-1.,"complete_ms":-1.,"requests":0}
	player.playback_started.connect(func(_channel,_serial,_at):
		if sample.first_playback_ms<0.:sample.first_playback_ms=(Time.get_ticks_usec()-started)/1000.)
	synth.segment_completed.connect(func(channel,serial,_key,stream,status,part,total,words):
		assert(status=="ok");player.deliver_segment(channel,serial,stream,part,total,words))
	synth.completed.connect(func(channel,serial,_key,stream,status):
		assert(status=="ok")
		if mode=="baseline_full_render_and_close":player.deliver_stream(channel,serial,stream)
		sample.complete_ms=(Time.get_ticks_usec()-started)/1000.)
	assert(player.accept("bench","Teacher",1,text,2,anchor,null,1.,{"expect_audio":true}))
	assert(synth.request("bench",1,"teacher",text,"bench",2,{"voice":"ash","segmented":mode!="baseline_full_render_and_close"})=="queued")
	while sample.complete_ms<0.:await process_frame
	assert(sample.first_playback_ms>=0.)
	sample.requests=provider.requests
	player.clear_session();synth.clear_session()
	player.queue_free();synth.queue_free();provider.queue_free();anchor.queue_free()
	await process_frame
	return sample
