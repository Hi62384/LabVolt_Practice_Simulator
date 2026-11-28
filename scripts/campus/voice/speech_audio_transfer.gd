extends RefCounted
## Authority-only callers validate proximity/session before accepting a packet.
## Assembly is per utterance, bounded, duplicate-safe and independent of arrival order.
const CHUNK_BYTES:=12000
const MAX_BYTES:=16_000_000
const MAX_BUFFERED_BYTES:=48_000_000
const MAX_TRANSFERS:=8
const TIMEOUT_MS:=30000
var transfers: Dictionary={}
var reserved_bytes:=0

static func utterance_key(channel: String,serial: int) -> String:return channel+":"+str(serial)

static func digest(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	return hash.finish().hex_encode()

func push(channel: String,serial: int,total: int,offset: int,rate: int,stereo: bool,chunk: PackedByteArray,metadata: Dictionary={}) -> Dictionary:
	prune()
	var frame_bytes:=4 if stereo else 2
	if channel.is_empty() or channel.length()>160 or serial<1 or serial>2147483647 or total<=0 or total>MAX_BYTES or total%frame_bytes!=0:return {"ok":false,"error":"invalid envelope"}
	if rate<8000 or rate>48000 or offset<0 or offset%CHUNK_BYTES!=0 or offset>=total or chunk.size()!=mini(CHUNK_BYTES,total-offset):return {"ok":false,"error":"invalid chunk"}
	var segment_total:=int(metadata.get("segment_total",1))
	var segment_index:=int(metadata.get("segment_index",0))
	var segment_text:=str(metadata.get("segment_text",""))
	if segment_total not in [1,2] or segment_index<0 or segment_index>=segment_total or (segment_total>1 and (segment_text.is_empty() or segment_text.length()>1600)):return {"ok":false,"error":"invalid segment"}
	var key:=utterance_key(channel,serial)
	if segment_total>1:key+=":part:"+str(segment_index)
	var expected_hash:=str(metadata.get("sha256",""))
	if not expected_hash.is_empty() and (expected_hash.length()!=64 or not expected_hash.is_valid_hex_number()):return {"ok":false,"error":"invalid digest"}
	if not transfers.has(key):
		if transfers.size()>=MAX_TRANSFERS or reserved_bytes+total>MAX_BUFFERED_BYTES:return {"ok":false,"error":"transfer capacity"}
		transfers[key]={"channel":channel,"serial":serial,"total":total,"rate":rate,"stereo":stereo,"chunks":{},"count":0,"started":Time.get_ticks_msec(),"updated":Time.get_ticks_msec(),"hash":expected_hash,"metadata":metadata.duplicate(true)}
		reserved_bytes+=total
	var transfer: Dictionary=transfers[key]
	if int(transfer.total)!=total or int(transfer.rate)!=rate or bool(transfer.stereo)!=stereo or str(transfer.hash)!=expected_hash or int(transfer.metadata.get("segment_total",1))!=segment_total or str(transfer.metadata.get("segment_text",""))!=segment_text:return {"ok":false,"error":"envelope changed"}
	if transfer.chunks.has(offset):
		return {"ok":transfer.chunks[offset]==chunk,"duplicate":true}
	transfer.chunks[offset]=chunk
	transfer.count=int(transfer.count)+chunk.size();transfer.updated=Time.get_ticks_msec()
	if int(transfer.count)<total:return {"ok":true,"complete":false}
	var data:=PackedByteArray()
	for at in range(0,total,CHUNK_BYTES):
		if not transfer.chunks.has(at):return {"ok":true,"complete":false}
		data.append_array(transfer.chunks[at])
	_drop(key)
	if not expected_hash.is_empty() and digest(data)!=expected_hash:return {"ok":false,"error":"digest mismatch"}
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=rate;stream.stereo=stereo;stream.data=data
	var projection:=str(metadata.get("projection","normal"))
	if projection not in ["whisper","quiet","normal","lecture","shout"]:projection="normal"
	stream.set_meta("voice_projection",projection)
	stream.set_meta("voice_normalized",bool(metadata.get("normalized",false)))
	return {"ok":true,"complete":true,"stream":stream,"serial":serial,"channel":channel,"segment_index":segment_index,"segment_total":segment_total,"segment_text":segment_text}

func cancel(channel: String,serial: int=0) -> void:
	for key in transfers.keys():
		if str(transfers[key].channel)==channel and (serial==0 or int(transfers[key].serial)==serial):_drop(key)

func clear() -> void:transfers.clear();reserved_bytes=0

func prune() -> void:
	var now:=Time.get_ticks_msec()
	for key in transfers.keys():
		var transfer: Dictionary=transfers[key]
		if now-int(transfer.updated)>TIMEOUT_MS or now-int(transfer.started)>TIMEOUT_MS*3:_drop(key)

func _drop(key: String) -> void:
	if not transfers.has(key):return
	reserved_bytes-=int(transfers[key].total);transfers.erase(key)
