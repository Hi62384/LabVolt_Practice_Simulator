extends RefCounted
## Incremental, bounded Responses/Chat SSE transport. Partial text is telemetry,
## never committed character dialogue. A terminal provider response is required.
var http := HTTPClient.new()
var done := false
var result: Dictionary = {}
var timing: Dictionary = {}
var delta_callback: Callable
var _started := 0
var _deadline := 0
var _sent := false
var _headers_read := false
var _status := 0
var _sse := false
var _path := ""
var _headers := PackedStringArray()
var _request_body := ""
var _bytes := PackedByteArray()
var _body := PackedByteArray()
var _received := 0
var _limit := 0
var _text := ""
var _terminal: Dictionary = {}
var _last_sequence := -1
var _chat_usage: Dictionary = {}
var _chat_model := ""
var _chat_finish := ""
var _retry_after_ms := 1000

func begin(url: String, headers: PackedStringArray, payload: Dictionary, timeout: float, limit: int, progress: Callable = Callable()) -> void:
	_started = Time.get_ticks_msec()
	_deadline = _started + int(timeout * 1000.)
	_limit = limit
	delta_callback = progress
	_headers = headers
	_headers.append("Accept: text/event-stream")
	_request_body = JSON.stringify(payload)
	var match_url := RegEx.create_from_string("^(https?)://([^/:]+)(?::([0-9]+))?(/.*)$").search(url)
	if match_url == null:
		_fail("The AI endpoint is invalid.", "configuration", false)
		return
	_path = match_url.get_string(4)
	var secure := match_url.get_string(1) == "https"
	var port := int(match_url.get_string(3)) if not match_url.get_string(3).is_empty() else (443 if secure else 80)
	http.read_chunk_size = 65536
	var error := http.connect_to_host(match_url.get_string(2), port, TLSOptions.client() if secure else null)
	if error != OK:_fail("Could not initialize the AI connection.", "connection_start", true)

func poll() -> void:
	if done:return
	if _headers_read and http.get_status() in [HTTPClient.STATUS_CONNECTED,HTTPClient.STATUS_DISCONNECTED]:
		finish();return
	var now := Time.get_ticks_msec()
	if now >= _deadline:
		_fail("The AI response exceeded its generation deadline.", "generation_timeout", false)
		return
	if not _sent and now - _started >= 15000:
		_fail("The AI server connection timed out before sending the request.", "connection_timeout", true)
		return
	var error := http.poll()
	if error != OK:
		_fail("The AI connection failed while receiving the response." if _sent else "The AI server could not be reached.", "connection_lost" if _sent else "connection_failed", not _sent)
		return
	var status := http.get_status()
	if status in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
		_fail("The AI server connection failed (DNS, network or TLS).", "connection_failed", not _sent)
		return
	if status == HTTPClient.STATUS_CONNECTED and not _sent:
		timing.connection_ms = now - _started
		var request_error := http.request(HTTPClient.METHOD_POST, _path, _headers, _request_body)
		_headers.clear()
		_request_body = ""
		if request_error != OK:
			_fail("Could not send the AI request.", "request_start", true)
			return
		_sent = true
		return
	if http.has_response() and not _headers_read:
		_headers_read = true
		_status = http.get_response_code()
		timing.response_headers_ms = now - _started
		for header: String in http.get_response_headers():
			var lower := header.to_lower()
			if lower.begins_with("content-type:"):_sse = "text/event-stream" in lower
			if lower.begins_with("retry-after:"):
				var seconds := header.substr(header.find(":") + 1).strip_edges()
				if seconds.is_valid_float():_retry_after_ms = clampi(roundi(seconds.to_float() * 1000.), 250, 30000)
	if status == HTTPClient.STATUS_BODY:
		# Bound work per frame even when the socket already has a large response.
		for _chunk in 4:
			if http.get_status()!=HTTPClient.STATUS_BODY:break
			var bytes := http.read_response_body_chunk()
			if bytes.is_empty():break
			consume(bytes)
			if done:return
		if http.get_status() in [HTTPClient.STATUS_CONNECTED,HTTPClient.STATUS_DISCONNECTED]:finish()
	elif _sent and status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		finish()

