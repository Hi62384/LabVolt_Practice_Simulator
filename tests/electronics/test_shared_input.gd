extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for f in 4:await process_frame
 game.session.roster[44]={"name":"Guest","ready":false};game.session.roster[45]={"name":"Other","ready":false}
 game.session.poses[44]={"position":Vector3(0,0,8)};game.session.poses[45]={"position":Vector3(0,0,8)}
 var board=load("res://scripts/breadboard_model.gd").empty();board.parts=[{"id":"button","type":"button","a":"A1","b":"F1"}]
 var station=game.dc_lab.benches[1];assert(station.apply({"op":"board","design":board})=="");station.board_owner=1
 game.dc_lab.accept(44,1,{"op":"input","id":"board/button","hold":true,"pressed":true})
 assert(station.board.controls["board/button"].pressed)
 game.dc_lab.accept(45,1,{"op":"input","id":"board/button","hold":true,"pressed":false})
 assert(station.board.controls["board/button"].pressed)
 game.session.poses[44].position=Vector3(100,0,0)
 game.dc_lab.accept(44,1,{"op":"input","id":"board/button","hold":true,"pressed":false})
 assert(not station.board.controls["board/button"].pressed)
 game.session.poses[44].position=Vector3(0,0,8);game.dc_lab.rate_limits.clear()
 game.dc_lab.accept(44,1,{"op":"input","id":"board/button","hold":true,"pressed":true})
 assert(station.board.controls["board/button"].pressed)
 game.session.roster.erase(44);game.session.roster_changed.emit()
 assert(not station.board.controls["board/button"].pressed)
 assert(station.board_owner==1)
 print("PASS: guest operates placed board, another player cannot release held button, immediate out-of-range release, disconnect releases without removing owner's circuit")
 quit()

