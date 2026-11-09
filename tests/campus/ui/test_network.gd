extends SceneTree
var transport: Node
var server := false
var received := 0
var replication: RefCounted
var cache: RefCounted
func _initialize() -> void:
	server="server" in OS.get_cmdline_user_args()
	transport=Node.new(); transport.name="ProfileTransport"; transport.set_script(load("res://tests/campus/ui/profile_transport.gd")); root.add_child(transport)
	transport.tree=self
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(25700,2) if server else peer.create_client("127.0.0.1",25700)
	if error!=OK: push_error("ENet start failed"); quit(1); return
	get_multiplayer().multiplayer_peer=peer
	if server:
		replication=load("res://scripts/campus/social/profile_replication.gd").new()
		get_multiplayer().peer_connected.connect(send_initial)
	else: cache=load("res://scripts/campus/social/profile_cache.gd").new()
	create_timer(12).timeout.connect(func():push_error("network timeout");quit(1))
func send_initial(peer: int) -> void:
	replication.publish("stable-identity","Duplicate",{"money":{"dollars":40,"password":"SECRET"},"firmware":{"memory":"SECRET"}},{"money":true})
	for packet in replication.collect(peer,["stable-identity"]): transport.rpc_id(peer,"deliver",packet)
func deliver(packet: Dictionary) -> void:
	if JSON.stringify(packet).contains("SECRET") or JSON.stringify(packet).contains("stable-identity"): push_error("privacy leak"); quit(1); return
	if not cache.receive(packet): push_error("bad packet"); quit(1); return
	received+=1
	if received==1:
		if cache.profiles[packet.id].money.dollars!=40: quit(1); return
		transport.rpc_id(1,"ack",1)
	elif received==2:
		if cache.profiles[packet.id].has("money") or cache.profiles[packet.id].name!="Renamed": quit(1); return
		print("UI_NETWORK_CLIENT_PASS privacy revoked; stable rename; no secrets")
		transport.rpc_id(1,"ack",2)
		create_timer(.3).timeout.connect(func():quit())
func ack(stage: int, peer: int) -> void:
	if stage==1:
		replication.publish("stable-identity","Renamed",{"money":{"dollars":40}},{})
		for packet in replication.collect(peer,["stable-identity"]): transport.rpc_id(peer,"deliver",packet)
	elif stage==2:
		print("UI_NETWORK_HOST_PASS unchanged packets=",replication.collect(peer,["stable-identity"]).size())
		create_timer(.5).timeout.connect(func():quit())
