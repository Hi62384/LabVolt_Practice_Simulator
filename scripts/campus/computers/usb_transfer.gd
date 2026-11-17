extends RefCounted
## Ordered, bounded staging for client-owned USB archive transfers. The caller
## must authenticate the peer and commit the completed archive before changing
## inventory ownership. No partial payload is ever returned as a completed one.
const CHUNK_SIZE := 64 * 1024
const MAX_SIZE := 158 * 1024 * 1024
const TIMEOUT_MS := 60 * 1000
var expected_size := 0
var expected_hash := ""
var received := 0
var last_activity_ms := 0
var buffer := PackedByteArray()
var started := false

func begin(size: int, digest: String, now_ms: int) -> bool:
	if started or size <= 0 or size > MAX_SIZE or digest.length() != 64 or not digest.is_valid_hex_number():return false
	expected_size=size
	expected_hash=digest.to_lower()
	received=0
	last_activity_ms=now_ms
	buffer.clear()
	started=true
	return true

func append(offset: int, chunk: PackedByteArray, now_ms: int) -> bool:
	if not started or now_ms < last_activity_ms or now_ms-last_activity_ms > TIMEOUT_MS:return false
	if offset != received or chunk.is_empty() or chunk.size() > CHUNK_SIZE or received+chunk.size() > expected_size:return false
	buffer.append_array(chunk)
	received+=chunk.size()
	last_activity_ms=now_ms
	return true

func finish(now_ms: int) -> Dictionary:
	if not started or now_ms < last_activity_ms or now_ms-last_activity_ms > TIMEOUT_MS:return {"error":"Transfer expired"}
	if received != expected_size:return {"error":"Transfer incomplete"}
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256)!=OK or hash.update(buffer)!=OK:return {"error":"Cannot verify transfer"}
	if hash.finish().hex_encode()!=expected_hash:return {"error":"Transfer checksum mismatch"}
	var complete := buffer
	buffer=PackedByteArray()
	started=false
	return {"bytes":complete}

func cancel() -> void:
	buffer.clear()
	started=false
	received=0
