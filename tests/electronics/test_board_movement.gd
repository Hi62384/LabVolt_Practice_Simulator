extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.player.position=Vector3(0,0,7.5)
 var board=load("res://scripts/breadboard_model.gd").empty();board.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}]
 game.dc_lab.accept(1,1,{"op":"board","design":board})
 var station=game.dc_lab.benches[1];station.wires=[["CH1+","B1"]]
 game.dc_lab.accept(1,1,{"op":"carry_board"});assert(not station.board_held)
 station.wires=[];game.dc_lab.accept(1,1,{"op":"carry_board"});assert(station.board_held)
 game.player.position=Vector3(6,0,5.5);game.dc_lab.accept(1,1,{"op":"rotate_board"});assert(is_equal_approx(station.board_rotation,PI/2))
 game.dc_lab.accept(1,1,{"op":"place_board","position":Vector3(6.5,.895,6)});assert(not station.board_held);assert(station.board.parts[0].id=="r")
 await process_frame
 assert(game.dc_lab.physical_boards[1].position==Vector3(6.5,.895,6))
 game.dc_lab.accept(1,1,{"op":"carry_board"});assert(station.board_held)
 game.dc_lab.accept(1,1,{"op":"place_board","position":Vector3(100,.895,6)});assert(station.board_held)
 print("PASS: wired boards cannot move; carry, rotate, distant table placement preserve design; invalid placement rejected")
 quit()
