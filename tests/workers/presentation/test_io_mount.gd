extends SceneTree
class Lab extends Node:
 var actions := []
 func request(index: int,action: Dictionary):actions.append({"index":index,"action":action.duplicate(true)})
class Owner extends "res://scripts/equipment_builder.gd":
 var dc_lab: Node

var failed := false
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
 if not ok:push_error(message);failed=true
func run():
 if not ResourceLoader.exists("res://scripts/io_devices/physical_surface.gd"):
  push_error("Run this test in the hash-verified combined IO fixture");quit(1);return
 var B=load("res://scripts/breadboard_model.gd");var C=load("res://scripts/io_devices/controls.gd")
 var D=load("res://scripts/io_devices/devices.gd");var catalog=load("res://scripts/io_devices/catalog.gd").all()
 var owner=Owner.new();root.add_child(owner);owner.dc_lab=Lab.new();owner.add_child(owner.dc_lab);owner.camera=Camera3D.new();owner.add_child(owner.camera)
 var physical=load("res://scripts/physical_breadboard.gd").new();owner.add_child(physical);physical.build(owner,1)
 var board=B.empty();board.parts=[{"id":"key","type":"io_keypad","a":"A3","b":"F6","pins":["A3","A4","A5","A6","F3","F4","F5"]},{"id":"enc","type":"io_encoder","a":"A12","b":"F12","pins":["A12","A13","F12"]},{"id":"rgb","type":"io_rgb","a":"A22","b":"F23","pins":["A22","A23","F22","F23"]}]
 board.io_controls={"board/key":C.defaults("io_keypad"),"board/enc":C.defaults("io_encoder")}
 var expanded=D.expand(catalog.io_rgb,"board/rgb",["r","g","b","k"],{})
 var live=D.tick(expanded[0],{"ok":true,"i":{"board/rgb/led0":.02,"board/rgb/led1":.01}}, {},.0005)
 var state={"board":board,"result":{"i":{}},"firmware":{"board/rgb":live},"board_owner":1}
 physical.update_state(state);await process_frame
 check(physical.io_views.size()==3,"Every eligible IO device must mount exactly one adapter")
 var key=physical.io_views["board/key"];var enc=physical.io_views["board/enc"]
 check(key.collider.get_meta("role")=="dc_io" and key.collider.get_meta("part_id")=="board/key","Collider must carry stable ID and routing role")
 check(key.collider.get_meta("dc_station")==1 and key.collider.collision_layer==4,"Collider must retain station identity and interaction layer")
 check(physical.io_views["board/rgb"].collider==null,"Output must not create a clickable input zone")
 check(physical.io_views["board/rgb"].view.surface.live.levels==live.levels,"Renderer must receive actual solved-current host output")
 var original_view=key.view
 physical.update_state(state);check(physical.io_views["board/key"].view==original_view,"Unchanged layouts must retain pending gesture/adapter identity")
 physical.io_pointer("board/key",key.view.to_global(Vector3(-.03,0,.03)),true)
 await process_frame;await process_frame
 check(owner.dc_lab.actions.size()==1,"Physical press must forward exactly one existing host input request")
 if owner.dc_lab.actions.size()!=1:quit(1);return
 var press=owner.dc_lab.actions[-1].action
 check(press.op=="input" and press.id=="board/key" and press.command.key==0 and press.command.pressed,"Ray UV must select the correct keypad key")
 physical.io_drag("board/key",Vector2(150,150));await process_frame
 physical.release_io_capture("board/key")
 check(owner.dc_lab.actions.size()==1 and key.view.surface.pending.size()==1,"Release must wait behind a press acknowledgment")
 var accepted=C.apply("io_keypad",board.io_controls["board/key"],press.command);board.io_controls["board/key"]=accepted.state
 physical.acknowledge_io("board/key",accepted.state)
 check(owner.dc_lab.actions.size()==2,"Ack must pump the queued release")
 var release=owner.dc_lab.actions[-1].action.command
 check(release.key==0 and not release.pressed and release.revision==1,"Release must retain original key and use acknowledged revision")
 accepted=C.apply("io_keypad",accepted.state,release);board.io_controls["board/key"]=accepted.state;physical.acknowledge_io("board/key",accepted.state)
 # Rejection acknowledgment with an unchanged revision must also unblock queued controls.
 physical.io_turn("board/enc",1);physical.io_turn("board/enc",1)
 var before=owner.dc_lab.actions.size();physical.acknowledge_io("board/enc",board.io_controls["board/enc"])
 check(owner.dc_lab.actions.size()==before+1,"Rejected unchanged-revision response must unblock the next command")
 physical.acknowledge_io("board/enc",board.io_controls["board/enc"])
 # Captured mouse motion drives the encoder without camera motion.
 physical.io_pointer("board/enc",enc.view.to_global(Vector3.ZERO),true);await process_frame;await process_frame
 physical.io_drag("board/enc",Vector2(0,-20));await process_frame;await process_frame
 check(owner.dc_lab.actions[-1].action.command.get("steps",0)==2,"Encoder drag must convert relative pixels to detents")
 physical.acknowledge_io("board/enc",board.io_controls["board/enc"]);physical.release_io_capture("board/enc")
 # Stow while press is in flight. Hidden view retires but release survives.
 physical.io_pointer("board/key",key.view.to_global(Vector3(-.03,0,.03)),true);await process_frame;await process_frame
 press=owner.dc_lab.actions[-1].action.command
 var stowed=state.duplicate(true);stowed.board_stowed=true;physical.update_state(stowed)
 check(not physical.io_views.has("board/key") and physical.io_retiring.has("board/key"),"Stow must remove active view while retaining unacknowledged release")
 check(not key.view.visible and key.collider.collision_layer==0,"Stowed input must have no visible surface or collision")
 accepted=C.apply("io_keypad",board.io_controls["board/key"],press);board.io_controls["board/key"]=accepted.state
 before=owner.dc_lab.actions.size();physical.acknowledge_io("board/key",accepted.state)
 check(owner.dc_lab.actions.size()==before+1 and not owner.dc_lab.actions[-1].action.command.pressed,"Retired view must forward its release after host acknowledgment")
 accepted=C.apply("io_keypad",accepted.state,owner.dc_lab.actions[-1].action.command);physical.acknowledge_io("board/key",accepted.state)
 await process_frame;check(not physical.io_retiring.has("board/key"),"Completed retired gesture must release its viewport")
 # Nested hidden-IC eligibility and PCB re-exposure retain globally qualified IDs.
 var source=B.empty();source.parts=[board.parts[0].duplicate(true)]
 var bp={"name":"IO assembly","package":"IC","footprint":{"width":8,"height":8,"color":"24775b"},"layout":{"rows":30,"parts":source.parts,"wires":[]},"parts":[],"pins":[{"name":"A","node":"L3"},{"name":"B","node":"R3"}],"exposed":[]}
 var nested=B.empty();nested.definitions={"ic:io":bp};nested.parts=[{"id":"outer","type":"ic:io","a":"A3","b":"F6","pins":["A3","F6"]}]
 var nested_state={"board":nested,"result":{"i":{}},"firmware":{}}
 physical.update_state(nested_state);check(physical.io_views.is_empty(),"Hidden IC must not expose IO surfaces or click zones")
 nested.definitions["ic:io"].exposed=["key"];physical.update_state(nested_state)
 check(physical.io_views.has("board/outer/key"),"Exposed nested ID must match backend instance path")
 nested.definitions["ic:io"].exposed=[];nested.definitions["ic:io"].package="PCB";physical.update_state(nested_state)
 check(physical.io_views.has("board/outer/key"),"PCB must expose its installed IO irrespective of IC exposed list")
 # Modal disable and carrying remove hit zones and reject new presses.
 physical.set_io_interact(false)
 check(physical.io_views["board/outer/key"].collider.collision_layer==0,"Modal exit must disable input collision")
 check(not physical.io_pointer("board/outer/key",physical.io_views["board/outer/key"].view.global_position,true),"Modal input must not submit commands")
 physical.set_io_interact(true)
 nested_state.board_held=true;nested_state.board_owner=1;physical.update_state(nested_state)
 check(physical.io_views["board/outer/key"].collider.collision_layer==0,"Carried board must not retain clickable IO zones")
 nested_state.board_held=false;physical.update_state(nested_state)
 # Render the host-published direct IO fixture.
 board.io_controls["board/key"]=accepted.state;physical.update_state(state)
 if DisplayServer.get_name()!="headless":
  var camera=Camera3D.new();root.add_child(camera);camera.position=physical.global_position+Vector3(0,.9,.55);camera.look_at(physical.global_position+Vector3(-.2,0,0),Vector3.UP);camera.make_current()
  for i in 4:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://../../outputs/io-mount-v2-review.png")
 owner.queue_free();await process_frame
 if not failed:print("PASS: optional IO mounting, solved output, stable IDs, world UV, revision rejection/release queue, stow retirement, nested eligibility and rendered inspection")
 quit(1 if failed else 0)

