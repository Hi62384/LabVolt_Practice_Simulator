extends SceneTree
class RequestRecorder extends RefCounted:
 var requests: Array=[]
 func request_world(index: int,action: Dictionary) -> void:requests.append({"index":index,"action":action.duplicate(true)})
class TradeBridge extends RefCounted:
 var authority=RequestRecorder.new()
class Lab extends RefCounted:
 var campus_offset:=Vector3(0,0,13.2)
 var states: Array=[{"board_position":Vector3.ZERO,"board_held":false},{"board_position":Vector3.ZERO,"board_held":false},{"board_position":Vector3.ZERO,"board_held":false}]
class FixtureGame extends Node3D:
 var front: Dictionary={"in_game":true}
 var player:=Node3D.new()
 var dc_lab=Lab.new()
 var electronics_trade=TradeBridge.new()
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game:=FixtureGame.new();root.add_child(game);game.add_child(game.player)
 var ui=preload("res://scripts/electronics_ui.gd").new();root.add_child(ui);ui.game=game;ui.status=Label.new();root.add_child(ui.status)
 ui.profile.open("pcb_deploy_offset_"+str(Time.get_ticks_usec()))
 var bp: Dictionary=preload("res://tests/remaining/pcb/pcb_tests.gd").fixture()
 var doc=preload("res://scripts/pcb_design/document.gd").new();doc.open(bp)
 var message: String=doc.save_copy(ui.profile);check(message.begins_with("Blueprint saved: "),"valid routed PCB fixture saves through actual profile")
 var id:=message.trim_prefix("Blueprint saved: ")
 check(ui.profile.obtain_ic(id,true).contains("added"),"fixture crafted from actual owned resistors")
 var board: Dictionary=preload("res://scripts/breadboard_model.gd").standalone(id,ui.profile.data.blueprints)
 ui.profile.data.kits.offset={"name":"Offset fixture","items":{id:1},"board":board};ui.profile.data.equipped="offset"
 check(ui.profile.kit_error("offset")=="","fixture uses a valid owned standalone PCB")
 var stock_before: Dictionary=ui.profile.data.inventory.duplicate(true)
 ui.bench=1;game.player.position=Vector3(0,0,20.7)
 ui.deploy()
 var requests: Array=game.electronics_trade.authority.requests
 if OS.get_cmdline_user_args().has("--expect-original-block"):
  check(requests.is_empty() and ui.status.text.begins_with("Walk to"),"original current-main UI reproduces wrong distant-bench rejection")
  check(game.player.position.distance_to(Vector3(0,0,8)+game.dc_lab.campus_offset)<4,"same player is inside actual authoritative bench reach")
  ui.status.queue_free();ui.queue_free();game.queue_free();await process_frame
  print("PCB_DEPLOY_OFFSET_ORIGINAL checks=",checks," failures=",failures," expected_block_reproduced=true")
  quit(0 if failures==0 else 1);return
 check(requests.size()==1,"first deployment at relocated M103 bench reaches authority request")
 check(requests[0].index==1 and requests[0].action.op=="board","bench index and authority API unchanged")
 check(ui.status.text.begins_with("Deployment requested"),"nearby player receives normal deployment feedback")
 check(requests[0].action.design==board,"request preserves entire routed board payload")
 check(ui.profile.data.inventory==stock_before,"reach fix cannot mint or debit inventory")
 # Original laboratory coordinate must no longer bypass the relocated reach check.
 game.player.position=Vector3(0,0,8);ui.deploy()
 check(requests.size()==1 and ui.status.text.begins_with("Walk to"),"legacy lab position is rejected when campus offset is active")
 game.player.position=Vector3(0,0,15);ui.deploy()
 check(requests.size()==1,"far campus player stays blocked")
 game.player.position=Vector3(0,0,17.21);ui.deploy()
 check(requests.size()==2,"inside four-metre relocated reach remains accepted")
 game.player.position=Vector3(0,0,17.19);ui.deploy()
 check(requests.size()==2,"outside four-metre relocated reach remains rejected")
 # Zero-offset legacy configuration retains original behavior.
 game.dc_lab.campus_offset=Vector3.ZERO;game.player.position=Vector3(0,0,7.5);ui.deploy()
 check(requests.size()==3,"zero-offset legacy bench remains compatible")
 # Explicit placement already uses world coordinates; never double-apply offset.
 game.dc_lab.campus_offset=Vector3(0,0,13.2);game.dc_lab.states[1].board_position=Vector3(2,.91,23)
 game.player.position=Vector3(2,0,22);ui.deploy()
 check(requests.size()==4,"explicit placed-board world position is unchanged")
 game.dc_lab.states[1].board_position=Vector3.ZERO
 # Automatic bench selection is preserved.
 ui.bench=-1;game.player.position=Vector3(6,0,20.7);ui.deploy()
 check(requests.size()==5 and requests[-1].index==2,"automatic right bench selection retains relocated origin")
 ui.bench=-1;game.player.position=Vector3(-6,0,20.7);ui.deploy()
 check(requests.size()==6 and requests[-1].index==0,"automatic left bench selection retains relocated origin")
 # Existing earlier guards and held-board behavior remain in force.
 ui.bench=1;game.front.in_game=false;game.player.position=Vector3(0,0,20.7);ui.deploy()
 check(requests.size()==6 and ui.status.text.begins_with("Start a laboratory"),"main-menu deployment gate preserved")
 game.front.in_game=true;ui.profile.data.inventory[id]=0;ui.deploy()
 check(requests.size()==6,"missing ownership still rejected before authority request")
 ui.profile.data.inventory[id]=1;ui.profile.data.kits.offset.board.rows=11;ui.deploy()
 check(requests.size()==6,"invalid circuit design remains rejected")
 ui.profile.data.kits.offset.board.rows=40
 game.dc_lab.states[1].board_held=true;game.player.position=Vector3(0,0,-18);ui.deploy()
 check(requests.size()==7,"existing held-board request path preserved for authoritative validation")
 check(ui.profile.data.inventory==stock_before,"all reach cases leave existing stock unchanged")
 ui.status.queue_free();ui.queue_free();game.queue_free();await process_frame
 print("PCB_DEPLOY_OFFSET checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
