extends SceneTree
func _initialize():call_deferred("run")
func run():
 var station=load("res://scripts/dc_station.gd").new()
 station.board={"parts":[]};station.wires=[["CH1+","B1"]]
 assert(station.apply({"op":"carry_board"})=="")
 assert(station.board_held and station.wires.size()==1)
 assert(not station.apply({"op":"stow_board"}).is_empty())
 assert(station.apply({"op":"place_board","position":Vector3(1,1,1)})=="")
 assert(not station.board_held and station.wires.size()==1)
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.dc_lab.states[1].wires=[["CH1+","B1"]]
 game.dc_lab.ports[1]["CH1+"]=Vector3(0,1,0)
 game.dc_lab.ports[1]["B1"]=Vector3(2,1,0)
 var pairs: Array=game.dc_lab.board_cable_pairs(1)
 assert(pairs.size()==1 and pairs[0][0]==Vector3(2,1,0) and pairs[0][1]==Vector3(0,1,0))
 var ac_station: int=game.dc_lab.AC_OFFSET
 game.session.labs[0].positions["P_A"]=Vector3(9,1,0)
 game.dc_lab.states[0].external_links=[{"a":{"station":1,"port":"B1"},"b":{"station":ac_station,"port":"P_A"}}]
 pairs=game.dc_lab.board_cable_pairs(1)
 assert(pairs.size()==2 and pairs[1][1]==Vector3(9,1,0))
 print("PASS wired board pickup and cable endpoint tracking")
 quit()
