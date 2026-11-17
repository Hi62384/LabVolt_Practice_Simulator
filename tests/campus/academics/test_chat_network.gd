extends SceneTree
const Session=preload("res://scripts/session.gd")
func _initialize():call_deferred("run")
func run():
 var h:=Node.new();h.name="Host";root.add_child(h)
 var c:=Node.new();c.name="Client";root.add_child(c)
 var ha=MultiplayerAPI.create_default_interface();var ca=MultiplayerAPI.create_default_interface()
 set_multiplayer(ha,h.get_path());set_multiplayer(ca,c.get_path())
 var hp:=ENetMultiplayerPeer.new();var cp:=ENetMultiplayerPeer.new()
 assert(hp.create_server(25785,2)==OK);ha.multiplayer_peer=hp
 assert(cp.create_client("127.0.0.1",25785)==OK);ca.multiplayer_peer=cp
 for i in 180:
  if cp.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED and ca.get_unique_id() in ha.get_peers():break
  await process_frame
 var id:=ca.get_unique_id();assert(id in ha.get_peers())
 var host=Session.new();host.name="Session";h.add_child(host)
 var client=Session.new();client.name="Session";c.add_child(client)
 host.online=true;client.online=true
 host.roster={1:{"name":"Host"},id:{"name":"Student"}};client.roster=host.roster.duplicate(true)
 var got:={"host":"","client":"","sender":"","count":0}
 host.chat_received.connect(func(_id,_name,msg):got.host=msg)
 client.chat_received.connect(func(_id,name,msg):got.client=msg;got.sender=name;got.count+=1)
 client.chat("Hello from the client")
 for i in 180:
  if not got.client.is_empty():break
  await process_frame
 assert(got.host=="Hello from the client" and got.client==got.host)
 host.last_chat[id]=-1000
 host.accept_chat(id," ")
 assert(got.host=="Hello from the client" and int(host.last_chat[id])==-1000)
 host.accept_chat(id,"X".repeat(1001))
 assert(got.host=="Hello from the client" and int(host.last_chat[id])==-1000)
 host.last_chat[id]=-1000
 host.accept_chat(id,"A".repeat(150)+"\r\t")
 assert(got.host.length()==100 and got.host=="A".repeat(100))
 for i in 180:
  if got.client==got.host:break
  await process_frame
 assert(got.client==got.host)
 var before_count: int=got.count
 client._player_chat(id,"Impostor","From the host")
 assert(got.sender=="Student" and got.count==before_count+1)
 client.roster.erase(id)
 before_count=got.count
 client._player_chat(id,"Impostor","Stale peer")
 assert(got.count==before_count)
 host.roster.erase(id)
 host.last_chat.erase(id)
 host.accept_chat(id,"Stale request")
 assert(got.host=="A".repeat(100))
 print("PASS host-relayed multiplayer text chat")
 cp.close();hp.close();await process_frame
 h.queue_free();c.queue_free();await process_frame
 quit()
