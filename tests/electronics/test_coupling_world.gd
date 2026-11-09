extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var lab=game.dc_lab
 game.player.position=Vector3(-6,0,8)
 lab.accept(1,0,{"op":"begin_external","port":"CH1+"})
 assert(lab.pending_endpoints.has(1))
 game.player.position=Vector3(0,0,8)
 lab.accept(1,1,{"op":"link_external","port":"R1a"})
 assert(lab.external_links.size()==1 and lab.benches[0].linked and lab.benches[1].linked)
 game.player.position=Vector3(-6,0,8);lab.accept(1,0,{"op":"begin_external","port":"CH1-"})
 game.player.position=Vector3(0,0,8);lab.accept(1,1,{"op":"link_external","port":"R1b"})
 lab.benches[0].master=true;lab.benches[0].channels[0].enabled=true
 for i in 4:await process_frame
 assert(abs(lab.benches[1].result.i.r0-.005)<.00001)
 lab.broadcast();assert(lab.states[0].external_links.size()==2)
 lab.accept(1,1,{"op":"unlink_external","port":"R1b"});assert(lab.external_links.size()==1)
 lab.accept(1,1,{"op":"unlink_external","port":"R1a"});assert(lab.external_links.is_empty() and not lab.benches[0].linked)
 game.player.position=Vector3(0,0,-8);lab.accept(1,0,{"op":"begin_external","port":"CH1+"});assert(not lab.pending_endpoints.has(1))
 print("PASS: physical cross-bench selection protocol, proximity checks, shared current, snapshot links, disconnection")
 quit()
