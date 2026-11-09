extends RefCounted
## Host-produced public bench snapshots only. Reliable ordered channel3. This is
## traffic projection, never an authorization, electrical solver or grading path.
const Router = preload("res://scripts/campus/performance/snapshot_router.gd")
const MAX_OBJECTS := 33
const MAX_BYTES := 2000000
var router := Router.new()
var _peers := {}
var _pending := {}
var _epoch := Crypto.new().generate_random_bytes(16).hex_encode()
var _serial := 0
var _stream := ""
var _sequence := 0
var _received := {}
var _retired: Array[String] = []
var _started_usec := Time.get_ticks_usec()
var _metrics := {"queued_packets":0,"queued_payload_bytes":0,"queued_raw_bytes":0,"received_packets":0,"received_payload_bytes":0,"unchanged_ticks":0,"failed_enqueues":0,"rejected_packets":0,"oversize_projections":0}

func prepare(peer: int, context: Dictionary, objects: Dictionary) -> Dictionary:
	if peer<=0 or (not _peers.has(peer) and _peers.size()>=16):
		return {"ok":false,"error":"Invalid/excess peer context"}
	var state: Dictionary = _peers.get(peer,{"stream":"","sequence":0,"reset":true})
	var reset: bool = state.reset or int(state.sequence)>=1073741824
	var stream: String = state.stream
	if reset:
		_serial += 1
		stream = _epoch+":"+str(_serial)
	var prepared: Dictionary = router.prepare_patch(peer,context,objects,reset)
	var patch: Dictionary = prepared.patch
	if not reset and patch.updates.is_empty() and patch.removed_fields.is_empty() and patch.entered_interest.is_empty() and patch.left_interest.is_empty():
		router.cancel_patch(peer)
		_pending.erase(peer)
		_metrics.unchanged_ticks += 1
		return {}
	var packet := {"schema":1,"stream_id":stream,"sequence":1 if reset else int(state.sequence)+1,"reset":reset}
	packet.merge(patch)
	var raw := var_to_bytes(packet)
	if raw.size()>MAX_BYTES:
		_metrics.oversize_projections += 1
		router.cancel_patch(peer)
		_pending.erase(peer)
		return {"ok":false,"error":"Bench projection exceeds existing2MB packet budget"}
	var encoded := raw.compress(FileAccess.COMPRESSION_ZSTD)
	_pending[peer] = {"token":prepared.token,"stream":stream,"sequence":packet.sequence,"raw_bytes":raw.size(),"payload_bytes":encoded.size()}
	return {"ok":true,"token":prepared.token,"packet":encoded,"raw_size":raw.size(),"object_updates":patch.updates.keys(),"reset":reset}

func commit(peer: int, token: int) -> bool:
	if not _pending.has(peer) or int(_pending[peer].token)!=token:
		return false
	var pending: Dictionary = _pending[peer]
	if not router.commit_patch(peer,token):
		return false
	_peers[peer] = {"stream":pending.stream,"sequence":pending.sequence,"reset":false}
	_metrics.queued_packets += 1
	_metrics.queued_raw_bytes += int(pending.raw_bytes)
	_metrics.queued_payload_bytes += int(pending.payload_bytes)
	_pending.erase(peer)
	return true

func failed_send(peer: int) -> void:
	router.cancel_patch(peer)
	_pending.erase(peer)
	request_full(peer)
	_metrics.failed_enqueues += 1

func request_full(peer: int) -> void:
	if _peers.has(peer):
		_peers[peer].reset = true

func forget_peer(peer: int) -> void:
	_peers.erase(peer)
	_pending.erase(peer)
	router.forget_peer(peer)

func reset_session() -> void:
	_peers.clear();_pending.clear();router.clear()
	_epoch = Crypto.new().generate_random_bytes(16).hex_encode()
	clear_receiver()

func clear_receiver() -> void:
	_received.clear();_retired.clear();_stream="";_sequence=0

