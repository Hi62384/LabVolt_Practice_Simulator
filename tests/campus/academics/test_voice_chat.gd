extends SceneTree
const Voice=preload("res://scripts/campus/voice/voice_chat.gd")
class FakeSession extends Node:
 signal roster_changed
 signal leaving
 var roster:={}
 var poses:={}
 var online:=true
 func peer_connected_now(_peer: int)->bool:return true
class FakePlayer extends Node3D:
 var enabled:=true
 var chat_typing:=false
 func down(_key: String)->bool:return false
class FakeFront extends Node:
 var in_game:=true
 var screen:=Control.new()
class FakeGame extends Node3D:
 var session: FakeSession
 var player: FakePlayer
 var front: FakeFront
 var avatars:={}
func _initialize():call_deferred("run")
func run():
 var host:=FakeGame.new();host.name="Host";root.add_child(host)
 var client:=FakeGame.new();client.name="Client";root.add_child(client)
 var server_api=MultiplayerAPI.create_default_interface();var client_api=MultiplayerAPI.create_default_interface()
 set_multiplayer(server_api,host.get_path());set_multiplayer(client_api,client.get_path())
 var sp:=ENetMultiplayerPeer.new();var cp:=ENetMultiplayerPeer.new()
 assert(sp.create_server(25784,2)==OK);server_api.multiplayer_peer=sp
 assert(cp.create_client("127.0.0.1",25784)==OK);client_api.multiplayer_peer=cp
 for i in 180:
  if cp.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:break
  await process_frame
 assert(cp.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED)
 var id:=client_api.get_unique_id()
 for i in 180:
  if id in server_api.get_peers():break
  await process_frame
 assert(id in server_api.get_peers())
 for g in [host,client]:
  g.session=FakeSession.new();g.add_child(g.session)
  g.player=FakePlayer.new();g.add_child(g.player)
  g.front=FakeFront.new();g.add_child(g.front);g.front.add_child(g.front.screen);g.front.screen.hide()
  g.session.roster={1:{"name":"Host"},id:{"name":"Client"}}
  g.session.poses={1:{"position":Vector3.ZERO},id:{"position":Vector3(1,0,0)}}
 var a=Voice.new();a.name="VoiceChat";host.add_child(a);a.build(host)
 var b=Voice.new();b.name="VoiceChat";client.add_child(b);b.build(client)
 var packet:=PackedByteArray();packet.resize(int(Voice.SAMPLE_RATE*Voice.PACKET_SECONDS)*2)
 a._relay(1,packet)
 for i in 90:
  if b.remotes.has(1):break
  await process_frame
 assert(b.remotes.has(1))
 assert(b.remotes[1].player.max_distance==24.0)
 var stamp: int=b.remotes[1].last
 host.session.poses[id].position=Vector3(100,0,0)
 a.last_packet.clear();a._relay(1,packet)
 for i in 10:await process_frame
 assert(b.remotes[1].last==stamp)
 print("PASS voice ENet relay, proximity cutoff and PCM playback")
 client.queue_free();host.queue_free();await process_frame
 cp.close();sp.close();quit()
