extends Node
const C=preload("res://scripts/io_devices/controls.gd")
const R=preload("res://scripts/io_devices/replication.gd")
var role := "host"
var control := C.defaults("io_encoder")
var state := {}
var completed := {}
var accepted := 0
var rejected := 0
var responses := 0
func _ready() -> void:
	name="IOTestPeer"
	role=OS.get_cmdline_user_args()[0]
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(25201,4) if role=="host" else peer.create_client("127.0.0.1",25201)
	if error!=OK:finish(1,"ENet setup failure");return
	multiplayer.multiplayer_peer=peer
	multiplayer.peer_connected.connect(connected)
	get_tree().create_timer(20.).timeout.connect(func():finish(1,"network timeout"))
	if role=="host":
		state={"board/module/encoder":{"control":control},"board/module/screen":{"powered":true,"cells":[165,90]}}
		print("IO HOST READY")
func connected(id: int) -> void:
	if role=="host":snapshot.rpc_id(id,R.delta({},state))
@rpc("authority","call_remote","reliable")
func snapshot(packet: Dictionary) -> void:
	var received := R.apply_delta({},packet)
	if received.get("board/module/screen",{}).get("cells",[])!=[165,90]:finish(1,"screen differs");return
	if role=="client":
		if received["board/module/encoder"].control.detent!=0:finish(1,"unexpected initial controls");return
		request.rpc_id(1,{"op":"turn","steps":1,"revision":0})
		request.rpc_id(1,{"op":"turn","steps":1,"revision":0})
	else:
		if received["board/module/encoder"].control.detent!=1:finish(1,"late join lost input state");return
		ack.rpc_id(1)
		get_tree().create_timer(.2).timeout.connect(func():finish(0,"late join framebuffer and input state match"))
@rpc("any_peer","call_remote","reliable")
func request(command: Dictionary) -> void:
	if not multiplayer.is_server():return
	var result := C.apply("io_encoder",control,command)
	if result.ok:control=result.state;state["board/module/encoder"].control=control;accepted+=1
	else:rejected+=1
	response.rpc_id(multiplayer.get_remote_sender_id(),result.ok)
@rpc("authority","call_remote","reliable")
func response(ok: bool) -> void:
	responses+=1
	if (responses==1 and not ok) or (responses==2 and ok):finish(1,"authority conflict result wrong");return
	if responses==2:
		ack.rpc_id(1)
		get_tree().create_timer(.2).timeout.connect(func():finish(0,"host accepted one revision and rejected stale concurrent request"))
@rpc("any_peer","call_remote","reliable")
func ack() -> void:
	if not multiplayer.is_server():return
	completed[multiplayer.get_remote_sender_id()]=true
	if completed.size()==2:
		get_tree().create_timer(.5).timeout.connect(func():finish(0 if accepted==1 and rejected==1 else 1,"two clients including late join; host controls authoritative"))
func finish(code: int,message: String) -> void:
	print("IO NETWORK ",role," ","PASS " if code==0 else "FAIL ",message)
	get_tree().quit(code)
