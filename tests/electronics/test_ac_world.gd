extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var dc=game.dc_lab;var ac=game.session.labs[0]
 for pair in [["R1a","PV_A"],["R1b","PV_N"]]:
  game.player.position=Vector3(-6,0,8);dc.accept(1,0,{"op":"begin_external","port":pair[0]})
  game.player.position=ac.positions[pair[1]]-Vector3(0,1,0)
  dc.accept(1,3,{"op":"link_external","port":pair[1]})
 assert(dc.external_links.size()==2)
 ac.powered=true;ac.level=.1;ac.recalculate()
 for i in 100:load("res://scripts/dc_coupling.gd").step(dc.benches+dc.ac_bridges,dc.external_links,.0005)
 assert(ac.readings.external_supply_rms.PV_A>.011)
 dc.broadcast();assert(dc.states[0].external_links.size()==2)
 dc.accept(1,3,{"op":"unlink_external","port":"PV_N"});assert(dc.external_links.size()==1)
 print("PASS: physical AC supply connection protocol, loaded current, snapshot and removal")
 quit()
