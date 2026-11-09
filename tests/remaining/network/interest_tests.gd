extends SceneTree
const Service=preload("res://scripts/campus/performance/dc_interest_service.gd")
const Context=preload("res://scripts/campus/performance/bench_interest_context.gd")
const Registry=preload("res://scripts/campus/world/room_registry.gd")
const Station=preload("res://scripts/dc_station.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)

func deliver(host: RefCounted, client: RefCounted, peer: int, view: Dictionary) -> Dictionary:
	var packet: Dictionary=host.prepare(peer,view.peers[peer],view.objects)
	if packet.is_empty():return {"unchanged":true}
	check(packet.get("ok",false),"host packet prepared")
	if not packet.get("ok",false):return {}
	var result: Dictionary=client.accept_encoded(packet.packet,packet.raw_size)
	check(result.ok,"reliable encoded projection accepted")
	check(host.commit(peer,packet.token),"enqueue success commits matching token")
	return packet

func run() -> void:
	var states: Array=[]
	for i in 3:
		var station:=Station.new();station.step(0.0005)
		var snapshot: Dictionary=station.snapshot();snapshot.board_epoch=i+1
		snapshot.firmware={"nested/device":{"memory":PackedByteArray([1,2,3,255]),"board_epoch":i+1}}
		states.append(snapshot)
	var dc: Array=[];var ac: Array=[]
	for i in 3:
		dc.append({"CH0+":Vector3((i-1)*6,1,19),"CH0-":Vector3((i-1)*6,1,19),"X1":Vector3(100,100,100)})
		ac.append({"P_A":Vector3((i-1)*6,1,0)})
	var poses: Dictionary={2:{"position":Vector3(-9,0,18)},3:{"position":Vector3(0,0,33),"zone_id":"dc_lab","dependencies":[0]},4:{"position":Vector3(9,0,18)}}
	var roster: Dictionary={2:{},3:{},4:{}}
	var context:=Context.new();var registry:=Registry.new()
	var view: Dictionary=context.build(roster,poses,registry,states,dc,ac,[])
	check(view.wanted_station_indices[2]==[0],"near left bench, other benches excluded by distance")
	check(view.wanted_station_indices[4]==[2],"same room right bench independent")
	check(view.wanted_station_indices[3].is_empty(),"gym excluded; forged zone/dependency fields ignored")
	check(view.objects["dc/0"].meta.position==Vector3(-6,1,19),"moving breadboard X ports excluded from fixed bench anchor")
	var authoritative_before:=var_to_bytes(states)
	var host:=Service.new();var left:=Service.new();var gym:=Service.new()
	var initial:=deliver(host,left,2,view)
	check(left.active(0) and not left.active(1) and not left.active(2),"receiver gets only its interested bench")
	check(var_to_bytes(left.state(0))==var_to_bytes(states[0]),"actual solver snapshot/nested memory/epoch round-trips exactly")
	deliver(host,gym,3,view)
	check(not gym.active(0) and not gym.active(1) and not gym.active(2),"initial out-of-zone reset has no bench objects")
	check(deliver(host,left,2,view).get("unchanged",false),"unchanged state sends zero packets")
	check(deliver(host,gym,3,view).get("unchanged",false),"unchanged remote zone sends zero packets")
	var first_raw: Dictionary=bytes_to_var(initial.packet.decompress(initial.raw_size,FileAccess.COMPRESSION_ZSTD))
	check(not left.accept_packet(first_raw).ok,"duplicate stream packet ignored")
	poses[2].position=Vector3(0,0,33)
	view=context.build(roster,poses,registry,states,dc,ac,[])
	deliver(host,left,2,view)
	check(not left.active(0) and left.state(0).is_empty(),"leave-interest evicts protocol object cache")
	states[0].revision+=1;states[0].board_epoch=40
	states[0].firmware["nested/device"].memory=PackedByteArray([9,8,7])
	poses[2].position=Vector3(-9,0,18)
	view=context.build(roster,poses,registry,states,dc,ac,[])
	deliver(host,left,2,view)
	check(var_to_bytes(left.state(0))==var_to_bytes(states[0]),"full reentry has latest state after remote changes")
	states[0]["optional_field"]={"x":1}
	view=context.build(roster,poses,registry,states,dc,ac,[]);deliver(host,left,2,view)
	states[0].erase("optional_field")
	view=context.build(roster,poses,registry,states,dc,ac,[]);deliver(host,left,2,view)
	check(not left.state(0).has("optional_field"),"explicit field tombstone removes stale key")
	states[0].revision+=1;view=context.build(roster,poses,registry,states,dc,ac,[])
	var failed: Dictionary=host.prepare(2,view.peers[2],view.objects)
	check(not host.commit(2,failed.token+1),"stale/wrong preparation token cannot commit")
	host.failed_send(2)
	var retry:=deliver(host,left,2,view)
	check(retry.reset and left.state(0).revision==states[0].revision,"failed send retries full stream, no lost baseline")
	check(not left.accept_packet(first_raw).ok,"retired reset cannot roll receiver back")
	var stable:=var_to_bytes(left._received)
	var corrupt: Dictionary=bytes_to_var(retry.packet.decompress(retry.raw_size,FileAccess.COMPRESSION_ZSTD))
	corrupt.stream_id="malformed-new";corrupt.sequence=1;corrupt.updates["dc/0"].result=42
	check(not left.accept_packet(corrupt).ok and var_to_bytes(left._received)==stable,"malformed state rejected atomically")
	check(not left.accept_encoded(PackedByteArray([1]),2000001).ok,"oversized compression claim rejected")
	states[0].revision+=1;view=context.build(roster,poses,registry,states,dc,ac,[])
	var gap: Dictionary=host.prepare(2,view.peers[2],view.objects)
	var raw_gap: Dictionary=bytes_to_var(gap.packet.decompress(gap.raw_size,FileAccess.COMPRESSION_ZSTD));raw_gap.sequence+=1
	check(left.accept_packet(raw_gap).need_full and var_to_bytes(left._received)==stable,"sequence gap requests full recovery without partial application")
	host.failed_send(2);deliver(host,left,2,view)
	host.forget_peer(2);left.clear_receiver();deliver(host,left,2,view)
	check(left.active(0),"disconnect/reconnect gets fresh full stream")
	host.reset_session();deliver(host,left,2,view)
	check(left.active(0) and left.state(0).board_epoch==40,"session reset is distinct from preserved board epoch")
	poses[2].position=Vector3(0,0,33);states[0].board_owner=2
	view=context.build(roster,poses,registry,states,dc,ac,[])
	check(0 in view.wanted_station_indices[2],"board owner retains remote circuit interest")
	states[0].board_owner=0
	var school: Dictionary={"identities":{2:"student-a",3:"student-b"},"allocation":{"student-a":{"bench":1,"group":1},"student-b":{"bench":1,"group":1}},"activity":{"kind":"lab","course_id":"ETY155"}}
	view=context.build(roster,poses,registry,states,dc,ac,[],school)
	check(1 in view.wanted_station_indices[2] and 1 in view.wanted_station_indices[3],"host-assigned shared bench persists for group members across rooms")
	poses[2].position=Vector3(-6,0,0)
	var links: Array=[{"a":{"station":0,"port":"CH0+"},"b":{"station":3,"port":"P_A"}},{"a":{"station":3,"port":"P_A"},"b":{"station":2,"port":"CH0-"}}]
	view=context.build(roster,poses,registry,states,dc,ac,links)
	check(0 in view.wanted_station_indices[2] and 2 in view.wanted_station_indices[2],"transitive DC-AC-DC electrical dependencies retained")
	view=context.build(roster,poses,registry,states,dc,ac,[],{}, {3:[2]})
	check(2 in view.wanted_station_indices[3],"host held-input/pending endpoint dependency retained")
	check(var_to_bytes(states[1])==var_to_bytes(bytes_to_var(authoritative_before)[1]),"interest handling leaves authoritative solver state unchanged")
	print("INTEREST C: %d checks, %d failures"%[checks,failures])
	print("METRICS "+JSON.stringify(host.metrics()))
	quit(1 if failures else 0)
