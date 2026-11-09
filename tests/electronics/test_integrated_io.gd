extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var lab=game.dc_lab;var station=lab.benches[0]
 var design=load("res://scripts/breadboard_model.gd").empty()
 design.parts=[{"id":"pad","type":"io_keypad","a":"A1","b":"F1","pins":["A1","F1","A2","F2","A3","F3","A4"]}]
 assert(station.apply({"op":"board","design":design})=="");station.board_owner=1
 game.session.roster[2]={"name":"Other"};game.session.poses[2]={"position":Vector3(-6,0,8)}
 var epoch=station.board_epoch
 lab._accept_checked(2,0,{"op":"input","id":"board/pad","board_epoch":epoch,"command":{"op":"key","key":0,"pressed":true,"revision":0}})
 assert(station.board.io_controls["board/pad"].keys==1)
 station.step(.0005);assert(station.result.ok)
 var expanded=load("res://scripts/breadboard_model.gd").expand(station.board).parts
 assert(expanded.any(func(p):return p.id=="board/pad/key0" and p.value==.01))
 lab._accept_checked(2,0,{"op":"input","id":"board/pad","board_epoch":epoch,"command":{"op":"key","key":0,"pressed":false,"revision":0}})
 assert(station.board.io_controls["board/pad"].keys==0)
 lab.rate_limits.erase(2)
 lab._accept_checked(2,0,{"op":"input","id":"board/pad","board_epoch":epoch,"command":{"op":"key","key":1,"pressed":true,"revision":2}})
 assert(station.board.io_controls["board/pad"].keys==2)
 game.session.roster.erase(2);lab.cleanup_io_holds();assert(station.board.io_controls["board/pad"].keys==0)
 assert(station.apply({"op":"board","design":design})=="")
 lab._accept_checked(1,0,{"op":"input","id":"board/pad","board_epoch":epoch,"command":{"op":"key","key":0,"pressed":true,"revision":0}})
 assert(station.board.get("io_controls",{}).is_empty())
 # Same actor, same device, same board: a retired view may not release a new view.
 var current_epoch=station.board_epoch
 game.player.position=Vector3(-6,0,8)
 lab._accept_checked(1,0,{"op":"input","id":"board/pad","board_epoch":current_epoch,"view_token":"new-view","command":{"op":"key","key":2,"pressed":true,"revision":0}})
 assert(station.board.io_controls["board/pad"].keys==4)
 lab._accept_checked(1,0,{"op":"input","id":"board/pad","board_epoch":current_epoch,"view_token":"retired-view","command":{"op":"release","revision":1}})
 assert(station.board.io_controls["board/pad"].keys==4)
 lab._accept_checked(1,0,{"op":"input","id":"board/pad","board_epoch":current_epoch,"view_token":"new-view","command":{"op":"release","revision":0}})
 assert(station.board.io_controls["board/pad"].keys==0)
 # Exercise the actual UI wiring and ACK routes, not just the guard helper.
 var ui=game.electronics;ui.bench=0;ui.designing=false
 lab.states[0]=station.snapshot()
 var old=load("res://scripts/breadboard_canvas.gd").new();root.add_child(old);ui.wire_io_canvas(old)
 var fresh=load("res://scripts/breadboard_canvas.gd").new();root.add_child(fresh);ui.wire_io_canvas(fresh)
 ui.canvas=fresh;ui.retired_io_canvases.append({"canvas":old,"bench":0,"kit":ui.profile.data.equipped})
 old.board=design.duplicate(true);fresh.board=design.duplicate(true)
 old.refresh_io_surfaces();fresh.refresh_io_surfaces()
 var old_surface=old.io_adapter.views["board/pad"]
 var new_surface=fresh.io_adapter.views["board/pad"]
 old_surface.awaiting_revision=7;new_surface.awaiting_revision=7
 assert(old.get_meta("io_view_token")!=fresh.get_meta("io_view_token"))
 ui.acknowledge_io_input(0,"board/pad",{"revision":8,"keys":0},current_epoch,str(old.get_meta("io_view_token")))
 assert(old_surface.awaiting_revision==-1 and new_surface.awaiting_revision==7)
 ui.acknowledge_io_input(0,"board/pad",{"revision":8,"keys":0},current_epoch,str(fresh.get_meta("io_view_token")))
 assert(new_surface.awaiting_revision==-1)
 print("PASS: integrated IO reducer changes real contact, rapid stale release accepted, disconnect clears keys, replaced-board command rejected; retired-view release rejected and actual UI ACK only unblocks its originating surface")
 quit()