func consume(bytes: PackedByteArray) -> void:
	_received += bytes.size()
	if _received > _limit:
		_fail("The AI response exceeded its bounded transport size.", "response_size", false)
		return
	if not _sse or _status < 200 or _status >= 300:
		_body.append_array(bytes)
		return
	_bytes.append_array(bytes)
	# Split byte lines, not partial UTF-8 strings; a multibyte character may span
	# arbitrary network packets. SSE data is decoded only at an event boundary.
	while not done:
		var boundary := -1
		var width := 0
		for index in maxi(0, _bytes.size() - 1):
			if _bytes[index] == 10 and _bytes[index + 1] == 10:
				boundary = index; width = 2; break
			if index + 3 < _bytes.size() and _bytes[index] == 13 and _bytes[index + 1] == 10 and _bytes[index + 2] == 13 and _bytes[index + 3] == 10:
				boundary = index; width = 4; break
		if boundary < 0:break
		var packet := _bytes.slice(0, boundary).get_string_from_utf8()
		_bytes = _bytes.slice(boundary + width)
		var data := PackedStringArray()
		for line in packet.replace("\r\n", "\n").split("\n"):
			if line.begins_with("data:"):data.append(line.substr(5).trim_prefix(" "))
		if not data.is_empty():_event("\n".join(data))

func _event(data: String) -> void:
	if data == "[DONE]":
		if _path.ends_with("/chat/completions"):
			_terminal = {"choices":[{"message":{"content":_text},"finish_reason":_chat_finish}],"usage":_chat_usage,"model":_chat_model}
			_complete(JSON.stringify(_terminal).to_utf8_buffer())
		return
	var parsed: Variant = JSON.parse_string(data)
	if not parsed is Dictionary:
		_fail("The AI stream contained an unreadable event.", "stream_protocol", false)
		return
	var event: Dictionary = parsed
	var sequence: Variant = event.get("sequence_number")
	if sequence is int or sequence is float:
		if int(sequence) <= _last_sequence:return
		_last_sequence = int(sequence)
	var kind := str(event.get("type", ""))
	if kind == "response.output_text.delta":
		_delta(str(event.get("delta", "")))
	elif kind in ["response.completed", "response.incomplete", "response.failed"]:
		if not event.get("response") is Dictionary:
			_fail("The AI stream ended without a valid response.", "stream_protocol", false)
			return
		_terminal = event.response
		_complete(JSON.stringify(_terminal).to_utf8_buffer())
	elif kind == "error":
		_fail("The AI provider reported a stream error.", "provider_stream_error", false)
	elif _path.ends_with("/chat/completions"):
		if event.get("usage") is Dictionary:_chat_usage = event.usage
		_chat_model = str(event.get("model", _chat_model))
		for choice in event.get("choices", []):
			if not choice is Dictionary or int(choice.get("index", 0)) != 0:continue
			if choice.get("delta") is Dictionary:_delta(str(choice.delta.get("content", "")))
			if choice.get("finish_reason") is String:_chat_finish = choice.finish_reason

func _delta(value: String) -> void:
	if value.is_empty():return
	if not timing.has("first_text_ms"):timing.first_text_ms = Time.get_ticks_msec() - _started
	_text += value
	if delta_callback.is_valid():delta_callback.call(value)

func finish() -> void:
	if done:return
	if not _headers_read:
		_fail("The AI connection closed before returning a response.", "connection_closed", not _sent)
	elif not _sse or _status < 200 or _status >= 300:
		_complete(_body)
	else:
		_fail("The AI stream ended before its completion event. No partial reply was delivered.", "stream_incomplete", false)

func cancel() -> void:
	if not done:_fail("The request was canceled or its conversation ended.", "canceled", false)

func _complete(body: PackedByteArray) -> void:
	timing.total_ms = Time.get_ticks_msec() - _started
	result = {"ok":true,"code":_status,"body":body,"retry_after_ms":_retry_after_ms,"timing":timing.duplicate(),"streamed":_sse}
	done = true
	http.close()

func _fail(message: String, code: String, retryable: bool) -> void:
	timing.total_ms = Time.get_ticks_msec() - _started
	result = {"ok":false,"error":message,"code":code,"retryable":retryable,"request_sent":_sent,"canceled":code == "canceled","timing":timing.duplicate(),"retry_after_ms":1000 if retryable else 0}
	done = true
	_headers.clear()
	_request_body = ""
	http.close()
