extends Node
## Bounded host speech scheduler. Provider failures never change vocal identity.
## The legacy process path is isolated behind explicit selection/test adapters.
signal completed(room: String,serial: int,key: String,stream: AudioStreamWAV,status: String)
signal segment_completed(room: String,serial: int,key: String,stream: AudioStreamWAV,status: String,index: int,total: int,text: String)
const Profiles=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Mixer=preload("res://scripts/campus/voice/audio_voice_mixer.gd")
const Delivery=preload("res://scripts/campus/academics/character_voice_delivery.gd")
const SpeechPlayer=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Speech=preload("res://scripts/campus/academics/character_speech.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const MAX_PREFETCH_ACTIVE:=2
const MAX_PREFETCH_ENTRIES:=12
const MAX_PART_CACHE:=32
const MAX_PART_CACHE_BYTES:=32000000
const MAX_JOBS:=6
const MAX_LISTENERS:=32
const TIMEOUT_MS:=30000
var pending: Array[Dictionary]=[]
var active: Dictionary={}
var keys: Dictionary={}
var launch_adapter: Callable
var running_adapter: Callable
var kill_adapter: Callable
var load_adapter: Callable
var profile_adapter: Callable
var model_adapter: Callable
var last_synthesis_ms := 0
const MAX_CLOUD_JOBS:=48
const MAX_CONCURRENT:=3
const MAX_ATTEMPTS:=3
const CLOUD_TIMEOUT_MS:=120000
var provider: Node
var legacy_enabled:=false
var cloud_pending: Array[Dictionary]=[]
var cloud_active: Dictionary={}
var cloud_keys: Dictionary={}
var session_epoch:=0
var request_serial:=0
var last_error:=""
var instance_id:=Crypto.new().generate_random_bytes(8).hex_encode()
var prefetch_turns: Dictionary={}
var prefetch_running: Dictionary={}
var prefetch_sequence:=0
var part_cache: Dictionary={}
var part_cache_order: Array[String]=[]
var part_cache_bytes:=0
var prefetch_hits:=0
var part_cache_hits:=0

func configure_provider(client: Node,mode: String="openai") -> void:
	if provider!=client or legacy_enabled!=(mode=="legacy_offline"):clear_session()
	provider=client;legacy_enabled=mode=="legacy_offline"

func diagnostics() -> Dictionary:
	var jobs: Array=[]
	for job in cloud_active.values():jobs.append({"character_id":job.id,"request_id":job.request_id,"age_ms":Time.get_ticks_msec()-int(job.created),"attempt":job.attempts,"state":"generating"})
	for job in cloud_pending:jobs.append({"character_id":job.id,"request_id":job.request_id,"age_ms":Time.get_ticks_msec()-int(job.created),"attempt":job.attempts,"state":"queued"})
	return {"provider":"legacy_offline" if legacy_enabled else "openai","active":cloud_active.size(),"queued":cloud_pending.size(),"jobs":jobs,"last_error":last_error,"last_synthesis_ms":last_synthesis_ms,"prefetch_active":prefetch_running.size(),"prefetch_turns":prefetch_turns.size(),"prefetch_hits":prefetch_hits,"part_cache_hits":part_cache_hits}


# Match the actual provider inputs, not transient job IDs, timestamps or
# local mixer gain. A different voice, mood instruction, model, phrase
# transition, or spoken text never reuses the wrong synthesized performance.
static func part_signature(text: String,delivery: Dictionary) -> String:
	var details:=Delivery.for_text(delivery,text)
	var model:=str(details.get("model",""))
	var family:=Models.verified_family(model)
	var speed: float=1.0 if family in Models.LIVE+Models.REALTIME or family=="gpt-audio-1.5" else float(details.get("speed",1.0))
	return JSON.stringify([text,model,details.get("voice","alloy"),details.get("voice_type","preset"),details.get("character_id",""),details.get("profile_version",0),details.get("instructions",""),speed]).sha256_text()

func _cache_part(text: String,delivery: Dictionary,stream: AudioStreamWAV) -> void:
	if not SpeechPlayer.valid_stream(stream) or stream.data.size()>MAX_PART_CACHE_BYTES:return
	var key:=part_signature(text,delivery)
	if part_cache.has(key):
		part_cache_bytes-=part_cache[key].data.size();part_cache_order.erase(key)
	part_cache[key]=stream;part_cache_order.append(key);part_cache_bytes+=stream.data.size()
	while part_cache.size()>MAX_PART_CACHE or part_cache_bytes>MAX_PART_CACHE_BYTES:
		var oldest: String=part_cache_order.pop_front()
		part_cache_bytes-=part_cache[oldest].data.size();part_cache.erase(oldest)

func prefetch_sentence(owner: String,index: int,text: String,delivery: Dictionary,guard: Callable) -> void:
	if not is_inside_tree() or not is_instance_valid(provider) or legacy_enabled or owner.is_empty() or index<0 or index>=Speech.MAX_SEGMENTS or text.is_empty() or text.length()>Speech.MAX_TEXT:return
	if not bool(delivery.get("ok",false)) or not guard.is_valid() or not bool(guard.call()):return
	var signature:=part_signature(text,delivery)
	if part_cache.has(signature):return
	var entries:=0
	for existing_parts in prefetch_turns.values():entries+=existing_parts.size()
	var parts: Dictionary=prefetch_turns.get_or_add(owner,{})
	if parts.has(index) or entries>=MAX_PREFETCH_ENTRIES:return
	# Identical earlier sentences can populate the exact-performance cache;
	# don't speculate a second billable rendering within the same turn.
	for earlier in parts.values():
		if earlier.signature==signature:return
	prefetch_sequence+=1
	var request_id:="voice-%s-%d-prefetch-%d-part-%d"%[instance_id,session_epoch,prefetch_sequence,index]
	parts[index]={"signature":signature,"text":text,"delivery":Delivery.for_text(delivery,text),"owner":owner,"index":index,"request_id":request_id,"guard":guard,"created":Time.get_ticks_msec(),"epoch":session_epoch,"done":false,"canceled":false}
	_pump_prefetch()

func _prefetch_valid(entry: Dictionary) -> bool:
	if bool(entry.get("canceled",false)) or int(entry.epoch)!=session_epoch or Time.get_ticks_msec()-int(entry.created)>CLOUD_TIMEOUT_MS:return false
	var guard: Callable=entry.guard
	return guard.is_valid() and bool(guard.call())

func _cancel_prefetch_entry(entry: Dictionary) -> void:
	entry.canceled=true
	if prefetch_running.has(entry.request_id) and is_instance_valid(provider) and provider.has_method("cancel_speech_request"):
		provider.cancel_speech_request(str(entry.request_id))

func discard_prefetch(owner: String) -> void:
	var parts: Dictionary=prefetch_turns.get(owner,{})
	prefetch_turns.erase(owner)
	for entry: Dictionary in parts.values():_cancel_prefetch_entry(entry)

func _pump_prefetch() -> void:
	if not is_inside_tree() or not is_instance_valid(provider):return
	for owner in prefetch_turns.keys():
		var parts: Dictionary=prefetch_turns[owner]
		for index in parts.keys():
			var entry: Dictionary=parts[index]
			if not _prefetch_valid(entry):
				_cancel_prefetch_entry(entry);parts.erase(index)
		if parts.is_empty():prefetch_turns.erase(owner)
	for owner in prefetch_turns.keys():
		var parts: Dictionary=prefetch_turns[owner]
		for index in parts.keys():
			if prefetch_running.size()>=MAX_PREFETCH_ACTIVE:return
			var entry: Dictionary=parts[index]
			if entry.done or prefetch_running.has(entry.request_id):continue
			if part_cache.has(entry.signature):
				entry.stream=part_cache[entry.signature];entry.done=true;continue
			prefetch_running[entry.request_id]=entry
			_render_prefetch(entry)

func _render_prefetch(entry: Dictionary) -> void:
	var details: Dictionary=entry.delivery.duplicate(true)
	details.request_id=entry.request_id;details.correlation_id=entry.owner
	details._valid=_prefetch_valid.bind(entry)
	details._audio_ready=_prefetch_audio_ready.bind(entry)
	var result: Dictionary=await provider.speak(str(entry.text),{},details.get("voice","alloy"),details)
	prefetch_running.erase(entry.request_id)
	if _prefetch_valid(entry):
		if not entry.has("stream"):_prefetch_audio_ready(result,entry)
		entry.result=result;entry.done=true
	if is_inside_tree():_pump_prefetch.call_deferred()

func _prefetch_audio_ready(result: Dictionary,entry: Dictionary) -> void:
	if not is_inside_tree() or not _prefetch_valid(entry) or entry.has("stream"):return
	if bool(result.get("ok",false)) and result.get("stream") is AudioStreamWAV and SpeechPlayer.valid_stream(result.stream):
		entry.stream=result.stream

func _claim_prefetch(job: Dictionary) -> void:
	var owner:=str(job.delivery.get("prefetch_turn",""))
	var parts: Dictionary=prefetch_turns.get(owner,{})
	var words: Array=job.get("parts",[job.text])
	for index in parts.keys():
		var entry: Dictionary=parts[index]
		if int(index)>=words.size():
			_cancel_prefetch_entry(entry);parts.erase(index);continue
		var details: Dictionary=_part_details(job,int(index)) if words.size()>1 else job.delivery
		if entry.signature!=part_signature(str(words[index]),details):
			_cancel_prefetch_entry(entry);parts.erase(index)
	if parts.is_empty():prefetch_turns.erase(owner)

func _take_prefetched(job: Dictionary,index: int,text: String,delivery: Dictionary) -> Dictionary:
	if not job.delivery.get("sentence_mode",false):return {}
	var signature:=part_signature(text,delivery)
	var owner:=str(job.delivery.get("prefetch_turn",""))
	var parts: Dictionary=prefetch_turns.get(owner,{})
	var entry: Dictionary=parts.get(index,{})
	if not entry.is_empty() and entry.signature==signature:
		# Join the already dispatched sentence instead of issuing a duplicate
		# paid request. An early verified waveform is enough; accounting drains.
		_pump_prefetch()
		while is_inside_tree() and cloud_active.has(job.request_id) and _prefetch_valid(entry) and not entry.has("stream") and not entry.done:await get_tree().process_frame
		parts.erase(index)
		if parts.is_empty():prefetch_turns.erase(owner)
		if not is_inside_tree() or not cloud_active.has(job.request_id) or not _prefetch_valid(entry):return {"ok":false,"canceled":true,"error":"Sentence canceled."}
		prefetch_hits+=1
		if entry.has("stream"):return {"ok":true,"stream":entry.stream}
		return entry.get("result",{"ok":false,"error":"Sentence unavailable."})
	if part_cache.has(signature):
		part_cache_hits+=1
		return {"ok":true,"stream":part_cache[signature]}
	return {}

func request(room: String,serial: int,id: String,text: String,key: String,priority:=0,delivery: Dictionary={}) -> String:
	if room.is_empty() or room.length()>160 or serial<1 or serial>2147483647 or id.is_empty() or text.is_empty() or text.length()>SpeechPlayer.MAX_TEXT or key.is_empty() or key.length()>128:return "invalid"
	if legacy_enabled or profile_adapter.is_valid() or launch_adapter.is_valid():return _request_legacy(room,serial,id,text,key,priority)
	if not is_instance_valid(provider):return "unavailable"
	if provider.has_method("configured") and not provider.configured():return "unavailable"
	if delivery.has("ok") and not bool(delivery.ok):return "incompatible_voice"
	if cloud_keys.has(key):
		discard_prefetch(str(delivery.get("prefetch_turn","")))
		var listeners: Array=cloud_keys[key]
		for listener in listeners:
			if str(listener.room)==room and int(listener.serial)==serial:return "duplicate"
		if listeners.size()>=MAX_LISTENERS:return "busy"
		listeners.append({"room":room,"serial":serial})
		for running: Dictionary in cloud_active.values():
			if str(running.key)==key and running.get("parts",[]).size()>1:
				for index in running.get("part_streams",{}):segment_completed.emit.call_deferred(room,serial,key,running.part_streams[index],"ok",int(index),running.parts.size(),str(running.parts[index]))
		for queued_job in cloud_pending:
			if str(queued_job.key)==key:queued_job.priority=maxi(int(queued_job.priority),priority)
		return "duplicate"
	if cloud_pending.size()+cloud_active.size()>=MAX_CLOUD_JOBS:return "busy"
	request_serial+=1
	var now:=Time.get_ticks_msec()
	var details:=Delivery.for_text(delivery,text)
	var request_id:="voice-%s-%d-%d"%[instance_id,session_epoch,request_serial]
	details.request_id=request_id
	details.correlation_id=request_id;details.retry_count=0
	var job:={"room":room,"serial":serial,"id":id,"text":text,"key":key,"priority":clampi(priority,0,14),"delivery":details,"request_id":request_id,
		"created":now,"ready_at":now,"attempts":0,"epoch":session_epoch}
	if bool(delivery.get("sentence_mode",false)):
		job.parts=Speech.sentence_parts(text,true)
		_claim_prefetch(job)
	elif bool(delivery.get("segmented",false)):
		job.parts=speech_parts(text)
	cloud_keys[key]=[{"room":room,"serial":serial}]
	cloud_pending.append(job)
	_pump_cloud.call_deferred()
	return "queued"

func _pump_cloud() -> void:
	if not is_inside_tree() or not is_instance_valid(provider):return
	var now:=Time.get_ticks_msec()
	for request_id in cloud_active.keys():
		var running: Dictionary=cloud_active[request_id]
		if now-int(running.created)<CLOUD_TIMEOUT_MS:continue
		cloud_active.erase(request_id)
		_cancel_provider_job(running)
		last_error="Speech generation timed out. The written response is preserved."
		_complete_cloud(running,null,"timeout")
	for index in range(cloud_pending.size()-1,-1,-1):
		if now-int(cloud_pending[index].created)>=CLOUD_TIMEOUT_MS:
			var expired: Dictionary=cloud_pending.pop_at(index);_complete_cloud(expired,null,"expired")
	while cloud_active.size()<MAX_CONCURRENT and not cloud_pending.is_empty():
		var next:=-1
		var best:=-INF
		for index in cloud_pending.size():
			var job: Dictionary=cloud_pending[index]
			if int(job.ready_at)>now:continue
			var same_character:=false
			for running in cloud_active.values():
				if str(running.id)==str(job.id):same_character=true;break
			if same_character:continue
			var score:=float(job.priority)+float(now-int(job.created))/5000.
			if score>best:best=score;next=index
		if next<0:break
		var job: Dictionary=cloud_pending.pop_at(next)
		cloud_active[job.request_id]=job
		_run_cloud(job)

func _run_cloud(job: Dictionary) -> void:
	if job.get("parts",[]).size()>1:
		await _run_segmented(job)
		return
	job.attempts=int(job.attempts)+1
	job.delivery.retry_count=int(job.attempts)-1
	job.delivery.request_id=str(job.request_id)+( "-retry-"+str(job.delivery.retry_count) if int(job.attempts)>1 else "")
	var voice: Variant=job.delivery.get("voice","alloy")
	job.delivery._audio_ready=_cloud_audio_ready.bind(job)
	var result: Dictionary=await _take_prefetched(job,0,str(job.text),job.delivery)
	if result.is_empty():result=await provider.speak(str(job.text),{},voice,job.delivery)
	if not is_inside_tree() or int(job.epoch)!=session_epoch or not cloud_active.has(job.request_id):return
	cloud_active.erase(job.request_id)
	if bool(job.get("delivered",false)):
		_pump_cloud.call_deferred()
		return
	if bool(result.get("ok",false)) and result.get("stream") is AudioStreamWAV and SpeechPlayer.valid_stream(result.stream):
		if job.delivery.get("sentence_mode",false):_cache_part(str(job.text),job.delivery,result.stream)
		var stream: AudioStreamWAV=Mixer.normalise(result.stream,job.delivery)
		last_synthesis_ms=Time.get_ticks_msec()-int(job.created)
		_complete_cloud(job,stream,"ok")
	else:
		var reason:=str(result.get("error","speech unavailable"))
		var retryable:=_safe_to_retry(result)
		if retryable and int(job.attempts)<MAX_ATTEMPTS and Time.get_ticks_msec()-int(job.created)<CLOUD_TIMEOUT_MS and cloud_keys.has(job.key):
			var retry_after:=clampi(int(result.get("retry_after_ms",0)),0,15000)
			job.ready_at=Time.get_ticks_msec()+maxi(retry_after,500*(1<<int(job.attempts)))
			cloud_pending.append(job)
		else:
			last_error=reason.left(240)
			_complete_cloud(job,null,"unavailable")
	_pump_cloud.call_deferred()

static func _safe_to_retry(result: Dictionary) -> bool:
	# A timeout, lost response or transcript mismatch may already be billable.
	# Retry only explicit rejection before generation, never an unknown outcome.
	if bool(result.get("canceled",false)):return false
	return int(result.get("status",0))==429 or str(result.get("code","")) in ["429","rate_limit_exceeded","queue_full"] or str(result.get("error","")).to_lower()=="busy"

func _cloud_audio_ready(result: Dictionary,job: Dictionary) -> void:
	if not is_inside_tree() or int(job.epoch)!=session_epoch or not cloud_active.has(job.request_id) or bool(job.get("delivered",false)):return
	if not bool(result.get("ok",false)) or not result.get("stream") is AudioStreamWAV or not SpeechPlayer.valid_stream(result.stream):return
	job.delivered=true
	if job.delivery.get("sentence_mode",false):_cache_part(str(job.text),job.delivery,result.stream)
	last_synthesis_ms=Time.get_ticks_msec()-int(job.created)
	_complete_cloud(job,Mixer.normalise(result.stream,job.delivery),"ok")

static func speech_parts(text: String) -> Array[String]:
	var result: Array[String]=[text]
	if text.length()<=420:return result
	# At most two renders: first complete thought + remainder. No word, number,
	# equation or abbreviation is cut to meet an arbitrary token boundary.
	var phrases:=Delivery.phrase_texts(text)
	var offset:=0
	for index in range(phrases.size()-1):
		var found:=text.find(phrases[index],offset)
		if found<0:return result
		offset=found+phrases[index].length()
		var first:=text.substr(0,offset).strip_edges()
		if first.length()<100 or first[-1] not in ".!?":continue
		if first.length()>360:break
		var tail:=text.substr(offset).strip_edges()
		if tail.length()<100:break
		return [first,tail]
	return result

func _run_segmented(job: Dictionary) -> void:
	job.attempts=int(job.attempts)+1
	job.part_streams={};job.started_parts={};job.finished_parts={};job.part_failures={}
	_start_part(job,0)
	while is_inside_tree() and int(job.epoch)==session_epoch and cloud_active.has(job.request_id) and job.finished_parts.size()<job.parts.size():await get_tree().process_frame
	if not is_inside_tree() or int(job.epoch)!=session_epoch or not cloud_active.has(job.request_id):return
	cloud_active.erase(job.request_id)
	if job.part_failures.is_empty() and job.part_streams.size()==job.parts.size():
		var combined:=_combine_parts(job)
		_complete_cloud(job,combined,"ok" if combined!=null else "invalid audio")
	else:
		last_error="Part of the voice response was unavailable. The written response is preserved."
		_complete_cloud(job,null,"unavailable")
	_pump_cloud.call_deferred()

func _start_part(job: Dictionary,index: int) -> void:
	if not is_inside_tree() or int(job.epoch)!=session_epoch or not cloud_active.has(job.request_id) or job.started_parts.has(index):return
	job.started_parts[index]=true
	var details:=_part_details(job,index)
	details._audio_ready=_part_audio_ready.bind(job,index)
	var result: Dictionary=await _take_prefetched(job,index,str(job.parts[index]),details)
	if result.is_empty():result=await provider.speak(str(job.parts[index]),{},details.get("voice","alloy"),details)
	if not is_inside_tree() or int(job.epoch)!=session_epoch or not cloud_active.has(job.request_id):return
	if not job.part_streams.has(index):_part_audio_ready(result,job,index)
	if not job.part_streams.has(index):
		job.part_failures[index]=true
		for listener: Dictionary in cloud_keys.get(job.key,[]):segment_completed.emit(str(listener.room),int(listener.serial),str(job.key),null,"unavailable",index,job.parts.size(),str(job.parts[index]))
		# Do not spend another request generating a tail after the first part
		# already failed; the written response remains the recovery path.
		for remaining in range(index+1,job.parts.size()):job.part_failures[remaining]=true;job.finished_parts[remaining]=true
	job.finished_parts[index]=true
	if job.part_streams.has(index) and index+1<job.parts.size():_start_part(job,index+1)

func _part_details(job: Dictionary,index: int) -> Dictionary:
	var details: Dictionary=job.delivery.duplicate(true)
	details.request_id=str(job.request_id)+"-part-"+str(index)
	# Phrase-transition indices belong to the original full response. Apply the
	# last preceding transition at the start of the next render, then reindex.
	var offset:=0
	for preceding in index:offset+=Delivery.phrase_texts(str(job.parts[preceding])).size()
	var transitions: Array=[]
	var inherited: Dictionary={"phrase":0}
	for transition: Dictionary in details.get("phrase_transitions",[]):
		var at:=int(transition.get("phrase",-1))
		if at<offset:
			for field: String in ["mood","intent","emotions"]:
				if transition.has(field):inherited[field]=transition[field]
		elif at-offset<Delivery.phrase_texts(str(job.parts[index])).size():
			var next:=transition.duplicate(true);next.phrase=at-offset;transitions.append(next)
	if inherited.size()>1:transitions.push_front(inherited)
	details.phrase_transitions=transitions
	details=Delivery.for_text(details,str(job.parts[index]))
	return details

func _part_audio_ready(result: Dictionary,job: Dictionary,index: int) -> void:
	if not is_inside_tree() or int(job.epoch)!=session_epoch or not cloud_active.has(job.request_id) or job.part_streams.has(index):return
	if not bool(result.get("ok",false)) or not result.get("stream") is AudioStreamWAV or not SpeechPlayer.valid_stream(result.stream):return
	if job.delivery.get("sentence_mode",false):_cache_part(str(job.parts[index]),_part_details(job,index),result.stream)
	var stream:=Mixer.normalise(result.stream,job.delivery)
	job.part_streams[index]=stream
	if index==0:last_synthesis_ms=Time.get_ticks_msec()-int(job.created)
	for listener: Dictionary in cloud_keys.get(job.key,[]):segment_completed.emit(str(listener.room),int(listener.serial),str(job.key),stream,"ok",index,job.parts.size(),str(job.parts[index]))
	# Start the next part while this verified part plays and the previous
	# transport drains final accounting. Provider lane limits still apply.
	if index+1<job.parts.size():_start_part.call_deferred(job,index+1)

func _combine_parts(job: Dictionary) -> AudioStreamWAV:
	var first: AudioStreamWAV=job.part_streams[0]
	var data:=PackedByteArray()
	for index in job.parts.size():
		var part: AudioStreamWAV=job.part_streams[index]
		if part.mix_rate!=first.mix_rate or part.stereo!=first.stereo or data.size()+part.data.size()>SpeechPlayer.MAX_WAV_BYTES:return null
		data.append_array(part.data)
	var result:=first.duplicate() as AudioStreamWAV
	result.data=data
	return result

func _cancel_provider_job(job: Dictionary) -> void:
	discard_prefetch(str(job.delivery.get("prefetch_turn","")))
	if not is_instance_valid(provider) or not provider.has_method("cancel_speech_request"):return
	provider.cancel_speech_request(str(job.delivery.get("request_id",job.request_id)))
	for index in job.get("started_parts",{}):provider.cancel_speech_request(str(job.request_id)+"-part-"+str(index))

func _complete_cloud(job: Dictionary,stream: AudioStreamWAV,status: String) -> void:
	discard_prefetch(str(job.delivery.get("prefetch_turn","")))
	var listeners: Array=cloud_keys.get(job.key,[])
	cloud_keys.erase(job.key)
	for listener in listeners:completed.emit(str(listener.room),int(listener.serial),str(job.key),stream,status)

func _cancel_cloud(room: String,serial: int=0) -> void:
	for key in cloud_keys.keys():
		var listeners: Array=cloud_keys[key]
		for index in range(listeners.size()-1,-1,-1):
			if str(listeners[index].room)==room and (serial==0 or int(listeners[index].serial)==serial):
				var listener: Dictionary=listeners.pop_at(index)
				completed.emit(room,int(listener.serial),str(key),null,"cancelled")
		if listeners.is_empty():cloud_keys.erase(key)
	for index in range(cloud_pending.size()-1,-1,-1):
		if not cloud_keys.has(cloud_pending[index].key):
			discard_prefetch(str(cloud_pending[index].delivery.get("prefetch_turn","")))
			cloud_pending.remove_at(index)
	for request_id in cloud_active.keys():
		var job: Dictionary=cloud_active[request_id]
		if bool(job.get("delivered",false)):continue
		if cloud_keys.has(job.key):continue
		cloud_active.erase(request_id)
		_cancel_provider_job(job)
	_pump_cloud.call_deferred()

func _request_legacy(room: String,serial: int,id: String,text: String,key: String,priority := 0) -> String:
	if room.is_empty() or serial<1 or text.is_empty() or text.length()>SpeechPlayer.MAX_TEXT or key.is_empty():return "invalid"
	var profiles: Dictionary=profile_adapter.call() if profile_adapter.is_valid() else Profiles.profiles()
	var profile: Dictionary=profiles.get(id,{})
	var model:=str(profile.get("model",""))
	var model_disk:=Profiles.resolve_model(model)
	var model_valid:=not model_disk.is_empty()
	if model_adapter.is_valid():model_valid=bool(model_adapter.call(model))
	if not model_valid:return "unavailable"
	if keys.has(key):
		if keys[key].size()>=MAX_LISTENERS:return "busy"
		keys[key].append({"room":room,"serial":serial})
		for queued in pending:
			if queued.key==key:queued.priority=maxi(int(queued.priority),priority)
		return "duplicate"
	if pending.size()+(1 if not active.is_empty() else 0)>=MAX_JOBS:return "busy"
	var job:={"room":room,"serial":serial,"id":id,"text":text,"key":key,"model":model,"model_disk":model_disk,"speaker":int(profile.speaker),"rate":float(profile.rate),"gain":float(profile.gain),"pause":int(profile.pause_ms),"priority":priority}
	keys[key]=[{"room":room,"serial":serial}];pending.append(job)
	# Launch failures may finish immediately. Give callers a chance to connect
	# or await completion before the worker can emit a result.
	if active.is_empty():_start_next.call_deferred()
	return "queued"

func cancel(room: String) -> void:
	cancel_utterance(room,0)

func cancel_utterance(room: String,serial: int) -> void:
	_cancel_cloud(room,serial)
	for key in keys.keys():
		var listeners: Array=keys[key]
		for index in range(listeners.size()-1,-1,-1):
			if str(listeners[index].room)==room and (serial==0 or int(listeners[index].serial)==serial):
				completed.emit(str(listeners[index].room),int(listeners[index].serial),str(key),null,"cancelled")
				listeners.remove_at(index)
	for index in range(pending.size()-1,-1,-1):
		if keys[pending[index].key].is_empty():
			keys.erase(pending[index].key);pending.remove_at(index)
	if not active.is_empty() and keys[active.key].is_empty():_finish("cancelled",true)

func clear_session() -> void:
	for owner in prefetch_turns.keys():discard_prefetch(str(owner))
	for entry: Dictionary in prefetch_running.values():_cancel_prefetch_entry(entry)
	prefetch_running.clear();part_cache.clear();part_cache_order.clear();part_cache_bytes=0
	prefetch_hits=0;part_cache_hits=0
	session_epoch+=1
	for request_id in cloud_active.keys():
		_cancel_provider_job(cloud_active[request_id])
	cloud_pending.clear();cloud_active.clear();cloud_keys.clear()
	pending.clear();keys.clear()
	if not active.is_empty():_finish("cancelled",true)

func _exit_tree() -> void:
	clear_session()

func _start_next() -> void:
	if not active.is_empty() or pending.is_empty():return
	var next := 0
	for index in range(1,pending.size()):
		if int(pending[index].priority)>int(pending[next].priority):next=index
	active=pending.pop_at(next)
	var base:="user://teacher_speech/"+str(Time.get_ticks_usec())+"_"+str(randi())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://teacher_speech"))
	active.input=base+".txt";active.output=base+".wav"
	var input:=FileAccess.open(active.input,FileAccess.WRITE)
	if input==null:_finish("input_error");return
	input.store_string(str(active.text));input.close()
	var executable:=OS.get_environment("LABVOLT_PIPER_PATH")
	var model_path:=str(active.model_disk)
	var input_path:=ProjectSettings.globalize_path(active.input)
	var output_path:=ProjectSettings.globalize_path(active.output)
	var args: PackedStringArray
	var bundled:=OS.get_executable_path().get_base_dir().path_join("piper/piper.exe")
	if executable.is_empty():
		if not FileAccess.file_exists(bundled):
			var development:=ProjectSettings.globalize_path("res://.deps/piper-standalone/piper/piper.exe")
			if FileAccess.file_exists(development):bundled=development
		if not FileAccess.file_exists(bundled) and not launch_adapter.is_valid():
			executable = "piper.exe" if OS.get_name() == "Windows" else "piper"
	if executable.is_empty():
		active.standalone=true
		var runner:=ProjectSettings.globalize_path("res://scripts/campus/academics/piper_runner.ps1")
		if not FileAccess.file_exists(runner):runner=OS.get_executable_path().get_base_dir().path_join("teacher_voices/piper_runner.ps1")
		if not FileAccess.file_exists(runner) and not launch_adapter.is_valid():_finish("engine_unavailable");return
		executable="powershell.exe"
		args=PackedStringArray(["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",runner,"-Piper",bundled,"-Model",model_path,"-InputPath",input_path,"-OutputPath",output_path,"-Speaker",str(active.speaker),"-LengthScale",str(1.0/float(active.rate)),"-SentenceSilence",str(float(active.pause)/1000.0)])
	else:
		args=PackedStringArray(["--model",model_path,"--config",model_path+".json","--input-file",input_path,"--output-file",output_path,"--speaker",str(active.speaker),"--length-scale",str(1.0/float(active.rate)),"--sentence-silence",str(float(active.pause)/1000.0),"--volume",str(active.gain)])
	if not launch_adapter.is_valid():
		executable=_resolve_executable(executable)
		if executable.is_empty():_finish("engine_unavailable");return
	var pid: int=launch_adapter.call(executable,args) if launch_adapter.is_valid() else OS.create_process(executable,args,false)
	if pid<=0:_finish("engine_unavailable");return
	active.pid=pid;active.started=Time.get_ticks_msec()

static func _resolve_executable(candidate: String) -> String:
	# An absent optional voice engine is an ordinary unavailable feature, not
	# a failed OS launch that asks Godot/.NET to format a native error stack.
	if candidate.is_empty():return ""
	if candidate.contains("/") or candidate.contains("\\"):
		var path:=ProjectSettings.globalize_path(candidate)
		return path if _executable_file(path) else ""
	var separator:=";" if OS.get_name()=="Windows" else ":"
	for directory in OS.get_environment("PATH").split(separator,false):
		var path:=str(directory).path_join(candidate)
		if _executable_file(path):return path
	return ""

static func _executable_file(path: String) -> bool:
	if not FileAccess.file_exists(path):return false
	return OS.get_name()=="Windows" or (FileAccess.get_unix_permissions(path)&73)!=0

func _process(_delta: float) -> void:
	_pump_cloud()
	if not prefetch_turns.is_empty():_pump_prefetch()
	if active.is_empty():return
	if Time.get_ticks_msec()-int(active.started)>TIMEOUT_MS:_finish("timeout",true);return
	var running: bool=running_adapter.call(int(active.pid)) if running_adapter.is_valid() else OS.is_process_running(int(active.pid))
	if running:return
	if not FileAccess.file_exists(active.output):_finish("output_error");return
	var output_file:=FileAccess.open(active.output,FileAccess.READ)
	if output_file==null or output_file.get_length()>SpeechPlayer.MAX_WAV_BYTES+100:
		_finish("output_error");return
	output_file.close()
	var stream: AudioStreamWAV=load_adapter.call(active.output) if load_adapter.is_valid() else AudioStreamWAV.load_from_file(active.output)
	if not SpeechPlayer.valid_stream(stream):_finish("output_error");return
	if active.get("standalone",false) and float(active.gain)!=1.0:
		stream.set_meta(SpeechPlayer.GAIN_META,clampf(float(active.gain),0.,2.))
	_finish("ok",false,stream)

func _finish(status: String,kill: bool=false,stream: AudioStreamWAV=null) -> void:
	if active.is_empty():return
	var job:=active;active={}
	if job.has("started"):last_synthesis_ms=Time.get_ticks_msec()-int(job.started)
	if kill and job.has("pid"):
		if kill_adapter.is_valid():kill_adapter.call(int(job.pid))
		else:OS.kill(int(job.pid))
	for path in [str(job.get("input","")),str(job.get("output",""))]:
		if not path.is_empty():DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var listeners: Array=keys.get(job.key,[])
	keys.erase(job.key)
	for listener in listeners:completed.emit(str(listener.room),int(listener.serial),str(job.key),stream,status)
	if not pending.is_empty():_start_next.call_deferred()
