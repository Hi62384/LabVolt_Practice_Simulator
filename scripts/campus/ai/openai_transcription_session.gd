extends RefCounted
## One explicit, bounded client-committed transcription turn. This transport
## never generates a conversational response. The host owns the actual dialogue.
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Processor=preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs")
const MAX_CHARS:=8000
const CHUNK_BYTES:=9600
const MAX_PACKET_BYTES:=262144
const TIMEOUT_MS:=120000
const CONNECT_TIMEOUT_MS:=15000
var socket: WebSocketPeer
var state:="new"
var result: Dictionary={}
var partial:=""
var model:=""
var request_id:=""
var sent_bytes:=0
var started_at:=0
var first_delta_ms:=-1
var _configured:=false
var _commit_sent:=false
var _item_id:=""
var _pending: Dictionary={}
var _seen: Dictionary={}
var _pcm:=PackedByteArray()
var _conversion
var _phase_started:=0
var conversion_ms:=-1
var connected_ms:=-1
var committed_ms:=-1

static func configuration(choice: String) -> Dictionary:
	return {"type":"transcription","audio":{"input":{"format":{"type":"audio/pcm","rate":24000},"transcription":{"model":choice},"turn_detection":null}}}

static func resample_16k_to_24k(pcm: PackedByteArray) -> PackedByteArray:
	return Processor.new().Resample16kTo24k(pcm)

func begin(choice: String,key: String,pcm: PackedByteArray,endpoint: String="",id: String="") -> Dictionary:
	if state!="new" or Models.verified_family(choice) not in Models.STREAMING_STT or not Models.available_for(choice,"stt"):return _error("Choose a supported streaming transcription model.")
	if pcm.size()<4800 or pcm.size()>5760000 or pcm.size()%2:return _error("Invalid PCM16 recording.")
	if key.is_empty():return _error("The host's OpenAI connection is unavailable.")
	var url:="wss://api.openai.com/v1/realtime?intent=transcription"
	if not endpoint.is_empty():
		if not OS.has_feature("editor") or RegEx.create_from_string("^ws://127\\.0\\.0\\.1:[0-9]{2,5}/v1$").search(endpoint)==null:return _error("Invalid loopback test endpoint.")
		url=endpoint+"/realtime?intent=transcription"
	started_at=Time.get_ticks_msec();_phase_started=started_at
	_conversion=Processor.new()
	_conversion.BeginResample16kTo24k(pcm)
	model=choice
	request_id=id if not id.is_empty() else Crypto.new().generate_random_bytes(12).hex_encode()
	socket=WebSocketPeer.new()
	socket.inbound_buffer_size=MAX_PACKET_BYTES*2
	socket.outbound_buffer_size=1024*1024
	socket.max_queued_packets=256
	socket.handshake_headers=PackedStringArray(["Authorization: Bearer "+key])
	if socket.connect_to_url(url)!=OK:
		socket=null
		return _error("Could not connect to streaming transcription.",true)
	state="connecting"
	return {"ok":true}

func poll() -> void:
	if state in ["closed","new"] or socket==null:return
	socket.poll()
	var now:=Time.get_ticks_msec()
	if _conversion!=null and _conversion.IsResampleReady():
		_pcm=_conversion.TakeResampledPcm();_conversion=null;conversion_ms=now-started_at
		if _pcm.is_empty():_finish(_error("Microphone sample-rate conversion failed."));return
	if socket.get_ready_state()==WebSocketPeer.STATE_OPEN and state=="connecting":
		socket.handshake_headers=PackedStringArray()
		connected_ms=now-started_at;state="configuring";_phase_started=now
		if not _send({"type":"session.update","session":configuration(model)}):_finish(_error("Could not configure streaming transcription.",true));return
	var count:=0
	while state!="closed" and socket!=null and socket.get_available_packet_count()>0 and count<64:
		count+=1
		var packet:=socket.get_packet()
		if packet.size()>MAX_PACKET_BYTES:_finish(_error("The transcription event was too large."));return
		var event: Variant=JSON.parse_string(packet.get_string_from_utf8())
		if not event is Dictionary:_finish(_error("The transcription service returned an unreadable event."));return
		receive_event(event)
	if state=="closed":return
	if socket.get_ready_state()==WebSocketPeer.STATE_CLOSED:_finish(_error("The transcription connection ended before a final transcript.",true));return
	if state in ["connecting","configuring"] and now-_phase_started>CONNECT_TIMEOUT_MS:
		_finish(_error("The transcription service could not connect." if state=="connecting" else "The transcription service did not acknowledge its audio configuration.",true));return
	if state not in ["connecting","configuring"] and now-_phase_started>TIMEOUT_MS:_finish(_error("The transcription upload timed out." if state=="sending" else "Speech recognition timed out after the audio was submitted.",true));return
	if state!="sending" or _conversion!=null:return
	# Bound the outgoing queue and yield between frames. A slow network never
	# consumes the rest of the microphone buffer or grows an unbounded backlog.
	for _batch in 8:
		if sent_bytes>=_pcm.size():
			if _send({"type":"input_audio_buffer.commit"}):
				_commit_sent=true;state="committed";_phase_started=now;committed_ms=now-started_at;_pcm.clear()
			return
		if socket.get_current_outbound_buffered_amount()>256*1024:return
		var chunk:=_pcm.slice(sent_bytes,mini(_pcm.size(),sent_bytes+CHUNK_BYTES))
		if not _send({"type":"input_audio_buffer.append","audio":Marshalls.raw_to_base64(chunk)}):return
		sent_bytes+=chunk.size()

