extends MultiplayerPeerExtension

const MAX_PACKET := 1024 * 1024
const TIMEOUT_MS := 10000
const MAX_QUEUED_BYTES := 4 * MAX_PACKET

var room_code := ""
var metered_messages := 0
var metered_connections := 1
var failure := ""
var _socket := WebSocketPeer.new()
var _status := CONNECTION_DISCONNECTED
var _id := 0
var _hosting := false
var _deadline := 0
var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false
var _packets: Array[PackedByteArray] = []
var _peers: Dictionary = {}

func open(endpoint: String, code: String = "", host_key: String = "") -> Error:
	_hosting = code.is_empty()
	_socket.inbound_buffer_size = MAX_QUEUED_BYTES
	_socket.outbound_buffer_size = MAX_QUEUED_BYTES
	if _hosting and not host_key.is_empty():
		_socket.handshake_headers = PackedStringArray(["Authorization: Bearer " + host_key])
	var path := "/v1/host" if _hosting else "/v1/join/" + code
	var error := _socket.connect_to_url(endpoint.trim_suffix("/") + path)
	if error == OK:
		_status = CONNECTION_CONNECTING
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	return error

func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	_socket.poll()
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			if _socket.was_string_packet():
				_control(JSON.parse_string(packet.get_string_from_utf8()))
			elif _status == CONNECTION_CONNECTED and packet.size() > 4:
				if _hosting: metered_messages += 1
				if _peers.has(packet.decode_s32(0)):
					_packets.append(packet)
			if _status == CONNECTION_DISCONNECTED:
				return
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED or (
		_status == CONNECTION_CONNECTING and Time.get_ticks_msec() >= _deadline
	):
		if failure.is_empty():
			failure = "Could not reach the relay." if _status == CONNECTION_CONNECTING else "Relay disconnected."
		_close()

func _control(value: Variant) -> void:
	if not value is Dictionary:
		return
	var id := int(value.get("id", 0))
	match str(value.get("type", "")):
		"error":
			failure = str(value.get("message", "Relay rejected the connection."))
			_close()
		"ready":
			if _status != CONNECTION_CONNECTING or id < 1 or (id == 1) != _hosting:
				return
			_id = id
			room_code = str(value.get("code", ""))
			_status = CONNECTION_CONNECTED
			if not _hosting:
				_peers[1] = true
				peer_connected.emit(1)
		"joined":
			metered_connections += 1
			if _hosting and _status == CONNECTION_CONNECTED and id > 1:
				if _refuse:
					_disconnect_peer(id, true)
					return
				_peers[id] = true
				peer_connected.emit(id)
		"left":
			if _peers.erase(id):
				peer_disconnected.emit(id)

func _put_packet_script(packet: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if packet.size() > MAX_PACKET:
		return ERR_INVALID_DATA
	var buffered := _socket.get_current_outbound_buffered_amount()
	if _mode != TRANSFER_MODE_RELIABLE and buffered > 65536:
		return OK
	if buffered + packet.size() > MAX_QUEUED_BYTES:
		_close()
		return ERR_OUT_OF_MEMORY
	var frame := PackedByteArray()
	frame.resize(4)
	frame.encode_s32(0, _target)
	frame.append_array(packet)
	var error := _socket.put_packet(frame)
	if _hosting and error == OK: metered_messages += 1
	return error

func _get_packet_script() -> PackedByteArray:
	return (_packets.pop_front() as PackedByteArray).slice(4)

func _get_available_packet_count() -> int:
	return _packets.size()

func _get_packet_peer() -> int:
	return _packets[0].decode_s32(0) if not _packets.is_empty() else 0

func _get_packet_mode() -> TransferMode:
	return TRANSFER_MODE_RELIABLE

func _get_packet_channel() -> int:
	return 0

func _get_max_packet_size() -> int:
	return MAX_PACKET

func _get_connection_status() -> ConnectionStatus:
	return _status

func _get_unique_id() -> int:
	return _id

func _is_server() -> bool:
	return _hosting

func _is_server_relay_supported() -> bool:
	return false

func _set_target_peer(id: int) -> void:
	_target = id

func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode

func _get_transfer_mode() -> TransferMode:
	return _mode

func _set_transfer_channel(channel: int) -> void:
	_channel = channel

func _get_transfer_channel() -> int:
	return _channel

func _set_refuse_new_connections(refuse: bool) -> void:
	_refuse = refuse

func _is_refusing_new_connections() -> bool:
	return _refuse

func _disconnect_peer(id: int, force: bool) -> void:
	if _hosting and id > 1:
		_socket.send_text("kick %d" % id)
		if force:
			_peers.erase(id)
	elif id == 1:
		_close()

func _close() -> void:
	_socket.close()
	_socket.poll()
	_packets.clear()
	_peers.clear()
	_status = CONNECTION_DISCONNECTED