func accept_encoded(encoded: PackedByteArray, raw_size: int) -> Dictionary:
	if raw_size<1 or raw_size>MAX_BYTES or encoded.size()>MAX_BYTES:
		return _reject("Invalid compressed size",true)
	var raw := encoded.decompress(raw_size,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=raw_size:
		return _reject("Decompression size mismatch",true)
	var packet: Variant = bytes_to_var(raw) # Objects are disabled; never bytes_to_var_with_objects.
	if not packet is Dictionary:
		return _reject("Invalid packet",true)
	var result := accept_packet(packet)
	if result.ok:
		_metrics.received_packets += 1
		_metrics.received_payload_bytes += encoded.size()
	return result

func accept_packet(packet: Dictionary) -> Dictionary:
	if not _valid_shape(packet):
		return _reject("Invalid interest schema",true)
	var stream: String = packet.stream_id
	var sequence: int = packet.sequence
	var reset: bool = packet.reset
	if stream in _retired or (stream==_stream and sequence<=_sequence):
		return _reject("Duplicate/retired stream",false)
	if stream!=_stream and (not reset or sequence!=1):
		return _reject("Full stream reset required",true)
	if stream==_stream and (reset or sequence!=_sequence+1):
		return _reject("Sequence gap",true)
	var next: Dictionary = {} if reset else _received.duplicate(true)
	for id in packet.left_interest:
		next.erase(id)
	for id in packet.updates:
		if not reset and id not in packet.entered_interest and not next.has(id):
			return _reject("Unknown delta object",true)
		if reset or id in packet.entered_interest:
			next[id] = packet.updates[id].duplicate(true)
		else:
			next[id].merge(packet.updates[id].duplicate(true),true)
	for id in packet.removed_fields:
		if not next.has(id):
			return _reject("Unknown removal object",true)
		for field in packet.removed_fields[id]:
			next[id].erase(field)
	if stream!=_stream and not _stream.is_empty():
		_retired.append(_stream)
		if _retired.size()>32:_retired.pop_front()
	_received=next;_stream=stream;_sequence=sequence
	return {"ok":true,"need_full":false,"reset":reset,"active_objects":_received.keys(),"left_interest":packet.left_interest.duplicate()}

func _valid_shape(packet: Dictionary) -> bool:
	for field in ["schema","stream_id","sequence","reset","updates","removed_fields","entered_interest","left_interest"]:
		if not packet.has(field):return false
	if typeof(packet.schema)!=TYPE_INT or packet.schema!=1 or not packet.stream_id is String or packet.stream_id.is_empty() or packet.stream_id.length()>80 or typeof(packet.sequence)!=TYPE_INT or packet.sequence<1 or not packet.reset is bool:return false
	if not packet.updates is Dictionary or not packet.removed_fields is Dictionary or not packet.entered_interest is Array or not packet.left_interest is Array:return false
	if packet.updates.size()>MAX_OBJECTS or packet.removed_fields.size()>MAX_OBJECTS or packet.entered_interest.size()>MAX_OBJECTS or packet.left_interest.size()>MAX_OBJECTS:return false
	for id in packet.updates:
		if not _valid_id(id) or not packet.updates[id] is Dictionary or id in packet.left_interest:return false
		var fields: Dictionary=packet.updates[id]
		if fields.size()>256:return false
		for name in fields:
			if not name is String or name.length()>128:return false
		if id=="links":
			if fields.has("external_links") and (not fields.external_links is Array or fields.external_links.size()>24):return false
		else:
			for name in ["board","result","firmware","scope","current_source","generator"]:
				if fields.has(name) and not fields[name] is Dictionary:return false
			for name in ["wires","channels","samples","current_sources","resistance"]:
				if fields.has(name) and not fields[name] is Array:return false
			for name in ["board_epoch","revision"]:
				if fields.has(name) and (typeof(fields[name])!=TYPE_INT or fields[name]<0):return false
	for id in packet.entered_interest:
		if not _valid_id(id) or not packet.updates.has(id):return false
	for id in packet.left_interest:
		if not _valid_id(id):return false
	for id in packet.removed_fields:
		if not _valid_id(id) or not packet.removed_fields[id] is Array or id in packet.left_interest:return false
		for field in packet.removed_fields[id]:
			if not field is String or field.length()>128 or packet.updates.get(id,{}).has(field):return false
	return true

func _valid_id(id: Variant) -> bool:
	if not id is String:return false
	if id=="links":return true
	var slot: String=id.trim_prefix("dc/")
	return id.begins_with("dc/") and slot.is_valid_int() and int(slot) in range(MAX_OBJECTS-1) and slot==str(int(slot))

func _reject(reason: String, full: bool) -> Dictionary:
	_metrics.rejected_packets += 1
	return {"ok":false,"need_full":full,"error":reason}

func active(index: int) -> bool:
	return _received.has("dc/"+str(index))

func state(index: int) -> Dictionary:
	return _received.get("dc/"+str(index),{}).duplicate(true)

func links() -> Array:
	return _received.get("links",{}).get("external_links",[]).duplicate(true)

func metrics() -> Dictionary:
	var output := _metrics.duplicate()
	output.elapsed_seconds = maxf(0.001,(Time.get_ticks_usec()-_started_usec)/1000000.0)
	output.queued_packets_per_second = float(output.queued_packets)/output.elapsed_seconds
	output.queued_payload_bytes_per_second = float(output.queued_payload_bytes)/output.elapsed_seconds
	output.byte_scope = "encoded application payload successfully enqueued, excludes RPC/ENet/IP overhead"
	return output
