extends SceneTree
## Two independent MultiplayerAPI roots and real loopback ENet, one lightweight process.
const Controller=preload("res://scripts/campus/facilities/facility_controller.gd")
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var server_api: MultiplayerAPI
var client_api: MultiplayerAPI
var host: Node
var client: Node
var ledger:={"dollars":100,"facilities":Rules.empty_profile()}
var response:={}
var event_count:=0
var events: Array=[]
var checks:=0
var failed:=0
var client_id:=0
var ticks:=1000

func check(v: bool,label: String) -> void:
	checks+=1
	if not v:failed+=1;printerr("FAIL "+label)

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var host_root:=Node.new();host_root.name="Host";root.add_child(host_root)
	var client_root:=Node.new();client_root.name="Client";root.add_child(client_root)
	server_api=MultiplayerAPI.create_default_interface();client_api=MultiplayerAPI.create_default_interface()
	set_multiplayer(server_api,host_root.get_path());set_multiplayer(client_api,client_root.get_path())
	var sp:=ENetMultiplayerPeer.new();var cp:=ENetMultiplayerPeer.new()
	check(sp.create_server(25650,2)==OK,"ENet server starts assigned port")
	server_api.multiplayer_peer=sp
	check(cp.create_client("127.0.0.1",25650)==OK,"ENet client starts")
	client_api.multiplayer_peer=cp
	host=Controller.new();host.name="Facilities";host_root.add_child(host)
	host.host.clock=func():return ticks
	client=Controller.new();client.name="Facilities";client_root.add_child(client)
	host.host.context=func(peer):
		if peer!=client_id or client_id==0:return {}
		return {"identity":"bound-client","room_id":"test-room","position":Vector3.ZERO,"allowed":true,"grounded":true}
	host.host.load_profile=func(_id):return ledger.facilities.duplicate(true)
	host.host.commit_profile=func(_id,delta,p):
		if ledger.dollars+delta<0:return false
		ledger.dollars+=delta;ledger.facilities=p.duplicate(true);return true
	host.host.anchors={"counter":{"room_id":"test-room","kind":"counter:tim_hortons","position":Vector3.ZERO}}
	host.host.anchors["rack"]={"room_id":"test-room","kind":"curl","position":Vector3.ZERO}
	host.interested_peers=func(_room):return [client_id] if client_id else []
	client.owner_result.connect(func(value):response=value)
	client.room_event.connect(func(_peer,value):event_count+=1;events.append(value))
	for i in 180:
		if cp.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:break
		await process_frame
	client_id=client_api.get_unique_id()
	check(cp.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED,"loopback connected")
	client.request({"op":"buy","item":"coffee","station":"counter","sequence":1,"peer":1})
	await wait_response()
	check(response.get("ok",false),"authenticated reliable RPC purchase")
	check(ledger.dollars==97 and ledger.facilities.orders.get("1",{}).get("item","")=="coffee","host dollar and food mutation")
	check(event_count==1 and events[0].get("held",{}).get("item","")=="coffee","room-interest high-level event received")
	response={};ticks+=100
	client.request({"op":"buy","item":"coffee","station":"counter","sequence":1})
	await wait_response()
	check(not response.get("ok",true) and ledger.dollars==97,"reliable replay cannot debit twice")
	check(not str(events).contains("dollars") and not str(events).contains("bound-client"),"public events exclude private balance/identity")
	# Same RPC exists on the client, but engine authority annotations reject client-authored public data.
	check(host.host.trusted(1).is_empty(),"claimed peer field did not impersonate host")
	for sip in 3:
		await send_action({"op":"consume"},800)
		check(response.get("ok",false),"network consume")
	await send_action({"op":"finish","xp":99999})
	check(not response.get("ok",true) and ledger.facilities.xp==0,"network forged exercise result denied")
	await send_action({"op":"start","station":"rack"})
	check(response.get("ok",false) and host.host.movement_locked(client_id),"network exercise starts and locks movement")
	for beat in 2:
		await send_action({"op":"beat"},700)
		check(response.get("ok",false),"network timed repetition phase")
	await send_action({"op":"finish"})
	check(response.get("ok",false) and ledger.facilities.xp==5,"network authoritative XP")
	await send_action({"op":"finish"})
	check(not response.get("ok",true) and ledger.facilities.xp==5,"network duplicate reward denied")
	cp.close();sp.close()
	host_root.queue_free();client_root.queue_free()
	await process_frame;await process_frame
	print("NETWORK checks=",checks," failures=",failed," public_events=",event_count)
	quit(1 if failed else 0)

func wait_response() -> void:
	for i in 180:
		if not response.is_empty():return
		await process_frame
	check(false,"bounded RPC response deadline")

func send_action(value: Dictionary, advance: int=100) -> void:
	ticks+=advance;response={}
	var request:=value.duplicate(true);request.sequence=int(ledger.facilities.last_sequence)+1
	client.request(request)
	await wait_response()