func receive_event(event: Dictionary) -> void:
	if state=="closed":return
	var eid:=str(event.get("event_id",""))
	if not eid.is_empty():
		if _seen.has(eid):return
		_seen[eid]=true
		if _seen.size()>4096:_seen.erase(_seen.keys()[0])
	var kind:=str(event.get("type",""))
	match kind:
		"error":
			_finish(_provider_error(event));return
		"session.updated":
			if state=="configuring" and not _configured:
				_configured=true;state="sending";_phase_started=Time.get_ticks_msec()
		"input_audio_buffer.committed":
			if not _commit_sent:return
			var item:=str(event.get("item_id",""))
			if item.is_empty() or item.length()>200:return
			if not _item_id.is_empty() and _item_id!=item:return
			_item_id=item
			if _pending.has(item):
				var pending: Dictionary=_pending[item]
				partial=str(pending.get("delta",""))
				if not partial.is_empty() and first_delta_ms<0:first_delta_ms=Time.get_ticks_msec()-started_at
				if pending.has("failure"):_finish(_provider_error(pending.failure))
				elif pending.has("final"):_accept_final(pending.final)
			_pending.clear()
		"conversation.item.input_audio_transcription.delta","conversation.item.input_audio_transcription.completed","conversation.item.input_audio_transcription.failed":
			if not _commit_sent and state!="sending":return
			var item:=str(event.get("item_id",""))
			if item.is_empty() or item.length()>200 or (not _item_id.is_empty() and item!=_item_id):return
			if kind.ends_with(".failed"):
				if item==_item_id:_finish(_provider_error(event))
				elif _pending.has(item) or _pending.size()<8:_pending.get_or_add(item,{}).failure=event
				return
			var is_final:=kind.ends_with(".completed")
			var value:=str(event.get("transcript","") if is_final else event.get("delta",""))
			if value.length()>MAX_CHARS:_finish(_error("The transcript exceeded the conversation limit."));return
			if item==_item_id:
				if is_final:_accept_final(event)
				else:
					partial+=value
					if partial.length()>MAX_CHARS:_finish(_error("The transcript exceeded the conversation limit."))
					elif first_delta_ms<0:first_delta_ms=Time.get_ticks_msec()-started_at
			else:
				# Deltas may precede the commit acknowledgement. Keep only bounded
				# provisional items, and publish the one confirmed by the server.
				if not _pending.has(item) and _pending.size()>=8:return
				var entry: Dictionary=_pending.get_or_add(item,{})
				if is_final:entry.final=event
				else:
					var combined:=str(entry.get("delta",""))+value
					if combined.length()>MAX_CHARS:_finish(_error("The transcript exceeded the conversation limit."))
					else:entry.delta=combined

func _accept_final(event: Dictionary) -> void:
	var words:=str(event.get("transcript","")).strip_edges()
	if words.is_empty():_finish(_error("No speech was recognized."));return
	if words.length()>MAX_CHARS:_finish(_error("The transcript exceeded the conversation limit."));return
	var metadata: Dictionary={"usage":event.get("usage",{}),"model":model}
	_finish({"ok":true,"text":words,"provider":"openai_streaming_transcription","first_delta_ms":first_delta_ms,"_api_metadata":metadata})

func cancel() -> void:
	if state!="closed":_finish({"ok":false,"canceled":true,"retryable":false,"error":"Speech recognition canceled."})

func _finish(value: Dictionary) -> void:
	if state=="closed":return
	state="closed";result=value
	result.request_id=request_id
	result.timings={"conversion_ms":conversion_ms,"connected_ms":connected_ms,"committed_ms":committed_ms,"first_delta_ms":first_delta_ms,"total_ms":maxi(0,Time.get_ticks_msec()-started_at)}
	_pcm.clear();_pending.clear();_seen.clear();_conversion=null
	if socket!=null:
		socket.close(1000)
		socket=null

func _send(value: Dictionary) -> bool:
	return socket!=null and socket.get_ready_state()==WebSocketPeer.STATE_OPEN and socket.send_text(JSON.stringify(value))==OK

static func _error(message: String,retryable:=false) -> Dictionary:
	return {"ok":false,"error":message,"retryable":retryable,"retry_after_ms":1000 if retryable else 0}

static func _provider_error(event: Dictionary) -> Dictionary:
	var detail: Variant=event.get("error",{})
	var code:=str(detail.get("code","")) if detail is Dictionary else ""
	var message:="The transcription service could not recognize this recording."
	match code:
		"invalid_api_key","authentication_error":message="Speech recognition authentication failed. Reconnect the host's API account."
		"insufficient_quota","billing_hard_limit_reached":message="The host's speech recognition account has no available API quota."
		"rate_limit_exceeded":message="Speech recognition is temporarily rate limited. Please wait before trying again."
		"model_not_found","model_not_available":message="The selected speech recognition model is not available to the host's account."
		"server_error","service_unavailable":message="The speech recognition service is temporarily unavailable."
		"invalid_value","invalid_request_error":message="The speech recognition service rejected the selected audio configuration."
	var response:=_error(message,code in ["rate_limit_exceeded","server_error","service_unavailable"])
	# Include a bounded machine code, never raw provider text or private audio.
	response.code=code.left(80) if RegEx.create_from_string("^[a-z0-9_]{1,80}$").search(code)!=null else "transcription_failed"
	return response
